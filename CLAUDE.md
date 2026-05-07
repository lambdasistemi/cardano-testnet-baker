# cardano-testnet-baker Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-05-07

## Active Technologies

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

- 001-scenario-bake-cli-plan: Added Haskell, GHC 9.12.3 (`ghc9123`) + haskell.nix, CHaP, iohk-nix crypto overlays,

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
