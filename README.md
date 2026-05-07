# cardano-testnet-baker

Deterministic Cardano testnet artifact baker.

Reads a declarative **scenario JSON** describing the network (initial stake,
producers, faucets, era schedule, optional ChainDB synthesis) and produces a
versioned, reproducible artifact set:

- Genesis files (Byron, Shelley, Alonzo, Conway)
- Pool keys (KES, VRF, cold, operational certificate, stake)
- Faucet (UTxO) keys with matching `initialFunds` entries
- Optional synthesized **ChainDB seed** that already spans the epochs Amaru
  bootstrap snapshots anchor to

Targets:

| Target | How |
|---|---|
| Local CLI | `nix run github:lambdasistemi/cardano-testnet-baker -- scenario validate <scenario.json>` |
| OCI image | published to `ghcr.io/lambdasistemi/cardano-testnet-baker:<sha>` |
| Native binary | DEB / RPM / AppImage / Homebrew tap (forthcoming) |

## Status

Feature 001 is in flight. The repository currently publishes the v1 scenario
schema, two committed examples, deterministic bake output, and a Docker Compose
node acceptance harness:

- `schemas/scenario/v1.schema.json`
- `examples/scenarios/local-fast.json`
- `examples/scenarios/normal.json`

The `scenario validate` command validates scenario JSON semantically. The
`bake` command writes deterministic genesis, pool key, faucet key, and metadata
artifacts. The compose acceptance harness starts a pinned `cardano-node` image
from the generated assets and fails on startup, genesis, config, or key
validation errors.

## Scenario Validation

Validate every committed example against the published JSON Schema:

```sh
just validate-scenarios
```

Validate a scenario with the CLI semantic checks:

```sh
nix run . -- scenario validate examples/scenarios/local-fast.json
```

## Baking

Bake the `local-fast` example:

```sh
just bake-local-fast
```

Bake both committed examples:

```sh
just bake-examples
```

The output directory contains `genesis/`, `pools/`, `utxo-keys/`, and
`metadata.json`. The metadata records deterministic input and artifact digests.

## Determinism

Run the Nix check that bakes both committed examples twice, recursively diffs
the output bytes, and compares file modes:

```sh
nix build .#checks.x86_64-linux.example-bake-determinism
```

## Compose Acceptance

Start a pinned `cardano-node 10.7.1` image from the baked assets:

```sh
just acceptance-local-fast
just acceptance-normal
```

The harness copies baked assets into a temporary runtime directory, patches only
runtime `systemStart` and Byron `startTime`, mounts the runtime assets read-only,
and waits for the node startup acceptance signal.

## Development

```sh
nix develop          # cabal, GHC 9.12.3, fourmolu, hlint, hls
just --list          # available recipes
just CI              # mirrors the GitHub CI pipeline
```

## License

Apache-2.0. See [LICENSE](./LICENSE).
