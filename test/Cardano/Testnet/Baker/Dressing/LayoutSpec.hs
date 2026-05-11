{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.Testnet.Baker.Dressing.LayoutSpec
Description : Unit tests for the dressing Layout.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0
-}
module Cardano.Testnet.Baker.Dressing.LayoutSpec
    ( spec
    ) where

import Cardano.Testnet.Baker.Dressing.Layout
    ( Layout (..)
    , NumPools (..)
    , PoolIx (..)
    , antithesisLayout
    , poolIndices
    )
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    )

spec :: Spec
spec = describe "Cardano.Testnet.Baker.Dressing.Layout" $ do
    describe "poolIndices" $ do
        it "enumerates 1..n" $ do
            map unPoolIx (poolIndices (NumPools 3)) `shouldBe` [1, 2, 3]
        it "produces a single index for NumPools 1" $ do
            map unPoolIx (poolIndices (NumPools 1)) `shouldBe` [1]

    describe "antithesisLayout" $ do
        let l = antithesisLayout
        it "names pool dirs p<n>" $ do
            layoutPoolDir l (PoolIx 1) `shouldBe` "p1"
            layoutPoolDir l (PoolIx 2) `shouldBe` "p2"
            layoutPoolDir l (PoolIx 7) `shouldBe` "p7"
        it "names hosts p<n>.example" $ do
            layoutPoolHost l (PoolIx 1) `shouldBe` "p1.example"
            layoutPoolHost l (PoolIx 3) `shouldBe` "p3.example"
        it "uses 'configs' and 'keys' subdirs" $ do
            layoutConfigDir l `shouldBe` "configs"
            layoutKeyDir l `shouldBe` "keys"
