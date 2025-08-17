## 1. Start the Secure Stack
1. Open a terminal in the folder with docker-compose.yml.
2. Run:
```
 docker compose up -d
```

3. Verify services:
```
docker ps
```

You should see ollama, nginx, and oauth2-proxy containers running.

## 2. Prepare Your Credentials
- mTLS: Import your client certificate (client-cert.p12) into your browser or API tool (Postman, curl).
- OIDC (if enabled): Be ready to log in with your enterprise identity (e.g., Entra ID, Okta).

## 3. Access the Gateway
- Open your browser and go to:
```
https://localhost
```
- If OIDC is enabled:
  - You’ll be redirected to your Identity Provider for login + MFA.
  - After login, you’ll return to the Ollama gateway.

## 4. Interact with Ollama
** List Available Models**
```
curl --cert ./certs/client-cert.pem --key ./certs/client-key.pem \
     --cacert ./certs/ca-cert.pem \
     https://localhost/api/tags

```

** Generate Text **
```
curl --cert ./certs/client-cert.pem --key ./certs/client-key.pem \
     --cacert ./certs/ca-cert.pem \
     -X POST https://localhost/api/generate \
     -H "Content-Type: application/json" \
     -d '{
           "model": "llama3",
           "prompt": "Explain zero-trust in simple terms."
         }'
```

** Switch Models **
- Just change "model": "mistral" or any other installed model in the JSON payload.

## 5. Add a New Model
- Temporarily allow outbound access or preload the model.
- Pull a model:
```
curl --cert ./certs/client-cert.pem --key ./certs/client-key.pem \
     --cacert ./certs/ca-cert.pem \
     -X POST https://localhost/api/pull \
     -H "Content-Type: application/json" \
     -d '{"name":"mistral"}'
```

## 6. Security & Compliance
- All traffic goes through NGINX → mTLS → OIDC → optional Prompt Filter → Ollama.
- Logs (access, auth, policy) are stored locally and can be forwarded to SIEM.
- No data leaves your PC unless you explicitly allow it.

## Tips
- Use Postman or VS Code REST Client for testing.
- For automation, store your cert paths and OIDC token in environment variables.
- Rotate client certs and OIDC tokens regularly.
