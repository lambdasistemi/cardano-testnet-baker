# Contract: Publish Pipeline Ordering & Failure Modes

**Feature**: [../spec.md](../spec.md)

This contract specifies the *order* in which the publish pipeline
performs its steps, *what fails the job*, and *what side effects* are
expected at each stage. Implementation details (which Nix expressions,
which CI YAML keys) live in plan.md/tasks.md; this is the behaviour
contract.

## Steps (per scenario, in order)

```text
1.  bake
2.  build seed image (oci-archive on disk, deterministic)
3.  extract /seed/ from the archive into a tmpfs path
4.  run compose/acceptance/run.sh against that tmpfs path
5.  derive primary and secondary tags from metadata.json + commit short SHA
6.  validate tags against the forbidden-tag list
7.  skopeo copy archive  →  ghcr.io/.../cardano-testnet-seed:<primary>
8.  skopeo copy archive  →  ghcr.io/.../cardano-testnet-seed:<secondary>
9.  emit a one-line summary (scenario, primary tag, secondary tag, manifest digest)
```

`build-gate` and the existing `compose-acceptance` job remain as they
are. The new `seed-image-publish` job depends on `build-gate` and runs
the steps above for every committed scenario.

## Determinism check

A separate Nix-side check (`seed-image-determinism`) builds each
scenario's image twice in the same CI run, extracts the manifest
digest from each archive, and fails if they differ. Order:

```text
build A → build B → skopeo inspect docker-archive:A → skopeo inspect docker-archive:B → diff
```

The determinism check is wired into the `Build Gate` job alongside the
existing checks (so any digest divergence fails the gate, not the
later publish job).

## Failure modes

| Failure | Effect on the run |
|---|---|
| `bake` fails | Job red, no image built, no push. (Already covered by Feature 002 acceptance gates.) |
| Image build is non-deterministic (digests differ) | `seed-image-determinism` check fails inside Build Gate. Job red, never reaches push. |
| `compose/acceptance/run.sh` returns `verdict=rejected` | `seed-image-publish` fails; no `skopeo` invocation. |
| Tag derivation fails (e.g. missing `inputDigest` in `metadata.json`) | Job red; this is a producer-side regression and is treated as such. |
| Tag validation rejects a derived tag | Job red. (Sentinel against accidentally regenerated forbidden tags.) |
| `skopeo copy` to primary tag fails | Job red. No second push attempted. |
| `skopeo copy` to secondary tag fails | Job red. Primary tag is already attached and remains so; a re-run idempotently re-attaches both. |

## Idempotency

The publish flow is idempotent at the registry: re-running the same
commit pushes the same content-addressable manifest digest to the same
tags. No new image is created in the registry; the existing manifest
gains the same tags it already has. This is the recovery path for
partial-failure scenarios.

## Concurrency

Concurrency is governed by the workflow-level
`group: ${{ github.workflow }}-${{ github.ref }}` already in place.
Two simultaneous runs on the same branch cannot race the registry.

## Authentication

The publish job uses `${{ github.token }}` with the
`packages: write` permission scoped to the job. No long-lived PAT is
used. If the token cannot push, the job fails — never silently skip
the push.

## Out-of-scope failure modes (deferred)

- Signing failure — v1 has no signing.
- Multi-arch manifest list assembly — v1 is single-arch.
- Retention pruning failure — v1 retains all images.
