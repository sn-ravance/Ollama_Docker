#!/usr/bin/env bash
set -euo pipefail

# Placeholder extractor for oauth2-proxy cookie from Safari on macOS.
# Safari stores cookies in a system-protected BinaryCookies/WebKit store that
# requires special tooling and entitlements to read. We do not ship those.
#
# Behavior:
# - Always exits non-zero with a clear message explaining manual steps.
# - Keeps interface compatible with the Chrome helper so the caller can fall back.
#
# Usage:
#   scripts/extract-cookie-macos-safari.sh [cookie_name] [host]
# Defaults:
#   cookie_name = _oauth2_proxy
#   host        = api.localhost
# Output:
#   None (stderr explains alternatives). Non-zero exit status.

COOKIE_NAME=${1:-_oauth2_proxy}
HOST=${2:-api.localhost}

err() { echo "[cookie:safari][ERROR] $*" >&2; exit 2; }

err "Safari cookie extraction is not supported by this repo (WebKit cookie store is protected).\n\nManual options:\n  1) Open https://localhost/login in Safari and sign in.\n  2) Safari → Develop → Show Web Inspector → Storage → Cookies → domain api.localhost or localhost.\n  3) Copy the cookie named '${COOKIE_NAME}' and use one of:\n     - Inline: COOKIE='${COOKIE_NAME}=...'
     - File:   echo '${COOKIE_NAME}=...' > /tmp/ollama_zta_cookie.txt; export COOKIE_FILE=/tmp/ollama_zta_cookie.txt\n\nAlternatively, use Chrome auto-extraction: --auto-cookie=chrome (if permitted)."
