# Tasks: Scenario JSON Schema and Bake CLI MVP

**Input**: Design documents from `specs/001-scenario-bake-cli/`
**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`
**Tests**: Required by the feature specification: schema validation, semantic validation, deterministic two-run baking, and Docker Compose node acceptance.

**Format**: `- [ ] T### [P?] [US?] Description with file path`

## Phase 1: Setup

**Purpose**: Add the pinned Cardano/Nix/tooling surface needed by every user story.

- [x] T001 Add `iohkNix` and `CHaP` flake inputs plus crypto and haskell.nix overlays in `flake.nix`
- [x] T002 Update `nix/project.nix` to accept `CHaP`, map `https://chap.intersectmbo.org/`, and add crypto pkg-config overrides
- [x] T003 Add CHaP repository, index-state, cardano package constraints, and any SHA-pinned source packages in `cabal.project`
- [x] T004 Add Haskell dependencies and exposed library modules for Feature 001 in `cardano-testnet-baker.cabal`
- [x] T005 Add `check-jsonschema`, Docker Compose tooling, `jq`, and shellcheck support to `nix/shell.nix`
- [x] T006 Create implementation directories `src/Cardano/Testnet/Baker/`, `schemas/scenario/`, `examples/scenarios/`, and `compose/acceptance/`

## Phase 2: Foundational

**Purpose**: Shared parser, validation, deterministic derivation, metadata, and CLI scaffolding that blocks all user stories.

**Critical**: Complete this phase before implementing any user story.

- [x] T007 [P] Add failing scenario decoding and semantic validation tests in `test/Cardano/Testnet/Baker/ScenarioSpec.hs`
- [x] T008 [P] Add failing deterministic HKDF/domain-separation tests in `test/Cardano/Testnet/Baker/DeterminismSpec.hs`
- [x] T009 [P] Add failing canonical metadata digest tests in `test/Cardano/Testnet/Baker/MetadataSpec.hs`
- [x] T010 Define scenario, pool, faucet, genesis, and output request types plus JSON decoding in `src/Cardano/Testnet/Baker/Scenario.hs`
- [x] T011 Implement semantic validation errors for required invariants in `src/Cardano/Testnet/Baker/Validation.hs`
- [x] T012 Implement HKDF/HMAC deterministic derivation helpers in `src/Cardano/Testnet/Baker/Determinism.hs`
- [x] T013 Implement canonical JSON/digest helpers and metadata types in `src/Cardano/Testnet/Baker/Metadata.hs`
- [x] T014 Add CLI parser skeleton for `scenario validate` and `bake` in `src/Cardano/Testnet/Baker/CLI.hs`
- [x] T015 Wire the new CLI parser through `app/Main.hs`
- [x] T016 Export new library modules from `src/Cardano/Testnet/Baker.hs` and register new spec modules in `cardano-testnet-baker.cabal`

**Checkpoint**: Scenario decoding, semantic validation, deterministic derivation, metadata digests, and CLI command parsing all have failing tests ready for implementation.

## Phase 3: User Story 1 - Bake A Scenario Offline (Priority: P1)

**Goal**: A user can run one bake command against a valid scenario and receive the deterministic `genesis/`, `pools/`, `utxo-keys/`, and `metadata.json` output tree.

**Independent Test**: Bake a test scenario twice into two empty directories, assert required paths exist, assert funding is represented in Shelley initial funds, and assert recursive byte-for-byte equality between runs.

### Tests for User Story 1

- [x] T017 [P] [US1] Add failing output layout tests for a minimal valid scenario in `test/Cardano/Testnet/Baker/BakeSpec.hs`
- [ ] T018 [US1] Add failing non-empty-output and interrupted-staging tests in `test/Cardano/Testnet/Baker/BakeSpec.hs`
- [ ] T019 [P] [US1] Add failing two-run recursive determinism tests in `test/Cardano/Testnet/Baker/DeterminismSpec.hs`
- [ ] T020 [US1] Add failing Shelley `initialFunds` faucet funding tests in `test/Cardano/Testnet/Baker/BakeSpec.hs`
- [x] T021 [P] [US1] Add the minimal bake test scenario fixture in `test/data/minimal-scenario.json`

