# Feature Specification: Haskell Dressing Layer Substituting The Configurator

**Feature Branch**: `feat/issue-23-dressing-haskell`
**Created**: 2026-05-11
**Status**: Draft
**Input**: Issue #23. Replace `compose/acceptance/multi/adapt.sh`
(introduced by #21) with a typed, composable Haskell **dressing** layer
that produces the per-pool runtime layout the antithesis configurator
container produces today, so the bash adapter can be deleted and
additional consumer profiles cost a value, not a new shell script.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Dress A Baked Artifact For The Antithesis Configurator (Priority: P1)

A testnet operator has a baked artifact set (the output of `bake`) and
wants to feed it into a multi-pool docker-compose that uses the same
service shape as `cardano-node-antithesis/testnets/cardano_node_master/
docker-compose.yaml`.  They invoke `dress` with the
`antithesis-configurator` profile and receive a runtime directory laid
out as the antithesis compose stack expects:

- `<runtime>/p<n>/configs/{config.json,topology.json,*-genesis.json}`
- `<runtime>/p<n>/keys/{kes.skey,vrf.skey,opcert.cert}`
- `<runtime>/utxo-keys/...` (passed through from the bake)

**Why this priority**: This is the substitution claim PR #22 proves
with a bash script.  Landing it in Haskell is what lets the repo
retire the configurator without re-introducing non-determinism.

**Independent Test**: For any baked scenario with N pools, dressing
with the `antithesis-configurator` profile produces a runtime
directory whose contents, file modes, and JSON shape match the bash
adapter's output byte-for-byte modulo the `systemStart` /
`startTime` runtime patch (which the runtime mold controls).

**Acceptance Scenarios**:

1. **Given** a baked `antithesis-master` scenario, **When** the
   operator runs `dress --profile antithesis-configurator`, **Then**
   the runtime directory contains exactly three per-pool subtrees
   (`p1`, `p2`, `p3`) each with the expected `configs/` + `keys/`
   layout, plus a copied `utxo-keys/` directory.
2. **Given** the same scenario, **When** the runtime directory is
   mounted into a 3-container docker-compose using the antithesis
   service shape, **Then** all three pools open their ChainDB
   cleanly.
3. **Given** a fast scenario (epochLength 120, k 1), **When** the
   pools start from the dressed runtime, **Then** they forge at least
   one non-genesis block and the chain tip hash appears in all three
   pools' logs (the block-agreement bar already used by #21).

---

### User Story 2 - Compose A New Profile Without Forking The Library (Priority: P1)

A consumer maintainer wants to define an alternative profile (e.g. a
star topology, or a different set of `config.json` patches) without
re-implementing the dressing pipeline.  They construct a `Profile`
value out of the public `Layout`, `Patch`, `Topology`, and
`RuntimeMold` building blocks and either compile it into the binary or
register it under a new CLI flag.

**Why this priority**: This is *the* justification for moving from
bash to Haskell.  If the abstractions don't compose, the migration is
a net loss.

**Independent Test**: A second profile that swaps `Ring 2` for `Star
{ hub = "p1" }` and disables the Alonzo bump must be expressible
without touching any existing module, and round-trip through `dress`
end-to-end.

**Acceptance Scenarios**:

1. **Given** the public dressing API, **When** a maintainer defines a
   `Profile` literal that reuses `antithesisConfigurator`'s layout but
   replaces its topology with `Star`, **Then** the project compiles
   without modifications elsewhere and `dress` accepts the new
   profile.
2. **Given** the same API, **When** a maintainer composes patches with
   `(<>)` (or an equivalent combinator), **Then** the resulting patch
   list applies in deterministic order to the same target JSON files
   without losing or duplicating edits.

---

### User Story 3 - Delete The Bash Adapter (Priority: P1)

After the dressing layer ships and the acceptance harness has been
re-wired to call `dress`, the bash adapter
(`compose/acceptance/multi/adapt.sh`) is removed.  The CI's
`Compose acceptance` job invokes `nix run . -- dress` instead.

**Why this priority**: Without the deletion this PR adds a new
codepath instead of replacing the old one — and the user's goal is
explicitly "remove these scripts".

**Independent Test**: After the PR lands,
`compose/acceptance/multi/adapt.sh` is absent, `dress` is the only
adapter between baker output and the acceptance harness, and the
`Compose acceptance` CI job is green on both `antithesis-master` and
`antithesis-fast` flows.

## Functional Requirements *(mandatory)*

- **FR-1**: A new `dress` subcommand exists on the `cardano-testnet-baker`
  binary.  Required flags: `--scenario`, `--baked`, `--profile`,
  `--out`.  Optional flag: `--system-start` (UNIX seconds, overrides
  the runtime mold's default).
- **FR-2**: A public `Profile` ADT exists with four fields: `Layout`,
  list of `Patch`es, `Topology`, `RuntimeMold`.  Each of those four
  building blocks has its own module and public API.
- **FR-3**: A built-in `antithesisConfigurator :: Profile` value
  encodes today's bash adapter:
  - Layout maps baker `pools/pool-X` to per-pool runtime dirs
    `p<n>` (where `n` is the pool's positional index, 1-based).
  - Patches: drop `*GenesisHash`, `hasEKG`, `options.mapBackends`;
    set `PeerSharing = true`; set `LedgerDB = {Backend: "V2InMemory"}`;
    bump `alonzo-genesis.maxTxExUnits` to 14M mem / 14B steps and
    `maxBlockExUnits` to 80M mem / 64B steps.
  - Topology: `Ring 2` (valency 2, advertise true, trustable true,
    pool host names of the form `p<n>.example`).
  - RuntimeMold: align `systemStart` and Byron `startTime` to a 120 s
    UNIX-epoch boundary (override-able via `--system-start`).
- **FR-4**: `Patch` is a typed JSON edit with a target file
  classifier (`Config`, `AlonzoGenesis`, `ShelleyGenesis`,
  `ByronGenesis`, `Topology`, `…`) and a transformation
  (`Value -> Value`).  Patches compose monoidally; order of
  application is the order of the `[Patch]` list.
- **FR-5**: `Topology` is a sum type with at least one constructor
  `Ring { valency :: Int, advertise :: Bool, trustable :: Bool }`.
  `renderTopology :: Topology -> PoolIx -> NumPools -> Topology.json`
  is a pure function.
- **FR-6**: `Layout` exposes pure functions
  `runtimePoolDir :: Layout -> PoolIx -> FilePath` and
  `runtimeKeyFiles :: Layout -> Map FileName ByteString -> Map FilePath ByteString`
  so dressing IO is at the edge of the program.
- **FR-7**: `RuntimeMold` exposes `runtimeOverrides :: RuntimeMold ->
  Now -> RuntimeOverrides` where `Now` is an injected clock value, so
  property tests can assert determinism without faking time globally.
- **FR-8**: The `dress` command is deterministic given fixed inputs
  including the clock value supplied via `--system-start`.  Without
  `--system-start`, the clock is the wall clock and the only
  non-determinism is the runtime mold's `systemStart` /
  `startTime` patch.
- **FR-9**: `compose/acceptance/multi/adapt.sh` is **deleted** in
  this PR.  `compose/acceptance/multi/run.sh` invokes
  `nix run . -- dress …` in its place.
- **FR-10**: `.github/workflows/ci.yml` `Compose acceptance` job
  passes both `antithesis-master` (chaindb-opened) and
  `antithesis-fast` (block-agreement) bars using the Haskell
  `dress`.

## Out Of Scope

- Additional `Profile` instances beyond `antithesisConfigurator`.
  The ADT shape must admit them, but no other profile lands in this
  PR.
- Wiring the dressed output into the actual `cardano-node-antithesis`
  docker-compose stack as a drop-in container.  That is the next
  ticket.
- Threading the configurator patches into `bake` itself.  Per
  Constitution principle I, runtime-mount-time mutations stay outside
  `bake`.

## Success Criteria

1. The dressing public API supports composing a second profile with
   a different topology and a different patch list, exercised by an
   internal test value (not exposed via CLI).
2. `just acceptance-antithesis-master` and `just acceptance-antithesis-fast`
   pass with `dress` in place of `adapt.sh`, with no remaining
   reference to `adapt.sh` in the tree.
3. CI `Compose acceptance` job passes on both flows.
4. The new modules and their tests live under
   `src/Cardano/Testnet/Baker/Dressing/` and
   `test/Cardano/Testnet/Baker/Dressing/`.
