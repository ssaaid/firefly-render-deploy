#!/bin/sh
set -eu

export DATA_DIRECTORY="${DATA_DIRECTORY:-/data/dataexchange}"
mkdir -p "$DATA_DIRECTORY/peer-certs"

envsubst < /app/config.json.template > "$DATA_DIRECTORY/config.json"

# dataexchange-https refuses to start without a pre-existing key.pem/cert.pem --
# it doesn't generate its own. The cert's O= field becomes this node's peer ID,
# so it needs to be stable across restarts (hence generating it once, onto the
# persistent disk, rather than fresh on every boot).
if [ ! -f "$DATA_DIRECTORY/key.pem" ] || [ ! -f "$DATA_DIRECTORY/cert.pem" ]; then
  openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
    -keyout "$DATA_DIRECTORY/key.pem" \
    -out "$DATA_DIRECTORY/cert.pem" \
    -subj "/O=${FIREFLY_ORG_NAME:-org1}/OU=${FIREFLY_NODE_NAME:-node1}/CN=${DATAEXCHANGE_PUBLIC_HOST:-localhost}"
fi

exec node /firefly-dataexchange-https/build/index.js
