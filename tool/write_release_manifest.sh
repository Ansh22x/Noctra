#!/usr/bin/env bash
# Writes noctra-update-manifest.json + SHA256SUMS.txt for a directory that
# already contains canonically named APKs (Noctra-<version>-<abi>.apk).
#
# The in-app updater reads the manifest from the GitHub release assets, so the
# CI release workflow and local packaging must publish byte-identical metadata.
# Keeping one implementation here means a single place to fix.
#
# Usage:
#   tool/write_release_manifest.sh <apk-dir> [version] [buildCode]
#
# version/buildCode default to pubspec.yaml; minimumAndroid defaults to the
# minSdk declared in android/app/build.gradle.kts.
# Optional signing:
#   NOCTRA_UPDATE_MANIFEST_SIGNING_KEY=/path/to/ed25519-private.pem
set -euo pipefail

DIR="${1:?usage: write_release_manifest.sh <apk-dir> [version] [buildCode]}"
[[ -d "$DIR" ]] || { echo "!! $DIR is not a directory" >&2; exit 1; }

cd "$(git rev-parse --show-toplevel)"

VERSION="${2:-}"
BUILD_CODE="${3:-}"
if [[ -z "$VERSION" || -z "$BUILD_CODE" ]]; then
  VERSION_LINE="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -n1)"
  [[ -n "$VERSION" ]] || VERSION="${VERSION_LINE%%+*}"
  [[ -n "$BUILD_CODE" ]] || BUILD_CODE="${VERSION_LINE##*+}"
fi
[[ -n "$VERSION" && -n "$BUILD_CODE" ]] \
  || { echo "!! Could not determine version/build code" >&2; exit 1; }

MIN_SDK="$(sed -n 's/.*minSdk[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' \
  android/app/build.gradle.kts | head -n1)"
MIN_SDK="${MIN_SDK:-26}"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v python >/dev/null 2>&1; then
    python -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"
  else
    echo "!! No SHA-256 hasher available (sha256sum/python)" >&2
    return 1
  fi
}

PACKAGES_JSON=""
SUMS_LINES=""
FOUND=0
for ABI in arm64-v8a armeabi-v7a x86_64 universal; do
  FILE="$DIR/Noctra-${VERSION}-${ABI}.apk"
  if [[ ! -f "$FILE" ]]; then
    echo "!! Missing $FILE — skipping $ABI" >&2
    continue
  fi
  SHA="$(sha256_of "$FILE")"
  echo "  $ABI -> $(basename "$FILE")  sha256=$SHA"
  SUMS_LINES+="$SHA  $(basename "$FILE")"$'\n'
  if [[ "$FOUND" == "1" ]]; then PACKAGES_JSON+=","; fi
  FOUND=1
  PACKAGES_JSON+="
    \"$ABI\": {
      \"file\": \"$(basename "$FILE")\",
      \"sha256\": \"$SHA\"
    }"
done

if [[ "$FOUND" == "0" ]]; then
  echo "!! No Noctra-${VERSION}-<abi>.apk found in $DIR" >&2
  exit 1
fi

cat > "$DIR/noctra-update-manifest.json" <<EOF
{
  "version": "$VERSION",
  "versionCode": $BUILD_CODE,
  "minimumAndroid": $MIN_SDK,
  "packages": {$PACKAGES_JSON
  }
}
EOF

# Two spaces between digest and name, sorted by filename: the format
# `sha256sum -c` expects.
printf '%s' "$SUMS_LINES" | LC_ALL=C sort -k2 > "$DIR/SHA256SUMS.txt"

echo
echo "==> Checksums: $DIR/SHA256SUMS.txt"
cat "$DIR/SHA256SUMS.txt"
echo
echo "==> Release manifest: $DIR/noctra-update-manifest.json"
cat "$DIR/noctra-update-manifest.json"
echo

if [[ -n "${NOCTRA_UPDATE_MANIFEST_SIGNING_KEY:-}" ]]; then
  if [[ ! -f "$NOCTRA_UPDATE_MANIFEST_SIGNING_KEY" ]]; then
    echo "!! Manifest signing key was not found" >&2
    exit 1
  fi
  if ! command -v openssl >/dev/null 2>&1; then
    echo "!! OpenSSL is required to sign the release manifest" >&2
    exit 1
  fi
  openssl pkeyutl -sign -rawin \
    -inkey "$NOCTRA_UPDATE_MANIFEST_SIGNING_KEY" \
    -in "$DIR/noctra-update-manifest.json" | base64 | tr -d '\r\n' \
    > "$DIR/noctra-update-manifest.json.sig"
  echo "==> Detached manifest signature: $DIR/noctra-update-manifest.json.sig"
fi
