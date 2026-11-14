import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import '../../core/utils/noctra_logger.dart';

// Native C function typedefs
typedef _NoctraRustInitC = Int32 Function();
typedef _NoctraRustInitDart = int Function();
typedef _NoctraDecryptC = Pointer<Utf8> Function(Pointer<Utf8> encrypted);
typedef _NoctraDecryptDart = Pointer<Utf8> Function(Pointer<Utf8> encrypted);
typedef _NoctraFreeStringC = Void Function(Pointer<Utf8> str);
typedef _NoctraFreeStringDart = void Function(Pointer<Utf8> str);
typedef _NoctraVectorizeC = Int32 Function(Pointer<Utf8> text, Pointer<Double> outVector);
typedef _NoctraVectorizeDart = int Function(Pointer<Utf8> text, Pointer<Double> outVector);
typedef _NoctraCosineSimC = Double Function(Pointer<Double> v1, Pointer<Double> v2);
typedef _NoctraCosineSimDart = double Function(Pointer<Double> v1, Pointer<Double> v2);
typedef _NoctraUpscaleC = Int32 Function(
    Pointer<Double> samples, IntPtr len, Uint16 channels, Uint32 sampleRate, Double strength);
typedef _NoctraUpscaleDart = int Function(
    Pointer<Double> samples, int len, int channels, int sampleRate, double strength);
typedef _NoctraStemsToDirC = Int32 Function(
    Pointer<Int16> pcm, IntPtr len, Uint32 sampleRate, Uint16 channels, Uint8 model, Pointer<Utf8> outDir);
typedef _NoctraStemsToDirDart = int Function(
    Pointer<Int16> pcm, int len, int sampleRate, int channels, int model, Pointer<Utf8> outDir);
typedef _NoctraWriteWavC = Int32 Function(
    Pointer<Utf8> path, Pointer<Int16> samples, IntPtr len, Uint32 sampleRate, Uint16 channels);
typedef _NoctraWriteWavDart = int Function(
    Pointer<Utf8> path, Pointer<Int16> samples, int len, int sampleRate, int channels);
typedef _NoctraRomanizeC = Pointer<Utf8> Function(Pointer<Utf8> text);
typedef _NoctraRomanizeDart = Pointer<Utf8> Function(Pointer<Utf8> text);
typedef _NoctraDetectScriptC = Pointer<Utf8> Function(Pointer<Utf8> text);
typedef _NoctraDetectScriptDart = Pointer<Utf8> Function(Pointer<Utf8> text);
typedef _NoctraScoreCandidateC = Double Function(
    Pointer<Utf8> query, Pointer<Utf8> title, Pointer<Utf8> artist);
typedef _NoctraScoreCandidateDart = double Function(
    Pointer<Utf8> query, Pointer<Utf8> title, Pointer<Utf8> artist);

/// Zero-copy, in-memory bridge to the native Rust engine (noctra_core).
class NoctraRustBridge {
  static final NoctraRustBridge instance = NoctraRustBridge._();
  NoctraRustBridge._() {
    _initLibrary();
  }

  DynamicLibrary? _lib;
  bool _isAvailable = false;
  _NoctraDecryptDart? _decryptFn;
  _NoctraFreeStringDart? _freeStringFn;
  _NoctraVectorizeDart? _vectorizeFn;
  _NoctraCosineSimDart? _cosineSimFn;
  _NoctraUpscaleDart? _upscaleFn;
  _NoctraStemsToDirDart? _separateStemsToDirFn;
  _NoctraWriteWavDart? _writeWavFn;
  _NoctraRomanizeDart? _romanizeFn;
  _NoctraDetectScriptDart? _detectScriptFn;
  _NoctraScoreCandidateDart? _scoreCandidateFn;

  bool get isAvailable => _isAvailable;

  void _initLibrary() {
    try {
      if (Platform.isWindows) {
        for (final p in ['noctra_core.dll', 'rust/noctra_core/target/release/noctra_core.dll']) {
          if (File(p).existsSync()) {
            _lib = DynamicLibrary.open(p);
            break;
          }
        }
        _lib ??= DynamicLibrary.open('noctra_core.dll');
      } else if (Platform.isAndroid || Platform.isLinux) {
        _lib = DynamicLibrary.open('libnoctra_core.so');
      } else if (Platform.isMacOS || Platform.isIOS) {
        _lib = DynamicLibrary.process();
      }

      if (_lib != null) {
        final initFn = _lib!.lookup<NativeFunction<_NoctraRustInitC>>('noctra_rust_init').asFunction<_NoctraRustInitDart>();
        if (initFn() == 1) {
          _bindFunctions();
          _isAvailable = true;
          NoctraLogger.i('Noctra Native Rust Core loaded successfully via FFI');
        }
      }
    } catch (e) {
      NoctraLogger.d('Rust FFI library not available, fallback to Dart: $e');
      _isAvailable = false;
    }
  }

