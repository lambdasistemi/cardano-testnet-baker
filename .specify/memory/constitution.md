<!--
Sync Impact Report

Version change: 1.0.0 -> 1.1.0
Modified principles:
- I. Declarative Scenarios As The Single Input: expanded to require a
  published, versioned JSON Schema for the scenario/bootstrapping JSON contract.
- VI. Smallest Provable Step: expanded to require Docker Compose cluster
  acceptance against generated assets before treating them as consumable.
Added sections: none
Removed sections: none
Templates requiring updates:
- .specify/templates/plan-template.md reviewed; no template change required
- .specify/templates/spec-template.md reviewed; no template change required
- .specify/templates/tasks-template.md reviewed; no template change required
- .specify/templates/commands/*.md reviewed; directory not present
Runtime guidance reviewed:
- README.md reviewed; no immediate wording change required before the schema
  feature lands
Deferred follow-ups: none
-->

# cardano-testnet-baker Constitution

## Core Principles

### I. Declarative Scenarios As The Single Input

The tool's contract is one JSON document — a *scenario* — that fully
describes a Cardano testnet (initial stake, producers, faucets, era
schedule, optional ChainDB synthesis). Every artifact the baker
produces is a deterministic function of that scenario. No hidden
inputs, no implicit defaults that vary between runs, no environment
variables silently shaping output.

Rule: if a parameter affects the output, it lives in the scenario
JSON or in a SHA-pinned dependency. If a parameter must vary at
consumer-mount time (e.g. `systemStart`), it is patched *outside*
the artifact, not by re-baking.

Rule: the scenario, also called the bootstrapping JSON when consumed
downstream, is a public compatibility contract. The repo MUST publish
a versioned JSON Schema for that contract, committed alongside the
example scenarios. CI MUST validate every committed example scenario
against the published schema. Schema-breaking changes MUST bump the
schema version and document the migration path in the feature plan.

### II. Determinism By Construction

A scenario plus a SHA-pinned baker version must produce bit-identical
artifacts on any host. Every key (KES, VRF, cold, op-cert, stake,
faucet) is derived from `(scenario.seed, role, label)` via a
documented derivation function. No `cardano-cli`-style
`--out-dir`-with-fresh-randomness paths, no clock-dependent fields
inside the artifact (Byron `systemStart` excepted; see Principle I).

Rule: every output file's content is reproducible offline from the
scenario + the baker SHA. CI verifies this with a determinism check
that bakes the same scenario twice and diffs.

### III. Reproducibility By Pinning, Not By Tags

Every dependency is pinned to a commit SHA, never a moving tag.

- Haskell: `cabal.project` `index-state` and
  `source-repository-package` SHAs (`--sha256` in nix32 format)
- Docker images we publish: tagged with the consumer's commit SHA,
  not `:main` or `:latest`
- `flake.lock` committed and treated as load-bearing

A `:main` tag in any production-facing artifact is a bug.

### IV. Nix-First, haskell.nix For Haskell

This is a Nix-first repo with haskell.nix as the Haskell layer.

- `flake.nix` thin, real config under `nix/{project,shell,checks}.nix`
- IOG cache (`hydra.iohk.io`) and `paolino.cachix.org`
- CHaP wired in only when a cardano-* dependency actually needs it
  (deferred until the first feature spec calls for it)
- `runs-on: nixos` for all CI jobs (lambdasistemi self-hosted runner)
- Build Gate first, downstream jobs gated on it
- Never `nix develop -c cabal test` in CI; always `nix build` /
  `nix run .#unit-tests`

### V. Stock Tools, Custom Orchestration

When the baker drives an existing Cardano executable
(`db-synthesizer`, `cardano-cli`, `cardano-node`), it consumes that
executable as either:

- **(a)** an unmodified upstream IOG release artifact, SHA-pinned, or
- **(b)** an in-repo executable that consumes upstream code purely as
  a *library* (no patches, no vendored copies)

Forking, vendoring, or maintaining feature branches against
ouroboros-network, ouroboros-consensus, cardano-ledger, or
cardano-node is not permitted. If a needed feature does not exist
upstream, the response is to upstream it or to write a minimal
mode-(b) tool, not to fork.

### VI. Smallest Provable Step

Prove an assumption with a smoke test before scaffolding around it.
The first feature spec exists to validate that a chosen approach
actually produces consumable artifacts; only then do we scale to
multiple scenarios, OCI publishing, or downstream wiring.

Rule: any feature that creates or changes baked testnet assets MUST
run a Docker Compose cluster acceptance test against those exact
assets before the feature is considered ready for `main`. The cluster
MUST mount the generated genesis files and required key material,
start the intended node topology far enough to validate the initial
chain state, and fail on genesis, configuration, key, or startup
validation errors.

## Code Quality Gates

- Hackage-ready Haskell at all times: `cabal check` clean, `-Werror`
  with the canonical warning set, Haddock on all exported names
- Fourmolu (70-char limit, leading commas/arrows, 4-space indent)
- HLint clean
- Shell scripts: `set -euo pipefail`, shellcheck clean
- Asset-producing features: Docker Compose cluster acceptance clean
  against the generated assets before merge
- `just CI` mirrors the GitHub CI workflow; runs locally before
  every push

## Distribution Targets

The CLI must be installable on developer laptops via at least:

- `nix run github:lambdasistemi/cardano-testnet-baker -- ...`
- A SHA-pinned OCI image at `ghcr.io/lambdasistemi/cardano-testnet-baker`
- Native binaries (Linux DEB/RPM/AppImage, macOS Homebrew tap) once
  the `distribute-binaries` flow is wired in

Each distribution channel publishes the same scenario-input contract;
swapping channels must not change output.

## Development Workflow

- Every ticket runs through speckit: `specify` → `plan` → `tasks` →
  `implement`. No implementation without a spec on disk.
- One worktree per branch; main repo stays on `main`.
- Linear history on `main` (rebase merge only).
- Branch protection: `Build Gate` required, admin bypass.
- PR descriptions are living documents — updated with every push.
- All PRs labeled (`feat`/`fix`/`chore`/...).
- Conventional Commits for release tooling.

## Governance

This constitution gates all planning. `speckit-plan` and
`speckit-tasks` must show how the proposed work satisfies (or
explicitly justifies an exception to) every Core Principle. Amendments
require a PR titled `chore(constitution): ...` and bump the version
below.

**Version**: 1.1.0 | **Ratified**: 2026-05-07 | **Last Amended**: 2026-05-07
