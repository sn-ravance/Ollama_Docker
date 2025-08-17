1. How They Access It
- The user runs docker compose up -d (or starts the Ollama app) on their PC.
- The NGINX gateway is bound to https://localhost:443 (or a custom hostname).
- The user never talks directly to Ollama—all requests go through NGINX, which enforces:
  - mTLS (client certificate required)
  - OIDC login (if enabled)
  - Rate limiting, WAF, and policy checks

2. Authentication Flow
- First-time access:
  - The user opens https://localhost in a browser or uses curl/Postman with their client certificate.
  - If OIDC is enabled, they’re redirected to Entra ID/Okta/Auth0 for login + MFA.
  - After login, a secure session cookie is set (browser) or a bearer token is used (API clients).

3. How They Interact with Ollama
- Via API:
  - The user sends requests to https://localhost/api/generate (or /api/tags, /api/pull).
  - Example:
    ```
    curl --cert ./certs/client-cert.pem --key ./certs/client-key.pem \
     --cacert ./certs/ca-cert.pem \
     -H "Authorization: Bearer <OIDC_TOKEN>" \
     -d '{"model":"llama3","prompt":"Summarize this text..."}' \
     https://localhost/api/generate
    ```

- Via Local Tools:
  - CLI tools or apps (like VS Code extensions) can point to https://localhost as the Ollama endpoint.
  - They must include the client cert and/or OIDC token.

4. Accessing Different Models
- Models are stored in the encrypted volume (ollama-data).
- To list models:
    ```
    curl --cert client-cert.pem --key client-key.pem \
     --cacert ca-cert.pem \
     https://localhost/api/tags
    ``` 

- To switch models, specify the model parameter in the API call:
  - ```
    { "model": "mistral", "prompt": "Explain zero-trust in simple terms." }
    ``` 

- To add a new model:
  - Temporarily allow controlled egress or preload the model into the volume.
  - Use:
    ```
    curl --cert client-cert.pem --key client-key.pem \
     --cacert ca-cert.pem \
     -X POST -d '{"name":"mistral"}' \
     https://localhost/api/pull
    ```

5. Security & Compliance in Action
- All prompts and responses flow through NGINX → optional Prompt Filter → Ollama.
- Logs (access, auth, policy decisions) go to a local SIEM agent (e.g., Cribl Edge).
- No data leaves the PC unless you explicitly configure outbound sync.
