#!/bin/sh
set -eu

mkdir -p /data/signer/keystore

if [ -z "${SIGNER_KEY:-}" ]; then
  echo "SIGNER_KEY is not set. This must be a raw hex private key (0x...) for the" >&2
  echo "org's signing identity -- used for the BatchPin contract and every" >&2
  echo "on-chain transaction FireFly submits. Generate one, store it safely, and" >&2
  echo "set it as an env var (never commit it). See README." >&2
  exit 1
fi

if [ -z "$(ls -A /data/signer/keystore 2>/dev/null)" ]; then
  node /app/make-keystore.js "$SIGNER_KEY" /data/signer/keystore
fi

mkdir -p /app/config
envsubst < /app/ffsigner.yml.template > /app/config/ffsigner.yml

exec ffsigner -f /app/config/ffsigner.yml
