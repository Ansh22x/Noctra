import { useState, useEffect } from 'react';
import {
  Download,
  Shield,
  Sparkles,
  Sliders,
  Mic2,
  Cpu,
  Radio,
  ArrowRight,
  Terminal,
  Volume2,
  CheckCircle2,
} from 'lucide-react';
import { useRelease } from '../context/ReleaseContext';
import { detectUserPlatform } from '../utils/detectPlatform';
import type { PlatformType } from '../types';
import { ShowcaseGallery } from '../components/ShowcaseGallery/ShowcaseGallery';
import { Link } from '../router/Router';
import styles from './HomePage.module.css';

interface SoundPreset {
  id: string;
  name: string;
  tag: string;
  desc: string;
  bars: number[];
}

const SOUND_PRESETS: SoundPreset[] = [
  {
    id: 'studio',
    name: 'Studio Master FLAC',
    tag: '24-BIT / 192kHz',
    desc: 'Bit-perfect linear frequency response with air-band headroom up to 48kHz.',
    bars: [45, 55, 62, 70, 75, 80, 82, 85, 88, 90, 86, 82, 78, 75, 72, 70],
  },
  {
    id: 'karaoke',
    name: 'Vocal Isolation',
    tag: 'RADIX-2 FFT STEMS',
    desc: 'Rust Core real-time phase cancellation isolates mid-band center vocal frequencies.',
    bars: [15, 20, 25, 30, 45, 92, 98, 96, 94, 90, 40, 25, 20, 15, 12, 10],
  },
  {
    id: 'harman',
    name: 'Harman 2019 Target',
    tag: 'AUDIOPHILE IEM CURVE',
    desc: 'Sub-bass boost (+6dB below 100Hz) with natural acoustic ear-gain pinna rise.',
    bars: [95, 92, 86, 74, 60, 52, 56, 68, 80, 84, 76, 68, 62, 58, 55, 50],
  },
  {
    id: 'exciter',
    name: 'Harmonic Air Exciter',
    tag: 'ANALOG SATURATION',
    desc: 'Even/odd harmonic synthesis injecting tube-like acoustic warmth into lossy streams.',
    bars: [60, 65, 68, 70, 72, 75, 78, 82, 88, 94, 96, 98, 99, 95, 90, 85],
  },
];

