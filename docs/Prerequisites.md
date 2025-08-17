prerequisites you need before running the Ollama Zero-Trust Deployment locally on your PC:
✅ 1. Hardware Requirements
CPU: Modern x86_64 processor (Intel i7/AMD Ryzen or better).
RAM: Minimum 16 GB (32 GB recommended for large models).
GPU (optional): NVIDIA GPU with CUDA support for acceleration (8 GB+ VRAM recommended).
Disk: At least 50 GB free (models can be large; encrypt the disk for compliance).
✅ 2. Software Requirements
Operating System:
Linux (Ubuntu 20.04+), macOS, or Windows 11 (with WSL2 for Docker).
Docker & Docker Compose:
Docker Engine 24.x or later
Docker Compose plugin v2.x
OpenSSL: For generating TLS/mTLS certificates.
curl or Postman: For API testing.
✅ 3. Security & Identity
Client Certificate (mTLS):
Generate using OpenSSL or your enterprise PKI.
Import into your browser or API client.
OIDC Credentials (if using SSO):
Client ID, Client Secret, and Issuer URL from your IdP (Azure Entra ID, Okta, Auth0).
Configure redirect URI: https://localhost/oauth2/callback.
✅ 4. Network & Access
Localhost Binding:
NGINX gateway runs on https://localhost:443.
Firewall Rules:
Block external access; allow only local connections.
Optional Proxy:
For controlled outbound access when pulling models.
✅ 5. Certificates & Keys
Server TLS Certificate: For NGINX (server-cert.pem, server-key.pem).
CA Certificate: For validating client certs (ca-cert.pem).
Client Certificate: For user authentication (client-cert.pem, client-key.pem).
✅ 6. Environment Files
.env file with:
OAUTH2_PROXY_COOKIE_SECRET (random 32-byte base64)
OIDC_CLIENT_ID, OIDC_CLIENT_SECRET, OIDC_ISSUER_URL