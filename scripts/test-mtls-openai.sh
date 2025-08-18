#!/usr/bin/env bash
set -euo pipefail

# Simple end-to-end test for the mTLS gateway and OpenAI-compatible routes.
# - Verifies hosts entry
# - Probes portal health
# - Probes mTLS health (with/without cert)
# - Lists models via /api and /v1
# - Runs a sample /api/generate and /v1/chat/completions

# Note:
# In full mode, the API at https://api.localhost requires BOTH mTLS and an active OIDC session.
# This script does NOT manage your browser OIDC session/cookies. If you are not logged in,
# calls may return 302 (redirect to login) or 401/403. In that case, first complete login at
# https://localhost/login and retry. For mTLS-only mode, start stack with: ./start.sh mtls

PASS=0; FAIL=0
note() { echo -e "[test] $*"; }
pass() { echo -e "[PASS] $*"; ((PASS++)) || true; }
fail() { echo -e "[FAIL] $*"; ((FAIL++)) || true; }

# Config
API_HOST=${API_HOST:-api.localhost}
PORTAL_HOST=${PORTAL_HOST:-localhost}
CERT=${CERT:-certs/client-cert.pem}
KEY=${KEY:-certs/client-key.pem}
CA=${CA:-certs/ca-cert.pem}
MODEL=${MODEL:-mistral}
# Optional OIDC session cookie for full mode (e.g., "_oauth2_proxy=..."), or cookie file path
COOKIE=${COOKIE:-}
COOKIE_FILE=${COOKIE_FILE:-}

# Optional: auto-extract cookie on macOS from supported browsers
# Usage: --auto-cookie=chrome|safari
AUTO_COOKIE=""
for arg in "$@"; do
  case "$arg" in
    --auto-cookie=chrome)
      AUTO_COOKIE="chrome";;
    --auto-cookie=safari)
      AUTO_COOKIE="safari";;
  esac
done

if [[ -z "$COOKIE_FILE" && -z "$COOKIE" && -n "$AUTO_COOKIE" ]]; then
  case "$AUTO_COOKIE" in
    chrome)
      if [[ -x "scripts/extract-cookie-macos-chrome.sh" ]]; then
        note "Attempting auto cookie extraction from Chrome..."
        if COOKIE_FILE_PATH=$(scripts/extract-cookie-macos-chrome.sh _oauth2_proxy "$API_HOST" 2>/dev/null); then
          COOKIE_FILE="$COOKIE_FILE_PATH"
          note "Using COOKIE_FILE=$COOKIE_FILE"
        else
          note "Chrome auto-extract failed; continuing without cookie."
        fi
      else
        note "Helper scripts/extract-cookie-macos-chrome.sh not found or not executable."
      fi
      ;;
    safari)
      if [[ -x "scripts/extract-cookie-macos-safari.sh" ]]; then
        note "Attempting auto cookie extraction from Safari..."
        if COOKIE_FILE_PATH=$(scripts/extract-cookie-macos-safari.sh _oauth2_proxy "$API_HOST" 2>/dev/null); then
          COOKIE_FILE="$COOKIE_FILE_PATH"
          note "Using COOKIE_FILE=$COOKIE_FILE"
        else
          note "Safari auto-extract unavailable or failed; continuing without cookie."
        fi
      else
        note "Helper scripts/extract-cookie-macos-safari.sh not found or not executable."
      fi
      ;;
  esac
fi

has_jq() { command -v jq >/dev/null 2>&1; }
http_code() { "${curl_base[@]}" "$@" -o /dev/null -w "%{http_code}\n"; }

curl_base=(curl -sS -k)
# Append cookie options if provided
if [[ -n "$COOKIE_FILE" ]]; then
  curl_base+=("-b" "$COOKIE_FILE")
elif [[ -n "$COOKIE" ]]; then
  curl_base+=("-b" "$COOKIE")
fi
with_cert=("--cert" "$CERT" "--key" "$KEY" "--cacert" "$CA")

require_file() {
  local f=$1
  if [[ ! -f "$f" ]]; then
    fail "Missing file: $f"
    exit 1
  fi
}

note "Checking required files..."
require_file "$CERT"; require_file "$KEY"; require_file "$CA"
pass "Certs present"

note "Checking /etc/hosts entry for $API_HOST..."
if grep -qE "\s$API_HOST(\s|$)" /etc/hosts; then
  pass "$API_HOST found in /etc/hosts"
else
  fail "$API_HOST not found in /etc/hosts (add: 127.0.0.1 $API_HOST)"
fi

note "Probing portal health (no cert): https://$PORTAL_HOST/healthz"
if "${curl_base[@]}" -o /dev/null -w "%{http_code}\n" "https://$PORTAL_HOST/healthz" | grep -q "^200$"; then
  pass "Portal health OK"
else
  fail "Portal health failed"
fi

