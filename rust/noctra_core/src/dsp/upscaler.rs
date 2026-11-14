//! 24-bit Audio Upscaling Engine with SIMD-ready architecture.
//!
//! Restores perceived brightness and harmonic air lost to lossy compression (MP3/AAC):
//! 1. Quadratic soft-saturation exciter.
//! 2. Dynamic band extension with fast/slow envelope tracking.
//! 3. Hyperbolic tangent soft peak limiting.
//! 4. Lossless 24-bit PCM WAV rendering.

use std::fs::File;
use std::io::{BufWriter, Write};
use std::path::Path;

use super::biquad::Biquad;

#[derive(Debug, Clone)]
pub struct UpscaleResult {
    pub path: String,
    pub sample_rate: u32,
    pub channels: u16,
    pub bit_depth: u16,
    pub input_samples: usize,
    pub output_samples: usize,
}

struct ChannelDsp {
    exc_hp: Biquad,
    exc_lp: Biquad,
    air: Biquad,
    env_coef_fast: f64,
    env_coef_slow: f64,
    fast_env: f64,
    slow_env: f64,
}

impl ChannelDsp {
    fn new(sample_rate: f64, strength: f64) -> Self {
        let sr = sample_rate;
        let exc_hp = Biquad::high_pass((2500.0f64).min(sr * 0.45), sr);
        let exc_lp = Biquad::low_pass((8000.0f64).min(sr * 0.45), sr);
        let air = Biquad::high_shelf(
            (9000.0f64).min(sr * 0.45),
            sr,
            4.0 + 4.0 * strength,
        );
        let env_coef_fast = (-1.0 / (0.003 * sr)).exp();
        let env_coef_slow = (-1.0 / (0.400 * sr)).exp();

        Self {
            exc_hp,
            exc_lp,
            air,
            env_coef_fast,
            env_coef_slow,
            fast_env: 0.0,
            slow_env: 0.0,
        }
    }

    #[inline(always)]
    fn process(&mut self, x: f64, drive: f64, harmonic_mix: f64, air_mix: f64) -> f64 {
        let hp_out = self.exc_hp.process(x);
        let band = self.exc_lp.process(hp_out);

        let sat = UpscaleDspEngine::soft_sat(band * drive) / UpscaleDspEngine::soft_sat(drive);
        let mut y = x + sat * harmonic_mix;

        let a = band.abs();
        self.fast_env = self.env_coef_fast * self.fast_env + (1.0 - self.env_coef_fast) * a;
        self.slow_env = self.env_coef_slow * self.slow_env + (1.0 - self.env_coef_slow) * a;
        let lift = (self.fast_env - self.slow_env).clamp(0.0, 1.0);

        let shaped = self.air.process(y);
        y += (shaped - y) * (air_mix * (0.5 + 0.5 * lift));

        UpscaleDspEngine::limit(y)
    }
}

pub struct UpscaleDspEngine;

impl UpscaleDspEngine {
    #[inline(always)]
    pub fn soft_sat(x: f64) -> f64 {
        let k = 1.5;
        (x * (1.0 + k)) / (1.0 + k * x.abs())
    }

    #[inline(always)]
    pub fn limit(x: f64) -> f64 {
        if x.abs() < 0.7 {
            return x;
        }
        let sign = if x < 0.0 { -1.0 } else { 1.0 };
        let a = x.abs();
        let t = (a - 0.7) / (1.0 - 0.7);
        let e = (2.0 * t).exp();
        let th = (e - 1.0) / (e + 1.0);
        sign * (0.7 + (1.0 - 0.7) * th)
    }

    /// Enhances raw float PCM samples in-place or returns an enhanced buffer.
    pub fn enhance_samples(
        pcm: &[f64],
        channels: u16,
        sample_rate: u32,
        strength: f64,
    ) -> Vec<f64> {
        let len = pcm.len();
        let mut out = vec![0.0f64; len];
        let drive = 1.0 + 2.0 * strength;
        let harmonic_mix = 0.18 + 0.30 * strength;
        let air_mix = 0.35 + 0.45 * strength;

        let sr = sample_rate as f64;
        let mut dsp0 = ChannelDsp::new(sr, strength);

        if channels == 2 {
            let mut dsp1 = ChannelDsp::new(sr, strength);
            for i in (0..len).step_by(2) {
                if i + 1 < len {
                    out[i] = dsp0.process(pcm[i], drive, harmonic_mix, air_mix);
                    out[i + 1] = dsp1.process(pcm[i + 1], drive, harmonic_mix, air_mix);
                }
            }
        } else {
            for i in 0..len {
                out[i] = dsp0.process(pcm[i], drive, harmonic_mix, air_mix);
            }
        }

        out
    }