export function HomePage() {
  const { release } = useRelease();
  const [os, setOs] = useState<PlatformType>('windows');
  const [activePreset, setActivePreset] = useState<SoundPreset>(SOUND_PRESETS[0]);

  useEffect(() => {
    setOs(detectUserPlatform());
  }, []);

  const currentBinary = release.binaries[os];
  const downloadUrl = currentBinary?.downloadUrl ?? release.releaseUrl;
  const osLabel = os.charAt(0).toUpperCase() + os.slice(1);

  return (
    <div className={styles.homeContainer}>
      {/* ─── BOLD CYBER-AUDIOPHILE HERO ─── */}
      <section className={styles.heroSection}>
        <div className={styles.heroBadgeWrapper}>
          <Link to="/changelog" className={styles.releasePill}>
            <span className={styles.pulseDot} />
            <span className={styles.releaseTag}>{release.tag} ACTIVE</span>
            <span className={styles.releaseDivider}>|</span>
            <span className={styles.releaseStatus}>BARE-METAL RUST CORE</span>
            <span className={styles.arrowIcon}>→</span>
          </Link>
        </div>

        <h1 className={styles.heroTitle}>
          SOVEREIGN ACOUSTICS.
          <br />
          <span className={styles.gradientTitle}>PURE UNTAMED SOUND.</span>
        </h1>

        <p className={styles.heroSubtitle}>
          The autonomous, zero-cloud music platform engineered for audiophiles. Bit-perfect
          Hi-Res FLAC up to <strong>24-bit/192kHz</strong>, bare-metal Rust stem separation,
          bilingual synced lyrics subtitles, and audiophile IEM target curves. Zero accounts,
          zero ads, zero tracking servers.
        </p>

        {/* Live Audio Visualizer Equalizer Strip */}
        <div className={styles.heroEqualizerStrip} aria-hidden="true">
          <div className={styles.equalizerGlow} />
          <div className={styles.equalizerBars}>
            {Array.from({ length: 32 }).map((_, i) => (
              <span
                key={i}
                className={styles.equalizerBar}
                style={{
                  animationDelay: `${(i * 0.045).toFixed(2)}s`,
                  animationDuration: `${(0.7 + (i % 7) * 0.12).toFixed(2)}s`,
                }}
              />
            ))}
          </div>
        </div>

        <div className={styles.ctaRow}>
          <a href={downloadUrl} className={styles.btnPrimary}>
            <Download size={19} />
            <span>Download for {osLabel}</span>
            <span className={styles.btnBadge}>{release.tag}</span>
          </a>

          <Link to="/download" className={styles.btnSecondary}>
            <span>All Platforms</span>
          </Link>

          <a
            href="https://github.com/Ansh22x/Noctra"
            target="_blank"
            rel="noopener noreferrer"
            className={styles.btnGhost}
          >
            <svg width="17" height="17" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
              <path d="M12 .5C5.65.5.5 5.65.5 12c0 5.08 3.29 9.39 7.86 10.91.58.11.79-.25.79-.55v-2.15c-3.2.7-3.87-1.36-3.87-1.36-.52-1.33-1.28-1.68-1.28-1.68-1.04-.71.08-.7.08-.7 1.15.08 1.76 1.18 1.76 1.18 1.03 1.76 2.69 1.25 3.35.96.1-.75.4-1.25.72-1.54-2.55-.29-5.23-1.28-5.23-5.68 0-1.26.45-2.28 1.18-3.09-.12-.29-.51-1.46.11-3.05 0 0 .96-.31 3.15 1.18a10.9 10.9 0 0 1 5.74 0c2.19-1.49 3.15-1.18 3.15-1.18.62 1.59.23 2.76.11 3.05.73.81 1.18 1.83 1.18 3.09 0 4.41-2.69 5.38-5.25 5.67.41.35.77 1.04.77 2.1v3.11c0 .3.21.67.8.55A11.51 11.51 0 0 0 23.5 12C23.5 5.65 18.35.5 12 .5Z" />
            </svg>
            <span>GitHub Star</span>
          </a>
        </div>

        {/* Studio Monitor Telemetry HUD */}
        <div className={styles.telemetryHud}>
          <div className={styles.telemetryItem}>
            <span className={styles.telemetryLabel}>ENGINE</span>
            <span className={styles.telemetryValue}>Rust FFI (0ms GC)</span>
          </div>
          <div className={styles.telemetryDivider} />
          <div className={styles.telemetryItem}>
            <span className={styles.telemetryLabel}>HEADROOM</span>
            <span className={styles.telemetryValue}>24-Bit / 192 kHz</span>
          </div>
          <div className={styles.telemetryDivider} />
          <div className={styles.telemetryItem}>
            <span className={styles.telemetryLabel}>SERVERLESS</span>
            <span className={styles.telemetryValue}>100% Standalone</span>
          </div>
          <div className={styles.telemetryDivider} />
          <div className={styles.telemetryItem}>
            <span className={styles.telemetryLabel}>SOVEREIGNTY</span>
            <span className={styles.telemetryValue}>Zero Telemetry</span>
          </div>
        </div>
      </section>

      {/* ─── REAL SCREENSHOT SHOWCASE ─── */}
      <ShowcaseGallery />

      {/* ─── INTERACTIVE SOUND STAGE DEMO ─── */}
      <section className={styles.soundStageSection}>
        <div className={styles.sectionHeader}>
          <span className={styles.sectionTag}>ACOUSTIC SIMULATION</span>
          <h2 className={styles.sectionTitle}>Interactive On-Device Sound Stages</h2>
          <p className={styles.sectionSubtitle}>
            Switch real-time DSP profiles to preview how Noctra's hardware exciter and target curves reshape the acoustic landscape.
          </p>
        </div>

        <div className={styles.soundStageCard}>
          <div className={styles.soundStageTabs}>
            {SOUND_PRESETS.map((preset) => (
              <button
                key={preset.id}
                type="button"
                className={`${styles.presetBtn} ${
                  activePreset.id === preset.id ? styles.presetBtnActive : ''
                }`}
                onClick={() => setActivePreset(preset)}
              >
                <span className={styles.presetName}>{preset.name}</span>
                <span className={styles.presetTag}>{preset.tag}</span>
              </button>
            ))}
          </div>

          <div className={styles.soundStageDisplay}>
            <div className={styles.displayHeader}>
              <div className={styles.displayInfo}>
                <span className={styles.displayBadge}>{activePreset.tag}</span>
                <h3 className={styles.displayTitle}>{activePreset.name}</h3>
                <p className={styles.displayDesc}>{activePreset.desc}</p>
              </div>
              <div className={styles.activePill}>
                <Volume2 size={15} />
                <span>ACTIVE DSP PASS</span>
              </div>
            </div>

            <div className={styles.spectrumVisualizer}>
              {activePreset.bars.map((height, idx) => (
                <div key={idx} className={styles.spectrumCol}>
                  <div
                    className={styles.spectrumBar}
                    style={{ height: `${height}%` }}
                  />
                  <span className={styles.spectrumFreq}>
                    {idx === 0
                      ? '32Hz'
                      : idx === 4
                      ? '250Hz'
                      : idx === 8
                      ? '2kHz'
                      : idx === 12
                      ? '8kHz'
                      : idx === 15
                      ? '20kHz'
                      : ''}
                  </span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* ─── HIGH-TECH BENTO GRID ─── */}
      <section className={styles.bentoSection}>
        <div className={styles.sectionHeader}>
          <span className={styles.sectionTag}>SYSTEM ARCHITECTURE</span>
          <h2 className={styles.sectionTitle}>Engineered Without Compromise</h2>
          <p className={styles.sectionSubtitle}>
            Every layer in Noctra is crafted for sovereign acoustic execution: zero cloud tracking, zero garbage collection pauses, and pure bit-perfect dynamics.
          </p>
        </div>

        <div className={styles.bentoGrid}>
          {/* Card 1: Rust Core (Large 2-column) */}
          <div className={`${styles.bentoCard} ${styles.bentoSpan2}`}>
            <div className={styles.bentoHeader}>
              <div className={styles.bentoIconWrapper}>
                <Cpu size={24} className={styles.bentoIcon} />
              </div>
              <span className={styles.bentoBadge}>BARE-METAL C-ABI</span>
            </div>
            <h3 className={styles.bentoTitle}>Native Embedded Rust Core (`noctra_core`)</h3>
            <p className={styles.bentoDesc}>
              Heavy digital signal processing runs inside compiled native Rust via zero-copy
              in-memory Dart FFI. Includes Cooley-Tukey Radix-2 FFT spectral stem separation
              (Vocals, Bass, Drums, Other) running 10x faster with zero JVM or Dart garbage
              collection stutter.
            </p>
            <div className={styles.codeSnippetBox}>
              <div className={styles.codeSnippetHeader}>
                <Terminal size={13} />
                <span>rust/noctra_core/src/dsp/stems.rs</span>
              </div>
              <pre className={styles.codePre}>
                <code>{`// Cooley-Tukey Radix-2 In-Place FFT with Bit-Reversal
let mut fft = FftStemSplitter::new(2048, 44100);
let stems = fft.separate_4stems(&stereo_pcm);
// Export isolated Vocals & Instrumental to 24-bit WAV`}</code>
              </pre>
            </div>
          </div>

          {/* Card 2: 24-Bit Upscaler */}
          <div className={styles.bentoCard}>
            <div className={styles.bentoHeader}>
              <div className={styles.bentoIconWrapper}>
                <Sparkles size={24} className={styles.bentoIcon} />
              </div>
              <span className={styles.bentoBadge}>STUDIO MASTER</span>
            </div>
            <h3 className={styles.bentoTitle}>On-Device 24-Bit Upscaler</h3>
            <p className={styles.bentoDesc}>
              Harmonic reconstruction, dynamic Nyquist bounds, and 24-bit headroom restoration
              export true uncompressed lossless WAVs directly on-device without cloud sidecars.
            </p>
            <div className={styles.pillList}>
              <span className={styles.miniPill}>High-Shelf Air Band</span>
              <span className={styles.miniPill}>Tanh Soft Saturation</span>
            </div>
          </div>

          {/* Card 3: Universal Synced Lyrics */}
          <div className={styles.bentoCard}>
            <div className={styles.bentoHeader}>
              <div className={styles.bentoIconWrapper}>
                <Mic2 size={24} className={styles.bentoIcon} />
              </div>
              <span className={styles.bentoBadge}>MULTI-SCRIPT</span>
            </div>
            <h3 className={styles.bentoTitle}>Universal Synced Subtitles</h3>
            <p className={styles.bentoDesc}>
              Apple Music-style dual synchronized lyrics with real-time translations. Offline
              Hangul Jamo decomposition, Kana Hepburn monographs, and Devanagari transliteration.
            </p>
            <div className={styles.pillList}>
              <span className={styles.miniPill}>Syllable Accents</span>
              <span className={styles.miniPill}>Sub-Millisecond Sync</span>
            </div>
          </div>

          {/* Card 4: Audiophile IEM Tuning */}
          <div className={styles.bentoCard}>
            <div className={styles.bentoHeader}>
              <div className={styles.bentoIconWrapper}>
                <Sliders size={24} className={styles.bentoIcon} />
              </div>
              <span className={styles.bentoBadge}>HARDWARE DSP</span>
            </div>
            <h3 className={styles.bentoTitle}>IEM Target Response Curves</h3>
            <p className={styles.bentoDesc}>
              5-band parametric equalizer tuned directly on Android 9+ DynamicsProcessor. Includes
              Harman 2019, Moondrop VDSF, and Tangzu Wan'er audiophile IEM targets.
            </p>
            <div className={styles.pillList}>
              <span className={styles.miniPill}>Harman Target</span>
              <span className={styles.miniPill}>Moondrop VDSF</span>
            </div>
          </div>

          {/* Card 5: Speaker Mesh (Large 2-column) */}
          <div className={`${styles.bentoCard} ${styles.bentoSpan2}`}>
            <div className={styles.bentoHeader}>
              <div className={styles.bentoIconWrapper}>
                <Radio size={24} className={styles.bentoIcon} />
              </div>
              <span className={styles.bentoBadge}>P2P WIRELESS</span>
            </div>
            <h3 className={styles.bentoTitle}>Speaker Mesh Acoustic P2P Synchronization</h3>
            <p className={styles.bentoDesc}>
              Turn every phone in the room into a synchronized surround-sound speaker array.
              Uses local NTP clock drift compensation, Wi-Fi Direct zero-router clustering,
              and low-latency acoustic packet synchronization. Zero internet required.
            </p>
            <div className={styles.meshPillsRow}>
              <div className={styles.meshPill}>
                <CheckCircle2 size={14} className={styles.meshCheck} />
                <span>Zero Router Dependency</span>
              </div>
              <div className={styles.meshPill}>
                <CheckCircle2 size={14} className={styles.meshCheck} />
                <span>Sub-5ms NTP Drift Compensation</span>
              </div>
              <div className={styles.meshPill}>
                <CheckCircle2 size={14} className={styles.meshCheck} />
                <span>Spatial Multi-Room Array</span>
              </div>
            </div>
          </div>

          {/* Card 6: Privacy Sovereignty */}
          <div className={`${styles.bentoCard} ${styles.bentoSpanFull}`}>
            <div className={styles.bentoHeader}>
              <div className={styles.bentoIconWrapper}>
                <Shield size={24} className={styles.bentoIcon} />
              </div>
              <span className={styles.bentoBadge}>AIR-GAPPED SOVEREIGNTY</span>
            </div>
            <div className={styles.sovereigntyContent}>
              <div>
                <h3 className={styles.bentoTitle}>Zero Cloud. Zero Accounts. Zero Telemetry.</h3>
                <p className={styles.bentoDesc}>
                  No email required, no passwords, no phone numbers, and no behavioral tracking.
                  Taste profiles are generated and indexed directly in local on-device SQLite databases.
                  The app is 100% standalone, serverless, and open source under GNU GPL-3.0.
                </p>
              </div>
              <div className={styles.sovereigntyCta}>
                <Link to="/architecture" className={styles.btnSecondary}>
                  <span>Inspect Architecture</span>
                  <ArrowRight size={15} />
                </Link>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ─── READY FOR PURE SOUND CTA CARD ─── */}
      <section className={styles.downloadCtaSection}>
        <div className={styles.ctaBox}>
          <div className={styles.ctaContent}>
            <span className={styles.ctaPill}>STANDALONE CLIENT · ZERO HOSTING</span>
            <h2 className={styles.ctaTitle}>Experience Pure Acoustic Sovereignty</h2>
            <p className={styles.ctaDesc}>
              Single-file standalone native installers compiled directly with cryptographic SHA-256
              integrity verification across Windows, Android, Linux, and iOS.
            </p>
            <div className={styles.ctaActions}>
              <Link to="/download" className={styles.btnPrimary}>
                <Download size={18} />
                <span>Downloads Center</span>
              </Link>
              <Link to="/features" className={styles.btnSecondary}>
                <span>Explore All Features</span>
              </Link>
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}
