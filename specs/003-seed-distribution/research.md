# Research: Synthesized ChainDB Seed Distribution

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)
**Date**: 2026-05-08

This file consolidates the empirical and procedural decisions made before
implementation, so they are not re-litigated in code review. Each section
records: Decision, Rationale, Alternatives considered.

## 1. Image builder — `buildLayeredImage` over `streamLayeredImage`

**Decision**: use `pkgs.dockerTools.buildLayeredImage` so that
`nix build .#seedImage-<scenario>` produces a *materialized*
docker-archive on disk (the result symlink points at a tarball, not a
stream script). All downstream tooling — `skopeo inspect docker-archive:`,
`skopeo copy docker-archive:`, the determinism check — can then read the
archive directly without an intermediate pipe-to-disk step.

**Rationale**: `streamLayeredImage` produces a script whose stdout is
the archive. That works for piping into `skopeo copy
docker-archive:/dev/stdin`, but it forces every other tool that wants to
*inspect* the archive — the determinism gate, the `seed-image-acceptance`
check, the maintainer's local `skopeo inspect` — to first run the script
into a temp file. Two paths means two opportunities for divergence (the
inspect path uses a fresh archive every invocation, the push path uses a
fresh archive every invocation; if either differs, false-positive
determinism failures appear). `buildLayeredImage` collapses that to one
materialized artifact: `result` *is* the archive, every consumer reads
the same bytes.

**Cost**: one extra copy of the seed bytes (~22 MB per scenario) lives
in the Nix store. Negligible at this scale.

**Alternatives considered**:

- `streamLayeredImage` — leaner store, but doubles tool surface and
  invites the divergence described above. Originally chosen here, then
  reversed once review pointed out that the quickstart and tasks both
  assumed an archive output. Rejected.
- `dockerTools.buildImage` (non-layered) — works for a single-layer
  image, but `buildLayeredImage` is the modern default and gives the
  registry the option to share blobs across pushes if a layer ever
  becomes shared. No reason to opt out.
- Hand-rolling an OCI manifest from `pkgs.runCommand` — strictly more
  code, no benefit. Rejected.

**Verification**: the CI determinism check runs `nix build` twice and
compares the manifest digest extracted via
`skopeo inspect docker-archive:./result-<scenario>`. Fail loud if they
differ.

## 2. Registry push tool — `skopeo` vs `docker`

**Decision**: use `skopeo copy
docker-archive:<path> docker://ghcr.io/lambdasistemi/cardano-testnet-seed:<tag>`.

**Rationale**:

- `skopeo` does not require a running `dockerd`. The publish job runs on
  `runs-on: nixos`, where Docker is not assumed to be available; pulling
  in `dockerd` just to push an image is heavyweight and brittle.
- `skopeo` reads `docker-archive:<path>` directly, so the materialized
  archive produced by `buildLayeredImage` (research §1) feeds straight
  into both `inspect` and `copy` invocations:
  `skopeo copy docker-archive:$(readlink -f result-seedImage-<scenario>)
   docker://ghcr.io/lambdasistemi/cardano-testnet-seed:<tag>`.
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
expression over `metadata.json`; image assembly is `dockerTools` over
the existing baker package output; `synthesis-report.json` projection
is `jq 'del(.observation)'`.

**Rationale**: Feature 002 already emits `metadata.json` with
`scenarioId`, `inputDigest`, `bakerVersion`, `bakerCommit`, and
`artifactDigests` (`src/Cardano/Testnet/Baker/Metadata.hs:74`).
Computing `<scenario>-<inputDigest>` and `<scenario>-sha-<bakerCommitSha7>`
from those values is a five-line shell snippet; promoting it into
Haskell adds test surface, build time, and a CLI subcommand for no
operational gain. Keeps the change strictly additive at the Nix and
shell layer, which is where image distribution belongs.

**Note on field naming**: `metadata.json` calls the canonical scenario
hash `inputDigest`; the synthesis report (when it exists) calls the
same value `scenarioDigest`. The publish app reads
`metadata.json.inputDigest` because metadata is always present and
deterministic. The consumer-facing tag fragment is named
`<scenarioDigest>` for the same reason it always has been: that is the
domain term consumers read. The translation is one line of `jq` and is
documented in
`contracts/artifact-identifier-scheme.md`.

**Alternatives considered**:

- A `cardano-testnet-baker tag` subcommand — possible if the tag scheme
  ever needs richer logic. Premature for v1.
- Reading the digest from the OCI manifest itself — only available
  *after* the image is built, but the tag must be known *before* the
  push. Rejected.
- Renaming `inputDigest` → `scenarioDigest` in the Haskell layer to
  make the names line up — out of scope for this feature, mechanical
  but breaking for any downstream that already parses `metadata.json`
  by name. Defer to a separate ticket if the inconsistency becomes
  load-bearing.

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

## 8. Synthesis-report determinism — strip `observation` at image-build time

**Decision**: when assembling the image, project
`synthesis-report.json` through `jq 'del(.observation)'` so the in-image
copy carries only the deterministic fields (`scenarioId`,
`scenarioDigest`, `bakerVersion`, `slotCount`, `profile`,
`chainDb.path`, `chainDb.bytes`, `chainDb.fileCount`,
`chainDb.packagedBytes`). The unpackaged bake output (in
`tmp/synthesis/<scenario>/`) keeps its full report including
`observation` for measurement purposes.

**Rationale**: Feature 002's contract
(`specs/002-chaindb-synthesis/contracts/artifact-layout.md`, Determinism
Rules) explicitly classifies `observation.startedAt`,
`observation.completedAt`, `observation.wallTimeMilliseconds`, and
`observation.host` as host-dependent. The existing
`example-bake-determinism` Nix check
(`nix/checks.nix:32`) already knows this — it diffs the output trees
with `--exclude synthesis-report.json` and then compares
`jq 'del(.observation)' synthesis-report.json` separately. Feature 003's
determinism gate (T002) needs the *image* manifest digest to be
byte-identical across rebuilds, which is impossible if the image
carries the timestamps. Stripping observation at image-build time
matches what 002 already does for its own determinism story and gives
consumers exactly the fields they actually need from a seed.

**Alternatives considered**:

- Drop `synthesis-report.json` from the image entirely — loses
  `slotCount`, `profile`, and `chainDb.*` size facts that consumers
  legitimately want. Rejected.
- Ship the full report, document the digest as "non-deterministic in
  observation but otherwise stable" — incompatible with FR-006 (image
  manifest digest byte-identical across rebuilds). Rejected.
- Modify the Haskell `synthesisReport` to omit observation entirely —
  out of scope; observation data is useful diagnostically in the
  unpackaged output. Rejected.
- Have the baker emit two reports (full + projected) — premature
  abstraction; the projection is a one-line `jq` at the image-build
  layer. Rejected.

## 9. Failure semantics for partial publishes

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
