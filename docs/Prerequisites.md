The prerequisites you need before running the Ollama Zero-Trust Deployment locally on your PC:

## 1. Hardware Requirements
- CPU: Modern x86_64 processor (Intel i7/AMD Ryzen or better).
- RAM: Minimum 64 GB.
- GPU (optional): NVIDIA GPU with CUDA support for acceleration (8 GB+ VRAM recommended).
- Disk: At least 50 GB free (models can be large; encrypt the disk for compliance).

## 2. Software Requirements
- Operating System:
  - Linux (Ubuntu 20.04+), macOS, or Windows 11 (with WSL2 for Docker).
- Docker & Docker Compose:
  - Docker Engine 24.x or later
  - Docker Compose plugin v2.x
- OpenSSL: For generating TLS/mTLS certificates.
- curl or Postman: For API testing.
- jq (optional): For pretty-printing JSON in scripts.

## 3. Security & Identity (Required)
- __Server TLS certificate (X.509)__
  - A CA-issued certificate and key assigned to the hostnames you will use.
  - For local dev without warnings, see `docs/Trusted_TLS_Certs.md` (mkcert) or use your enterprise CA.
  - Place files as:
    - `certs/server-cert.pem` (full chain)
    - `certs/server-key.pem` (private key)
  - Do not replace `certs/ca-cert.pem` unless changing the client-auth CA.

- __Client certificate for mTLS__
  - Issue client certs from your mTLS CA (self-managed or enterprise PKI).
  - Files used by curl/tools:
    - `certs/client-cert.pem`, `certs/client-key.pem`, and `certs/ca-cert.pem` (issuer CA)
  - Import the client certificate to your browser/API client as needed.

- __OIDC (Azure Entra ID) App Registration__ (required when using OIDC)
  - Create an app registration with:
    - Redirect URI: `https://localhost/oauth2/callback` (or your portal hostname)
    - Assign and record: Client ID, Client Secret, Issuer URL (tenant)
  - Environment variables (see `.env.example`):
    - `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`, `OIDC_ISSUER_URL`
    - `OAUTH2_PROXY_COOKIE_SECRET` (32-byte base64)
    - `OAUTH2_PROXY_REDIRECT_URL` must match your redirect URI

## 4. Network & Access
- Localhost Binding:
  - NGINX gateway runs on https://localhost:443.
- Firewall Rules:
  - Block external access; allow only local connections.
- Optional Proxy:
  - For controlled outbound access when pulling models.

- Hostnames (SNI split)
  - `localhost` for the portal (OIDC + mTLS on `/api/*`)
  - `api.localhost` for direct API (mTLS + OIDC enforced)
  - Ensure `/etc/hosts` contains: `127.0.0.1 api.localhost` for local testing.

- CORS / Origins
  - Set `OLLAMA_ORIGINS` in `docker-compose.yml` to your exact UI origin(s), e.g., `https://localhost` or `https://ai.example.com`.

## 5. Configuration checklist (before starting)
- __Certificates__:
  - `certs/server-cert.pem` and `certs/server-key.pem` present (see `docs/Trusted_TLS_Certs.md`).
  - `certs/ca-cert.pem` present for client-auth; client cert/key available.
- __OIDC env vars__ (when OIDC enabled):
  - `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`, `OIDC_ISSUER_URL` set.
  - `OAUTH2_PROXY_REDIRECT_URL` matches the portal hostname and is registered in Entra ID.
  - `OAUTH2_PROXY_COOKIE_SECRET` set (32-byte base64).
- __Hostnames__:
  - `nginx/nginx.conf` `server_name` values match your certificate SANs.
  - `/etc/hosts` has `api.localhost` if using defaults.
- __Docker__:
  - Docker Engine 24.x+, Compose v2.x running.
- __Optional tools__:
  - `jq` installed for nicer script output.

## 5. Certificates & Keys
Server TLS Certificate: For NGINX (server-cert.pem, server-key.pem).
CA Certificate: For validating client certs (ca-cert.pem).
Client Certificate: For user authentication (client-cert.pem, client-key.pem).

## 6. Environment Files
- .env file with:
  - OAUTH2_PROXY_COOKIE_SECRET (random 32-byte base64)
  - OIDC_CLIENT_ID, OIDC_CLIENT_SECRET, OIDC_ISSUER_URL
