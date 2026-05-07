{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.Testnet.Baker.SynthesisSpec
Description : ChainDB synthesis preparation tests.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0
-}
module Cardano.Testnet.Baker.SynthesisSpec
    ( spec
    ) where

import Cardano.Testnet.Baker.Keys
    ( PoolKeyArtifacts (..)
    , derivePoolKeyArtifacts
    )
import Cardano.Testnet.Baker.Scenario (PoolDeclaration (..))
import Cardano.Testnet.Baker.Synthesis
    ( SynthesisError (..)
    , SynthesisRun (..)
    , bulkCredentialFromPoolArtifacts
    , dbSynthesizerRunner
    , renderBulkCredentials
    , runSynthesis
    )
import Control.Exception (finally)
import Control.Monad (when)
import Data.Aeson (Value, eitherDecode)
import Data.Bits ((.|.))
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import System.Directory
    ( createDirectoryIfMissing
    , doesDirectoryExist
    , doesPathExist
    , removePathForcibly
    )
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.Posix.Files
    ( ownerExecuteMode
    , ownerReadMode
    , ownerWriteMode
    , setFileMode
    )
import Test.Hspec
    ( Spec
    , describe
    , expectationFailure
    , it
    , shouldBe
    , shouldReturn
    )

spec :: Spec
spec = do
    describe "synthesis bulk credentials" $ do
        it "renders one opcert/VRF/KES text-envelope tuple per pool" $ do
            let poolAArtifacts = derivePoolKeyArtifacts seed poolA
                poolBArtifacts = derivePoolKeyArtifacts seed poolB

            decoded <-
                decodeRendered $
                    renderBulkCredentials
                        [ bulkCredentialFromPoolArtifacts poolAArtifacts
                        , bulkCredentialFromPoolArtifacts poolBArtifacts
                        ]

            decoded
                `shouldBe` [ expectedCredentialTuple poolAArtifacts
                           , expectedCredentialTuple poolBArtifacts
                           ]

        it "renders no credentials as the canonical empty JSON array" $
            renderBulkCredentials [] `shouldBe` Right "[]"

        it "rejects a malformed operational certificate envelope" $
            renderBulkCredentials
                [ bulkCredentialFromPoolArtifacts
                    (poolArtifacts{poolOperationalCertificateEnvelope = "nope"})
                ]
                `shouldSatisfyLeft` \case
                    SynthesisInvalidTextEnvelope
                        "operationalCertificate"
                        _ ->
                            True
                    _ -> False

    describe "db-synthesizer runner" $ do
        it "passes config, db, bulk credentials, and slot count arguments" $
            withScratch "runner-args" $ \root -> do
                let executable = root </> "db-synthesizer"
                    argsPath = root </> "args.txt"
                    chainDbPath = root </> "chain-db"
                    run =
                        SynthesisRun
                            { synthesisRunNodeConfigPath =
                                root </> "config.json"
                            , synthesisRunBulkCredentialsPath =
                                root </> "bulk-credentials.json"
                            , synthesisRunChainDbPath = chainDbPath
                            , synthesisRunSlotCount = 42
                            }
                writeExecutable
                    executable
                    [ "#!/usr/bin/env bash"
                    , "set -euo pipefail"
                    , "printf '%s\\n' \"$@\" > " <> argsPath
                    , "db=''"
                    , "while [[ $# -gt 0 ]]; do"
                    , "  case \"$1\" in"
                    , "    --db) db=\"$2\"; shift 2 ;;"
                    , "    *) shift ;;"
                    , "  esac"
                    , "done"
                    , "mkdir -p \"$db/immutable\""
                    ]

                result <- runSynthesis (dbSynthesizerRunner executable) run

                result `shouldBe` Right ()
                readFile argsPath
                    `shouldReturnLines` [ "--config"
                                        , synthesisRunNodeConfigPath run
                                        , "--db"
                                        , synthesisRunChainDbPath run
                                        , "--bulk-credentials-file"
                                        , synthesisRunBulkCredentialsPath run
                                        , "--slots"
                                        , "42"
                                        , "-f"
                                        ]
                doesDirectoryExist (chainDbPath </> "immutable")
                    `shouldReturn` True

        it "returns stdout and stderr when the synthesizer exits non-zero" $
            withScratch "runner-failure" $ \root -> do
                let executable = root </> "db-synthesizer"
                    run =
                        SynthesisRun
                            { synthesisRunNodeConfigPath =
                                root </> "config.json"
                            , synthesisRunBulkCredentialsPath =
                                root </> "bulk-credentials.json"
                            , synthesisRunChainDbPath =
                                root </> "chain-db"
                            , synthesisRunSlotCount = 1
                            }
                writeExecutable
                    executable
                    [ "#!/usr/bin/env bash"
                    , "echo out"
                    , "echo err >&2"
                    , "exit 23"
                    ]

                result <- runSynthesis (dbSynthesizerRunner executable) run

                result
                    `shouldBe` Left
                        ( SynthesisProcessFailed
                            executable
                            (ExitFailure 23)
                            "out\n"
                            "err\n"
                        )

