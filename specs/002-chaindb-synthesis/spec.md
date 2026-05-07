# Feature Specification: ChainDB Seed Synthesis Measurement MVP

**Feature Branch**: `002-chaindb-synthesis`
**Created**: 2026-05-07
**Status**: Draft
**Input**: User description: "Feature 002: ChainDB seed synthesis measurement MVP. Extend scenario JSON with an explicit optional synthesis request; bake genesis, keys, metadata, and a synthesized ChainDB seed from the same scenario; measure synthesis wall time, ChainDB size on disk, and packaged size proxy; verify with Docker Compose cardano-node startup from the generated seed copy. Issue #8."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Bake A Synthesized Seed (Priority: P1)

A testnet operator requests ChainDB seed synthesis in the scenario JSON and
receives a deterministic artifact set that includes genesis files, pool and
faucet keys, metadata, and a synthesized ChainDB seed derived from the same
scenario input.

**Why this priority**: This is the first step beyond genesis/key baking. It
proves the repo can replace runtime chain creation with an offline seed that
downstream nodes can copy into private writable storage.

**Independent Test**: Can be fully tested by baking a valid synthesis-enabled
scenario into an empty output directory and verifying that the generated output
contains the normal genesis/key artifacts plus a ChainDB seed artifact and
metadata tied to the same scenario digest.

**Acceptance Scenarios**:

1. **Given** a valid scenario with synthesis requested and an empty output
   directory, **When** the operator runs the bake, **Then** the output contains
   the genesis/key artifacts, a synthesized ChainDB seed, and metadata for the
   complete artifact set.
2. **Given** the same synthesis-enabled scenario and baker version, **When**
   the operator bakes into two separate empty output directories, **Then** the
   non-run-specific generated artifacts are byte-identical across both
   directories.
3. **Given** a synthesis-enabled scenario with faucet funds, **When** the seed
   is produced, **Then** the spendable funds expected by consumers are present
   through genesis initial funds rather than through transactions inserted
   during synthesis.

---

### User Story 2 - Measure The Seed Before Choosing Distribution (Priority: P2)

A maintainer bakes at least one realistic-epoch scenario and receives a
machine-readable report that records how large the generated ChainDB seed is
and how long synthesis took, so the project can make an evidence-based storage
and publishing decision later.

**Why this priority**: Artifact size and synthesis cost are the open risks.
The project should measure them before choosing GHCR, release assets, S3, or
another distribution strategy.

**Independent Test**: Can be tested by running synthesis for the committed
measurement scenario and checking that the report records wall time, on-disk
size, packaged-size proxy, file count, scenario identity, and baker version.

**Acceptance Scenarios**:

1. **Given** a synthesis-enabled realistic scenario, **When** synthesis
   completes, **Then** the measurement report records the ChainDB size on disk,
   packaged-size proxy, file count, and synthesis wall time.
2. **Given** a measurement report, **When** a maintainer reads it, **Then** the
   report clearly separates deterministic artifact facts from host-dependent
   timing observations.
3. **Given** multiple committed synthesis scenarios, **When** CI or a
   maintainer runs the measurement workflow, **Then** each scenario's
   measurements are attributable to a scenario identity and input digest.

---

### User Story 3 - Verify The Seed With A Node (Priority: P3)

A maintainer verifies that synthesized seeds are usable by starting a Docker
Compose node from a private writable copy of the generated seed and the
matching generated genesis/key assets.

**Why this priority**: A seed artifact is not consumable just because files
exist. It must be accepted by the intended node startup path and must support
the downstream copy-then-run model.

**Independent Test**: Can be tested by running the compose acceptance harness
against a freshly baked synthesis-enabled scenario and confirming that the
node starts from the seeded state instead of regenerating chain state.

**Acceptance Scenarios**:

1. **Given** a freshly baked synthesis-enabled output, **When** compose
   acceptance starts a node, **Then** the node uses a private writable copy of
   the ChainDB seed and accepts the matching genesis and configuration.
2. **Given** an invalid, incomplete, or mismatched ChainDB seed, **When**
   compose acceptance starts the node, **Then** acceptance fails with evidence
   that startup rejected the generated state.
3. **Given** the immutable generated seed output, **When** compose acceptance
   runs, **Then** the original generated seed remains unchanged and only the
   private copy is mutated by the node.

### Edge Cases

- A scenario omits synthesis, so the existing genesis/key-only bake remains
  valid and does not create a seed artifact.
- A synthesis request is malformed, unsupported, or missing a parameter that
  affects the seed output.
- Synthesis completes but produces no spendable transaction activity because
  synthesized blocks are empty.
- The requested output directory already contains a previous seed or partial
  synthesis output.
