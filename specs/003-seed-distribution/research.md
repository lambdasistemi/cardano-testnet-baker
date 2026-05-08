# Research: Synthesized ChainDB Seed Distribution

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)
**Date**: 2026-05-08

This file consolidates the empirical and procedural decisions made before
implementation, so they are not re-litigated in code review. Each section
records: Decision, Rationale, Alternatives considered.

## 1. Image builder — `streamLayeredImage` vs `buildLayeredImage`

**Decision**: prefer `pkgs.dockerTools.streamLayeredImage`; fall back to
`pkgs.dockerTools.buildLayeredImage` only if streaming produces a different
manifest digest across two consecutive `nix build` invocations under our
existing pin set.

**Rationale**: `streamLayeredImage` produces a *script* that emits a
docker-archive on stdout — the layer hashes and manifest are
content-derived from inputs and the script itself is a fixed-output
derivation only when its output is consumed. The Nix store path is
deterministic given identical inputs. `buildLayeredImage` materializes the
archive inside the Nix store; both are deterministic in principle, but
`streamLayeredImage` avoids a second copy of the bake output's bytes inside
the store and pipes more cleanly into `skopeo copy
docker-archive:/dev/stdin docker://…`. Net effect: faster build, lower
disk pressure, same manifest semantics.

**Alternatives considered**:

- `buildLayeredImage` — equally deterministic, doubles disk usage at build
  time. Acceptable fallback if streaming reveals a stability issue.
- `dockerTools.buildImage` (single-layer) — works, but `dockerTools`
  guidance prefers the layered variants for cache friendliness even at one
  layer; no concrete reason to prefer it.
- Hand-rolling an OCI manifest from `pkgs.runCommand` — strictly more code
  to maintain, no benefit. Rejected.

**Verification**: the CI determinism check builds the image twice and
compares the manifest digest extracted via `skopeo inspect
docker-archive:…`. Fail loud if they differ.

## 2. Registry push tool — `skopeo` vs `docker`

**Decision**: use `skopeo copy
docker-archive:<path> docker://ghcr.io/lambdasistemi/cardano-testnet-seed:<tag>`.

**Rationale**:

- `skopeo` does not require a running `dockerd`. The publish job runs on
  `runs-on: nixos`, where Docker is not assumed to be available; pulling
  in `dockerd` just to push an image is heavyweight and brittle.
- `skopeo` accepts `docker-archive:/dev/stdin`, allowing the
  `streamLayeredImage` script to pipe directly into the push:
  `nix run .#seedImage-<scenario>-stream | skopeo copy
  docker-archive:/dev/stdin docker://…:<tag>`.
- `skopeo` supports both `--src-tls-verify` and `--dest-tls-verify`,
  required by the constitution's pinning principle when validating remote
  manifests.
- The same tool covers `inspect` (for the determinism digest comparison)
  and `copy` (for the tag fan-out).

**Alternatives considered**:

- `docker load && docker push` — requires `dockerd`, requires the
  `compose-acceptance` runner type (`ubuntu-latest`), splits the publish
  flow across two runner classes. Rejected for operational complexity.
- `crane` — capable, but adds another binary not already in the shell.
  Rejected.

## 3. Runner choice for the publish job

**Decision**: `runs-on: nixos` for `seed-image-publish`. Push the image
from the same self-hosted runner that built it, eliminating an extra
upload-cache-download round trip.

**Rationale**: the constitution mandates `runs-on: nixos` for nix-driven
jobs. The image build is a pure nix derivation and benefits from the
shared `paolino.cachix.org` cache. `skopeo` runs equally well there. No
benefit to switching runner types.

**Alternatives considered**:

- `ubuntu-latest` — would let us reuse the Docker daemon already present
  for compose acceptance, but contradicts the rule and forfeits the cache.
- A separate self-hosted Linux runner without Nix — no operational reason
  to introduce one.

