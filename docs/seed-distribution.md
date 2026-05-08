# Seed Image Distribution

Every push to `main` and every pull-request branch publishes a
deterministic, content-addressable OCI seed image for every committed
scenario under
`ghcr.io/lambdasistemi/cardano-testnet-seed`. Each scenario is
published under two tags: a content-derived *primary* tag and a
commit-traceable *secondary* tag.

This page consolidates the maintainer / reviewer / consumer flows.
Detailed motivation, decisions, and contracts live under
[`specs/003-seed-distribution/`](../specs/003-seed-distribution/).

## Tag scheme

```
ghcr.io/lambdasistemi/cardano-testnet-seed:<scenario>-<scenario-digest>
ghcr.io/lambdasistemi/cardano-testnet-seed:<scenario>-sha-<commit-sha-short>
```

- `<scenario>` is the file name (without `.json`) of a committed
  `examples/scenarios/<scenario>.json`.
- `<scenario-digest>` is the SHA-256 of the canonical scenario JSON
  (64 lowercase hex chars). It re-resolves to the same bytes for as
  long as the scenario JSON content is unchanged.
- `<commit-sha-short>` is the first 7 hex chars of the baker repo's
  commit SHA at publish time. Even if the scenario content reverts to
  something with the same digest, this tag will not be reused for
  another commit.

Both `latest` and any moving tag (`main`, branch names, `next`,
`dev`, `prod`) are explicitly forbidden by the publish pipeline; see
[`contracts/artifact-identifier-scheme.md`](../specs/003-seed-distribution/contracts/artifact-identifier-scheme.md)
for the grammar and pinning guidance.

## Image layout

The image is `scratch`-based, single-layer, no entrypoint. Under
`/seed/` you get the same tree the baker writes locally — see
[`contracts/seed-image-layout.md`](../specs/003-seed-distribution/contracts/seed-image-layout.md)
for the canonical layout and file-mode contract.

## A. Maintainer — dry-run a publish locally before pushing

```bash
cd /code/cardano-testnet-baker

# 1. Build images for every committed scenario. Each `result-...`
#    symlink is a materialised docker-archive.
nix build -L \
  --out-link result-seedImage-local-fast .#seedImage-local-fast \
  --out-link result-seedImage-normal     .#seedImage-normal

# 2. Inspect the manifest digest and layer digest for a scenario.
nix run nixpkgs#skopeo -- \
  inspect --raw "docker-archive:$(readlink -f result-seedImage-local-fast)" \
  | jq '.config.digest, .layers[].digest'

# 3. Read the tags the publish job *would* push (without pushing).
just publish-seed-images --dry-run

# 4. (Optional) Smoke-test the seed by running the compose
#    acceptance harness directly against the freshly built image.
compose/acceptance/run.sh local-fast \
  "docker-archive:$(readlink -f result-seedImage-local-fast)"
```

`just publish-seed-images --dry-run` prints exactly four stdout
lines (two scenarios × two tags), each in the form
`<scenario>  <target-uri>`:

```text
local-fast  ghcr.io/lambdasistemi/cardano-testnet-seed:local-fast-3a9f…2c1
local-fast  ghcr.io/lambdasistemi/cardano-testnet-seed:local-fast-sha-832deb6
normal      ghcr.io/lambdasistemi/cardano-testnet-seed:normal-7e80…f44
normal      ghcr.io/lambdasistemi/cardano-testnet-seed:normal-sha-832deb6
```

Push happens only in CI; the maintainer never `skopeo`s by hand.

## B. Reviewer — verify a published image offline

```bash
# 1. Check out the baker at the commit SHA the registry advertises.
git fetch origin
git checkout 832deb6  # the secondary tag's <commit-sha-short>

# 2. Build the image locally (materialised archive at result-...).
nix build --out-link result-seedImage-local-fast .#seedImage-local-fast

# 3. Read the local manifest digest.
nix run nixpkgs#skopeo -- \
  inspect --raw "docker-archive:$(readlink -f result-seedImage-local-fast)" \
  | jq -r '.config.digest'
# → sha256:<64 hex>

# 4. Pull the digest of the registry image *without trusting it*.
nix run nixpkgs#skopeo -- \
  inspect --raw \
  "docker://ghcr.io/lambdasistemi/cardano-testnet-seed:local-fast-sha-832deb6" \
  | jq -r '.config.digest'

# 5. Compare. Equal ⇒ the registry image is byte-identical to the
#    locally source-built image at this commit.
```

If the digests differ, the producer has lost determinism — file an
issue against this repo with both digests. The build gate's
`seed-image-determinism` check runs on every push for exactly this
reason; see
[`contracts/publish-pipeline.md §"Determinism check"`](../specs/003-seed-distribution/contracts/publish-pipeline.md)
for what the gate proves and what it deliberately does not.

## C. Downstream consumer — pin and use a seed

In a downstream Dockerfile:

```dockerfile
ARG SEED_REF=ghcr.io/lambdasistemi/cardano-testnet-seed:local-fast-3a9f…2c1

FROM ${SEED_REF} AS seed
FROM ghcr.io/intersectmbo/cardano-node:10.7.1

COPY --from=seed /seed/chain-db   /db
COPY --from=seed /seed/genesis    /genesis
COPY --from=seed /seed/pools      /pools
COPY --from=seed /seed/utxo-keys  /utxo-keys
```

For a per-commit pin (audit / post-mortem), use the secondary tag:

```dockerfile
ARG SEED_REF=ghcr.io/lambdasistemi/cardano-testnet-seed:local-fast-sha-832deb6
```

For the strongest pin (recommended for release branches), promote
either tag to a manifest digest:

```dockerfile
ARG SEED_REF=ghcr.io/lambdasistemi/cardano-testnet-seed@sha256:<manifestDigest>
```

See
[`contracts/consumer-copy-from.md`](../specs/003-seed-distribution/contracts/consumer-copy-from.md)
for the consumer-side copy contract (which directories are stable,
which are out of contract).

## CI surfaces

- **`Build Gate`** runs
  `nix build .#checks.x86_64-linux.seed-image-determinism`. Every
  push has the determinism gate enforced before any acceptance or
  publish path runs.
- **`Compose acceptance`** builds each scenario's seed image and
  runs `compose/acceptance/run.sh <scenario> docker-archive:<archive>`
  against it. Publishing only proceeds when every scenario's verdict
  is `accepted`.
- **`Publish seed images`** runs after both jobs above are green; it
  authenticates `skopeo` against `ghcr.io` via the workflow's
  `${{ github.token }}` and invokes `nix run .#publishSeedImages`.

## Frequently asked questions

**Q. Why no `:latest` tag?**
Constitution §III pinning principle: every consumer-visible
identifier must point to a stable artifact. `latest` invariably
becomes load-bearing in some downstream where it should not be.

**Q. The `normal` build takes ~2 minutes; does that fail PR
checks?**
No, the existing pipeline already accepts that cost from Feature
002. This feature adds another ~3 minutes for image build + push
(SC-005).

**Q. How do I add a new scenario?**
Drop a JSON file into `examples/scenarios/<name>.json`. Both the
schema-validation check and the seed-image publish job pick it up
automatically.

**Q. Is the image signed?**
v1 ships unsigned. A follow-up will introduce cosign keyless. To
verify integrity in v1, compare the registry digest to a locally
built one — the determinism invariant lets you reproduce offline.
