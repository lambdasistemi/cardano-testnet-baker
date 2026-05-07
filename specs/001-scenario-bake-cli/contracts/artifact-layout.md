# Artifact Layout Contract

Given:

```text
cardano-testnet-baker bake --scenario scenario.json --out <output-dir>
```

The published output must have this top-level shape:

```text
<output-dir>/
├── genesis/
├── pools/
├── utxo-keys/
└── metadata.json
```

Required genesis files:

```text
genesis/byron-genesis.json
genesis/shelley-genesis.json
genesis/alonzo-genesis.json
genesis/conway-genesis.json
genesis/config.json
```

Required pool files for each pool label:

```text
pools/<pool-label>/keys/cold.skey
pools/<pool-label>/keys/cold.vkey
pools/<pool-label>/keys/kes.skey
pools/<pool-label>/keys/vrf.skey
pools/<pool-label>/keys/opcert.cert
pools/<pool-label>/keys/stake.skey
pools/<pool-label>/keys/stake.vkey
```

Required faucet files for each faucet label:

```text
utxo-keys/<faucet-label>.skey
utxo-keys/<faucet-label>.addr.info
```

Determinism rules:
- Relative paths are stable.
- JSON files use deterministic key ordering and formatting.
- Metadata records artifact digests over canonical bytes.
- No run-time clock value appears in deterministic artifacts.
