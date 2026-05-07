# Contract: CLI Synthesis Behavior

## Existing Command

```text
cardano-testnet-baker bake --scenario scenario.json --out <output-dir>
```

## Behavior

- If the scenario does not request synthesis, output matches the Feature 001
  genesis/key artifact contract.
- If the scenario requests synthesis, the same bake command also produces a
  ChainDB seed and synthesis measurement report.
- Invalid synthesis requests fail with a non-zero exit code before publishing
  a completed-looking output directory.

## Exit Semantics

- `0`: bake completed and every requested artifact was published.
- non-zero: decode, validation, genesis/key bake, synthesis, measurement, or
  publish step failed.

## Diagnostics

Failures must identify whether the problem is:

- scenario schema or semantic validation,
- missing generated pool credentials,
- synthesizer execution failure,
- measurement failure, or
- output publication failure.