### Implementation for User Story 1

- [x] T022 [US1] Implement Cardano text-envelope rendering helpers in `src/Cardano/Testnet/Baker/TextEnvelope.hs`
- [ ] T023 [US1] Implement deterministic KES, VRF, cold, stake, op-cert, and faucet key generation in `src/Cardano/Testnet/Baker/Keys.hs`
- [ ] T024 [US1] Implement Byron, Shelley, Alonzo, Conway, and node config generation in `src/Cardano/Testnet/Baker/Genesis.hs`
- [x] T025 [US1] Implement staged artifact writing and atomic publish in `src/Cardano/Testnet/Baker/Bake.hs`
- [ ] T026 [US1] Implement `metadata.json` writing with artifact digests in `src/Cardano/Testnet/Baker/Metadata.hs`
- [ ] T027 [US1] Wire the `bake --scenario --out` command in `src/Cardano/Testnet/Baker/CLI.hs`
- [ ] T028 [US1] Add a `just bake-local-fast` developer recipe in `justfile`

**Checkpoint**: User Story 1 works independently with the minimal test scenario and proves deterministic output shape without committed public examples.

## Phase 4: User Story 2 - Declare MVP Scenarios In JSON (Priority: P2)

**Goal**: Publish the v1 scenario JSON Schema and the two committed example scenarios, then validate both structurally and semantically.

**Independent Test**: Run `check-jsonschema` against both examples, then run `cardano-testnet-baker scenario validate` against each example and verify the expected scenario-specific fields.

### Tests for User Story 2

- [ ] T029 [P] [US2] Add failing schema validation check wiring for committed examples in `nix/checks.nix`
- [ ] T030 [P] [US2] Add failing `local-fast` and `normal` semantic validation tests in `test/Cardano/Testnet/Baker/ScenarioSpec.hs`
- [ ] T031 [P] [US2] Add failing CLI validation tests for valid and invalid scenario files in `test/Cardano/Testnet/Baker/CLISpec.hs`

### Implementation for User Story 2

- [ ] T032 [US2] Publish the v1 scenario JSON Schema in `schemas/scenario/v1.schema.json`
- [ ] T033 [US2] Add the `local-fast` example scenario in `examples/scenarios/local-fast.json`
- [ ] T034 [US2] Add the `normal` example scenario in `examples/scenarios/normal.json`
- [ ] T035 [US2] Implement `scenario validate` semantic validation output in `src/Cardano/Testnet/Baker/CLI.hs`
- [ ] T036 [US2] Add `check-jsonschema` example validation to `nix/checks.nix`
- [ ] T037 [US2] Add `just validate-scenarios` and include it in `just CI` in `justfile`
- [ ] T038 [US2] Update example scenario documentation in `README.md`

**Checkpoint**: User Story 2 works independently: the public schema and both examples validate without needing compose acceptance.

## Phase 5: User Story 3 - Verify Baked Assets With A Node (Priority: P3)

**Goal**: CI proves the baked assets are usable by starting a Docker Compose node cluster from the generated genesis/config/key material.

**Independent Test**: Bake each committed example, run the compose acceptance harness against the generated assets, and fail on startup, genesis, config, or key validation errors.

### Tests for User Story 3

- [ ] T039 [P] [US3] Add failing compose harness script validation tests in `test/Cardano/Testnet/Baker/ComposeAcceptanceSpec.hs`
- [ ] T040 [US3] Add failing acceptance command contract checks in `test/Cardano/Testnet/Baker/ComposeAcceptanceSpec.hs`
- [ ] T041 [US3] Add failing runtime start-time patch tests in `test/Cardano/Testnet/Baker/ComposeAcceptanceSpec.hs`

### Implementation for User Story 3

