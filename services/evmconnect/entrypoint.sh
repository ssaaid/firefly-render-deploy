#!/bin/sh
set -eu

CONFIG_DIR=/app/config
mkdir -p "$CONFIG_DIR" /data/evmconnect

envsubst < /app/evmconnect.yml.template > "$CONFIG_DIR/evmconnect.yml"

exec evmconnect -f "$CONFIG_DIR/evmconnect.yml"
