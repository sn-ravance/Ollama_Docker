#!/usr/bin/env bash
set -Eeuo pipefail

# Simple logger helpers
log() { printf "[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }
die() { printf "[ERROR] %s\n" "$*" >&2; exit 1; }

require() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }
require docker

# Optional deps
if ! command -v jq >/dev/null 2>&1; then
  log "jq not found; some JSON views will be skipped."
  JQ=false
else
  JQ=true
fi

STACK_NAME=ollama_zta
BACKEND_NET=${STACK_NAME}_backend
EGRESS_NET=${STACK_NAME}_egress
OAUTH2=oauth2-proxy
NGINX=nginx

# Mode selection: default 'full' uses docker-compose.yml (OIDC + mTLS on 443)
# Pass 'mtls' to use docker-compose.mtls.yml (mTLS-only on 4443)
MODE="${1:-full}"
# Optional flags (full mode only):
# --open             launch default browser to https://localhost/login
# --open-incognito   prefer opening a private/incognito window in common browsers
OPEN_BROWSER=0
OPEN_INCOGNITO=0
case "${2:-}" in
  --open) OPEN_BROWSER=1 ;;
  --open-incognito) OPEN_INCOGNITO=1 ;;
  "") : ;; 
  *) log "Unknown option: ${2:-}" ;;
esac

if [[ "$MODE" == "mtls" ]]; then
  COMPOSE_FILE="docker-compose.mtls.yml"
  NGINX="nginx-mtls"
  HEALTH_PORT=4443
  SKIP_OAUTH2=1
else
  COMPOSE_FILE="docker-compose.yml"
  HEALTH_PORT=443
  SKIP_OAUTH2=0
fi

# Bring up stack (networks get created automatically by compose)
log "Recreating '$MODE' stack to pick up latest compose/network changes"
docker compose -f "$COMPOSE_FILE" down || true
docker compose -f "$COMPOSE_FILE" up -d

log "Checking networks"
docker network ls | grep -E "${BACKEND_NET}|${EGRESS_NET}" || true

# Wait for oauth2-proxy to become healthy (up to ~90s)
wait_healthy() {
  local name=$1; local tries=30; local delay=3
  for i in $(seq 1 "$tries"); do
    local status
    status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$name" 2>/dev/null || echo "unknown")
    log "$name status: $status ($i/$tries)"
    if [[ "$status" == "healthy" || "$status" == "running" ]]; then
      return 0
    fi
    sleep "$delay"
  done
  return 1
}

if [[ "$SKIP_OAUTH2" -eq 0 ]]; then
  log "Waiting for $OAUTH2 health..."
  if ! wait_healthy "$OAUTH2"; then
    log "$OAUTH2 not healthy; running quick DNS/HTTPS diagnostics on egress network"
    docker run --rm --network "${EGRESS_NET}" busybox nslookup login.microsoftonline.com || true
    docker run --rm --network "${EGRESS_NET}" curlimages/curl:8.8.0 -sS \
      https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration | head -n 5 || true

    log "Recent $OAUTH2 logs:"
    docker logs --tail 80 "$OAUTH2" || true

    log "Running detailed diagnoser"
    bash docs/diagnose-ollama-oidc.sh || true
    die "$OAUTH2 failed to become healthy. See diagnostics above."
  fi
fi

if [[ "$SKIP_OAUTH2" -eq 0 ]]; then
  log "$OAUTH2 is healthy; starting NGINX (compose has health dependency) and verifying reachability"
else
  log "mTLS-only mode; starting NGINX (compose has health dependency) and verifying reachability"
fi
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

log "Probe https://localhost:${HEALTH_PORT}/healthz"
if ! curl -sk --max-time 5 "https://localhost:${HEALTH_PORT}/healthz" >/dev/null; then
  log "Health probe failed; tailing NGINX logs"
  docker logs --tail 100 "$NGINX" || true
  die "NGINX not reachable on ${HEALTH_PORT}"
fi

log "All checks passed. Stack is up."

open_incognito_macos() {
  local url="$1"
  # Try common browsers in order
  if [[ -d "/Applications/Google Chrome.app" || -d "$HOME/Applications/Google Chrome.app" ]]; then
    log "Opening Chrome incognito: $url"
    open -na "Google Chrome" --args --incognito "$url" || true
    return 0
  fi
  if [[ -d "/Applications/Microsoft Edge.app" || -d "$HOME/Applications/Microsoft Edge.app" ]]; then
    log "Opening Edge InPrivate: $url"
    open -na "Microsoft Edge" --args --inprivate "$url" || true
    return 0
  fi
  if [[ -d "/Applications/Brave Browser.app" || -d "$HOME/Applications/Brave Browser.app" ]]; then
    log "Opening Brave incognito: $url"
    open -na "Brave Browser" --args --incognito "$url" || true
    return 0
  fi
  if [[ -d "/Applications/Firefox.app" || -d "$HOME/Applications/Firefox.app" ]]; then
    log "Opening Firefox private window: $url"
    open -na "Firefox" --args -private-window "$url" || true
    return 0
  fi
  # Safari has no reliable CLI incognito flag — fall back to normal open
  return 1
}

# Optionally open the login page (only meaningful in full OIDC mode)
if [[ "$SKIP_OAUTH2" -eq 0 ]]; then
  URL="https://localhost/login"
  if [[ "$OPEN_INCOGNITO" -eq 1 ]]; then
    if open_incognito_macos "$URL"; then
      :
    else
      log "Incognito not supported via CLI for available browsers; opening normally: $URL"
      if command -v open >/dev/null 2>&1; then
        open "$URL" || true
      elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$URL" || true
      elif command -v start >/dev/null 2>&1; then
        start "$URL" || true
      fi
    fi
  elif [[ "$OPEN_BROWSER" -eq 1 ]]; then
    log "Opening browser to $URL"
    if command -v open >/dev/null 2>&1; then
      open "$URL" || true
    elif command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$URL" || true
    elif command -v start >/dev/null 2>&1; then
      start "$URL" || true
    else
      log "No known URL opener found; please open $URL manually."
    fi
  fi
fi
exit 0
