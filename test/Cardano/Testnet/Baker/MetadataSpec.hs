{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.Testnet.Baker.MetadataSpec
Description : Canonical metadata encoding and digest tests.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0
-}
module Cardano.Testnet.Baker.MetadataSpec
    ( spec
    ) where

import Cardano.Testnet.Baker.Metadata
    ( BakeMetadata (..)
    , Digest (..)
    , canonicalJsonBytes
    , canonicalJsonDigest
    , digestBytes
    , metadataToValue
    )
import Data.Aeson (Value (..), object, (.=))
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec = describe "metadata canonicalization" $ do
    it "renders object keys in deterministic ascending order" $
        canonicalJsonBytes unorderedValue `shouldBe` "{\"a\":true,\"b\":1}"

    it "digests bytes as SHA256 base16" $
        digestBytes "abc"
            `shouldBe` Digest
                "ba7816bf8f01cfea414140de5dae2223\
                \b00361a396177a9cb410ff61f20015ad"

    it "gives equal digests for semantically equal objects" $
        canonicalJsonDigest unorderedValue
            `shouldBe` canonicalJsonDigest reorderedValue

    it "omits wall-clock timestamps from metadata JSON" $ do
        let encoded =
                LBS.toStrict $
                    canonicalJsonBytes $
                        metadataToValue $
                            BakeMetadata
                                { metadataScenarioId = "local-fast"
                                , metadataSchemaVersion = 1
                                , metadataBakerVersion = "0.1.0.0"
                                , metadataBakerCommit = "dirty"
                                , metadataInputDigest = Digest "input"
                                , metadataArtifactDigests =
                                    [("metadata.json", Digest "self")]
                                , metadataDerivationVersion = "v1"
                                , metadataCreatedBy = "cardano-testnet-baker"
                                }
        BS.isInfixOf "createdAt" encoded `shouldBe` False
        BS.isInfixOf "timestamp" encoded `shouldBe` False

    it "keeps synthesis observation fields out of deterministic metadata" $ do
        let encoded =
                LBS.toStrict $
                    canonicalJsonBytes $
                        metadataToValue $
                            BakeMetadata
                                { metadataScenarioId = "normal"
                                , metadataSchemaVersion = 1
                                , metadataBakerVersion = "0.1.0.0"
                                , metadataBakerCommit = "dirty"
                                , metadataInputDigest = Digest "input"
                                , metadataArtifactDigests =
                                    [
                                        ( "synthesis-report.json"
                                        , Digest "report"
                                        )
                                    ]
                                , metadataDerivationVersion = "v1"
                                , metadataCreatedBy = "cardano-testnet-baker"
                                }
        BS.isInfixOf "wallTimeMilliseconds" encoded `shouldBe` False
        BS.isInfixOf "startedAt" encoded `shouldBe` False
        BS.isInfixOf "completedAt" encoded `shouldBe` False
        BS.isInfixOf "host" encoded `shouldBe` False

unorderedValue :: Value
unorderedValue = object ["b" .= Number 1, "a" .= Bool True]

reorderedValue :: Value
reorderedValue = object ["a" .= Bool True, "b" .= Number 1]
