{- |
Module      : Cardano.Testnet.Baker.Dressing.Layout
Description : Pool-index to filesystem-path mapping for dressing.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

A 'Layout' captures the per-pool directory and host-name conventions a
particular consumer expects.  The antithesis configurator uses
@p<n>@ directory names and @p<n>.example@ host names; alternative
consumers can supply different formatters without forking the
dressing pipeline.
-}
module Cardano.Testnet.Baker.Dressing.Layout
    ( PoolIx (..)
    , NumPools (..)
    , poolIndices
    , Layout (..)
    , antithesisLayout
    ) where

import Data.Text (Text)
import Data.Text qualified as T

{- | 1-based pool index.  Pools are addressed positionally (the order
they appear in the scenario).  The dressing layer never invents a
'PoolIx' out of thin air: it walks the baker output's pool
directory list and assigns indices @[1..n]@ deterministically.
-}
newtype PoolIx = PoolIx {unPoolIx :: Int}
    deriving (Eq, Ord, Show)

{- | Number of pools the dressing is producing.  Always
@NumPools n@ with @n >= 1@; the 'Profile.applyProfile' caller is
responsible for upholding the invariant.
-}
newtype NumPools = NumPools {unNumPools :: Int}
    deriving (Eq, Ord, Show)

{- | Enumerate the pool indices @[PoolIx 1 .. PoolIx n]@.  Pure helper
for callers that need to walk every pool.
-}
poolIndices :: NumPools -> [PoolIx]
poolIndices (NumPools n) = [PoolIx i | i <- [1 .. n]]

{- | Per-pool filesystem and naming conventions.

'Layout' carries functions, so it has no 'Eq' or 'Show' instance.
Tests assert behaviour by applying the functions to concrete pool
indices.
-}
data Layout = Layout
    { layoutPoolDir :: PoolIx -> FilePath
    {- ^ Per-pool runtime directory name, relative to the dressed
    output root.  Antithesis: @"p<n>"@.
    -}
    , layoutPoolHost :: PoolIx -> Text
    {- ^ Host name used to address the pool from peers.  Antithesis:
    @"p<n>.example"@.
    -}
    , layoutConfigDir :: FilePath
    {- ^ Sub-directory under each pool's runtime dir that holds the
    node config and genesis files.  Antithesis: @"configs"@.
    -}
    , layoutKeyDir :: FilePath
    {- ^ Sub-directory under each pool's runtime dir that holds the
    per-pool keys (KES, VRF, opcert).  Antithesis: @"keys"@.
    -}
    }

{- | Layout used by the @antithesis-configurator@ profile.  Mirrors
@cardano-node-antithesis/components/configurator/configurator.sh@.
-}
antithesisLayout :: Layout
antithesisLayout =
    Layout
        { layoutPoolDir = \(PoolIx i) -> "p" <> show i
        , layoutPoolHost = \(PoolIx i) -> "p" <> T.pack (show i) <> ".example"
        , layoutConfigDir = "configs"
        , layoutKeyDir = "keys"
        }
