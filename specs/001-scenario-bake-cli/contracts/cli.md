# CLI Contract

## `cardano-testnet-baker scenario validate`

Run baker semantic validation before baking. Structural JSON Schema validation
is a separate CI/public-contract check.

```text
cardano-testnet-baker scenario validate examples/scenarios/local-fast.json
```

Exit codes:
- `0`: scenario passes semantic validation.
- `1`: validation failed; stderr names the field or invariant.
- `2`: command usage error.

## `cardano-testnet-baker bake`

Bake deterministic assets from one scenario.

```text
cardano-testnet-baker bake \
  --scenario examples/scenarios/local-fast.json \
  --out ./out/local-fast
```

Rules:
- `--scenario` is required.
- `--out` is required and must not already contain files.
- The command writes `genesis/`, `pools/`, `utxo-keys/`, and `metadata.json`.
- The command does not patch a run-specific `systemStart`.
- Invalid or unsupported scenarios fail without publishing a completed-looking
  partial output.
