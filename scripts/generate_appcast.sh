#!/usr/bin/env bash
set -euo pipefail

DEFAULT_TOOL="generate_appcast"
LOCAL_TOOL="/Users/johngleason/Tools/bin/generate_appcast"
if [[ -x "${LOCAL_TOOL}" ]]; then
  DEFAULT_TOOL="${LOCAL_TOOL}"
fi
SPARKLE_TOOL="${SPARKLE_TOOL:-${DEFAULT_TOOL}}"
RELEASE_DIR="${1:-dist}"
APPCAST_PATH="${2:-appcast.xml}"
ED_KEY_FILE="${ED_KEY_FILE:-./keys/sparkle_ed25519_private_key.pem}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://example.com/DictateGo/releases/}"

if ! command -v "${SPARKLE_TOOL}" >/dev/null 2>&1; then
  echo "Sparkle tool '${SPARKLE_TOOL}' not found. Install Sparkle's 'generate_appcast' and retry." >&2
  exit 1
fi

if [[ ! -f "${ED_KEY_FILE}" ]]; then
  echo "Missing Ed25519 private key at ${ED_KEY_FILE}." >&2
  exit 1
fi

"${SPARKLE_TOOL}" \
  --ed-key-file "${ED_KEY_FILE}" \
  --download-url-prefix "${DOWNLOAD_URL_PREFIX}" \
  -o "${APPCAST_PATH}" \
  "${RELEASE_DIR}"

echo "Wrote appcast to ${APPCAST_PATH}"
