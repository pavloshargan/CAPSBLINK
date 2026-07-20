#!/usr/bin/env bash
# Packs dist/<App>.app into a compressed DMG with an /Applications shortcut.
#
# Usage: scripts/make-dmg.sh <CapsBlink|CapsBlinkAgents>
# Env:   VERSION (used in the DMG file name; default 0.0.0-dev)
set -euo pipefail

APP="${1:-CapsBlink}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

VERSION="${VERSION:-$(git describe --tags --always 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0-dev}"

APP_DIR="dist/$APP.app"
[[ -d "$APP_DIR" ]] || { echo "error: $APP_DIR missing — run scripts/bundle-app.sh $APP first" >&2; exit 1; }

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP_DIR" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

DMG="dist/$APP-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "$APP" -srcfolder "$STAGING" -ov -format UDZO -quiet "$DMG"
echo "Built $DMG"
