import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctra/services/rust/noctra_rust_bridge.dart';

void main() {
  group('NoctraRustBridge FFI Tests', () {
    final bridge = NoctraRustBridge.instance;

    test('verifies native Rust core library is loaded', () {
      expect(bridge.isAvailable, isTrue,
          reason: 'noctra_core.dll must be loaded via FFI');
    });

    test('decrypts JioSaavn DES token in native Rust', () {
      if (!bridge.isAvailable) return;
      expect(bridge.decryptJioSaavn(''), isNull);
      expect(bridge.decryptJioSaavn('invalid-token!'), isNull);
    });

    test('generates 16-axis vector in native Rust', () {
      if (!bridge.isAvailable) return;
      final vec = bridge.vectorize16Axis('Late Night Synthwave Drive with deep bass');
      expect(vec, isNotNull);
      expect(vec!.length, equals(16));
      for (final val in vec) {
        expect(val, inInclusiveRange(0.0, 1.0));
      }
      expect(vec[10], greaterThan(0.6));
      expect(vec[9], greaterThan(0.6));
    });

    test('computes cosine similarity in native Rust', () {
      if (!bridge.isAvailable) return;
      final v1 = List<double>.filled(16, 1.0);
      final v2 = List<double>.filled(16, 1.0);
      final sim = bridge.cosineSimilarity(v1, v2);
      expect(sim, isNotNull);
      expect(sim!, closeTo(1.0, 1e-4));

      final v3 = List<double>.filled(16, 0.0)..[0] = 1.0;
      final v4 = List<double>.filled(16, 0.0)..[1] = 1.0;
      final simOrtho = bridge.cosineSimilarity(v3, v4);
      expect(simOrtho, isNotNull);
      expect(simOrtho!, closeTo(0.0, 1e-4));
    });

    test('upscales stereo PCM samples in-place in native Rust', () {
      if (!bridge.isAvailable) return;
      final pcm = Float64List.fromList([0.1, -0.1, 0.2, -0.2, 0.3, -0.3]);
      final ok = bridge.upscaleSamplesInPlace(pcm, 2, 44100, 0.6);
      expect(ok, isTrue);
      for (final s in pcm) {
        expect(s.abs(), lessThanOrEqualTo(1.0));
      }
    });

    test('writes 16-bit PCM WAV file via native Rust', () {
      if (!bridge.isAvailable) return;
      final samples = Int16List.fromList(List.generate(2048, (i) => (i * 10).clamp(-32768, 32767)));
      final tempFile = File('${Directory.systemTemp.path}/test_rust_wav_${DateTime.now().millisecondsSinceEpoch}.wav');
      try {
        final ok = bridge.writeWavFile(tempFile.path, samples, 44100, 1);
        expect(ok, isTrue);
        expect(tempFile.existsSync(), isTrue);
        expect(tempFile.lengthSync(), equals(44 + 2048 * 2));
      } finally {
        if (tempFile.existsSync()) tempFile.deleteSync();
      }
    });

    test('separates audio into 4 stems via native Rust FFT engine', () {
      if (!bridge.isAvailable) return;
      final samples = Int16List.fromList(List.generate(4096, (i) => ((i % 100) * 100).clamp(-32768, 32767)));
      final tempDir = Directory('${Directory.systemTemp.path}/test_stems_${DateTime.now().millisecondsSinceEpoch}');
      tempDir.createSync(recursive: true);
      try {
        final ok = bridge.separateStemsToDirectory(samples, 44100, 1, tempDir.path);
        expect(ok, isTrue);
        expect(File('${tempDir.path}/vocals.wav').existsSync(), isTrue);
        expect(File('${tempDir.path}/drums.wav').existsSync(), isTrue);
        expect(File('${tempDir.path}/bass.wav').existsSync(), isTrue);
        expect(File('${tempDir.path}/other.wav').existsSync(), isTrue);
      } finally {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    });

    test('romanizes multi-script text in native Rust', () {
      if (!bridge.isAvailable) return;
      // Korean Hangul
      expect(bridge.romanizeText('안녕하세요'), equals('annyeonghaseyo'));
      // Russian Cyrillic
      expect(bridge.romanizeText('Привет'), equals('Privet'));
      // Ukrainian Cyrillic
      expect(bridge.romanizeText('Київ'), equals('Kyyiv'));
      // Japanese Kana
      expect(bridge.romanizeText('ありがとう'), equals('arigatou'));
      // Devanagari
      expect(bridge.romanizeText('नमस्ते'), equals('namaste'));
    });

    test('detects script in native Rust', () {
      if (!bridge.isAvailable) return;
      expect(bridge.detectScript('사랑해요'), equals('korean'));
      expect(bridge.detectScript('こんにちは'), equals('japanese'));
      expect(bridge.detectScript('Привет'), equals('cyrillic'));
      expect(bridge.detectScript('नमस्ते'), equals('devanagari'));
      expect(bridge.detectScript('Hello World'), equals('latin'));
    });

    test('scores search candidates with fuzzy matching in native Rust', () {
      if (!bridge.isAvailable) return;
      final scoreExact = bridge.scoreCandidate('Blinding Lights', 'Blinding Lights', 'The Weeknd');
      expect(scoreExact, equals(1.0));

      final scoreNatural = bridge.scoreCandidate('Starboy by The Weeknd', 'Starboy', 'The Weeknd');
      expect(scoreNatural, greaterThanOrEqualTo(0.95));

      final scoreRemix = bridge.scoreCandidate('Starboy by The Weeknd', 'Starboy (Remix)', 'The Weeknd');
      expect(scoreRemix, lessThan(scoreNatural));
    });
  });
}
