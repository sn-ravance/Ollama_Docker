# Setup OIDC with Entra ID
A step-by-step guide for integrating Azure Entra ID (OIDC) with your Ollama Zero-Trust Gateway:

## Prerequisites
- Azure subscription with Entra ID admin rights.
- Your tenant ID (find in Azure Portal → Azure Active Directory → Overview).
- The redirect URI for oauth2-proxy:

```
https://localhost/oauth2/callback
```

- Docker Compose stack with oauth2-proxy and NGINX configured.

## Step 1: Register an App in Azure Entra ID
1. Go to Azure Portal → Azure Active Directory → App registrations → New registration.
2. Name: Ollama Zero-Trust Gateway.
3. Supported account types:
  - Choose Accounts in this organizational directory only (or multi-tenant if needed).
4. Redirect URI:
  - Type: Web
  - Value:

  ```
  https://localhost/oauth2/callback
  ```

5. Click Register.

## Step 2: Configure App Settings
1. In the app’s Overview, note:
  - Application (client) ID → OIDC_CLIENT_ID
  - Directory (tenant) ID → used in OIDC_ISSUER_URL
2. Go to Certificates & secrets → New client secret:
  - Description: ollama-gateway-secret
  - Expiry: Choose 6–12 months (rotate regularly).
  - Copy the secret value → OIDC_CLIENT_SECRET.

## Step 3: Set API Permissions
- Go to API permissions → Add a permission → Microsoft Graph → Delegated permissions:
  - Select:

  ```
  openid
  profile
  email
  ```

- Click Grant admin consent.

## Step 4: Configure oauth2-proxy Environment
- Update your .env file:
```
OAUTH2_PROXY_COOKIE_SECRET=<random-32-byte-base64>
OIDC_CLIENT_ID=<Application (client) ID>
OIDC_CLIENT_SECRET=<Client secret value>
OIDC_ISSUER_URL=https://login.microsoftonline.com/<tenant-id>/v2.0
```

## Step 5: Update docker-compose.yml
- Ensure oauth2-proxy service includes:
```
environment:
  OAUTH2_PROXY_PROVIDER: "oidc"
  OAUTH2_PROXY_CLIENT_ID: "${OIDC_CLIENT_ID}"
  OAUTH2_PROXY_CLIENT_SECRET: "${OIDC_CLIENT_SECRET}"
  OAUTH2_PROXY_OIDC_ISSUER_URL: "${OIDC_ISSUER_URL}"
  OAUTH2_PROXY_REDIRECT_URL: "https://localhost/oauth2/callback"
  OAUTH2_PROXY_SCOPE: "openid profile email"
  OAUTH2_PROXY_COOKIE_SECRET: "${OAUTH2_PROXY_COOKIE_SECRET}"
```

## Step 6: Update NGINX Config
- In nginx.conf:
```
location /api/ {
    auth_request /oauth2/auth;
    proxy_pass http://ollama_upstream;
    proxy_set_header X-Auth-Request-User $upstream_http_x_auth_request_user;
    proxy_set_header X-Auth-Request-Email $upstream_http_x_auth_request_email;
}
```

## Step 7: Test the Flow
1. Restart the stack:
```
docker compose down && docker compose up -d
```

2. Open https://localhost in your browser:
  - You’ll be redirected to Microsoft login.
  - Complete MFA → redirected back to Ollama gateway.

3. Verify:
```
curl -k --cert client-cert.pem --key client-key.pem \
     --cacert ca-cert.pem \
     -H "Authorization: Bearer <token>" \
     https://localhost/api/tags
```

## Result:
- mTLS + OIDC enforced.
- User identity (email, groups) available in headers for RBAC.
- Logs capture auth events for compliance.

# Troubleshooting
Here are common troubleshooting tips for Azure Entra ID OIDC integration with your Ollama Zero-Trust setup:

## 1. Redirect URI Mismatch
### Symptom:
- Browser shows:
```
AADSTS50011: The redirect URI specified in the request does not match the redirect URIs configured for the application.
```
### Fix:
- In Azure Portal → App Registration → Authentication, ensure:
```
https://localhost/oauth2/callback
```

is listed as a Redirect URI (type: Web).

- If using a custom hostname (e.g., https://ollama.local), add that too.
## 2. Invalid Client Secret
### Symptom:
- oauth2-proxy logs show:
```
invalid_client: AADSTS7000215: Invalid client secret provided.
```

###Fix:
- Regenerate the client secret in Azure → App → Certificates & secrets.
- Update .env with the secret value (not the ID).
- Restart the stack:
```
docker compose down && docker compose up -d
```

## 3. Wrong Issuer URL
### Symptom:
- oauth2-proxy logs:
```
oidc: issuer did not match the issuer returned by provider
```

### Fix:
- Use the correct Issuer URL:
```
https://login.microsoftonline.com/<tenant-id>/v2.0
```
- Replace <tenant-id> with your Directory (tenant) ID from Azure AD Overview.

## 4. Missing Scopes or Consent
### Symptom:
- Login works, but oauth2-proxy fails to get user info. Fix:
- In Azure → App → API permissions:
  - Add openid, profile, email under Microsoft Graph → Delegated permissions.
  - Click Grant admin consent.

## 5. Cookie or Session Issues
### Symptom:
- Infinite redirect loop or 401 Unauthorized after login. Fix:
- Ensure OAUTH2_PROXY_COOKIE_SECRET is a 32-byte base64 string:
```
openssl rand -base64 32
```
- Check that your browser allows secure cookies for https://localhost.

## 6. SSL/TLS Problems
### Symptom:
- Browser warns about invalid cert or oauth2-proxy fails health check. Fix:
- Use the same CA for NGINX and oauth2-proxy trust chain.
- For local testing, add your CA cert to the system/browser trust store.

## 7. Group Claims Missing
### Symptom:
- You need RBAC by Azure AD groups, but headers are empty. Fix:
- In Azure → App → Token configuration:
  - Add Group claims (Security groups or Directory roles).
- Update oauth2-proxy config to include --oidc-groups-claim=groups.

** Tip: ** Always check oauth2-proxy logs:
```
docker logs oauth2-proxy

```
and NGINX logs for auth_request failures.
