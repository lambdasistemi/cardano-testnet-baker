# Quickstart: Scenario Bake CLI MVP

## Enter The Shell

```sh
nix develop
```

## Validate Example Scenarios

```sh
check-jsonschema \
  --schemafile schemas/scenario/v1.schema.json \
  examples/scenarios/local-fast.json \
  examples/scenarios/normal.json

cardano-testnet-baker scenario validate examples/scenarios/local-fast.json
cardano-testnet-baker scenario validate examples/scenarios/normal.json
```

## Bake A Scenario

```sh
rm -rf out/local-fast-a out/local-fast-b

cardano-testnet-baker bake \
  --scenario examples/scenarios/local-fast.json \
  --out out/local-fast-a
```

Expected top-level output:

```text
out/local-fast-a/
├── genesis/
├── pools/
├── utxo-keys/
└── metadata.json
```

## Check Determinism

```sh
cardano-testnet-baker bake \
  --scenario examples/scenarios/local-fast.json \
  --out out/local-fast-b

diff -ru out/local-fast-a out/local-fast-b
```

The diff must be empty.

## Run Compose Acceptance

```sh
compose/acceptance/run.sh local-fast out/local-fast-a
```

The harness patches start times in a temporary runtime copy and starts the node
cluster from the generated assets. It must fail on genesis, config, key, or
startup validation errors.

## Full Local Gate

```sh
nix develop --quiet -c just CI
```

Feature 001 extends this gate with schema validation, two-run determinism, and
compose acceptance for `local-fast` and `normal`.
