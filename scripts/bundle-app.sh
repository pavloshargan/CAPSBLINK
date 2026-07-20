#!/usr/bin/env bash
# Assembles a distributable .app bundle from the SwiftPM build products.
#
# Usage:
#   scripts/bundle-app.sh <CapsBlink|CapsBlinkAgents>
#
# Environment:
#   VERSION        App version (default: git describe, else 0.0.0-dev)
#   UNIVERSAL=1    Build a universal (arm64 + x86_64) binary
#   BUNDLE_MODEL=1 Copy Models/<gguf> into the bundle (CapsBlink only)
#   SIGN_IDENTITY  codesign identity (default "-" = ad-hoc)
set -euo pipefail

APP="${1:-CapsBlink}"
case "$APP" in
    CapsBlink|CapsBlinkAgents) ;;
    *) echo "usage: $0 <CapsBlink|CapsBlinkAgents>" >&2; exit 64 ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

VERSION="${VERSION:-$(git describe --tags --always 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0-dev}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

BUILD_ARGS=(-c release --product "$APP")
BIN_DIR=".build/release"
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
    BIN_DIR=".build/apple/Products/Release"
fi

echo "Building $APP $VERSION (release)..."
swift build "${BUILD_ARGS[@]}"

# Assemble and sign in a temp dir: building inside an iCloud-synced folder
# (e.g. ~/Documents) races with the sync daemon, which tags the bundle with
# FinderInfo attributes that make codesign reject it as "detritus".
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
APP_DIR="$STAGING/$APP.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/$APP" "$APP_DIR/Contents/MacOS/$APP"
sed "s/__VERSION__/$VERSION/g" "Resources/$APP-Info.plist" > "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

# Only the page watcher links llama.cpp; embed its framework and point the
# executable's rpath at Contents/Frameworks.
if [[ "$APP" == "CapsBlink" ]]; then
    FRAMEWORK_SRC="Vendor/llama.xcframework/macos-arm64_x86_64/llama.framework"
    if [[ ! -d "$FRAMEWORK_SRC" ]]; then
        echo "error: $FRAMEWORK_SRC missing — run 'make deps' first" >&2
        exit 1
    fi
    mkdir -p "$APP_DIR/Contents/Frameworks"
    cp -R "$FRAMEWORK_SRC" "$APP_DIR/Contents/Frameworks/"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_DIR/Contents/MacOS/$APP" 2>/dev/null || true

    if [[ "${BUNDLE_MODEL:-0}" == "1" ]]; then
        shopt -s nullglob
        MODELS=(Models/*.gguf)
        shopt -u nullglob
        if [[ ${#MODELS[@]} -eq 0 ]]; then
            echo "error: BUNDLE_MODEL=1 but no Models/*.gguf found — run 'make model' first" >&2
            exit 1
        fi
        mkdir -p "$APP_DIR/Contents/Resources/Models"
        cp "${MODELS[@]}" "$APP_DIR/Contents/Resources/Models/"
        echo "Bundled model: ${MODELS[*]}"
    fi
fi

echo "Code signing ($SIGN_IDENTITY)..."
xattr -cr "$APP_DIR" # extended attributes make codesign reject the bundle
if [[ -d "$APP_DIR/Contents/Frameworks/llama.framework" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" "$APP_DIR/Contents/Frameworks/llama.framework"
fi
SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    SIGN_FLAGS+=(--options runtime --timestamp)
fi
codesign "${SIGN_FLAGS[@]}" "$APP_DIR"
codesign --verify --verbose=1 "$APP_DIR"

mkdir -p dist
rm -rf "dist/$APP.app"
mv "$APP_DIR" "dist/$APP.app"
echo "Built dist/$APP.app"
