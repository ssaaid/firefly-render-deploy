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
  firefly-signer (pserv)
  holds the org's signing key
          │
          ▼
  firefly-besu (pserv)
  single-validator IBFT2 chain
```

- **firefly-core** — the FireFly API/UI. Public. Talks to Postgres and the four
  plugins below over Render's private network.
- **firefly-evmconnect** — blockchain connector. Private. Talks to `firefly-signer`,
  never holds a key itself.
- **firefly-signer** — holds the org's private key (FireFly Signer / `ffsigner`).
  Private. Signs transactions, relays everything else to `firefly-besu`.
- **firefly-besu** — a single-validator Besu IBFT2 chain, private, dedicated to this
  deployment. See "Connecting to Besu" below.
- **firefly-ipfs** — shared storage backend (IPFS/kubo). Private.
- **firefly-dataexchange** — point-to-point transfer between organizations. **Must be
  public** — this is the one piece other orgs' FireFly nodes dial directly over the
  internet, so it's a `web` service, not `pserv`.

Each service is a thin Docker wrapper around the official Hyperledger images
(`ghcr.io/hyperledger-firefly/firefly`, `evmconnect`, `dataexchange-https`, `signer`,
`ipfs/kubo`, `hyperledger/besu`) that substitutes environment variables into a config
template at container start (`envsubst` in each `entrypoint.sh`). Render wires the
private hostnames between services via `fromService` in `render.yaml`.

`firefly-core` runs its default namespace in **multiparty mode** — broadcasts get
batched, published to `firefly-ipfs`, and pinned on-chain via a deployed BatchPin
contract, with org/node identities registered on that same contract. This has been
run and verified locally end to end, including an org + node identity
self-registration (see "Multiparty mode: registering your identity" below).

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
`BLOCKCHAIN_RPC_URL` directly on `firefly-evmconnect` — `SIGNER_HOST` (pointing at
`firefly-signer`) takes precedence over it only while that service exists.

## Multiparty mode: the signer and the BatchPin contract

FireFly doesn't hold signing keys itself — `firefly-evmconnect` forwards every
`eth_sendTransaction` to `firefly-signer` (FireFly Signer / `ffsigner`), which holds
an encrypted [Keystore V3](https://github.com/ethereum/wiki/wiki/Web3-Secrets-Module)
file, signs, and relays the raw transaction (and everything else, untouched) to
`firefly-besu`.

**Generating the signing key.** Like `BESU_VALIDATOR_KEY`, `SIGNER_KEY` is a raw hex
private key that must never be committed. Generate one (e.g. `openssl rand -hex 32`,
prefixed with `0x`), store it in your password manager, then:
- **Locally**: `SIGNER_KEY=0x...` in `.env`.
- **On Render**: set it on `firefly-signer`'s `SIGNER_KEY` env var in the dashboard.

On first boot, `services/signer/entrypoint.sh` turns that raw key into a Keystore V3
file on the service's persistent disk (`/data/signer/keystore`), using `ethers` (bundled
into the image at build time) because `ffsigner` itself has no keygen command. The
address it prints to the container log the first time (`Generated keystore for address
0x...`) is **not** a secret — it's the public account address — but note it down; you
need it for `ORG_SIGNING_KEY` below. The filenames matter: `ffsigner`'s default
file-wallet mode expects `<address>.key.json` + `<address>.pwd` (see
`services/signer/ffsigner.yml.template`'s `fileWallet.filenames`) — get this wrong and
it silently tries to use the encrypted key file's own content as the password.

**Deploying the BatchPin contract.** FireFly ships the contract's ABI+bytecode inside
the core image at `/firefly/contracts/Firefly.json` (`contracts["Firefly.sol:Firefly"]`
— no constructor args). Deploy it through the signer exactly like any other
transaction, extracting the bytecode first:
```bash
# Extract the bytecode (run against whichever firefly-core image tag you're using)
docker run --rm --entrypoint sh ghcr.io/hyperledger-firefly/firefly:v1.5.0 \
  -c "cat /firefly/contracts/Firefly.json" > /tmp/Firefly.json
BYTECODE="0x$(python3 -c "import json; print(json.load(open('/tmp/Firefly.json'))['contracts']['Firefly.sol:Firefly']['bin'])")"

# Deploy via the signer -- locally that's localhost:8555, on Render it's
# firefly-signer's internal address (open a one-off shell/tunnel, or run this from
# a service that can reach it on the private network)
curl -s -X POST -H "Content-Type: application/json" --data '{
  "jsonrpc":"2.0","method":"eth_sendTransaction",
  "params":[{"from":"<your signer address>","data":"'"$BYTECODE"'","gas":"0x3D0900","gasPrice":"0x0"}],
  "id":1
}' http://localhost:8555

