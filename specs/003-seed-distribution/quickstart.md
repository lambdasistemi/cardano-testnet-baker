# Quickstart: Synthesized Seed Distribution

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)
**Date**: 2026-05-08

Three audiences, three flows.

## A. Maintainer — dry-run a publish locally before pushing

```bash
cd /code/cardano-testnet-baker

# 1. Build images for every committed scenario.
#    Each `result-...` symlink is a materialized docker-archive
#    (buildLayeredImage), readable directly by skopeo.
nix build -L \
  --out-link result-seedImage-local-fast .#seedImage-local-fast \
  --out-link result-seedImage-normal     .#seedImage-normal

# 2. Inspect the manifest digest for a scenario.
nix run nixpkgs#skopeo -- \
  inspect --raw "docker-archive:$(readlink -f result-seedImage-local-fast)" \
  | jq '.config.digest, .layers[].digest'

# 3. Read tags the publish job *would* push (without pushing).
nix run .#publishSeedImages -- --dry-run

# 4. (Optional) Smoke-test the seed inside the freshly built image.
compose/acceptance/run.sh local-fast \
  "docker-archive:$(readlink -f result-seedImage-local-fast)"
```

`--dry-run` prints lines of the form:

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
git checkout 832deb6  # the secondary tag's <bakerCommitSha7>

# 2. Build the image locally (materialized archive at result-...).
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

# 5. Compare. Equal ⇒ the registry image is byte-identical to source-built.
```

If the digests differ, the producer has lost determinism — file an issue
against this repo with both digests.

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

For the strongest pin (recommended for release branches), promote either
tag to a manifest digest:

```dockerfile
ARG SEED_REF=ghcr.io/lambdasistemi/cardano-testnet-seed@sha256:<manifestDigest>
```

## Determinism check (CI)

The `Build Gate` job runs `nix build .#checks.x86_64-linux.seed-image-determinism`.
That check builds each committed scenario's image twice and asserts that
the OCI manifest digests match. Any divergence fails the gate.

## Compose acceptance against the pulled image (CI)

The `compose-acceptance` job invokes
`compose/acceptance/run.sh <scenario> docker-archive:<built-image>`,
which extracts `/seed/` to a tmpfs and runs the existing node startup
probe against it. Publishing only proceeds when the verdict is
`accepted`.

## Frequently asked questions

**Q. Why no `:latest` tag?**
A. Constitution §III pinning principle: every consumer-visible
identifier must point to a stable artifact. `latest` invariably becomes
load-bearing in some downstream where it should not be.

**Q. The `normal` build takes ~2 minutes; does that fail PR checks?**
A. No, the existing pipeline already accepts that cost from Feature 002.
This feature adds another ~3 minutes for image build + push (SC-005).

**Q. How do I add a new scenario?**
A. Drop a JSON file into `examples/scenarios/<name>.json`. Both the
schema-validation check and the seed-image publish job pick it up
automatically.

**Q. Is the image signed?**
A. v1 ships unsigned. A follow-up will introduce cosign keyless. To
verify integrity in v1, compare the registry digest to a locally built
one — the determinism invariant lets you reproduce offline.
