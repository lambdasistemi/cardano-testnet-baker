# Implementation Plan: Scenario JSON Schema and Bake CLI MVP

**Branch**: `001-scenario-bake-cli-plan` | **Date**: 2026-05-07 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/001-scenario-bake-cli/spec.md`

## Summary

Build the first production-shaped slice of `cardano-testnet-baker`: a Haskell
CLI that semantically validates a scenario JSON, derives deterministic Cardano
genesis/key artifacts from `scenario.seed`, and writes the required artifact
tree. The same feature publishes a versioned JSON Schema, adds committed
`local-fast` and `normal` scenarios, a two-run determinism check, and a Docker
Compose cluster acceptance test that mounts the generated assets and proves a
node accepts the genesis/config/key material during startup.

Planning uncovered one spec correction: the merged spec originally kept CHaP
wiring out of scope. That conflicts with the constitution's new compose-cluster
acceptance rule and with the need to produce node-accepted Cardano keys and
genesis files. This planning branch revises the spec so CHaP/cardano-* library
wiring is in scope for Feature 001.

## Technical Context

**Language/Version**: Haskell, GHC 9.12.3 (`ghc9123`)
**Primary Dependencies**: haskell.nix, CHaP, iohk-nix crypto overlays,
`cardano-api` / ledger and crypto packages aligned with the pinned
`cardano-node` acceptance image, `aeson`, `optparse-applicative`, HKDF/HMAC
crypto primitives, `directory`/`filepath`, `check-jsonschema` for schema
validation in CI, Docker Compose for acceptance
**Storage**: Filesystem only; no database. Bakes are written to a temporary
staging directory and atomically published to the requested output directory.
**Testing**: Hspec unit tests, golden/determinism tests, JSON Schema validation
for examples, `nix develop --quiet -c just CI`, and a Docker Compose cluster
acceptance test for generated assets.
**Target Platform**: Linux x86_64 under Nix and the `runs-on: nixos` runner.
**Project Type**: CLI/tooling with a library core and thin executable wrapper.
**Performance Goals**: Each example scenario bakes in under 30 seconds on the
CI runner; the compose acceptance test reaches the node-startup verdict within
3 minutes per scenario.
**Constraints**: One scenario JSON is the only output-affecting input; no
run-specific `systemStart` is baked; all keys derive from
`(scenario.seed, role, label)`; all cardano-* dependencies are SHA/index-state
pinned; no upstream forks or vendored Cardano source; generated JSON is
canonical enough for byte-identical two-run diffs.
**Scale/Scope**: Two committed scenarios, a small MVP schema, shared genesis
artifacts, pool-specific key directories, faucet/UTxO key directories, metadata,
and one compose acceptance harness with an immutable node image reference.
ChainDB synthesis and image publishing are future features.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Verdict | Evidence |
|-----------|---------|----------|
| I. Declarative scenarios as the single input | PASS | Plan publishes `schemas/scenario/v1.schema.json`; all output-affecting fields are in `scenario.json`; example scenarios are schema-validated in CI. |
| II. Determinism by construction | PASS | Key derivation uses HKDF/HMAC from `(scenario.seed, role, label)`; output writing uses stable file names and canonical JSON; CI bakes twice and diffs. |
| III. Reproducibility by pinning | PASS | CHaP, iohk-nix, cardano packages, node acceptance image, and any SRPs are pinned by lock/index-state/SHA; no moving tags are production inputs. |
| IV. Nix-first, haskell.nix for Haskell | PASS | Plan extends `nix/{project,shell,checks}.nix`; CI continues to use Nix checks/apps, not ad hoc `nix develop -c cabal test`. |
| V. Stock tools, custom orchestration | PASS | Cardano functionality is consumed from upstream packages/libraries and stock node images; no forks, patches, or vendored Cardano source. |
| VI. Smallest provable step | PASS | MVP produces genesis/keys/metadata only, proves them with a compose cluster, and leaves ChainDB synthesis plus distribution for later tickets. |

## Project Structure

### Documentation (this feature)

```text
specs/001-scenario-bake-cli/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── artifact-layout.md
│   ├── cli.md
│   ├── compose-acceptance.md
│   └── scenario-schema.md
├── checklists/
│   └── requirements.md
└── spec.md
```

### Source Code (repository root)

```text
app/
└── Main.hs

src/
├── Cardano/Testnet/Baker.hs
└── Cardano/Testnet/Baker/
    ├── Bake.hs
    ├── CLI.hs
    ├── Determinism.hs
    ├── Genesis.hs
    ├── Keys.hs
    ├── Metadata.hs
    ├── Scenario.hs
    ├── TextEnvelope.hs
    ├── Validation.hs
    └── Version.hs

schemas/
└── scenario/
    └── v1.schema.json

examples/
└── scenarios/
    ├── local-fast.json
    └── normal.json

compose/
└── acceptance/
    ├── docker-compose.yaml
    ├── patch-system-start.sh
    ├── run.sh
    └── topology/

test/
├── Cardano/Testnet/Baker/
│   ├── BakeSpec.hs
│   ├── CLISpec.hs
│   ├── ComposeAcceptanceSpec.hs
│   ├── DeterminismSpec.hs
│   ├── MetadataSpec.hs
│   ├── ScenarioSpec.hs
│   └── VersionSpec.hs
└── Spec.hs

nix/
├── checks.nix
├── project.nix
└── shell.nix
```

**Structure Decision**: keep one Haskell package with a typed library core and
a thin CLI. Schema, examples, and compose acceptance fixtures are repository
contracts rather than generated files. The compose harness patches `systemStart`
in a temporary copy of the baked artifacts, preserving the deterministic artifact
contract while proving node startup compatibility.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| CHaP/cardano-* packages added in Feature 001 | Node-accepted genesis and keys require upstream Cardano serialization, key, and genesis types. | Hand-written JSON/text envelopes or random `cardano-cli` generation would either fail node acceptance or violate deterministic key derivation. |

## Phase 1 Re-check (Post-design)

| Principle | Verdict | Notes |
|-----------|---------|-------|
| Declarative scenario input | PASS | `scenario-schema.md` and `data-model.md` define the public contract and field ownership. |
| Determinism | PASS | `Determinism.md` decisions in research map to tests and metadata digests. |
| Reproducibility | PASS | Nix/CHaP pinning and immutable compose image references are part of the source layout and test plan. |
| Nix-first | PASS | Quickstart uses `nix run`/`just`, and CI checks are Nix-backed. |
| Stock tools/custom orchestration | PASS | Compose uses stock `cardano-node`; Haskell code consumes upstream libraries. |
| Smallest provable step | PASS | No ChainDB synthesis, bundle production, or publishing is introduced. |

No unresolved clarifications remain. Plan ready for `/speckit.tasks`.
