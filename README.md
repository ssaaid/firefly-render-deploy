# firefly-render-deploy

Deploys a single-org [Hyperledger FireFly](https://hyperledger.github.io/firefly/) supernode
to [Render](https://render.com) using a Blueprint (`render.yaml`).

## Architecture

```
                 ┌────────────────────┐
  internet ───▶  │  firefly-core (web) │ ── Postgres (Render managed)
                 └─────────┬──────────┘
                            │ private network
          ┌─────────────────┼─────────────────┐
          ▼                 ▼                 ▼
  firefly-evmconnect   firefly-ipfs     firefly-dataexchange (web, public)
     (pserv)              (pserv)         ◀── reached directly by other
          │                                     orgs' FireFly nodes
          ▼
  your blockchain RPC
  (Besu/Quorum node, or a public testnet)
```

- **firefly-core** — the FireFly API/UI. Public. Talks to Postgres and the three
  plugins below over Render's private network.
- **firefly-evmconnect** — blockchain connector. Private. Points at `BLOCKCHAIN_RPC_URL`
  (your own Besu/Quorum network, or any EVM-compatible RPC).
- **firefly-ipfs** — shared storage backend (IPFS/kubo). Private.
- **firefly-dataexchange** — point-to-point transfer between organizations. **Must be
  public** — this is the one piece other orgs' FireFly nodes dial directly over the
  internet, so it's a `web` service, not `pserv`.

Each service is a thin Docker wrapper around the official Hyperledger images
(`hyperledger/firefly`, `firefly-evmconnect`, `firefly-dataexchange-https`, `ipfs/kubo`)
that substitutes environment variables into a config template at container start
(`envsubst` in each `entrypoint.sh`). Render wires the private hostnames between
services via `fromService` in `render.yaml`.

## Before you deploy

1. **Verify the config templates against your FireFly version.** The YAML under
   `services/*/*.template` mirrors the schema FireFly's own CLI (`ff init`) generates,
   but that schema has changed across FireFly releases. Run `scripts/check-config.sh`
   and, if you have the `ff` CLI installed, diff its generated `core.yml` /
   `evmconnect.yml` against the templates here before trusting them in production.
2. **Decide what blockchain FireFly talks to.** You have `besu-ibft2-private-blockchain`
   and `quorum-kubernetes` locally — if you want FireFly to connect to one of those
   instead of a public testnet, that node's RPC endpoint needs to be reachable from
   Render (e.g. exposed publicly with firewall rules, or via a VPN/tunnel into Render's
   private network — Render alone can't reach an RPC node sitting only on your laptop
   or a private VPC without one of those).
3. **Review the Blueprint spec.** `render.yaml` uses `fromService`/`fromDatabase` to
   wire internal URLs; double-check the exact field names against
   [Render's current Blueprint spec](https://render.com/docs/blueprint-spec) since
   this file was written from memory of that schema, not fetched live.

## Test locally first

```bash
cp .env.example .env
# edit .env: point BLOCKCHAIN_RPC_URL at a real RPC endpoint

docker compose up --build
```

Then open:
- `http://localhost:5000/api/v1/network/organizations` — core API
- `http://localhost:5000/ui` — FireFly Explorer UI

## Deploy to Render

1. Push this repo to GitHub/GitLab.
2. In the Render dashboard: **New → Blueprint**, point it at the repo.
3. Render will create `firefly-db`, `firefly-ipfs`, `firefly-evmconnect`,
   `firefly-dataexchange`, `firefly-core` from `render.yaml`.
4. Set the `sync: false` env vars in the dashboard before the first deploy:
   - `firefly-evmconnect` → `BLOCKCHAIN_RPC_URL`
   - `firefly-dataexchange` → `DATAEXCHANGE_PUBLIC_HOST` (its `*.onrender.com` hostname,
     or your custom domain — you'll only know the exact hostname after the first deploy,
     so redeploy this service once you have it)
5. Once all services are live, register your org/node identity against
   `firefly-core`'s public URL (see the
   [FireFly multiparty setup docs](https://hyperledger.github.io/firefly/)).

## Repo layout

```
render.yaml                  Render Blueprint (all services + managed Postgres)
docker-compose.yml           Local equivalent, for testing before you push
services/core/               FireFly core: Dockerfile, entrypoint, config template
services/evmconnect/         Blockchain connector
services/dataexchange/       Org-to-org data exchange (public-facing)
services/ipfs/               Shared storage backend
scripts/check-config.sh      Sanity checks before deploying
```