# Then fetch the receipt (same backend, e.g. localhost:8546 for firefly-besu) for
# "contractAddress" -- that's your BATCHPIN_CONTRACT_ADDRESS.
```
Set `ORG_SIGNING_KEY` (the signer's address) and `BATCHPIN_CONTRACT_ADDRESS` on
`firefly-core`, then restart it.

## Multiparty mode: registering your identity

Once `firefly-core` is up with a resolved BatchPin contract (`/api/v1/status` shows
`multiparty.enabled: true` and a `contract.active`), org and node still show
`registered: false` until you claim them — this broadcasts a message through IPFS +
the BatchPin contract, so it also proves the whole multiparty pipeline works:
```bash
curl -s -X POST http://localhost:5050/api/v1/network/organizations/self -d '{}'
# wait a few seconds for it to batch, publish to IPFS, and pin on-chain, then:
curl -s -X POST http://localhost:5050/api/v1/network/nodes/self -d '{}'
```
Check `/api/v1/status` or the **Network** tab in the UI (`/ui`) afterwards — both
should show `registered: true`. If the node claim 404s with "Identity could not be
resolved", the org claim hasn't confirmed on-chain yet; wait ~10s and retry.

## Before you deploy

The full stack (besu, signer, evmconnect, ipfs, dataexchange, postgres, core) has been
run and verified **locally, end to end, in multiparty mode**: Besu produces blocks,
the signer signs and relays through to it, the BatchPin contract was deployed and
resolved, and an org + node identity was self-registered and confirmed (broadcast →
IPFS → on-chain pin → event → `registered: true`). Still worth a look before deploying:

1. **FireFly's version will drift.** The image tags are pinned (`v1.5.0`/`v1.5.1`/`v1.4.0`/`v1.2.1`,
   from [firefly/manifest.json](https://github.com/hyperledger/firefly/blob/main/manifest.json)),
   but if you bump them, re-check the config schema with
   `docker run --rm --entrypoint /usr/bin/firefly <image> showconfig` — it changes between
   releases (e.g. `org:`/`node:` are deprecated and `admin:` was renamed to `spi:` since
   whatever version these templates were last written against).
2. **Review the Blueprint spec.** `render.yaml` uses `fromService`/`fromDatabase` to
   wire internal URLs; double-check the exact field names against
   [Render's current Blueprint spec](https://render.com/docs/blueprint-spec) since
   this file was written from memory of that schema, not fetched live (unlike the
   container configs above, this part has NOT been run against a real Render account yet).
3. **Cross-arch emulation is slow, not broken.** All these images are `linux/amd64`
   only. On an arm64 dev machine (Apple Silicon) Docker runs them under emulation —
   `ethers`' scrypt-based keystore encryption in particular can take 10+ seconds under
   that emulation. A container that looks "stuck" for a few seconds right after a
   keystore-generation step is very likely just this, not a hang.

## Test locally first

```bash
cp .env.example .env
# edit .env: set BESU_VALIDATOR_KEY and SIGNER_KEY (see "Connecting to Besu" /
# "Multiparty mode" above), then ORG_SIGNING_KEY and BATCHPIN_CONTRACT_ADDRESS
# once you've generated/deployed those (chicken-and-egg: bring the stack up once
# without them to generate the signer key, deploy the contract, then set these
# two and restart firefly-core)

docker compose up --build
```

Then open:
- `http://localhost:5050/api/v1/status` — core API (note: host port 5050, mapped from
  the container's 5000 — 5000 is often already taken locally, e.g. by macOS AirPlay)
- `http://localhost:5050/ui` — FireFly Explorer UI, **Network** tab once registered

## Deploy to Render

1. Push this repo to GitHub/GitLab.
2. In the Render dashboard: **New → Blueprint**, point it at the repo.
3. Render will create `firefly-db`, `firefly-besu`, `firefly-signer`, `firefly-ipfs`,
   `firefly-evmconnect`, `firefly-dataexchange`, `firefly-core` from `render.yaml`.
4. Set the `sync: false` env vars in the dashboard before the first deploy:
   - `firefly-besu` → `BESU_VALIDATOR_KEY` (see "Connecting to Besu" above)
   - `firefly-signer` → `SIGNER_KEY` (see "Multiparty mode" above)
   - `firefly-dataexchange` → `DATAEXCHANGE_PUBLIC_HOST` (its `*.onrender.com` hostname,
     or your custom domain — you'll only know the exact hostname after the first deploy,
     so redeploy this service once you have it)
5. Once `firefly-besu` and `firefly-signer` are live, deploy the BatchPin contract
   through the signer (see "Multiparty mode" above) and set `ORG_SIGNING_KEY` +
   `BATCHPIN_CONTRACT_ADDRESS` on `firefly-core`, then deploy it.
6. Register your org + node identity (see "Multiparty mode: registering your
   identity" above) against `firefly-core`'s public URL.

## Repo layout

```
render.yaml                  Render Blueprint (all services + managed Postgres)
docker-compose.yml           Local equivalent, for testing before you push
services/core/               FireFly core: Dockerfile, entrypoint, config template (multiparty mode)
services/evmconnect/         Blockchain connector
services/signer/             Holds the org's signing key, generates its own keystore on first boot
services/besu/               Single-validator IBFT2 chain (genesis.json committed, key is not)
services/dataexchange/       Org-to-org data exchange (public-facing), generates its own TLS cert on first boot
services/ipfs/               Shared storage backend
scripts/check-config.sh      Sanity checks before deploying
```
