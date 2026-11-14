//! Minimal Biquad Filter implementation (Robert Bristow-Johnson Audio EQ Cookbook)
//! for high-pass, low-pass, and high-shelf dynamic frequency shaping.

use std::f64::consts::PI;

#[derive(Debug, Clone)]
pub struct Biquad {
    b0: f64,
    b1: f64,
    b2: f64,
    a1: f64,
    a2: f64,
    x1: f64,
    x2: f64,
    y1: f64,
    y2: f64,
}

impl Biquad {
    pub fn low_pass(f0: f64, sample_rate: f64) -> Self {
        Self::design(f0, sample_rate, 0.707, "lp")
    }

    pub fn high_pass(f0: f64, sample_rate: f64) -> Self {
        Self::design(f0, sample_rate, 0.707, "hp")
    }

    pub fn high_shelf(f0: f64, sample_rate: f64, gain_db: f64) -> Self {
        let w0 = 2.0 * PI * f0 / sample_rate;
        let cw = w0.cos();
        let sw = w0.sin();
        let a = 10.0f64.powf(gain_db / 40.0);
        let sq = 2.0 * a.sqrt() * 0.707 * sw;
        let a0 = (a + 1.0) - (a - 1.0) * cw + sq;

        let b0 = (a * ((a + 1.0) + (a - 1.0) * cw + sq)) / a0;
        let b1 = (-2.0 * a * ((a - 1.0) + (a + 1.0) * cw)) / a0;
        let b2 = (a * ((a + 1.0) + (a - 1.0) * cw - sq)) / a0;
        let a1 = (2.0 * ((a - 1.0) - (a + 1.0) * cw)) / a0;
        let a2 = ((a + 1.0) - (a - 1.0) * cw - sq) / a0;

        Self {
            b0,
            b1,
            b2,
            a1,
            a2,
            x1: 0.0,
            x2: 0.0,
            y1: 0.0,
            y2: 0.0,
        }
    }

    fn design(f0: f64, sample_rate: f64, q: f64, filter_type: &str) -> Self {
        let w0 = 2.0 * PI * f0 / sample_rate;
        let cw = w0.cos();
        let sw = w0.sin();
        let alpha = sw / (2.0 * q);

        let (b0, b1, b2) = if filter_type == "lp" {
            ((1.0 - cw) / 2.0, 1.0 - cw, (1.0 - cw) / 2.0)
        } else {
            ((1.0 + cw) / 2.0, -(1.0 + cw), (1.0 + cw) / 2.0)
        };

        let a0 = 1.0 + alpha;
        let a1 = -2.0 * cw;
        let a2 = 1.0 - alpha;

        Self {
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0,
            x1: 0.0,
            x2: 0.0,
            y1: 0.0,
            y2: 0.0,
        }
    }

    #[inline(always)]
    pub fn process(&mut self, x: f64) -> f64 {
        let y = self.b0 * x + self.b1 * self.x1 + self.b2 * self.x2 - self.a1 * self.y1 - self.a2 * self.y2;
        self.x2 = self.x1;
        self.x1 = x;
        self.y2 = self.y1;
        self.y1 = y;
        y
    }
}
