# Research: Determinize `normal` Scenario db-synthesizer Output

This artifact carries the FR-005 obligation: identify and record the root
cause of the `normal` scenario drift, the smallest reproducer parameter
envelope, and the chosen FR-006 fix path. It also discharges User Story 2's
"root-cause evidence is captured" promise so a maintainer reading the merged
PR does not have to re-derive the investigation.

The research items below are stated as decisions the plan commits to, with
the evidence each must produce by Phase 2 (tasks). Items marked
`[NEEDS EVIDENCE]` carry their evidence in the corresponding TDD work
commit body.

## R-001: FR-006 fix path

**Decision**: Take **FR-006 path (a)** — consume the upstream stock
`db-synthesizer` executable unmodified and resolve the drift via
adjustment of an *existing* `synthesis.*` field on
`examples/scenarios/normal.json`. Do not introduce a new scenario field
unless R-002 demonstrates that no existing field bisects the drift.

If R-002 returns "no scenario-side envelope stops the drift while keeping
`normal` realistic enough", fall back to **FR-006 path (c)**: file an
upstream issue against `intersectmbo/ouroboros-consensus`, land a fix
commit on its `main` branch, and bump this repo's `cabal.project`
`source-repository-package` `tag` + `--sha256` for
`ouroboros-consensus` to that fix commit (constitution Principle III;
user-memory rule "Pins main only").

**Path (b) is rejected** because the synthesizer is already consumed as
a library through a thin Nix-side `iog-tools.nix` wrapper that exposes
`exes.db-synthesizer`, with no patches and no orchestration glue
beyond the existing `Cardano.Testnet.Baker.Synthesis` module. A new
in-repo executable would not give us any handle the current call site
does not already have, and would add an upstream-tracking burden for no
determinism win — moving the call from "stock binary" to "library
linked into in-repo binary" cannot fix non-determinism that lives
inside the library's own logic.

**Rationale**:

- Path (a) is strictly smaller than path (c). It changes one scenario
  JSON field rather than a `cabal.project` pin and (transitively) the
  `flake.lock`. Constitution Principle VI ("Smallest Provable Step")
  prefers it.
- Path (a) keeps the upstream pin stable for the rest of the
  cardano-node 10.7.1 alignment, which Features 001 and 002 share.
- The `normal` scenario was always intended as a "realistic
  measurement" path (see Feature 002 R-007 "realistic-epoch
  measurement"), so a *small* parameter adjustment that preserves
  realism is acceptable. A bisected-and-shrunk `slotCount`, for
  example, is still measurable enough to inform the storage strategy
  Feature 002 was sizing for.
- Path (c) is a fallback, not a default, because issue #15's resolution
  paths 1 and 2 have to run *first* to produce the upstream report
  with evidence. Filing a vague upstream "synthesis is non-deterministic
  at scale" issue without a reproducer is not actionable for the
  consensus team.

**Trigger to switch to path (c)**: R-002 ends with all of
`(slotCount, securityParam, epochLength)` widened, no envelope reduces
the drift to nil, and R-003 names the divergence mechanism with enough
specificity to file upstream.

## R-002: Smallest reproducer parameter envelope

**Decision**: The "smallest reproducer parameter envelope" required by
FR-005 is the smallest concrete `(slotCount, securityParam,
epochLength)` triple, at the fixed scenario seed
`f0e0d0c0b0a090807060504030201000` and the fixed
`activeSlotsCoeff = 0.05`, that *still* produces a non-empty
`chain-db/volatile/blocks-*.dat` file-set diff between two independent
`db-synthesizer` runs of the same input. The current observed drift
sits at `slotCount=300000, securityParam=432, epochLength=86400`
(`examples/scenarios/normal.json` as committed); the current
non-drifting boundary sits at `slotCount=720` (`local-fast.json`).

The bisect order is:

