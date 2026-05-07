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
| Local CLI | `nix run github:lambdasistemi/cardano-testnet-baker -- bake scenario.json` |
| OCI image | published to `ghcr.io/lambdasistemi/cardano-testnet-baker:<sha>` |
| Native binary | DEB / RPM / AppImage / Homebrew tap (forthcoming) |

## Status

Scaffolding in flight. The actual baker, scenario schema, and synthesizer
wiring are introduced via Spec-Driven Development; see open PRs and the
`specs/` tree.

## Development

```sh
nix develop          # cabal, GHC 9.6.7, fourmolu, hlint, hls
just --list          # available recipes
just CI              # mirrors the GitHub CI pipeline
```

## License

Apache-2.0. See [LICENSE](./LICENSE).
