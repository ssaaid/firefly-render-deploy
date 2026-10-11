#!/bin/sh
set -eu

CONFIG_DIR=/app/config
mkdir -p "$CONFIG_DIR" /data/evmconnect

# SIGNER_HOST (signing chain) takes precedence over BESU_HOST (direct,
# no-signing connection -- used by the second, independent chain's
# evmconnect instance, which has nothing to sign since it's gateway mode
# with no contract). Both fall back to BLOCKCHAIN_RPC_URL if set directly.
if [ -n "${SIGNER_HOST:-}" ]; then
  export BLOCKCHAIN_RPC_URL="http://${SIGNER_HOST}:8545"
elif [ -n "${BESU_HOST:-}" ]; then
  export BLOCKCHAIN_RPC_URL="http://${BESU_HOST}:8545"
fi

envsubst < /app/evmconnect.yml.template > "$CONFIG_DIR/evmconnect.yml"

exec evmconnect -f "$CONFIG_DIR/evmconnect.yml"
