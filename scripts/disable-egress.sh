#!/usr/bin/env bash
set -euo pipefail

log() { echo "[disable-egress] $*"; }

# Configurable via env vars
CONTAINER="${CONTAINER:-ollama}"
DEFAULT_EGRESS="ollama_zta_egress"
EGRESS_NET="${EGRESS_NET:-$DEFAULT_EGRESS}"

# Resolve egress network if not present
if ! docker network inspect "$EGRESS_NET" >/dev/null 2>&1; then
  DETECTED=$(docker network ls --format '{{.Name}}' | grep -E '_egress$' | head -n1 || true)
  if [[ -n "${DETECTED:-}" ]]; then
    log "EGRESS_NET '$EGRESS_NET' not found; using detected network: $DETECTED"
    EGRESS_NET="$DETECTED"
  else
    log "ERROR: egress network not found. Set EGRESS_NET to your compose egress network name."
    exit 1
  fi
fi

log "Disconnecting container '$CONTAINER' from network '$EGRESS_NET'..."
if docker network disconnect "$EGRESS_NET" "$CONTAINER" 2>/dev/null; then
  log "Disconnected."
else
  log "Network disconnect returned non-zero; it may already be disconnected. Continuing..."
fi

log "Current networks for $CONTAINER:"
# Try jq if available for nicer output, otherwise fall back
if command -v jq >/dev/null 2>&1; then
  docker inspect -f '{{json .NetworkSettings.Networks}}' "$CONTAINER" | jq -r 'keys[]'
else
  docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{println $k}}{{end}}' "$CONTAINER"
fi

log "Done. Isolation restored. Tip: override with EGRESS_NET=<name> if autodetect is wrong."
