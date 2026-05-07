# Feature Specification: Scenario JSON Schema and Bake CLI MVP

**Feature Branch**: `001-scenario-bake-cli`  
**Created**: 2026-05-07  
**Status**: Draft  
**Input**: User description: "Scenario JSON schema and bake-from-scenario CLI MVP"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Bake A Scenario Offline (Priority: P1)

A testnet operator provides one declarative `scenario.json` and an output
directory, then receives a complete deterministic artifact set that can be
mounted by downstream consumers without running in-cluster key or genesis
generation.

**Why this priority**: This is the MVP value of the baker: replace runtime
generation with a reproducible offline bake from a single scenario input.

**Independent Test**: Can be fully tested by baking a valid scenario into an
empty output directory and verifying that the required artifact directories
and metadata exist with scenario-derived contents.

**Acceptance Scenarios**:

1. **Given** a valid MVP scenario JSON and an empty output directory, **When**
   the operator runs the bake command, **Then** the output directory contains
   `genesis/`, `pools/`, `utxo-keys/`, and `metadata.json`.
2. **Given** the same valid scenario JSON and baker version, **When** the
   operator bakes into two separate empty output directories, **Then** every
   generated file is byte-identical across both directories.
3. **Given** a completed bake, **When** a downstream consumer reads the
   generated artifacts, **Then** all funding intended to survive future empty
   ChainDB synthesis is represented as Shelley initial funds rather than as
   transient runtime funding.

---

### User Story 2 - Declare MVP Scenarios In JSON (Priority: P2)

A scenario author describes the testnet shape in one JSON document, including
the seed, genesis parameters, era parameters, pools, faucet funding, and UTxO
key requirements needed for the MVP bake.

**Why this priority**: Determinism and reproducibility require that every
output-affecting parameter is visible in the scenario rather than hidden in
runtime defaults.

**Independent Test**: Can be tested by validating the committed example
scenarios against the MVP schema and confirming that they contain all fields
needed for the bake.

**Acceptance Scenarios**:

1. **Given** the `local-fast` example scenario, **When** it is validated,
   **Then** it declares `epochLength=120` and all required MVP scenario fields.
2. **Given** the `normal` example scenario, **When** it is validated, **Then**
   it declares preprod-shaped parameters including `epochLength=86400`,
   `k=2160`, and `activeSlotsCoeff=0.05`.
3. **Given** a scenario with a missing required output-affecting parameter,
   **When** the operator attempts to bake it, **Then** the system rejects the
   scenario with a clear validation message and does not produce a partial
   artifact set.

---

### User Story 3 - Verify Baked Assets With A Node (Priority: P3)

A maintainer can trust that committed example scenarios stay bakeable and
deterministic because automated checks bake each example twice, compare the
outputs, and start a node smoke test from the baked assets.

**Why this priority**: The MVP needs a repeatable proof that the first
supported scenarios are stable and consumable before expanding to ChainDB
synthesis, bundles, or distribution channels.

**Independent Test**: Can be tested by running the project CI workflow and
confirming that both committed example scenarios pass validation, baking, and
two-run output comparison, then by starting the node smoke test with the baked
assets mounted as its genesis and key inputs.

**Acceptance Scenarios**:

1. **Given** the committed `local-fast` and `normal` scenarios, **When** CI
   runs, **Then** each scenario is baked successfully.
2. **Given** either committed example scenario, **When** CI bakes it twice from
   the same scenario JSON and baker version, **Then** CI fails if any generated
   file differs between the two outputs.
3. **Given** a successful bake for each committed example scenario, **When** CI
   starts the Docker Compose node smoke test with the baked assets mounted,
   **Then** the node accepts the generated genesis and required key material
   during startup instead of failing with genesis, configuration, or key
   validation errors.

### Edge Cases

- A requested output directory already contains files from an earlier bake.
- A scenario JSON is malformed or does not match the MVP schema.
- A scenario omits a required field that affects genesis, pools, keys,
  funding, era parameters, or metadata.
- A scenario attempts to bake `systemStart` as a run-specific value.
- A scenario requests ChainDB synthesis, Amaru bundle production, OCI image
  output, native binary packaging, MkDocs generation, or CHaP wiring.
