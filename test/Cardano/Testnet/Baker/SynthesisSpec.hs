{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.Testnet.Baker.SynthesisSpec
Description : ChainDB synthesis preparation tests.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0
-}
module Cardano.Testnet.Baker.SynthesisSpec
    ( spec
    ) where

import Cardano.Testnet.Baker.Keys
    ( PoolKeyArtifacts (..)
    , derivePoolKeyArtifacts
    )
import Cardano.Testnet.Baker.Scenario (PoolDeclaration (..))
import Cardano.Testnet.Baker.Synthesis
    ( SynthesisError (..)
    , bulkCredentialFromPoolArtifacts
    , renderBulkCredentials
    )
import Data.Aeson (Value, eitherDecode)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Test.Hspec
    ( Spec
    , describe
    , expectationFailure
    , it
    , shouldBe
    )

spec :: Spec
spec = describe "synthesis bulk credentials" $ do
    it "renders one opcert/VRF/KES text-envelope tuple per pool" $ do
        let poolAArtifacts = derivePoolKeyArtifacts seed poolA
            poolBArtifacts = derivePoolKeyArtifacts seed poolB

        decoded <-
            decodeRendered $
                renderBulkCredentials
                    [ bulkCredentialFromPoolArtifacts poolAArtifacts
                    , bulkCredentialFromPoolArtifacts poolBArtifacts
                    ]

        decoded
            `shouldBe` [ expectedCredentialTuple poolAArtifacts
                       , expectedCredentialTuple poolBArtifacts
                       ]

    it "renders no credentials as the canonical empty JSON array" $
        renderBulkCredentials [] `shouldBe` Right "[]"

    it "rejects a malformed operational certificate envelope" $
        renderBulkCredentials
            [ bulkCredentialFromPoolArtifacts
                (poolArtifacts{poolOperationalCertificateEnvelope = "nope"})
            ]
            `shouldSatisfyLeft` \case
                SynthesisInvalidTextEnvelope
                    "operationalCertificate"
                    _ ->
                        True
                _ -> False

decodeRendered :: Either err LBS.ByteString -> IO [[Value]]
decodeRendered = \case
    Left _ ->
        expectationFailure "bulk credential rendering failed"
            >> pure []
    Right bytes ->
        case eitherDecode bytes of
            Left err -> expectationFailure err >> pure []
            Right credentials -> pure credentials

expectedCredentialTuple :: PoolKeyArtifacts -> [Value]
expectedCredentialTuple PoolKeyArtifacts{..} =
    [ decodeEnvelope poolOperationalCertificateEnvelope
    , decodeEnvelope poolVrfSigningEnvelope
    , decodeEnvelope poolKesSigningEnvelope
    ]

decodeEnvelope :: LBS.ByteString -> Value
decodeEnvelope bytes =
    case eitherDecode bytes of
        Left err -> error err
        Right value -> value

shouldSatisfyLeft :: Either err value -> (err -> Bool) -> IO ()
shouldSatisfyLeft actual predicate =
    case actual of
        Left err
            | predicate err -> pure ()
            | otherwise -> expectationFailure "unexpected Left value"
        Right _ -> expectationFailure "expected Left"

seed :: BS.ByteString
seed = "deterministic synthesis seed"

poolArtifacts :: PoolKeyArtifacts
poolArtifacts = derivePoolKeyArtifacts seed poolA

poolA :: PoolDeclaration
poolA =
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

poolB :: PoolDeclaration
poolB =
    PoolDeclaration
        { poolLabel = "pool-b"
        , poolPledge = 1000000000
        , poolCost = 340000000
        , poolMargin = 0.05
        , poolStake = 1000000000
        , poolColdKeyLabel = "pool-b-cold"
        , poolVrfKeyLabel = "pool-b-vrf"
        , poolKesKeyLabel = "pool-b-kes"
        , poolStakeKeyLabel = "pool-b-stake"
        }
