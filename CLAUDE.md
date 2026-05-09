# cardano-testnet-baker Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-05-09

## Active Technologies
- Haskell, GHC 9.12.3 via haskell.nix `ghc9123` + cardano-node 10.7.1-aligned Cardano libraries, stock `db-synthesizer`, `aeson`, `optparse-applicative`, JSON Schema tooling, Docker Compose acceptance image (002-chaindb-synthesis)
- Filesystem artifact directory containing genesis, keys, metadata, optional `chain-db/`, and synthesis measurement report (002-chaindb-synthesis)
- Haskell, GHC 9.12.3 via haskell.nix `ghc9123`. Same (015-synthesizer-nondeterminism)
- No new storage. Same on-disk artifact tree as Feature 002: (015-synthesizer-nondeterminism)

- Haskell, GHC 9.12.3 (`ghc9123`) + haskell.nix, CHaP, iohk-nix crypto overlays, (001-scenario-bake-cli-plan)

## Project Structure

```text
src/
tests/
```

## Commands

```sh
nix develop
just --list
nix develop --quiet -c just CI
```

## Code Style

Haskell, GHC 9.12.3 (`ghc9123`): Follow the project Fourmolu, HLint,
Haddock, and Nix-first conventions in the constitution.

## Recent Changes
- 015-synthesizer-nondeterminism: Added Haskell, GHC 9.12.3 via haskell.nix `ghc9123`. Same
- 002-chaindb-synthesis: Added Haskell, GHC 9.12.3 via haskell.nix `ghc9123` + cardano-node 10.7.1-aligned Cardano libraries, stock `db-synthesizer`, `aeson`, `optparse-applicative`, JSON Schema tooling, Docker Compose acceptance image

- 001-scenario-bake-cli-plan: Added Haskell, GHC 9.12.3 (`ghc9123`) + haskell.nix, CHaP, iohk-nix crypto overlays,

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
