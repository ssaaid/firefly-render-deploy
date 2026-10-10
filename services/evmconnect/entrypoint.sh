#!/bin/sh
set -eu

CONFIG_DIR=/app/config
mkdir -p "$CONFIG_DIR" /data/evmconnect

# SIGNER_HOST is injected via render.yaml's fromService wiring to the
# firefly-signer private service, which signs transactions and relays
# everything else to firefly-besu -- evmconnect itself never sees a key.
# Falls back to BLOCKCHAIN_RPC_URL directly if set (e.g. to point at a
# different chain/signer setup instead of the bundled one).
if [ -n "${SIGNER_HOST:-}" ]; then
  export BLOCKCHAIN_RPC_URL="http://${SIGNER_HOST}:8545"
fi

envsubst < /app/evmconnect.yml.template > "$CONFIG_DIR/evmconnect.yml"

exec evmconnect -f "$CONFIG_DIR/evmconnect.yml"
