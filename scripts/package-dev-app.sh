#!/usr/bin/env bash
#
# package-dev-app.sh — wrap SwiftPM's SeshatAppKit executable into a
# double-clickable Seshat.app bundle for local testing.
#
# This is a dev-loop helper. Distribution builds (Developer ID, notarization,
# Homebrew) come in Phase 4.
#
# Usage:
#   scripts/package-dev-app.sh              # debug build (faster)
#   scripts/package-dev-app.sh release      # optimized build
#
# Output: ./Seshat.app
# Launch: open Seshat.app

set -euo pipefail

CONFIG="${1:-debug}"
if [[ "$CONFIG" != "debug" && "$CONFIG" != "release" ]]; then
    echo "Usage: $0 [debug|release]" >&2
    exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="Seshat"
BINARY_NAME="SeshatAppKit"
BUNDLE_ID="com.nitkrar.seshat"
VERSION="0.1.0"
MIN_MACOS="14.0"
BUILD_DIR=".build/$CONFIG"
APP_PATH="$REPO_ROOT/$APP_NAME.app"

echo "==> [1/5] Building $BINARY_NAME ($CONFIG)..."
swift build -c "$CONFIG" --product "$BINARY_NAME"

if [[ ! -x "$BUILD_DIR/$BINARY_NAME" ]]; then
    echo "error: expected executable at $BUILD_DIR/$BINARY_NAME not found" >&2
    exit 1
fi

echo "==> [2/5] Assembling $APP_PATH..."
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"
cp "$BUILD_DIR/$BINARY_NAME" "$APP_PATH/Contents/MacOS/$BINARY_NAME"

echo "==> [3/5] Writing Info.plist..."
cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${BINARY_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Nitkrar. MIT License.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Seshat transcribes your speech into text locally on your Mac. Audio never leaves your device.</string>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

# Legacy macOS bundle marker (harmless; some tools still check for it).
printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"

echo "==> [4/5] Ad-hoc code signing (hardened runtime + mic entitlement)..."
# macOS 26 requires hardened runtime for the binary to pass AMFI. Hardened
# runtime additionally requires the audio-input entitlement for microphone
# access; tccd silently denies the mic prompt (promptPolicy=4) without it.
ENTITLEMENTS_PLIST="$(mktemp -t seshat-entitlements.XXXXXX).plist"
trap 'rm -f "$ENTITLEMENTS_PLIST"' EXIT
cat > "$ENTITLEMENTS_PLIST" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
ENT

codesign \
    --force \
    --sign - \
    --deep \
    --options runtime \
    --entitlements "$ENTITLEMENTS_PLIST" \
    --timestamp=none \
    "$APP_PATH" >/dev/null

echo "==> [5/5] Verifying signature..."
codesign --verify --verbose "$APP_PATH"

SIZE="$(du -sh "$APP_PATH" | awk '{print $1}')"

echo ""
echo "✓ Built $APP_PATH ($SIZE)"
echo ""
echo "  Launch:             open \"$APP_PATH\""
echo "  First-run Gatekeeper:  right-click → Open, then click Open"
echo "  First run will prompt for microphone permission."
echo "  On first record, Parakeet CoreML model (~442 MiB) downloads to:"
echo "    ~/Library/Application Support/Seshat/models/parakeet-tdt-0.6b-v2/"
echo ""
