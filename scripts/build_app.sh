#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="Dictaphone.app"
APP_BUNDLE="$BUILD_DIR/$APP_NAME"

echo "================================================"
echo " Building Dictaphone macOS Native Application"
echo "================================================"

cd "$PROJECT_DIR"

echo "-> Compiling release binary (Swift)..."
swift build -c release --build-system native

BIN_PATH="$PROJECT_DIR/.build/arm64-apple-macosx/release/Dictaphone"
if [ ! -f "$BIN_PATH" ]; then
    # Fallback to whatever release target was built
    BIN_PATH=$(find "$PROJECT_DIR/.build" -type f -name "Dictaphone" -perm +111 | grep "release" | head -n 1)
fi

echo "-> Assembling $APP_NAME bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/Dictaphone"
chmod +x "$APP_BUNDLE/Contents/MacOS/Dictaphone"

# Copy Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Code signing with stable Designated Requirement so macOS TCC doesn't lose permissions on rebuild
echo "-> Signing $APP_NAME with stable designated requirement..."
codesign --force --deep --sign - --requirements '=designated => identifier "com.fcc.Dictaphone"' "$APP_BUNDLE"

echo ""
echo "[OK] Successfully built: $APP_BUNDLE"
echo "Binary size: $(du -sh "$APP_BUNDLE" | cut -f1)"
