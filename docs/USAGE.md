# Ollama ZTA Usage Guide

This guide covers end-to-end usage: starting the stack, downloading models, sending prompts, integrating from apps (Node/JS), OpenAI-compatible notes, and testing via OpenAPI.

## Prerequisites
- Certificates generated under `certs/` (run `cd certs && bash gencerts.sh`).
- `/etc/hosts` has `127.0.0.1 api.localhost`.
- Browser trust: import `certs/client-cert.p12` and trust `certs/ca-cert.pem`.

## Start the stack
- With OIDC portal and mTLS API (auto-open login page):
  ```bash
  ./start.sh full --open
  # or open a private/incognito window (macOS: Chrome/Edge/Brave/Firefox)
  ./start.sh full --open-incognito
  ```
  - Portal (OIDC): https://localhost (login at /login)
  - API (OIDC-only): https://localhost/api (no client cert required)
  - API (mTLS-only): https://api.localhost (client certificate required)

- mTLS-only (no OIDC):
  ```bash
  ./start.sh mtls
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

## No-cookie usage

Use either of the following, without relying on browser cookies:

- mTLS-only API (no OIDC):
  ```bash
  # Present client certs to mTLS vhost
  curl --cert certs/client-cert.pem --key certs/client-key.pem \
       --cacert certs/ca-cert.pem https://api.localhost/api/tags
  ```

- OIDC Bearer token (no cookies):
  - Prereq: set `OIDC_CLIENT_ID` and `OIDC_ISSUER_URL` in `.env` (see `.env.example`).
  - Fetch a token using the Device Code flow helper:
    ```bash
    TOKEN=$(./scripts/fetch-oidc-token.sh --print-access-token)
    ```
  - Call the OIDC-only API on `localhost` using the bearer token:
    ```bash
    curl -k -H "Authorization: Bearer $TOKEN" https://localhost/api/tags
    ```

## Pull models (egress toggle)
- Egress is blocked by default. Use helper scripts to temporarily allow outbound pulls:
  ```bash
  ./scripts/enable-egress.sh
  curl --cert certs/client-cert.pem --key certs/client-key.pem \
       --cacert certs/ca-cert.pem \
       -X POST -H "Content-Type: application/json" \
       -d '{"name":"mistral"}' https://api.localhost/api/pull
  ./scripts/disable-egress.sh
  ```

## Verify models
```bash
curl --cert certs/client-cert.pem --key certs/client-key.pem \
     --cacert certs/ca-cert.pem https://api.localhost/api/tags
```

## Generate text
```bash
curl --cert certs/client-cert.pem --key certs/client-key.pem \
     --cacert certs/ca-cert.pem \
     -X POST -H "Content-Type: application/json" \
     -d '{"model":"mistral","prompt":"Explain zero-trust in simple terms."}' \
     https://api.localhost/api/generate
```

## Browser access to mTLS API
- Import `certs/client-cert.p12` into the login keychain and trust `certs/ca-cert.pem`.
- In Keychain Access, create an Identity Preference for `https://api.localhost` bound to your client cert.
- Visit https://api.localhost/api/tags and select your certificate if prompted. In full mode you must also be logged in via OIDC on `https://localhost`.

## Using from applications (Node.js)
When your app connects to the mTLS gateway, configure HTTPS with client certs. Example with `axios`:

```js
const https = require('https');
const axios = require('axios');
const fs = require('fs');

const agent = new https.Agent({
  cert: fs.readFileSync('certs/client-cert.pem'),
  key: fs.readFileSync('certs/client-key.pem'),
  ca: fs.readFileSync('certs/ca-cert.pem'),
  // rejectUnauthorized: true // keep default true for security
});

const api = axios.create({
  baseURL: 'https://api.localhost', // mTLS vhost
  httpsAgent: agent,
});

async function listModels() {
  const res = await api.get('/api/tags');
  return res.data;
}

async function generate() {
  const res = await api.post('/api/generate', {
    model: 'mistral',
    prompt: 'Explain zero-trust in simple terms.'
  }, { headers: { 'Content-Type': 'application/json' }});
  return res.data;
}
```

### Integrating with an existing helper (example: `tmodel_mk10/utils/ollama.js`)
- If the helper expects an HTTP endpoint, set it to the gateway: `https://api.localhost`.
- Use an HTTPS client that supports mTLS as in the axios example above; pass the `httpsAgent` to requests.
- If the helper currently points to a different API (e.g., FastAPI wrapper), you can either:
  - Update to call the Ollama native endpoints (`/api/tags`, `/api/pull`, `/api/generate`), or
  - Keep the wrapper but configure the wrapper to call `https://api.localhost` with client certs.

## OpenAI-compatible usage
Ollama provides an OpenAI-compatible API in recent versions (e.g., `/v1/chat/completions`). Our NGINX routes native Ollama endpoints under `/api/*`. If you prefer the OpenAI-compatible paths:
- Reference: https://github.com/ollama/ollama/blob/main/docs/openai.md
- You can add an additional NGINX location to proxy `/v1/*` to the same upstream (not enabled by default here). If you want this, open an issue and we can wire it for you.
- OpenAI SDK usage typically needs:
  - `baseURL` → `https://api.localhost/v1`
  - TLS options or system keychain to present the client cert (SDK support varies).

## OIDC portal flow (optional)
- Login: https://localhost/login
- Claims view: https://localhost/me
- Auth split overview:
  - `https://localhost/api/*` → OIDC-only (no client cert required)
  - `https://api.localhost` → mTLS-only (client certificate required)
  - You can still run the dedicated mTLS-only stack with `./start.sh mtls`.

## Stop and cleanup
- Safe stop (default; keeps volumes/images):
  ```bash
  ./stop.sh
  ```
- Deep clean (remove named volumes; optionally service images):
  ```bash
  ./stop.sh --prune         # prompts for confirmation
  ./stop.sh --prune --yes   # non-interactive
  ```

## OpenAPI (Swagger) spec
- File: `docs/openapi.yaml`
- Note: Browser-based Swagger UI won’t present a client cert by default. Use CLI tools (e.g., `curl`) or code that can present client certs. You can still import the spec into tools that support mTLS.

## Troubleshooting
- `400` on `https://api.localhost/healthz` without a cert: expected (mTLS vhost requires client auth).
- Model pull fails with DNS/egress errors: run `./scripts/enable-egress.sh`, pull, then `./scripts/disable-egress.sh`.
- Certificate selection not prompting in browser: set an Identity Preference for `https://api.localhost`.
