{- |
Module      : Cardano.Testnet.Baker.Dressing.Profile
Description : The Profile ADT and the pure applyProfile function.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

A 'Profile' bundles the four building blocks ('Layout', '[Patch]',
'Topology', 'RuntimeMold') that together describe a consumer's
dressed-output contract.  'applyProfile' is the pure function that
turns a baker output + a profile + a clock-derived
'RuntimeOverrides' into the in-memory representation of the
dressed runtime tree.

The dressed-output split between @dressedJsonFiles@ (JSON values
keyed by relative path) and @dressedByteFiles@ (raw bytes keyed by
relative path) is deliberate: keys pass through verbatim and never
travel through Aeson, while config + genesis + topology JSON
content is the natural unit for patches and golden-file
comparisons.
-}
module Cardano.Testnet.Baker.Dressing.Profile
    ( Profile (..)
    , BakedOutput (..)
    , PoolBaked (..)
    , DressedOutput (..)
    , applyProfile
    ) where

import Cardano.Testnet.Baker.Dressing.Layout
    ( Layout (..)
    , NumPools (..)
    , PoolIx (..)
    , poolIndices
    )
import Cardano.Testnet.Baker.Dressing.Patch
    ( Patch
    , PatchTarget (..)
    , applyPatches
    )
import Cardano.Testnet.Baker.Dressing.Runtime
    ( RuntimeMold
    , RuntimeOverrides
    )
import Cardano.Testnet.Baker.Dressing.Topology
    ( Topology
    , renderTopology
    )
import Data.Aeson (Value)
import Data.ByteString (ByteString)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import System.FilePath ((</>))

{- | A consumer-targeted dressing recipe.

The four fields are the levers a downstream profile twists to
match its consumer's contract; 'profileName' is the CLI selector.
Two profiles with identical layout / patches / topology / runtime
fields produce identical dressed output for the same input.
-}
data Profile = Profile
    { profileName :: !Text
    , profileLayout :: !Layout
    , profilePatches :: ![Patch]
    , profileTopology :: !Topology
    , profileRuntime :: !RuntimeMold
    }

{- | The relevant portion of a baker output, read into memory.

'bakedGenesisFiles' is keyed by basename
(@"config.json"@, @"alonzo-genesis.json"@, etc.).  'bakedPools' is
ordered: the head pool becomes 'PoolIx' 1, the next 'PoolIx' 2,
and so on.
-}
data BakedOutput = BakedOutput
    { bakedGenesisFiles :: !(Map FilePath Value)
    , bakedPools :: ![PoolBaked]
    , bakedUtxoKeys :: !(Map FilePath ByteString)
    }
    deriving (Eq, Show)

{- | The per-pool data the baker emits: a label (from the baker's
@pools/<label>/@ directory name) and the per-pool key files.
-}
data PoolBaked = PoolBaked
    { poolBakedLabel :: !Text
    , poolBakedKeys :: !(Map FilePath ByteString)
    }
    deriving (Eq, Show)

{- | The in-memory representation of the dressed runtime tree.

'dressedJsonFiles' covers the JSON content (config, topology,
genesis) written under each pool's @configs/@ dir.
'dressedByteFiles' covers the key files (kes, vrf, opcert) and
the pass-through @utxo-keys/@ tree.
-}
data DressedOutput = DressedOutput
    { dressedJsonFiles :: !(Map FilePath Value)
    , dressedByteFiles :: !(Map FilePath ByteString)
    }
    deriving (Eq, Show)

{- | Apply a profile to a baker output, producing the in-memory
dressed tree.  Pure: every byte of the output is a function of the
arguments.
-}
applyProfile
    :: Profile -> BakedOutput -> RuntimeOverrides -> DressedOutput
applyProfile Profile{..} BakedOutput{..} ro =
    DressedOutput
        { dressedJsonFiles = jsonFiles
        , dressedByteFiles = byteFiles
        }
  where
    numPools = NumPools (length bakedPools)

    poolPair :: PoolIx -> PoolBaked
    poolPair (PoolIx i) = bakedPools !! (i - 1)

    poolConfigPath :: PoolIx -> FilePath -> FilePath
    poolConfigPath ix file =
        layoutPoolDir profileLayout ix
            </> layoutConfigDir profileLayout
            </> file

    poolKeyPath :: PoolIx -> FilePath -> FilePath
    poolKeyPath ix file =
        layoutPoolDir profileLayout ix
            </> layoutKeyDir profileLayout
            </> file

    -- Helper that runs the configured patches against a target.
    patched :: PatchTarget -> FilePath -> Value
    patched target name =
        case Map.lookup name bakedGenesisFiles of
            Just v -> applyPatches profilePatches ro target v
            Nothing -> error ("applyProfile: missing baked genesis file " <> name)

    perPoolJson :: PoolIx -> Map FilePath Value
    perPoolJson ix =
        Map.fromList
            [ (poolConfigPath ix "config.json", patched TargetConfig "config.json")
            ,
                ( poolConfigPath ix "alonzo-genesis.json"
                , patched TargetAlonzoGenesis "alonzo-genesis.json"
                )
            ,
                ( poolConfigPath ix "byron-genesis.json"
                , patched TargetByronGenesis "byron-genesis.json"
                )
            ,
                ( poolConfigPath ix "conway-genesis.json"
                , patched TargetConwayGenesis "conway-genesis.json"
                )
            ,
                ( poolConfigPath ix "shelley-genesis.json"
                , patched TargetShelleyGenesis "shelley-genesis.json"
                )
            ,
                ( poolConfigPath ix "topology.json"
                , renderTopology
                    profileTopology
                    (layoutPoolHost profileLayout)
                    ix
                    numPools
                )
            ]

    perPoolBytes :: PoolIx -> Map FilePath ByteString
    perPoolBytes ix =
        Map.fromList
            [ (poolKeyPath ix file, bytes)
            | file <- ["kes.skey", "vrf.skey", "opcert.cert"]
            , Just bytes <- [Map.lookup file (poolBakedKeys (poolPair ix))]
            ]

    jsonFiles =
        Map.unions [perPoolJson ix | ix <- poolIndices numPools]

    byteFiles =
        Map.unions
            [ Map.unions [perPoolBytes ix | ix <- poolIndices numPools]
            , Map.mapKeys ("utxo-keys" </>) bakedUtxoKeys
            ]