- Two distinct pool, faucet, or UTxO key labels collide after normalization.
- Baking is interrupted before all artifacts are written.
- The node smoke test cannot start because the generated genesis files, pool
  keys, or faucet/UTxO keys are internally inconsistent.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST define an MVP scenario JSON schema covering all
  inputs required to bake genesis files, pool keys, faucet or UTxO keys, era
  parameters, faucet funding, deterministic key derivation, and artifact
  metadata.
- **FR-002**: System MUST accept exactly one scenario JSON document as the
  declarative source for output-affecting bake parameters.
- **FR-003**: System MUST provide a bake command that reads `scenario.json` and
  writes artifacts under the requested output directory using the contract
  `<output-dir>/{genesis/,pools/,utxo-keys/,metadata.json}`.
- **FR-004**: System MUST derive all generated keys from `scenario.seed`, the
  key role, and the key label, so the same scenario and baker version produce
  the same key material across hosts.
- **FR-005**: System MUST make every generated artifact a deterministic
  function of the scenario JSON plus the baker version.
- **FR-006**: System MUST represent faucet funding that must survive later
  empty ChainDB synthesis as Shelley initial funds in the baked genesis
  artifacts.
- **FR-007**: System MUST NOT bake a run-specific `systemStart`; consumers are
  responsible for patching `systemStart` at boot.
- **FR-008**: System MUST write `metadata.json` describing the scenario
  identity, schema version, baker version, deterministic input digest, and
  generated artifact set.
- **FR-009**: System MUST include two committed example scenarios: `local-fast`
  with `epochLength=120`, and `normal` with preprod-shaped parameters including
  `epochLength=86400`, `k=2160`, and `activeSlotsCoeff=0.05`.
- **FR-010**: System MUST reject invalid, incomplete, unsupported, or
  out-of-scope scenarios with actionable messages and without leaving a
  completed-looking partial artifact set.
- **FR-011**: System MUST include automated validation that bakes both example
  scenarios twice and fails when outputs from the two runs are not
  byte-identical.
- **FR-012**: System MUST include a Docker Compose node smoke test that mounts
  baked assets for each committed example scenario and fails when the node
  rejects the generated genesis, configuration, or required key material during
  startup.
- **FR-013**: System MUST keep ChainDB synthesis, Amaru bundle production, OCI
  image build or publication, native binary distribution, MkDocs work, and
  CHaP wiring outside this feature's completed scope.

### Key Entities *(include if feature involves data)*

- **Scenario**: The single JSON input describing a reproducible testnet bake,
  including schema version, seed, network shape, genesis and era parameters,
  pool declarations, faucet funding, and requested UTxO keys.
- **Bake Output**: The versioned artifact directory produced from a scenario,
  consisting of genesis files, pool key material, UTxO or faucet keys, and
  metadata.
- **Pool Declaration**: A scenario entry for a block producer and its required
  deterministic key labels and genesis participation parameters.
- **Faucet Funding Declaration**: A scenario entry for funds that should be
  available to consumers and represented in Shelley initial funds for future
  ChainDB synthesis compatibility.
- **Bake Metadata**: A machine-readable record that identifies the scenario,
  schema version, baker version, deterministic input digest, and output files.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can bake a valid MVP scenario into the required artifact
  directory shape in a single command.
- **SC-002**: Re-baking either committed example scenario twice with the same
  baker version produces byte-identical output files in automated validation.
- **SC-003**: Both committed example scenarios validate successfully and bake
  successfully in CI, and the resulting assets pass the node startup smoke
  test.
- **SC-004**: Invalid MVP scenarios are rejected before a completed-looking
  artifact set is produced, with messages that identify the offending field or
  unsupported request.
- **SC-005**: The `metadata.json` for every successful bake records enough
  information for a maintainer to identify the scenario, schema version, baker
  version, deterministic input digest, and generated artifact set.
- **SC-006**: CI provides evidence that a node can start far enough with each
  committed example's baked assets to accept the generated genesis and key
  material without validation errors.

## Assumptions

- The MVP scenario schema is intentionally minimal but versioned, so later
  features can extend it without changing the single-scenario input contract.
- The bake command may require the output directory to be absent or empty; if
  it is not empty, the safe default is to reject the bake rather than merge
  outputs.
- `local-fast` and `normal` are the only required committed examples for this
  feature.
- ChainDB synthesis may consume these outputs later, but this feature only
  prepares genesis, keys, and metadata.
- Amaru bootstrap bundle work remains provisional and outside this feature.
