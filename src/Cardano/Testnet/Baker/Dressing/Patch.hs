{- |
Module      : Cardano.Testnet.Baker.Dressing.Patch
Description : Composable, typed JSON edits applied at dressing time.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

A 'Patch' is a typed, named JSON edit pinned to a 'PatchTarget'
(@config.json@, @alonzo-genesis.json@, etc.).  Patches compose via
list concatenation; 'applyPatches' folds the list in order over a
target value.

The transformation function receives the 'RuntimeOverrides' value
the dressing computed once at the top of the run, so patches that
need to inject @systemStart@ or @startTime@ are just patches whose
transformation reads from the override record.  Static patches
ignore the argument.

The built-in patches at the bottom of this module reproduce the
configurator's emission rules verbatim:

* drop @*GenesisHash@, @hasEKG@, @options.mapBackends@ from
  @config.json@
* set @PeerSharing@ and @LedgerDB.Backend@ in @config.json@
* bump @maxTxExUnits@ / @maxBlockExUnits@ in
  @alonzo-genesis.json@
* write the runtime override into @systemStart@ /
  @startTime@ of shelley / byron genesis
-}
module Cardano.Testnet.Baker.Dressing.Patch
    ( PatchTarget (..)
    , Patch (..)
    , applyPatches

      -- * Built-in static patches
    , dropGenesisHashes
    , dropHasEKG
    , dropMapBackends
    , setPeerSharing
    , setLedgerDBInMemory
    , bumpAlonzoExUnits

      -- * Built-in runtime patches
    , setSystemStart
    , setByronStartTime
    ) where

import Cardano.Testnet.Baker.Dressing.Runtime
    ( RuntimeOverrides (..)
    )
import Data.Aeson
    ( Value (Object, String)
    , toJSON
    )
import Data.Aeson.Key (Key)
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.Foldable (foldl')
import Data.Text (Text)

-- | The file a patch operates on.
data PatchTarget
    = TargetConfig
    | TargetShelleyGenesis
    | TargetAlonzoGenesis
    | TargetByronGenesis
    | TargetConwayGenesis
    | TargetTopology
    deriving (Eq, Ord, Show)

{- | A typed, named JSON edit.  The transformation receives the
'RuntimeOverrides' value the dressing computed once; static
patches ignore the argument.
-}
data Patch = Patch
    { patchTarget :: !PatchTarget
    , patchName :: !Text
    , patchTransform :: !(RuntimeOverrides -> Value -> Value)
    }

instance Show Patch where
    show p =
        "Patch "
            <> show (patchName p)
            <> " @ "
            <> show (patchTarget p)

{- | Fold the patches that target @target@ over @value@, left to
right.  Patches targeting a different file are skipped.
-}
applyPatches
    :: [Patch] -> RuntimeOverrides -> PatchTarget -> Value -> Value
applyPatches patches ro target v0 = foldl' step v0 patches
  where
    step v p
        | patchTarget p == target = patchTransform p ro v
        | otherwise = v

-- ---------------------------------------------------------------
-- Aeson helpers

deleteKey :: Key -> Value -> Value
deleteKey k (Object o) = Object (KM.delete k o)
deleteKey _ v = v

setKey :: Key -> Value -> Value -> Value
setKey k x (Object o) = Object (KM.insert k x o)
setKey _ _ v = v

-- | Apply @f@ to the value under @k@ if it exists; no-op otherwise.
overKey :: Key -> (Value -> Value) -> Value -> Value
overKey k f (Object o) =
    case KM.lookup k o of
        Just inner -> Object (KM.insert k (f inner) o)
        Nothing -> Object o
overKey _ _ v = v

-- ---------------------------------------------------------------
-- Built-in static patches

{- | Drop the four optional @*GenesisHash@ fields from
@config.json@.  No-op when the keys are absent (which is the case
for baker output today).
-}
dropGenesisHashes :: Patch
dropGenesisHashes =
    Patch
        { patchTarget = TargetConfig
        , patchName = "drop-genesis-hashes"
        , patchTransform = \_ ->
            deleteKey "AlonzoGenesisHash"
                . deleteKey "ByronGenesisHash"
                . deleteKey "ConwayGenesisHash"
                . deleteKey "ShelleyGenesisHash"
        }

-- | Drop @hasEKG@.
dropHasEKG :: Patch
dropHasEKG =
    Patch
        { patchTarget = TargetConfig
        , patchName = "drop-has-ekg"
        , patchTransform = \_ -> deleteKey "hasEKG"
        }

-- | Drop @options.mapBackends@.
dropMapBackends :: Patch
dropMapBackends =
    Patch
        { patchTarget = TargetConfig
        , patchName = "drop-map-backends"
        , patchTransform = \_ -> overKey "options" (deleteKey "mapBackends")
        }

-- | Set the top-level @PeerSharing@ flag.
setPeerSharing :: Bool -> Patch
setPeerSharing peerSharing =
    Patch
        { patchTarget = TargetConfig
        , patchName = "set-peer-sharing"
        , patchTransform = \_ -> setKey "PeerSharing" (toJSON peerSharing)
        }

{- | Set @LedgerDB@ to @{ Backend: "V2InMemory" }@.  Matches the
configurator default when @UTXO_HD_WITH@ is unset.
-}
setLedgerDBInMemory :: Patch
setLedgerDBInMemory =
    Patch
        { patchTarget = TargetConfig
        , patchName = "set-ledger-db-in-memory"
        , patchTransform = \_ ->
            setKey
                "LedgerDB"
                (Object (KM.fromList [("Backend", String "V2InMemory")]))
        }

-- | Bump the four Alonzo ExUnits caps so asteria scripts fit.
bumpAlonzoExUnits :: Patch
bumpAlonzoExUnits =
    Patch
        { patchTarget = TargetAlonzoGenesis
        , patchName = "bump-alonzo-exunits"
        , patchTransform = \_ ->
            overKey
                "maxTxExUnits"
                ( setKey "exUnitsMem" (toJSON (14000000 :: Int))
                    . setKey "exUnitsSteps" (toJSON (14000000000 :: Int))
                )
                . overKey
                    "maxBlockExUnits"
                    ( setKey "exUnitsMem" (toJSON (80000000 :: Int))
                        . setKey "exUnitsSteps" (toJSON (64000000000 :: Int))
                    )
        }

-- ---------------------------------------------------------------
-- Built-in runtime patches

-- | Write @systemStart@ into @shelley-genesis.json@.
setSystemStart :: Patch
setSystemStart =
    Patch
        { patchTarget = TargetShelleyGenesis
        , patchName = "set-system-start"
        , patchTransform = \RuntimeOverrides{..} ->
            setKey "systemStart" (String systemStartIso)
        }

-- | Write byron @startTime@ into @byron-genesis.json@.
setByronStartTime :: Patch
setByronStartTime =
    Patch
        { patchTarget = TargetByronGenesis
        , patchName = "set-byron-start-time"
        , patchTransform = \RuntimeOverrides{..} ->
            setKey "startTime" (toJSON systemStartUnix)
        }
