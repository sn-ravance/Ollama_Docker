# list models
curl -sS -k \
  --cert certs/client-cert.pem --key certs/client-key.pem --cacert certs/ca-cert.pem \
  https://api.localhost/api/tags | jq .

# pull model
curl -sS -k \
  --cert certs/client-cert.pem --key certs/client-key.pem --cacert certs/ca-cert.pem \
  -H 'Content-Type: application/json' -X POST \
  -d '{"name":"llama3.1:8b"}' \
  https://api.localhost/api/pull

# prompt (OpenAI-compatible)
curl -sS -k \
  --cert certs/client-cert.pem --key certs/client-key.pem --cacert certs/ca-cert.pem \
  -H 'Content-Type: application/json' -X POST \
  -d '{"model":"llama3.1:8b","messages":[{"role":"user","content":"Explain zero trust in one paragraph."}]}' \
  https://api.localhost/v1/chat/completions