- [ ] T042 [US3] Create the minimal acceptance cluster definition in `compose/acceptance/docker-compose.yaml`
- [ ] T043 [US3] Pin the acceptance `cardano-node` image by digest or SHA-pinned Nix input in `compose/acceptance/docker-compose.yaml`
- [ ] T044 [US3] Implement runtime-only `systemStart` and Byron `startTime` patching in `compose/acceptance/patch-system-start.sh`
- [ ] T045 [US3] Implement compose setup, wait, log capture, verdict, and cleanup in `compose/acceptance/run.sh`
- [ ] T046 [US3] Add static topology/config fixtures needed by the acceptance cluster in `compose/acceptance/topology/`
- [ ] T047 [US3] Add `just bake-examples`, `just acceptance-local-fast`, and `just acceptance-normal` recipes in `justfile`
- [ ] T048 [US3] Add Nix checks for two-run example bakes and recursive diffs in `nix/checks.nix`
- [ ] T049 [US3] Add Nix/CI hooks for compose acceptance of `local-fast` and `normal` in `nix/checks.nix`
- [ ] T050 [US3] Update GitHub Actions to run schema, bake determinism, and compose acceptance jobs after Build Gate in `.github/workflows/ci.yml`

**Checkpoint**: User Story 3 works independently from the committed examples and proves node startup acceptance for generated assets.

## Final Phase: Polish & Cross-Cutting Concerns

- [ ] T051 Update `README.md` with schema validation, bake, determinism, and compose acceptance commands
- [ ] T052 Add `cabal check` and Haddock verification coverage to `just CI` or equivalent Nix checks in `justfile`
- [ ] T053 Run `nix develop --quiet -c just format` from repository root `.`
- [ ] T054 Run `nix develop --quiet -c just CI` from repository root `.`
- [ ] T055 Record final verification evidence and open implementation PR notes in `specs/001-scenario-bake-cli/quickstart.md`

## Dependencies & Execution Order

### Phase Dependencies

| Phase | Depends On | Blocks |
|-------|------------|--------|
| Phase 1 Setup | none | Phase 2 |
| Phase 2 Foundational | Phase 1 | all user stories |
| Phase 3 US1 | Phase 2 | US3 compose acceptance needs baked assets |
| Phase 4 US2 | Phase 2 | US3 CI examples need committed scenarios |
| Phase 5 US3 | Phase 3 and Phase 4 | final feature acceptance |
| Final Phase | Phase 5 | PR readiness |

### User Story Dependencies

| Story | Dependency | Rationale |
|-------|------------|-----------|
| US1 | Phase 2 only | Can bake a minimal test scenario without committed public examples. |
| US2 | Phase 2 only | Can publish and validate schema/examples without compose. |
| US3 | US1 and US2 | Needs both baked assets and committed examples. |

## Parallel Opportunities

### Setup

T001-T005 touch different Nix/Cabal files but should be reviewed together because dependency solver failures can cross file boundaries.

### User Story 1

```text
T017 Bake output tests
T019 Determinism tests
T020 Faucet funding tests
T022 Text-envelope helpers
T023 Key generation helpers
```

### User Story 2

```text
T032 JSON Schema
T033 local-fast example
T034 normal example
T030 semantic tests
```

### User Story 3

```text
T042 docker-compose.yaml
T043 patch-system-start.sh
T044 run.sh
T045 topology fixtures
```

## Implementation Strategy

### MVP First

1. Complete Phase 1 and Phase 2.
2. Complete US1 so the baker can produce deterministic local artifacts.
3. Stop and validate US1 with `test/data/minimal-scenario.json`.

### Incremental Delivery

1. Add US2 schema/examples and validate committed scenarios.
2. Add US3 compose acceptance once examples and bakes are stable.
3. Run the full local gate before pushing implementation.

### Final Verification Gate

```sh
nix develop --quiet -c just CI
```

The final gate must include unit tests, formatting, HLint, schema validation,
two-run bake determinism, and Docker Compose acceptance for both committed
examples.
