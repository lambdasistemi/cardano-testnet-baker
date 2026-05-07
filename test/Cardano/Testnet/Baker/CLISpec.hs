{- |
Module      : Cardano.Testnet.Baker.CLISpec
Description : CLI parser tests.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0
-}
module Cardano.Testnet.Baker.CLISpec
    ( spec
    ) where

import Cardano.Testnet.Baker.CLI
    ( BakeOptions (..)
    , Command (..)
    , ScenarioCommand (..)
    , parseCommandArgs
    )
import Data.Either (isLeft)
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = describe "CLI parser" $ do
    it "parses scenario validation" $
        parseCommandArgs
            ["scenario", "validate", "examples/scenarios/local-fast.json"]
            `shouldBe` Right
                ( CommandScenario
                    ( ScenarioValidate
                        "examples/scenarios/local-fast.json"
                    )
                )

    it "parses bake inputs" $
        parseCommandArgs
            [ "bake"
            , "--scenario"
            , "examples/scenarios/local-fast.json"
            , "--out"
            , "out/local-fast"
            ]
            `shouldBe` Right
                ( CommandBake
                    BakeOptions
                        { bakeScenarioPath =
                            "examples/scenarios/local-fast.json"
                        , bakeOutputDir = "out/local-fast"
                        }
                )

    it "rejects bake without an output directory" $
        parseCommandArgs
            ["bake", "--scenario", "examples/scenarios/local-fast.json"]
            `shouldSatisfy` isLeft
