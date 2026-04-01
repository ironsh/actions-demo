#!/usr/bin/env bash
set -euo pipefail

CA_DIR="$(cd "$(dirname "$0")" && pwd)/ca"
mkdir -p "$CA_DIR"

if [[ -f "$CA_DIR/ca.crt" && -f "$CA_DIR/ca.key" ]]; then
  echo "CA already exists at $CA_DIR — skipping generation."
  exit 0
fi

openssl genrsa -out "$CA_DIR/ca.key" 4096
openssl req -x509 -new -nodes \
  -key "$CA_DIR/ca.key" \
  -sha256 -days 3650 \
  -subj "/CN=iron-proxy CA" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign" \
  -out "$CA_DIR/ca.crt"

echo "CA certificate and key written to $CA_DIR/"
