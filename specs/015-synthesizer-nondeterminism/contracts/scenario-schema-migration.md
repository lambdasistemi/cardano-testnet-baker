# Contract: Scenario Schema Migration (conditional)

**Feature**: [../spec.md](../spec.md)
**Plan**: [../plan.md](../plan.md)

This contract is **conditional**. It applies only if Phase 0 research
ends with R-001 -> path (a) **and** the chosen scenario-side knob is a
*new* `synthesis.*` field (not an existing-field value adjustment).

If R-001 -> path (a) and only an existing field's value changes (most
likely `synthesis.slotCount`), this contract is **not** triggered: no
schema bump, no migration note, no consumer-visible contract break.
The published JSON Schema stays at v1.

If R-001 -> path (c), this contract is **not** triggered either: the
fix lives entirely in the pinned upstream commit, and no scenario-side
field changes.

## When this contract triggers

Trigger condition (all of):

1. R-001 chose path (a).
2. R-002's bisect did not stop the drift via any *existing* field's
   value range. It identified a new control surface (for example, a
   parallelism cap) that has to live as a new scenario-level
   parameter so that downstream consumers can re-derive it.
3. The `Scenario` entity therefore needs a new `synthesis.*` field.

## Contract shape (when triggered)

When triggered, this feature produces:

1. A new schema file `schemas/scenario/v2.schema.json`. The v2 file is
   v1 plus the new field, with `$id` and any `version` field bumped
   accordingly.
2. A migration note inside the new schema (or alongside it as
   `schemas/scenario/MIGRATION-v1-to-v2.md`) that:
   - Names the new field, its type, its default, and its semantics
     (in particular, what aspect of `db-synthesizer` it constrains).
   - States explicitly that any existing v1 scenario JSON document
     remains valid after upgrading to a v2-aware baker, modulo the
     new field's documented default.
   - States that the deterministic seed bytes for `normal` change
     between the pre-fix and post-fix baker SHAs (constitution
     Principle III, spec Assumption 2).
3. The `nix/checks.nix:scenario-schema` check is updated to reference
   `v2.schema.json`.
4. `examples/scenarios/normal.json` is updated with the new field set
   to whatever value R-002's bisect picked.
5. `examples/scenarios/local-fast.json` is updated only if the new
   field has no safe default; otherwise the default carries
   `local-fast` through unchanged.
6. The CLI `bake` path validates v2 input and rejects unknown fields
   (existing behavior of the existing validator, no new code).

## Backwards compatibility

If the new field has a safe default that matches today's `local-fast`
behavior, v1 documents continue to validate against v2 (additive
schema change). If the new field is required, v1 documents break and
the migration note must call out a one-line edit.

The plan prefers an additive change.

## Out-of-Scope

- Branching the schema to support both v1 and v2 long-term.
  Rejected: the project is pre-1.0 (constitution v1.1.0, no external
  schema consumers yet beyond this repo). One schema version on
  `main` at a time.
- Publishing the v2 schema to a separate distribution channel.
  Rejected: same channel as v1 (`schemas/scenario/`).
