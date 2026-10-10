#!/bin/sh
set -eu

CONFIG_DIR=/app/config
mkdir -p "$CONFIG_DIR" /data/evmconnect

# BESU_HOST is injected via render.yaml's fromService wiring to the firefly-besu
# private service. Falls back to BLOCKCHAIN_RPC_URL directly if set (e.g. to
# point at a different/external chain instead of the bundled Besu node).
if [ -n "${BESU_HOST:-}" ]; then
  export BLOCKCHAIN_RPC_URL="http://${BESU_HOST}:8545"
fi

envsubst < /app/evmconnect.yml.template > "$CONFIG_DIR/evmconnect.yml"

exec evmconnect -f "$CONFIG_DIR/evmconnect.yml"
