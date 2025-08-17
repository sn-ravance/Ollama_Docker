#!/usr/bin/env bash
set -Eeuo pipefail

# ------------------------------------------------------------------------------
# Ollama Zero-Trust Gateway — Azure Entra ID (OIDC) Diagnostic Script
# Checks Docker services, TLS/mTLS, oauth2-proxy env, Azure issuer metadata,
# NGINX health, OIDC redirects, and optional Ollama API call through the gateway.
# ------------------------------------------------------------------------------
#
# Purpose:
# A self‑contained Bash diagnostic script that validates your Azure Entra ID (OIDC) + oauth2‑proxy + NGINX + Ollama setup on a single PC. It checks:
# Docker services and network exposure
# TLS/mTLS certs & chain
# oauth2‑proxy environment and Azure Issuer metadata
# NGINX health, OIDC redirect, and auth gate behavior
# Basic end‑to‑end call to the Ollama API (optional, with client certs)
#
# To run:
# chmod +x diagnose-ollama-oidc.sh
#
# ./diagnose-ollama-oidc.sh \
#   --env ./.env \
#   --cert ./certs/client-cert.pem \
#   --key  ./certs/client-key.pem \
#   --cacert ./certs/ca-cert.pem
#
# Flags (all optional):
# --env : path to your .env file (default: ./.env)
# --cert|--key|--cacert : client/CA certs for mTLS to NGINX
# --host : gateway host (default: localhost)
# --port : gateway port (default: 443)
# --timeout : HTTP timeout seconds (default: 10)
# 
# What this script tells you
# 
# Container health: Confirms ollama, nginx, and oauth2-proxy are up and healthy.
# TLS/mTLS: Verifies port 443, checks server handshake (and client cert if provided).
# OIDC config: Ensures OIDC_CLIENT_ID/SECRET, OIDC_ISSUER_URL, cookie secret, and redirect URI exist.
# Azure discovery: Pulls the .well-known/openid-configuration from your tenant and checks that the returned issuer aligns with your configured OIDC_ISSUER_URL.
# Auth gate behavior: Calls /api/tags and interprets 200/302/401/403 to pinpoint whether mTLS or OIDC is blocking you.
# End‑to‑end: Optionally hits /api/generate through NGINX with your client cert to prove the full path.
#
# Tips for Interpreting Results
#
# 302 on /api/* → You likely need to complete the OIDC login in a browser (https://localhost).
# 401/403 on /api/* → mTLS cert not presented/valid, or OIDC session missing/expired.
# Issuer mismatch warning → Revisit OIDC_ISSUER_URL (use https://login.microsoftonline.com/<tenant-id>/v2.0).
# Cannot reach discovery → Check outbound connectivity to Microsoft endpoints or corporate proxy configuration.

# Defaults
ENV_FILE="./.env"
HOST="localhost"
PORT="443"
CLIENT_CERT=""
CLIENT_KEY=""
CA_CERT=""
TIMEOUT="10"

# Colors
ok()    { printf "\033[32m✔ %s\033[0m\n" "$*"; }
warn()  { printf "\033[33m⚠ %s\033[0m\n" "$*"; }
err()   { printf "\033[31m✘ %s\033[0m\n" "$*"; }
info()  { printf "\033[36m➜ %s\033[0m\n" "$*"; }

mask() {
  # mask secrets leaving first/last 2 chars
  local s="${1:-}"; [[ -z "$s" ]] && { echo ""; return; }
  local len=${#s}
  if (( len <= 6 )); then echo "•••"; else
    echo "${s:0:2}•••${s: -2}"
  fi
}

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --env PATH           Path to .env file (default: ./.env)
  --cert PATH          Client certificate (PEM) for mTLS to NGINX
  --key PATH           Client private key (PEM) for mTLS to NGINX
  --cacert PATH        CA certificate (PEM) that signed server & client certs
  --host NAME          Gateway host (default: localhost)
  --port N             Gateway port (default: 443)
  --timeout SECS       HTTP timeout (default: 10)
  -h, --help           Show this help

Examples:
  $0 --env .env --cert ./certs/client-cert.pem --key ./certs/client-key.pem --cacert ./certs/ca-cert.pem
EOF
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV_FILE="$2"; shift 2;;
    --cert) CLIENT_CERT="$2"; shift 2;;
    --key) CLIENT_KEY="$2"; shift 2;;
    --cacert) CA_CERT="$2"; shift 2;;
    --host) HOST="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    --timeout) TIMEOUT="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) err "Unknown option: $1"; usage; exit 1;;
  esac
done

REQUIRE_CMDS=(docker openssl sed grep awk curl)
for c in "${REQUIRE_CMDS[@]}"; do
  command -v "$c" >/dev/null 2>&1 || { err "Missing command: $c"; exit 2; }
done

