#!/usr/bin/env bash
set -euo pipefail

# Build and package DictateGo for distribution
# This script creates a properly signed, notarized release

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

# Configuration
SCHEME="DictateGo"
CONFIGURATION="Release"
DERIVED_DATA="$PROJECT_DIR/build/DerivedData"
BUILD_DIR="$DERIVED_DATA/Build/Products/$CONFIGURATION"
DIST_DIR="$PROJECT_DIR/dist"
IDENTITY="Developer ID Application: John Gleason (9TY9ZN5TFN)"

# Get version from Info.plist
VERSION=$(defaults read "$PROJECT_DIR/DictateGo/Info.plist" CFBundleShortVersionString)
BUILD_NUMBER=$(defaults read "$PROJECT_DIR/DictateGo/Info.plist" CFBundleVersion)

echo "Building DictateGo $VERSION (build $BUILD_NUMBER)..."

# Clean and build
xcodebuild clean build \
  -project DictateGo.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA"

# Create distribution directory
mkdir -p "$DIST_DIR"

# Package as zip
APP_PATH="$BUILD_DIR/DictateGo.app"
ZIP_NAME="DictateGo-$VERSION.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

echo "Creating $ZIP_NAME..."
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

# Verify code signature
echo "Verifying code signature..."
codesign --verify --deep --strict "$APP_PATH"
spctl -a -vv "$APP_PATH" || echo "Warning: App is not notarized"

echo ""
echo "✅ Build complete!"
echo "   App: $APP_PATH"
echo "   Zip: $ZIP_PATH"
echo ""
echo "Next steps:"
echo "1. Notarize the app: xcrun notarytool submit \"$ZIP_PATH\" --keychain-profile \"notarytool-profile\" --wait"
echo "2. Staple the ticket: xcrun stapler staple \"$APP_PATH\""
echo "3. Re-create zip: ditto -c -k --sequesterRsrc --keepParent \"$APP_PATH\" \"$ZIP_PATH\""
echo "4. Generate appcast: ./scripts/generate_appcast.sh"
echo "5. Upload to GitHub releases"
