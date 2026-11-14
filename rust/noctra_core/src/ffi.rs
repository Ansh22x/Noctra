//! C FFI Exports for in-memory Dart / Flutter zero-copy integration.
//!
//! Provides direct native access to:
//! - JioSaavn DES 320kbps URL decryption.
//! - 24-bit Audio DSP Upscaling (SIMD harmonic exciter, dynamic Nyquist, soft limiter).
//! - 16-Axis Neural Vector Generation and Cosine Similarity.
//! - On-device Audio Stem Separation (FFT / IFFT spectral band splitting).
//! - RIFF WAVE audio writer.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use crate::crypto::des::decrypt_jiosaavn_media_url;
use crate::dsp::stems::{separate_stems, separate_stems_to_directory, write_wav, StemModel};
use crate::dsp::upscaler::UpscaleDspEngine;
use crate::services::ai_rag::{cosine_similarity, generate_16axis_vector};
use crate::services::ranker::score_candidate;
use crate::services::romanizer::{detect_script, romanize_text};

/// Returns 1 to verify that the native Rust core library is initialized and functional.
#[no_mangle]
pub extern "C" fn noctra_rust_init() -> i32 {
    1
}

/// Decrypts a JioSaavn encrypted media token into a direct 320kbps stream URL.
///
/// Returns a heap-allocated C-string that MUST be freed using [noctra_free_string].
/// If decryption fails or input is null, returns null.
#[no_mangle]
pub extern "C" fn noctra_decrypt_jiosaavn(encrypted_ptr: *const c_char) -> *mut c_char {
    if encrypted_ptr.is_null() {
        return std::ptr::null_mut();
    }

    let c_str = unsafe { CStr::from_ptr(encrypted_ptr) };
    let Ok(encrypted_str) = c_str.to_str() else {
        return std::ptr::null_mut();
    };

    match decrypt_jiosaavn_media_url(encrypted_str) {
        Some(decrypted) => match CString::new(decrypted) {
            Ok(c_string) => c_string.into_raw(),
            Err(_) => std::ptr::null_mut(),
        },
        None => std::ptr::null_mut(),
    }
}

/// Frees a C-string allocated by Rust FFI.
#[no_mangle]
pub extern "C" fn noctra_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

/// Computes the 16-axis neural acoustic vector for the given text.
///
/// Writes 16 double values directly into `out_vector`.
/// Returns 0 on success, or -1 on invalid input.
#[no_mangle]
pub extern "C" fn noctra_vectorize_16axis(text_ptr: *const c_char, out_vector: *mut f64) -> i32 {
    if text_ptr.is_null() || out_vector.is_null() {
        return -1;
    }

    let c_str = unsafe { CStr::from_ptr(text_ptr) };
    let Ok(text) = c_str.to_str() else {
        return -1;
    };

    let vec = generate_16axis_vector(text);
    unsafe {
        std::ptr::copy_nonoverlapping(vec.as_ptr(), out_vector, 16);
    }

    0
}

/// Computes cosine similarity between two 16-dimensional vectors with [0.0, 1.0] span.
#[no_mangle]
pub extern "C" fn noctra_cosine_similarity(v1_ptr: *const f64, v2_ptr: *const f64) -> f64 {
    if v1_ptr.is_null() || v2_ptr.is_null() {
        return 0.5;
    }

    let v1 = unsafe { std::slice::from_raw_parts(v1_ptr, 16) };
    let v2 = unsafe { std::slice::from_raw_parts(v2_ptr, 16) };

    cosine_similarity(v1, v2)
}

/// Upscales raw float PCM audio samples in-place directly in memory.
///
/// Executes the 24-bit harmonic exciter, dynamic air band lift, and tanh soft limiter
/// at native CPU speed with zero memory allocations in the inner loop.
///
/// Returns 0 on success, or -1 on invalid input.
#[no_mangle]
pub extern "C" fn noctra_upscale_samples(
    samples_ptr: *mut f64,
    len: usize,
    channels: u16,
    sample_rate: u32,
    strength: f64,
) -> i32 {
    if samples_ptr.is_null() || len == 0 || channels == 0 || sample_rate == 0 {
        return -1;
    }

    let samples = unsafe { std::slice::from_raw_parts(samples_ptr, len) };
    let enhanced = UpscaleDspEngine::enhance_samples(samples, channels, sample_rate, strength);

    unsafe {
        std::ptr::copy_nonoverlapping(enhanced.as_ptr(), samples_ptr, len);
    }

    0
}

/// Separates interleaved 16-bit PCM audio samples into 4 isolated stems in memory.
///
/// `model_code`: 0 = Light, 1 = HighQuality, 2 = Karaoke.
/// Writes directly into caller-allocated buffers `out_vocals`, `out_drums`, `out_bass`, `out_other`.
/// Returns 0 on success, or -1 on error.
#[no_mangle]
pub extern "C" fn noctra_separate_stems(
    input_pcm: *const i16,
    len: usize,
    sample_rate: u32,
    channels: u16,
    model_code: u8,
    out_vocals: *mut i16,
    out_drums: *mut i16,
    out_bass: *mut i16,
    out_other: *mut i16,
) -> i32 {
    if input_pcm.is_null()
        || len == 0
        || sample_rate == 0
        || channels == 0
        || out_vocals.is_null()
        || out_drums.is_null()
        || out_bass.is_null()
        || out_other.is_null()
    {
        return -1;
    }

    let pcm = unsafe { std::slice::from_raw_parts(input_pcm, len) };
    let model = match model_code {
        1 => StemModel::HighQuality,
        2 => StemModel::Karaoke,
        _ => StemModel::Light,
    };

    let result = separate_stems(pcm, sample_rate, channels, model);

    unsafe {
        std::ptr::copy_nonoverlapping(result.vocals.as_ptr(), out_vocals, len);
        std::ptr::copy_nonoverlapping(result.drums.as_ptr(), out_drums, len);
        std::ptr::copy_nonoverlapping(result.bass.as_ptr(), out_bass, len);
        std::ptr::copy_nonoverlapping(result.other.as_ptr(), out_other, len);
    }

    0
}

