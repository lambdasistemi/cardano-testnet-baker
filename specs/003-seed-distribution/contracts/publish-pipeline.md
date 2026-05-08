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
scenario's image twice (as two genuinely independent Nix derivations,
forced via a `derivationSuffix` parameter on `mkSeedImage` so they do
not share the inner `streamLayeredImage` derivation) and asserts that
the consumer-visible image identity is byte-identical across the
pair. Order:

```text
build A → build B → extract manifest+config+layer.tar from each → diff
```

Concretely the check verifies, per scenario, two distinct
properties of the published artifact:

1. **Deterministic seed payload.** Each archive carries exactly
   one layer; the two `layer.tar` payloads are byte-identical
   (`sha256sum` equal). This guards against host-clock or
   hostname leaks in the customisation layer — i.e. it ensures
   that the bytes of `/seed/...` a consumer reads after
   `COPY --from=` are a pure function of the source code and the
   flake lock.
2. **Stable image-config fields.** The two image configs' fields
   outside `history` are byte-identical under `jq 'del(.history)'`.
   The fields covered are `architecture`, `os`, `created`,
   `config`, and `rootfs.diff_ids` — everything that affects how
   a consumer interprets the layer and the surrounding metadata.

Plus a fixed-value invariant: `architecture == "amd64"`,
`os == "linux"`, and `created` begins with `1970-01-01T00:00:00`.
Mutating any of these in `nix/seed-image.nix` flips the
assertion.

The gate does *not* compare the OCI **manifest digest** between
the two test builds, and it does *not* compare the **config
digest** between them. It compares the deterministic seed payload
plus the stable consumer-facing config fields above. The next
section explains why "manifest digest equality across the two
test builds" is not the property the gate can or should enforce.

### Why the gate does not compare the manifest digest

`pkgs.dockerTools.streamLayeredImage` writes `history[].comment`
into the OCI image config as
`"store paths: ['/nix/store/<hash>-<customisation-layer-name>']"`.
Because the round-1 reviewer requirement is that the two test
builds be *genuinely independent* — so non-determinism in the
customisation layer is observable rather than masked by Nix's
eval cache — the two builds have, by construction, different
customisation-layer store paths. That divergence flows into
`history.comment`, into the config sha, and finally into the OCI
manifest digest.

So the literal property "byte-identical manifest digest across
two genuinely independent test builds" cannot hold for archives
produced by `dockerTools.streamLayeredImage` in this nixpkgs
vintage. The gate therefore checks something weaker but
sufficient for FR-006: the *seed payload* is byte-identical
across builds and the *consumer-facing config fields* are
byte-identical across builds. A consumer pulling the published
image by tag receives one specific manifest, with one specific
manifest digest; the gate guarantees that whatever digest CI
ends up pushing is a pure function of the source — i.e. two CI
runs of the same commit, with the same flake lock, push the
same manifest digest, even though that single-shot identity is
not what the in-derivation gate compares.

The check is wired into the `Build Gate` job alongside the
existing checks (so any layer-payload or meaningful-config
divergence fails the gate, not the later publish job).

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
