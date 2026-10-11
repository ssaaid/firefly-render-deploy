#!/bin/sh
set -eu

CONFIG_DIR=/app/config
mkdir -p "$CONFIG_DIR"

# Render's "fromService" blueprint wiring only hands us bare hostnames
# (property: host) for other private services on the internal network.
# The actual ports are fixed by each service's own Dockerfile/entrypoint,
# so we assemble full URLs here instead of relying on string concatenation
# inside render.yaml, which the Blueprint spec does not support.
export EVMCONNECT_URL="http://${EVMCONNECT_HOST}:5008"
export EVMCONNECT2_URL="http://${EVMCONNECT2_HOST}:5008"
export DATAEXCHANGE_URL="http://${DATAEXCHANGE_HOST}:3000"
export IPFS_API_URL="http://${IPFS_HOST}:5001"
export IPFS_GATEWAY_URL="http://${IPFS_HOST}:8080"

envsubst < /app/firefly.core.yml.template > "$CONFIG_DIR/firefly.core.yml"

exec firefly -f "$CONFIG_DIR/firefly.core.yml"
