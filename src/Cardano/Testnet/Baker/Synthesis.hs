{- |
Module      : Cardano.Testnet.Baker.Synthesis
Description : ChainDB synthesis input preparation.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Prepares deterministic inputs for the stock upstream @db-synthesizer@
executable from already-generated bake artifacts.
-}
module Cardano.Testnet.Baker.Synthesis
    ( BulkCredential
    , ChainDbMeasurement (..)
    , SynthesisError (..)
    , SynthesisObservation (..)
    , SynthesisReport (..)
    , SynthesisRun (..)
    , SynthesisRunner (..)
    , bulkCredentialKesSigningKey
    , bulkCredentialOperationalCertificate
    , bulkCredentialVrfSigningKey
    , bulkCredentialFromPoolArtifacts
    , dbSynthesizerRunner
    , measureChainDb
    , renderBulkCredentials
    , renderSynthesisReport
    ) where

import Cardano.Testnet.Baker.Keys (PoolKeyArtifacts (..))
import Cardano.Testnet.Baker.Metadata
    ( Digest (..)
    , canonicalJsonBytes
    )
import Control.Exception (try)
import Crypto.Hash qualified as Crypto
import Data.Aeson
    ( Value
    , eitherDecode
    , object
    , toJSON
    , (.=)
    )
import Data.ByteString.Lazy qualified as LBS
import Data.Int (Int64)
import Data.List (sort)
import Data.Text (Text)
import Data.Text qualified as Text
import System.Directory
    ( doesDirectoryExist
    , getFileSize
    , listDirectory
    )
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.Process (readProcessWithExitCode)

-- | One producer credential tuple for @db-synthesizer@ bulk mode.
data BulkCredential = BulkCredential
    { bulkCredentialOperationalCertificate :: LBS.ByteString
    -- ^ Operational certificate text envelope.
    , bulkCredentialVrfSigningKey :: LBS.ByteString
    -- ^ VRF signing key text envelope.
    , bulkCredentialKesSigningKey :: LBS.ByteString
    -- ^ KES signing key text envelope.
    }
    deriving (Eq, Show)

-- | Failures while preparing synthesizer inputs from baked artifacts.
data SynthesisError
    = SynthesisInvalidTextEnvelope Text String
    | SynthesisInvalidGenesis FilePath String
    | SynthesisProcessFailed FilePath ExitCode String String
    | SynthesisProcessException FilePath String
    deriving (Eq, Show)

-- | Deterministic measurements for a completed ChainDB seed directory.
data ChainDbMeasurement = ChainDbMeasurement
    { chainDbBytes :: Integer
    -- ^ Sum of all regular file sizes under @chain-db/@.
    , chainDbFileCount :: Int
    -- ^ Number of regular files under @chain-db/@.
    , chainDbPackagedBytes :: Integer
    -- ^ Deterministic proxy for packaged size.
    }
    deriving (Eq, Show)

-- | Host-dependent observation captured around one synthesis run.
data SynthesisObservation = SynthesisObservation
    { observationWallTimeMilliseconds :: Integer
    , observationStartedAt :: Text
    , observationCompletedAt :: Text
    , observationHost :: Text
    }
    deriving (Eq, Show)

-- | Machine-readable report emitted beside deterministic metadata.
data SynthesisReport = SynthesisReport
    { reportScenarioId :: Text
    , reportScenarioDigest :: Digest
    , reportBakerVersion :: Text
    , reportSlotCount :: Int
    , reportProfile :: Maybe Text
    , reportChainDb :: ChainDbMeasurement
    , reportObservation :: SynthesisObservation
    }
    deriving (Eq, Show)

-- | One invocation of the upstream synthesizer.
data SynthesisRun = SynthesisRun
    { synthesisRunNodeConfigPath :: FilePath
    -- ^ Generated node @config.json@ path.
    , synthesisRunBulkCredentialsPath :: FilePath
    -- ^ Generated bulk credentials JSON path.
    , synthesisRunChainDbPath :: FilePath
    -- ^ Destination ChainDB seed directory.
    , synthesisRunSlotCount :: Int
    -- ^ Number of slots to synthesize.
    }
    deriving (Eq, Show)

-- | Effect boundary for producing a ChainDB seed.
newtype SynthesisRunner = SynthesisRunner
    { runSynthesis :: SynthesisRun -> IO (Either SynthesisError ())
    }

-- | Invoke the stock upstream @db-synthesizer@ executable.
dbSynthesizerRunner :: FilePath -> SynthesisRunner
dbSynthesizerRunner executable =
    SynthesisRunner $ \SynthesisRun{..} -> do
        result <-
            tryProcess $
                readProcessWithExitCode
                    executable
                    (synthesisArgs SynthesisRun{..})
                    ""
        pure $
            case result of
                Left err -> Left (SynthesisProcessException executable err)
                Right (ExitSuccess, _stdout, _stderr) -> Right ()
                Right (exitCode, stdout, stderr) ->
                    Left $
                        SynthesisProcessFailed
                            executable
                            exitCode
                            stdout
                            stderr

synthesisArgs :: SynthesisRun -> [String]
synthesisArgs SynthesisRun{..} =
    [ "--config"
    , synthesisRunNodeConfigPath
    , "--db"
    , synthesisRunChainDbPath
    , "--bulk-credentials-file"
    , synthesisRunBulkCredentialsPath
    , "--slots"
    , show synthesisRunSlotCount
    , "-f"
    ]

