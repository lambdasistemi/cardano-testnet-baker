# Implementation Plan: ChainDB Seed Synthesis Measurement MVP

**Branch**: `002-chaindb-synthesis` | **Date**: 2026-05-07 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/002-chaindb-synthesis/spec.md`

## Summary

Extend the existing scenario bake path with an optional `synthesis` request
that creates a deterministic ChainDB seed alongside genesis, pool keys, faucet
keys, and metadata. Reuse the stock upstream `db-synthesizer` executable from
the already-pinned `ouroboros-consensus` source package, generate its bulk
credentials from baked pool artifacts, record deterministic artifact facts
separately from host-dependent timing, and verify the seed by starting a
`cardano-node` compose service from a private writable copy.

## Technical Context

**Language/Version**: Haskell, GHC 9.12.3 via haskell.nix `ghc9123`  
**Primary Dependencies**: cardano-node 10.7.1-aligned Cardano libraries, stock `db-synthesizer`, `aeson`, `optparse-applicative`, JSON Schema tooling, Docker Compose acceptance image  
**Storage**: Filesystem artifact directory containing genesis, keys, metadata, optional `chain-db/`, and synthesis measurement report  
**Testing**: Hspec unit tests, Nix checks, schema validation, two-run
determinism checks, shellcheck, Docker Compose seed acceptance  
**Target Platform**: x86_64-linux Nix builds; Ubuntu runner for Docker Compose
acceptance  
**Project Type**: CLI plus Nix-packaged checks and shell acceptance harness  
**Performance Goals**: Routine synthesis acceptance for `local-fast` completes
within the existing 60 minute compose CI budget; realistic-epoch measurement
records wall time and size without blocking storage decisions on guesses  
**Constraints**: One scenario JSON is the only output-affecting input;
`systemStart` is patched outside deterministic artifacts; synthesized blocks
are empty so funding must come from Shelley initial funds; generated seeds are
immutable source artifacts copied to private writable node storage before use  
**Scale/Scope**: Add optional synthesis for committed examples, measure at
least one realistic-epoch scenario, keep OCI publishing and downstream bundle
production out of scope

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Plan Evidence |
|-----------|--------|---------------|
| I. Declarative scenarios as single input | PASS | `synthesis` is an explicit schema field; slot count/profile choices live in scenario JSON, not env vars. |
| II. Determinism by construction | PASS | ChainDB seed artifacts are derived from scenario, baker SHA, and pinned synthesizer; measurement timing is separated from deterministic metadata. |
| III. Reproducibility by pinning | PASS | Reuse existing cardano-node 10.7.1 package pins and expose the pinned upstream `db-synthesizer`; no moving tags. |
| IV. Nix-first, haskell.nix | PASS | Tool exposure and checks are Nix derivations; CI continues through Build Gate first. |
| V. Stock tools, custom orchestration | PASS | Invoke upstream `db-synthesizer` unmodified; baker only prepares inputs, runs it, and stages outputs. |
| VI. Smallest provable step | PASS | Feature is measurement plus compose acceptance only; publishing strategy remains deferred. |

## Project Structure

### Documentation (this feature)

```text
specs/002-chaindb-synthesis/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── artifact-layout.md
│   ├── cli.md
│   ├── compose-seed-acceptance.md
│   ├── measurement-report.md
│   └── scenario-schema.md
└── tasks.md
```

### Source Code (repository root)

```text
src/Cardano/Testnet/Baker/
├── Bake.hs
├── CLI.hs
├── Genesis.hs
├── Keys.hs
├── Metadata.hs
├── Scenario.hs
├── Synthesis.hs
└── Validation.hs

test/Cardano/Testnet/Baker/
├── BakeSpec.hs
├── CLISpec.hs
├── ComposeAcceptanceSpec.hs
├── ScenarioSpec.hs
└── SynthesisSpec.hs

compose/acceptance/
├── docker-compose.yaml
├── patch-system-start.sh
└── run.sh

nix/
├── checks.nix
├── iog-tools.nix
├── project.nix
└── shell.nix
```

**Structure Decision**: Keep synthesis orchestration in the existing Haskell
CLI boundary with one new `Synthesis` module. Add a small Nix `iog-tools.nix`
helper to expose stock upstream executables, matching the existing sibling
project pattern. Keep Docker acceptance under `compose/acceptance`.

## Phase 0 Research

See [research.md](./research.md).

## Phase 1 Design

See [data-model.md](./data-model.md) and contracts:

- [scenario-schema.md](./contracts/scenario-schema.md)
- [cli.md](./contracts/cli.md)
- [artifact-layout.md](./contracts/artifact-layout.md)
- [measurement-report.md](./contracts/measurement-report.md)
- [compose-seed-acceptance.md](./contracts/compose-seed-acceptance.md)

## Post-Design Constitution Check

| Principle | Status | Design Evidence |
|-----------|--------|-----------------|
| I. Declarative scenarios as single input | PASS | `synthesis` schema contract contains `enabled`, `slotCount`, and measurement intent. |
| II. Determinism by construction | PASS | Deterministic output metadata excludes wall-clock fields; measurement report carries host-observation fields. |
| III. Reproducibility by pinning | PASS | `db-synthesizer` comes from the pinned consensus SRP already aligned to cardano-node 10.7.1. |
| IV. Nix-first, haskell.nix | PASS | New tools and checks are exposed through Nix; local `just CI` mirrors CI. |
| V. Stock tools, custom orchestration | PASS | No fork or vendored consensus code; orchestration shells out to the stock executable. |
| VI. Smallest provable step | PASS | Acceptance proves node startup from a seed copy and records size/time evidence; image publishing remains out of scope. |

## Complexity Tracking

No constitution violations.
