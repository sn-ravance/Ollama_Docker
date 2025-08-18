#!/usr/bin/env bash
set -euo pipefail

# fetch-oidc-token.sh
# Device Code flow helper for Azure Entra ID (generic OIDC compatible with oauth2-proxy)
# - Reads OIDC_CLIENT_ID and OIDC_ISSUER_URL from .env
# - Requests device code, prompts user to verify, polls token endpoint
# - Prints tokens and can emit just the access or ID token for piping
#
# Usage examples:
#   ./scripts/fetch-oidc-token.sh                      # interactive; prints both tokens
#   ./scripts/fetch-oidc-token.sh --print-access-token # prints only access token
#   ./scripts/fetch-oidc-token.sh --print-id-token     # prints only id token
#   TOKEN=$(./scripts/fetch-oidc-token.sh --print-access-token) \
#     && curl -k -H "Authorization: Bearer $TOKEN" https://localhost/api/tags
#
# Notes:
# - Default scopes: "openid profile email offline_access"
# - For Entra ID, OIDC_ISSUER_URL example:
#     https://login.microsoftonline.com/<tenant-id>/v2.0
# - This script requires Python 3 for minimal JSON parsing (avoids jq dependency).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC2046
  export $(grep -E '^(OIDC_CLIENT_ID|OIDC_CLIENT_SECRET|OIDC_ISSUER_URL)=' "$ROOT_DIR/.env" | xargs) || true
fi

OIDC_CLIENT_ID=${OIDC_CLIENT_ID:-}
OIDC_CLIENT_SECRET=${OIDC_CLIENT_SECRET:-}
OIDC_ISSUER_URL=${OIDC_ISSUER_URL:-}
SCOPES="openid profile email offline_access"
PRINT_MODE="all" # all|access|id

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope|--scopes)
      shift
      SCOPES="$1"
      ;;
    --print-access-token)
      PRINT_MODE="access"
      ;;
    --print-id-token)
      PRINT_MODE="id"
      ;;
    -h|--help)
      sed -n '1,80p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2; exit 1
      ;;
  esac
  shift
done

if [[ -z "$OIDC_CLIENT_ID" || -z "$OIDC_ISSUER_URL" ]]; then
  echo "ERROR: OIDC_CLIENT_ID and OIDC_ISSUER_URL must be set (see .env.example)." >&2
  exit 2
fi

# Derive Entra endpoints from issuer
# issuer e.g. https://login.microsoftonline.com/<tenant>/v2.0
BASE="${OIDC_ISSUER_URL%/v2.0}"
DEVICE_ENDPOINT="$BASE/oauth2/v2.0/devicecode"
TOKEN_ENDPOINT="$BASE/oauth2/v2.0/token"

# Request device code
DEVICE_JSON=$(curl -fsS -X POST "$DEVICE_ENDPOINT" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "client_id=$OIDC_CLIENT_ID" \
  --data-urlencode "scope=$SCOPES")

if [[ -z "$DEVICE_JSON" ]]; then
  echo "Failed to contact device endpoint (empty response). Check network and OIDC_ISSUER_URL." >&2
  exit 3
fi
if command -v jq >/dev/null 2>&1; then
  user_code=$(printf '%s' "$DEVICE_JSON" | jq -r '.user_code // empty')
  verification_uri=$(printf '%s' "$DEVICE_JSON" | jq -r '.verification_uri // .verification_uri_complete // empty')
  device_code=$(printf '%s' "$DEVICE_JSON" | jq -r '.device_code // empty')
  interval=$(printf '%s' "$DEVICE_JSON" | jq -r '.interval // 5')
  expires_in=$(printf '%s' "$DEVICE_JSON" | jq -r '.expires_in // 900')
