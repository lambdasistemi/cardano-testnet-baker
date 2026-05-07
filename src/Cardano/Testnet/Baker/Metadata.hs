{- |
Module      : Cardano.Testnet.Baker.Metadata
Description : Bake metadata and artifact digest helpers.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Defines metadata emitted alongside baked artifacts and canonical digest
helpers for reproducibility checks.
-}
module Cardano.Testnet.Baker.Metadata
    ( BakeMetadata (..)
    , Digest (..)
    , canonicalJsonBytes
    , canonicalJsonDigest
    , digestBytes
    , metadataToValue
    ) where

import Crypto.Hash qualified as Crypto
import Data.Aeson (Value (..), encode, object, (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString (ByteString)
import Data.ByteString.Builder qualified as Builder
import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (toList)
import Data.List (sortOn)
import Data.Text (Text)
import Data.Text qualified as Text

-- | Base16 SHA256 digest for baked inputs and generated artifacts.
newtype Digest = Digest Text
    deriving (Eq, Show)

-- | Deterministic metadata emitted with every artifact set.
data BakeMetadata = BakeMetadata
    { metadataScenarioId :: Text
    -- ^ Scenario identifier from the source JSON.
    , metadataSchemaVersion :: Int
    -- ^ Scenario schema version accepted by the baker.
    , metadataBakerVersion :: Text
    -- ^ Baker package version.
    , metadataBakerCommit :: Text
    -- ^ Source revision or @dirty@ marker used for the bake.
    , metadataInputDigest :: Digest
    -- ^ Digest of the canonical scenario input.
    , metadataArtifactDigests :: [(FilePath, Digest)]
    -- ^ Output artifact digests keyed by relative path.
    , metadataDerivationVersion :: Text
    -- ^ Version of the deterministic derivation scheme.
    , metadataCreatedBy :: Text
    -- ^ Tool identifier, intentionally not a timestamp.
    }
    deriving (Eq, Show)

-- | Render JSON bytes with objects sorted by key.
canonicalJsonBytes :: Value -> LBS.ByteString
canonicalJsonBytes =
    Builder.toLazyByteString . renderValue

-- | Digest canonical JSON bytes with SHA256/base16.
canonicalJsonDigest :: Value -> Digest
canonicalJsonDigest =
    digestBytes . LBS.toStrict . canonicalJsonBytes

-- | Digest strict bytes with SHA256/base16.
digestBytes :: ByteString -> Digest
digestBytes bytes =
    Digest . Text.pack . show $
        (Crypto.hash bytes :: Crypto.Digest Crypto.SHA256)

-- | Convert bake metadata to JSON without wall-clock or host-local fields.
metadataToValue :: BakeMetadata -> Value
metadataToValue BakeMetadata{..} =
    object
        [ "scenarioId" .= metadataScenarioId
        , "schemaVersion" .= metadataSchemaVersion
        , "bakerVersion" .= metadataBakerVersion
        , "bakerCommit" .= metadataBakerCommit
        , "inputDigest" .= digestText metadataInputDigest
        , "artifactDigests" .= artifactDigestsToValue metadataArtifactDigests
        , "derivationVersion" .= metadataDerivationVersion
        , "createdBy" .= metadataCreatedBy
        ]

renderValue :: Value -> Builder.Builder
renderValue = \case
    Object values -> renderObject values
    Array values -> renderArray (toList values)
    value -> Builder.lazyByteString (encode value)

renderObject :: KeyMap.KeyMap Value -> Builder.Builder
renderObject values =
    Builder.char7 '{'
        <> commaSeparated
            ( map
                renderMember
                (sortOn (Key.toText . fst) (KeyMap.toList values))
            )
        <> Builder.char7 '}'

renderMember :: (Key.Key, Value) -> Builder.Builder
renderMember (key, value) =
    Builder.lazyByteString (encode (Key.toText key))
        <> Builder.char7 ':'
        <> renderValue value

renderArray :: [Value] -> Builder.Builder
renderArray values =
    Builder.char7 '['
        <> commaSeparated (map renderValue values)
        <> Builder.char7 ']'

commaSeparated :: [Builder.Builder] -> Builder.Builder
commaSeparated = \case
    [] -> mempty
    first : rest ->
        first <> foldMap (Builder.char7 ',' <>) rest

artifactDigestsToValue :: [(FilePath, Digest)] -> Value
artifactDigestsToValue artifactDigests =
    object
        [ Key.fromString path .= digestText digest
        | (path, digest) <- artifactDigests
        ]

digestText :: Digest -> Text
digestText (Digest digest) = digest
