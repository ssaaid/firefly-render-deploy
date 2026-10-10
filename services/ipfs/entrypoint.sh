#!/bin/sh
set -eu

export IPFS_PATH=/data/ipfs

if [ ! -f "$IPFS_PATH/config" ]; then
  ipfs init
fi

# The default kubo config binds the API/Gateway to 127.0.0.1, which is
# unreachable from other services on Render's private network. Rebind to
# 0.0.0.0 so firefly-core can reach the API from another container.
ipfs config Addresses.API /ip4/0.0.0.0/tcp/5001
ipfs config Addresses.Gateway /ip4/0.0.0.0/tcp/8080

exec ipfs daemon --migrate=true
