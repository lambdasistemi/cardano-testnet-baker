## approved

Retroactive plan-review verdict for PR
[#12](https://github.com/lambdasistemi/cardano-testnet-baker/pull/12),
covering commit
[566bffa](https://github.com/lambdasistemi/cardano-testnet-baker/commit/566bffa1f5318a20532a5af56820b6a07c024e50)
("docs: plan seed distribution feature") and the plan-side fixes
folded into commit
[c8e2c33](https://github.com/lambdasistemi/cardano-testnet-baker/commit/c8e2c333f9f2724b2e3c549ed74c5011e9087e35)
("docs(003): fix three review-surfaced inconsistencies").

The earlier reviewer-driven c8e2c33 commit is itself the audit trail:
three plan/research/contract issues (synthesis-report determinism,
metadata field name, streamLayeredImage-vs-buildLayeredImage) were
caught by review and folded back into the plan, contracts, and
research artifacts before any implementation commit landed.

The present plan satisfies the gate:

- Connects back to the accepted spec (FR-001..FR-013, SC-001..SC-005;
  primary tag `<scenario>-<scenarioDigest>`, secondary
  `<scenario>-sha-<bakerCommitSha7>`).
- Names the main design decisions: `pkgs.dockerTools.buildLayeredImage`
  (a switch from the original `streamLayeredImage` after review),
  skopeo over docker for push, nixos runner, no Haskell change,
  github.token over PAT, all-or-nothing partial-publish semantics. All
  recorded in
  [`research.md`](https://github.com/lambdasistemi/cardano-testnet-baker/blob/003-seed-distribution/specs/003-seed-distribution/research.md).
- Identifies risks and migration concerns: the `synthesis-report.json`
  determinism projection (§8 of research, FR-002/FR-012), the
  `metadata.json.inputDigest` vs `scenarioDigest` field-name reality
  (§4 of research, FR-003), and the v1-unsigned posture with cosign
  deferred to follow-up (FR-013, eventually issue
  [#14](https://github.com/lambdasistemi/cardano-testnet-baker/issues/14)).
- Defines proof per behaviour change: each FR maps to a CI gate
  (Build Gate determinism, Compose acceptance, Publish seed images),
  with the determinism check itself listed as the proof for the
  byte-identical-rebuild claim.
- Groups work into vertical commit slices (T001..T009) that match
  one-PR-commit-per-task and were reviewable one at a time.
- Makes TDD/DDD possible per slice: each task names the validation
  command (`nix run`, `nix flake check`, `bash compose/acceptance/run.sh`,
  `gh issue view`) and the contract section it honours instead of
  inventing parallel docs.
- States how manual / live smoke checks are represented: the publish
  flow is gated on Build Gate before fanning out, and Compose
  acceptance against the about-to-be-published image (§VI) is the
  manual-equivalent gate, run automatically in CI.

Implementation evidence on tip
[`f6474b3`](https://github.com/lambdasistemi/cardano-testnet-baker/commit/f6474b3):
all 9 CI jobs green on run
[25597265936](https://github.com/lambdasistemi/cardano-testnet-baker/actions/runs/25597265936),
including the publish, determinism, and compose-acceptance gates the
plan named.

Retroactive note: this file was written during the finalization audit
to close the plan-review gap that the in-flight review loop had filled
informally through c8e2c33 rather than as a separate file.
