{- |
Module      : Cardano.Testnet.Baker.ComposeAcceptanceSpec
Description : Docker Compose acceptance harness tests.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0
-}
module Cardano.Testnet.Baker.ComposeAcceptanceSpec
    ( spec
    ) where

import Control.Exception (finally)
import Control.Monad (when)
import Data.Bits ((.&.))
import Data.List (isInfixOf)
import System.Directory
    ( createDirectoryIfMissing
    , doesPathExist
    , removePathForcibly
    )
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.Posix.Files
    ( fileMode
    , getFileStatus
    , ownerExecuteMode
    )
import System.Process (readProcessWithExitCode)
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    , shouldSatisfy
    )

spec :: Spec
spec = describe "compose acceptance harness" $ do
    it "pins the cardano-node image by digest and mounts assets read-only" $ do
        compose <- readFile "compose/acceptance/docker-compose.yaml"

        compose
            `shouldSatisfy` isInfixOf
                "ghcr.io/intersectmbo/cardano-node@sha256:3275d357053d21f3220f74b0854fd584e1fe322dfa1bbb78effd760c3191d14c"
        compose `shouldSatisfy` isInfixOf ":/assets:ro"

    it "keeps the acceptance scripts executable" $ do
        assertExecutable "compose/acceptance/run.sh"
        assertExecutable "compose/acceptance/patch-system-start.sh"

    it "runs the documented compose command lifecycle" $ do
        runScript <- readFile "compose/acceptance/run.sh"

        runScript `shouldSatisfy` isInfixOf "docker compose"
        runScript `shouldSatisfy` isInfixOf "patch-system-start.sh"
        runScript `shouldSatisfy` isInfixOf "Net\\.Server\\.Local\\.Started"
        runScript
            `shouldSatisfy` isInfixOf "down --volumes --remove-orphans"

    it "patches start times only in the runtime copy" $
        withScratch "patch-system-start" $ \root -> do
            let sourceDir = root </> "source"
                runtimeDir = root </> "runtime"
            writeGenesisPair sourceDir
            writeGenesisPair runtimeDir

            (exitCode, _stdout, stderr) <-
                readProcessWithExitCode
                    "env"
                    [ "ACCEPTANCE_SYSTEM_START=2030-01-02T03:04:05Z"
                    , "ACCEPTANCE_START_TIME=1893553445"
                    , "bash"
                    , "compose/acceptance/patch-system-start.sh"
                    , runtimeDir
                    ]
                    ""

            stderr `shouldBe` ""
            exitCode `shouldBe` ExitSuccess
            sourceShelley <-
                readFile $
                    sourceDir </> "genesis/shelley-genesis.json"
            runtimeShelley <-
                readFile $
                    runtimeDir </> "genesis/shelley-genesis.json"
            runtimeByron <-
                readFile $
                    runtimeDir </> "genesis/byron-genesis.json"
            sourceShelley `shouldSatisfy` not . isInfixOf "systemStart"
            runtimeShelley
                `shouldSatisfy` isInfixOf
                    "\"systemStart\": \"2030-01-02T03:04:05Z\""
            runtimeByron `shouldSatisfy` isInfixOf "\"startTime\": 1893553445"

assertExecutable :: FilePath -> IO ()
assertExecutable path = do
    status <- getFileStatus path
    fileMode status .&. ownerExecuteMode `shouldSatisfy` (/= 0)

writeGenesisPair :: FilePath -> IO ()
writeGenesisPair root = do
    let genesisDir = root </> "genesis"
    createDirectoryIfMissing True genesisDir
    writeFile
        (genesisDir </> "shelley-genesis.json")
        "{\"networkMagic\":42}\n"
    writeFile (genesisDir </> "byron-genesis.json") "{\"startTime\":0}\n"

withScratch :: FilePath -> (FilePath -> IO ()) -> IO ()
withScratch name action = do
    let root = "tmp/unit/compose-acceptance" </> name
    removeIfExists root
    createDirectoryIfMissing True root
    action root `finally` removeIfExists root

removeIfExists :: FilePath -> IO ()
removeIfExists path = do
    exists <- doesPathExist path
    when exists $
        removePathForcibly path
