# Tasks: ChainDB Seed Synthesis Measurement MVP

**Input**: Design documents from `/specs/002-chaindb-synthesis/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Test tasks are included because the spec defines independent
acceptance criteria and this feature changes baked assets.

**Organization**: Tasks are grouped by user story to allow incremental
implementation and validation.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Expose the stock upstream tools and make the new docs visible.

- [ ] T001 Add `nix/iog-tools.nix` exposing the pinned upstream `db-synthesizer` executable
- [ ] T002 Update `nix/project.nix` source filtering to include `nix/iog-tools.nix` and synthesis docs where needed
- [ ] T003 Update `flake.nix` and `nix/shell.nix` so the development shell and `nix run` wrapper can run `db-synthesizer`
- [ ] T004 [P] Add the synthesis feature docs to `README.md`
- [ ] T005 [P] Link issue #8 from `specs/002-chaindb-synthesis/quickstart.md`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Extend the scenario contract and core types before any story
depends on synthesis behavior.

**CRITICAL**: No user story work can begin until this phase is complete.

- [ ] T006 Write failing schema tests for optional `synthesis` in `test/Cardano/Testnet/Baker/ScenarioSpec.hs`
- [ ] T007 Extend `schemas/scenario/v1.schema.json` with the optional `synthesis` object from `contracts/scenario-schema.md`
- [ ] T008 Extend `src/Cardano/Testnet/Baker/Scenario.hs` with synthesis request types and decoding
- [ ] T009 Extend `src/Cardano/Testnet/Baker/Validation.hs` with synthesis semantic validation
- [ ] T010 Update `examples/scenarios/local-fast.json` with a routine synthesis request
- [ ] T011 Update `examples/scenarios/normal.json` with a realistic measurement synthesis request
- [ ] T012 Update `test/data/minimal-scenario.json` or fixtures so genesis-only scenarios remain covered
- [ ] T013 Run `nix develop --quiet -c just validate-scenarios`

**Checkpoint**: The published scenario schema supports synthesis without
breaking genesis-only scenarios.

---

## Phase 3: User Story 1 - Bake A Synthesized Seed (Priority: P1) MVP

**Goal**: A synthesis-enabled scenario bakes genesis/key artifacts and a
deterministic ChainDB seed from the same scenario input.

**Independent Test**: Bake `local-fast` twice, verify the seed directory exists
in both outputs, and diff non-run-specific outputs.

### Tests for User Story 1

- [ ] T014 [P] [US1] Write failing tests for bulk credential generation in `test/Cardano/Testnet/Baker/SynthesisSpec.hs`
- [ ] T015 [P] [US1] Write failing bake orchestration test for synthesis-enabled output and preserved faucet initial funds in `test/Cardano/Testnet/Baker/BakeSpec.hs`
- [ ] T016 [P] [US1] Write failing CLI behavior test for synthesis validation failures in `test/Cardano/Testnet/Baker/CLISpec.hs`

### Implementation for User Story 1

- [ ] T017 [US1] Add `src/Cardano/Testnet/Baker/Synthesis.hs` with bulk credential rendering from generated pool artifacts
- [ ] T018 [US1] Add a synthesizer runner abstraction in `src/Cardano/Testnet/Baker/Synthesis.hs` so unit tests can use a fake runner
- [ ] T019 [US1] Update `src/Cardano/Testnet/Baker/Bake.hs` to stage `chain-db/` only when synthesis is requested
- [ ] T020 [US1] Update `src/Cardano/Testnet/Baker/Bake.hs` to fail atomically when synthesis fails
- [ ] T021 [US1] Update `src/Cardano/Testnet/Baker/CLI.hs` to surface synthesis validation and runner errors clearly
- [ ] T022 [US1] Update `nix/checks.nix` with a two-run synthesis determinism check for `local-fast` that normalizes host-only report fields
- [ ] T023 [US1] Update `justfile` with a `synthesize-local-fast` or equivalent recipe
- [ ] T024 [US1] Run `nix run . -- bake --scenario examples/scenarios/local-fast.json --out tmp/synthesis/local-fast`
- [ ] T025 [US1] Run the local two-run deterministic diff for `local-fast` excluding host-only report fields

Note: `local-fast` uses `securityParam=2` with `epochLength=120` because
the upstream synthesizer rejects `securityParam=10` at this epoch length.

**Checkpoint**: User Story 1 is independently functional and `local-fast`
produces a ChainDB seed.

---

## Phase 4: User Story 2 - Measure The Seed Before Choosing Distribution (Priority: P2)

**Goal**: The baker records raw and packaged seed size plus wall time for at
least one realistic-epoch synthesis run.

**Independent Test**: Bake the `normal` measurement scenario and inspect
`synthesis-report.json` for deterministic artifact facts and host-dependent
observations.

### Tests for User Story 2

- [ ] T026 [P] [US2] Write failing measurement report encoding tests in `test/Cardano/Testnet/Baker/SynthesisSpec.hs`
- [ ] T027 [P] [US2] Write failing packaged-size proxy tests in `test/Cardano/Testnet/Baker/SynthesisSpec.hs`
- [ ] T028 [P] [US2] Write failing metadata separation test in `test/Cardano/Testnet/Baker/MetadataSpec.hs`

### Implementation for User Story 2

- [ ] T029 [US2] Implement ChainDB byte counting and file counting in `src/Cardano/Testnet/Baker/Synthesis.hs`
- [ ] T030 [US2] Implement deterministic packaged-size proxy measurement in `src/Cardano/Testnet/Baker/Synthesis.hs`
- [ ] T031 [US2] Implement `synthesis-report.json` rendering in `src/Cardano/Testnet/Baker/Synthesis.hs`
- [ ] T032 [US2] Update `src/Cardano/Testnet/Baker/Metadata.hs` so deterministic metadata excludes host-dependent timing
- [ ] T033 [US2] Update `nix/checks.nix` with a report-shape check for synthesis outputs
- [ ] T034 [US2] Update `justfile` with a realistic measurement recipe for `normal`
- [ ] T035 [US2] Run the `normal` synthesis measurement path and record the observed report location in `specs/002-chaindb-synthesis/quickstart.md`

Note: `normal` is intentionally not part of the per-commit `just CI` synthesis
loop because its `slotCount=300000` path is the realistic measurement workflow
for this story, not the routine fast acceptance gate.

**Checkpoint**: User Story 2 produces size and timing evidence for storage
strategy decisions.

---

## Phase 5: User Story 3 - Verify The Seed With A Node (Priority: P3)

**Goal**: Compose acceptance starts a node from a private writable copy of the
generated seed and rejects invalid or mismatched state.

**Independent Test**: Run compose acceptance against a freshly baked
synthesis-enabled `local-fast` output and observe `verdict=accepted`.

### Tests for User Story 3

- [ ] T036 [P] [US3] Write failing compose harness tests for seeded database copy behavior in `test/Cardano/Testnet/Baker/ComposeAcceptanceSpec.hs`
- [ ] T037 [P] [US3] Write failing compose harness tests proving generated seed output is not mutated in `test/Cardano/Testnet/Baker/ComposeAcceptanceSpec.hs`
- [ ] T038 [P] [US3] Write failing negative acceptance test contract for missing or mismatched `chain-db/` in `test/Cardano/Testnet/Baker/ComposeAcceptanceSpec.hs`

### Implementation for User Story 3

- [ ] T039 [US3] Update `compose/acceptance/docker-compose.yaml` to mount a private writable node database path
- [ ] T040 [US3] Update `compose/acceptance/run.sh` to copy `chain-db/` into the private writable database path when present
- [ ] T041 [US3] Update `compose/acceptance/run.sh` to verify the immutable generated output is unchanged after acceptance
- [ ] T042 [US3] Update `compose/acceptance/run.sh` failure matching for ChainDB startup rejection evidence
- [ ] T043 [US3] Update `.github/workflows/ci.yml` to run synthesis seed acceptance for the routine scenario
- [ ] T044 [US3] Update `justfile` so `just CI` mirrors the synthesis seed acceptance path
- [ ] T045 [US3] Run `compose/acceptance/run.sh local-fast tmp/synthesis/local-fast`
- [ ] T046 [US3] Capture accepted `local-fast` and measured `normal` evidence in `specs/002-chaindb-synthesis/quickstart.md`

**Checkpoint**: User Story 3 proves generated synthesis assets are consumable
by the node startup path.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final quality gates, documentation, and PR readiness.

- [ ] T047 [P] Update `README.md` with synthesis output layout and measurement caveats
- [ ] T048 [P] Update `specs/002-chaindb-synthesis/contracts/artifact-layout.md` if implementation changes final paths
- [ ] T049 Run `nix develop --quiet -c just format`
- [ ] T050 Run `nix develop --quiet -c just CI`
- [ ] T051 Run `nix develop --quiet -c shellcheck compose/acceptance/run.sh compose/acceptance/patch-system-start.sh .github/scripts/check-action-runtimes.sh`
- [ ] T052 Run `git diff --check`
- [ ] T053 Update issue #8 with size, timing, acceptance, and CI evidence

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies.
- **Foundational (Phase 2)**: Depends on Setup and blocks all user stories.
- **US1 (Phase 3)**: Depends on Foundational.
- **US2 (Phase 4)**: Depends on US1 because measurement requires generated seed output.
- **US3 (Phase 5)**: Depends on US1 and can run partly in parallel with US2 after seed output exists.
- **Polish (Phase 6)**: Depends on selected user stories being complete.

### User Story Dependencies

- **User Story 1 (P1)**: MVP. Produces the seed artifact.
- **User Story 2 (P2)**: Requires US1 seed artifact and adds measurement reporting.
- **User Story 3 (P3)**: Requires US1 seed artifact and verifies node acceptance; final CI wiring should wait until US2/US3 behavior is stable.

### Parallel Opportunities

- T004 and T005 can run in parallel.
- T014, T015, and T016 can run in parallel.
- T026, T027, and T028 can run in parallel.
- T036, T037, and T038 can run in parallel.
- Documentation polish tasks T047 and T048 can run in parallel.

## Parallel Examples

```text
Task: "Write failing tests for bulk credential generation in test/Cardano/Testnet/Baker/SynthesisSpec.hs"
Task: "Write failing bake orchestration test for synthesis-enabled output in test/Cardano/Testnet/Baker/BakeSpec.hs"
Task: "Write failing CLI behavior test for synthesis validation failures in test/Cardano/Testnet/Baker/CLISpec.hs"
```

```text
Task: "Write failing compose harness tests for seeded database copy behavior in test/Cardano/Testnet/Baker/ComposeAcceptanceSpec.hs"
Task: "Write failing compose harness tests proving generated seed output is not mutated in test/Cardano/Testnet/Baker/ComposeAcceptanceSpec.hs"
Task: "Write failing negative acceptance test contract for missing chain-db/ in test/Cardano/Testnet/Baker/ComposeAcceptanceSpec.hs"
```

## Implementation Strategy

### MVP First

1. Complete Setup and Foundational tasks.
2. Complete User Story 1.
3. Stop and validate deterministic `local-fast` synthesis before adding
   measurement and compose seed acceptance.

### Incremental Delivery

1. Add scenario contract and parser support.
2. Add deterministic seed generation.
3. Add measurement report.
4. Add compose seed acceptance.
5. Run full local and GitHub CI before merge.

### Notes

- Every task uses exact file paths.
- Tasks marked `[P]` either touch different files or can be split before
  implementation.
- Write the failing tests first for each story, then implement the minimum
  change needed to pass.
- Do not add OCI image publishing or downstream bundle production in this
  feature.
