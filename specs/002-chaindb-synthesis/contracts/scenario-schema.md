# Contract: Scenario Schema Synthesis Extension

## Location

```text
schemas/scenario/v1.schema.json
```

## Optional Root Field

```json
{
  "synthesis": {
    "enabled": true,
    "slotCount": 720,
    "profile": "local-fast-ci"
  }
}
```

## Rules

- `synthesis` is optional.
- If `synthesis` is absent, synthesis is disabled.
- If `synthesis.enabled` is `false`, no ChainDB seed is produced.
- If `synthesis.enabled` is `true`, `slotCount` is required.
- `slotCount` must be a positive integer.
- `profile` is optional and must be a non-empty string when present.
- Unknown keys under `synthesis` are rejected.
- Schema validation and semantic validation must agree on these rules.

## Committed Examples

- `local-fast` should become the routine synthesis acceptance scenario.
- `normal` should provide the realistic-epoch measurement path before storage
  strategy decisions.
