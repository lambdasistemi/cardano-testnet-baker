# Implementation Plan: Synthesized ChainDB Seed Distribution

**Branch**: `003-seed-distribution` | **Date**: 2026-05-08 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/003-seed-distribution/spec.md`

## Summary

Wrap the deterministic baker output produced by Feature 002 into a
content-addressable, seed-only OCI image and publish it to
`ghcr.io/lambdasistemi/cardano-testnet-seed`. Build the image via
`pkgs.dockerTools` from the existing baker derivation, derive primary and
secondary tags from the baker's already-emitted `scenarioDigest` plus the
short commit SHA, run the existing compose acceptance harness against the
seed extracted from the image about to be published, verify byte-identical
manifest digests across rebuilds, and document the consumer-side
`COPY --from=` snippet for the paired downstream PR in
`lambdasistemi/amaru-bootstrap#15`.

## Technical Context

**Language/Version**: Nix (image assembly, CI orchestration), Haskell GHC
9.12.3 via haskell.nix `ghc9123` (existing baker, unchanged)
**Primary Dependencies**: `pkgs.dockerTools.buildLayeredImage` (image
build, materialized archive), `skopeo` (registry push and inspect),
`jq` (tag derivation from `metadata.json.inputDigest`; deterministic
projection of `synthesis-report.json`), existing
`cardano-testnet-baker` CLI and `compose/acceptance/run.sh` harness
**Storage**: OCI image registry — `ghcr.io/lambdasistemi/cardano-testnet-seed`
**Testing**: Nix checks (`seed-image-determinism`,
`seed-image-acceptance`), GitHub Actions `seed-image-publish` job, dry-run
via `nix run .#publishSeedImages -- --dry-run`
**Target Platform**: `x86_64-linux` for the build runner; `linux/amd64`
single-arch manifest for the published image
**Project Type**: CLI + Nix-packaged image build + GitHub Actions publish
job + shell acceptance harness extension
**Performance Goals**: Add no more than ~3 minutes to the build gate
beyond the existing `normal` synthesis cost (per SC-005). Image build is
streaming and cache-friendly.
**Constraints**: No moving tags; image manifest digest must be
byte-identical across rebuilds at the same baker SHA; the seed payload
must remain a faithful copy of the baker output (no rewriting, no
post-processing); push must use `${{ github.token }}` (workflow OIDC),
never a long-lived PAT.
**Scale/Scope**: Two scenarios today (`local-fast`, `normal`), automatic
extension to any new committed scenario. Storage cost negligible (~22 MB
per scenario; retain forever).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Plan Evidence |
|-----------|--------|---------------|
| I. Declarative scenarios as single input | PASS | No new inputs introduced. Scenario JSON remains the only output-affecting input. The image is a packaging of the existing bake output. |
| II. Determinism by construction | PASS | `pkgs.dockerTools.buildLayeredImage` with `created = "1970-01-01T00:00:00Z"` plus a single layer of byte-identical bake output (with `synthesis-report.json` projected through `jq 'del(.observation)'` to drop host-dependent timestamps, per Feature 002's already-established determinism rule) yields a stable manifest. CI determinism check rebuilds and diffs the manifest digest via `skopeo inspect docker-archive:`. |
| III. Reproducibility by pinning | PASS | Every published tag is content- or SHA-derived (`<scenario>-<scenarioDigest>`, `<scenario>-sha-<bakerCommitSha7>`). No `:latest`, no `:main`, no branch-named tags. |
| IV. Nix-first, haskell.nix | PASS | Image is a flake output (`packages.<system>.seedImage-<scenario>`); CI uses `nix build` and `nix run`, never `nix develop -c`. |
| V. Stock tools, custom orchestration | PASS | `dockerTools` and `skopeo` are stock nixpkgs. No fork, no vendoring. |
| VI. Smallest provable step | PASS | Compose acceptance runs against the seed extracted from the *image about to be published*, not against an unpackaged baker tree. v1 ships unsigned; cosign deferred to a follow-up issue. |

## Project Structure

### Documentation (this feature)

```text
specs/003-seed-distribution/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── artifact-identifier-scheme.md
│   ├── consumer-copy-from.md
│   ├── publish-pipeline.md
│   └── seed-image-layout.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
nix/
├── checks.nix                    # extended with seed-image-determinism, seed-image-acceptance
├── seed-image.nix                # NEW: pkgs.dockerTools.buildLayeredImage from a baked scenario, with synthesis-report projected
└── seed-publish.nix              # NEW: app that iterates scenarios and shells out to skopeo

flake.nix                         # NEW outputs: packages.seedImage-<scenario>, apps.publishSeedImages

compose/acceptance/
└── run.sh                        # extended: accept directory OR oci-archive ref; extract /seed/ to tmpfs

.github/workflows/
└── ci.yml                        # NEW job: seed-image-publish, gated on Build Gate + compose-acceptance

justfile                          # NEW recipe: publish-seed-images (wraps nix run .#publishSeedImages)

docs/
└── seed-distribution.md          # NEW: consumer-side documentation; linked from README

README.md                         # add a "Consuming the seed image" section linking docs/seed-distribution.md
```

**Structure Decision**: this feature adds two thin Nix modules (`seed-image.nix`,
`seed-publish.nix`), extends `compose/acceptance/run.sh`, adds one CI job, one
justfile recipe, and one consumer-facing documentation file. It does not add
new Haskell modules — image assembly and tag derivation are pure Nix + jq
work, and the deterministic payload is already produced by Feature 002.

## Phase 0 Output

`research.md` records the empirical and procedural decisions that should
not be re-discussed at implementation time:

1. **`buildLayeredImage` over `streamLayeredImage`** — materialized
   archive so all consumers (inspect, copy, determinism check) read the
   same `result` symlink.
2. **`skopeo copy` vs `docker load + docker push`** on the runner.
3. **Runner type** for the publish job (`runs-on: nixos`).
4. **Why no Haskell change is needed** for tag derivation; note that
   `metadata.json.inputDigest` is the field the publish app reads (the
   consumer-facing tag fragment is named `<scenarioDigest>` per the
   identifier scheme contract).
5. **Why `compose/acceptance/run.sh` extension is the right surface**.
6. **Synthesis-report normalization** — strip the `observation` block
   at image-build time so the in-image copy is deterministic, matching
   Feature 002's existing determinism rule for the report.

## Phase 1 Output

- `data-model.md` — entities, identifiers, payload layout.
- `contracts/artifact-identifier-scheme.md` — primary and secondary tag
  rules.
- `contracts/consumer-copy-from.md` — consumer Dockerfile snippet, MIME
  contract.
- `contracts/publish-pipeline.md` — bake → image → acceptance → push
  ordering and failure modes.
- `contracts/seed-image-layout.md` — exact `/seed/` tree the consumer
  receives.
- `quickstart.md` — maintainer dry-run, reviewer offline-reproduction
  walkthrough, downstream consumer recipe.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

(none)
