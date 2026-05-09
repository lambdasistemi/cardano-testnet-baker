## approved

Final reviewer audit for PR
[#12](https://github.com/lambdasistemi/cardano-testnet-baker/pull/12)
on tip
[`f6474b3`](https://github.com/lambdasistemi/cardano-testnet-baker/commit/f6474b3)
(post-finalization the tip becomes the amended `_reviews` commit).

### Stack audit

Base = `75836dca` (`chore: add PR gate` on `main`). Stack from base
to tip is 16 non-`_reviews` commits + the `_reviews` meta commit.

- Spec / plan / tasks (4 commits, docs-only):
  [832deb6](https://github.com/lambdasistemi/cardano-testnet-baker/commit/832deb63862d6df1c79f502a7ee5415e06f662af),
  [566bffa](https://github.com/lambdasistemi/cardano-testnet-baker/commit/566bffa1f5318a20532a5af56820b6a07c024e50),
  [d9f982f](https://github.com/lambdasistemi/cardano-testnet-baker/commit/d9f982fa5715a68b6934cec7d4fe5a0374ae5309),
  [c8e2c33](https://github.com/lambdasistemi/cardano-testnet-baker/commit/c8e2c333f9f2724b2e3c549ed74c5011e9087e35).
  Reviewed retroactively in `plan-review.md` and `tasks-review.md`;
  c8e2c33 is itself the audit trail for three review-surfaced
  inconsistencies caught before any code landed.
- Implementation (8 task commits): all eight have `<sha>.md` files
  with `## approved` (T001..T008).
- Bug-fix rounds (4 commits) on top of the task set: all four have
  `<sha>.md` files with `## approved`. The two fix rounds whose
  approvals were written during this finalization audit are
  [a9dd69a](https://github.com/lambdasistemi/cardano-testnet-baker/commit/a9dd69ad4a1e1040c3e806084277681b4ee7d575)
  and
  [10e8b74](https://github.com/lambdasistemi/cardano-testnet-baker/commit/10e8b74f06fa70c9fecabda5caca62d3a9e52812).
- Commit-message gate: every commit subject is Conventional Commits
  compliant; every commit body is non-empty; no WIP/draft/tmp/fixup/
  squash subjects remain.

### Resolved blocker history

The earlier finalization attempt (now superseded by this verdict)
blocked on
[run 25581132964](https://github.com/lambdasistemi/cardano-testnet-baker/actions/runs/25581132964/job/75100087121),
which failed `seed-image-determinism` for the `normal` scenario. The
upstream `db-synthesizer` non-determinism behind that failure is
filed as
[issue #15](https://github.com/lambdasistemi/cardano-testnet-baker/issues/15)
and the in-PR gate was deliberately narrowed to `local-fast` while
that issue is open (see
[a9dd69a](https://github.com/lambdasistemi/cardano-testnet-baker/commit/a9dd69ad4a1e1040c3e806084277681b4ee7d575),
spec FR-006 / SC-002, contracts/publish-pipeline.md). The narrowing
is a one-line change in `nix/checks.nix` reversible when #15 lands.

The follow-up bug chain
([b4672c3](https://github.com/lambdasistemi/cardano-testnet-baker/commit/b4672c36a98b25cfc12112eb47a7bce91cfabc9a),
[a9dd69a](https://github.com/lambdasistemi/cardano-testnet-baker/commit/a9dd69ad4a1e1040c3e806084277681b4ee7d575),
[10e8b74](https://github.com/lambdasistemi/cardano-testnet-baker/commit/10e8b74f06fa70c9fecabda5caca62d3a9e52812),
[649deb4](https://github.com/lambdasistemi/cardano-testnet-baker/commit/649deb470ad82c70814182baa3d19e739867c0ed))
landed each runtime issue (per-file determinism diagnostic, gate
narrowing, `0600` skey perms, skopeo trust policy) as a separate
vertical commit on top of the stack rather than amending the buried
T002/T003/T006 originals.

### CI evidence

Run
[25597265936](https://github.com/lambdasistemi/cardano-testnet-baker/actions/runs/25597265936)
on the post-T006-FIX tip is fully green across all 9 jobs:

- Action runtimes
- Build Gate (`seed-image-determinism` for `local-fast`,
  `bake-determinism`, scenario derivations)
- Scenario schema
- Compose acceptance (against the seed image archive, both
  `local-fast` and `normal`)
- Unit tests
- Bake determinism
- HLint
- Formatting
- Publish seed images

### Locked-decision check

- Single seed-only OCI image at
  `ghcr.io/lambdasistemi/cardano-testnet-seed`, scratch base. ✓
- Tagging: primary `<scenario>-<scenarioDigest>` (from
  `metadata.json.inputDigest`), secondary
  `<scenario>-sha-<bakerCommitSha7>`; no moving tags. ✓
- Both committed scenarios published every push. ✓
- Compose acceptance against the seed extracted from the image
  about to be published. ✓
- Determinism rebuild + manifest digest comparison (narrowed to
  `local-fast` pending #15). ✓
- v1 unsigned; cosign keyless deferred to
  [#14](https://github.com/lambdasistemi/cardano-testnet-baker/issues/14). ✓
- Retain all per-commit images forever; no active pruning. ✓
- linux/amd64 only. ✓

### Approval action

PR metadata refreshed via `gh pr edit` (body now reflects the final
merged state — locked decisions, scope-out list, follow-ups #14 and
#15). Draft flag cleared via `gh pr ready 12`.

`gh pr review --approve` attempted on
2026-05-09T09:11Z and refused by GitHub:

```text
failed to create review: GraphQL: Review Can not approve your own
pull request (addPullRequestReview)
```

The PR was authored by `paolino` and the reviewer GH session is
also `paolino`, so GitHub rejects self-approval at the API layer.
Per the canonical pull-request skill, finalization does not write
`Done` when the approval call fails; the state stays
`WaitingForFinalization` with this blocker named. The PR is
ready-for-review and out of draft, so a different GH account can
approve when one is available.

State is therefore `WaitingForFinalization` with the only remaining
gate being `gh pr review --approve` from a non-author GitHub
identity. No further code, plan, or task work is outstanding.
