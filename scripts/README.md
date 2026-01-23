Sparkle appcast workflow

1) Keys are already generated for this repo:
   - Private key: ./keys/sparkle_ed25519_private_key.pem
   - Public key in DictateGo/Info.plist (SUPublicEDKey)

2) Build a release and export a .dmg or .zip into ./dist/.

3) Generate the appcast:
   DOWNLOAD_URL_PREFIX=https://example.com/DictateGo/releases/ \
   ./scripts/generate_appcast.sh dist appcast.xml
