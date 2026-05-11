{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.Testnet.Baker.Dressing.RuntimeSpec
Description : Unit tests for the dressing RuntimeMold.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0
-}
module Cardano.Testnet.Baker.Dressing.RuntimeSpec
    ( spec
    ) where

import Cardano.Testnet.Baker.Dressing.Runtime
    ( Now (..)
    , RuntimeMold (..)
    , RuntimeOverrides (..)
    , antithesisRuntime
    , runtimeOverrides
    )
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    , shouldSatisfy
    )

spec :: Spec
spec = describe "Cardano.Testnet.Baker.Dressing.Runtime" $ do
    describe "antithesisRuntime aligned values" $ do
        let ro = runtimeOverrides antithesisRuntime
        it "1735689600 (aligned) round-trips" $ do
            ro (Now 1735689600)
                `shouldBe` RuntimeOverrides
                    { systemStartUnix = 1735689600
                    , systemStartIso = "2025-01-01T00:00:00Z"
                    }
        it "rounds 1735689659 down to the 120 s boundary" $
            systemStartUnix (ro (Now 1735689659)) `shouldBe` 1735689600
        it "rounds 1735689720 (aligned again) unchanged" $
            systemStartUnix (ro (Now 1735689720)) `shouldBe` 1735689720

    describe "alignment is idempotent" $ do
        let ro = runtimeOverrides antithesisRuntime
            once t = systemStartUnix (ro (Now (fromIntegral t)))
            twice t = once (once t)
        it "applying alignment twice yields the same value (1735689659)" $
            twice (1735689659 :: Int) `shouldBe` once 1735689659
        it "applying alignment twice yields the same value (1735690000)" $
            twice (1735690000 :: Int) `shouldBe` once 1735690000

    describe "alignment never exceeds input" $ do
        let ro = runtimeOverrides antithesisRuntime
        it "for 1735689659 returns <= 1735689659" $
            systemStartUnix (ro (Now 1735689659))
                `shouldSatisfy` (<= 1735689659)
        it "for 1735690000 returns <= 1735690000" $
            systemStartUnix (ro (Now 1735690000))
                `shouldSatisfy` (<= 1735690000)

    describe "alignment quantum is divisible" $ do
        let RuntimeMold{..} = antithesisRuntime
            ro = runtimeOverrides antithesisRuntime
        it "antithesisRuntime uses 120s alignment" $
            runtimeAlign `shouldBe` 120
        it "outputs are divisible by 120" $
            (systemStartUnix (ro (Now 1735689659)) `mod` runtimeAlign)
                `shouldBe` 0
