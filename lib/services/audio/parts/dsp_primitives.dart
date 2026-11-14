import 'dart:math';
import 'dart:typed_data';

/// Shared value types + biquad filter for the pure-Dart DSP engines.

class ExtractedPcm {
  final Int16List pcm;
  final int sampleRate;
  final int channels;

  ExtractedPcm({
    required this.pcm,
    required this.sampleRate,
    required this.channels,
  });
}

class BiquadFilter {
  double a0 = 1.0, a1 = 0.0, a2 = 0.0, b0 = 1.0, b1 = 0.0, b2 = 0.0;
  double x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;

  BiquadFilter();

  factory BiquadFilter.lowPass(double cutoff, double sampleRate) {
    final f = BiquadFilter();
    final w0 = 2 * pi * (cutoff / sampleRate);
    final cosW0 = cos(w0);
    final alpha = sin(w0) / (2 * 0.7071);

    f.b0 = (1 - cosW0) / 2;
    f.b1 = 1 - cosW0;
    f.b2 = (1 - cosW0) / 2;
    f.a0 = 1 + alpha;
    f.a1 = -2 * cosW0;
    f.a2 = 1 - alpha;
    return f;
  }

  factory BiquadFilter.highPass(double cutoff, double sampleRate) {
    final f = BiquadFilter();
    final w0 = 2 * pi * (cutoff / sampleRate);
    final cosW0 = cos(w0);
    final alpha = sin(w0) / (2 * 0.7071);

    f.b0 = (1 + cosW0) / 2;
    f.b1 = -(1 + cosW0);
    f.b2 = (1 + cosW0) / 2;
    f.a0 = 1 + alpha;
    f.a1 = -2 * cosW0;
    f.a2 = 1 - alpha;
    return f;
  }

  factory BiquadFilter.bandPass(double centerFreq, double bandwidth, double sampleRate) {
    final f = BiquadFilter();
    final w0 = 2 * pi * (centerFreq / sampleRate);
    final q = centerFreq / max(10.0, bandwidth);
    final alpha = sin(w0) / (2 * max(0.1, q));

    f.b0 = alpha;
    f.b1 = 0;
    f.b2 = -alpha;
    f.a0 = 1 + alpha;
    f.a1 = -2 * cos(w0);
    f.a2 = 1 - alpha;
    return f;
  }

  double process(double input) {
    final y = (b0 / a0) * input + (b1 / a0) * x1 + (b2 / a0) * x2 - (a1 / a0) * y1 - (a2 / a0) * y2;
    x2 = x1;
    x1 = input;
    y2 = y1;
    y1 = y;
    return y;
  }
}
