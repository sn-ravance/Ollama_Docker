# 1) Create a local CA
openssl genrsa -out ca-key.pem 4096
openssl req -x509 -new -nodes -key ca-key.pem -sha256 -days 3650 \
  -subj "/C=US/ST=MN/L=Minneapolis/O=LocalLab/CN=Local CA" \
  -out ca-cert.pem

# 2) Create server cert for 'localhost'
openssl genrsa -out server-key.pem 4096
openssl req -new -key server-key.pem \
  -subj "/C=US/ST=MN/L=Minneapolis/O=LocalLab/CN=localhost" \
  -out server.csr

cat > server.ext <<EOF
basicConstraints=CA:FALSE
subjectAltName = @alt_names
[alt_names]
DNS.1 = localhost
DNS.2 = api.localhost
IP.1  = 127.0.0.1
EOF

openssl x509 -req -in server.csr -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial \
  -out server-cert.pem -days 825 -sha256 -extfile server.ext

# 3) Create a client cert (import into your browser/tool for mTLS)
openssl genrsa -out client-key.pem 4096
openssl req -new -key client-key.pem \
  -subj "/C=US/ST=MN/L=Minneapolis/O=LocalLab/CN=local-user" \
  -out client.csr

openssl x509 -req -in client.csr -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial \
  -out client-cert.pem -days 825 -sha256

# Optional: generate a PKCS#12 for easy browser import
openssl pkcs12 -export -inkey client-key.pem -in client-cert.pem -certfile ca-cert.pem \
  -out client-cert.p12
