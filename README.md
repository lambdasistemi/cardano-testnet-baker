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
schema and two committed examples:

- `schemas/scenario/v1.schema.json`
- `examples/scenarios/local-fast.json`
- `examples/scenarios/normal.json`

The `scenario validate` command validates scenario JSON semantically. The
`bake` command and node acceptance harness are introduced in later Feature 001
slices; see the `specs/` tree for the task breakdown.

## Scenario Validation

Validate every committed example against the published JSON Schema:

```sh
just validate-scenarios
```

Validate a scenario with the CLI semantic checks:

```sh
nix run . -- scenario validate examples/scenarios/local-fast.json
```

## Development

```sh
nix develop          # cabal, GHC 9.12.3, fourmolu, hlint, hls
just --list          # available recipes
just CI              # mirrors the GitHub CI pipeline
```

## License

Apache-2.0. See [LICENSE](./LICENSE).
