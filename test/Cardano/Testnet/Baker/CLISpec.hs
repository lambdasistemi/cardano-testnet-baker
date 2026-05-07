{- |
Module      : Cardano.Testnet.Baker.CLISpec
Description : CLI parser tests.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0
-}
module Cardano.Testnet.Baker.CLISpec
    ( spec
    ) where

import Cardano.Testnet.Baker.Bake (BakeOutput (..))
import Cardano.Testnet.Baker.CLI
    ( BakeOptions (..)
    , Command (..)
    , ScenarioCommand (..)
    , parseCommandArgs
    , runBakeOptions
    , runScenarioValidate
    )
import Control.Exception (finally)
import Control.Monad (when)
import Data.Either (isLeft)
import System.Directory
    ( createDirectoryIfMissing
    , doesPathExist
    , removePathForcibly
    )
import System.FilePath ((</>))
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    , shouldReturn
    , shouldSatisfy
    )

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

    it "validates a committed scenario file" $
        runScenarioValidate "examples/scenarios/local-fast.json"
            `shouldReturn` Right ()

    it "bakes a committed scenario file" $
        withScratch "bake-local-fast" $ \root -> do
            let outputDir = root </> "local-fast"

            result <-
                runBakeOptions
                    BakeOptions
                        { bakeScenarioPath =
                            "examples/scenarios/local-fast.json"
                        , bakeOutputDir = outputDir
                        }

            result `shouldBe` Right (BakeOutput outputDir)
            doesPathExist (outputDir </> "metadata.json")
                `shouldReturn` True

    it "returns an error for an invalid scenario file" $
        withScratch "invalid-scenario" $ \root -> do
            let scenarioPath = root </> "bad.json"
            writeFile scenarioPath invalidScenario

            runScenarioValidate scenarioPath `shouldSatisfyM` isLeft

    it "rejects baking an invalid scenario without publishing output" $
        withScratch "invalid-bake" $ \root -> do
            let scenarioPath = root </> "bad.json"
                outputDir = root </> "out"
            writeFile scenarioPath invalidScenario

            runBakeOptions
                BakeOptions
                    { bakeScenarioPath = scenarioPath
                    , bakeOutputDir = outputDir
                    }
                `shouldSatisfyM` isLeft
            doesPathExist outputDir `shouldReturn` False

withScratch :: FilePath -> (FilePath -> IO ()) -> IO ()
withScratch name action = do
    let root = "tmp/unit/cli" </> name
    removeIfExists root
    createDirectoryIfMissing True root
    action root `finally` removeIfExists root

removeIfExists :: FilePath -> IO ()
removeIfExists path = do
    exists <- doesPathExist path
    when exists $
        removePathForcibly path

shouldSatisfyM :: (Show a) => IO a -> (a -> Bool) -> IO ()
shouldSatisfyM action predicate = do
    value <- action
    value `shouldSatisfy` predicate

invalidScenario :: String
invalidScenario =
    "{\
    \\"schemaVersion\":1,\
    \\"scenarioId\":\"bad\",\
    \\"seed\":\"00\",\
    \\"network\":{\"networkMagic\":42,\"networkId\":\"Testnet\"},\
    \\"eraSchedule\":{\"shelley\":0,\"alonzo\":0,\"conway\":0},\
    \\"genesis\":{\"epochLength\":120,\"activeSlotsCoeff\":0.05,\"securityParam\":10,\"k\":1,\"maxLovelaceSupply\":1000000},\
    \\"pools\":[],\
    \\"faucets\":[]\
    \}"