    /// Enhances audio and writes a true 24-bit PCM RIFF WAVE file.
    pub fn process_to_wav24(
        pcm_16bit: &[i16],
        channels: u16,
        sample_rate: u32,
        strength: f64,
        output_path: &Path,
    ) -> Result<UpscaleResult, std::io::Error> {
        let float_samples: Vec<f64> = pcm_16bit.iter().map(|&s| (s as f64) / 32768.0).collect();
        let enhanced = Self::enhance_samples(&float_samples, channels, sample_rate, strength);

        let file = File::create(output_path)?;
        let mut writer = BufWriter::new(file);

        // RIFF WAVE header for 24-bit PCM
        let bytes_per_sample = 3usize;
        let data_len = (enhanced.len() * bytes_per_sample) as u32;

        writer.write_all(b"RIFF")?;
        writer.write_all(&(36 + data_len).to_le_bytes())?;
        writer.write_all(b"WAVEfmt ")?;
        writer.write_all(&16u32.to_le_bytes())?; // Subchunk1Size
        writer.write_all(&1u16.to_le_bytes())?; // AudioFormat = PCM
        writer.write_all(&channels.to_le_bytes())?;
        writer.write_all(&sample_rate.to_le_bytes())?;
        let byte_rate = sample_rate * (channels as u32) * (bytes_per_sample as u32);
        writer.write_all(&byte_rate.to_le_bytes())?;
        let block_align = channels * (bytes_per_sample as u16);
        writer.write_all(&block_align.to_le_bytes())?;
        writer.write_all(&24u16.to_le_bytes())?; // BitsPerSample = 24
        writer.write_all(b"data")?;
        writer.write_all(&data_len.to_le_bytes())?;

        // 24-bit sample serialization
        let mut buf = [0u8; 3];
        for &sample in &enhanced {
            let clamped = (sample * 8388607.0).clamp(-8388608.0, 8388607.0).round() as i32;
            buf[0] = (clamped & 0xFF) as u8;
            buf[1] = ((clamped >> 8) & 0xFF) as u8;
            buf[2] = ((clamped >> 16) & 0xFF) as u8;
            writer.write_all(&buf)?;
        }

        writer.flush()?;

        Ok(UpscaleResult {
            path: output_path.to_string_lossy().to_string(),
            sample_rate,
            channels,
            bit_depth: 24,
            input_samples: pcm_16bit.len(),
            output_samples: enhanced.len(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_soft_sat_produces_smooth_harmonics() {
        assert_eq!(UpscaleDspEngine::soft_sat(0.0), 0.0);
        let sat_half = UpscaleDspEngine::soft_sat(0.5);
        assert!(sat_half > 0.5);
        let sat_one = UpscaleDspEngine::soft_sat(1.0);
        assert_eq!(sat_one, 1.0);
    }

    #[test]
    fn test_limiter_never_exceeds_unity() {
        for val in [-5.0, -2.0, -1.0, -0.5, 0.0, 0.5, 1.0, 2.0, 5.0] {
            let lim = UpscaleDspEngine::limit(val);
            assert!(lim.abs() <= 1.0, "Limiter output exceeded 1.0: {}", lim);
        }
    }

    #[test]
    fn test_enhance_stereo_pcm_samples() {
        let stereo_samples = vec![0.1, -0.1, 0.2, -0.2, 0.3, -0.3];
        let enhanced = UpscaleDspEngine::enhance_samples(&stereo_samples, 2, 44100, 0.6);
        assert_eq!(enhanced.len(), stereo_samples.len());
        for &s in &enhanced {
            assert!(s.abs() <= 1.0);
        }
    }
}