1. Halve `slotCount` from 300000 toward 720, keeping
   `securityParam` and `epochLength` at the `normal.json` values, until
   the drift stops. Record the smallest drifting `slotCount` and the
   largest non-drifting `slotCount`. The "smallest envelope" is the
   smallest drifting `slotCount` — the shortest run that still exposes
   the bug.
2. If the drift survives all the way down to `slotCount == 720`,
   widen the bisect axis to `securityParam` and then to
   `epochLength`. This case is unlikely (because `local-fast` does
   not drift), but the plan stays honest about it.
3. Each bisect step is two `db-synthesizer` runs of the same scenario
   JSON, with the file-set diff under
   `chain-db/volatile/blocks-*.dat` as the oracle. The diff is
   exactly the one the existing `seed-image-determinism` gate
   computes; the bisect harness lives next to the gate so the oracle
   is shared.

**Why `slotCount` first**: The issue body's "Hypothesis" section names
the four candidate mechanisms (parallel block production schedule,
wallclock-sensitive stop boundary, time-based seed fall-through,
`/dev/urandom` read inside synthesizer glue). Three of the four scale
with run length, not with chain parameters. `slotCount` is therefore
the most likely single-axis knob.

**Why this is "smallest"**: A smaller envelope means a faster bisect
inside `db-synthesizer`'s own source tree if R-001 falls through to
path (c). The shortest reproducing run is also the shortest gate
runtime if path (a) chooses a smaller `slotCount` for `normal`.

**Evidence required by tasks.md** `[NEEDS EVIDENCE]`:

- A row table of `(slotCount, securityParam, epochLength) -> drift?`
  observations covering the bisect.
- The smallest drifting `slotCount` recorded in this artifact.
- A reproducer recipe (`just reproduce-15-drift`) that bakes
  `normal` twice and exits non-zero on file-set diff.

**Alternatives considered**:

- *Bisect on `securityParam` first*: rejected because `securityParam`
  is a chain-protocol parameter with a coupled effect on block
  density; changing it changes far more than just run-length-like
  drift exposure.
- *Bisect on `activeSlotsCoeff`*: rejected for the same reason —
  changing it changes block density, which would conflate the drift
  signal with a totally different variable.
- *Run with verbose synthesizer tracing first, bisect later*:
  rejected as Phase-0 sequencing — tracing without a reproducer
  produces a haystack. We bisect on the oracle that already exists
  (the file-set diff) and only then collect traces at the smallest
  envelope.

## R-003: Named divergence mechanism

**Decision**: Phase 0 must name the divergence mechanism with enough
specificity to satisfy User Story 2 acceptance scenario §1. Acceptable
named mechanisms (from the issue body) are:

- A non-deterministic parallel block-production schedule inside
  `db-synthesizer` proper.
- A wallclock-sensitive stop boundary on the synthesis loop.
- A time-based seed fall-through somewhere in the synthesizer glue
  that drops back to system time when an explicit seed isn't threaded
  all the way down.
- A `/dev/urandom` read inside the Haskell library glue (for example
  a `withCryptoSecureRandom` that ignores the deterministic
  `(scenario.seed, role, label)` derivation).
- A new mechanism, named with file/line evidence inside
  `ouroboros-consensus`.

**Acceptance bar**: "named with evidence", not "fixed in this repo".
Principle V keeps any upstream code change upstream. The evidence may
take the form of (i) a `db-synthesizer` `+RTS -DDEBUG` trace pair where
the divergence point is identified, (ii) a `git grep` reference inside
the pinned `ouroboros-consensus` source tree pointing at the
non-determinism site, (iii) a comment from the consensus team on a
filed issue, or (iv) an experimental confirmation that *removing* a
named knob (for example `/dev/urandom`) collapses the drift.

**Why this is in research and not in plan**: The plan must commit to a
fix path (R-001) and a smallest envelope (R-002) up front because
those decisions shape Phase 1 design. The named mechanism (R-003) is
the durable record FR-005 promises — it lives in this file, not in
plan.md, because it is empirical evidence rather than a design
decision.

**Evidence required by tasks.md** `[NEEDS EVIDENCE]`:

