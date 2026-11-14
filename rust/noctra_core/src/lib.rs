//! Noctra Core: High-performance Native Rust Engine.
//!
//! Provides:
//! - 24-bit Audio Upscaling DSP (SIMD harmonic exciter, dynamic Nyquist, soft limiter).
//! - JioSaavn 320kbps DES media decryption & multi-source catalog resolution.
//! - Offline 16-axis acoustic vector space and Hybrid Dense RAG re-ranker.
//! - Ultra-low-latency Axum HTTP server drop-in replacement for the Python sidecar.

pub mod crypto;
pub mod dsp;
pub mod ffi;
pub mod server;
pub mod services;

pub use crypto::des::{decrypt_des_ecb, decrypt_jiosaavn_media_url};
pub use dsp::{Biquad, UpscaleDspEngine, UpscaleResult};
pub use server::create_router;
pub use services::{
    ai_rag::{generate_16axis_vector, hybrid_dense_rag_rerank, query_knowledge_graph_context},
    jiosaavn::{get_jiosaavn_trending, search_jiosaavn_music},
    lyrics::fetch_lyrics,
    musicbrainz::enrich_metadata,
    spotify::{fetch_spotify_playlist, get_dynamic_spotify_charts},
};
