# firefly-render-deploy

Deploys a single-org [Hyperledger FireFly](https://hyperledger.github.io/firefly/) supernode
to [Render](https://render.com) using a Blueprint (`render.yaml`).

## Architecture

```
                 ┌─────────────────────┐
  internet ───▶  │  firefly-core (web)  │ ── Postgres (Render managed)
                 └─────────┬───────────┘
                            │ private network
          ┌─────────────────┼─────────────────┐
          ▼                 ▼                 ▼
  firefly-evmconnect   firefly-ipfs     firefly-dataexchange (web, public)
     (pserv)              (pserv)         ◀── reached directly by other
          │                                     orgs' FireFly nodes
          ▼
  firefly-besu (pserv)
  single-validator IBFT2 chain
```

- **firefly-core** — the FireFly API/UI. Public. Talks to Postgres and the three
  plugins below over Render's private network.
- **firefly-evmconnect** — blockchain connector. Private. Talks to `firefly-besu`.
- **firefly-besu** — a single-validator Besu IBFT2 chain, private, dedicated to this
  deployment. See "Connecting to Besu" below.
- **firefly-ipfs** — shared storage backend (IPFS/kubo). Private.
- **firefly-dataexchange** — point-to-point transfer between organizations. **Must be
  public** — this is the one piece other orgs' FireFly nodes dial directly over the
  internet, so it's a `web` service, not `pserv`.

Each service is a thin Docker wrapper around the official Hyperledger images
(`hyperledger/firefly`, `firefly-evmconnect`, `firefly-dataexchange-https`, `ipfs/kubo`,
`hyperledger/besu`) that substitutes environment variables into a config template at
container start (`envsubst` in each `entrypoint.sh`). Render wires the private
hostnames between services via `fromService` in `render.yaml`.

## Connecting to Besu

You already have `besu-ibft2-private-blockchain` (a 4-node IBFT2 cluster meant to run
on your laptop via docker-compose, or on an OpenShift cluster via `besu.sh`) and
`quorum-kubernetes` locally. Neither is reachable from Render as-is: the docker-compose
version only binds to `localhost`, and the OpenShift script needs an actual cluster to
run against. Rather than exposing your laptop or standing up a cluster, `firefly-besu`
bundles a brand-new, dedicated **single-validator** IBFT2 chain (chainId `138801`) that
deploys alongside FireFly on Render itself — a single validator always has quorum with
itself, so it produces blocks with no peers and no bootnodes needed.

`services/besu/genesis.json` is committed (it's public chain config, no secret). The
matching validator private key is **not** committed — committing a key to git is a bad
habit worth keeping even for a throwaway dev chain. It was generated once for this repo
and printed to the terminal when this was set up; store it in your password manager, then:

- **Locally**: put it in `.env` as `BESU_VALIDATOR_KEY=0x...` (`.env` is gitignored).
- **On Render**: set it on the `firefly-besu` service's `BESU_VALIDATOR_KEY` env var
  in the dashboard (it's marked `sync: false` in `render.yaml`, so Render won't ask
  you to set it until you open that service's Environment tab).

If you lose the key, regenerate both together — don't reuse the old genesis with a new
key, they won't match:
```bash
docker run --rm -v "$(pwd)/services/besu:/data" hyperledger/besu:23.4.1 \
  operator generate-blockchain-config \
  --config-file=/data/ibftConfigFile.json --to=/data/networkFiles --private-key-file-name=key
```
(you'll need a small `ibftConfigFile.json` with `"count": 1` — see
`besu-ibft2-private-blockchain/genesis-generator/ibftConfigFile.json` for the shape)
— then copy the new `genesis.json` over `services/besu/genesis.json` and use the new key.

To point FireFly at a *different* chain instead (your real 4-node Besu cluster once it's
reachable, Quorum, or a public testnet), remove the `firefly-besu` service and set
`BLOCKCHAIN_RPC_URL` directly on `firefly-evmconnect` — `BESU_HOST` takes precedence
over it only while `firefly-besu` exists.

## Before you deploy

1. **Verify the config templates against your FireFly version.** The YAML under
   `services/*/*.template` mirrors the schema FireFly's own CLI (`ff init`) generates,
   but that schema has changed across FireFly releases. Run `scripts/check-config.sh`
   and, if you have the `ff` CLI installed, diff its generated `core.yml` /
   `evmconnect.yml` against the templates here before trusting them in production.
2. **Review the Blueprint spec.** `render.yaml` uses `fromService`/`fromDatabase` to
   wire internal URLs; double-check the exact field names against
   [Render's current Blueprint spec](https://render.com/docs/blueprint-spec) since
   this file was written from memory of that schema, not fetched live.

## Test locally first

```bash
cp .env.example .env
# edit .env: set BESU_VALIDATOR_KEY (see "Connecting to Besu" above)

docker compose up --build
```

Then open:
- `http://localhost:5000/api/v1/network/organizations` — core API
- `http://localhost:5000/ui` — FireFly Explorer UI

## Deploy to Render

1. Push this repo to GitHub/GitLab.
2. In the Render dashboard: **New → Blueprint**, point it at the repo.
3. Render will create `firefly-db`, `firefly-besu`, `firefly-ipfs`,
   `firefly-evmconnect`, `firefly-dataexchange`, `firefly-core` from `render.yaml`.
4. Set the `sync: false` env vars in the dashboard before the first deploy:
   - `firefly-besu` → `BESU_VALIDATOR_KEY` (see "Connecting to Besu" above)
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
services/besu/               Single-validator IBFT2 chain (genesis.json committed, key is not)
services/dataexchange/       Org-to-org data exchange (public-facing)
services/ipfs/               Shared storage backend
scripts/check-config.sh      Sanity checks before deploying
```
