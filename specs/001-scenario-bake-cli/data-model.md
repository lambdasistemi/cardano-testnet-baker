# Data Model: Scenario JSON Schema and Bake CLI MVP

## Scenario

The single declarative JSON input. Every field that affects output must live
here or in a SHA-pinned dependency.

Required fields:
- `schemaVersion`: scenario schema version, initially `1`.
- `scenarioId`: stable human-readable scenario identifier.
- `seed`: hex/base16 seed material used only as HKDF input.
- `network`: network magic, network id, and protocol/network shape.
- `eraSchedule`: hard-fork activation choices for the MVP scenarios.
- `genesis`: genesis and era parameters, including `epochLength`,
  `activeSlotsCoeff`, `securityParam`, `k`, supply, and protocol parameters.
- `pools`: non-empty list of pool declarations.
- `faucets`: funded UTxO/faucet declarations represented in Shelley
  `initialFunds`.

Validation rules:
- All output-affecting fields are explicit.
- `systemStart` and Byron `startTime` are not run-specific baked values.
- Pool labels and faucet labels are unique after normalization.
- Faucet funds fit within declared supply.
- Unsupported requests such as ChainDB synthesis or OCI output are rejected.

## Pool Declaration

Describes one block producer's deterministic key labels and genesis
participation parameters.

Fields:
- `label`
- `pledge`
- `cost`
- `margin`
- `stake`
- `coldKeyLabel`
- `vrfKeyLabel`
- `kesKeyLabel`
- `stakeKeyLabel`

Relationships:
- Belongs to one Scenario.
- Produces one output subtree under `pools/<label>/`.
- Contributes registration/delegation state to Shelley genesis.

## Faucet Funding Declaration

Declares funds that downstream transaction generators can spend.

Fields:
- `label`
- `paymentKeyLabel`
- `lovelace`
- optional `metadata`

Relationships:
- Belongs to one Scenario.
- Produces signing/address information under `utxo-keys/`.
- Adds exactly one Shelley `initialFunds` entry.

## Bake Output

Filesystem artifact tree produced from one Scenario and one baker version.

Required paths:
- `genesis/byron-genesis.json`
- `genesis/shelley-genesis.json`
- `genesis/alonzo-genesis.json`
- `genesis/conway-genesis.json`
- `genesis/config.json`
- `pools/<pool-label>/keys/{cold.skey,cold.vkey,kes.skey,vrf.skey,opcert.cert,stake.skey,stake.vkey}`
- `utxo-keys/<faucet-label>.skey`
- `utxo-keys/<faucet-label>.addr.info`
- `metadata.json`

State transitions:
- `ValidatedScenario -> StagedOutput`
- `StagedOutput -> PublishedOutput`
- `PublishedOutput -> AcceptedByCompose`

## Bake Metadata

Machine-readable record for provenance and reproducibility.

Fields:
- `scenarioId`
- `schemaVersion`
- `bakerVersion`
- `bakerCommit`
- `inputDigest`
- `artifactDigests`
- `derivationVersion`
- `createdBy`

Validation rules:
- No wall-clock timestamp is included in deterministic metadata.
- Digests are over canonical bytes in relative-path order.

## Compose Acceptance Run

Temporary verification state, not part of the baked deterministic artifact.

Fields:
- `scenarioId`
- `artifactPath`
- `patchedRuntimePath`
- `nodeImage`
- `nodeImageDigest`
- `composeProjectName`
- `verdict`
- `logPath`

Validation rules:
- Runtime start-time patches happen only in `patchedRuntimePath`.
- The bake output is mounted read-only.
- The node image reference is immutable: digest-pinned or otherwise recorded in
  a SHA-pinned Nix input used to build the acceptance runner.
- Failure logs identify node startup, genesis, config, or key validation errors.