else
  user_code=$(python3 - <<'PY'
import sys, json
try:
  j=json.load(sys.stdin)
  print(j.get('user_code',''))
except Exception:
  print('')
PY
<<<"$DEVICE_JSON")
  verification_uri=$(python3 - <<'PY'
import sys, json
try:
  j=json.load(sys.stdin)
  print(j.get('verification_uri','') or j.get('verification_uri_complete',''))
except Exception:
  print('')
PY
<<<"$DEVICE_JSON")
  device_code=$(python3 - <<'PY'
import sys, json
try:
  j=json.load(sys.stdin)
  print(j.get('device_code',''))
except Exception:
  print('')
PY
<<<"$DEVICE_JSON")
  interval=$(python3 - <<'PY'
import sys, json
try:
  j=json.load(sys.stdin)
  print(j.get('interval',5))
except Exception:
  print(5)
PY
<<<"$DEVICE_JSON")
  expires_in=$(python3 - <<'PY'
import sys, json
try:
  j=json.load(sys.stdin)
  print(j.get('expires_in',900))
except Exception:
  print(900)
PY
<<<"$DEVICE_JSON")
fi

if [[ -z "$device_code" ]]; then
  echo "Failed to start device code flow (no device_code in response). Raw response:" >&2
  echo "$DEVICE_JSON" >&2
  exit 3
fi

cat <<MSG
Please complete sign-in:
  Visit: $verification_uri
  Code:  $user_code
Waiting for authorization...
MSG

# Poll token endpoint
START=$(date +%s)
ACCESS_TOKEN=""
ID_TOKEN=""
while true; do
  now=$(date +%s)
  if (( now - START > expires_in )); then
    echo "Device code expired before authorization." >&2
    exit 4
  fi
  # NOTE: do NOT use -f here; Azure returns HTTP 400 with useful JSON bodies
  RESP=$(curl -sS -X POST "$TOKEN_ENDPOINT" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode "grant_type=urn:ietf:params:oauth:grant-type:device_code" \
    --data-urlencode "client_id=$OIDC_CLIENT_ID" \
    --data-urlencode "device_code=$device_code" \
    ${OIDC_CLIENT_SECRET:+--data-urlencode "client_secret=$OIDC_CLIENT_SECRET"} || true)

  # If still pending, server returns error=authorization_pending
  if echo "$RESP" | grep -q 'authorization_pending'; then
    sleep "$interval"
    continue
  fi

  # If slow_down suggested, wait extra
  if echo "$RESP" | grep -q 'slow_down'; then
    sleep "$((interval+2))"
    continue
  fi

  # Try to parse tokens
  ACCESS_TOKEN=$(python3 - <<'PY'
import sys, json
try:
  j=json.load(sys.stdin)
  print(j.get('access_token',''))
except Exception:
  print('')
PY
<<<"$RESP")
  ID_TOKEN=$(python3 - <<'PY'
import sys, json
try:
  j=json.load(sys.stdin)
  print(j.get('id_token',''))
except Exception:
  print('')
PY
<<<"$RESP")

  if [[ -n "$ACCESS_TOKEN" || -n "$ID_TOKEN" ]]; then
    break
  fi

  # Some other error
  echo "Authorization failed or unexpected response:" >&2
  if [[ -z "$RESP" ]]; then
    echo "(empty response from token endpoint; check network or issuer URL)" >&2
  else
    echo "$RESP" >&2
    if echo "$RESP" | grep -q 'authorization_declined'; then
      echo "User declined authorization." >&2
    elif echo "$RESP" | grep -q 'expired_token'; then
      echo "Device code expired; re-run the script to get a new code." >&2
    elif echo "$RESP" | grep -q 'bad_verification_code'; then
      echo "Incorrect code entered; re-run and enter the shown code exactly." >&2
    fi
  fi
  exit 5
done

case "$PRINT_MODE" in
  access)
    [[ -n "$ACCESS_TOKEN" ]] && echo "$ACCESS_TOKEN" || { echo "No access token returned" >&2; exit 6; }
    ;;
  id)
    [[ -n "$ID_TOKEN" ]] && echo "$ID_TOKEN" || { echo "No id token returned" >&2; exit 6; }
    ;;
  all)
    echo "ACCESS_TOKEN=$ACCESS_TOKEN"
    echo "ID_TOKEN=$ID_TOKEN"
    ;;
esac
