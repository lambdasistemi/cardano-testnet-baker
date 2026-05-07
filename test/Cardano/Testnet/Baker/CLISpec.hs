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
import Data.List (isInfixOf)
import System.Directory
    ( createDirectoryIfMissing
    , doesPathExist
    , removePathForcibly
    )
import System.FilePath ((</>))
import Test.Hspec
    ( Spec
    , describe
    , expectationFailure
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

    it "bakes a genesis-only scenario file" $
        withScratch "bake-minimal" $ \root -> do
            let outputDir = root </> "minimal"

            result <-
                runBakeOptions
                    BakeOptions
                        { bakeScenarioPath =
                            "test/data/minimal-scenario.json"
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

    it "reports synthesis validation failures without publishing output" $
        withScratch "invalid-synthesis-bake" $ \root -> do
            let scenarioPath = root </> "bad-synthesis.json"
                outputDir = root </> "out"
            writeFile scenarioPath synthesisMissingSlotCountScenario

            result <-
                runBakeOptions
                    BakeOptions
                        { bakeScenarioPath = scenarioPath
                        , bakeOutputDir = outputDir
                        }

            pure result
                `shouldReturnLeftContaining` "synthesis slotCount is required when enabled"
            doesPathExist outputDir `shouldReturn` False

    it
        "reports non-positive synthesis slot counts with the offending value"
        $ withScratch "invalid-synthesis-slot-count"
        $ \root -> do
            let scenarioPath = root </> "bad-synthesis-slot-count.json"
            writeFile scenarioPath synthesisZeroSlotCountScenario

            runScenarioValidate scenarioPath
                `shouldReturnLeftContaining` "synthesis slotCount must be positive, got 0"

    it "reports empty synthesis profiles" $
        withScratch "invalid-synthesis-profile" $ \root -> do
            let scenarioPath = root </> "bad-synthesis-profile.json"
            writeFile scenarioPath synthesisEmptyProfileScenario

            runScenarioValidate scenarioPath
                `shouldReturnLeftContaining` "synthesis profile must be non-empty when present"

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

shouldReturnLeftContaining :: IO (Either String a) -> String -> IO ()
shouldReturnLeftContaining action expected = do
    result <- action
    case result of
        Left err ->
            err `shouldSatisfy` isInfixOf expected
        Right _ ->
            expectationFailure "expected validation failure"

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

synthesisMissingSlotCountScenario :: String
synthesisMissingSlotCountScenario =
    synthesisScenario "{\"enabled\":true}"

synthesisZeroSlotCountScenario :: String
synthesisZeroSlotCountScenario =
    synthesisScenario "{\"enabled\":true,\"slotCount\":0}"

synthesisEmptyProfileScenario :: String
synthesisEmptyProfileScenario =
    synthesisScenario
        "{\"enabled\":true,\"slotCount\":1,\"profile\":\"\"}"

synthesisScenario :: String -> String
synthesisScenario synthesis =
    "{\
    \\"schemaVersion\":1,\
    \\"scenarioId\":\"bad-synthesis\",\
    \\"seed\":\"00\",\
    \\"network\":{\"networkMagic\":42,\"networkId\":\"Testnet\"},\
    \\"eraSchedule\":{\"shelley\":0,\"alonzo\":0,\"conway\":0},\
    \\"genesis\":{\"epochLength\":120,\"activeSlotsCoeff\":0.05,\"securityParam\":10,\"k\":1,\"maxLovelaceSupply\":1000000},\
    \\"pools\":[{\"label\":\"pool-a\",\"pledge\":1,\"cost\":1,\"margin\":0.0,\"stake\":1,\"coldKeyLabel\":\"cold\",\"vrfKeyLabel\":\"vrf\",\"kesKeyLabel\":\"kes\",\"stakeKeyLabel\":\"stake\"}],\
    \\"faucets\":[{\"label\":\"faucet\",\"paymentKeyLabel\":\"payment\",\"lovelace\":1}],\
    \\"synthesis\":"
        <> synthesis
        <> "\
           \}"
