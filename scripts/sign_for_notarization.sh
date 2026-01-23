#!/usr/bin/env bash
set -euo pipefail

# Re-sign app and all embedded frameworks for notarization
# This script properly signs Sparkle framework components with Developer ID

if [ $# -ne 1 ]; then
    echo "Usage: $0 <path-to-DictateGo.app>"
    exit 1
fi

APP_PATH="$1"
IDENTITY="Developer ID Application: John Gleason (9TY9ZN5TFN)"
ENTITLEMENTS="$(dirname "$0")/../DictateGo/DictateGo.entitlements"

echo "Re-signing app for notarization: $APP_PATH"
echo "Using identity: $IDENTITY"

# Sign Sparkle framework components (deepest first)
SPARKLE_FW="$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B"

# Sign XPC services
for xpc in "$SPARKLE_FW/XPCServices"/*.xpc; do
    if [ -d "$xpc" ]; then
        echo "Signing $(basename "$xpc")..."
        codesign --force --sign "$IDENTITY" \
            --options runtime \
            --timestamp \
            "$xpc"
    fi
done

# Sign Updater.app
if [ -d "$SPARKLE_FW/Updater.app" ]; then
    echo "Signing Updater.app..."
    codesign --force --sign "$IDENTITY" \
        --options runtime \
        --timestamp \
        "$SPARKLE_FW/Updater.app"
fi

# Sign Autoupdate binary
if [ -f "$SPARKLE_FW/Autoupdate" ]; then
    echo "Signing Autoupdate..."
    codesign --force --sign "$IDENTITY" \
        --options runtime \
        --timestamp \
        "$SPARKLE_FW/Autoupdate"
fi

# Sign main Sparkle framework
echo "Signing Sparkle.framework..."
codesign --force --sign "$IDENTITY" \
    --options runtime \
    --timestamp \
    "$SPARKLE_FW/Sparkle"

# Sign the main app bundle
echo "Signing DictateGo.app..."
codesign --force --sign "$IDENTITY" \
    --options runtime \
    --timestamp \
    --entitlements "$ENTITLEMENTS" \
    "$APP_PATH"

echo "✅ Signing complete!"
echo ""
echo "Verifying signatures..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo ""
echo "✅ Verification complete!"