# Load .env (safe parse of VAR=value)
if [[ -f "$ENV_FILE" ]]; then
  info "Loading environment from $ENV_FILE"
  # shellcheck disable=SC2046
  export $(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$ENV_FILE" | sed 's/#.*//')
else
  warn "No .env file found at $ENV_FILE (continuing without it)"
fi

# Read vars (may be empty)
OIDC_CLIENT_ID="${OIDC_CLIENT_ID:-}"
OIDC_CLIENT_SECRET="${OIDC_CLIENT_SECRET:-}"
OIDC_ISSUER_URL="${OIDC_ISSUER_URL:-}"
OAUTH2_PROXY_COOKIE_SECRET="${OAUTH2_PROXY_COOKIE_SECRET:-}"
OAUTH2_PROXY_REDIRECT_URL="${OAUTH2_PROXY_REDIRECT_URL:-https://localhost/oauth2/callback}"

echo
info "Configuration summary (masked):"
echo "  Host:                 $HOST:$PORT"
echo "  ENV file:             $ENV_FILE"
echo "  Issuer URL:           ${OIDC_ISSUER_URL:-<unset>}"
echo "  Client ID:            $(mask "${OIDC_CLIENT_ID:-}")"
echo "  Client Secret:        $(mask "${OIDC_CLIENT_SECRET:-}")"
echo "  Cookie Secret:        $(mask "${OAUTH2_PROXY_COOKIE_SECRET:-}")"
echo "  Redirect URL:         ${OAUTH2_PROXY_REDIRECT_URL}"
echo "  mTLS certs provided:  $([[ -n "$CLIENT_CERT" && -n "$CLIENT_KEY" && -n "$CA_CERT" ]] && echo yes || echo no)"

echo
info "1) Docker services status"
if docker ps --format '{{.Names}}' | grep -Eq '(^|,)ollama(,|$)|(^|,)nginx(,|$)|(^|,)oauth2-proxy(,|$)'; then
  docker ps --format '  - {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E 'ollama|nginx|oauth2-proxy' || true
  ok "Core containers are present."
else
  err "Expected containers (ollama, nginx, oauth2-proxy) not found. Did you run 'docker compose up -d'?"
fi
echo
info "2) NGINX port binding & TLS"
if ss -ltn '( sport = :'$PORT' )' 2>/dev/null | grep -q ":$PORT"; then
  ok "Port $PORT is listening."
else
  err "Port $PORT is not listening on the host."
fi

# If certs provided, probe /healthz with mTLS; else do a basic HTTPS probe with -k
CURL_BASE=(curl -sS --max-time "$TIMEOUT" -H "Connection: close")
if [[ -n "$CA_CERT" ]]; then CURL_BASE+=(--cacert "$CA_CERT"); else CURL_BASE+=(-k); fi
if [[ -n "$CLIENT_CERT" && -n "$CLIENT_KEY" ]]; then
  CURL_BASE+=(--cert "$CLIENT_CERT" --key "$CLIENT_KEY")
fi

HEALTHZ=$("${CURL_BASE[@]}" "https://${HOST}:${PORT}/healthz" || true)
if [[ -n "$HEALTHZ" ]]; then ok "NGINX /healthz reachable."; else warn "NGINX /healthz not reachable (TLS/mTLS or NGINX not ready?)."; fi

echo
info "3) TLS certificate chain checks (server & client)"
if [[ -n "$CA_CERT" ]]; then
  openssl x509 -in "$CA_CERT" -noout -subject -dates >/dev/null && ok "Loaded CA cert: $(openssl x509 -in "$CA_CERT" -noout -subject | sed 's/subject= //')"
fi

# Try to fetch server cert via s_client (best-effort)
if command -v timeout >/dev/null 2>&1; then TO="timeout 5"; else TO=""; fi
if [[ -n "$CLIENT_CERT" && -n "$CLIENT_KEY" && -n "$CA_CERT" ]]; then
  if $TO openssl s_client -connect "${HOST}:${PORT}" -cert "$CLIENT_CERT" -key "$CLIENT_KEY" -CAfile "$CA_CERT" -quiet < /dev/null >/dev/null 2>&1; then
    ok "mTLS handshake with server succeeded."
  else
    warn "mTLS handshake failed (cert/key/CA mismatch or NGINX not requiring client cert?)."
  fi
else
  warn "Skipping mTLS handshake test (client/CA certs not all provided)."
fi

if [[ -n "${CLIENT_CERT}" ]]; then
  openssl x509 -in "$CLIENT_CERT" -noout -subject -issuer -dates >/dev/null && ok "Client cert parsed successfully."
fi

echo
info "4) oauth2-proxy environment sanity"
[[ -n "${OIDC_CLIENT_ID}" ]] && ok "Client ID present." || err "Missing OIDC_CLIENT_ID in env."
[[ -n "${OIDC_CLIENT_SECRET}" ]] && ok "Client Secret present." || err "Missing OIDC_CLIENT_SECRET in env."
[[ -n "${OIDC_ISSUER_URL}" ]] && ok "Issuer URL present." || err "Missing OIDC_ISSUER_URL in env."
[[ -n "${OAUTH2_PROXY_COOKIE_SECRET}" ]] && ok "Cookie Secret present." || warn "Missing OAUTH2_PROXY_COOKIE_SECRET (may cause cookie/session issues)."
[[ "${OAUTH2_PROXY_REDIRECT_URL}" == "https://localhost/oauth2/callback" || "${OAUTH2_PROXY_REDIRECT_URL}" == https://* ]] && ok "Redirect URL set: ${OAUTH2_PROXY_REDIRECT_URL}" || warn "Redirect URL is unusual: ${OAUTH2_PROXY_REDIRECT_URL}"

echo
info "5) Azure OIDC discovery metadata"
if [[ -n "${OIDC_ISSUER_URL}" ]]; then
  META_URL="${OIDC_ISSUER_URL%/}/.well-known/openid-configuration"
  DISCOVERY=$("${CURL_BASE[@]}" "$META_URL" || true)
  if [[ -n "$DISCOVERY" ]]; then
    ISSUER=$(echo "$DISCOVERY" | sed -nE 's/.*"issuer"\s*:\s*"([^"]+)".*/\1/p')
    AUTHZ=$(echo "$DISCOVERY" | sed -nE 's/.*"authorization_endpoint"\s*:\s*"([^"]+)".*/\1/p')
    TOKEN=$(echo "$DISCOVERY" | sed -nE 's/.*"token_endpoint"\s*:\s*"([^"]+)".*/\1/p')
    JWKS=$(echo "$DISCOVERY" | sed -nE 's/.*"jwks_uri"\s*:\s*"([^"]+)".*/\1/p')
    echo "  issuer:                ${ISSUER:-<missing>}"
    echo "  authorization_endpoint:${AUTHZ:-<missing>}"
    echo "  token_endpoint:        ${TOKEN:-<missing>}"
    echo "  jwks_uri:              ${JWKS:-<missing>}"
    if [[ -n "$ISSUER" && "$ISSUER" == "${OIDC_ISSUER_URL%/}"* ]]; then
      ok "Issuer in discovery matches configured OIDC_ISSUER_URL (prefix check)."
    else
      warn "Issuer mismatch — oauth2-proxy may log 'issuer did not match'."
    fi
  else
    err "Failed to fetch OIDC discovery document: $META_URL"
  fi
else
  warn "Skipping discovery (no OIDC_ISSUER_URL)."
fi

echo
info "6) oauth2-proxy container health"
if docker ps --format '{{.Names}}' | grep -q '^oauth2-proxy$'; then
  docker inspect --format '  - Status: {{.State.Status}}  Health: {{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' oauth2-proxy || true
  echo "  Last 20 log lines:"
  docker logs --tail 20 oauth2-proxy || true
else
  warn "oauth2-proxy container not found."
fi

echo
info "7) NGINX auth_request and redirect behavior"
HTTP_CODE=$("${CURL_BASE[@]}" -o /dev/null -w "%{http_code}" "https://${HOST}:${PORT}/api/tags" || true)
case "$HTTP_CODE" in
  200) ok "Request to /api/tags returned 200 (access allowed).";;
  302) ok "Request to /api/tags returned 302 (likely redirect to OIDC start) — expected if not logged in.";;
  401|403) warn "Request to /api/tags returned $HTTP_CODE (unauthorized/forbidden) — check mTLS or OIDC session.";;
  000) err "Connection failed — check NGINX/certs/firewall.";;
  *) warn "Unexpected HTTP code from /api/tags: $HTTP_CODE";;
