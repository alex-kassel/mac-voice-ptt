#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_SRC="$PROJECT_DIR/build/Dictaphone.app"
DEST_APP="/Applications/Dictaphone.app"

if [ ! -d "$APP_SRC" ]; then
    echo "App bundle not found. Building first..."
    bash "$SCRIPT_DIR/build_app.sh"
fi

echo "-> Stopping any running Dictaphone processes..."
pkill -f "Dictaphone.app/Contents/MacOS/Dictaphone" 2>/dev/null || true
# Also stop old python version if running
launchctl unload "$HOME/Library/LaunchAgents/com.fcc.dictaphone.plist" 2>/dev/null || true
pkill -f "dictaphone/main.py" 2>/dev/null || true
sleep 1

echo "-> Installing to $DEST_APP..."
rm -rf "$DEST_APP"
cp -R "$APP_SRC" "$DEST_APP"

# Remove quarantine attribute if set
xattr -d com.apple.quarantine "$DEST_APP" 2>/dev/null || true

echo "-> Launching $DEST_APP..."
open "$DEST_APP"

echo ""
echo "================================================"
echo " [OK] Dictaphone installed successfully!"
echo "================================================"
echo ""
echo "IMPORTANT: Make sure to grant permissions in macOS:"
echo " 1. System Settings -> Privacy & Security -> Accessibility -> Enable 'Dictaphone'"
echo " 2. System Settings -> Privacy & Security -> Microphone -> Enable 'Dictaphone'"
echo ""
echo "To enable Auto-start on login:"
echo " Click the ◉ icon in the menu bar and check 'Launch at Login'."
echo "================================================"
