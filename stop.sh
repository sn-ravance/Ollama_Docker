#!/usr/bin/env bash
set -Eeuo pipefail

# Stop and clean up all services, containers, and networks created by this stack.
# Default: non-destructive (does NOT delete volumes or images).
# Use --prune for a deep clean (removes volumes and optionally service images) with confirmation.

STACK_NAME=ollama_zta
BACKEND_NET=${STACK_NAME}_backend
EGRESS_NET=${STACK_NAME}_egress

log() { printf "[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }
die() { printf "[ERROR] %s\n" "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $0 [--prune] [--yes]

Options:
  --prune   Deep clean: also remove named volumes (model cache) and optionally service images.
  --yes|-y  Skip confirmations (dangerous with --prune).
EOF
}

PRUNE=false
YES=false
for arg in "$@"; do
  case "$arg" in
    --prune) PRUNE=true ;;
    --yes|-y) YES=true ;;
    -h|--help) usage; exit 0 ;;
    *) log "Unknown argument: $arg"; usage; exit 1 ;;
  esac
done

command -v docker >/dev/null 2>&1 || die "Docker is required"

log "Bringing down compose stacks (full + mtls)"
# Try both compose files if present
if [[ -f docker-compose.yml ]]; then
  if $PRUNE; then
    docker compose -f docker-compose.yml down --remove-orphans -v || true
  else
    docker compose -f docker-compose.yml down --remove-orphans || true
  fi
fi
if [[ -f docker-compose.mtls.yml ]]; then
  if $PRUNE; then
    docker compose -f docker-compose.mtls.yml down --remove-orphans -v || true
  else
    docker compose -f docker-compose.mtls.yml down --remove-orphans || true
  fi
fi

log "Force-stopping known containers if still running"
for name in nginx nginx-mtls oauth2-proxy ollama; do
  if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
    log "Removing container: $name"
    docker rm -f "$name" || true
  fi
done

log "Removing project networks if present"
for net in "$BACKEND_NET" "$EGRESS_NET"; do
  if docker network ls --format '{{.Name}}' | grep -qx "$net"; then
    log "Removing network: $net"
    docker network rm "$net" || true
  fi
done

if $PRUNE; then
  log "Deep clean requested (--prune)"
  if ! $YES; then
    read -r -p "This will remove named volumes (model cache). Continue? [y/N] " ans
    case "${ans:-N}" in
      y|Y) : ;; 
      *) log "Skip prune of volumes/images"; PRUNE=false ;;
    esac
  fi
fi

if $PRUNE; then
  # Remove any volumes created by this project (compose down -v should already remove declared volumes)
  # Extra safety: try typical names
  for vol in "${STACK_NAME}_ollama-data" "ollama-data"; do
    if docker volume ls --format '{{.Name}}' | grep -qx "$vol"; then
      log "Removing volume: $vol"
      docker volume rm "$vol" || true
    fi
  done

  # Optionally remove service images
  if $YES; then
    REMOVE_IMAGES=true
  else
    read -r -p "Also remove service images (nginx, oauth2-proxy, ollama)? [y/N] " ans2
    case "${ans2:-N}" in
      y|Y) REMOVE_IMAGES=true ;;
      *) REMOVE_IMAGES=false ;;
    esac
  fi

  if ${REMOVE_IMAGES:-false}; then
    for img in \
      nginx:alpine \
      quay.io/oauth2-proxy/oauth2-proxy:latest \
      ollama/ollama:latest \
      curlimages/curl:8.8.0; do
      if docker image ls --format '{{.Repository}}:{{.Tag}}' | grep -qx "$img"; then
        log "Removing image: $img"
        docker image rm -f "$img" || true
      fi
    done
  fi
fi

if $PRUNE; then
  log "Done. Containers, networks, volumes removed. Images removed if selected."
else
  log "Done. Containers stopped and networks removed. Volumes/images left intact."
fi
