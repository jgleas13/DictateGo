# DictateGo Release Workflow

## Prerequisites

1. **Apple Developer Account** with Developer ID certificates
2. **Notarization credentials** configured
3. **Sparkle Ed25519 keys** generated (already done)

## Step-by-Step Release Process

### 1. Build Release

```bash
cd /Users/johngleason/Projects/DictateGo-recovered

# Build with Release configuration
xcodebuild clean build \
  -project DictateGo.xcodeproj \
  -scheme DictateGo \
  -configuration Release

# App location:
# ~/Library/Developer/Xcode/DerivedData/DictateGo-*/Build/Products/Release/DictateGo.app
```

### 2. Notarize with Apple (CRITICAL)

```bash
# Set up notarization credentials (one-time setup)
xcrun notarytool store-credentials "notary-profile" \
  --apple-id "your-apple-id@example.com" \
  --team-id "9TY9ZN5TFN" \
  --password "app-specific-password"

# Create ZIP for notarization
ditto -c -k --sequesterRsrc --keepParent \
  ~/Library/Developer/Xcode/DerivedData/DictateGo-*/Build/Products/Release/DictateGo.app \
  /tmp/DictateGo-for-notarization.zip

# Submit for notarization (takes 1-5 minutes)
xcrun notarytool submit /tmp/DictateGo-for-notarization.zip \
  --keychain-profile "notary-profile" \
  --wait

# If successful, staple the ticket to the app
xcrun stapler staple ~/Library/Developer/Xcode/DerivedData/DictateGo-*/Build/Products/Release/DictateGo.app

# Verify notarization
spctl -a -vv ~/Library/Developer/Xcode/DerivedData/DictateGo-*/Build/Products/Release/DictateGo.app
# Should say: "source=Notarized Developer ID"
```

### 3. Create Distribution ZIP

```bash
# NOW create the final ZIP (after notarization)
mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent \
  ~/Library/Developer/Xcode/DerivedData/DictateGo-*/Build/Products/Release/DictateGo.app \
  dist/DictateGo-X.Y.Z.zip
```

### 4. Generate Sparkle Signature

```bash
# Generate appcast with Ed25519 signature
DOWNLOAD_URL_PREFIX=https://github.com/jgleas13/DictateGo/releases/download/VX.Y.Z/ \
  ./scripts/generate_appcast.sh dist appcast-new.xml

# The signature will be in appcast-new.xml
```

### 5. Upload to GitHub Releases

```bash
# Create release and upload ZIP
gh release create VX.Y.Z dist/DictateGo-X.Y.Z.zip \
  --title "vX.Y.Z" \
  --notes "Release notes here"
```

### 6. Update Appcast Feed

```bash
# Update gh-pages branch
cd /Users/johngleason/Projects/DictateGo-recovered-gh-pages
cp ../appcast-new.xml appcast.xml
git add appcast.xml
git commit -m "Release vX.Y.Z"
git push origin gh-pages
```

## Why Notarization is Required

1. **Security**: Apple verifies the app doesn't contain malware
2. **Gatekeeper**: Prevents "unidentified developer" warnings
3. **Sparkle Validation**: Sparkle checks notarization status
4. **Signature Integrity**: Notarization ticket becomes part of the signature chain

## Troubleshooting

### "EdDSA signature does not match"
- Cause: ZIP created BEFORE notarization
- Fix: Always notarize first, then create ZIP

### "App is not notarized"
- Cause: Missing `xcrun notarytool` step
- Fix: Follow step 2 above

### "Gatekeeper blocks update"
- Cause: Notarization ticket not stapled
- Fix: Run `xcrun stapler staple`

## For Testing Without Notarization

For local testing ONLY (not for distribution):

```bash
# Disable Gatekeeper for testing (NOT recommended for production)
sudo spctl --master-disable

# Test update locally
# Re-enable after testing:
sudo spctl --master-enable
```

## Notes

- Notarization requires an **App-Specific Password** from Apple
- Each notarization submission takes 1-5 minutes
- The notarization ticket is embedded in the app bundle
- The ZIP must be created AFTER stapling the ticket
- The Ed25519 signature is generated from the final ZIP
