#!/usr/bin/env bash
# Builds Noctra's GitHub-distribution artifacts LOCALLY and writes the
# release manifest the in-app updater consumes. It never uploads or
# publishes anything — publishing stays a GitHub step (or CI, see
# .github/workflows/cross_platform_build.yml).
#
# Usage:
#   tool/build_release.sh            # per-ABI + universal APKs + manifest
#   tool/build_release.sh --no-build # only hash existing APKs + manifest
# Optional signing:
#   NOCTRA_UPDATE_MANIFEST_SIGNING_KEY=/path/to/ed25519-private.pem \
#     tool/build_release.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
NO_BUILD=0
if [[ "${1:-}" == "--no-build" ]]; then NO_BUILD=1; fi

FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
OUT="build/release"

VERSION_LINE="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -n1)"
VERSION="${VERSION_LINE%%+*}"
BUILD_CODE="${VERSION_LINE##*+}"
echo "Version: $VERSION (buildCode $BUILD_CODE)"

if [[ "$NO_BUILD" == "0" ]]; then
  echo "==> Building per-ABI release APKs (this takes a while)"
  "$FLUTTER_BIN" build apk --release --split-per-abi
  echo "==> Building universal release APK"
  "$FLUTTER_BIN" build apk --release
fi

# --- collect + rename artifacts -------------------------------------------
declare -A ABI_FILES=(
  [arm64-v8a]=app-arm64-v8a-release.apk
  [armeabi-v7a]=app-armeabi-v7a-release.apk
  [x86_64]=app-x86_64-release.apk
  [universal]=app-release.apk
)

FLUTTER_APK="${FLUTTER_APK_DIR:-build/app/outputs/flutter-apk}"
rm -rf "$OUT"
mkdir -p "$OUT"
for ABI in arm64-v8a armeabi-v7a x86_64 universal; do
  SRC="$FLUTTER_APK/${ABI_FILES[$ABI]}"
  if [[ ! -f "$SRC" ]]; then
    echo "!! Missing $SRC — skipping $ABI" >&2
    continue
  fi
  cp "$SRC" "$OUT/Noctra-${VERSION}-${ABI}.apk"
done

bash tool/write_release_manifest.sh "$OUT" "$VERSION" "$BUILD_CODE"

echo "==> Upload ALL of the following to the GitHub release:"
echo "    - every Noctra-*.apk under $OUT/"
echo "    - SHA256SUMS.txt"
echo "    - noctra-update-manifest.json (exact name required)"
if [[ -f "$OUT/noctra-update-manifest.json.sig" ]]; then
  echo "    - noctra-update-manifest.json.sig (exact name required)"
fi