## 4. Why no Haskell change is needed

**Decision**: do not modify any Haskell module. Tag derivation is a `jq`
expression over `metadata.json`; image assembly is `dockerTools` over the
existing baker package output.

**Rationale**: Feature 002 already emits `metadata.json` with
`scenarioId`, `scenarioDigest`, and `bakerVersion`. Computing
`<scenario>-<scenarioDigest>` and `<scenario>-sha-<bakerCommitSha7>` from
those values is a five-line shell snippet; promoting it into Haskell adds
test surface, build time, and a CLI subcommand for no operational gain.
Keeps the change strictly additive at the Nix and shell layer, which is
where image distribution belongs.

**Alternatives considered**:

- A `cardano-testnet-baker tag` subcommand — possible if the tag scheme
  ever needs richer logic. Premature for v1.
- Reading the digest from the OCI manifest itself — only available *after*
  the image is built, but the tag must be known *before* the push. Rejected.

## 5. Compose acceptance — extend the existing harness, do not duplicate

**Decision**: extend `compose/acceptance/run.sh` to accept either:

- a directory path (current behavior, for local `bake` outputs), or
- an OCI archive path or `docker-archive:` URI from which the script
  extracts `/seed/` to a tmpfs before invoking the existing node startup
  probe.

Keep the directory mode the default for local development. The CI publish
flow always invokes the OCI-archive mode against the artifact about to be
pushed.

**Rationale**:

- The startup probe is the actual acceptance contract; what changes is
  only the source of the seed bytes. Sharing one script avoids a "the
  acceptance harness diverged from CI" class of bug.
- A tmpfs extraction cleanly separates artifact bytes (read-only, image)
  from node working state (writable, ephemeral) and matches the producer
  contract from Feature 002 ("immutable source artifacts copied to private
  writable node storage").

**Alternatives considered**:

- A second script — duplicates startup logic, drifts. Rejected.
- Loading the image into a local `dockerd` and binding `/seed/` from a
  named volume — requires `dockerd` on the runner, which we explicitly
  avoid (decision §2). Rejected.

## 6. Authentication to GHCR

**Decision**: the publish job authenticates with the workflow's
auto-issued `${{ github.token }}`, scoped to `packages: write` for that
job only. No long-lived PAT, no organization-wide secret.

**Rationale**: constitution §III pinning principle plus general supply
chain hygiene. The workflow OIDC token is already scoped to the
repository and revoked at job end.

**Alternatives considered**:

- A `lambdasistemi`-org PAT — broader blast radius, manual rotation,
  rejected.

## 7. Secondary tag short-SHA length

**Decision**: 7 hex characters (`<scenario>-sha-<bakerCommitSha7>`).

**Rationale**: matches `git log --pretty=%h` default and the rest of the
ecosystem. 7 chars × 16⁷ ≈ 268 M values; collision risk in this repo is
nil.

**Alternatives considered**:

- 12 chars — overkill for a per-repo namespace.
- Full 40-char SHA — readable but verbose; `:scenario-sha-<40hex>` reads
  badly. Rejected.

## 8. Failure semantics for partial publishes

**Decision**: the publish step is "all-or-nothing per scenario". The
script first pushes the primary tag, then the secondary tag, and treats a
secondary-tag failure as an overall job failure (so the run is marked
red even though the primary tag did succeed). It does not attempt a
rollback (GHCR has no "delete a tag" semantics that matter here — a
re-run will re-attach both tags to the same content-addressed manifest).

**Rationale**: registry pushes of the *same content* are idempotent in
practice — re-running the workflow re-attaches both tags to the same
manifest digest. The visible failure on partial publish ensures a human
notices.

**Alternatives considered**:

- Push a transactional "manifest list" with both tags attached at once —
  not a primitive registries actually offer; tag attachment is sequential.
- Silent ignore on second-tag failure — hides a misconfiguration. Rejected.
