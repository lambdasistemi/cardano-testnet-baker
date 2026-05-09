# Implementation Plan: Determinize `normal` Scenario db-synthesizer Output

**Branch**: `015-synthesizer-nondeterminism` | **Date**: 2026-05-09 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/015-synthesizer-nondeterminism/spec.md`

## Summary

Close the PR #12 narrowing of the `seed-image-determinism` Nix gate so it
covers the full `examples/scenarios/*.json` set, by removing the
producer-side non-determinism that surfaces in `db-synthesizer` runs of the
`normal` scenario at `slotCount = 300000`. The fix path is committed up
front to **FR-006 path (a)**: keep consuming the upstream stock
`db-synthesizer` executable, and resolve the drift through scenario-side
input adjustment, with **FR-006 path (c)** as the documented fallback if
research falsifies the scenario-side hypothesis. Path (b) (in-repo
executable consuming consensus as a library) is rejected up front because
the present mode (a) consumption already satisfies Principle V and is
strictly smaller.

The plan structures research as a one-knob bisect on `synthesis.slotCount`
under fixed `securityParam`/`epochLength`, with a two-stage CI extension
so that `seed-image-determinism` gates the full scenario set and SC-001's
"three consecutive runs" property is covered both inside one CI invocation
(via the gate's already-internal pair-build) and across at least three
independent CI invocations (via the existing per-PR + per-push cadence and
a new `just` recipe that triples the gate locally before push).

## Spec Trace

| Spec item | Plan handling |
|-----------|---------------|
| FR-001, FR-002 | Phase 0 research narrows the input that produces drift; Phase 1 design wires the chosen knob into `examples/scenarios/normal.json` (and, if needed, into the schema). |
| FR-003 | Phase 1 design widens `nix/checks.nix:determinismScenarioFiles` from the `local-fast`-only `builtins.filter` back to the full `scenarioFiles`. |
| FR-004 | Phase 1 design rewrites the narrowing notes in `specs/003-seed-distribution/spec.md` (FR-006 / SC-002) and `specs/003-seed-distribution/contracts/publish-pipeline.md`. |
| FR-005 | Phase 0 `research.md` is the durable carrier. The "smallest envelope" is concretized as the smallest `slotCount` at fixed `securityParam=432`/`epochLength=86400` that still drifts (see Phase 0 §R-002). |
| FR-006 | Plan commits to path (a). Fallback to path (c) is documented and gated on a concrete trigger (research §R-001 outcome). Path (b) is rejected. |
| FR-007 | `local-fast` stays in `determinismScenarioFiles`; the gate widening is additive, never subtractive. |
| FR-008 | If the chosen knob is a *new* scenario field, Phase 1 contracts include a v1->v2 schema bump and migration note; if it is an existing field's value change, the schema is unchanged. The plan flags both branches because the input falls out of research. |
| FR-009 | Compose acceptance harness invocation against the post-fix `normal` seed is added as a Phase 1 contract and a CI step ordering rule. |
| SC-001 | Determinism harness §"Three-runs property" wires the property into local + CI surface. |
| SC-002 | Same surface as FR-001/FR-002. |
| SC-003 | This `plan.md` plus `research.md` are the durable carriers. |
| SC-004 | FR-003 line edit. |
| SC-005 | FR-009 wiring. |
| SC-006 | FR-004 doc rewrite. |

## Technical Context

**Language/Version**: Haskell, GHC 9.12.3 via haskell.nix `ghc9123`. Same
toolchain as Features 001/002/003; this feature changes inputs and the
gate scope, not the toolchain.

**Primary Dependencies**:

- Stock `db-synthesizer` from the pinned
  `ouroboros-consensus` source-repository-package (currently
  `tag: c87aa760001e60f0f0d3353f793eb089adb917e7`,
  `--sha256: 1hxmmhci120krklnx4dy5jbw5dwjwyvmfqns6frci6fw2qbsr7d7`,
  consumed unmodified through `nix/iog-tools.nix`).
- Existing scenario JSON Schema at `schemas/scenario/v1.schema.json`.
- Existing Compose acceptance harness at `compose/acceptance/run.sh`.
- Existing seed-image determinism gate at `nix/checks.nix` (introduced
  by PR #12 / Feature 003).

**Storage**: No new storage. Same on-disk artifact tree as Feature 002:
`seed/genesis/`, `seed/pools/`, `seed/utxo-keys/`, `seed/chain-db/`,
`seed/metadata.json`, `seed/synthesis-report.json`.

**Testing**: Hspec unit tests where applicable (only if a Haskell-side
change is needed; the default expectation is no Haskell change), Nix
checks (the existing `seed-image-determinism` widened to full scope, the
existing `example-bake-determinism`, `synthesis-report-shape`,
`scenario-schema`), shellcheck on shell pieces, Compose acceptance.

**Target Platform**: x86_64-linux Nix builds; Ubuntu runner for Compose
acceptance. No new platform.

**Project Type**: CLI plus Nix-packaged checks and shell acceptance
harness. No structural change.

**Performance Goals**: The `normal` scenario seed-image-determinism gate
must fit within the existing PR CI budget. The current `local-fast`-only
gate is sub-minute; the `normal` synthesis-bake-image flow is on the
order of tens of seconds at `slotCount=300000`, so two independent
derivations (`-determinism-a`, `-determinism-b`) plus the diff stage
remain inside the project's per-PR CI budget. If Phase 0 research lowers
`slotCount` for `normal`, the gate cost drops accordingly.

**Constraints**:

- No fork or vendored copy of `ouroboros-consensus` /
  `cardano-node` (Principle V).
- No moving tags; if path (c) is taken, the new
  `ouroboros-consensus` SRP `tag` and `--sha256` must point at a fix
  commit on `main` (Principle III; matches the user-memory rule
  "Pins main only").
- No environment variables silently shaping output (Principle I).
- The existing pair-build mechanism in `seed-image-determinism` is
  treated as load-bearing; this feature changes the in-scope scenario
  list, not the mechanism (spec Assumption 4; user-memory rule "Don't
  fix working infra").

**Scale/Scope**: One scenario (`normal`) returns to the determinism
gate. No new scenario is added in this feature. No new module is added
unless Phase 0 research demonstrates one is required.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Plan Evidence |
|-----------|--------|---------------|
| I. Declarative scenarios as single input | PASS | The fix is either an existing-field value change (no schema effect) or an additive scenario-field with schema v1->v2 bump and migration note (FR-008). No env-var route, no implicit default. |
| II. Determinism by construction | PASS | The whole feature exists to satisfy this principle for `normal`. The harness asserts byte-identical seed payloads across two independent derivations, three CI invocations. |
| III. Reproducibility by pinning | PASS | If path (c) is taken, the SRP `tag` is bumped to a fix commit SHA on `main` and `--sha256` is regenerated in nix32. The current SRP pin already follows this rule. |
| IV. Nix-first, haskell.nix | PASS | Gate widening is a one-line edit in `nix/checks.nix`; no new build path. CI continues through the Build Gate. |
| V. Stock tools, custom orchestration | PASS | Path (a) preserves stock-tool consumption verbatim. Path (c) preserves stock-tool consumption with a new pinned upstream commit. Path (b) is rejected. No fork, no vendor. |
| VI. Smallest provable step | PASS | The plan defers the path (a) vs. (c) call to Phase 0 research, runs Compose acceptance against the post-fix `normal` seed (FR-009), and produces one bisect-safe vertical slice per change point. |

## Project Structure

### Documentation (this feature)

```text
specs/015-synthesizer-nondeterminism/
├── plan.md                         # this file
├── research.md                     # Phase 0 root-cause and envelope record
├── data-model.md                   # Phase 1 entity changes (mostly delta vs. 002/003)
├── quickstart.md                   # Phase 1 maintainer playbook
├── contracts/
│   ├── determinism-harness.md      # Phase 1 — pair-build + 3-runs property
│   ├── scenario-schema-migration.md  # Phase 1 — v1->v2 only if research demands it
│   └── narrowing-rewrite.md        # Phase 1 — exact text to remove/rewrite in 003
├── checklists/
│   └── requirements.md             # already on disk, owner-approved
└── tasks.md                        # Phase 2 output (NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
nix/
├── checks.nix                      # widen determinismScenarioFiles to full scenarioFiles
└── (no new modules expected)

examples/scenarios/
├── normal.json                     # may receive a parameter adjustment (research-driven)
└── (local-fast.json untouched)

schemas/scenario/
└── v1.schema.json                  # only edited if FR-008 requires a new field

specs/003-seed-distribution/
├── spec.md                         # rewrite FR-006 known-limitation block + SC-002
└── contracts/publish-pipeline.md   # rewrite the narrowing paragraphs

cabal.project                       # only edited if path (c) is taken
flake.lock                          # only regenerated if path (c) is taken

justfile                            # add `determinism-normal` recipe (3-runs harness)
```

**Structure Decision**: Make this feature subtractive by default —
remove the `local-fast`-only filter, edit the narrowing notes, run the
gate. Touch `examples/scenarios/normal.json` only if Phase 0 research
identifies a scenario-side knob; touch `cabal.project` only if Phase 0
research closes path (a) and forces path (c). The structure mirrors
Features 002/003: one Haskell module surface (none expected), Nix
checks under `nix/`, Compose acceptance unchanged, contracts as small
markdown files.

## Phase 0 Research

See [research.md](./research.md). Mandatory outputs before Phase 1 can
close:

- **R-001**: Path call between FR-006 (a) and (c). Decision is binary
  and one-shot: if a scenario-side parameter envelope can stop the
  drift while keeping `normal` realistic enough to satisfy the
  measurement intent of Feature 002, take path (a); otherwise file
  upstream and switch to path (c).
- **R-002**: The "smallest reproducer parameter envelope" required by
  FR-005, expressed as a concrete `(slotCount, securityParam,
  epochLength)` triple at the fixed scenario seed
  `0xf0e0d0c0...01000`. The bisect axis is `slotCount` first
  (cheapest knob), with `securityParam` and `epochLength` widened
  only on negative results.
- **R-003**: The named divergence mechanism inside
  `db-synthesizer` (one of the four named in spec User Story 2 §1, or
  a new one). The acceptance bar is "named with evidence", not "fixed
  in this repo": Principle V keeps the upstream fix upstream.

## Phase 1 Design

See:

- [data-model.md](./data-model.md) — entity-level delta vs. Features
  002/003. The only entity that may change is `Scenario` (if a new
  `synthesis.*` field is introduced), with a corresponding
  `Synthesized ChainDB Seed` byte change between pre-fix and post-fix
  baker SHAs (Assumption 2 in spec).
- [contracts/determinism-harness.md](./contracts/determinism-harness.md) —
  the SC-001 / SC-002 harness, the three-runs property, where it lives
  in CI, and how it relates to the existing pair-build inside
  `nix/checks.nix:seed-image-determinism`.
- [contracts/scenario-schema-migration.md](./contracts/scenario-schema-migration.md) —
  the FR-008 contract. Filled in only if R-001 picks path (a) *and*
  the chosen knob is a new field.
- [contracts/narrowing-rewrite.md](./contracts/narrowing-rewrite.md) —
  the exact-text rewrite of the PR #12 narrowing paragraphs in
  `specs/003-seed-distribution/spec.md` and `contracts/publish-pipeline.md`.
- [quickstart.md](./quickstart.md) — maintainer playbook from "open
  this PR" to "merge it" including the local 3-runs harness.

## Determinism Harness — SC-001 / SC-002 Surface

The single largest plan-level decision after FR-006 is what
"three consecutive runs" in SC-001 means and where it lives. The
spec's stylistic note flagged the ambiguity. The plan resolves it as
follows:

1. **Inside one CI invocation** — the existing
   `seed-image-determinism` gate already builds each scenario as
   two genuinely independent derivations and diffs the layer
   payload. That covers "two builds at the same SHA on the same
   runner" without a separate harness change. After widening
   `determinismScenarioFiles` back to `scenarioFiles`, this property
   covers `normal` automatically.

2. **Across CI invocations** — `seed-image-determinism` runs on
   every push and every PR branch. The first three independent CI
   invocations of this branch (and any subsequent branches) all
   exercise the gate. SC-001 is met as long as the gate is green
   across at least three of those invocations without intermittent
   failure. The plan does *not* add a new "run the gate three times
   inside one workflow" matrix step; that would burn CI cost without
   strengthening the property — three sequential runs on the same
   runner are not three independent observations.

3. **Locally before push** — the plan adds a `just` recipe
   `determinism-normal` that runs
   `nix build .#checks.x86_64-linux.seed-image-determinism` three
   times in sequence with `--rebuild` between calls, so a maintainer
   can falsify intermittent drift before pushing. This recipe is the
   user-memory rule "Run FULL CI locally before every push" and is
   referenced by the quickstart and tasks artefacts.

The detailed harness contract is in
[contracts/determinism-harness.md](./contracts/determinism-harness.md).

## Risks, Edge Cases, Migrations

- **Intermittent drift after the fix.** The drift may have been
  probabilistic — two pre-fix runs occasionally matched by chance.
  The plan mitigates by retaining the gate's pair-build inside one
  CI invocation, the three-runs CI cadence, and the local
  `determinism-normal` recipe before push. The reviewer-side rule is
  "do not approve on a single green CI; require three consecutive
  green CIs of `seed-image-determinism` before merging".
- **Path (c) regenerates flake.lock.** If the chosen path bumps the
  `ouroboros-consensus` SRP, `flake.lock` updates. The PR description
  must call this out, the determinism gate re-runs against the new
  pin, and Compose acceptance re-runs against the new seed bytes.
- **Schema migration cost.** If R-001 -> path (a) introduces a new
  `synthesis.*` field, the published JSON Schema bumps to v2 and
  consumers (currently `schemas/scenario/v1.schema.json` consumers
  in this repo only — no external consumer published yet) follow the
  migration note in
  [contracts/scenario-schema-migration.md](./contracts/scenario-schema-migration.md).
- **Seed-byte cascade.** The deterministic seed bytes for `normal`
  *will* change between pre-fix and post-fix baker SHAs. This is
  expected per spec Assumption 2 and Principle III: consumers pin
  the baker SHA, not a moving tag. The 003-feature published image
  primary tag (`<scenario>-<scenarioDigest>`) for `normal` will
  change with this PR, which is the intended behaviour.
- **Future scenarios.** Because `determinismScenarioFiles` becomes
  the full glob `scenarioFiles`, any future committed scenario is
  in-gate by default, matching FR-003 spirit. The plan does not need
  an allow-list mechanism.
- **003-feature in flight.** PR #12 (Feature 003) is the upstream PR
  this branch depends on. The narrowing edits in FR-004 / SC-006
  cannot be made until 003 lands on `main`. The plan calls this out
  as a sequencing constraint in `quickstart.md`; tasks.md will
  reflect it.

## Public Contracts Touched

- **`nix/checks.nix:seed-image-determinism`** — in-scope scenario
  list expands from `local-fast` to all of
  `examples/scenarios/*.json` (FR-003).
- **`schemas/scenario/v1.schema.json`** — possibly bumped to
  `v2.schema.json` with a migration note (FR-008, conditional on
  R-001 outcome and chosen knob).
- **`examples/scenarios/normal.json`** — possibly modified
  (FR-005 chosen envelope, conditional on R-001 outcome).
- **`specs/003-seed-distribution/spec.md`** and
  **`specs/003-seed-distribution/contracts/publish-pipeline.md`** —
  narrowing notes rewritten (FR-004).
- **`cabal.project`** + **`flake.lock`** — possibly bumped if path (c)
  is taken (Principle III).

No CLI surface change. No JSON schema for the synthesis report.

## TDD Vertical Slices

The plan exposes the following vertical, bisect-safe commit slices.
Each slice is testable in isolation, fails before the change, passes
after, and matches the user-memory rule "Vertical commits — one
commit per feature, not per layer". These map directly into Phase 2
tasks but the plan must already make them obvious:

1. **R-002 reproducer slice** — a `just` recipe
   `reproduce-15-drift` that bakes `normal` twice and exits non-zero
   if `chain-db/volatile/blocks-*.dat` file sets differ. RED on
   pre-fix baker; GREEN after the chosen fix. Lives entirely in
   `justfile` + a small shell script under `compose/acceptance/` or
   a new `scripts/` directory.
2. **R-001 path-(a) slice** OR **R-001 path-(c) slice** — exactly
   one of these is committed, depending on R-001 outcome:
   - Path (a): one commit edits
     `examples/scenarios/normal.json` (and possibly
     `schemas/scenario/v*.schema.json`) and bakes-clean against the
     R-002 reproducer.
   - Path (c): one commit bumps `cabal.project`'s
     `ouroboros-consensus` SRP `tag` + `--sha256`, regenerates
     `flake.lock`, and bakes-clean against the R-002 reproducer.
3. **Gate widening slice** — one commit edits
   `nix/checks.nix:determinismScenarioFiles` from
   `builtins.filter (f: f == "local-fast.json") scenarioFiles`
   to `scenarioFiles`. RED-becomes-GREEN against the
   `seed-image-determinism` Nix check now that slice 2 has fixed
   the producer.
4. **Doc-rewrite slice** — one commit rewrites the FR-004 narrowing
   notes in
   `specs/003-seed-distribution/spec.md` and
   `specs/003-seed-distribution/contracts/publish-pipeline.md`.
   No code change.
5. **Acceptance + 3-runs harness slice** — one commit adds the
   `just determinism-normal` recipe and a small `tests/` or `nix/`
   wrapper that materialises the SC-005 / SC-001 properties for
   local pre-push use.

Slices are bisect-safe because each compiles and runs the existing CI
gate after merging onto its predecessor. Slice 3 specifically depends
on slice 2 to be green; reviewer must enforce this ordering.

**Scope reduction at finalization (2026-05-09).** PR #16 ships the
functional MVP as Slices 1 + 2 only — the reproducer
(`just reproduce-15-drift`) and the producer fix (cap
`examples/scenarios/normal.json:slotCount` at 100000, below the
volatile-DB GC drift floor identified in research §R-003). Slices
3, 4, and 5 were each found, mid-implementation, to depend on text
or derivations introduced by PR #12 (`003-seed-distribution`, still
OPEN): Slice 3 widens a `seed-image-determinism` gate that does not
exist on this branch's base; Slice 4's three `narrowing-rewrite.md`
sources live in `specs/003-seed-distribution/...`; Slice 5's
recipe builds the same `seed-image-determinism` derivation three
times. They are deferred to follow-up issues #18 (Slice 3), #19
(Slice 4), and #20 (Slice 5), each blocked on PR #12 landing.
The bug closing #15 is functionally fixed by Slices 1 + 2 alone —
the producer is deterministic on the `normal` scenario at
`slotCount = 100000`, falsifiable locally via Slice 1's oracle.

## Post-Design Constitution Check

| Principle | Status | Design Evidence |
|-----------|--------|-----------------|
| I. Declarative scenarios as single input | PASS | The only output-affecting input lives in scenario JSON or in a SHA-pinned dependency. No env var. |
| II. Determinism by construction | PASS | Phase 1 contracts assert byte-identical `chain-db/` and stripped `synthesis-report.json` across two independent derivations and three CI invocations. |
| III. Reproducibility by pinning | PASS | Path (c), if taken, bumps `cabal.project` SRP `tag` to a `main` commit and regenerates `--sha256` in nix32. |
| IV. Nix-first, haskell.nix | PASS | Gate widening, the 3-runs harness, and Compose acceptance all run through Nix outputs. |
| V. Stock tools, custom orchestration | PASS | Stock `db-synthesizer` consumed unmodified in either path (a) or path (c). Path (b) explicitly rejected. |
| VI. Smallest provable step | PASS | Each vertical slice is independently testable; Compose acceptance exercises the post-fix `normal` seed before merge. |

## Complexity Tracking

No constitution violations.
