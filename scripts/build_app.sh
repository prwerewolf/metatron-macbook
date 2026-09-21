#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "=========================================="
echo "  Building Metatron for macOS (Apple M4 Max)"
echo "=========================================="

APP_NAME="Metatron"
BUILD_CONFIG="release"

# 1. Compile Swift executable
echo "Compiling Swift executable ($BUILD_CONFIG)..."
swift build -c "$BUILD_CONFIG"

EXECUTABLE_PATH="$DIR/.build/$BUILD_CONFIG/$APP_NAME"
APP_BUNDLE="$DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# 2. Recreate .app bundle structure
echo "Packaging $APP_NAME.app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 3. Copy binary
cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# 4. Copy Info.plist
cp "$DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

# 5. Copy local MLX daemon to resources
cp "$DIR/daemon/whisper_daemon.py" "$RESOURCES_DIR/whisper_daemon.py"
chmod +x "$RESOURCES_DIR/whisper_daemon.py"

# 6. Copy AppIcon.icns
if [ -f "$DIR/Resources/AppIcon.icns" ]; then
    cp "$DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# 7. Ad-hoc codesign the bundle
echo "Codesigning bundle with ad-hoc signature..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "=========================================="
echo "  Successfully built: $APP_BUNDLE"
echo "=========================================="
