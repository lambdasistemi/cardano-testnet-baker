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
    , SynthesisError (..)
    , SynthesisRun (..)
    , SynthesisRunner (..)
    , bulkCredentialKesSigningKey
    , bulkCredentialOperationalCertificate
    , bulkCredentialVrfSigningKey
    , bulkCredentialFromPoolArtifacts
    , dbSynthesizerRunner
    , renderBulkCredentials
    ) where

import Cardano.Testnet.Baker.Keys (PoolKeyArtifacts (..))
import Cardano.Testnet.Baker.Metadata (canonicalJsonBytes)
import Control.Exception (try)
import Data.Aeson (Value, eitherDecode, toJSON)
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import System.Exit (ExitCode (..))
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
