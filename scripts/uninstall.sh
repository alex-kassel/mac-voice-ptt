#!/usr/bin/env bash
set -euo pipefail

DEST_APP="/Applications/Dictaphone.app"

echo "================================================"
echo " Uninstalling Dictaphone"
echo "================================================"

echo "-> Stopping Dictaphone..."
pkill -f "Dictaphone.app/Contents/MacOS/Dictaphone" 2>/dev/null || true
sleep 1

if [ -d "$DEST_APP" ]; then
    echo "-> Removing $DEST_APP..."
    rm -rf "$DEST_APP"
fi

echo ""
echo "[OK] Dictaphone has been uninstalled from /Applications."
echo "If you also wish to delete your configuration, run:"
echo "  rm -rf ~/.dictaphone"
