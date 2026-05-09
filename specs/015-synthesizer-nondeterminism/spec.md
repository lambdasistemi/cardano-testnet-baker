# Feature Specification: Determinize `normal` Scenario db-synthesizer Output

**Feature Branch**: `015-synthesizer-nondeterminism`
**Created**: 2026-05-09
**Status**: Draft
**Input**: GitHub issue lambdasistemi/cardano-testnet-baker#15
("fix(synthesis): normal scenario db-synthesizer output
non-deterministic across runs")

## Background

PR #12 (Feature 003: seed image distribution) introduced a
`seed-image-determinism` Nix check that builds each scenario's seed
image twice as independent derivations and asserts the layer
payload is byte-identical across the pair. The check passes for
`local-fast` (`slotCount = 720`) but fails for `normal`
(`slotCount = 300000`) with a real producer-side determinism drift.
The observed deltas:

1. `seed/chain-db/volatile/blocks-6.dat` exists in one build and is
   missing from the other — the synthesizer emits a different
   number of volatile blocks across runs of the same scenario.
2. `seed/synthesis-report.json` diverges because `chainDb.bytes`,
   `chainDb.fileCount`, and `chainDb.packagedBytes` reflect (1).
   The existing report-shape projection only strips
   `observation.*` host-clock fields, since size accounting is
   part of artifact identity.

Both differences cascade from the same upstream non-determinism
inside `db-synthesizer` at scale. As a workaround, PR #12 narrowed
the determinism gate to `local-fast` only and documented the
narrowing in `specs/003-seed-distribution/contracts/publish-pipeline.md`
and `specs/003-seed-distribution/spec.md` (FR-006 / SC-002). This
feature closes that workaround.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Determinism Gate Includes `normal` (Priority: P1)

A maintainer rebuilds the seed image for the `normal` scenario
twice as independent derivations and the determinism gate observes
byte-identical seed payloads.

**Why this priority**: This is the user-visible contract the
project promised: `(scenario, baker SHA) → bit-identical seed`
(constitution principle II). Without it, downstream consumers of
the published seed have no guarantee that two builds at the same
input produce the same output, and the project cannot trust its
own publishing pipeline for any scenario richer than `local-fast`.

**Independent Test**: Re-enable `normal` in the
`seed-image-determinism` gate scenario list, build the gate twice
(or run the gate's already-internal pair-build), and observe that
both pair builds succeed without diff output.

**Acceptance Scenarios**:

1. **Given** the `normal` scenario in the determinism gate's
   in-scope scenario list, **When** the gate runs, **Then** the
   pair build of `normal` reports zero file-set differences and
   zero per-file byte differences.
2. **Given** two independent invocations of synthesis on the
   `normal` scenario at the same baker SHA, **When** the
   resulting `chain-db/` directories are compared, **Then** the
   set of files, their relative paths, and their byte contents are
   identical.
3. **Given** two independent synthesis runs on the `normal`
   scenario, **When** their `synthesis-report.json` files have
   `observation.*` stripped, **Then** the remaining artifact-fact
   fields (including `chainDb.bytes`, `chainDb.fileCount`, and
   `chainDb.packagedBytes`) are identical.

---

### User Story 2 - Root-Cause Evidence Is Captured (Priority: P2)

A maintainer reading the PR can identify which input or upstream
behaviour caused the drift and how the fix removes that cause,
without re-deriving the investigation from scratch.

**Why this priority**: A "the gate is green again" fix without
documented mechanism is a regression risk. The constitution
forbids hidden inputs and varying defaults; recording the root
cause in the feature artifacts protects principles I and II
against quietly returning later.

**Independent Test**: Open the feature's research notes (or the
research/plan artifact produced during planning) and confirm they
identify (a) the divergence mechanism observed in `db-synthesizer`
on `normal`, (b) the smallest reproducer parameter that triggers
or stops triggering it, and (c) which fix path was taken
(scenario-side adjustment, in-repo wrapping, or pinned upstream
fix).

**Acceptance Scenarios**:

1. **Given** the merged PR for issue #15, **When** a maintainer
   reads the spec/research artifact, **Then** the divergence
   mechanism is named (for example: parallel block production
   schedule, wallclock-sensitive stop boundary, time-based seed
   fall-through, or `/dev/urandom` read inside synthesizer glue).
2. **Given** the chosen fix path, **When** the maintainer reads
   the plan artifact, **Then** the fix is justified against
   constitution principle V (stock tools, custom orchestration);
   either the synthesizer is consumed unmodified with adjusted
   inputs, or it is consumed as a library through a minimal
   in-repo executable, or a pinned upstream fix is referenced.

---

### User Story 3 - Workaround Is Removed (Priority: P3)

A maintainer removes the PR #12 narrowing so the determinism gate
covers all `examples/scenarios/*.json` files, and the documents
that recorded the narrowing reflect the new behaviour.

**Why this priority**: The narrowing was explicitly documented as
temporary. Leaving it in place after the synthesizer is
deterministic would mean the gate's published scope keeps lying
about what the project guarantees.

**Independent Test**: Inspect `nix/checks.nix` and confirm the
`seed-image-determinism` scenario list now equals
`examples/scenarios/*.json`. Inspect
`specs/003-seed-distribution/contracts/publish-pipeline.md` and
`specs/003-seed-distribution/spec.md` (FR-006 / SC-002) and
confirm the narrowing notes are removed or rewritten to reflect
full-scope coverage.

**Acceptance Scenarios**:

1. **Given** the merged PR for issue #15, **When** a maintainer
   inspects `nix/checks.nix`, **Then** the determinism gate
   in-scope scenario list is the full
   `examples/scenarios/*.json` set, not a `local-fast`-only
   subset.
2. **Given** the merged PR for issue #15, **When** a maintainer
   reads `specs/003-seed-distribution/spec.md` and
   `contracts/publish-pipeline.md`, **Then** any "narrowed to
   `local-fast`" carve-out is either removed or rewritten to
   describe the post-fix full-scope behaviour.

### Edge Cases

- The fix is upstream-only (in `intersectmbo/ouroboros-consensus`
  or the synthesizer library glue) and this repo only updates
  pins and the gate's scenario list.
- The fix requires a scenario-side change (for example bounding
  parallelism or fixing a clock-sensitive stop boundary) that
  must be reflected in the published JSON Schema for the scenario
  contract.
- The drift is intermittent — two runs sometimes match by chance.
  The gate must therefore stay reproducible across many builds,
  not just the next two.
- A new scenario added later is also non-deterministic; the gate
  must detect that case rather than silently re-narrowing.
- The fix changes the deterministic seed bytes produced by
  existing scenarios, so any seed already published from the
  previous (drifty) baker version becomes non-reproducible from
  the new baker SHA. Downstream guidance must explain that this
  is expected (constitution III: pin the baker SHA, not a moving
  tag).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST produce byte-identical
  non-run-specific seed artifacts for the `normal` scenario
  across two independent builds at the same baker SHA, including
  every file under `seed/chain-db/`.
- **FR-002**: System MUST produce byte-identical
  artifact-fact fields in `seed/synthesis-report.json` for the
  `normal` scenario across two independent builds at the same
  baker SHA, after stripping host-dependent
  `observation.*` fields.
- **FR-003**: System MUST extend the `seed-image-determinism`
  gate's in-scope scenario list back to the full
  `examples/scenarios/*.json` set, removing the PR #12
  `local-fast`-only narrowing.
- **FR-004**: System MUST update
  `specs/003-seed-distribution/contracts/publish-pipeline.md` and
  `specs/003-seed-distribution/spec.md` (FR-006 / SC-002) to no
  longer claim that `normal` is exempt from the determinism gate.
- **FR-005**: System MUST identify and record the root cause of
  the drift in the feature's plan or research artifact, including
  the divergence mechanism, the smallest reproducer parameter
  envelope, and the chosen fix path.
- **FR-006**: System MUST satisfy the chosen fix path through one
  of: (a) consuming the upstream `db-synthesizer` unmodified with
  adjusted scenario inputs, (b) consuming the upstream synthesizer
  library through a minimal in-repo executable, or (c) pinning a
  fix-bearing upstream commit, in line with constitution principle
  V (stock tools, no fork or vendored copy of consensus / network
  / ledger / node).
- **FR-007**: System MUST keep the `local-fast` scenario in the
  determinism gate and continue to pass it.
- **FR-008**: System MUST update the published scenario JSON
  Schema and the schema-version migration note when the fix
  introduces or alters any scenario-side parameter that affects
  seed output.
- **FR-009**: System MUST run the existing Docker Compose
  acceptance harness against the post-fix `normal` seed and
  observe a successful node startup from a private writable copy,
  preserving the constitution's principle VI cluster-acceptance
  obligation.

### Key Entities *(include if feature involves data)*

- **Scenario**: Existing bootstrapping JSON input. The `normal`
  scenario is the in-scope identity for this feature.
- **Synthesized ChainDB Seed**: Existing immutable seed artifact;
  this feature requires its non-run-specific bytes to be a pure
  function of `(scenario, baker SHA)`.
- **Synthesis Report**: Existing `synthesis-report.json` whose
  artifact-fact fields must become deterministic for the `normal`
  scenario.
- **Determinism Gate**: The existing `seed-image-determinism`
  Nix check; in-scope scenario list expands from `local-fast` only
  to all of `examples/scenarios/*.json`.
- **Drift Cause Note**: Persistent record of the identified
  upstream or scenario-side cause, owned by the feature's plan or
  research artifact.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The `seed-image-determinism` gate in CI passes with
  the `normal` scenario in scope across at least three consecutive
  CI runs without intermittent failures.
- **SC-002**: Two independent local builds of the `normal`
  scenario seed at the same baker SHA produce zero file-set
  differences and zero per-file byte differences.
- **SC-003**: The PR description and at least one durable
  artifact in the feature's spec/plan/research directory document
  the root cause of the original drift and the chosen fix path.
- **SC-004**: After the PR merges, the
  `seed-image-determinism` gate's in-scope scenario list equals
  the full `examples/scenarios/*.json` file set.
- **SC-005**: The post-fix `normal` seed continues to satisfy
  Docker Compose acceptance: a node starts from a private
  writable copy of the seed without genesis, configuration, or
  startup-validation errors.
- **SC-006**: The PR #12 narrowing notes in
  `specs/003-seed-distribution/spec.md` and
  `contracts/publish-pipeline.md` are removed or rewritten to
  reflect full-scope determinism.

## Assumptions

- The drift is producer-side inside `db-synthesizer` at the slot
  count used by `normal`; consumer-side (compose acceptance) is
  not the cause and continues to behave as today.
- A change in deterministic seed bytes between the pre-fix and
  post-fix baker SHA is expected and acceptable, because
  consumers pin the baker commit SHA per constitution principle
  III; no published seed from the old SHA needs to remain
  reproducible from the new SHA.
- The fix can be delivered without forking any upstream Cardano
  library; if a code change is required upstream, this repo will
  pin a fix-bearing commit rather than vendor a patch
  (constitution principle V).
- The determinism gate built in PR #12 is structurally correct;
  this feature only changes its in-scope scenario list, not its
  pair-build mechanism.
- No other currently-passing scenario in
  `examples/scenarios/*.json` regresses to non-determinism as a
  side effect of the fix; the regression surface stays at the
  scenario-list level.
