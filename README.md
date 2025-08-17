# Ollama Docker Container

## Description
A production‑ready Docker Compose stack to run Ollama locally with zero‑trust and compliance controls:
- Private, internal‑only network for the Ollama runtime
- NGINX reverse proxy terminating TLS/mTLS (client certs)
- Optional OIDC authentication via oauth2-proxy (works with Entra ID/Okta/Google, etc.)
- ocked‑down container privileges, rate limiting, CORS, and structured logs
- Clear placeholders and comments so you can adapt it quickly on your machine

## Install/Setup

### 1) Generate TLS/mTLS certs
```
cd certs && bash ../generate-certs.sh   ### or run the openssl commands manually
cd ..
```

### 2) Start the stack
```
docker compose up -d
```

### 3) Test (mTLS + OIDC):
** If using mTLS only: **

```
curl --cert ./certs/client-cert.pem --key ./certs/client-key.pem \
     --cacert ./certs/ca-cert.pem \
     https://localhost/healthz
```

### Call Ollama via the gateway:
```
curl --cert ./certs/client-cert.pem --key ./certs/client-key.pem \
     --cacert ./certs/ca-cert.pem \
     -sS https://localhost/api/tags
```
