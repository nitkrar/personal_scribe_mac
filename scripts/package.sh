#!/usr/bin/env bash
#
# package.sh — build Seshat.app; optionally install to /Applications,
# produce a DMG, and launch.
#
# Usage:
#   scripts/package.sh [options]
#
# Options:
#   -c, --config <debug|release>   Build config (default: debug)
#   -i, --install                  Replace /Applications/Seshat.app after build
#   -d, --dmg                      Also emit Seshat-<ver>.dmg at repo root
#   -r, --run                      Launch after install (implies --install)
#   -h, --help                     Show this help
#
# Examples:
#   scripts/package.sh                      # build ./Seshat.app only
#   scripts/package.sh -ir                  # build + install + launch (common dev loop)
#   scripts/package.sh -c release -ir       # release build + install + launch
#   scripts/package.sh -d                   # build + DMG (for GitHub Release upload)
#
# Notes:
#   * Always rebuilds the .app fresh — no way to skip. Avoids running
#     a stale binary after a code change.
#   * Ad-hoc signed with hardened runtime + audio-input entitlement.
#   * Install replaces /Applications/Seshat.app at a stable path — per-path
#     TCC grants (Mic, Input Monitoring, Accessibility) persist across rebuilds.
#   * First-run Gatekeeper: right-click Seshat.app → Open, OR
#       xattr -dr com.apple.quarantine /Applications/Seshat.app

set -euo pipefail

CONFIG="debug"
DO_INSTALL=0
DO_DMG=0
DO_RUN=0

print_usage() {
    sed -n '2,/^set -euo/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config)
            if [[ $# -lt 2 ]]; then
                echo "error: --config requires an argument" >&2
                exit 2
            fi
            CONFIG="$2"
            shift 2
            ;;
        -i|--install)
            DO_INSTALL=1
            shift
            ;;
        -d|--dmg)
            DO_DMG=1
            shift
            ;;
        -r|--run)
            DO_RUN=1
            DO_INSTALL=1
            shift
            ;;
        -h|--help)
            print_usage
            ;;
        -ir|-ri)
            DO_INSTALL=1
            DO_RUN=1
            shift
            ;;
        -id|-di)
            DO_INSTALL=1
            DO_DMG=1
            shift
            ;;
        -ird|-idr|-rid|-rdi|-dir|-dri)
            DO_INSTALL=1
            DO_RUN=1
            DO_DMG=1
            shift
            ;;
        *)
            echo "error: unknown option: $1" >&2
            echo "run '$0 --help' for usage" >&2
            exit 2
            ;;
    esac
done

if [[ "$CONFIG" != "debug" && "$CONFIG" != "release" ]]; then
    echo "error: --config must be debug or release (got '$CONFIG')" >&2
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
INSTALL_PATH="/Applications/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION"
DMG_PATH="$REPO_ROOT/$DMG_NAME.dmg"
ICON_SOURCE="$REPO_ROOT/plans/seshat_agent_bundle/01_Foundations/assets/logo_dark.png"
ICNS_PATH="$REPO_ROOT/$APP_NAME.icns"
GIT_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo 'unknown')"

# --- [1] Build ---
echo "==> Building $BINARY_NAME ($CONFIG)..."
swift build -c "$CONFIG" --product "$BINARY_NAME"

if [[ ! -x "$BUILD_DIR/$BINARY_NAME" ]]; then
    echo "error: expected executable at $BUILD_DIR/$BINARY_NAME not found" >&2
    exit 1
fi

# --- [2] Assemble .app ---
echo "==> Assembling $APP_PATH..."
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"
cp "$BUILD_DIR/$BINARY_NAME" "$APP_PATH/Contents/MacOS/$BINARY_NAME"

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
    <key>CFBundleIconFile</key>
    <string>${APP_NAME}</string>
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
    <key>SeshatGitSHA</key>
    <string>${GIT_SHA}</string>
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

printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"

