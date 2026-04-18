#!/usr/bin/env bash
#
# package-dev-dmg.sh — wrap Seshat.app into a distributable .dmg.
#
# Produces a compressed read-only DMG with an /Applications alias so the
# installer experience is "drag Seshat.app into Applications".
#
# This is a dev/dogfood helper. It uses ad-hoc signing only (no Developer ID,
# no notarization). First-run on another Mac will hit Gatekeeper — user must
# right-click → Open, OR run:
#   xattr -dr com.apple.quarantine /Applications/Seshat.app
#
# Usage:
#   scripts/package-dev-dmg.sh              # debug build
#   scripts/package-dev-dmg.sh release      # optimized build
#
# Output: ./Seshat-<version>.dmg
# Install: open Seshat-<version>.dmg  → drag into Applications

set -euo pipefail

CONFIG="${1:-debug}"
if [[ "$CONFIG" != "debug" && "$CONFIG" != "release" ]]; then
    echo "Usage: $0 [debug|release]" >&2
    exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="Seshat"
VERSION="0.1.0"
APP_PATH="$REPO_ROOT/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION"
DMG_PATH="$REPO_ROOT/$DMG_NAME.dmg"
STAGING_DIR="$(mktemp -d -t seshat-dmg-staging)"
trap 'rm -rf "$STAGING_DIR"' EXIT

echo "==> [1/4] Building $APP_NAME.app ($CONFIG)..."
"$REPO_ROOT/scripts/package-dev-app.sh" "$CONFIG"

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: expected $APP_PATH not found after build" >&2
    exit 1
fi

echo "==> [2/4] Staging DMG contents at $STAGING_DIR..."
cp -R "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> [3/4] Creating compressed DMG..."
rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "$DMG_PATH" >/dev/null

echo "==> [4/4] Verifying DMG..."
hdiutil verify "$DMG_PATH" >/dev/null

SIZE="$(du -sh "$DMG_PATH" | awk '{print $1}')"

echo ""
echo "✓ Built $DMG_PATH ($SIZE)"
echo ""
echo "  Install:  open \"$DMG_PATH\" → drag $APP_NAME.app into Applications"
echo ""
echo "  First-run on another Mac (ad-hoc signed, not notarized):"
echo "    Option A: right-click Seshat.app → Open → click Open in dialog"
echo "    Option B: xattr -dr com.apple.quarantine /Applications/Seshat.app"
echo ""
echo "  First launch prewarms Parakeet CoreML (~442 MiB) in the background to:"
echo "    ~/Library/Application Support/Seshat/models/parakeet-tdt-0.6b-v2/"
echo "  First record blocks only if prewarm hasn't finished yet."
echo ""
