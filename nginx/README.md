This config:
- Terminates TLS and enforces mTLS (client cert required)
- Enforces OIDC via oauth2-proxy (auth_request)
- Adds rate limiting, CORS, and security headers
- Proxies only the Ollama API paths

NGINX acts as the secure gateway in this architecture. Its role is critical for enforcing zero-trust principles and compliance:

1. TLS Termination & mTLS Enforcement
- NGINX terminates HTTPS connections and enforces mutual TLS (client certificates).
- This ensures only trusted clients (with valid certs) can reach the Ollama API.

2. Authentication & Authorization Layer
- Integrates with oauth2-proxy for OIDC/OAuth2 SSO (e.g., Azure Entra ID, Okta).
- Performs auth_request checks before forwarding traffic to Ollama.
- Adds RBAC context via headers (e.g., user email, group claims).

3. API Gateway & Policy Enforcement
- Acts as a reverse proxy to Ollama, hiding the backend from direct access.

- Implements:
  - Rate limiting (prevent DoS or abuse)
  - Connection limits
  - CORS restrictions
  - Security headers (CSP, X-Frame-Options, etc.)

4. Network Segmentation
- NGINX is the only service exposed to localhost (or a controlled interface).
- Ollama runs on an internal-only Docker network, unreachable from the host directly.

5. Compliance & Logging
- Central point for access logs, auth logs, and TLS handshake logs.
- These logs can be shipped to SIEM (Splunk, Sentinel) for compliance audits.

## In short: 
NGINX is the policy enforcement point (PEP) in a zero-trust model, handling secure ingress, auth, and traffic governance before requests ever hit Ollama.


