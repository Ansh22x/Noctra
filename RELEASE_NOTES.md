# Noctra v1.0.0

**Release date:** 2026-11-14
**Repository:** [github.com/Ansh22x/Noctra](https://github.com/Ansh22x/Noctra)
**Website:** [noctra-audio.netlify.app](https://noctra-audio.netlify.app/)

## Highlights

Noctra v1.0.0 is the first release published from the consolidated repository. It
keeps the full on-device feature set — bit-perfect Hi-Res FLAC playback, the
24-bit audio upscaler, neural taste modelling, bilingual lyrics — and rebuilds
the distribution pipeline around per-architecture Android packages that the
in-app updater can verify.

## Android Packages

| Package | ABI | Use it when |
|---|---|---|
| `Noctra-1.0.0-arm64-v8a.apk` | 64-bit ARM | Recommended for every modern phone and tablet |
| `Noctra-1.0.0-armeabi-v7a.apk` | 32-bit ARM | Older 32-bit devices only |
| `Noctra-1.0.0-x86_64.apk` | x86_64 | Emulators, ChromeOS, Windows Subsystem for Android |
| `Noctra-1.0.0-universal.apk` | All ABIs | When you are unsure about the device ABI |
| `Noctra-1.0.0.aab` | Google Play | Play Store upload only — not directly installable |

Android 8.0 (API 26) or newer is required. Every package is signed with the same
certificate, so an APK upgrades over the previous install without an uninstall.

## Desktop & iOS

Windows (`.exe`), Linux (`.deb`) and iOS (`.ipa`) packages are built by the
release workflow on their native runners; they appear on a release once the
workflow can sign Android builds. Android is the platform verified for this
tag.

## Integrity & Updates

- `noctra-update-manifest.json` publishes the version, `versionCode`,
  `minimumAndroid` and a `file` + `sha256` pair per ABI. The in-app updater
  resolves the exact package for the device, downloads it from a pinned GitHub
  URL, and refuses any artifact whose digest does not match.
- `SHA256SUMS.txt` lists every attached file:
  `sha256sum -c SHA256SUMS.txt --ignore-missing`.
- An optional detached Ed25519 signature (`noctra-update-manifest.json.sig`) is
  published when the release-signing key is configured.

## Repository Hygiene

- Removed the stale `release/` metadata, the obsolete PowerShell release
  dispatcher and the superseded Python packager.
- Dropped duplicated artwork and the installer archives that were previously
  committed to the deployed docs bundle.
- Every repository, updater and website link points at `Ansh22x/Noctra` and
  `noctra-audio.netlify.app`.
