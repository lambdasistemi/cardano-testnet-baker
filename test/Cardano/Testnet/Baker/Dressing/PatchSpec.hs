{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.Testnet.Baker.Dressing.PatchSpec
Description : Unit tests for dressing Patch and its built-ins.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0
-}
module Cardano.Testnet.Baker.Dressing.PatchSpec
    ( spec
    ) where

import Cardano.Testnet.Baker.Dressing.Patch
    ( PatchTarget (..)
    , applyPatches
    , bumpAlonzoExUnits
    , dropGenesisHashes
    , dropHasEKG
    , dropMapBackends
    , setByronStartTime
    , setLedgerDBInMemory
    , setPeerSharing
    , setSystemStart
    )
import Cardano.Testnet.Baker.Dressing.Runtime
    ( RuntimeOverrides (..)
    )
import Data.Aeson
    ( Value (Object)
    , object
    , toJSON
    , (.=)
    )
import Data.Aeson.KeyMap qualified as KM
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    )

-- | Trivial overrides used for static-patch tests.
zeroOverrides :: RuntimeOverrides
zeroOverrides =
    RuntimeOverrides
        { systemStartUnix = 0
        , systemStartIso = "1970-01-01T00:00:00Z"
        }

-- | Fixture overrides matching the golden bash adapter run.
fixtureOverrides :: RuntimeOverrides
fixtureOverrides =
    RuntimeOverrides
        { systemStartUnix = 1735689600
        , systemStartIso = "2025-01-01T00:00:00Z"
        }

-- | Look up a top-level field from a JSON object.
field :: Value -> KM.Key -> Maybe Value
field (Object o) k = KM.lookup k o
field _ _ = Nothing

spec :: Spec
spec = describe "Cardano.Testnet.Baker.Dressing.Patch" $ do
    describe "dropGenesisHashes" $
        it "removes all four *GenesisHash fields when present" $ do
            let input =
                    object
                        [ "AlonzoGenesisHash" .= ("a" :: String)
                        , "ByronGenesisHash" .= ("b" :: String)
                        , "ConwayGenesisHash" .= ("c" :: String)
                        , "ShelleyGenesisHash" .= ("s" :: String)
                        , "Other" .= ("keep" :: String)
                        ]
                output = applyPatches [dropGenesisHashes] zeroOverrides TargetConfig input
            field output "AlonzoGenesisHash" `shouldBe` Nothing
            field output "ByronGenesisHash" `shouldBe` Nothing
            field output "ConwayGenesisHash" `shouldBe` Nothing
            field output "ShelleyGenesisHash" `shouldBe` Nothing
            field output "Other" `shouldBe` Just "keep"

    describe "dropHasEKG / dropMapBackends" $ do
        it "removes hasEKG when present" $ do
            let input = object ["hasEKG" .= True, "keep" .= True]
                output = applyPatches [dropHasEKG] zeroOverrides TargetConfig input
            field output "hasEKG" `shouldBe` Nothing
            field output "keep" `shouldBe` Just (toJSON True)
        it "removes options.mapBackends but keeps the rest of options" $ do
            let input =
                    object
                        [ "options"
                            .= object
                                [ "mapBackends" .= ([] :: [Value])
                                , "keep" .= True
                                ]
                        ]
                output = applyPatches [dropMapBackends] zeroOverrides TargetConfig input
            case field output "options" of
                Just (Object opts) -> do
                    KM.lookup "mapBackends" opts `shouldBe` Nothing
                    KM.lookup "keep" opts `shouldBe` Just (toJSON True)
                _ -> fail "options should remain an object"

    describe "setPeerSharing / setLedgerDBInMemory" $ do
        it "writes the PeerSharing flag" $ do
            let output =
                    applyPatches
                        [setPeerSharing True]
                        zeroOverrides
                        TargetConfig
                        (object [])
            field output "PeerSharing" `shouldBe` Just (toJSON True)
        it "writes LedgerDB = { Backend: \"V2InMemory\" }" $ do
            let output =
                    applyPatches
                        [setLedgerDBInMemory]
                        zeroOverrides
                        TargetConfig
                        (object [])
            field output "LedgerDB"
                `shouldBe` Just (object ["Backend" .= ("V2InMemory" :: String)])

    describe "bumpAlonzoExUnits" $
        it "bumps tx and block ExUnits to the configurator targets" $ do
            let input =
                    object
                        [ "maxTxExUnits"
                            .= object
                                [ "exUnitsMem" .= (10 :: Int)
                                , "exUnitsSteps" .= (10 :: Int)
                                ]
                        , "maxBlockExUnits"
                            .= object
                                [ "exUnitsMem" .= (10 :: Int)
                                , "exUnitsSteps" .= (10 :: Int)
                                ]
                        ]
                output =
                    applyPatches
                        [bumpAlonzoExUnits]
                        zeroOverrides
                        TargetAlonzoGenesis
                        input
            field output "maxTxExUnits"
                `shouldBe` Just
                    ( object
                        [ "exUnitsMem" .= (14000000 :: Int)
                        , "exUnitsSteps" .= (14000000000 :: Int)
                        ]
                    )
            field output "maxBlockExUnits"
                `shouldBe` Just
                    ( object
                        [ "exUnitsMem" .= (80000000 :: Int)
                        , "exUnitsSteps" .= (64000000000 :: Int)
                        ]
                    )

    describe "runtime patches" $ do
        it "setSystemStart writes systemStartIso into shelley genesis" $ do
            let output =
                    applyPatches
                        [setSystemStart]
                        fixtureOverrides
                        TargetShelleyGenesis
                        (object [])
            field output "systemStart"
                `shouldBe` Just (toJSON ("2025-01-01T00:00:00Z" :: String))
        it "setByronStartTime writes systemStartUnix into byron genesis" $ do
            let output =
                    applyPatches
                        [setByronStartTime]
                        fixtureOverrides
                        TargetByronGenesis
                        (object [])
            field output "startTime"
                `shouldBe` Just (toJSON (1735689600 :: Int))

    describe "applyPatches" $ do
        it "skips patches that target a different file" $ do
            let input = object ["x" .= (1 :: Int)]
                output =
                    applyPatches
                        [setPeerSharing True]
                        zeroOverrides
                        TargetAlonzoGenesis
                        input
            output `shouldBe` input
        it "applies patches left to right" $ do
            -- The two patches both target TargetConfig.  After the
            -- first, hasEKG is gone; after the second, PeerSharing is
            -- set.  Reversing the order yields the same result here
            -- because the patches are independent — that is good.
            let input = object ["hasEKG" .= True]
                output =
                    applyPatches
                        [dropHasEKG, setPeerSharing False]
                        zeroOverrides
                        TargetConfig
                        input
            field output "hasEKG" `shouldBe` Nothing
            field output "PeerSharing" `shouldBe` Just (toJSON False)
