# Tasks: Determinize `normal` Scenario db-synthesizer Output

**Input**: Design documents from `/specs/015-synthesizer-nondeterminism/`
**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`

**Tests**: Required — the spec defines independent acceptance
criteria around byte-identical seed payloads (SC-002), three
consecutive green CI runs (SC-001), and node startup acceptance
(SC-005). Test-first RED/GREEN evidence is the bisect oracle for
each slice below.

**Organization**: Tasks are grouped by **TDD vertical slice** as
defined in `plan.md` "TDD Vertical Slices". Each slice is one
bisect-safe vertical commit. The mapping from slice to spec user
stories is:

- Slice 1 (reproducer) → US2 (root-cause evidence) and as RED
  oracle for slices 2, 3, 5.
- Slice 2 (fix path (a) or (c)) → US1 (gate includes `normal`).
- Slice 3 (gate widening) → US1 + US3.
- Slice 4 (doc rewrite) → US3 (workaround removed). **Blocked on
  PR #12 landing on `main`** — the rewrite targets text that does
  not yet exist on this branch's base.
- Slice 5 (local 3-runs harness) → cross-cutting determinism
  surface, **parallel-safe** with slices 2-4.

**Format**: `- [ ] T### [P?] [US?] Description with file path`.
Every slice section ends with the **commit obligation** stating
the RED-before / GREEN-after evidence required to mark the slice
done.

**Slice ordering (reviewer-enforced, per
`llm/reviews/15/reviewer-notes.md` §"Slice ordering")**:

1. Slice 1 first (independent, produces the oracle).
2. Slice 2 after slice 1 (uses slice 1 oracle as RED→GREEN).
3. Slice 3 after slice 2 GREEN against the slice-1 reproducer.
4. Slice 4 only after PR #12 has landed on `main`.
5. Slice 5 may be authored at any point alongside slices 2-4.

**`gate.sh` precondition** (per `reviewer-notes.md` §"Open"):
the pre-existing local `blst` narHash mismatch must be resolved
**before** any slice that touches Nix or Haskell code is pushed
for review. Plan-phase and tasks-phase commits are pure docs and
treat the gate as informational.

---

## Scope reduction at finalization (2026-05-09)

PR #16 ships the **functional MVP** as Slices 1+2 only. Slices 3,
4, and 5 were each found, mid-implementation, to depend on text
or derivations introduced by PR #12 (`003-seed-distribution`,
still OPEN) in ways the original plan/tasks did not surface:

- **Slice 3 (T015-T016) — DEFERRED-TO-FOLLOW-UP #18.**
  The `seed-image-determinism` derivation it widens, and the
  narrowing comment block it deletes, both live on PR #12
  (commits `d16b526`, `b4672c3`, `a9dd69a`). Absent on this
  branch's base.
- **Slice 4 (T017-T020) — DEFERRED-TO-FOLLOW-UP #19.**
  Already correctly marked BLOCKED-ON-PR#12 in Phase 6 below.
  Sources 1, 2, 3 of `contracts/narrowing-rewrite.md` target
  text in `specs/003-seed-distribution/...` that PR #12 owns.
- **Slice 5 (T021-T022) — DEFERRED-TO-FOLLOW-UP #20.**
  The `determinism-normal` recipe per
  `contracts/determinism-harness.md` Surface 3 builds
  `.#checks.x86_64-linux.seed-image-determinism` three times.
  That attribute does not exist on this branch's flake; it is
  owned by PR #12. Originally marked PARALLEL-SAFE with slices
  2-4 (which is correct on the bisect-ordering axis), but the
  recipe calls a PR #12-owned derivation, so it is not runnable
  on this branch.

Slice content below is preserved as a record of intent for the
follow-up tickets. The slice headers (Phase 5, 6, 7) carry
DEFERRED-TO-FOLLOW-UP markers pointing at the issues above.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Make the new feature artifacts navigable from
existing entry points and confirm the worktree is ready for
slice work.

- [ ] T001 [P] Add a "Recent Changes" row for 015 to `CLAUDE.md`
      via `.specify/scripts/bash/update-agent-context.sh` (already
      done in the plan commit; confirm the row is present and
      do not re-run if so)
