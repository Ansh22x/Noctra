# Changelog

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
