---
sha: d16b52648b9ffd8dc7952eec4f4fe3fc9a5add0b
patch: wip-t002-enforce-seed-image
task: T002
---

## ready

Round 8 of T002 — addresses the round-7 verdict on `c784ea4`.

The reviewer correctly flagged two more spec passages that
still claimed manifest-digest equality after the round-7
reframing:

1. `spec.md` SC-002 said the build gate verified unchanged
   scenarios by comparing artifact manifest digests across
   rebuilds — directly contradicting the new FR-006 wording
   and the in-gate oracle.
2. `tasks.md` Phase 5 (US3) said US3 was "structurally
   satisfied by Phase 2" via T002 alone. That overstated T002:
   T002 establishes the in-gate determinism oracle, but the
   manifest-digest equality the offline-reviewer test depends
   on comes from T006 (the CI publish job materialising a
   single deterministic manifest) plus T007 (the documented
   reproduction walkthrough), not from T002 alone.

### What changed

- **`spec.md` SC-002**: rewritten to name the actual in-gate
  oracle ("deterministic seed payload and stable image-config
  fields"). Adds a closing clause noting that two consecutive
  CI pushes still produce the same registry manifest digest as
  the production-side property, but that this is established
  by the determinism of the build closure rather than directly
  compared by the in-gate check. Cross-references FR-006 and
  the publish-pipeline contract.
- **`tasks.md` Phase 5 (US3)**: rewritten to spell out that
  US3 is satisfied by the *combination* of T002 (in-gate
  oracle), T006 (CI publish materialising the registry
  manifest), and T007 (offline-reproduction walkthrough). T002
  alone is no longer overstated as satisfying US3's
  manifest-digest claim.

### Implementation

Unchanged from round 7. CI behaviour is identical; only spec
docs change.

### Commit message

Title and body unchanged — the round-6 dictated text already
named the property the gate actually enforces.

## approved

The determinism gate now uses two independent image builds, compares the seed payload and stable config fields it can actually prove, and the spec/tasks no longer overstate that T002 compares manifest digests.
