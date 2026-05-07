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
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (for_)
import Data.List (sort)
import System.Directory
    ( createDirectoryIfMissing
    , doesDirectoryExist
    , doesPathExist
    , listDirectory
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
spec = describe "bake output layout" $ do
    it "publishes the required MVP artifact paths" $
        withScratch "layout" $ \root -> do
            (scenarioBytes, scenario) <- loadMinimalScenario
            let outputDir = root </> "out"

            result <- runBake scenarioBytes scenario outputDir

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

            result <- runBake scenarioBytes scenario outputDir

            result
                `shouldBe` Left (BakeOutputDirectoryNotEmpty outputDir)
            doesPathExist existingFile `shouldReturn` True

    it "removes a stale staging directory before publishing" $
        withScratch "stale-staging" $ \root -> do
            (scenarioBytes, scenario) <- loadMinimalScenario
            let outputDir = root </> "out"
                stagingDir = root </> ".out.staging"
                staleFile = stagingDir </> "stale.txt"
            createDirectoryIfMissing True stagingDir
            writeFile staleFile "stale"

            result <- runBake scenarioBytes scenario outputDir

            result `shouldBe` Right (BakeOutput outputDir)
            doesPathExist staleFile `shouldReturn` False
            doesPathExist stagingDir `shouldReturn` False
            doesPathExist (outputDir </> "metadata.json")
                `shouldReturn` True

    it "writes byte-identical output across two runs" $
        withScratch "two-run-determinism" $ \root -> do
            (scenarioBytes, scenario) <- loadMinimalScenario
            let outputA = root </> "out-a"
                outputB = root </> "out-b"

            resultA <- runBake scenarioBytes scenario outputA
            resultB <- runBake scenarioBytes scenario outputB

            resultA `shouldBe` Right (BakeOutput outputA)
            resultB `shouldBe` Right (BakeOutput outputB)
            assertEqualTrees outputA outputB

    it "writes generated key files as text envelopes" $
        withScratch "key-envelopes" $ \root -> do
            (scenarioBytes, scenario) <- loadMinimalScenario
            let outputDir = root </> "out"

            result <- runBake scenarioBytes scenario outputDir

            result `shouldBe` Right (BakeOutput outputDir)
            coldKey <-
                LBS.readFile $
                    outputDir </> "pools/pool-a/keys/cold.skey"
            coldKey `shouldSatisfy` isTextEnvelope

loadMinimalScenario :: IO (LBS.ByteString, Scenario)
loadMinimalScenario = do
    scenarioBytes <- LBS.readFile "test/data/minimal-scenario.json"
    case decodeScenarioBytes scenarioBytes of
        Left err -> fail err
        Right scenario -> pure (scenarioBytes, scenario)

runBake
    :: LBS.ByteString
    -> Scenario
    -> FilePath
    -> IO (Either BakeError BakeOutput)
runBake scenarioBytes scenario outputDir =
    bakeScenario
        BakeRequest
            { bakeRequestScenario = scenario
            , bakeRequestScenarioBytes = scenarioBytes
            , bakeRequestOutputDir = outputDir
            , bakeRequestBakerCommit = "test"
            }

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

assertEqualTrees :: FilePath -> FilePath -> IO ()
assertEqualTrees left right = do
    leftFiles <- recursiveFiles left
    rightFiles <- recursiveFiles right
    leftFiles `shouldBe` rightFiles
    for_ leftFiles $ \relativePath -> do
        leftBytes <- LBS.readFile (left </> relativePath)
        rightBytes <- LBS.readFile (right </> relativePath)
        leftBytes `shouldBe` rightBytes

recursiveFiles :: FilePath -> IO [FilePath]
recursiveFiles root =
    go ""
  where
    go relative = do
        let dir = if null relative then root else root </> relative
        entries <- sort <$> listDirectory dir
        concat <$> traverse (collect relative) entries

    collect relative entry = do
        let relativePath =
                if null relative
                    then entry
                    else relative </> entry
            fullPath = root </> relativePath
        isDirectory <- doesDirectoryExist fullPath
        if isDirectory
            then go relativePath
            else pure [relativePath]

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

isTextEnvelope :: LBS.ByteString -> Bool
isTextEnvelope bytes =
    BS.isInfixOf "\"type\"" strictBytes
        && BS.isInfixOf "\"description\"" strictBytes
        && BS.isInfixOf "\"cborHex\"" strictBytes
  where
    strictBytes = LBS.toStrict bytes