note "Probing mTLS health without cert (expected to fail handshake) https://$API_HOST/healthz"
if "${curl_base[@]}" -o /dev/null -w "%{http_code}\n" "https://$API_HOST/healthz" >/dev/null 2>&1; then
  note "Received an HTTP code without cert; this is unexpected but may vary by client"
else
  pass "Handshake failed as expected without cert"
fi

note "Probing mTLS health with cert: https://$API_HOST/healthz"
if "${curl_base[@]}" "${with_cert[@]}" -o /dev/null -w "%{http_code}\n" "https://$API_HOST/healthz" | grep -q "^200$"; then
  pass "mTLS health OK"
else
  fail "mTLS health failed with cert"
fi

note "Listing models via native API: https://$API_HOST/api/tags"
code=$(http_code "${with_cert[@]}" "https://$API_HOST/api/tags") || code="000"
case "$code" in
  200)
    if has_jq; then
      if "${curl_base[@]}" "${with_cert[@]}" "https://$API_HOST/api/tags" | jq . >/dev/null; then
        pass "/api/tags returned JSON"
      else
        fail "/api/tags returned non-JSON or parse error"
      fi
    else
      pass "/api/tags HTTP 200"
    fi
    ;;
  302)
    fail "/api/tags returned 302 (OIDC login required). Login at https://$PORTAL_HOST/login then retry."
    ;;
  401|403)
    fail "/api/tags returned $code (mTLS or OIDC missing). Ensure client cert is used and OIDC session is active in full mode."
    ;;
  *)
    fail "/api/tags unexpected HTTP code: $code"
    ;;
esac

note "Listing models via OpenAI-compatible: https://$API_HOST/v1/models"
code=$(http_code "${with_cert[@]}" "https://$API_HOST/v1/models") || code="000"
case "$code" in
  200)
    if has_jq; then
      if "${curl_base[@]}" "${with_cert[@]}" "https://$API_HOST/v1/models" | jq . >/dev/null; then
        pass "/v1/models returned JSON"
      else
        fail "/v1/models returned non-JSON or parse error"
      fi
    else
      pass "/v1/models HTTP 200"
    fi
    ;;
  302)
    fail "/v1/models returned 302 (OIDC login required). Login at https://$PORTAL_HOST/login then retry."
    ;;
  401|403)
    fail "/v1/models returned $code (mTLS or OIDC missing). Ensure client cert is used and OIDC session is active in full mode."
    ;;
  *)
    fail "/v1/models unexpected HTTP code: $code"
    ;;
esac

note "Generating via native API: https://$API_HOST/api/generate (model=$MODEL)"
code=$(http_code "${with_cert[@]}" "https://$API_HOST/api/generate") || code="000"
case "$code" in
  200)
    if has_jq; then
      if "${curl_base[@]}" "${with_cert[@]}" -X POST \
        -H 'Content-Type: application/json' \
        -d "{\"model\":\"$MODEL\",\"prompt\":\"Explain zero-trust in simple terms.\"}" \
        "https://$API_HOST/api/generate" | jq . >/dev/null; then
        pass "/api/generate returned JSON"
      else
        fail "/api/generate returned non-JSON or parse error"
      fi
    else
      pass "/api/generate HTTP 200"
    fi
    ;;
  302)
    fail "/api/generate returned 302 (OIDC login required). Login at https://$PORTAL_HOST/login then retry."
    ;;
  401|403)
    fail "/api/generate returned $code (mTLS or OIDC missing). Ensure client cert is used and OIDC session is active in full mode."
    ;;
  *)
    fail "/api/generate unexpected HTTP code: $code"
    ;;
esac

note "Generating via OpenAI-compatible: https://$API_HOST/v1/chat/completions (model=$MODEL)"
code=$(http_code "${with_cert[@]}" "https://$API_HOST/v1/chat/completions") || code="000"
case "$code" in
  200)
    if has_jq; then
      if "${curl_base[@]}" "${with_cert[@]}" -X POST \
        -H 'Content-Type: application/json' \
        -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Explain zero-trust in simple terms.\"}]}" \
        "https://$API_HOST/v1/chat/completions" | jq . >/dev/null; then
        pass "/v1/chat/completions returned JSON"
      else
        fail "/v1/chat/completions returned non-JSON or parse error"
      fi
    else
      pass "/v1/chat/completions HTTP 200"
    fi
    ;;
  302)
    fail "/v1/chat/completions returned 302 (OIDC login required). Login at https://$PORTAL_HOST/login then retry."
    ;;
  401|403)
    fail "/v1/chat/completions returned $code (mTLS or OIDC missing). Ensure client cert is used and OIDC session is active in full mode."
    ;;
  *)
    fail "/v1/chat/completions unexpected HTTP code: $code"
    ;;
esac

note "Results: PASS=$PASS FAIL=$FAIL"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
