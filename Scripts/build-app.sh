#!/bin/zsh
# Assembles "Ground Control.app" from the SwiftPM build products.
# Usage: Scripts/build-app.sh [release|debug]   (default: release)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Ground Control.app"

echo "▸ Building ($CONFIG)…"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

echo "▸ Assembling ${APP}..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/GroundControl" "$APP/Contents/MacOS/GroundControl"
if [[ -f "$BIN_DIR/gc-mcp" ]]; then
    cp "$BIN_DIR/gc-mcp" "$APP/Contents/MacOS/gc-mcp"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

echo "▸ Signing (ad-hoc)…"
# Inner binaries first, then the bundle.
if [[ -f "$APP/Contents/MacOS/gc-mcp" ]]; then
    codesign --force --sign - "$APP/Contents/MacOS/gc-mcp"
fi
codesign --force --sign - --entitlements "Resources/GroundControl.entitlements" "$APP"

echo "✓ $APP"