tryProcess :: IO a -> IO (Either String a)
tryProcess action = do
    result <- try action
    pure $
        case result of
            Left err -> Left (show (err :: IOError))
            Right value -> Right value

-- | Select the producer artifacts consumed by the synthesizer.
bulkCredentialFromPoolArtifacts
    :: PoolKeyArtifacts
    -> BulkCredential
bulkCredentialFromPoolArtifacts PoolKeyArtifacts{..} =
    BulkCredential
        { bulkCredentialOperationalCertificate =
            poolOperationalCertificateEnvelope
        , bulkCredentialVrfSigningKey = poolVrfSigningEnvelope
        , bulkCredentialKesSigningKey = poolKesSigningEnvelope
        }

-- | Render the upstream bulk-credentials JSON array.
renderBulkCredentials
    :: [BulkCredential]
    -> Either SynthesisError LBS.ByteString
renderBulkCredentials credentials =
    canonicalJsonBytes . toJSON
        <$> traverse bulkCredentialEnvelopes credentials

-- | Measure a completed ChainDB directory deterministically.
measureChainDb :: FilePath -> IO ChainDbMeasurement
measureChainDb root = do
    files <- recursiveFiles root
    entries <- traverse (chainDbFileEntry root) files
    let bytes = sum (fileBytes <$> entries)
        manifestBytes =
            LBS.length $
                canonicalJsonBytes $
                    toJSON (chainDbFileEntryValue <$> entries)
    pure
        ChainDbMeasurement
            { chainDbBytes = bytes
            , chainDbFileCount = length entries
            , chainDbPackagedBytes = bytes + fromInt64 manifestBytes
            }

-- | Render the synthesis report contract as canonical JSON.
renderSynthesisReport :: SynthesisReport -> LBS.ByteString
renderSynthesisReport SynthesisReport{..} =
    canonicalJsonBytes $
        object
            [ "schemaVersion" .= (1 :: Int)
            , "scenarioId" .= reportScenarioId
            , "scenarioDigest" .= digestText reportScenarioDigest
            , "bakerVersion" .= reportBakerVersion
            , "synthesis"
                .= object
                    [ "slotCount" .= reportSlotCount
                    , "profile" .= reportProfile
                    ]
            , "chainDb"
                .= object
                    [ "path" .= ("chain-db" :: Text)
                    , "bytes" .= chainDbBytes reportChainDb
                    , "fileCount" .= chainDbFileCount reportChainDb
                    , "packagedBytes"
                        .= chainDbPackagedBytes reportChainDb
                    ]
            , "observation"
                .= object
                    [ "wallTimeMilliseconds"
                        .= observationWallTimeMilliseconds reportObservation
                    , "startedAt"
                        .= observationStartedAt reportObservation
                    , "completedAt"
                        .= observationCompletedAt reportObservation
                    , "host" .= observationHost reportObservation
                    ]
            ]

data ChainDbFileEntry = ChainDbFileEntry
    { filePath :: FilePath
    , fileBytes :: Integer
    , fileDigest :: Digest
    }

chainDbFileEntry :: FilePath -> FilePath -> IO ChainDbFileEntry
chainDbFileEntry root relativePath = do
    let path = root </> relativePath
    bytes <- LBS.readFile path
    size <- getFileSize path
    pure
        ChainDbFileEntry
            { filePath = relativePath
            , fileBytes = size
            , fileDigest = digestLazyBytes bytes
            }

chainDbFileEntryValue :: ChainDbFileEntry -> Value
chainDbFileEntryValue ChainDbFileEntry{..} =
    object
        [ "path" .= filePath
        , "bytes" .= fileBytes
        , "digest" .= digestText fileDigest
        ]

recursiveFiles :: FilePath -> IO [FilePath]
recursiveFiles root =
    go ""
  where
    go relative = do
        let dir = if null relative then root else root </> relative
        entries <- sort <$> listDirectory dir
        concat
            <$> traverse
                ( \entry -> do
                    let relativePath =
                            if null relative
                                then entry
                                else relative </> entry
                        fullPath = root </> relativePath
                    isDirectory <- doesDirectoryExist fullPath
                    if isDirectory
                        then go relativePath
                        else pure [relativePath]
                )
                entries

fromInt64 :: Int64 -> Integer
fromInt64 =
    fromIntegral

digestText :: Digest -> Text
digestText (Digest digest) = digest

digestLazyBytes :: LBS.ByteString -> Digest
digestLazyBytes bytes =
    Digest . Text.pack . show $
        (Crypto.hashlazy bytes :: Crypto.Digest Crypto.SHA256)

bulkCredentialEnvelopes
    :: BulkCredential
    -> Either SynthesisError [Value]
bulkCredentialEnvelopes BulkCredential{..} =
    sequence
        [ parseEnvelope
            "operationalCertificate"
            bulkCredentialOperationalCertificate
        , parseEnvelope "vrfSigningKey" bulkCredentialVrfSigningKey
        , parseEnvelope "kesSigningKey" bulkCredentialKesSigningKey
        ]

parseEnvelope
    :: Text
    -> LBS.ByteString
    -> Either SynthesisError Value
parseEnvelope name bytes =
    case eitherDecode bytes of
        Left err -> Left (SynthesisInvalidTextEnvelope name err)
        Right value -> Right value
