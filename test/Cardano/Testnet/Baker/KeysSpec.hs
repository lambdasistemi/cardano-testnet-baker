{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.Testnet.Baker.KeysSpec
Description : Deterministic key envelope tests.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0
-}
module Cardano.Testnet.Baker.KeysSpec
    ( spec
    ) where

import Cardano.Testnet.Baker.Keys
    ( FaucetKeyArtifacts (..)
    , PoolKeyArtifacts (..)
    , deriveFaucetKeyArtifacts
    , derivePoolKeyArtifacts
    )
import Cardano.Testnet.Baker.Scenario
    ( FaucetDeclaration (..)
    , PoolDeclaration (..)
    )
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    , shouldNotBe
    , shouldSatisfy
    )

spec :: Spec
spec = describe "deterministic key envelopes" $ do
    it "derives stable pool key envelopes for identical inputs" $
        derivePoolKeyArtifacts seed pool
            `shouldBe` derivePoolKeyArtifacts seed pool

    it "separates pool key labels" $
        poolColdSigningEnvelope (derivePoolKeyArtifacts seed pool)
            `shouldNotBe` poolColdSigningEnvelope
                (derivePoolKeyArtifacts seed pool{poolColdKeyLabel = "other"})

    it "renders pool signing keys as Cardano text envelopes" $
        poolColdSigningEnvelope (derivePoolKeyArtifacts seed pool)
            `shouldSatisfy` isTextEnvelope

    it "renders faucet payment keys as Cardano text envelopes" $
        faucetPaymentSigningEnvelope
            (deriveFaucetKeyArtifacts seed faucet)
            `shouldSatisfy` isTextEnvelope

seed :: BS.ByteString
seed = "deterministic scenario seed"

pool :: PoolDeclaration
pool =
    PoolDeclaration
        { poolLabel = "pool-a"
        , poolPledge = 1000000000
        , poolCost = 340000000
        , poolMargin = 0.05
        , poolStake = 1000000000
        , poolColdKeyLabel = "pool-a-cold"
        , poolVrfKeyLabel = "pool-a-vrf"
        , poolKesKeyLabel = "pool-a-kes"
        , poolStakeKeyLabel = "pool-a-stake"
        }

faucet :: FaucetDeclaration
faucet =
    FaucetDeclaration
        { faucetLabel = "faucet"
        , faucetPaymentKeyLabel = "faucet-payment"
        , faucetLovelace = 1000000000
        , faucetMetadata = Nothing
        }

isTextEnvelope :: LBS.ByteString -> Bool
isTextEnvelope bytes =
    BS.isInfixOf "\"type\"" strictBytes
        && BS.isInfixOf "\"description\"" strictBytes
        && BS.isInfixOf "\"cborHex\"" strictBytes
  where
    strictBytes = LBS.toStrict bytes
