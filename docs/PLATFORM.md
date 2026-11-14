# Noctra Cross-Platform Readiness

Status of the multi-platform port. This document is **honest**: it reflects
what is implemented and verified on Android, and what is scaffold-only or
untestable in the current environment.

## Environment reality (recorded, not assumed)

| Target   | Toolchain present | Build verified | Runtime verified |
|----------|-------------------|----------------|------------------|
| Android  | yes (SDK 36)      | yes            | yes (RMX3395)    |
| Windows  | **no** (no Visual Studio) | no       | no               |
| Linux    | **no** (`linux/` tree absent) | no    | no               |
| iOS      | **no** (no macOS/Xcode) | no         | no               |
| macOS    | no                | no             | no               |
| Web      | partial (Chrome)  | no             | no               |

`ios/`, `macos/`, `windows/`, `web/` directories exist as framework scaffolds.
Android remains the flagship release platform, and all release artifacts are
produced by GitHub Actions (`.github/workflows/cross_platform_build.yml`):
Android universal + per-ABI APKs + AAB (release-keystore signed via repo
secrets), Windows Inno Setup installer, Linux `.deb`, and a sideloadable iOS
`.ipa` — checksummed and published automatically on `v*` tags. The local
machine still cannot verify desktop/iOS builds; those claims rest on the
workflow runners, not this environment.

## Release artifacts & the updater contract

Every release publishes four installable Android variants plus the Play bundle.
`tool/write_release_manifest.sh` is the single source of truth for naming and
digests, and it is what both `tool/build_release.sh` (local) and the release
workflow run, so the metadata cannot drift between the two.

| Artifact | ABI | Notes |
|---|---|---|
| `Noctra-<version>-arm64-v8a.apk` | `arm64-v8a` | Default for modern devices; what the updater selects on a 64-bit phone |
| `Noctra-<version>-armeabi-v7a.apk` | `armeabi-v7a` | 32-bit legacy devices |
| `Noctra-<version>-x86_64.apk` | `x86_64` | Emulators, ChromeOS, WSA |
| `Noctra-<version>-universal.apk` | all | Fallback for unknown ABIs |
| `Noctra-<version>.aab` | all | Play Store upload only |
| `noctra-update-manifest.json` | — | `version`, `versionCode`, `minimumAndroid`, and `file` + `sha256` per ABI |
| `noctra-update-manifest.json.sig` | — | Present only when a signing key is configured |
| `SHA256SUMS.txt` | — | Digests for every file attached to the release |

The in-app updater (`lib/services/updater/`) fetches the manifest first and
picks the exact ABI package, falling back to `universal`; it refuses any
artifact whose SHA-256 does not match the pinned digest, and it derives the
download URL from a hard-coded base rather than from remote JSON. Releases
without a manifest still resolve through the legacy asset-name scan.

Android minimum is **API 26 (Android 8.0)**, enforced in
`android/app/build.gradle.kts` (`minSdk = 26`) and mirrored in the manifest's
`minimumAndroid`. Windows, Linux and iOS jobs are `continue-on-error`: a broken
desktop build cannot block the Android APKs from publishing.

## Capability contracts

Platform decisions flow through `lib/core/platform/`:

- `noctra_capabilities.dart` — `NoctraPlatform` + `NoctraCapabilities`
  registry (isAndroid / isDesktop / supportsLauncherIcons /
  supportsNativeAudioEffects / supportsNativeResolver / supportsSelfUpdate …).
- `export_core_platform.dart` — barrel import.

Rules (enforced by `test/architecture_boundaries_test.dart`):

1. `core/`, `data/models/`, `ui/` must not import `dart:io` / `dart:ffi`,
   construct `MethodChannel`/`EventChannel`, or use raw `Platform.is*`.
2. Platform adapters live in `services/platform/` and `services/resolvers/`,
   `services/audio`, `services/updater` — they own channels, permissions and
   filesystem paths.

## Feature / platform matrix

Classification: FULL = implemented & Android-verified · PARTIAL = implemented
with Android-only parts · PLATFORM-SPECIFIC = adapter exists, Android impl only
· UNAVAILABLE = not implemented on that platform · NOT APPLICABLE.

| Feature                    | Android | Windows | Linux | iOS |
|----------------------------|---------|---------|-------|-----|
| Playback (local/stream)    | FULL    | scaffold | —    | scaffold |
| Queue / shuffle / repeat   | FULL    | shared code | shared | shared |
| Search / artists / albums  | FULL    | shared code | shared | shared |
| Playlists                  | FULL    | shared code | shared | shared |
| Downloads + offline        | FULL    | shared code* | shared* | shared* |
| Lyrics (+ romanization)    | FULL    | shared code | shared | shared |
| Recommendations/generated  | FULL    | shared code | shared | shared |
| Themes (3, no AMOLED)      | FULL    | shared code | shared | shared |
| Library persistence        | FULL    | PARTIAL (sqflite desktop not configured) | PARTIAL | FULL |
| Artwork                    | FULL    | shared code | shared | shared |
| Audio effects (native DSP) | FULL    | UNAVAILABLE | UNAVAILABLE | UNAVAILABLE |
| Visualizer (native)        | FULL    | UNAVAILABLE | UNAVAILABLE | UNAVAILABLE |
| Audio routing (native)     | FULL    | UNAVAILABLE | UNAVAILABLE | PARTIAL |
| Media controls/notification| FULL    | scaffold | —    | scaffold |
| Background playback        | FULL    | scaffold | —    | scaffold |
| Bluetooth controls         | FULL    | N/A       | N/A   | PARTIAL |
| Native resolver (Kotlin)   | FULL    | UNAVAILABLE | UNAVAILABLE | UNAVAILABLE |
| Updater (self-update)      | FULL    | UNAVAILABLE | UNAVAILABLE | UNAVAILABLE |
| Jam / P2P (LAN)            | FULL    | untested   | untested | UNAVAILABLE |
| Stem separation (native)   | FULL    | UNAVAILABLE | UNAVAILABLE | UNAVAILABLE |

\* Download path resolution is platform-aware via
`services/platform/download_location_resolver.dart`; the download pipeline
(ytdlp + native stem engine) remains Android-oriented.

## Refactor boundaries established (this phase)

- `lib/core/utils/dynamic_icon_service.dart` → `services/platform/` (channel
  adapter no longer lives in `core`).
- `data/models/download_location.dart` is now a pure model; the path resolver
  moved to `services/platform/download_location_resolver.dart` (Android path
  behavior preserved byte-for-byte).
- `services/platform/download_folder_service.dart` owns the Android
  storage-permission + folder picker + write-probe so the settings widget has
  no `dart:io`/permission_handler/`Platform.isAndroid`.
- `services/resolvers/native_resolver_client.dart` is the only UI-reachable
  native InnerTube entry; the stem sheet no longer constructs a channel.
- Migration import UI now hands a path to
  `MigrationManager.processImportPath` instead of constructing `File`.
- `NoctraCapabilities` replaces scattered `Platform.isAndroid`/`kIsWeb`
  checks in adapters (icon service, effects engine).

## What still needs real platforms (next stages)

Actual Windows/Linux/iOS enablement — `flutter create --platforms=…`, desktop
audio engine adapters, iOS AVAudioSession/lock-screen integration, per-platform
updater providers — cannot be built or tested in this environment and is not
claimed. The capability registry + enforcement rules are the seam those
adapters plug into.
