# Using a CA‑issued TLS Certificate (no browser warnings)

This guide explains how to replace the self‑signed server certificate with a certificate trusted by your OS/browser while keeping mTLS for client authentication.

Key points:
- Server TLS is terminated at NGINX using `server.crt`/`server.key`.
- Client mTLS verification uses a separate CA file `ca.crt`.
- Replace the server certificate/key only. Do not replace `ca.crt` unless you also change the CA used to issue client certificates.

Relevant files and mounts:
- NGINX config: `nginx/nginx.conf`
- Docker Compose mounts:
  - `./certs/server-cert.pem  -> /etc/nginx/tls/server.crt`
  - `./certs/server-key.pem   -> /etc/nginx/tls/server.key`
  - `./certs/ca-cert.pem      -> /etc/nginx/tls/ca.crt` (client-auth CA)

The NGINX vhosts in `nginx/nginx.conf` are:
- `server_name localhost` (OIDC portal)
- `server_name api.localhost` (mTLS API)

Choose one of the options below.

---

## Option A: Real domain + Public CA (production-like)
Use this if you own a domain and want zero warnings everywhere without installing local trust.

1) DNS
- Create DNS records that point to your host:
  - `ai.example.com` for the portal (or another name you prefer)
  - `api.ai.example.com` for the API (or another name you prefer)

2) Issue a certificate
- Obtain a certificate from a public CA (e.g., your corporate PKI, DigiCert, Let’s Encrypt). The cert’s SANs should cover your chosen hostnames (e.g., `ai.example.com` and `api.ai.example.com`).
- You may use a wildcard cert `*.example.com` if allowed by your CA policy.

3) Update NGINX `server_name`
- Edit `nginx/nginx.conf`:
  - Replace `server_name localhost;` with your portal hostname (e.g., `server_name ai.example.com;`).
  - Replace `server_name api.localhost;` with your API hostname (e.g., `server_name api.ai.example.com;`).

4) Replace mounted files
- Place the CA-issued server cert and key as:
  - `certs/server-cert.pem` (full chain: leaf + intermediates)
  - `certs/server-key.pem` (private key)
- Keep `certs/ca-cert.pem` as your client-auth CA (the CA that issued the client certificates). Do not overwrite unless you are also migrating the client cert CA.

5) OAuth2/OIDC callback URL
- In `docker-compose.yml`, update:
  - `OAUTH2_PROXY_REDIRECT_URL` to `https://ai.example.com/oauth2/callback`
  - `OAUTH2_PROXY_WHITELIST_DOMAINS` to include your domain (e.g., `ai.example.com`)

6) Restart stack
```bash
./start.sh full
```
- Verify:
  - `https://ai.example.com/healthz` (no warning)
  - `https://api.ai.example.com/healthz` (requires client cert)

---

## Option B: Local development with mkcert (trusted locally)
This removes warnings on your machine by installing a locally trusted root CA. Great for `localhost`/`api.localhost` without public DNS.

1) Install mkcert and trust the local root
- macOS:
```bash
brew install mkcert nss   # nss helps Firefox trust store
mkcert -install           # installs local root CA into macOS Keychain/Firefox
```

2) Generate a cert for both hostnames
```bash
mkcert localhost api.localhost
# Outputs two files, e.g.:
#  - localhost+2.pem (certificate)
#  - localhost+2-key.pem (private key)
```

3) Replace NGINX server cert/key
```bash
cp localhost+2.pem certs/server-cert.pem
cp localhost+2-key.pem certs/server-key.pem
```
- Keep `certs/ca-cert.pem` as-is (this is the mTLS client-auth CA you already use for client certificates).

4) Restart stack
```bash
./start.sh full
```
- Verify with your browser and curl (no `-k` needed):
```bash
curl --cert certs/client-cert.pem --key certs/client-key.pem \
     --cacert certs/ca-cert.pem \
     https://api.localhost/healthz
```

Notes:
- mkcert only affects trust on your local machine. Other devices will still see warnings unless they also trust the mkcert root.

---

## Option C: Enterprise/internal CA (managed trust)
Use this if your organization has an internal PKI and client machines trust that root CA.

1) Request certs
- Ask PKI to issue a certificate for your chosen names:
  - Local testing: `localhost` and `api.localhost` in SAN (some CAs may disallow this).
  - Preferred: real internal DNS names, e.g., `ai.dev.corp` and `api.ai.dev.corp`.

2) Deploy server cert/key
- Save the issued certificate (with chain) and key to:
  - `certs/server-cert.pem`
  - `certs/server-key.pem`
- Do not modify `certs/ca-cert.pem` unless your mTLS client certificates are also issued by the enterprise CA. If switching client CA, replace `certs/ca-cert.pem` with the issuing CA used for the client certs.

3) Update hostnames
- Update `nginx/nginx.conf` `server_name` values to match the issued cert.
- Update any OAuth2 redirect and whitelist vars in `docker-compose.yml` as needed.

4) Restart and verify
```bash
./start.sh full
```

---

## Common pitfalls and tips
- Certificate chain: `server-cert.pem` should include intermediates as required by your CA.
- File permissions: ensure `certs/server-key.pem` is readable by Docker on your host.
- Do not overwrite `certs/ca-cert.pem` unless you are changing the CA for client certificates (mTLS). Server TLS and client-auth CA are independent concerns.
- Hostnames must match `server_name` and the certificate SANs.
- OIDC on api host: If you want to prevent bypass of OIDC, this repo can enforce OIDC on `api.localhost` as well (see `nginx/nginx.conf` `/api/` and `/v1/` under `server_name api.localhost`).
- OLLAMA_ORIGINS: set `OLLAMA_ORIGINS` in `docker-compose.yml` to your exact UI origins (e.g., `https://ai.example.com`) when you change hostnames.
- If you change hostnames, update OAuth2 redirect URL and whitelist domain in `docker-compose.yml`.
- For local `/etc/hosts` testing (mkcert case), ensure:
```
127.0.0.1   localhost api.localhost
```

---

## Rollback
If something goes wrong, restore the original self-signed files:
```bash
git checkout -- certs/server-cert.pem certs/server-key.pem
./start.sh full
```
