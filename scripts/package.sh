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
ICNS_SOURCE="$REPO_ROOT/Sources/SeshatAppKit/Resources/AppIcon.icns"
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

# --- [3] Embed app icon ---
# The canonical `.icns` is a checked-in artifact at
# `Sources/SeshatAppKit/Resources/AppIcon.icns` (has proper RGBA
# transparency around the rounded rect). Earlier revisions auto-
# generated from `logo_dark.png` via sips+iconutil, but that source
# is an RGB-only logo with no alpha — the resulting icon rendered as
# a flat dark square in the Dock/LaunchPad instead of the expected
# rounded-rect-with-transparency. Ship the hand-authored icns.
echo "==> Embedding $ICNS_SOURCE as app icon..."
if [[ ! -f "$ICNS_SOURCE" ]]; then
    echo "error: app icon source not found at $ICNS_SOURCE" >&2
    exit 1
fi
cp "$ICNS_SOURCE" "$APP_PATH/Contents/Resources/$APP_NAME.icns"

# --- [4] Sign ---
# Prefer a stable self-signed identity (`Nitkrar Dev`) if present in
# the login Keychain. Stable identity → TCC permissions persist across
# rebuilds because the TCC database keys signed apps on signing
# identity, not on CD hash. Ad-hoc (`--sign -`) is the fallback for
# fresh clones / other machines that haven't created the cert yet —
# permissions will reset per build on those.
#
# Set up the cert once per machine via:
#   Keychain Access → Certificate Assistant → Create a Certificate…
#   Name: "Nitkrar Dev", Identity Type: Self Signed Root, Type: Code Signing
SIGN_IDENTITY="Nitkrar Dev"
if ! security find-identity -v -p codesigning | grep -q "\"$SIGN_IDENTITY\""; then
    echo "==> '$SIGN_IDENTITY' codesigning identity not found — falling back to ad-hoc."
    echo "    (Permissions will reset each rebuild. Create the cert in Keychain Access"
    echo "    to preserve TCC grants across rebuilds on this machine.)"
    SIGN_IDENTITY="-"
fi
echo "==> Signing with identity: $SIGN_IDENTITY (hardened runtime + mic entitlement)..."
ENTITLEMENTS_PLIST="$(mktemp -t seshat-entitlements.XXXXXX).plist"
cleanup() {
    rm -f "$ENTITLEMENTS_PLIST"
    [[ -n "${STAGING_DIR:-}" ]] && rm -rf "$STAGING_DIR"
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
    --sign "$SIGN_IDENTITY" \
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
