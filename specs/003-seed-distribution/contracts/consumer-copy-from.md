# Contract: Consumer-Side `COPY --from=` Recipe

**Feature**: [../spec.md](../spec.md)

This is the integration surface for downstream Dockerfiles. The
`lambdasistemi/amaru-bootstrap#15` PR uses this snippet verbatim. Any
future consumer (Antithesis testnet, internal stacks, third-party) is
expected to follow the same shape.

## Minimal Dockerfile snippet

```dockerfile
# 1. Pull a specific seed by primary content tag.
ARG SEED_REF=ghcr.io/lambdasistemi/cardano-testnet-seed:local-fast-<scenarioDigest>

FROM ${SEED_REF} AS seed
FROM ghcr.io/intersectmbo/cardano-node:10.7.1

# 2. Copy the seed payload into the node's working tree.
COPY --from=seed /seed/chain-db   /db
COPY --from=seed /seed/genesis    /genesis
COPY --from=seed /seed/pools      /pools
COPY --from=seed /seed/utxo-keys  /utxo-keys
```

## Compose-snippet variant

```yaml
services:
  seed:
    image: ghcr.io/lambdasistemi/cardano-testnet-seed:local-fast-<scenarioDigest>
    command: ["true"]            # the image has no entrypoint; it exists to be COPYed from

  node:
    image: ghcr.io/intersectmbo/cardano-node:10.7.1
    depends_on:
      - seed
    volumes:
      - seed-vol:/seed:ro
    # … node-specific environment, entrypoint, etc.

volumes:
  seed-vol:
    # populated by an init-container or an out-of-band `docker create + cp` step
```

> Compose itself does not have a primitive for `COPY --from=` between
> images. Two production-ready patterns:
>
> 1. **Build a wrapper image** in CI that already contains the seed (the
>    Dockerfile snippet above).
> 2. **Use an init-container** that pulls the seed image and `cp`s
>    `/seed/` into a shared named volume before the node starts.
>
> Either works; pick based on whether the consumer wants pull-time or
> startup-time integration.

## Pinning policy

| Strength | What you write | When to use |
|---|---|---|
| Strongest | `…@sha256:<manifest-digest>` | release branches, audited stacks |
| Strong   | `…:<scenario>-sha-<commitShort>` | per-commit reproducer |
| Default  | `…:<scenario>-<scenarioDigest>` | most consumers |

Never pin a non-existent moving tag (none are published; any such pin
will fail to resolve).

## What changes when the seed is updated

- New baker commit + same scenario JSON → primary tag re-resolves to a
  manifest with the *same* `manifestDigest` (Feature 003's determinism
  invariant). Consumers feel no change.
- Scenario JSON changes → primary tag changes (digest changed).
  Downstream PRs update their `ARG SEED_REF`.
- Baker commit changes but scenario JSON unchanged → secondary tag
  changes (its commit short SHA changes); primary tag is unaffected.

## Failure modes the consumer may observe

| Symptom | Cause | Consumer action |
|---|---|---|
| `manifest unknown` on pull | Tag was never published, or typo in the tag | Verify the tag matches a digest emitted by a real baker run |
| Bytes inside `/seed/` differ from `synthesis-report.json` | Bug — file an issue against this repo | n/a, this is a producer-side regression |
| Image works in `docker pull` but `docker buildx` fails on `COPY --from=` | buildx requires images to declare their platform; this image declares `linux/amd64` only | Either build with `--platform linux/amd64` or ask for multi-arch support (current scope: amd64 only) |
