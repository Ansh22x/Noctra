# Changelog

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