# --- [3] Generate .icns from master logo ---
# Regenerated every build: cheap (sips is fast on 2048px source) and avoids
# drift between source logo and installed icon. Output `$APP_NAME.icns` lives
# at repo root (.gitignored) so it can be inspected; the canonical copy is
# embedded in `$APP_PATH/Contents/Resources/$APP_NAME.icns` referenced by
# `CFBundleIconFile` in Info.plist.
echo "==> Generating $ICNS_PATH from logo_dark.png..."
if [[ ! -f "$ICON_SOURCE" ]]; then
    echo "error: icon source not found at $ICON_SOURCE" >&2
    exit 1
fi
ICONSET_DIR="$(mktemp -d -t seshat-iconset)/$APP_NAME.iconset"
mkdir -p "$ICONSET_DIR"
# Canonical iconset slots per Apple HIG — iconutil requires these exact names.
# 1x slots: 16, 32, 128, 256, 512.  @2x slots: same sizes, doubled pixels.
for size in 16 32 128 256 512; do
    doubled=$((size * 2))
    sips -z "$size" "$size" "$ICON_SOURCE" \
        --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    sips -z "$doubled" "$doubled" "$ICON_SOURCE" \
        --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"
cp "$ICNS_PATH" "$APP_PATH/Contents/Resources/$APP_NAME.icns"

# --- [4] Sign ---
echo "==> Ad-hoc signing (hardened runtime + mic entitlement)..."
ENTITLEMENTS_PLIST="$(mktemp -t seshat-entitlements.XXXXXX).plist"
cleanup() {
    rm -f "$ENTITLEMENTS_PLIST"
    [[ -n "${STAGING_DIR:-}" ]] && rm -rf "$STAGING_DIR"
    [[ -n "${ICONSET_DIR:-}" ]] && rm -rf "$(dirname "$ICONSET_DIR")"
}
trap cleanup EXIT
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

codesign --verify --verbose "$APP_PATH"

APP_SIZE="$(du -sh "$APP_PATH" | awk '{print $1}')"
echo "✓ Built $APP_PATH ($APP_SIZE)"

# --- [5] DMG (optional) ---
if [[ "$DO_DMG" == "1" ]]; then
    echo ""
    echo "==> Packaging DMG..."
    STAGING_DIR="$(mktemp -d -t seshat-dmg-staging)"
    cp -R "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
    ln -s /Applications "$STAGING_DIR/Applications"
    rm -f "$DMG_PATH"
    hdiutil create \
        -volname "$APP_NAME $VERSION" \
        -srcfolder "$STAGING_DIR" \
        -ov \
        -format UDZO \
        -fs HFS+ \
        "$DMG_PATH" >/dev/null
    hdiutil verify "$DMG_PATH" >/dev/null
    DMG_SIZE="$(du -sh "$DMG_PATH" | awk '{print $1}')"
    echo "✓ Built $DMG_PATH ($DMG_SIZE)"
fi

# --- [6] Install (optional) ---
if [[ "$DO_INSTALL" == "1" ]]; then
    echo ""
    echo "==> Installing to $INSTALL_PATH..."
    osascript -e 'tell application "Seshat" to quit' >/dev/null 2>&1 || true
    sleep 1
    rm -rf "$INSTALL_PATH"
    ditto "$APP_PATH" "$INSTALL_PATH"
    echo "✓ Installed $INSTALL_PATH"
fi

# --- [7] Run (optional) ---
if [[ "$DO_RUN" == "1" ]]; then
    echo ""
    echo "==> Launching $INSTALL_PATH..."
    open "$INSTALL_PATH"
fi

echo ""
if [[ "$DO_INSTALL" != "1" && "$DO_DMG" != "1" ]]; then
    echo "  Launch:  open \"$APP_PATH\""
elif [[ "$DO_DMG" == "1" && "$DO_INSTALL" != "1" ]]; then
    echo "  Install: open \"$DMG_PATH\" → drag $APP_NAME.app into Applications"
fi
echo ""
