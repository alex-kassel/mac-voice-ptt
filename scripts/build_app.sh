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

# Ad-hoc code signing (allows macOS to identify and store Accessibility/Mic permissions per bundle)
echo "-> Signing $APP_NAME..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "[OK] Successfully built: $APP_BUNDLE"
echo "Binary size: $(du -sh "$APP_BUNDLE" | cut -f1)"