  void _bindFunctions() {
    final lib = _lib!;
    _decryptFn = lib.lookup<NativeFunction<_NoctraDecryptC>>('noctra_decrypt_jiosaavn').asFunction<_NoctraDecryptDart>();
    _freeStringFn = lib.lookup<NativeFunction<_NoctraFreeStringC>>('noctra_free_string').asFunction<_NoctraFreeStringDart>();
    _vectorizeFn = lib.lookup<NativeFunction<_NoctraVectorizeC>>('noctra_vectorize_16axis').asFunction<_NoctraVectorizeDart>();
    _cosineSimFn = lib.lookup<NativeFunction<_NoctraCosineSimC>>('noctra_cosine_similarity').asFunction<_NoctraCosineSimDart>();
    _upscaleFn = lib.lookup<NativeFunction<_NoctraUpscaleC>>('noctra_upscale_samples').asFunction<_NoctraUpscaleDart>();
    _separateStemsToDirFn = lib.lookup<NativeFunction<_NoctraStemsToDirC>>('noctra_separate_stems_to_dir').asFunction<_NoctraStemsToDirDart>();
    _writeWavFn = lib.lookup<NativeFunction<_NoctraWriteWavC>>('noctra_write_wav_file').asFunction<_NoctraWriteWavDart>();
    _romanizeFn = lib.lookup<NativeFunction<_NoctraRomanizeC>>('noctra_romanize_text').asFunction<_NoctraRomanizeDart>();
    _detectScriptFn = lib.lookup<NativeFunction<_NoctraDetectScriptC>>('noctra_detect_script').asFunction<_NoctraDetectScriptDart>();
    _scoreCandidateFn = lib.lookup<NativeFunction<_NoctraScoreCandidateC>>('noctra_score_candidate').asFunction<_NoctraScoreCandidateDart>();
  }

  /// Decrypts a JioSaavn encrypted media URL in pure native Rust.
  String? decryptJioSaavn(String encryptedUrl) {
    if (!_isAvailable || _decryptFn == null || _freeStringFn == null) return null;
    final cEncrypted = encryptedUrl.toNativeUtf8();
    try {
      final resPtr = _decryptFn!(cEncrypted);
      if (resPtr == nullptr) return null;
      try {
        return resPtr.toDartString();
      } finally {
        _freeStringFn!(resPtr);
      }
    } catch (e) {
      NoctraLogger.w('Rust FFI decryption failed: $e');
      return null;
    } finally {
      malloc.free(cEncrypted);
    }
  }

  /// Generates the 16-axis neural coordinate vector for text in pure native Rust.
  List<double>? vectorize16Axis(String text) {
    if (!_isAvailable || _vectorizeFn == null) return null;
    final cText = text.toNativeUtf8();
    final outPtr = malloc<Double>(16);
    try {
      final status = _vectorizeFn!(cText, outPtr);
      if (status != 0) return null;
      return List<double>.generate(16, (i) => outPtr[i]);
    } catch (e) {
      NoctraLogger.w('Rust FFI vectorize failed: $e');
      return null;
    } finally {
      malloc.free(cText);
      malloc.free(outPtr);
    }
  }

  /// Computes cosine similarity between two 16-axis vectors in pure native Rust.
  double? cosineSimilarity(List<double> v1, List<double> v2) {
    if (!_isAvailable || _cosineSimFn == null || v1.length < 16 || v2.length < 16) return null;
    final ptr1 = malloc<Double>(16);
    final ptr2 = malloc<Double>(16);
    try {
      for (int i = 0; i < 16; i++) {
        ptr1[i] = v1[i];
        ptr2[i] = v2[i];
      }
      return _cosineSimFn!(ptr1, ptr2);
    } catch (e) {
      NoctraLogger.w('Rust FFI cosine similarity failed: $e');
      return null;
    } finally {
      malloc.free(ptr1);
      malloc.free(ptr2);
    }
  }

