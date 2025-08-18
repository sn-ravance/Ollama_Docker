# Ollama Docker ZTA

## Description
A production‑ready Docker Compose stack to run Ollama locally with zero‑trust and compliance controls:
- Private, internal‑only network for the Ollama runtime
- NGINX reverse proxy terminating TLS/mTLS (client certs)
- Optional OIDC authentication via oauth2-proxy (works with Entra ID/Okta/Google, etc.)
- Locked‑down container privileges, rate limiting, CORS, and structured logs
- Clear placeholders and comments so you can adapt it quickly on your machine

## Install/Setup

### 0) Generate TLS/mTLS certs (required)
```
cd certs && bash gencerts.sh   ### or run the openssl commands manually
cd ..
```

### 1) Optional: Enable OIDC (SSO)
- Copy `.env.example` to `.env` and populate:
  - `OAUTH2_PROXY_COOKIE_SECRET` (openssl rand -base64 32)
  - `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`, `OIDC_ISSUER_URL`

### 2) Start the stack (with OIDC portal and mTLS API)
Preferred via helper script (adds health checks and diagnostics):
```
./start.sh full --open            # open default browser to https://localhost/login
# or
./start.sh full --open-incognito  # try incognito/private window (Chrome/Edge/Brave/Firefox on macOS)
```
Note: Browser auto-open flags apply to full (OIDC) mode only.

Or using docker compose directly (no browser auto-open):
```
docker compose up -d
```

### Or: Start mTLS‑only (no OIDC)
```
./start.sh mtls
# or: docker compose -f docker-compose.mtls.yml up -d
```

## Recommended workflow

Start stack:

```bash
./start.sh full    # or ./start.sh mtls
```

Enable egress when you need to pull:

```bash
bash scripts/enable-egress.sh
```

Pull model(s):

```bash
curl -sS -k --cert certs/client-cert.pem --key certs/client-key.pem --cacert certs/ca-cert.pem \
  -H 'Content-Type: application/json' -X POST \
  -d '{"name":"llama3.1:8b"}' https://api.localhost/api/pull
```

Optionally disable egress afterward:

```bash
bash scripts/disable-egress.sh
```

### 3) Endpoints
- OIDC portal: `https://localhost` (login at `/login`, claims at `/me`)
- Secure API: `https://api.localhost` (requires client certificate AND OIDC session)
  - Add to `/etc/hosts`: `127.0.0.1 api.localhost`

### 4) Quick tests
- Health (portal vhost):
  ```
  curl -k -s -o /dev/null -w "%{http_code}\n" https://localhost/healthz
  ```
- List models (mTLS API):
  ```
  curl --cert ./certs/client-cert.pem --key ./certs/client-key.pem \
       --cacert ./certs/ca-cert.pem \
       https://api.localhost/api/tags
  ```

### 5) Pull models (temporary egress)
```
./scripts/enable-egress.sh
curl --cert ./certs/client-cert.pem --key ./certs/client-key.pem \
     --cacert ./certs/ca-cert.pem \
     -X POST -H "Content-Type: application/json" \
     -d '{"name":"mistral"}' https://api.localhost/api/pull
./scripts/disable-egress.sh
```

### 6) Send a prompt
```
curl --cert ./certs/client-cert.pem --key ./certs/client-key.pem \
     --cacert ./certs/ca-cert.pem \
     -X POST -H "Content-Type: application/json" \
     -d '{"model":"mistral","prompt":"Explain zero-trust in simple terms."}' \
     https://api.localhost/api/generate
```

### 7) Stop and cleanup
- Safe stop (default, keeps volumes/images):
  ```
  ./stop.sh
  ```
- Deep clean (also remove named volumes; optionally images):
  ```
  ./stop.sh --prune         # prompts for confirmation
  ./stop.sh --prune --yes   # non-interactive (CI), removes volumes; will promptless offer to remove images
  ```

## Documentation
- See `docs/USAGE.md` for a comprehensive guide, app integration examples, and troubleshooting.
- OpenAPI spec: `docs/openapi.yaml` (import into tools that support client certificates).
 - Trusted TLS certs (remove browser warnings): `docs/Trusted_TLS_Certs.md`

### Hostnames and CORS (important in prod)
- __OLLAMA_ORIGINS__: In `docker-compose.yml`, set `OLLAMA_ORIGINS` to your exact UI origin(s), e.g., `https://ai.example.com`. Avoid wildcards.
- __NGINX server_name__: If you change certificate hostnames, update `server_name` in `nginx/nginx.conf` for both vhosts.
- __OIDC redirect__: Update `OAUTH2_PROXY_REDIRECT_URL` and `OAUTH2_PROXY_WHITELIST_DOMAINS` in `docker-compose.yml` when hostnames change.
