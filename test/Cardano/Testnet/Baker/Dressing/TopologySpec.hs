{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.Testnet.Baker.Dressing.TopologySpec
Description : Unit tests for the dressing Topology renderer.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0
-}
module Cardano.Testnet.Baker.Dressing.TopologySpec
    ( spec
    ) where

import Cardano.Testnet.Baker.Dressing.Layout
    ( NumPools (..)
    , PoolIx (..)
    , antithesisLayout
    , layoutPoolHost
    )
import Cardano.Testnet.Baker.Dressing.Topology
    ( Topology (..)
    , antithesisTopology
    , renderTopology
    )
import Data.Aeson
    ( Value (Array, Object, String)
    )
import Data.Aeson.KeyMap qualified as KM
import Data.Text (Text)
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    )

-- | Convert the rendered topology to the access-point host list.
accessPointHosts :: Value -> [Text]
accessPointHosts (Object o) =
    case KM.lookup "localRoots" o of
        Just (Array roots) ->
            concatMap rootHosts roots
        _ -> []
  where
    rootHosts (Object r) = case KM.lookup "accessPoints" r of
        Just (Array aps) -> mapMaybeHost aps
        _ -> []
    rootHosts _ = []

    mapMaybeHost = foldr step []
    step (Object ap) acc = case KM.lookup "address" ap of
        Just (String t) -> t : acc
        _ -> acc
    step _ acc = acc
accessPointHosts _ = []

spec :: Spec
spec = describe "Cardano.Testnet.Baker.Dressing.Topology" $ do
    let hostOf = layoutPoolHost antithesisLayout

    describe "Ring with 3 pools matches the configurator output" $ do
        let render i =
                accessPointHosts $
                    renderTopology
                        antithesisTopology
                        hostOf
                        (PoolIx i)
                        (NumPools 3)
        it "p1 connects to p3 then p2" $
            render 1 `shouldBe` ["p3.example", "p2.example"]
        it "p2 connects to p1 then p3" $
            render 2 `shouldBe` ["p1.example", "p3.example"]
        it "p3 connects to p2 then p1" $
            render 3 `shouldBe` ["p2.example", "p1.example"]

    describe "Ring wraps the boundaries for any pool count" $ do
        let render n i =
                accessPointHosts $
                    renderTopology
                        antithesisTopology
                        hostOf
                        (PoolIx i)
                        (NumPools n)
        it "5-pool ring: pool 1 -> pool 5, pool 2" $
            render 5 1 `shouldBe` ["p5.example", "p2.example"]
        it "5-pool ring: pool 5 -> pool 4, pool 1" $
            render 5 5 `shouldBe` ["p4.example", "p1.example"]

    describe "antithesisTopology" $
        it "is Ring 2 advertised + trustable" $
            antithesisTopology
                `shouldBe` Ring
                    { ringValency = 2
                    , ringAdvertise = True
                    , ringTrustable = True
                    }
