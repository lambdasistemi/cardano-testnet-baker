{- |
Module      : Cardano.Testnet.Baker.Determinism
Description : Deterministic byte derivation helpers.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Implements domain-separated key and artifact derivation from scenario
seed material.
-}
module Cardano.Testnet.Baker.Determinism
    ( DerivationRole (..)
    , derivationDomain
    , deriveBytes
    ) where

import Crypto.Hash (SHA256)
import Crypto.KDF.HKDF qualified as HKDF
import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.Text.Encoding qualified as Text

-- | Role-specific domain for deterministic byte derivation.
data DerivationRole
    = PoolColdKey
    | PoolVrfKey
    | PoolKesKey
    | PoolStakeKey
    | FaucetPaymentKey
    deriving (Eq, Show)

-- | Root derivation domain for Feature 001 deterministic material.
derivationDomain :: ByteString
derivationDomain = "cardano-testnet-baker/v1"

-- | Derive deterministic bytes for a role and label from scenario seed bytes.
deriveBytes
    :: ByteString -> DerivationRole -> Text -> Int -> ByteString
deriveBytes seed role label byteCount =
    let prk = HKDF.extract derivationDomain seed :: HKDF.PRK SHA256
        info = roleTag role <> ":" <> Text.encodeUtf8 label
    in  HKDF.expand prk info byteCount

roleTag :: DerivationRole -> ByteString
roleTag = \case
    PoolColdKey -> "pool-cold"
    PoolVrfKey -> "pool-vrf"
    PoolKesKey -> "pool-kes"
    PoolStakeKey -> "pool-stake"
    FaucetPaymentKey -> "faucet-payment"
