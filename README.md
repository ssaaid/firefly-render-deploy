# firefly-render-deploy

Deploys a single-org [Hyperledger FireFly](https://hyperledger.github.io/firefly/) supernode
to [Render](https://render.com) using a Blueprint (`render.yaml`).

## Architecture

```
                 ┌─────────────────────┐
  internet ───▶  │  firefly-core (web)  │ ── Postgres (Render managed)
                 │  namespace "default" │
                 │  namespace "besu2"   │
                 └─────────┬───────────┘
                            │ private network
     ┌──────────────┬───────────┼─────────────────┐
     ▼               ▼          ▼                 ▼
firefly-evmconnect2  firefly-evmconnect  firefly-ipfs   firefly-dataexchange (web, public)
  (pserv)              (pserv)             (pserv)        ◀── reached directly by other
     │                    │                                    orgs' FireFly nodes
     ▼                    ▼
firefly-besu2        firefly-signer (pserv)
(pserv)              holds the org's signing key
chainId 138802              │
no signer needed            ▼
(gateway namespace)   firefly-besu (pserv)
                       single-validator IBFT2 chain, chainId 138801
                       (multiparty namespace, BatchPin contract)
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
- **firefly-besu2** — a second, independent single-validator Besu chain (chainId
  `138802`), surfaced as its own FireFly namespace (`besu2`, gateway mode) via
  **firefly-evmconnect2** — see "A second, independent Besu chain" below.

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

> **Do not generate a fresh `BESU_VALIDATOR_KEY`.** Unlike `SIGNER_KEY` (any new random
> key works fine there), this one is NOT interchangeable: `genesis.json`'s `extraData`
> hardcodes a specific validator address, and if the key you run with doesn't derive to
> that exact address, Besu boots fine, answers RPC calls fine, and silently never
> produces a single block -- it's just not in the validator set, so it has no authority
> to propose. This happened once deploying this exact repo: a freshly-generated key was
> pasted into `BESU_VALIDATOR_KEY` on Render, the service showed "Deployed", RPC worked,
> and `eth_blockNumber` sat at `0x0` for 15+ minutes with zero IBFT log lines before
> anyone noticed. Use the one key below, on every environment, forever (unless you
> regenerate both together per the next paragraph).

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

## A second, independent Besu chain -- wired into FireFly as its own namespace

`firefly-besu2` (`services/besu2/`) is a second single-validator IBFT2 chain, chainId
`138802`, built the exact same way as `firefly-besu` but with its own fresh genesis +
validator key.

Same rules as the first chain: `services/besu2/genesis.json` is committed, the matching
`BESU_VALIDATOR_KEY` (set on `firefly-besu2`'s own env var, independent of
`firefly-besu`'s) is not, and it must be the exact key generated for *this* genesis —
reusing `firefly-besu`'s key here (or vice versa) just gets you a node that answers RPC
calls and never produces a block, same failure mode documented above.

Unlike `firefly-besu`, this chain IS visible from FireFly -- as a **second namespace**,
not inside "default". A FireFly namespace in multiparty mode is tied to exactly one
blockchain (one BatchPin contract), so two chains means two namespaces, not two
blockchain plugins under one namespace. The `besu2` namespace runs in **gateway mode**
(no `multiparty` block, no contract, no org/node) since nothing needs broadcasting --
it exists to prove chain connectivity, not to run multi-party flows:
```yaml
# services/core/firefly.core.yml.template
namespaces:
  predefined:
    - name: besu2
      plugins:
        - database0   # shared across namespaces, scoped internally by namespace column
        - blockchain1
plugins:
  blockchain:
    - name: blockchain1
      type: ethereum
      ethereum:
        ethconnect:
          url: "${EVMCONNECT2_URL}"
          topic: "1"   # must differ from blockchain0's topic "0"
```
`firefly-evmconnect2` connects **directly** to `firefly-besu2` -- no signer in between,
since gateway mode has nothing to sign. It reuses `services/evmconnect`'s image
unchanged; `BESU_HOST` (rather than `SIGNER_HOST`) tells its entrypoint to skip the
signer and build `BLOCKCHAIN_RPC_URL` straight from the chain.

Switch to it in the UI via the namespace picker, or hit its own status directly:
```bash
curl -s http://localhost:5050/api/v1/namespaces/besu2/status   # or firefly-core's public URL on Render
```
Verified locally: both namespaces start side by side (`Initialized namespace 'default'
multiparty=true` and `Initialized namespace 'besu2' multiparty=false` in the logs), and
`/ui/namespaces/besu2/home` loads.

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
— no constructor args, and the file has two `"bin"` fields: the real one is the first,
longer match -- the second belongs to the `IBatchPin` interface and is empty). Deploy
it through the signer exactly like any other transaction.

*Locally* (both `firefly-core`'s image and `curl` are on your host):
```bash
docker run --rm --entrypoint sh ghcr.io/hyperledger-firefly/firefly:v1.5.0 \
  -c "cat /firefly/contracts/Firefly.json" > /tmp/Firefly.json
BIN=$(grep -o '"bin":"[0-9a-f]*"' /tmp/Firefly.json | head -1 | sed 's/"bin":"//;s/"$//')

curl -s -X POST -H "Content-Type: application/json" --data '{
  "jsonrpc":"2.0","method":"eth_sendTransaction",
  "params":[{"from":"<your signer address>","data":"0x'"$BIN"'","gas":"0x3D0900","gasPrice":"0x0"}],
  "id":1
}' http://localhost:8555
# then eth_getTransactionReceipt against localhost:8546 (besu) for "contractAddress"
```

*On Render*, `firefly-signer` is a `pserv` — not reachable from your machine or the
internet, only from other services on the project's private network. Use Render's
**Shell** tab on the `firefly-core` service (it's on the same private network, and its
image has `curl` but not Python, hence the `grep`/`sed` extraction instead of a JSON
parser) and run, verbatim:
```bash
BIN=$(grep -o '"bin":"[0-9a-f]*"' /firefly/contracts/Firefly.json | head -1 | sed 's/"bin":"//;s/"$//')

curl -s -X POST -H "Content-Type: application/json" --data '{
  "jsonrpc":"2.0","method":"eth_sendTransaction",
  "params":[{"from":"<your signer address>","data":"0x'"$BIN"'","gas":"0x3D0900","gasPrice":"0x0"}],
  "id":1
}' http://firefly-signer:8545
```
Then `eth_getTransactionReceipt` the same way against `http://firefly-besu:8545` for
`"contractAddress"`. This assumes Render's private network resolves other services by
their plain service name from any service's shell, not just ones wired via
`fromService` — that's the one piece of this whole Render-specific flow that hasn't
been run against a real account; everything above the "On Render" line has.