- Synthesis is interrupted before the seed and measurement report are
  complete.
- A measurement varies between hosts even though the generated seed is
  deterministic.
- The generated seed is copied into writable storage for one node and then
  reused incorrectly as shared mutable storage for multiple nodes.
- The acceptance harness patches run-specific startup time for node boot
  without rebaking or mutating deterministic seed artifacts.
- The seed is too large or slow for routine CI and must be measured without
  making every CI path impractical.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST extend the published scenario JSON contract with an
  explicit optional synthesis request covering every output-affecting ChainDB
  seed parameter.
- **FR-002**: System MUST preserve genesis/key-only baking for scenarios that
  do not request synthesis.
- **FR-003**: System MUST bake genesis files, pool keys, faucet keys, metadata,
  and the synthesized ChainDB seed from the same scenario JSON input when
  synthesis is requested.
- **FR-004**: System MUST make non-run-specific ChainDB seed artifacts a
  deterministic function of the scenario JSON plus the baker version and
  pinned dependencies.
- **FR-005**: System MUST keep run-specific values, including the startup time
  used by acceptance or consumers, outside the deterministic baked seed.
- **FR-006**: System MUST record synthesis measurements that include wall
  time, ChainDB size on disk, packaged-size proxy, file count, scenario
  identity, input digest, and baker version.
- **FR-007**: System MUST clearly separate deterministic artifact metadata
  from host-dependent measurement observations.
- **FR-008**: System MUST represent spendable faucet funding that survives
  empty-block synthesis as genesis initial funds.
- **FR-009**: System MUST reject invalid, unsupported, incomplete, or
  inconsistent synthesis requests with actionable messages and without leaving
  a completed-looking partial seed output.
- **FR-010**: System MUST verify synthesized seed usability with Docker
  Compose acceptance that starts a node from a private writable copy of the
  generated seed plus the matching generated genesis and key assets.
- **FR-011**: System MUST ensure compose acceptance fails when the generated
  genesis, configuration, keys, or ChainDB seed are invalid or mismatched.
- **FR-012**: System MUST leave the immutable generated seed output unchanged
  during acceptance; node runtime mutations occur only in the private writable
  copy.
- **FR-013**: System MUST produce enough measurement evidence for maintainers
  to choose a later storage and publishing strategy.
- **FR-014**: System MUST keep OCI image publishing, release asset upload, S3
  upload, native binary distribution, downstream bundle production, and
  multi-node packaged distribution outside this feature's completed scope.

### Key Entities *(include if feature involves data)*

- **Synthesis Request**: Optional scenario section that declares whether a
  ChainDB seed should be produced and which output-affecting parameters shape
  that seed.
- **Synthesized ChainDB Seed**: The generated immutable seed artifact intended
  to be copied into private writable node storage before runtime.
- **Synthesis Measurement Report**: Machine-readable evidence describing seed
  size, packaged-size proxy, file count, wall time, scenario identity, input
  digest, and baker version.
- **Seed Acceptance Run**: A compose-based validation run that copies the seed,
  starts a node from the copy, and records whether the generated state was
  accepted.
- **Scenario**: The single bootstrapping JSON input that determines genesis,
  keys, faucet funds, optional synthesis, and metadata outputs.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can request synthesis in a valid scenario and receive a
  completed artifact directory containing genesis/key artifacts, metadata, and
  a ChainDB seed artifact.
- **SC-002**: Re-baking the same synthesis-enabled scenario twice with the
  same baker version produces byte-identical non-run-specific artifacts.
- **SC-003**: At least one realistic-epoch synthesis run records ChainDB
  on-disk size, packaged-size proxy, file count, and wall time in a
  machine-readable report.
- **SC-004**: Compose acceptance starts a node from a private writable copy of
  the synthesized seed and reports acceptance for every committed
  synthesis-enabled scenario that is expected to pass.
- **SC-005**: Invalid or mismatched synthesis outputs fail compose acceptance
  before they can be treated as consumable artifacts.
- **SC-006**: The measurement output gives maintainers enough evidence to make
  the next storage decision without relying on guesses about seed size or
  synthesis duration.

## Assumptions

- The first synthesis feature is a measurement and acceptance MVP, not a
  publishing or distribution feature.
- Existing `local-fast` and `normal` scenarios remain required examples; the
  plan may decide whether both request synthesis immediately or whether one
  additional measurement variant is needed.
- Synthesis may be expensive enough that routine CI uses a bounded scenario
  while a realistic-epoch measurement can run in a separate explicit path.
- Downstream consumers will copy the immutable seed into private writable
  node storage before starting each node.
- The spendable balances expected after synthesis come from genesis initial
  funds, not from transactions generated during synthesis.