- [ ] T002 [P] Confirm `llm/reviews/15/gate.sh` is executable and
      reproducible from a clean tree; record the current `blst`
      narHash status in `llm/reviews/15/reviewer-notes.md`
      (pre-existing; reviewer-owned)

**Checkpoint**: Worktree is mapped to the plan; gate state is
known.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Phase 0 research closure — the `(slotCount, …)`
bisect that R-002 promises, and the divergence-mechanism naming
that R-003 promises. No code change here; the only artefact is the
durable `research.md` update with evidence.

**Critical**: No slice 2 work can begin until R-001 has resolved
to **path (a)** or **path (c)** with R-002 evidence. Slice 1's
reproducer is the experimental harness this phase uses.

- [ ] T003 Run the bisect described in `research.md` §R-002 over
      `synthesis.slotCount` (300000 → 720) at fixed
      `securityParam=432, epochLength=86400, activeSlotsCoeff=0.05,
      seed=f0e0d0c0b0a090807060504030201000`. Record each
      `(slotCount, drift?)` row in `research.md` §R-002 "Evidence
      required by tasks.md". The harness for each candidate is two
      `db-synthesizer` runs of the same scenario JSON with a
      file-set diff under `chain-db/volatile/blocks-*.dat` as the
      oracle. Slice 1's `just reproduce-15-drift` recipe is the
      preferred wrapper once it lands; bare scripts are acceptable
      until then.
- [ ] T004 If T003's bisect runs out of envelope (drift survives
      to `slotCount == 720`), widen to `securityParam` and then
      `epochLength` per `research.md` §R-002 step 2. Record any
      additional rows in the same table.
- [ ] T005 Name the divergence mechanism per `research.md` §R-003
      and attach evidence (one of: `+RTS -DDEBUG` trace pair,
      `git grep` reference inside the pinned `ouroboros-consensus`
      source tree, consensus-team comment on a filed issue, or
      experimental confirmation that disabling a named knob
      collapses the drift). Update `research.md` §R-003 "Evidence
      required by tasks.md" in place.
- [ ] T006 Resolve R-001 to **path (a)** or **path (c)** based on
      T003-T005. The trigger to switch from path (a) to path (c)
      is documented in `research.md` §R-001 "Trigger to switch to
      path (c)". Record the choice and one-paragraph rationale in
      `research.md` §R-001.

