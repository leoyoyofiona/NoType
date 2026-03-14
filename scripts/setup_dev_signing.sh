#!/bin/zsh
set -euo pipefail

IDENTITY_NAME="NoType Dev"
KEYCHAIN="$HOME/Library/Keychains/notype-dev.keychain-db"
KEYCHAIN_PASSWORD="NoType2026"
P12_PASSWORD="notype-dev-signing"

if [ -f "$KEYCHAIN" ] && security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -Fq "\"$IDENTITY_NAME\""; then
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/openssl.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no

[dn]
CN = NoType Dev

[v3]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

openssl req \
  -newkey rsa:2048 \
  -x509 \
  -sha256 \
  -days 3650 \
  -nodes \
  -config "$TMP_DIR/openssl.cnf" \
  -keyout "$TMP_DIR/dev.key" \
  -out "$TMP_DIR/dev.crt" >/dev/null 2>&1

openssl pkcs12 \
  -export \
  -inkey "$TMP_DIR/dev.key" \
  -in "$TMP_DIR/dev.crt" \
  -out "$TMP_DIR/dev.p12" \
  -name "$IDENTITY_NAME" \
  -passout pass:"$P12_PASSWORD" >/dev/null 2>&1

if [ ! -f "$KEYCHAIN" ]; then
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
  security set-keychain-settings -lut 21600 "$KEYCHAIN" >/dev/null
fi

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null

security import "$TMP_DIR/dev.p12" \
  -k "$KEYCHAIN" \
  -f pkcs12 \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign >/dev/null

security add-trusted-cert \
  -d \
  -r trustRoot \
  -k "$KEYCHAIN" \
  "$TMP_DIR/dev.crt" >/dev/null

security set-key-partition-list \
  -S apple-tool:,apple: \
  -s \
  -k "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN" >/dev/null

security list-keychains -d user -s "$KEYCHAIN" >/dev/null
