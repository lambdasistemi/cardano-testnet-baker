# Quickstart: ChainDB Seed Synthesis Measurement MVP

Tracking issue: [#8 ChainDB seed synthesis measurement MVP](https://github.com/lambdasistemi/cardano-testnet-baker/issues/8).

## 1. Validate Scenarios

```bash
just validate-scenarios
cardano-testnet-baker scenario validate examples/scenarios/local-fast.json
cardano-testnet-baker scenario validate examples/scenarios/normal.json
```

## 2. Bake A Synthesis-Enabled Scenario

```bash
rm -rf tmp/synthesis/local-fast
cardano-testnet-baker bake \
  --scenario examples/scenarios/local-fast.json \
  --out tmp/synthesis/local-fast
```

Expected output includes:

```text
tmp/synthesis/local-fast/
├── chain-db/
├── genesis/
├── metadata.json
├── pools/
├── synthesis-report.json
└── utxo-keys/
```

## 3. Measure The Realistic Scenario

```bash
rm -rf tmp/synthesis/normal
cardano-testnet-baker bake \
  --scenario examples/scenarios/normal.json \
  --out tmp/synthesis/normal
jq . tmp/synthesis/normal/synthesis-report.json
```

Use the report to inspect on-disk ChainDB size, packaged-size proxy, file
count, and synthesis wall time.

## 4. Run Compose Seed Acceptance

```bash
compose/acceptance/run.sh local-fast tmp/synthesis/local-fast
```

The run must print `verdict=accepted` only after the node accepts the copied
seed, genesis, config, and key material.

## 5. Determinism Check

```bash
rm -rf tmp/synthesis/a tmp/synthesis/b
cardano-testnet-baker bake \
  --scenario examples/scenarios/local-fast.json \
  --out tmp/synthesis/a
cardano-testnet-baker bake \
  --scenario examples/scenarios/local-fast.json \
  --out tmp/synthesis/b
diff -ru \
  --exclude synthesis-report.json \
  tmp/synthesis/a \
  tmp/synthesis/b
```

The ChainDB seed and deterministic metadata must match. Timing observations in
`synthesis-report.json` are intentionally host-dependent.