Set `ORG_SIGNING_KEY` (the signer's address) and `BATCHPIN_CONTRACT_ADDRESS` on
`firefly-core`, then redeploy it.

## Multiparty mode: registering your identity

Once `firefly-core` is up with a resolved BatchPin contract (`/api/v1/status` shows
`multiparty.enabled: true` and a `contract.active`), org and node still show
`registered: false` until you claim them — this broadcasts a message through IPFS +
the BatchPin contract, so it also proves the whole multiparty pipeline works. Run this
against `http://localhost:5050` locally, or `firefly-core`'s public `*.onrender.com`
URL on Render (this one IS public, unlike the signer):
```bash
curl -s -X POST http://localhost:5050/api/v1/network/organizations/self -d '{}'
# wait a few seconds for it to batch, publish to IPFS, and pin on-chain, then:
curl -s -X POST http://localhost:5050/api/v1/network/nodes/self -d '{}'
```
Check `/api/v1/status` or the **Network** tab in the UI (`/ui`) afterwards — both
should show `registered: true`. If the node claim 404s with "Identity could not be
resolved", the org claim hasn't confirmed on-chain yet; wait ~10s and retry.

**Known limitation: there's no working "update profile" call.** If you register the
node, then change `DATAEXCHANGE_PUBLIC_HOST` (or anything else in its profile) and
re-POST `/network/nodes/self` -- even passing the existing identity's `id` in the
body -- FireFly doesn't treat it as an update. It generates a brand new claim for a
new identity UUID, which then gets rejected on confirmation: `FF10407: Rejected
identity claim '<new-id>' - conflicts with existing: '<old-id>'`. The already-published
profile (cert, endpoint) is stuck with whatever was true the first time you registered.
Get `DATAEXCHANGE_PUBLIC_HOST` right *before* that first registration if you can; if
you're stuck with a stale profile afterwards, this needs more investigation (something
under `/identities` rather than `/network/nodes/self` is the likely right tool, but
that wasn't found/verified here) -- or just accept it until you actually need a second
org to dial into this node correctly.

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
3. Render will create `firefly-db`, `firefly-besu`, `firefly-besu2`, `firefly-signer`,
   `firefly-ipfs`, `firefly-evmconnect`, `firefly-evmconnect2`, `firefly-dataexchange`,
   `firefly-core` from `render.yaml`.
4. Set the `sync: false` env vars in the dashboard before the first deploy:
   - `firefly-besu` → `BESU_VALIDATOR_KEY` (see "Connecting to Besu" above)
   - `firefly-besu2` → `BESU_VALIDATOR_KEY` (its OWN key, see "A second, independent
     Besu chain" above — don't reuse `firefly-besu`'s)
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
services/evmconnect/         Blockchain connector image, reused as-is for both firefly-evmconnect and firefly-evmconnect2
services/signer/             Holds the org's signing key, generates its own keystore on first boot
services/besu/               Single-validator IBFT2 chain (genesis.json committed, key is not)
services/besu2/              A second, independent IBFT2 chain -- its own "besu2" namespace in FireFly
services/dataexchange/       Org-to-org data exchange (public-facing), generates its own TLS cert on first boot
services/ipfs/               Shared storage backend
scripts/check-config.sh      Sanity checks before deploying
```
