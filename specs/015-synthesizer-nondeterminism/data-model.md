# Data Model: Determinize `normal` Scenario db-synthesizer Output

This feature is mostly subtractive: it removes a CI gate narrowing and
optionally adjusts a single scenario-level input. Most entities of
interest are inherited from Features 002 and 003, not introduced here.

The data-model deltas below describe **what may change** about each
existing entity, with the conditional that closes the change. The
conditionals fall out of `research.md` R-001 and R-002.

## Existing Entities (inherited)

### Scenario

Inherited from Feature 001 / 002. JSON document under
`examples/scenarios/`. Schema at `schemas/scenario/v1.schema.json`.

**Possible delta in this feature**:

- An *existing* `synthesis.*` field's value on
  `examples/scenarios/normal.json` may change (most likely
  `synthesis.slotCount`). No schema effect.
- A *new* `synthesis.*` field may be added to bound the drift mechanism
  (for example, an explicit `synthesis.parallelism` if R-003 names a
  parallel scheduler). In that case the schema bumps to
  `schemas/scenario/v2.schema.json`, with a migration note
  ([contracts/scenario-schema-migration.md](./contracts/scenario-schema-migration.md)).

The `local-fast.json` and `normal.json` fields not under
`synthesis.*` are out of scope for this feature.

### Synthesized ChainDB Seed

Inherited from Feature 002. Immutable seed artifact under
`seed/chain-db/{immutable,ledger,volatile}/`.

**Delta in this feature**:

- The deterministic byte content for `normal` *will* change between the
  pre-fix baker SHA and the post-fix baker SHA. This is expected per
  spec Assumption 2 and constitution Principle III: consumers pin the
  baker SHA, not a moving tag, so a byte change between SHAs is
  acceptable.
- After the fix, two independent builds at the post-fix baker SHA must
  produce byte-identical `seed/chain-db/` contents (FR-001).

No file layout change. No new files under `seed/`.

### Synthesis Report

Inherited from Feature 002. JSON document `seed/synthesis-report.json`
with two top-level halves: deterministic artifact-fact fields and a
host-dependent `observation.*` block.

**Delta in this feature**:

- The deterministic half (`scenarioId`, `scenarioDigest`,
  `bakerVersion`, `slotCount`, `profile`, `chainDb.bytes`,
  `chainDb.fileCount`, `chainDb.packagedBytes`) becomes byte-identical
  across two independent runs of the `normal` scenario at the
  post-fix baker SHA (FR-002).
- If R-001 -> path (a) changes `synthesis.slotCount` for `normal`,
  then `synthesis.slotCount` in this report changes accordingly. The
  *shape* of the report does not change; only the values do.

### Determinism Gate

Inherited from Feature 003 (`nix/checks.nix:seed-image-determinism`,
introduced by PR #12 commit `d16b526`).

**Delta in this feature**:

- The in-scope scenario list expands from
  `builtins.filter (f: f == "local-fast.json") scenarioFiles` to
  `scenarioFiles` (FR-003).
- The pair-build mechanism, the `mkSeedImagePair` helper, and the
  per-file diagnostic loop are all unchanged (spec Assumption 4).

### Drift Cause Note (new)

This feature introduces one new durable record entity: the
**Drift Cause Note**, owned by `research.md`. It carries:

- The named divergence mechanism (R-003).
- The smallest reproducer envelope (R-002).
- The chosen FR-006 fix path (R-001).

It is text in `research.md`, not a code or data artifact. It is the
durable carrier the spec (User Story 2, FR-005, SC-003) requires the
PR to leave behind.

## State Transitions

There are no in-process state machines in this feature. The relevant
"state" is the lifecycle of the determinism gate's scope, which goes
through exactly one transition over this PR:

```text
local-fast-only (PR #12 narrowing)
    -> full scenarioFiles (this feature, slice 3)
```

That single transition is the SC-004 success criterion.

## Validation Rules

All inherited from Features 001/002/003:

- The scenario JSON must validate against the published JSON Schema
  (existing `nix/checks.nix:scenario-schema` check).
- The synthesis report's deterministic half must be byte-identical
  across runs (existing `nix/checks.nix:example-bake-determinism` for
  `local-fast`; this feature implicitly extends that property to
  `normal` via the determinism gate).
- The seed must pass Compose acceptance (existing
  `compose/acceptance/run.sh`).

This feature adds no new validation rules.

## Public Contracts

See `contracts/`:

- [`determinism-harness.md`](./contracts/determinism-harness.md) —
  always applies.
- [`scenario-schema-migration.md`](./contracts/scenario-schema-migration.md) —
  applies only if R-001 -> path (a) and a *new* scenario field is
  introduced.
- [`narrowing-rewrite.md`](./contracts/narrowing-rewrite.md) — always
  applies.
