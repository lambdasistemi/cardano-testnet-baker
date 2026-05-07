# Contract: Synthesis Measurement Report

## Path

```text
<output-dir>/synthesis-report.json
```

## Shape

```json
{
  "schemaVersion": 1,
  "scenarioId": "normal",
  "scenarioDigest": "hex-encoded-digest",
  "bakerVersion": "version-or-commit",
  "synthesis": {
    "slotCount": 300000,
    "profile": "normal-realistic"
  },
  "chainDb": {
    "path": "chain-db",
    "bytes": 0,
    "fileCount": 0,
    "packagedBytes": 0
  },
  "observation": {
    "wallTimeMilliseconds": 0,
    "startedAt": "2026-05-07T00:00:00Z",
    "completedAt": "2026-05-07T00:00:00Z",
    "host": "runner-or-host-label"
  }
}
```

## Rules

- `scenarioId`, `scenarioDigest`, `bakerVersion`, `synthesis`, and `chainDb`
  identify the generated artifact.
- `observation` fields describe the host run and may differ across machines.
- `bytes`, `fileCount`, and `packagedBytes` are measured after synthesis
  completes.
- `packagedBytes` is a proxy measurement and does not commit the project to a
  final publishing format.
