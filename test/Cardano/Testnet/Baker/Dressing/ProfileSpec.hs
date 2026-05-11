{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.Testnet.Baker.Dressing.ProfileSpec
Description : Unit tests for applyProfile structure.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0
-}
module Cardano.Testnet.Baker.Dressing.ProfileSpec
    ( spec
    ) where

import Cardano.Testnet.Baker.Dressing.Profile
    ( BakedOutput (..)
    , DressedOutput (..)
    , PoolBaked (..)
    , applyProfile
    )
import Cardano.Testnet.Baker.Dressing.Profiles.AntithesisConfigurator
    ( antithesisConfigurator
    )
import Cardano.Testnet.Baker.Dressing.Runtime
    ( RuntimeOverrides (..)
    )
import Data.Aeson (Value (Null), object, (.=))
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as T
import Test.Hspec
    ( Spec
    , describe
    , expectationFailure
    , it
    , shouldBe
    , shouldContain
    )

{- | A minimal stub baker output whose JSON values are placeholders.
Sufficient for asserting the path/shape contract; the byte content
of keys is irrelevant here, so we synthesize a recognizable tag
per pool.  AntithesisConfiguratorSpec compares against the golden
fixture for the content contract.
-}
stubBaked :: Int -> BakedOutput
stubBaked n =
    BakedOutput
        { bakedGenesisFiles =
            Map.fromList
                [ ("config.json", object ["stub" .= ("config" :: String)])
                ,
                    ( "alonzo-genesis.json"
                    , object
                        [ "maxTxExUnits"
                            .= object ["exUnitsMem" .= (0 :: Int), "exUnitsSteps" .= (0 :: Int)]
                        , "maxBlockExUnits"
                            .= object ["exUnitsMem" .= (0 :: Int), "exUnitsSteps" .= (0 :: Int)]
                        ]
                    )
                , ("byron-genesis.json", object [])
                , ("conway-genesis.json", object [])
                , ("shelley-genesis.json", object [])
                ]
        , bakedPools =
            [ PoolBaked
                { poolBakedLabel = "pool-" <> labelFor i
                , poolBakedKeys =
                    Map.fromList
                        [ ("kes.skey", tag i "kes")
                        , ("vrf.skey", tag i "vrf")
                        , ("opcert.cert", tag i "opcert")
                        ]
                }
            | i <- [1 .. n]
            ]
        , bakedUtxoKeys =
            Map.fromList
                [ ("genesis.1.skey", "stub-utxo-key")
                , ("genesis.1.addr.info", "stub-addr-info")
                ]
        }
  where
    tag i s = T.encodeUtf8 (T.pack ("pool-" <> show i <> "-" <> s))
    labelFor :: Int -> Text
    labelFor 1 = "a"
    labelFor 2 = "b"
    labelFor 3 = "c"
    labelFor i = T.pack ("x" <> show i)

zeroOverrides :: RuntimeOverrides
zeroOverrides =
    RuntimeOverrides
        { systemStartUnix = 0
        , systemStartIso = "1970-01-01T00:00:00Z"
        }

spec :: Spec
spec = describe "Cardano.Testnet.Baker.Dressing.Profile" $ do
    describe "applyProfile produces the expected file layout" $ do
        let baked = stubBaked 3
            dressed = applyProfile antithesisConfigurator baked zeroOverrides

        it "emits 6 JSON files per pool (3 pools = 18 files)" $
            length (Map.keys (dressedJsonFiles dressed)) `shouldBe` 18

        it "writes config.json into each pool's configs dir" $ do
            jsonPaths dressed `shouldContain` ["p1/configs/config.json"]
            jsonPaths dressed `shouldContain` ["p2/configs/config.json"]
            jsonPaths dressed `shouldContain` ["p3/configs/config.json"]

        it "writes topology.json into each pool's configs dir" $ do
            jsonPaths dressed `shouldContain` ["p1/configs/topology.json"]
            jsonPaths dressed `shouldContain` ["p2/configs/topology.json"]
            jsonPaths dressed `shouldContain` ["p3/configs/topology.json"]

        it "writes the four genesis files into each pool's configs dir" $
            mapM_
                ( \f ->
                    jsonPaths dressed `shouldContain` ["p1/configs/" <> f]
                )
                [ "alonzo-genesis.json"
                , "byron-genesis.json"
                , "conway-genesis.json"
                , "shelley-genesis.json"
                ]

        it "writes 3 key files per pool (3 pools = 9 + 2 utxo-keys)" $
            length (Map.keys (dressedByteFiles dressed)) `shouldBe` 9 + 2

        it "writes the three keys into each pool's keys dir" $
            mapM_
                ( \f ->
                    bytePaths dressed `shouldContain` ["p1/keys/" <> f]
                )
                ["kes.skey", "vrf.skey", "opcert.cert"]

        it "passes utxo-keys through under utxo-keys/" $
            bytePaths dressed `shouldContain` ["utxo-keys/genesis.1.skey"]

    describe "applyProfile is pure" $ do
        let baked = stubBaked 3
            r1 = applyProfile antithesisConfigurator baked zeroOverrides
            r2 = applyProfile antithesisConfigurator baked zeroOverrides
        it "produces identical output on identical input" $
            r1 `shouldBe` r2

    describe "applyProfile uses the bakedPools positional order" $ do
        let baked = stubBaked 3
            dressed = applyProfile antithesisConfigurator baked zeroOverrides
            kesPaths =
                filter
                    (\p -> takeBaseFile p == "kes.skey")
                    (Map.keys (dressedByteFiles dressed))
        it "produces kes.skey for p1, p2, p3 in that order" $
            sort kesPaths
                `shouldBe` [ "p1/keys/kes.skey"
                           , "p2/keys/kes.skey"
                           , "p3/keys/kes.skey"
                           ]

    describe "applyProfile placeholder JSON" $ do
        let baked = stubBaked 1
            dressed = applyProfile antithesisConfigurator baked zeroOverrides
        it "writes a non-null config.json under p1" $
            case Map.lookup "p1/configs/config.json" (dressedJsonFiles dressed) of
                Just Null -> expectationFailure "config.json should not be Null"
                Just _ -> pure ()
                Nothing -> expectationFailure "config.json missing from p1"
  where
    jsonPaths = Map.keys . dressedJsonFiles
    bytePaths = Map.keys . dressedByteFiles
    takeBaseFile = reverse . takeWhile (/= '/') . reverse
