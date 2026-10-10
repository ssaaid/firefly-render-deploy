#!/bin/sh
# Sanity-checks the generated config templates against a running local stack,
# and reminds you to cross-check them against the FireFly CLI's own output
# if you're on a different FireFly version than the one pinned in the
# Dockerfiles (hyperledger/firefly:latest, firefly-evmconnect:latest, etc).
set -eu

echo "== FireFly CLI reference (optional) =="
if command -v ff >/dev/null 2>&1; then
  echo "ff CLI found: $(ff version 2>/dev/null || true)"
  echo "You can run 'ff init ethereum refcheck 1' in a scratch dir and diff"
  echo "its generated core.yml / evmconnect.yml against services/*/*.template"
  echo "to catch any schema drift before deploying to Render."
else
  echo "ff CLI not installed. Install it to generate a known-good reference config:"
  echo "  curl -L https://github.com/hyperledger/firefly-cli/releases/latest/download/firefly-cli_\$(uname -s)_\$(uname -m).tar.gz | tar xz"
fi

echo
echo "== docker-compose config check =="
docker compose config >/dev/null && echo "docker-compose.yml: OK"
