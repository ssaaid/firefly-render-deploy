#!/bin/sh
set -eu

DATA_DIR=/data/besu
mkdir -p "$DATA_DIR"

if [ -z "${BESU_VALIDATOR_KEY:-}" ]; then
  echo "BESU_VALIDATOR_KEY is not set. This must be the private key matching the" >&2
  echo "validator address baked into genesis.json's extraData, or this node will" >&2
  echo "never reach quorum with itself and no blocks will be produced." >&2
  exit 1
fi

printf '%s' "$BESU_VALIDATOR_KEY" > "$DATA_DIR/key"

exec besu \
  --data-path="$DATA_DIR" \
  --genesis-file=/app/genesis.json \
  --node-private-key-file="$DATA_DIR/key" \
  --p2p-enabled=false \
  --rpc-http-enabled \
  --rpc-http-api=ETH,NET,IBFT,TRACE,DEBUG \
  --rpc-http-host=0.0.0.0 \
  --rpc-http-port=8545 \
  --rpc-http-cors-origins=all \
  --host-allowlist=* \
  --min-gas-price=0