- The mechanism name and the evidence type (i, ii, iii, or iv above).
- A link or quote sufficient for a future maintainer reading this
  artifact to verify the claim without re-deriving the bisect.

## R-004: Determinism harness placement

**Decision**: The SC-001 "three consecutive runs" property is enforced
through three distinct surfaces, not one:

1. *Inside one CI invocation*: the existing
   `nix/checks.nix:seed-image-determinism` gate already pair-builds
   each scenario as two genuinely independent derivations and diffs
   the layer payload (FR-006 in 003-spec, plus the per-file
   diagnostic added in PR #12 commit `b4672c3`). After widening
   `determinismScenarioFiles` from
   `builtins.filter (f: f == "local-fast.json") scenarioFiles` to
   `scenarioFiles`, this property covers `normal` automatically. No
   harness change needed.
2. *Across CI invocations*: the gate runs on every push and every PR
   branch (003-spec FR-008). SC-001's "three consecutive runs"
   threshold is met by the first three independent CI invocations
   that exercise the widened gate. Reviewer policy: do not approve
   the merge until at least three consecutive `seed-image-determinism`
   runs have completed green on this branch.
3. *Locally before push*: a new `just determinism-normal` recipe
   runs `nix build .#checks.x86_64-linux.seed-image-determinism`
   three times in sequence with a `--rebuild` flag between calls,
   so a maintainer falsifies intermittent drift before pushing.
   This is the user-memory rule "Run FULL CI locally before every
   push" applied to the specific surface this feature touches.

**Rationale**:

- Three sequential runs on the same runner inside one workflow do not
  give three independent observations; the Nix store cache fuses
  them. So "three consecutive CI runs" must mean three independent
  workflow invocations, not three steps inside one workflow.
- Adding a new CI matrix step that runs the gate three times in one
  workflow would burn CI budget for a property the existing pair-build
  already covers in-derivation, and would weaken the spec's "three
  *independent* CI runs" intent.
- The local recipe gives the maintainer a fast falsification surface
  that doesn't depend on CI observability.

**Alternatives considered**:

- *Add a `--matrix run=1,2,3` to the GitHub workflow*: rejected as
  above (no extra independence; CI cost goes up).
- *Make the gate intentionally reseed on each derivation*: rejected
  because the gate's whole purpose is to assert determinism; injecting
  randomness into the gate undermines its own oracle.

## R-005: Constitution-V justification of path (a)

**Decision**: Path (a) is constitution-Principle-V-compliant by
construction. Stock `db-synthesizer` is invoked exactly as today
through `nix/iog-tools.nix`'s
`project.hsPkgs.ouroboros-consensus.components.exes.db-synthesizer`,
no flags added, no flags removed, no environment variables
introduced, no patches. The only change inside the baker is to one
input value in `examples/scenarios/normal.json`.

**Rationale**: User Story 2 acceptance scenario §2 requires the plan
to "justify the fix against constitution principle V; either the
synthesizer is consumed unmodified with adjusted inputs, or it is
consumed as a library through a minimal in-repo executable, or a
pinned upstream fix is referenced". Path (a) is the first of those
three. Path (c) (the fallback) is the third. Both pass.

## R-006: Compose acceptance against post-fix `normal` seed

**Decision**: FR-009 requires Compose acceptance against the post-fix
`normal` seed. Re-use the existing `compose/acceptance/run.sh` flow,
the same one Feature 002 introduced and Feature 003 wired into the
publish pipeline. No new harness; no compose-yaml change.

**Rationale**: Constitution Principle VI requires Compose acceptance
on every feature that creates or changes baked testnet assets. This
feature changes the bytes of the `normal` seed (Assumption 2 in
spec), so the existing harness must run against the new bytes before
merge. The harness already accepts a seed directory and starts a
`cardano-node` from a private writable copy; the only thing this
feature has to do is *invoke* it during CI, which the
`build-gate -> compose-acceptance` job ordering in 003 already does.

**Alternatives considered**: none. Constitution VI is non-negotiable.
