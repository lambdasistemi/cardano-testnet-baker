# Contract: PR #12 Narrowing Rewrite

**Feature**: [../spec.md](../spec.md)
**Plan**: [../plan.md](../plan.md)

This contract specifies the exact textual edits that satisfy FR-004
and SC-006: the PR #12 narrowing notes in
`specs/003-seed-distribution/spec.md` and
`specs/003-seed-distribution/contracts/publish-pipeline.md` must be
removed or rewritten to reflect post-fix full-scope determinism.

The edits cannot be applied until PR #12 (Feature 003) has merged
into `main`, because those files do not yet exist on this branch's
base. The rewrite is therefore a Phase 2 task with a sequencing
constraint surfaced in `quickstart.md`.

## Sources to rewrite

After PR #12 merges, the following text fragments must be located and
rewritten:

### Source 1 — `specs/003-seed-distribution/spec.md`, FR-006 known limitation

The current text (from `git show origin/003-seed-distribution`):

```text
**Known limitation (tracked under
[issue #15](https://github.com/lambdasistemi/cardano-testnet-baker/issues/15)):**
the in-gate determinism check currently runs against
`local-fast` only. The `normal` scenario triggers an upstream
`db-synthesizer` non-determinism (different volatile-block count
per run at 300,000 slots) that lives outside Feature 003's
surface; widening the gate to `normal` is a one-line edit in
`nix/checks.nix` once the upstream issue is resolved. `normal`
is still published every push — the seed payload is functionally
usable as a node warmup — but its byte-identical-rebuild
property is not asserted by CI yet.
```

**Action**: Delete the entire "Known limitation" block. FR-006 reads
without it once `normal` is in-gate.

### Source 2 — `specs/003-seed-distribution/spec.md`, SC-002

The current text references issue #15:

```text
Per the FR-006 known limitation, the gate currently runs against
`local-fast` only; `normal` is shipped without the byte-identical
assertion until
[issue #15](https://github.com/lambdasistemi/cardano-testnet-baker/issues/15)
is resolved.
```

**Action**: Delete the trailing "Per the FR-006 known limitation..."
sentence. SC-002 then reads as a plain statement that the gate covers
all in-tree scenarios.

### Source 3 — `specs/003-seed-distribution/contracts/publish-pipeline.md`

The "Determinism check" section currently introduces the gate. After
PR #12 lands, search this file for any mention of `local-fast`-only
narrowing or "issue #15" deferrals and apply the same removal.

**Action**: If the file contains a narrowing paragraph parallel to
the spec.md FR-006 limitation block, delete it. Otherwise no edit is
required in this contract.

### Source 4 — `nix/checks.nix` comment block

The narrowing in PR #12 includes an inline comment block in
`nix/checks.nix` referencing issue #15:

```nix
# Scenarios `seed-image-determinism` runs against. The intent is
# to cover *every* committed scenario, but we narrow it
# explicitly here while issue
# <https://github.com/lambdasistemi/cardano-testnet-baker/issues/15>
# tracks an upstream `db-synthesizer` non-determinism that
# surfaces only at the slot count `normal` uses (300,000) — the
# synthesizer emits a different number of `chain-db/volatile/`
# blocks between independent runs of the same input. The seed
# is still functionally usable (cardano-node treats the volatile
# set as transient), so the publish flow continues to ship
# `normal`; the gate just doesn't assert byte-identical rebuilds
# for it until #15 is resolved. Once it is, restore this list to
# `scenarioFiles` and delete this comment.
```

**Action**: Delete the entire comment block when the narrowing is
removed. The widening commit (slice 3 in `plan.md`) executes both
edits together so the file is internally consistent at every commit.

## Acceptance

The narrowing rewrite is complete when:

- `git grep '#15\|issue 15\|local-fast.*only\|local-fast-only'` inside
  `specs/003-seed-distribution/` and `nix/checks.nix` returns no
  matches that refer to the determinism narrowing. (Other unrelated
  references to the issue, if any, may remain.)
- `git grep 'determinismScenarioFiles'` in `nix/checks.nix` shows
  `scenarioFiles` directly assigned, with no filter wrapping.

## Out-of-Scope

- Touching any other 003 spec or contract paragraph that does not
  reference the narrowing. This feature does not own the rest of the
  003 specification.
- Adding a "what changed and why" history paragraph to the 003 spec.
  The git commit message is the durable history record;
  `specs/003-...` files are kept living, not append-only.