/// Separates interleaved 16-bit PCM audio samples and writes 4 WAV files to `output_dir`.
///
/// Returns 0 on success, or -1 on error.
#[no_mangle]
pub extern "C" fn noctra_separate_stems_to_dir(
    input_pcm: *const i16,
    len: usize,
    sample_rate: u32,
    channels: u16,
    model_code: u8,
    output_dir_ptr: *const c_char,
) -> i32 {
    if input_pcm.is_null() || len == 0 || sample_rate == 0 || channels == 0 || output_dir_ptr.is_null() {
        return -1;
    }

    let c_str = unsafe { CStr::from_ptr(output_dir_ptr) };
    let Ok(output_dir) = c_str.to_str() else {
        return -1;
    };

    let pcm = unsafe { std::slice::from_raw_parts(input_pcm, len) };
    let model = match model_code {
        1 => StemModel::HighQuality,
        2 => StemModel::Karaoke,
        _ => StemModel::Light,
    };

    match separate_stems_to_directory(pcm, sample_rate, channels, output_dir, model) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

/// Writes a 16-bit PCM RIFF WAVE file to the specified file path.
///
/// Returns 0 on success, or -1 on error.
#[no_mangle]
pub extern "C" fn noctra_write_wav_file(
    path_ptr: *const c_char,
    samples_ptr: *const i16,
    len: usize,
    sample_rate: u32,
    channels: u16,
) -> i32 {
    if path_ptr.is_null() || samples_ptr.is_null() || sample_rate == 0 || channels == 0 {
        return -1;
    }

    let c_str = unsafe { CStr::from_ptr(path_ptr) };
    let Ok(path) = c_str.to_str() else {
        return -1;
    };

    let samples = unsafe { std::slice::from_raw_parts(samples_ptr, len) };

    match write_wav(path, samples, sample_rate, channels) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

/// Transliterates multi-script lyrics (Hangul, Cyrillic, Kana, Devanagari) to Latin.
///
/// Returns a heap-allocated C-string that MUST be freed using [noctra_free_string].
#[no_mangle]
pub extern "C" fn noctra_romanize_text(text_ptr: *const c_char) -> *mut c_char {
    if text_ptr.is_null() {
        return std::ptr::null_mut();
    }

    let c_str = unsafe { CStr::from_ptr(text_ptr) };
    let Ok(text) = c_str.to_str() else {
        return std::ptr::null_mut();
    };

    let romanized = romanize_text(text);
    match CString::new(romanized) {
        Ok(c_string) => c_string.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Detects the script of the given text (e.g. "korean", "japanese", "cyrillic", "devanagari", "latin").
///
/// Returns a static C-string that does NOT need to be freed.
#[no_mangle]
pub extern "C" fn noctra_detect_script(text_ptr: *const c_char) -> *const c_char {
    if text_ptr.is_null() {
        return b"other\0".as_ptr() as *const c_char;
    }

    let c_str = unsafe { CStr::from_ptr(text_ptr) };
    let Ok(text) = c_str.to_str() else {
        return b"other\0".as_ptr() as *const c_char;
    };

    let script = detect_script(text);
    match script.as_str() {
        "japanese" => b"japanese\0".as_ptr() as *const c_char,
        "chinese" => b"chinese\0".as_ptr() as *const c_char,
        "korean" => b"korean\0".as_ptr() as *const c_char,
        "cyrillic" => b"cyrillic\0".as_ptr() as *const c_char,
        "devanagari" => b"devanagari\0".as_ptr() as *const c_char,
        "thai" => b"thai\0".as_ptr() as *const c_char,
        "arabic" => b"arabic\0".as_ptr() as *const c_char,
        "latin" => b"latin\0".as_ptr() as *const c_char,
        _ => b"other\0".as_ptr() as *const c_char,
    }
}

/// Computes search relevance score in [0.0, 1.0] for a candidate track against a query.
#[no_mangle]
pub extern "C" fn noctra_score_candidate(
    query_ptr: *const c_char,
    title_ptr: *const c_char,
    artist_ptr: *const c_char,
) -> f64 {
    if query_ptr.is_null() || title_ptr.is_null() || artist_ptr.is_null() {
        return 0.0;
    }

    let Ok(query) = (unsafe { CStr::from_ptr(query_ptr) }).to_str() else { return 0.0 };
    let Ok(title) = (unsafe { CStr::from_ptr(title_ptr) }).to_str() else { return 0.0 };
    let Ok(artist) = (unsafe { CStr::from_ptr(artist_ptr) }).to_str() else { return 0.0 };

    score_candidate(query, title, artist)
}
