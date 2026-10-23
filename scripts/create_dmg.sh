#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="Dictaphone.app"
APP_BUNDLE="$BUILD_DIR/$APP_NAME"
DMG_PATH="$BUILD_DIR/Dictaphone.dmg"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "App bundle not found. Building app first..."
    bash "$SCRIPT_DIR/build_app.sh"
fi

echo "================================================"
echo " Creating Dictaphone.dmg"
echo "================================================"

DMG_TMP=$(mktemp -d /tmp/dictaphone_dmg.XXXXXX)
trap 'rm -rf "$DMG_TMP"' EXIT

cp -R "$APP_BUNDLE" "$DMG_TMP/"
ln -s /Applications "$DMG_TMP/Applications"

rm -f "$DMG_PATH"

hdiutil create \
    -volname "Dictaphone" \
    -srcfolder "$DMG_TMP" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo ""
echo "[OK] Successfully created DMG: $DMG_PATH"
echo "DMG size: $(du -sh "$DMG_PATH" | cut -f1)"
