# Quickstart: Determinize `normal` Scenario db-synthesizer Output

This is the maintainer playbook for resolving issue #15. It walks
from "open the worktree" to "merge the PR" and orders the steps so
that each commit is bisect-safe.

## Prerequisites

- PR #12 (Feature 003 — seed distribution) **merged to `main`**.
  The narrowing rewrite (FR-004 / SC-006) cannot land until then,
  because the source paragraphs do not yet exist on `main`.
- A working `nix develop` shell.
- A free hour for the bisect on `slotCount` (Phase 0 R-002).

If PR #12 is still open, this branch can still produce R-002 and
R-003 evidence, but the gate-widening commit (slice 3 in
`plan.md`) and the doc-rewrite commit (slice 4) must wait. The plan
allows the worker to publish slices 1 and 2 first and pause; the
reviewer's "approve to merge" gate is what waits on PR #12.

## Reproducer (slice 1)

```bash
just reproduce-15-drift
```

This recipe (added by slice 1) bakes `examples/scenarios/normal.json`
twice into `tmp/repro-15/run-{a,b}/seed/` and exits non-zero if the
file-set under `chain-db/volatile/blocks-*.dat` differs between the
two runs.

Pre-fix expected outcome: non-zero exit, `chain-db/volatile/blocks-6.dat`
present in one run and missing from the other.

Post-fix expected outcome: zero exit.

Because Phase 0 research lives durably in `research.md`, the
reproducer also prints the smallest-drifting `slotCount` recorded
there as a comment, so the maintainer can re-run the bisect with a
shorter scenario without grepping the research notes.

## Bisect (Phase 0 R-002)

Halve `synthesis.slotCount` from 300000 toward 720, two runs per
candidate, recording `(slotCount, drift?)` in the durable
`research.md` table. Stop when the drift disappears; the smallest
drifting `slotCount` is the FR-005 envelope.

## Apply the fix (slice 2)

Two branches based on R-001 outcome:

- **Path (a)** (preferred): edit
  `examples/scenarios/normal.json`'s `synthesis.*` field per R-002.
  If a new field is required, also add it to
  `schemas/scenario/v2.schema.json` per
  [contracts/scenario-schema-migration.md](./contracts/scenario-schema-migration.md).
- **Path (c)** (fallback): bump `cabal.project`'s
  `ouroboros-consensus` SRP `tag` to a `main` commit on
  `intersectmbo/ouroboros-consensus` that carries the upstream fix.
  Regenerate `--sha256` in nix32 with
  `nix-prefetch-git --quiet --url <git-url> --rev <sha>` and
  format-convert to nix32 if needed. Regenerate `flake.lock` with
  `nix flake update`.

Run `just reproduce-15-drift` after the slice-2 commit. It must exit
zero.

## Widen the gate (slice 3)

Edit `nix/checks.nix`:

```diff
- determinismScenarioFiles = builtins.filter (f: f == "local-fast.json") scenarioFiles;
+ determinismScenarioFiles = scenarioFiles;
```

Delete the surrounding `# Scenarios ... Once it is, restore...`
comment block (see
[contracts/narrowing-rewrite.md](./contracts/narrowing-rewrite.md)
"Source 4").

Run `just determinism-normal` (added by slice 5). It must complete
all three sub-runs green.

## Rewrite the narrowing (slice 4)

Apply the rewrites in
[contracts/narrowing-rewrite.md](./contracts/narrowing-rewrite.md)
sources 1, 2, 3. Verify with the `git grep` acceptance test in that
file.

## Add the local 3-runs harness (slice 5)

Add the `just determinism-normal` recipe per
[contracts/determinism-harness.md](./contracts/determinism-harness.md)
Surface 3.

## Run the full local CI gate

```bash
nix develop --quiet -c just CI
llm/reviews/15/gate.sh
```

Both must pass.

## Push and wait for three green CI runs

Push the branch. Wait until at least three independent CI invocations
of `seed-image-determinism` have completed green for `normal`
(SC-001). The reviewer's approval gate enforces this before merge.

## Compose acceptance (FR-009 / SC-005)

`compose-acceptance` runs automatically on every CI invocation after
the build gate (003-spec FR-007). It already exercises the post-fix
`normal` seed. No manual step needed unless CI fails.

## Merge

Standard rebase merge through GitHub. Owner finalizes per the
resolve-ticket protocol.
