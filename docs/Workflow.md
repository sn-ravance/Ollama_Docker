1. How They Access It
- The user runs docker compose up -d (or starts the Ollama app) on their PC.
- The NGINX gateway exposes two vhosts on 443 via SNI:
  - Portal (OIDC): https://localhost
  - API: https://api.localhost (in full mode requires mTLS + OIDC; mTLS-only alternative available via `./start.sh mtls`)
- The user never talks directly to Ollama—all requests go through NGINX, which enforces:
  - mTLS (client certificate required)
  - OIDC login (if enabled)
  - Rate limiting, WAF, and policy checks

2. Authentication Flow
- First-time access:
  - For portal: open https://localhost (browser). If OIDC is enabled, you’re redirected to Entra ID/Okta/Auth0 for login + MFA. A secure session cookie is set.
  - For API (https://api.localhost):
    - Full mode: present your client certificate (mTLS) and ensure you have an active OIDC session.
    - mTLS-only mode: present your client certificate; OIDC not required.

3. How They Interact with Ollama
- Via API:
  - Send requests to the mTLS API: https://api.localhost (paths: /api/generate, /api/tags, /api/pull).
  - Example:
    ```
    curl --cert ./certs/client-cert.pem --key ./certs/client-key.pem \
     --cacert ./certs/ca-cert.pem \
     -H "Content-Type: application/json" \
     -d '{"model":"mistral","prompt":"Summarize this text..."}' \
     https://api.localhost/api/generate
    ```
- Via Local Tools:
  - Preferred endpoint: https://api.localhost (port 443).
    - Full mode: requires client certificate and OIDC session.
    - mTLS-only mode: requires client certificate (no OIDC).
    - Add to /etc/hosts: `127.0.0.1 api.localhost`.
    - Ensure your server cert trusts include SAN for `api.localhost` (provided here).
  - Alternative: https://localhost:4443 (separate mTLS-only stack) — client certificate required; no OIDC.

4. Accessing Different Models
- Models are stored in the encrypted volume (ollama-data).
- To list models:
    ```
    curl --cert client-cert.pem --key client-key.pem \
     --cacert ca-cert.pem \
     https://api.localhost/api/tags
    ``` 

- To switch models, specify the model parameter in the API call:
  - ```
    { "model": "mistral", "prompt": "Explain zero-trust in simple terms." }
    ``` 

- To add a new model:
  - Temporarily allow controlled egress (see `scripts/enable-egress.sh`) or preload the model into the volume.
  - Use:
    ```
    curl --cert client-cert.pem --key client-key.pem \
     --cacert ca-cert.pem \
     -X POST -d '{"name":"mistral"}' \
     https://api.localhost/api/pull
    ```
  - Note: When using `scripts/enable-egress.sh`, ensure you understand the implications of allowing egress traffic.

  - Browser access to API (api.localhost on 443):
    - Import `certs/client-cert.p12` into login Keychain and trust `certs/ca-cert.pem`.
    - In Keychain Access, create an Identity Preference for your client cert with URL `https://api.localhost`.
    - Visit `https://api.localhost/api/tags` and select your client certificate when prompted.
    - If not prompted, quit/reopen the browser or try a new window.

5. Security & Compliance in Action
- All prompts and responses flow through NGINX → optional Prompt Filter → Ollama.
- Logs (access, auth, policy decisions) go to a local SIEM agent (e.g., Cribl Edge).
- No data leaves the PC unless you explicitly configure outbound sync.
