# Implementation Plan: Haskell Dressing Layer Substituting The Configurator

**Feature Branch**: `feat/issue-23-dressing-haskell`
**Spec**: `spec.md`
**Status**: Draft

## Architecture

```
src/Cardano/Testnet/Baker/Dressing/
  Profile.hs         -- the Profile ADT + Apply
  Layout.hs          -- PoolIx, NumPools, layout primitives
  Patch.hs           -- JSON patch sum type + composition
  Topology.hs        -- Ring constructor + renderTopology
  Runtime.hs         -- RuntimeMold, Now, RuntimeOverrides
  Profiles/
    AntithesisConfigurator.hs   -- the only built-in profile
src/Cardano/Testnet/Baker/Dress.hs
  -- top-level "dress" function: IO orchestrator that loads baker
  -- output, applies a Profile, writes the runtime tree.

app/Main.hs
  -- adds the `dress` subcommand to the existing CLI.

test/Cardano/Testnet/Baker/Dressing/
  ProfileSpec.hs
  PatchSpec.hs
  TopologySpec.hs
  LayoutSpec.hs
  RuntimeSpec.hs
  AntithesisConfiguratorSpec.hs
```

## Key Decisions

### D-1: Pure core + IO orchestrator

All four building blocks (`Layout`, `Patch`, `Topology`,
`RuntimeMold`) are pure values producing pure descriptions
(`Map FilePath ByteString`, `Value -> Value`, etc.).  IO is confined
to `src/Cardano/Testnet/Baker/Dress.hs`, which loads the baker output
into memory, applies the profile, and writes the result.  Property
tests assert determinism on the pure core without faking the
filesystem.

### D-2: Patch is a typed sum + transformation

```haskell
data PatchTarget
  = TargetConfig
  | TargetShelleyGenesis
  | TargetAlonzoGenesis
  | TargetByronGenesis
  | TargetConwayGenesis
  | TargetTopology

data Patch = Patch
  { patchTarget    :: !PatchTarget
  , patchTransform :: !(Value -> Value)
  , patchName      :: !Text       -- for tracing / debugging
  }
```

Composition: a `[Patch]` is folded over the inputs in order.  No
`Monoid` instance on `Patch` itself; `[Patch]` already has one via
list concatenation.  Order matters and must stay explicit.

### D-3: Topology is closed-sum, extensible by adding constructors

```haskell
data Topology
  = Ring  { ringValency :: !Int, ringAdvertise :: !Bool, ringTrustable :: !Bool }
  -- future: | Star { hub :: !PoolIx } | Mesh | Custom
```

`renderTopology :: Topology -> PoolIx -> NumPools -> Value` is a
pure function returning the JSON shape `cardano-node` expects.  Pool
host names follow a `Layout`-supplied formatter so star topologies
can use the same machinery.

### D-4: Layout owns the pool-index → path mapping

```haskell
newtype PoolIx = PoolIx Int          -- 1-based
newtype NumPools = NumPools Int

data Layout = Layout
  { layoutPoolDir   :: PoolIx -> FilePath        -- "p1", "p2", ...
  , layoutPoolHost  :: PoolIx -> Text            -- "p1.example", ...
  , layoutConfigDir :: FilePath                  -- "configs"
  , layoutKeyDir    :: FilePath                  -- "keys"
  }
```

The antithesis layout: `layoutPoolDir = "p" <> show ix`,
`layoutPoolHost = "p" <> show ix <> ".example"`.  Star and mesh
profiles will need different host name formatters; `Layout` is the
natural place.

### D-5: RuntimeMold separates *what* from *now*

```haskell
data RuntimeMold = RuntimeMold
  { runtimeAlign :: !Int     -- seconds; e.g. 120 for the configurator
  }

newtype Now = Now { unNow :: POSIXTime }

data RuntimeOverrides = RuntimeOverrides
  { systemStartIso  :: !Text
  , systemStartUnix :: !Int64
  }

runtimeOverrides :: RuntimeMold -> Now -> RuntimeOverrides
```