esac

echo
info "8) End-to-end generate test (optional)"
if [[ -n "$CLIENT_CERT" && -n "$CLIENT_KEY" ]]; then
  GEN_CODE=$("${CURL_BASE[@]}" -o /dev/null -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -d '{"model":"llama3","prompt":"ping"}' \
    "https://${HOST}:${PORT}/api/generate" || true)
  case "$GEN_CODE" in
    200) ok "Ollama /api/generate reachable through the gateway.";;
    302) warn "Got 302 — OIDC login required (open browser to complete sign-in).";;
    401|403) warn "Got $GEN_CODE — mTLS or OIDC authorization missing.";;
    *) warn "Unexpected code from /api/generate: $GEN_CODE";;
  esac
else
  warn "Skipping /api/generate call (client cert/key not provided)."
fi
echo
info "9) Ollama container & logs"
if docker ps --format '{{.Names}}' | grep -q '^ollama$'; then
  docker inspect --format '  - Status: {{.State.Status}}  Health: {{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' ollama || true
  echo "  Last 20 log lines:"
  docker logs --tail 20 ollama || true
else
  warn "ollama container not found."
fi
echo
info "10) NGINX container & logs"
if docker ps --format '{{.Names}}' | grep -q '^ollama-gateway$'; then
  docker inspect --format '  - Status: {{.State.Status}}  Health: {{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' ollama-gateway || true
  echo "  Last 20 log lines:"
  docker logs --tail 20 ollama-gateway || true
else
  warn "NGINX container (ollama-gateway) not found."
fi
echo
ok "Diagnostics complete."
echo "Hint: For oauth2-proxy errors, run:  docker logs -f oauth2-proxy"
echo "      Common fixes: Issuer URL mismatch, redirect URI mismatch, invalid client secret."
