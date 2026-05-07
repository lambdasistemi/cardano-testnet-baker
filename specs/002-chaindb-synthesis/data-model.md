# Data Model: ChainDB Seed Synthesis Measurement MVP

## Scenario Synthesis Request

Optional section in the scenario JSON.

- `enabled`: boolean that opts a scenario into ChainDB seed synthesis.
- `slotCount`: positive integer number of slots to synthesize.
- `profile`: optional human-readable label used for reports and examples.

Validation rules:

- If absent, synthesis is disabled and genesis/key baking behaves as Feature
  001 specified.
- If present with `enabled=true`, `slotCount` is required and must be positive.
- Unknown keys are rejected.
- Every field that changes seed output must live in this object or another
  existing scenario field.

## Synthesis Request

Internal validated value derived from the scenario plus bake output paths.

- Scenario identity and input digest.
- Node config path.
- Pool credential artifact paths.
- Requested slot count.
- Output ChainDB seed path.

State transitions:

1. `NotRequested`
2. `Requested`
3. `Running`
4. `Completed`
5. `Failed`

## Synthesized ChainDB Seed

Immutable generated artifact directory.

```text
chain-db/
├── immutable/
├── ledger/
└── volatile/
```

Validation rules:

- Directory is produced only when synthesis is requested.
- Directory is generated in a staging location and published atomically with
  the rest of the bake output.
- The seed is treated as immutable source material after bake completion.

## Bulk Credentials

Deterministic intermediate JSON file prepared from generated pool artifacts.

- One entry per selected producer.
- Each entry contains the operational certificate, VRF signing key, and KES
  signing key needed by the synthesizer.

Validation rules:

- Credentials come from generated artifacts for the same scenario.
- Missing or mismatched pool artifacts fail synthesis before publishing a
  completed-looking output.

## Synthesis Measurement Report

Machine-readable report emitted beside deterministic metadata.

- `scenarioId`
- `scenarioDigest`
- `bakerVersion`
- `slotCount`
- `chainDbPath`
- `chainDbBytes`
- `chainDbFileCount`
- `packagedBytes`
- `wallTimeMilliseconds`
- `startedAt`
- `completedAt`
- `host`

Validation rules:

- Size and file-count fields describe the completed generated seed.
- Timing and host fields are host-dependent observations and are not part of
  deterministic artifact equality.

## Seed Acceptance Run

Compose validation that proves a node accepts the generated seed.

- Scenario name.
- Generated output path.
- Runtime copy path.
- Node image identity.
- Verdict.
- Log path.

Validation rules:

- Acceptance copies the generated seed into writable runtime storage.
- The generated output remains unchanged by the node.
- A startup, genesis, key, config, or ChainDB validation error fails the run.