The clock is a value, never read inside the mold.  `Dress.hs`
captures `Now` once, passes it to the mold, and the result is a
deterministic `RuntimeOverrides` value.

### D-6: Profile is an immutable record

```haskell
data Profile = Profile
  { profileName     :: !Text                 -- CLI selector
  , profileLayout   :: !Layout
  , profilePatches  :: ![Patch]
  , profileTopology :: !Topology
  , profileRuntime  :: !RuntimeMold
  }
```

The CLI exposes a closed `Map Text Profile` of named built-in
profiles.  This PR adds `antithesisConfigurator`; future profiles
land by adding entries.  External profiles (library consumers
constructing their own `Profile` value) are supported by the
exposed API even though the CLI is closed.

### D-7: Dress IO orchestrator pseudo-code

```haskell
dress :: DressOpts -> IO ()
dress opts = do
  scenario  <- decodeFile (dressScenario opts)
  baked     <- loadBakedOutput (dressBaked opts)        -- pure value
  now       <- maybe getCurrentNow pure (dressNow opts)
  let runtime = runtimeOverrides (profileRuntime p) now
      dressed = applyProfile p baked runtime            -- pure
  writeDressedOutput (dressOut opts) dressed
  where
    p = lookupProfile (dressProfile opts)
```

`applyProfile :: Profile -> BakedOutput -> RuntimeOverrides -> DressedOutput`
is the core pure function — that is where property tests live.

## Determinism Argument

For any fixed `(scenario, bakedOutput, profile, now)` tuple, the
output of `dress` is bit-identical.  This is provable by induction on
`applyProfile`:

- `Layout` functions are pure.
- `Patch` transformations are pure JSON transformations.
- `Topology` rendering is pure.
- `RuntimeOverrides` is a pure function of `runtimeAlign` and `now`.

The only non-determinism in the IO orchestrator is the clock read
when `--system-start` is not supplied; making that explicit (and the
default override-able from CLI) keeps the property under control.

## Tests

- **PatchSpec**: composition is associative; order of edits is the
  order of the list; each built-in patch leaves untouched fields
  intact.
- **TopologySpec**: `Ring n` produces the expected `accessPoints`
  for `PoolIx`es in `[1..NumPools]`, wraps at boundaries, respects
  valency.
- **LayoutSpec**: pool dirs and host names are bijective with
  `PoolIx`.
- **RuntimeSpec**: aligning `Now` to `runtimeAlign` is idempotent
  for already-aligned times; rounds down for misaligned times;
  produces ISO strings that round-trip to UNIX seconds.
- **AntithesisConfiguratorSpec**: applying the profile to a fixture
  baked output yields a runtime layout whose files match a golden
  fixture (JSON-stable, mode-stable), modulo the runtime overrides.
- **ProfileSpec**: `applyProfile` is pure and idempotent w.r.t. the
  output filesystem map under fixed inputs.

## Migration Strategy

1. Add the new modules behind a feature-test (TDD: red → green →
   refactor).  `applyProfile` reaches the golden fixture before
   wiring CLI.
2. Add the `dress` subcommand once `applyProfile` is green.
3. Update `compose/acceptance/multi/run.sh` to call
   `nix run . -- dress` and drop the bash adapt path.
4. Delete `compose/acceptance/multi/adapt.sh`.
5. Update `.github/workflows/ci.yml` to match.

## Risks

- **R-1**: Golden fixtures drift if the bash adapter changes
  upstream.  Mitigation: pin the fixture to a snapshot of `adapt.sh`
  output captured during this PR, document the snapshot's origin in
  the test module.
- **R-2**: `Patch` ordering matters and is easy to get wrong if
  someone reorders the profile's patch list.  Mitigation: write the
  ordering rule into a Haddock note on `antithesisConfigurator` and
  reflect it in `PatchSpec`.
- **R-3**: Future topologies (star, mesh) may want per-pool
  metadata the current `Topology` type doesn't carry.  Mitigation:
  do not over-engineer in this PR; add fields when the second
  profile lands.
