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

CI also runs the two committed examples through the Nix determinism check:

```sh
nix build .#checks.x86_64-linux.example-bake-determinism
```

## Run Compose Acceptance

```sh
just acceptance-local-fast
just acceptance-normal
```

The harness patches start times in a temporary runtime copy and starts the node
cluster from the generated assets. It must fail on genesis, config, key, or
startup validation errors.

## Full Local Gate

```sh
nix develop --quiet -c just CI
```

Feature 001 extends this gate with schema validation, two-run determinism, and
compose acceptance for freshly baked `local-fast` and `normal` assets.

## PR Verification Evidence

Recorded during PR #5 finalization on 2026-05-07:

```text
nix develop --quiet -c cabal check
  No errors or warnings could be found in the package.

nix build --quiet --impure --option allow-import-from-derivation true --expr '<library haddock derivation>'
  exit 0

nix develop --quiet -c just format
  exit 0

nix develop --quiet -c just CI
  47 examples, 0 failures

  local-fast verdict=accepted
  local-fast logPath=/code/cardano-testnet-baker-issue-2-plan/tmp/acceptance-logs/ctb-local-fast-3669608/cardano-node.log

  normal verdict=accepted
  normal logPath=/code/cardano-testnet-baker-issue-2-plan/tmp/acceptance-logs/ctb-normal-3670145/cardano-node.log
```