decodeRendered :: Either err LBS.ByteString -> IO [[Value]]
decodeRendered = \case
    Left _ ->
        expectationFailure "bulk credential rendering failed"
            >> pure []
    Right bytes ->
        case eitherDecode bytes of
            Left err -> expectationFailure err >> pure []
            Right credentials -> pure credentials

expectedCredentialTuple :: PoolKeyArtifacts -> [Value]
expectedCredentialTuple PoolKeyArtifacts{..} =
    [ decodeEnvelope poolOperationalCertificateEnvelope
    , decodeEnvelope poolVrfSigningEnvelope
    , decodeEnvelope poolKesSigningEnvelope
    ]

decodeEnvelope :: LBS.ByteString -> Value
decodeEnvelope bytes =
    case eitherDecode bytes of
        Left err -> error err
        Right value -> value

shouldSatisfyLeft :: Either err value -> (err -> Bool) -> IO ()
shouldSatisfyLeft actual predicate =
    case actual of
        Left err
            | predicate err -> pure ()
            | otherwise -> expectationFailure "unexpected Left value"
        Right _ -> expectationFailure "expected Left"

shouldReturnLines :: IO String -> [String] -> IO ()
shouldReturnLines action expected = do
    actual <- lines <$> action
    actual `shouldBe` expected

withScratch :: FilePath -> (FilePath -> IO ()) -> IO ()
withScratch name action = do
    let root = "tmp/unit/synthesis" </> name
    removeIfExists root
    createDirectoryIfMissing True root
    action root `finally` removeIfExists root

removeIfExists :: FilePath -> IO ()
removeIfExists path = do
    exists <- doesPathExist path
    when exists $
        removePathForcibly path

writeExecutable :: FilePath -> [String] -> IO ()
writeExecutable path lines' = do
    writeFile path (unlines lines')
    setFileMode
        path
        (ownerReadMode .|. ownerWriteMode .|. ownerExecuteMode)

seed :: BS.ByteString
seed = "deterministic synthesis seed"

poolArtifacts :: PoolKeyArtifacts
poolArtifacts = derivePoolKeyArtifacts seed poolA

poolA :: PoolDeclaration
poolA =
    PoolDeclaration
        { poolLabel = "pool-a"
        , poolPledge = 1000000000
        , poolCost = 340000000
        , poolMargin = 0.05
        , poolStake = 1000000000
        , poolColdKeyLabel = "pool-a-cold"
        , poolVrfKeyLabel = "pool-a-vrf"
        , poolKesKeyLabel = "pool-a-kes"
        , poolStakeKeyLabel = "pool-a-stake"
        }

poolB :: PoolDeclaration
poolB =
    PoolDeclaration
        { poolLabel = "pool-b"
        , poolPledge = 1000000000
        , poolCost = 340000000
        , poolMargin = 0.05
        , poolStake = 1000000000
        , poolColdKeyLabel = "pool-b-cold"
        , poolVrfKeyLabel = "pool-b-vrf"
        , poolKesKeyLabel = "pool-b-kes"
        , poolStakeKeyLabel = "pool-b-stake"
        }