  /// Upscales PCM float samples in-place using native Rust SIMD DSP.
  bool upscaleSamplesInPlace(Float64List pcmSamples, int channels, int sampleRate, double strength) {
    if (!_isAvailable || _upscaleFn == null || pcmSamples.isEmpty) return false;
    final len = pcmSamples.length;
    final ptr = malloc<Double>(len);
    try {
      final view = ptr.asTypedList(len);
      view.setAll(0, pcmSamples);
      final status = _upscaleFn!(ptr, len, channels, sampleRate, strength);
      if (status == 0) {
        pcmSamples.setAll(0, view);
        return true;
      }
      return false;
    } catch (e) {
      NoctraLogger.w('Rust FFI sample upscaling failed: $e');
      return false;
    } finally {
      malloc.free(ptr);
    }
  }

  /// Separates 16-bit PCM audio samples directly into 4 WAV files in [outputDir].
  bool separateStemsToDirectory(Int16List pcm, int sampleRate, int channels, String outputDir, {String model = 'light'}) {
    if (!_isAvailable || _separateStemsToDirFn == null || pcm.isEmpty) return false;
    final len = pcm.length;
    final modelCode = model == 'hq' ? 1 : (model == 'karaoke' ? 2 : 0);
    final pcmPtr = malloc<Int16>(len);
    final outDirPtr = outputDir.toNativeUtf8();
    try {
      pcmPtr.asTypedList(len).setAll(0, pcm);
      return _separateStemsToDirFn!(pcmPtr, len, sampleRate, channels, modelCode, outDirPtr) == 0;
    } catch (e) {
      NoctraLogger.w('Rust FFI stem separation failed: $e');
      return false;
    } finally {
      malloc.free(pcmPtr);
      malloc.free(outDirPtr);
    }
  }

  /// Writes a 16-bit PCM WAV file via native Rust.
  bool writeWavFile(String path, Int16List samples, int sampleRate, int channels) {
    if (!_isAvailable || _writeWavFn == null || samples.isEmpty) return false;
    final len = samples.length;
    final pathPtr = path.toNativeUtf8();
    final samplesPtr = malloc<Int16>(len);
    try {
      samplesPtr.asTypedList(len).setAll(0, samples);
      return _writeWavFn!(pathPtr, samplesPtr, len, sampleRate, channels) == 0;
    } catch (e) {
      NoctraLogger.w('Rust FFI WAV write failed: $e');
      return false;
    } finally {
      malloc.free(pathPtr);
      malloc.free(samplesPtr);
    }
  }

  /// Transliterates multi-script lyrics (Hangul, Cyrillic, Kana, Devanagari) in native Rust.
  String? romanizeText(String text) {
    if (!_isAvailable || _romanizeFn == null || _freeStringFn == null || text.isEmpty) return null;
    final cText = text.toNativeUtf8();
    try {
      final resPtr = _romanizeFn!(cText);
      if (resPtr == nullptr) return null;
      try {
        return resPtr.toDartString();
      } finally {
        _freeStringFn!(resPtr);
      }
    } catch (e) {
      NoctraLogger.w('Rust FFI romanizeText failed: $e');
      return null;
    } finally {
      malloc.free(cText);
    }
  }

  /// Detects predominant script of text (e.g. "korean", "japanese", "cyrillic", "devanagari", "latin").
  String detectScript(String text) {
    if (!_isAvailable || _detectScriptFn == null || text.isEmpty) return 'other';
    final cText = text.toNativeUtf8();
    try {
      final resPtr = _detectScriptFn!(cText);
      if (resPtr == nullptr) return 'other';
      return resPtr.toDartString();
    } catch (e) {
      return 'other';
    } finally {
      malloc.free(cText);
    }
  }

  /// Computes fuzzy search candidate relevance score in [0.0, 1.0] using native Rust.
  double scoreCandidate(String query, String title, String artist) {
    if (!_isAvailable || _scoreCandidateFn == null) return -1.0;
    final cQuery = query.toNativeUtf8();
    final cTitle = title.toNativeUtf8();
    final cArtist = artist.toNativeUtf8();
    try {
      return _scoreCandidateFn!(cQuery, cTitle, cArtist);
    } catch (e) {
      return -1.0;
    } finally {
      malloc.free(cQuery);
      malloc.free(cTitle);
      malloc.free(cArtist);
    }
  }
}
