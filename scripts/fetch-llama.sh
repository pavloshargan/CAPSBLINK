#!/usr/bin/env bash
# Downloads the pinned, prebuilt llama.cpp xcframework from the official
# llama.cpp GitHub releases and unpacks it into Vendor/llama.xcframework.
#
# The build tag and archive checksum are pinned below; bump both together to
# upgrade llama.cpp (see docs/MODEL.md).
set -euo pipefail

LLAMA_TAG="${LLAMA_TAG:-b10068}"
LLAMA_SHA256="${LLAMA_SHA256:-5238397dd4ca305c9db537c3ae106948909ba2605e77d2d3463ac2d2ca08cc8a}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$REPO_ROOT/Vendor"
DEST="$VENDOR_DIR/llama.xcframework"
STAMP="$VENDOR_DIR/.llama-version"
ZIP_URL="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_TAG}/llama-${LLAMA_TAG}-xcframework.zip"

if [[ -d "$DEST" && -f "$STAMP" && "$(cat "$STAMP")" == "$LLAMA_TAG" ]]; then
    echo "llama.xcframework ${LLAMA_TAG} already present, skipping."
    exit 0
fi

mkdir -p "$VENDOR_DIR"
ZIP_PATH="$VENDOR_DIR/llama-${LLAMA_TAG}-xcframework.zip"

if [[ ! -f "$ZIP_PATH" ]]; then
    echo "Downloading llama.cpp xcframework ${LLAMA_TAG}..."
    curl --fail --location --progress-bar -o "$ZIP_PATH.tmp" "$ZIP_URL"
    mv "$ZIP_PATH.tmp" "$ZIP_PATH"
fi

echo "Verifying checksum..."
ACTUAL="$(shasum -a 256 "$ZIP_PATH" | cut -d' ' -f1)"
if [[ "$ACTUAL" != "$LLAMA_SHA256" ]]; then
    echo "error: checksum mismatch for $ZIP_PATH" >&2
    echo "  expected: $LLAMA_SHA256" >&2
    echo "  actual:   $ACTUAL" >&2
    exit 1
fi

echo "Extracting (skipping debug symbols)..."
EXTRACT_DIR="$(mktemp -d)"
trap 'rm -rf "$EXTRACT_DIR"' EXIT
unzip -q "$ZIP_PATH" -x '*dSYM*' -d "$EXTRACT_DIR"

rm -rf "$DEST"
mv "$EXTRACT_DIR/build-apple/llama.xcframework" "$DEST"

# We skip the (large) dSYMs, but the xcframework's Info.plist still points at
# them, which fails multi-arch (xcbuild) builds. Drop the references.
i=0
while /usr/libexec/PlistBuddy -c "Print :AvailableLibraries:$i" "$DEST/Info.plist" >/dev/null 2>&1; do
    /usr/libexec/PlistBuddy -c "Delete :AvailableLibraries:$i:DebugSymbolsPath" "$DEST/Info.plist" 2>/dev/null || true
    i=$((i + 1))
done
echo "$LLAMA_TAG" > "$STAMP"
rm -f "$ZIP_PATH"
echo "Installed $DEST (llama.cpp ${LLAMA_TAG})"
