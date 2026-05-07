# Scenario Schema Contract

Published schema path:

```text
schemas/scenario/v1.schema.json
```

Committed examples:

```text
examples/scenarios/local-fast.json
examples/scenarios/normal.json
```

Schema requirements:
- Draft version is declared in `$schema`.
- `$id` is stable and includes the schema major version.
- `additionalProperties: false` is used for closed MVP objects unless a field is
  explicitly designed as metadata.
- Required root keys include `schemaVersion`, `scenarioId`, `seed`, `network`,
  `eraSchedule`, `genesis`, `pools`, and `faucets`.
- Unsupported future features such as ChainDB synthesis are not accepted by the
  v1 schema.

CI requirements:
- Validate both committed examples against `schemas/scenario/v1.schema.json`.
- Use `check-jsonschema` from the Nix shell/check environment for structural
  schema validation.
- Run semantic validation through the baker CLI after structural schema validation.
- Fail on schema drift between examples, parser expectations, and published
  contract.
