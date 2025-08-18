#!/usr/bin/env bash
set -euo pipefail

# Configuration
MODEL=${MODEL:-llama3.3:latest}
PROMPT=${PROMPT:-"Explain zero trust in one paragraph."}
CERT_ARGS=(
  --cert certs/client-cert.pem
  --key certs/client-key.pem
  --cacert certs/ca-cert.pem
)

echo "[test-chat] Listing models..."
if command -v jq >/dev/null 2>&1; then
  curl -sS -k "${CERT_ARGS[@]}" https://api.localhost/api/tags | jq . || true
else
  curl -sS -k "${CERT_ARGS[@]}" https://api.localhost/api/tags || true
fi

echo "[test-chat] Pulling model: ${MODEL}"

# Stream pull progress and render a simple percentage indicator.
pull_with_progress() {
  local tmp
  tmp=$(mktemp)
  # Stream, tee to tmp for later inspection, and render progress
  curl -sS -k "${CERT_ARGS[@]}" \
    -H 'Content-Type: application/json' -X POST \
    -d "{\"name\":\"${MODEL}\"}" \
    https://api.localhost/api/pull \
    | tee "$tmp" \
    | while IFS= read -r line; do
        # Try jq first for robust parsing
        if command -v jq >/dev/null 2>&1; then
          pct=$(echo "$line" | jq -r 'select(.total and .completed) | ( ( .completed * 100 ) / (.total|if .==0 then 1 else . end) )' 2>/dev/null || echo "")
          dg=$(echo "$line" | jq -r 'select(.digest) | .digest' 2>/dev/null || echo "")
        else
          # Fallback: extract numbers with sed/grep; may be less precise
          total=$(echo "$line" | sed -n 's/.*"total":\([0-9]\+\).*/\1/p' | head -n1)
          completed=$(echo "$line" | sed -n 's/.*"completed":\([0-9]\+\).*/\1/p' | head -n1)
          dg=$(echo "$line" | sed -n 's/.*"digest":"\([^"]\+\)".*/\1/p' | head -n1)
          if [[ -n "$total" && -n "$completed" && "$total" -gt 0 ]]; then
            pct=$(( completed * 100 / total ))
          else
            pct=""
          fi
        fi
        if [[ -n "${pct:-}" ]]; then
          printf "\r[test-chat][pull] %3s%% %s" "$pct" "${dg:-}"
        fi
      done
  local rc=${PIPESTATUS[0]}
  # Finish the progress line
  echo
  OUTPUT=$(cat "$tmp")
  rm -f "$tmp"
  return $rc
}

OUTPUT=""
pull_with_progress || true
[[ -n "$OUTPUT" ]] && echo "$OUTPUT" | tail -n1 >/dev/null 2>&1

# Detect DNS misbehavior that commonly occurs when Zscaler or similar is intercepting DNS/egress
if echo "$OUTPUT" | grep -qiE 'server misbehaving|lookup registry\.ollama\.ai'; then
  echo "[test-chat][WARN] Model pull failed due to DNS resolution issues (possible Zscaler interference)."
  echo "[test-chat][ACTION] If Zscaler is active, temporarily disable it and retry."
  echo "[test-chat] Enabling egress network and retrying pull once..."
  ./scripts/enable-egress.sh || true
  sleep 1
  OUTPUT=""
  pull_with_progress || true
  [[ -n "$OUTPUT" ]] && echo "$OUTPUT" | tail -n1 >/dev/null 2>&1
fi

# Basic success check before prompting
if ! echo "$OUTPUT" | grep -q '"status":"success"'; then
  echo "[test-chat][WARN] Pull may not have completed successfully. Proceeding to prompt anyway."
fi

echo "[test-chat] Sending prompt via OpenAI-compatible endpoint..."
# Build JSON payload safely
if command -v jq >/dev/null 2>&1; then
  PAYLOAD=$(jq -n --arg model "$MODEL" --arg prompt "$PROMPT" '{model:$model, messages:[{role:"user", content:$prompt}]}')
else
  ESCAPED_PROMPT=${PROMPT//\"/\\\"}
  PAYLOAD="{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"${ESCAPED_PROMPT}\"}]}"
fi

curl -sS -k "${CERT_ARGS[@]}" \
  -H 'Content-Type: application/json' -X POST \
  -d "$PAYLOAD" \
  https://api.localhost/v1/chat/completions