**Checkpoint**: `research.md` carries the smallest envelope, the
named mechanism, and the chosen fix path. SC-003 ("the PR
description and at least one durable artifact … document the root
cause") is mechanically satisfied.

---

## Phase 3: Slice 1 — `just reproduce-15-drift` (Priority: P1)

**Goal**: A `just` recipe that bakes
`examples/scenarios/normal.json` twice and exits non-zero if the
file set under `chain-db/volatile/blocks-*.dat` differs between
the two runs. Independent of slice 2 in commit ordering; produces
the RED oracle slice 2 must turn GREEN.

**Maps to**: spec User Story 2 (root-cause evidence) — the
recipe is the durable, executable carrier of R-002. Also serves as
RED-before evidence for slice 2 and slice 3.

**Independent Test**: On the pre-fix baker SHA,
`just reproduce-15-drift` exits non-zero with a printable
file-set diff. After slice 2 lands, it exits zero on the same
baker SHA.

### Tests for Slice 1

- [ ] T007 [US2] Author the file-set diff oracle as a small shell
      script under `scripts/reproduce-15-drift.sh` (or extend
      `compose/acceptance/` if more natural) so the recipe is one
      line of `just`. The script must:
  - Bake `examples/scenarios/normal.json` twice into
    `tmp/repro-15/run-{a,b}/seed/`.
  - Diff the file set under
    `tmp/repro-15/run-{a,b}/seed/chain-db/volatile/blocks-*.dat`
    using `diff -ruN` or equivalent.
  - Exit non-zero on any diff; exit zero on a clean diff.
  - Print the smallest-drifting `slotCount` recorded in
    `research.md` §R-002 as a comment line on startup, per
    `quickstart.md` §"Reproducer (slice 1)".
- [ ] T008 [US2] Verify (manually, on the pre-fix baker SHA) the
      script's RED behaviour matches the observed-deltas list in
      `spec.md` §"Background" (e.g.
      `seed/chain-db/volatile/blocks-6.dat` present in one run and
      missing in the other). Capture the observed RED output as a
      one-paragraph note in the slice-1 commit body.

### Implementation for Slice 1

- [ ] T009 [US2] Add the `reproduce-15-drift` recipe to
      `justfile` that invokes the script from T007.

### Slice 1 commit obligation

One vertical commit containing T007-T009. **RED evidence**:
running `just reproduce-15-drift` on the pre-fix baker SHA exits
non-zero (captured in T008's commit-body paragraph). **GREEN
evidence**: deferred to slice 2.

**Checkpoint**: The reproducer is in tree and reproduces drift on
the current baker SHA.

---

## Phase 4: Slice 2 — Fix the producer (Priority: P1)

**Goal**: Resolve the producer-side drift via the path chosen in
T006. **Exactly one** of the two task subsets below is committed,
not both.

**Maps to**: spec User Story 1 (FR-001, FR-002, FR-006). After
this slice, slice 1's `just reproduce-15-drift` exits zero.

**Independent Test**: `just reproduce-15-drift` exits zero on the
post-fix baker SHA. Two independent local builds of
`examples/scenarios/normal.json` produce byte-identical
`seed/chain-db/` and a byte-identical deterministic half of
`seed/synthesis-report.json` (modulo `observation.*`).

### Tests for Slice 2

- [ ] T010 [US1] Re-run slice 1's `just reproduce-15-drift` after
      the fix is applied (T011-T014 below, depending on path)
      and confirm zero exit. Capture the GREEN output in the
      slice-2 commit body.

### Implementation for Slice 2 — Path (a) (preferred per R-001)

Owner of the field decision and any schema delta is
`contracts/scenario-schema-migration.md` (only triggered if a
*new* field is required). Refer to that document instead of
re-listing schema mechanics here.

- [ ] T011 [US1] Edit `examples/scenarios/normal.json` per the
      R-002 envelope (most likely lowering `synthesis.slotCount`
      to the smallest non-drifting value recorded in `research.md`
      §R-002, while preserving "realistic measurement" intent per
      `research.md` §R-001 rationale).
- [ ] T012 [US1] **Conditional on a new scenario field being
      introduced** (see
      `contracts/scenario-schema-migration.md`
      "When this contract triggers"): bump
      `schemas/scenario/v1.schema.json` to
      `schemas/scenario/v2.schema.json`, add the migration note,
      update `nix/checks.nix:scenario-schema` to reference v2,
      and update `examples/scenarios/local-fast.json` only if the
      new field has no safe default. The exact contract shape is
      defined in `contracts/scenario-schema-migration.md`
      §"Contract shape (when triggered)" — do not re-list it
      here.

### Implementation for Slice 2 — Path (c) (fallback)

Trigger condition documented in `research.md` §R-001 "Trigger to
switch to path (c)".

- [ ] T013 [US1] Bump `cabal.project`'s `ouroboros-consensus`
      `source-repository-package` `tag` to a fix-bearing commit on
      `intersectmbo/ouroboros-consensus`'s `main` branch (per
      constitution Principle III and the user-memory rule
      "Pins main only"). Regenerate `--sha256` in nix32 with
      `nix-prefetch-git --quiet --url <git-url> --rev <sha>`.
- [ ] T014 [US1] Regenerate `flake.lock` with `nix flake update`,
      keeping the diff scoped to the inputs the new pin
      transitively touches. Call out the `flake.lock` regeneration
      in the slice-2 commit body per `plan.md` §"Risks, Edge
      Cases, Migrations" "Path (c) regenerates flake.lock".

### Slice 2 commit obligation

One vertical commit containing exactly one of `{T011[+T012],
T013+T014}` plus T010 verification. **RED evidence**: slice 1's
oracle exits non-zero on the immediate parent commit. **GREEN
evidence**: slice 1's oracle exits zero on this commit, captured
in the commit body.

**Checkpoint**: The `normal` scenario is producer-deterministic at
this baker SHA. The gate is still narrowed to `local-fast` in
`nix/checks.nix`; widening is slice 3.

---

## Phase 5: Slice 3 — Widen `seed-image-determinism` to full scope (Priority: P1) **DEFERRED-TO-FOLLOW-UP #18**

**Goal**: Restore the determinism gate's in-scope scenario list
to the full `examples/scenarios/*.json` set. Owner of the exact
edit is `contracts/determinism-harness.md` Surface 1 — refer to
that document for the one-line diff rather than re-listing it
here.

**Maps to**: spec User Story 1 + User Story 3 (FR-003, SC-004).

**Depends on**: Slice 2 GREEN against slice 1's oracle. Reviewer
must enforce this ordering (per `reviewer-notes.md` §"Slice
ordering" and `plan.md` §"TDD Vertical Slices" "Slice 3
specifically depends on slice 2 to be green").

**Independent Test**:
`nix build .#checks.x86_64-linux.seed-image-determinism` succeeds
green for both `local-fast` and `normal` at the slice-3 commit.

### Tests for Slice 3

- [ ] T015 [US1] Build
      `nix build --rebuild .#checks.x86_64-linux.seed-image-determinism`
      twice locally on the slice-3 commit; both must succeed.
      Capture the second build's output in the slice-3 commit body
      as GREEN evidence. (RED evidence: the same command on the
      slice-3 *parent* commit fails on `normal` per the in-tree
      diagnostic added in PR #12 commit `b4672c3`.)

### Implementation for Slice 3

- [ ] T016 [US1] Apply the one-line edit defined in
      `contracts/determinism-harness.md` Surface 1 (and surfaced
      in `quickstart.md` §"Widen the gate (slice 3)") to
      `nix/checks.nix`. Delete the surrounding `# Scenarios …
      Once it is, restore…` comment block per
      `contracts/narrowing-rewrite.md` Source 4 — this comment
      lives in `nix/checks.nix` and travels with the gate
      widening, not with the spec doc rewrite (slice 4).

### Slice 3 commit obligation

One vertical commit containing T015-T016. **RED evidence**: gate
fails on `normal` against the slice-3 parent (i.e. the slice-2
GREEN commit) when `determinismScenarioFiles` is widened locally
without the producer fix — but this is an evidence-only check; the
real RED for slice 3 is "the gate is currently narrowed", which
is structural, not a test failure. **GREEN evidence**: the gate
passes for the full `scenarioFiles` glob on this commit.

**Checkpoint**: SC-004 ("the in-scope scenario list equals the
full `examples/scenarios/*.json` set") is met. CI runs of
`seed-image-determinism` on subsequent pushes count toward the
SC-001 three-runs threshold.

---

## Phase 6: Slice 4 — Rewrite the PR #12 narrowing (Priority: P3) **BLOCKED-ON-PR#12** **DEFERRED-TO-FOLLOW-UP #19**

**Goal**: Remove or rewrite the four narrowing fragments enumerated
in `contracts/narrowing-rewrite.md` (Sources 1, 2, 3 in
`specs/003-seed-distribution/...`; Source 4 lives in
`nix/checks.nix` and is owned by slice 3).

**Maps to**: spec User Story 3 (FR-004, SC-006).

**Blocking dependency**: PR #12 (Feature 003) **must be merged to
`main`** before this slice can land. Sources 1, 2, 3 do not exist
on this branch's base until PR #12 lands; the rewrite cannot be
authored against absent text. This is surfaced in `plan.md`
§"Risks, Edge Cases, Migrations" "003-feature in flight" and in
`quickstart.md` §"Prerequisites".

**Independent Test**: The acceptance grep defined in
`contracts/narrowing-rewrite.md` §"Acceptance" — do not
re-list the grep here; the contract owns the exact text.

### Tests for Slice 4

- [ ] T017 [US3] Run the acceptance grep from
      `contracts/narrowing-rewrite.md` §"Acceptance" against the
      slice-4 commit. Capture the empty-result output in the
      commit body as GREEN evidence. (RED evidence: the same grep
      against the slice-4 parent commit returns matches.)

### Implementation for Slice 4

- [ ] T018 [US3] Apply Source 1 edit per
      `contracts/narrowing-rewrite.md` Source 1 to
      `specs/003-seed-distribution/spec.md` (FR-006 known-limitation
      block).
- [ ] T019 [US3] Apply Source 2 edit per
      `contracts/narrowing-rewrite.md` Source 2 to the same file
      (SC-002 trailing sentence).
- [ ] T020 [US3] Apply Source 3 edit per
      `contracts/narrowing-rewrite.md` Source 3 to
      `specs/003-seed-distribution/contracts/publish-pipeline.md`
      if and only if the file contains a narrowing paragraph
      after PR #12 lands (the contract calls this out as
      conditional).

### Slice 4 commit obligation

One vertical commit containing T017-T020. **RED evidence**: grep
on the slice-4 parent returns the four fragments. **GREEN
evidence**: grep returns no narrowing matches on this commit.

**Reviewer enforcement**: Do not approve this slice until PR #12
is on `main` and the slice-4 parent is rebased onto a `main` that
contains the four source fragments. Workers must not invent the
target text.

**Checkpoint**: SC-006 ("PR #12 narrowing notes … are removed or
rewritten") is met.

---

## Phase 7: Slice 5 — Local 3-runs harness (Priority: P2) **PARALLEL-SAFE** **DEFERRED-TO-FOLLOW-UP #20**

**Goal**: Add `just determinism-normal` per
`contracts/determinism-harness.md` Surface 3. Owner of the recipe
text is the contract — refer there for the exact `bash` body
rather than re-listing it here.

**Maps to**: spec User Story 1 (SC-001 local pre-push surface)
and the cross-cutting determinism harness.

**Parallel-safety**: Slice 5 touches only `justfile`; it does
**not** touch `nix/checks.nix`, scenario JSON, schemas, or
`cabal.project`. It can be authored at any point alongside slices
2-4 without bisect-ordering hazard. Per `reviewer-notes.md`
§"Slice ordering" item 5, slice 5 is independent.

**Independent Test**: `just determinism-normal` runs three
sequential `nix build --rebuild
.#checks.x86_64-linux.seed-image-determinism` invocations; all
three must complete green.

### Tests for Slice 5

- [ ] T021 [US1] Run `just determinism-normal` on the slice-5
      commit (assuming slices 2-3 have landed; otherwise on a
      branch that includes slices 2-3). All three sub-runs must
      exit zero. Capture the third sub-run's success line in the
      slice-5 commit body as GREEN evidence.

### Implementation for Slice 5

- [ ] T022 [US1] Add the `determinism-normal` recipe to
      `justfile` per `contracts/determinism-harness.md` Surface 3.
      The recipe body is fully defined in the contract; do not
      add or remove flags.

### Slice 5 commit obligation

One vertical commit containing T021-T022. **RED evidence**:
`just --list` on the parent commit does not show
`determinism-normal`. **GREEN evidence**: `just
determinism-normal` runs three green sub-builds on this commit.

**Checkpoint**: The local pre-push falsification surface is in
tree. SC-001's local sub-property
(`contracts/determinism-harness.md` Surface 3) is met.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Quality gates and PR-readiness once slices 1-5 are in
tree. The reviewer-side three-runs CI policy lives in
`contracts/determinism-harness.md` Surface 2 and is **not** a
worker task — workers do not push spurious recheck invocations to
stack runs. Workers wait for natural CI cadence.

- [ ] T023 [P] Run `nix develop --quiet -c just CI` and capture
      green output in the PR description.
- [ ] T024 [P] Run `llm/reviews/15/gate.sh` and capture green
      output in the PR description. Pre-existing `blst` narHash
      mismatch must be resolved before this step (see
      `reviewer-notes.md` §"Required action before WorkRequired").
- [ ] T025 [P] Confirm Compose acceptance against the post-fix
      `normal` seed has run via the existing
      `build-gate -> compose-acceptance` ordering (no new step
      needed; this is `research.md` §R-006 + `quickstart.md`
      §"Compose acceptance (FR-009 / SC-005)"). Capture the
      `verdict=accepted` line in the PR description.
- [ ] T026 Run `git diff --check` and `nix develop --quiet -c
      shellcheck` on any new shell artefacts (T007's
      `scripts/reproduce-15-drift.sh` if it lives outside
      `compose/acceptance/`, otherwise covered by `gate.sh`).
- [ ] T027 Update the PR description with the slice-by-slice
      evidence summary (RED/GREEN excerpts captured in slice
      commit bodies, plus the SC-001 three-CI-runs link list per
      `contracts/determinism-harness.md` Surface 2 — populated
      after the third CI run goes green).

---

## Dependencies & Execution Order

### Slice Dependencies

The slice order is encoded by `plan.md` §"TDD Vertical Slices"
and re-stated in `llm/reviews/15/reviewer-notes.md` §"Slice
ordering". This document does not duplicate the rationale; it
references the owning sources.

```text
Slice 1 (independent)
   └─> Slice 2 (uses slice 1 oracle as RED→GREEN)
          └─> Slice 3 (depends on slice 2 GREEN)
                  └─> Polish (Phase 8)
                          ▲
Slice 5 (independent, parallel-safe with 2/3/4) ────┘

Slice 4 (BLOCKED on PR #12 landing on `main`) ──────┘
```

### Phase Dependencies

- Setup (Phase 1): No code dependencies.
- Foundational (Phase 2 — research closure): Blocks Slice 2.
  Slices 1 and 5 may proceed in parallel with Phase 2.
- Slice 1 (Phase 3): Independent of slices 2-5.
- Slice 2 (Phase 4): Depends on Phase 2 (R-001 chosen) and
  Slice 1's oracle (used as RED→GREEN evidence).
- Slice 3 (Phase 5): Depends on Slice 2 GREEN against Slice 1's
  oracle.
- Slice 4 (Phase 6): **BLOCKED-ON-PR#12** — depends on PR #12
  landing on `main` and is rebase-sensitive.
- Slice 5 (Phase 7): **PARALLEL-SAFE** — independent of
  slices 2-4.
- Polish (Phase 8): Depends on slices 1-3 and 5 in tree;
  slice 4 may close the polish loop after PR #12 lands.

### Within Each Slice

- Each slice = exactly one bisect-safe vertical commit (per
  `plan.md` §"TDD Vertical Slices" and the user-memory rule
  "Vertical commits — one commit per feature, not per layer").
- RED-before evidence must exist in the slice's commit body or
  in a referenced research note before the slice ships.
- GREEN-after evidence must exist in the slice's commit body
  before reviewer attention is requested.
- Bisect-safety: each commit compiles and runs the existing CI
  gate; the user-memory rule "Bisect-safe commits" applies.

### Parallel Opportunities

- T001 and T002 (Setup) can run in parallel.
- Slice 1 (T007-T009) and Slice 5 (T021-T022) can be authored
  in parallel as soon as Phase 2 starts.
- Within Polish: T023, T024, T025 can run in parallel.

### Sequencing constraints surfaced from owning sources

- `quickstart.md` §"Prerequisites": PR #12 merged to `main`
  before slice 4.
- `contracts/determinism-harness.md` Surface 2: three
  consecutive CI runs of `seed-image-determinism` green before
  reviewer approves merge — this is reviewer policy, not a
  worker task, and is referenced here only to make the
  end-to-end PR sequencing legible.

---

## Implementation Strategy

### MVP First (Slices 1-3 + Slice 5)

1. Phase 1 Setup + Phase 2 Foundational research.
2. Slice 1 (reproducer in tree).
3. Slice 2 (producer fix; one of path (a) or path (c)).
4. Slice 3 (gate widened).
5. Slice 5 (local 3-runs harness).
6. Polish (Phase 8) excluding the post-PR#12 doc rewrite.
7. **STOP and VALIDATE**: SC-001 three CI runs, SC-002 local
   pair-build, SC-005 Compose acceptance.

### Incremental Delivery

After the MVP lands, slice 4 is delivered the moment PR #12 is
on `main`:

1. Rebase the branch onto a `main` that contains the four
   source fragments named in `contracts/narrowing-rewrite.md`.
2. Apply T018-T020.
3. Re-run the acceptance grep (T017).
4. Update PR description (T027) and request reviewer approval.

### Notes

- Every task uses exact file paths (or names the contract that
  does, per the user-memory rule "tasks reference contracts").
- Tasks marked `[P]` either touch different files or can be
  authored before the dependent slice exists.
- Slice 2 is **exactly one** of path (a) or path (c); the
  research closure in Phase 2 picks which.
- Slice 4 is **not** a worker free-pass to copy the
  `contracts/narrowing-rewrite.md` text into a different file;
  the contract pre-commits target text on a `main`-merged base
  and the worker only applies the rewrite once that base
  exists.
- Workers do not push to manufacture CI run counts — the SC-001
  three-runs property is observed from natural pushes plus
  reviewer `recheck` re-invocations per
  `contracts/determinism-harness.md` Surface 2.
