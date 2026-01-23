#!/usr/bin/env bash
set -euo pipefail

# Create a styled DMG for DictateGo distribution
# Usage: ./scripts/create_dmg.sh <path-to-app> <version>

APP_PATH="${1:-}"
VERSION="${2:-}"

if [[ -z "$APP_PATH" || -z "$VERSION" ]]; then
    echo "Usage: $0 <path-to-DictateGo.app> <version>"
    echo "Example: $0 build/DerivedData/Build/Products/Release/DictateGo.app 2.0.1"
    exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "Error: App not found at $APP_PATH"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$PROJECT_DIR/dist"
DMG_NAME="DictateGo-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGING_DIR="$BUILD_DIR/dmg-staging-${VERSION}"
BACKGROUND_DIR="$BUILD_DIR/dmg-background"

echo "Creating DMG for DictateGo $VERSION..."

# Clean up
rm -rf "$STAGING_DIR"
rm -f "$DMG_PATH"
mkdir -p "$STAGING_DIR"
mkdir -p "$DIST_DIR"

# Copy app to staging
echo "Copying app..."
cp -R "$APP_PATH" "$STAGING_DIR/"

# Create Applications symlink
ln -s /Applications "$STAGING_DIR/Applications"

# Copy background
mkdir -p "$STAGING_DIR/.background"
cp "$BACKGROUND_DIR/background.png" "$STAGING_DIR/.background/"

# Copy DS_Store for icon layout
cp "$BACKGROUND_DIR/DS_Store" "$STAGING_DIR/.DS_Store"

# Create temporary DMG
TEMP_DMG="$BUILD_DIR/temp-${VERSION}.dmg"
echo "Creating temporary DMG..."
hdiutil create -srcfolder "$STAGING_DIR" -volname "DictateGo" -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" -format UDRW "$TEMP_DMG"

# Convert to compressed DMG
echo "Converting to compressed DMG..."
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"
rm -f "$TEMP_DMG"

# Clean up staging
rm -rf "$STAGING_DIR"

echo ""
echo "✅ DMG created: $DMG_PATH"
ls -lh "$DMG_PATH"
