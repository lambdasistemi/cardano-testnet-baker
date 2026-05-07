# Contract: Synthesis Artifact Layout

## Genesis/Key-Only Scenario

Unchanged from Feature 001:

```text
<output-dir>/
├── genesis/
├── metadata.json
├── pools/
└── utxo-keys/
```

## Synthesis-Enabled Scenario

```text
<output-dir>/
├── chain-db/
│   ├── immutable/
│   ├── ledger/
│   └── volatile/
├── genesis/
├── metadata.json
├── pools/
├── synthesis-report.json
└── utxo-keys/
```

## Determinism Rules

- `chain-db/` is deterministic for the same scenario, baker version, and
  pinned dependencies.
- `metadata.json` remains deterministic.
- `synthesis-report.json` may contain host-dependent timing observations and
  must not be included in byte-for-byte deterministic artifact equality unless
  timing fields are explicitly ignored by the check.

## Publication Rules

- The output directory is published only after all requested artifacts are
  complete.
- A failed synthesis must not leave a completed-looking output directory.
- Acceptance may copy the output but must not mutate it.
