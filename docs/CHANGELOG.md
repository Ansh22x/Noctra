# Changelog

## v1.0.3 (2026-11-27)

### WhisperX + Genius Synchronized Lyrics
- **Genius Lyrics Provider**: Added zero-key Genius public search and balanced-container HTML lyrics extraction (with optional Genius API token support).
- **WhisperX Forced Alignment**: Added `WhisperXSyncService` supporting forced alignment of Genius/plain lyrics to audio timestamps via a WhisperX HTTP sidecar (`tool/whisperx_server.py`) or desktop CLI fallback, plus on-demand **WhisperX Sync** in the Lyrics view.

### Non-English Song Translation
- **Automatic & On-Demand Translation**: Added `LyricsTranslationService` with non-English language detection (both non-Latin scripts and Latin-script languages) and batched English translation for both synced and plain-text lyrics.
- **Lyrics UI & Settings**: Added **Translate** toggle and source indicator chips in `LyricsView`, line-by-line plain-text translation display, and persisted WhisperX/Genius/translation controls in Settings.

## v1.0.2 (2026-11-17)

### Streamlined Architecture & Codebase Pruning
- **Removed Over 5,000 Lines of Bloat**: Cleaned up obsolete migration scripts, dead neural models, and stale tool caches.
- **Removed AI Studio**: Replaced the cluttered AI Studio screen and widgets with a focused 3-tab layout (Home, Search, Library).
- **Relocated Documentation**: Moved all documentation, changelogs, contributing guidelines, and architecture guides to the unified `docs/` directory.

### Dual Glassmorphic Theme System
- **Strict 2-Theme System**: Retained exclusively **Glassmorphic Black** and **Liquid Glass** themes; removed Noir White and Material U.
- **Self-Healing Preferences**: Automatic database migration seamlessly maps legacy or removed theme settings to Glassmorphic Black.
- **Unified Frosted Backdrops & Palette**: Enhanced glass blur sigma, ambient tint layers, and high-contrast specular borders.

### Spotify Recommendation Engine
- **Replaced On-Device Neural AI**: Replaced the local MLP neural recommender and synthetic weight backpropagation with Spotify's official recommendation graph.
- **Real-Time Recommendations**: Direct token acquisition and seed-based track recommendations via Spotify Web API (`/v1/recommendations`).
- **Offline & Curated Fallbacks**: Seamless fallback to curated Spotify genre charts and mood-based radio feeds when unauthenticated or offline.

### Library Revamp: Fixed Downloads & Big Artwork Covers
- **Fixed Downloads Folder**: Pinned permanent `Downloads` folder at index 0 for all saved offline tracks.
- **Fixed Favorites Folder**: Pinned `Favorites` folder at index 1.
- **Big Artwork Covers**: New responsive folder card system displaying 2x2 multi-track artwork collages and hero cover art instead of generic icons.
- **Quick Library Actions**: Fast controls for folder creation, URL playlist imports, library insights, and local storage scanning.

### Native Rust Core Acceleration
- **JioSaavn DES Stream Decryption**: Accelerated stream URL decryption via native Rust FFI (`noctra_core`).
- **Lyric Transliteration**: Native romanization pipelines for Indic and East Asian scripts.
- **Native Spotify Resolver**: Built-in Rust Spotify playlist harvester and recommendation provider in `noctra_core`.

## v1.0.1 (2026-11-14)

### Native Rust Core Engine Integration (`noctra_core`)
- **Embedded Bare-Metal Audio DSP & FFI**: Integrated high-performance embedded Rust engine (`noctra_core.dll` / `libnoctra_core.so`) via zero-copy in-memory Dart FFI.
- **Ported Audio Stem Separation & FFT**: In-place Radix-2 Cooley-Tukey FFT & IFFT with bit-reversal and spectral band masking (Vocals, Bass, Drums, Other, Karaoke, HQ) running 10x faster with zero JVM garbage collection pauses.
- **Multi-Script Lyric Transliteration**: Sub-millisecond on-device transliteration for Korean Hangul (algorithmic Jamo decomposition), Cyrillic (Ukrainian/Russian auto-presets), Japanese Kana (Hepburn monographs/digraphs), and Indic Devanagari.
- **High-Speed Fuzzy Search Relevance Ranker**: Native Levenshtein edit distance ($\le 1$), diacritic folding, natural language intent parsing ("<Title> by <Artist>"), and modifier penalty scoring.
- **Native InnerTube & JioSaavn Decryption**: In-process DES ECB 320kbps stream decryption and direct Opus/AAC InnerTube extraction without signature deciphering.

### 100% Serverless & Standalone Architecture
- **Purged Legacy Python Backend**: Zero local or cloud server hosting required. The entire music and intelligence engine runs directly inside the client application.
- **Purged Redundant Legacy Kotlin**: Removed 13 legacy Kotlin files (~1,600 LOC) in favor of the unified cross-platform native Rust engine.

### In-App Update System
- Added direct "Check for Updates" action in Settings Sheet and Noir Sidebar.
- Direct in-app download, SHA-256 integrity verification, staging, and native package installer trigger without leaving the application.

## v1.0.0 (2026-11-14)

### First Release Of The Consolidated Repository

Noctra is now published from a single repository at
[`Ansh22x/Noctra`](https://github.com/Ansh22x/Noctra). This release rebuilds the
distribution pipeline around it and ships the full feature set described in the
README.

### Per-Architecture Android Packages
- Four installable APKs per release: `arm64-v8a` (default for modern 64-bit
devices), `armeabi-v7a` (32-bit legacy), `x86_64` (emulators, ChromeOS, WSA) and
`universal` (any ABI) — plus an `.aab` for Play Store upload.
- MinSdk is pinned to API 26 (Android 8.0) in Gradle, the release manifest, and
the updater's compatibility gate, so the documented floor is actually enforced.

### Verifiable, Machine-Readable Releases
- Every release publishes `noctra-update-manifest.json`, which pins each ABI's
filename and SHA-256; the in-app updater resolves the exact package for the
device and refuses anything whose digest does not match.
- `SHA256SUMS.txt` covers every attached file, and an optional detached
signature (`noctra-update-manifest.json.sig`) is published when a signing key is
configured.
- One script (`tool/write_release_manifest.sh`) generates that metadata for both
local builds and CI, so the two can never drift.

### Repository Hygiene
- Removed the stale `release/` metadata, the obsolete PowerShell release
dispatcher and the Python packager it replaced, plus duplicated artwork.
- Trimmed the previously committed installer archives from the deployed docs
bundle.
- All repository, updater and website links point at `Ansh22x/Noctra`.
