{- |
Module      : Cardano.Testnet.Baker.BakeSpec
Description : Bake output layout tests.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0
-}
module Cardano.Testnet.Baker.BakeSpec
    ( spec
    ) where

import Cardano.Testnet.Baker.Bake
    ( BakeError (..)
    , BakeOutput (..)
    , BakeRequest (..)
    , bakeScenario
    )
import Cardano.Testnet.Baker.Scenario
    ( Scenario
    , decodeScenarioBytes
    )
import Control.Exception (finally)
import Control.Monad (when)
import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (for_)
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
    )

spec :: Spec
spec = describe "bake output layout" $ do
    it "publishes the required MVP artifact paths" $
        withScratch "layout" $ \root -> do
            (scenarioBytes, scenario) <- loadMinimalScenario
            let outputDir = root </> "out"

            result <-
                bakeScenario
                    BakeRequest
                        { bakeRequestScenario = scenario
                        , bakeRequestScenarioBytes = scenarioBytes
                        , bakeRequestOutputDir = outputDir
                        , bakeRequestBakerCommit = "test"
                        }

            result `shouldBe` Right (BakeOutput outputDir)
            for_ requiredPaths $ \relativePath ->
                doesPathExist (outputDir </> relativePath)
                    `shouldReturn` True

    it "rejects a non-empty output directory without deleting it" $
        withScratch "non-empty-output" $ \root -> do
            (scenarioBytes, scenario) <- loadMinimalScenario
            let outputDir = root </> "out"
                existingFile = outputDir </> "existing.txt"
            createDirectoryIfMissing True outputDir
            writeFile existingFile "existing"

            result <-
                bakeScenario
                    BakeRequest
                        { bakeRequestScenario = scenario
                        , bakeRequestScenarioBytes = scenarioBytes
                        , bakeRequestOutputDir = outputDir
                        , bakeRequestBakerCommit = "test"
                        }

            result
                `shouldBe` Left (BakeOutputDirectoryNotEmpty outputDir)
            doesPathExist existingFile `shouldReturn` True

loadMinimalScenario :: IO (LBS.ByteString, Scenario)
loadMinimalScenario = do
    scenarioBytes <- LBS.readFile "test/data/minimal-scenario.json"
    case decodeScenarioBytes scenarioBytes of
        Left err -> fail err
        Right scenario -> pure (scenarioBytes, scenario)

withScratch :: FilePath -> (FilePath -> IO ()) -> IO ()
withScratch name action = do
    let root = "tmp/unit" </> name
    removeIfExists root
    createDirectoryIfMissing True root
    action root `finally` removeIfExists root

removeIfExists :: FilePath -> IO ()
removeIfExists path = do
    exists <- doesPathExist path
    when exists $
        removePathForcibly path

requiredPaths :: [FilePath]
requiredPaths =
    [ "genesis/byron-genesis.json"
    , "genesis/shelley-genesis.json"
    , "genesis/alonzo-genesis.json"
    , "genesis/conway-genesis.json"
    , "genesis/config.json"
    , "pools/pool-a/keys/cold.skey"
    , "pools/pool-a/keys/cold.vkey"
    , "pools/pool-a/keys/kes.skey"
    , "pools/pool-a/keys/vrf.skey"
    , "pools/pool-a/keys/opcert.cert"
    , "pools/pool-a/keys/stake.skey"
    , "pools/pool-a/keys/stake.vkey"
    , "utxo-keys/faucet.skey"
    , "utxo-keys/faucet.addr.info"
    , "metadata.json"
    ]
