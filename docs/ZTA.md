## What this shows
- NGINX is the only exposed endpoint (bound to 127.0.0.1:443), enforcing mTLS and acting as the policy enforcement point (WAF, rate limiting, CORS, headers).
- oauth2‑proxy provides OIDC SSO, with NGINX using auth_request to gate /api/*.
- Ollama is reachable only on the internal Docker network (no host port mapping).
- Models live in an encrypted volume; logs stream to a local SIEM/Cribl Edge for audit/compliance.

## Key controls
- mTLS ensures only clients with a trusted certificate reach the proxy.
- OIDC (oauth2‑proxy) provides user identity; NGINX receives X-Auth-Request-User/group headers to enable RBAC/ABAC at the edge.
- NGINX enforces rate limits, CORS, and security headers before any request touches Ollama.
- Ollama is shielded on an internal network with no host‑exposed port.

## Optional Add‑Ons you might want
- Prompt security filter (simple regex or policy engine) as another internal microservice called by NGINX via auth_request before proxying to Ollama.
- Token & context caps via NGINX request body size limits and upstream timeouts.
- Model routing (e.g., different upstreams by path /api/generate/llama vs /api/generate/mixtral) for environment separation.

## Diagram
(See Ollama_ZTA_SeqDia.png)
```
sequenceDiagram
    actor C as Client (Browser/CLI)
    actor N as NGINX (Policy Enforcement Point / Reverse Proxy)
    actor P as oauth2-proxy (OIDC/OAuth2)
    actor I as Identity Provider (Entra ID / Okta / Auth0)
    actor F as Prompt/Policy Filter (optional microservice)
    actor O as Ollama (LLM runtime, internal-only)
    actor L as SIEM / Local Logs

    C ->> N : HTTPS request to /api/generate
    N ->> N : Verify TLS handshake + client cert (mTLS), apply WAF/rate-limit/CORS
    alt mTLS missing/invalid
        N ->> C : 401/403 (blocked by TLS policy)
        N ->> L : Log TLS/authn failure + client info (no PII)
    else mTLS valid
        N ->> L : Log access (TLS OK, proceeding to OIDC gate)
    end

    N ->> P : subrequest /oauth2/auth (check session)
    alt No valid session cookie
        P ->> N : 401 Unauthorized (needs sign‑in)
        N ->> C : 302 Redirect → /oauth2/start
        C ->> P : GET /oauth2/start
        P ->> C : 302 Redirect → I /authorize (PKCE)
        C ->> I : User login + MFA (per policy)
        I ->> C : 302 Redirect → P /oauth2/callback?code=...
        C ->> P : GET /oauth2/callback (code exchange for tokens)
        P ->> C : Set secure session cookie, 302 back to original URL
        C ->> N : Retry original /api/* request (now with session)
        N ->> P : subrequest /oauth2/auth
        P ->> N : 200 OK + X-Auth headers (user, groups, email)
    else Valid session present
        P ->> N : 200 OK + X-Auth headers (user, groups, email)
    end
    N ->> L : Log auth decision + user/group claims (minimized)

    N ->> F : POST /filter (prompt, caller, app metadata)
    alt Policy violation (e.g., PII, jailbreak, over-size, blocked tenant)
        F ->> N : 406/422 with reason code
        N ->> C : 4xx safe error (masked)
    else Allowed
        F ->> N : 200 Allowed
    end

    N ->> O : POST /api/generate (add X-User/X-Groups, strip cookies, set timeouts)
    O ->> N : Streamed tokens / chunked response
    loop while streaming tokens
        N ->> C : Forward token chunks (SSE/HTTP streaming)
    end

    N ->> L : Access + security events (JSON)
    P ->> L : Auth events (login/refresh/logout)
    F ->> L : Policy evaluation results (allow/block, rule id)
    O ->> L : Inference metrics (durations, model id, token counts)

    N ->> C : 200 OK (final chunk) OR controlled 4xx with safe message
```

## Notes
- NGINX is the Policy Enforcement Point: It’s the only exposed endpoint, enforcing mTLS, OIDC, WAF/rate limiting, CORS, and security headers before any request reaches Ollama.
- oauth2‑proxy supplies identity to NGINX via auth_request; headers like X-Auth-Request-User/-Groups enable RBAC/ABAC decisions at the edge.
- The Prompt/Policy Filter is optional but recommended for PII redaction, jailbreak/prompt‑injection screening, and use‑case/tenant scoping.
- Ollama remains on an internal network (no host port mapping) and only accepts traffic from NGINX.
- Logs flow to your local SIEM/Cribl agent for audit trails and compliance reporting.

## ZTA
Here’s how the Azure Entra ID OIDC + mTLS + NGINX + Ollama architecture aligns with Zero Trust Architecture (ZTA) principles:
1. Verify Explicitly
  - mTLS at the edge: Every client must present a valid certificate before any request is processed.
  - OIDC with Entra ID: Strong identity verification using enterprise IdP, MFA, and conditional access policies.
  - Continuous validation: oauth2-proxy checks session tokens on every request via auth_request.
2. Least Privilege Access
  - Role-Based Access Control (RBAC): NGINX receives user identity and group claims from oauth2-proxy, enabling fine-grained authorization.
  - Scoped tokens: OIDC tokens only include necessary claims (openid, profile, email).
  - No direct Ollama exposure: Ollama runs on an internal network; only NGINX can reach it.
3. Assume Breach
- Network segmentation: Internal Docker network isolates Ollama and oauth2-proxy from the host and internet.
- Defense-in-depth:
  - WAF and rate limiting at NGINX.
  - Optional prompt/policy filter to block malicious or sensitive requests.
  - Logging & monitoring: All access, auth, and policy decisions are logged to SIEM for anomaly detection.
4. Secure All Communications
- TLS 1.3 everywhere: Between client ↔ NGINX and NGINX ↔ oauth2-proxy.
- mTLS: Ensures both client and server authenticate each other.
- Encrypted storage: Model files and logs stored on encrypted volumes.
5. Continuous Monitoring & Governance
- SIEM integration: Logs from NGINX, oauth2-proxy, and Ollama feed into local or enterprise SIEM.
- Policy enforcement: Prompt filter enforces compliance and security policies dynamically.
- Automated health checks: Docker health probes for all services.

This design removes implicit trust, enforces identity-based access, and monitors every transaction, which are core ZTA principles.

