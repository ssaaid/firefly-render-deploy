#!/bin/sh
set -eu

CONFIG_DIR=/app/config
mkdir -p "$CONFIG_DIR" /data/dataexchange/certs /data/dataexchange/destinations

envsubst < /app/dataexchange.yml.template > "$CONFIG_DIR/dataexchange.yml"

exec dataexchange-https "$CONFIG_DIR/dataexchange.yml"
