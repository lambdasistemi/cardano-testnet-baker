{- |
Module      : Cardano.Testnet.Baker.Dressing.Profiles.AntithesisConfigurator
Description : Built-in profile reproducing the antithesis configurator's output.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

The @antithesis-configurator@ profile composes the building blocks
from "Cardano.Testnet.Baker.Dressing.Layout",
".Patch", ".Topology", and ".Runtime" into the exact shape the bash
adapter produces today.  It is the only profile that ships with
this repo; additional profiles land by adding values here or in a
sibling module.
-}
module Cardano.Testnet.Baker.Dressing.Profiles.AntithesisConfigurator
    ( antithesisConfigurator
    ) where

import Cardano.Testnet.Baker.Dressing.Layout (antithesisLayout)
import Cardano.Testnet.Baker.Dressing.Patch
    ( bumpAlonzoExUnits
    , dropGenesisHashes
    , dropHasEKG
    , dropMapBackends
    , setByronStartTime
    , setLedgerDBInMemory
    , setPeerSharing
    , setSystemStart
    )
import Cardano.Testnet.Baker.Dressing.Profile (Profile (..))
import Cardano.Testnet.Baker.Dressing.Runtime (antithesisRuntime)
import Cardano.Testnet.Baker.Dressing.Topology (antithesisTopology)

{- | The configurator-equivalent profile.

The patch list reproduces @configurator.sh@'s emissions in the
order they appear in the script: drop hashes / EKG / mapBackends,
set PeerSharing + LedgerDB, bump Alonzo ExUnits, then write the
runtime overrides into shelley + byron genesis.  Order matters when
patches interact; the unit tests in
@Cardano.Testnet.Baker.Dressing.PatchSpec@ assert that the
configurator-relevant patches are independent under this order.
-}
antithesisConfigurator :: Profile
antithesisConfigurator =
    Profile
        { profileName = "antithesis-configurator"
        , profileLayout = antithesisLayout
        , profilePatches =
            [ dropGenesisHashes
            , dropHasEKG
            , dropMapBackends
            , setPeerSharing True
            , setLedgerDBInMemory
            , bumpAlonzoExUnits
            , setSystemStart
            , setByronStartTime
            ]
        , profileTopology = antithesisTopology
        , profileRuntime = antithesisRuntime
        }
