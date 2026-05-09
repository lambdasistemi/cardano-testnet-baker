## approved

Retroactive tasks-review verdict for PR
[#12](https://github.com/lambdasistemi/cardano-testnet-baker/pull/12),
covering commit
[d9f982f](https://github.com/lambdasistemi/cardano-testnet-baker/commit/d9f982fa5715a68b6934cec7d4fe5a0374ae5309)
("docs: break seed distribution feature into vertical tasks") and
the tasks-side fixes folded into commit
[c8e2c33](https://github.com/lambdasistemi/cardano-testnet-baker/commit/c8e2c333f9f2724b2e3c549ed74c5011e9087e35)
("docs(003): fix three review-surfaced inconsistencies").

The task set in
[`tasks.md`](https://github.com/lambdasistemi/cardano-testnet-baker/blob/003-seed-distribution/specs/003-seed-distribution/tasks.md)
satisfies the gate:

- Maps to the approved plan and to acceptance criteria (FR-001..
  FR-013, SC-001..SC-005). Each task references the contract
  section it honours rather than duplicating spec text.
- Grouped into vertical reviewable slices T001..T009. T001 builds
  the seed-image flake outputs, T002 enforces determinism in the
  Build Gate, T003 wires Compose acceptance to the seed image, T004
  consumes the archive form, T005 adds the publishSeedImages app
  and just recipe, T006 publishes images on push, T007 documents
  consumer wiring, T008 files the cosign follow-up
  ([#14](https://github.com/lambdasistemi/cardano-testnet-baker/issues/14)),
  T009 is reviewer-owned PR finalisation.
- RED/proof per behaviour change is named on each task (the gate
  re-runs the publish flow for T002, archive-mode acceptance for
  T003/T004, the in-image manifest digest for T005/T006).
- GREEN implementation per task is one bisect-safe commit; each
  task explicitly states "lands as one commit on top of the
  stack" and names its validation command.
- Each future commit was kept bisect-safe — confirmed in the actual
  history: every base-stack commit
  ([03855bb](https://github.com/lambdasistemi/cardano-testnet-baker/commit/03855bb6e952c09250e1b5d90b7c8a82bd7272c7),
  [d16b526](https://github.com/lambdasistemi/cardano-testnet-baker/commit/d16b52648b9ffd8dc7952eec4f4fe3fc9a5add0b),
  [1bd0b8a](https://github.com/lambdasistemi/cardano-testnet-baker/commit/1bd0b8a32b43162abbacf340bb30b1bdcfb9f85a),
  [4fe0a7b](https://github.com/lambdasistemi/cardano-testnet-baker/commit/4fe0a7b6e019cf36c1ee3a7b56b8713dbb1343e5),
  [c97f826](https://github.com/lambdasistemi/cardano-testnet-baker/commit/c97f8265234f3ce01dca9b8545859df0ec0e532d),
  [21ee706](https://github.com/lambdasistemi/cardano-testnet-baker/commit/21ee706a36e32f02692561cbabcc8953c3b71f95),
  [54f2564](https://github.com/lambdasistemi/cardano-testnet-baker/commit/54f25644bbf5b64edb7a32657152b38d4bc42a0a),
  [c6a8b3a](https://github.com/lambdasistemi/cardano-testnet-baker/commit/c6a8b3a4145ca57b9cf15158ddab53ce8e6bd07d))
  has a per-sha review file with `## approved`.
- Non-code tasks (T008, T009) are marked as docs/metadata work, not
  behaviour changes.
- Determinism follow-up: the four fix-rounds
  ([b4672c3](https://github.com/lambdasistemi/cardano-testnet-baker/commit/b4672c36a98b25cfc12112eb47a7bce91cfabc9a),
  [a9dd69a](https://github.com/lambdasistemi/cardano-testnet-baker/commit/a9dd69ad4a1e1040c3e806084277681b4ee7d575),
  [10e8b74](https://github.com/lambdasistemi/cardano-testnet-baker/commit/10e8b74f06fa70c9fecabda5caca62d3a9e52812),
  [649deb4](https://github.com/lambdasistemi/cardano-testnet-baker/commit/649deb470ad82c70814182baa3d19e739867c0ed))
  were not in the original task set; they were CI-surfaced bugs in
  T002/T003/T006 patched as follow-up vertical commits with their
  own per-sha review files (rather than amending T002/T003/T006
  in-place under several already-approved downstream patches). The
  tasks doc itself is unchanged for those rounds; the rationale is
  recorded inside each fix's review file.

Implementation evidence on tip
[`f6474b3`](https://github.com/lambdasistemi/cardano-testnet-baker/commit/f6474b3):
all 9 CI jobs green on run
[25597265936](https://github.com/lambdasistemi/cardano-testnet-baker/actions/runs/25597265936).

Retroactive note: this file was written during the finalization audit
to close the tasks-review gap; the in-flight loop filled it informally
through c8e2c33 and the per-slice review files.
