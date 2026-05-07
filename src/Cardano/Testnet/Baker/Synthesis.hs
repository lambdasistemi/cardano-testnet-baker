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
    , renderBulkCredentials
    ) where

import Cardano.Testnet.Baker.Keys (PoolKeyArtifacts (..))
import Cardano.Testnet.Baker.Metadata (canonicalJsonBytes)
import Data.Aeson (Value, eitherDecode, toJSON)
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)

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
