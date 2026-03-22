#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/app/ClaudeGuardian"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="ClaudeGuardian"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "╔══════════════════════════════════════╗"
echo "║     Building ClaudeGuardian.app      ║"
echo "╚══════════════════════════════════════╝"
echo ""

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Create .app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/hook"

# Step 1: Compile Swift
echo "[1/4] Compiling Swift sources..."
swiftc -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    "$SRC_DIR/Sources/main.swift" \
    "$SRC_DIR/Sources/sprites.swift" \
    -framework Cocoa \
    -framework SwiftUI \
    -framework Network \
    -O 2>&1
echo "  ✓ Binary compiled"

# Step 2: Copy Info.plist
echo "[2/4] Copying Info.plist..."
cp "$SRC_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
echo "  ✓ Info.plist copied"

# Step 3: Bundle resources (hooks + default config)
echo "[3/4] Bundling resources..."
cp "$SCRIPT_DIR/hook/"*.py "$APP_BUNDLE/Contents/Resources/hook/"
cp "$SCRIPT_DIR/guardian.config.json" "$APP_BUNDLE/Contents/Resources/guardian.config.json"
cp "$SCRIPT_DIR/post-install.sh" "$APP_BUNDLE/Contents/Resources/post-install.sh"
chmod +x "$APP_BUNDLE/Contents/Resources/post-install.sh"
chmod +x "$APP_BUNDLE/Contents/Resources/hook/"*.py
echo "  ✓ Hooks and config bundled"

# Step 4: Create zip for distribution
echo "[4/4] Creating distribution zip..."
cd "$BUILD_DIR"
zip -r "$APP_NAME.zip" "$APP_NAME.app" -x "*.DS_Store"
cd "$SCRIPT_DIR"

ZIP_SIZE=$(du -h "$BUILD_DIR/$APP_NAME.zip" | cut -f1)
SHA=$(shasum -a 256 "$BUILD_DIR/$APP_NAME.zip" | cut -d' ' -f1)

echo ""
echo "╔══════════════════════════════════════╗"
echo "║          Build Complete!             ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "  App:    $APP_BUNDLE"
echo "  Zip:    $BUILD_DIR/$APP_NAME.zip ($ZIP_SIZE)"
echo "  SHA256: $SHA"
echo ""
echo "  Next steps:"
echo "    1. Upload $BUILD_DIR/$APP_NAME.zip as a GitHub release asset"
echo "    2. Update the SHA256 in your Homebrew cask formula"
echo ""
