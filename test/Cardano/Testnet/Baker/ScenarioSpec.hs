{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.Testnet.Baker.ScenarioSpec
Description : Scenario JSON decoding and semantic validation tests.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0
-}
module Cardano.Testnet.Baker.ScenarioSpec
    ( spec
    ) where

import Cardano.Testnet.Baker.Scenario
    ( Scenario (..)
    , ScenarioGenesis (..)
    , SynthesisRequest (..)
    , decodeScenarioBytes
    )
import Cardano.Testnet.Baker.Validation
    ( ValidatedScenario (..)
    , ValidationFailure (..)
    , validateScenario
    )
import Data.Aeson
    ( Value (..)
    , eitherDecode'
    )
import Data.Aeson.Key (Key)
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy (ByteString)
import Data.ByteString.Lazy qualified as LBS
import Data.Either (isLeft)
import Data.Foldable (toList)
import Data.Maybe (isJust)
import Data.Text (Text)
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = describe "Scenario decoding and validation" $ do
    it "decodes the MVP scenario fields" $ do
        let decoded = decodeScenarioBytes minimalScenario
        scenarioScenarioId <$> decoded `shouldBe` Right "local-fast"
        scenarioGenesisEpochLength . scenarioGenesis <$> decoded
            `shouldBe` Right 120

    it "decodes an optional synthesis request" $ do
        let decoded = decodeScenarioBytes scenarioWithSynthesis
        scenarioSynthesis <$> decoded
            `shouldBe` Right
                ( Just
                    ( SynthesisRequest
                        { synthesisEnabled = True
                        , synthesisSlotCount = Just 720
                        , synthesisProfile = Just "local-fast-ci"
                        }
                    )
                )

    it "decodes an omitted synthesis request as Nothing" $ do
        let decoded = decodeScenarioBytes minimalScenario
        scenarioSynthesis <$> decoded `shouldBe` Right Nothing

    it "rejects unknown synthesis request fields" $
        decodeScenarioBytes scenarioWithUnknownSynthesisField
            `shouldSatisfy` isLeft

    it "rejects synthesis without an enabled flag" $
        decodeScenarioBytes scenarioWithSynthesisMissingEnabled
            `shouldSatisfy` isLeft

    it "validates a minimal scenario" $ do
        let Right scenario = decodeScenarioBytes minimalScenario
        validateScenario scenario
            `shouldBe` Right (ValidatedScenario scenario)

    it "validates disabled synthesis without a slot count" $ do
        let Right scenario = decodeScenarioBytes scenarioWithDisabledSynthesis
        validateScenario scenario
            `shouldBe` Right (ValidatedScenario scenario)

    it "validates enabled synthesis with a slot count and profile" $ do
        let Right scenario = decodeScenarioBytes scenarioWithSynthesis
        validateScenario scenario
            `shouldBe` Right (ValidatedScenario scenario)

    it "keeps the minimal fixture as genesis-only coverage" $ do
        scenario <- loadScenario "test/data/minimal-scenario.json"
        scenarioSynthesis scenario `shouldBe` Nothing
        validateScenario scenario
            `shouldBe` Right (ValidatedScenario scenario)

    it "validates the committed local-fast scenario" $ do
        scenario <- loadScenario "examples/scenarios/local-fast.json"
        validateScenario scenario
            `shouldBe` Right (ValidatedScenario scenario)
        scenarioGenesisEpochLength (scenarioGenesis scenario)
            `shouldBe` 120

    it "validates the committed normal scenario" $ do
        scenario <- loadScenario "examples/scenarios/normal.json"
        validateScenario scenario
            `shouldBe` Right (ValidatedScenario scenario)
        scenarioGenesisEpochLength (scenarioGenesis scenario)
            `shouldBe` 86400
        scenarioGenesisK (scenarioGenesis scenario) `shouldBe` 2160
        scenarioGenesisActiveSlotsCoeff (scenarioGenesis scenario)
            `shouldBe` 0.05

    it "rejects duplicate pool labels after normalization" $ do
        let Right scenario = decodeScenarioBytes duplicatePoolLabels
        validateScenario scenario
            `shouldBe` Left [DuplicatePoolLabel "pool-a"]

    it "rejects faucet funding above declared supply" $ do
        let Right scenario = decodeScenarioBytes overfundedFaucet
        validateScenario scenario
            `shouldBe` Left [FaucetFundingExceedsSupply 2000000 1000000]

    it "rejects enabled synthesis without a slot count" $ do
        let Right scenario = decodeScenarioBytes scenarioWithSynthesisMissingSlotCount
        validateScenario scenario `shouldBe` Left [SynthesisSlotCountRequired]

    it "rejects non-positive synthesis slot counts" $ do
        let Right scenario = decodeScenarioBytes scenarioWithZeroSynthesisSlotCount
        validateScenario scenario
            `shouldBe` Left [SynthesisSlotCountNotPositive 0]

    it "rejects an empty synthesis profile" $ do
        let Right scenario = decodeScenarioBytes scenarioWithEmptySynthesisProfile
        validateScenario scenario
            `shouldBe` Left [SynthesisProfileEmpty]

    it "rejects run-specific systemStart in the baked scenario" $
        decodeScenarioBytes scenarioWithSystemStart `shouldSatisfy` isLeft

    it "publishes synthesis as an optional root schema field" $ do
        schema <- loadScenarioSchema
        schemaPath ["properties", "synthesis"] schema
            `shouldSatisfy` isJust
        schemaPath ["required"] schema
            `shouldSatisfy` maybe False (notElem "synthesis" . stringArray)

    it
        "defines synthesis schema fields and rejects unknown synthesis keys"
        $ do
            schema <- loadScenarioSchema
            synthesis <- requireRootPropertySchema "synthesis" schema
            schemaPath ["additionalProperties"] synthesis
                `shouldBe` Just (Bool False)
            stringArray <$> schemaPath ["required"] synthesis
                `shouldBe` Just ["enabled"]
            schemaPath ["properties", "enabled", "type"] synthesis
                `shouldBe` Just (String "boolean")
            schemaPath ["properties", "slotCount", "type"] synthesis
                `shouldBe` Just (String "integer")
            schemaPath ["properties", "slotCount", "minimum"] synthesis
                `shouldBe` Just (Number 1)
            schemaPath ["properties", "profile", "type"] synthesis
                `shouldBe` Just (String "string")
            schemaPath ["properties", "profile", "minLength"] synthesis
                `shouldBe` Just (Number 1)

    it "requires slotCount only when synthesis is enabled" $ do
        schema <- loadScenarioSchema
        synthesis <- requireRootPropertySchema "synthesis" schema
        schemaPath ["allOf"] synthesis
            `shouldSatisfy` maybe False hasEnabledSlotCountConditional

minimalScenario :: ByteString
minimalScenario =
    "{\
    \\"schemaVersion\":1,\
    \\"scenarioId\":\"local-fast\",\
    \\"seed\":\"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f\",\
    \\"network\":{\"networkMagic\":42,\"networkId\":\"Testnet\"},\
    \\"eraSchedule\":{\"shelley\":0,\"alonzo\":0,\"conway\":0},\
    \\"genesis\":{\"epochLength\":120,\"activeSlotsCoeff\":0.05,\"securityParam\":10,\"k\":1,\"maxLovelaceSupply\":1000000000},\
    \\"pools\":[{\"label\":\"pool-a\",\"pledge\":1000000,\"cost\":340000000,\"margin\":0.05,\"stake\":100000000,\"coldKeyLabel\":\"pool-a-cold\",\"vrfKeyLabel\":\"pool-a-vrf\",\"kesKeyLabel\":\"pool-a-kes\",\"stakeKeyLabel\":\"pool-a-stake\"}],\
    \\"faucets\":[{\"label\":\"faucet\",\"paymentKeyLabel\":\"genesis.1\",\"lovelace\":1000000}]\
    \}"

duplicatePoolLabels :: ByteString
duplicatePoolLabels =
    "{\
    \\"schemaVersion\":1,\
    \\"scenarioId\":\"duplicate-pools\",\
    \\"seed\":\"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f\",\
    \\"network\":{\"networkMagic\":42,\"networkId\":\"Testnet\"},\
    \\"eraSchedule\":{\"shelley\":0,\"alonzo\":0,\"conway\":0},\
    \\"genesis\":{\"epochLength\":120,\"activeSlotsCoeff\":0.05,\"securityParam\":10,\"k\":1,\"maxLovelaceSupply\":1000000000},\
    \\"pools\":[{\"label\":\"Pool-A\",\"pledge\":1000000,\"cost\":340000000,\"margin\":0.05,\"stake\":100000000,\"coldKeyLabel\":\"pool-a-cold\",\"vrfKeyLabel\":\"pool-a-vrf\",\"kesKeyLabel\":\"pool-a-kes\",\"stakeKeyLabel\":\"pool-a-stake\"},{\"label\":\"pool-a\",\"pledge\":1000000,\"cost\":340000000,\"margin\":0.05,\"stake\":100000000,\"coldKeyLabel\":\"pool-a2-cold\",\"vrfKeyLabel\":\"pool-a2-vrf\",\"kesKeyLabel\":\"pool-a2-kes\",\"stakeKeyLabel\":\"pool-a2-stake\"}],\
    \\"faucets\":[{\"label\":\"faucet\",\"paymentKeyLabel\":\"genesis.1\",\"lovelace\":1000000}]\
    \}"

overfundedFaucet :: ByteString
overfundedFaucet =
    "{\
    \\"schemaVersion\":1,\
    \\"scenarioId\":\"overfunded\",\
    \\"seed\":\"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f\",\
    \\"network\":{\"networkMagic\":42,\"networkId\":\"Testnet\"},\
    \\"eraSchedule\":{\"shelley\":0,\"alonzo\":0,\"conway\":0},\
    \\"genesis\":{\"epochLength\":120,\"activeSlotsCoeff\":0.05,\"securityParam\":10,\"k\":1,\"maxLovelaceSupply\":1000000},\
    \\"pools\":[{\"label\":\"pool-a\",\"pledge\":1000000,\"cost\":340000000,\"margin\":0.05,\"stake\":100000000,\"coldKeyLabel\":\"pool-a-cold\",\"vrfKeyLabel\":\"pool-a-vrf\",\"kesKeyLabel\":\"pool-a-kes\",\"stakeKeyLabel\":\"pool-a-stake\"}],\
    \\"faucets\":[{\"label\":\"faucet\",\"paymentKeyLabel\":\"genesis.1\",\"lovelace\":2000000}]\
    \}"

scenarioWithSystemStart :: ByteString
scenarioWithSystemStart =
    "{\
    \\"schemaVersion\":1,\
    \\"scenarioId\":\"bad-system-start\",\
    \\"seed\":\"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f\",\
    \\"network\":{\"networkMagic\":42,\"networkId\":\"Testnet\"},\
    \\"eraSchedule\":{\"shelley\":0,\"alonzo\":0,\"conway\":0},\
    \\"genesis\":{\"epochLength\":120,\"activeSlotsCoeff\":0.05,\"securityParam\":10,\"k\":1,\"maxLovelaceSupply\":1000000000,\"systemStart\":\"2026-05-07T00:00:00Z\"},\
    \\"pools\":[{\"label\":\"pool-a\",\"pledge\":1000000,\"cost\":340000000,\"margin\":0.05,\"stake\":100000000,\"coldKeyLabel\":\"pool-a-cold\",\"vrfKeyLabel\":\"pool-a-vrf\",\"kesKeyLabel\":\"pool-a-kes\",\"stakeKeyLabel\":\"pool-a-stake\"}],\
    \\"faucets\":[{\"label\":\"faucet\",\"paymentKeyLabel\":\"genesis.1\",\"lovelace\":1000000}]\
    \}"

scenarioWithSynthesis :: ByteString
scenarioWithSynthesis =
    "{\
    \\"schemaVersion\":1,\
    \\"scenarioId\":\"synthesis-request\",\
    \\"seed\":\"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f\",\
    \\"network\":{\"networkMagic\":42,\"networkId\":\"Testnet\"},\
    \\"eraSchedule\":{\"shelley\":0,\"alonzo\":0,\"conway\":0},\
    \\"genesis\":{\"epochLength\":120,\"activeSlotsCoeff\":0.05,\"securityParam\":10,\"k\":1,\"maxLovelaceSupply\":1000000000},\
    \\"pools\":[{\"label\":\"pool-a\",\"pledge\":1000000,\"cost\":340000000,\"margin\":0.05,\"stake\":100000000,\"coldKeyLabel\":\"pool-a-cold\",\"vrfKeyLabel\":\"pool-a-vrf\",\"kesKeyLabel\":\"pool-a-kes\",\"stakeKeyLabel\":\"pool-a-stake\"}],\
    \\"faucets\":[{\"label\":\"faucet\",\"paymentKeyLabel\":\"genesis.1\",\"lovelace\":1000000}],\
    \\"synthesis\":{\"enabled\":true,\"slotCount\":720,\"profile\":\"local-fast-ci\"}\
    \}"

scenarioWithUnknownSynthesisField :: ByteString
scenarioWithUnknownSynthesisField =
    "{\
    \\"schemaVersion\":1,\
    \\"scenarioId\":\"bad-synthesis-field\",\
    \\"seed\":\"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f\",\
    \\"network\":{\"networkMagic\":42,\"networkId\":\"Testnet\"},\
    \\"eraSchedule\":{\"shelley\":0,\"alonzo\":0,\"conway\":0},\
    \\"genesis\":{\"epochLength\":120,\"activeSlotsCoeff\":0.05,\"securityParam\":10,\"k\":1,\"maxLovelaceSupply\":1000000000},\
    \\"pools\":[{\"label\":\"pool-a\",\"pledge\":1000000,\"cost\":340000000,\"margin\":0.05,\"stake\":100000000,\"coldKeyLabel\":\"pool-a-cold\",\"vrfKeyLabel\":\"pool-a-vrf\",\"kesKeyLabel\":\"pool-a-kes\",\"stakeKeyLabel\":\"pool-a-stake\"}],\
    \\"faucets\":[{\"label\":\"faucet\",\"paymentKeyLabel\":\"genesis.1\",\"lovelace\":1000000}],\
    \\"synthesis\":{\"enabled\":true,\"slotCount\":720,\"unexpected\":true}\
    \}"

scenarioWithSynthesisMissingEnabled :: ByteString
scenarioWithSynthesisMissingEnabled =
    "{\
    \\"schemaVersion\":1,\
    \\"scenarioId\":\"bad-synthesis-missing-enabled\",\
    \\"seed\":\"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f\",\
    \\"network\":{\"networkMagic\":42,\"networkId\":\"Testnet\"},\
    \\"eraSchedule\":{\"shelley\":0,\"alonzo\":0,\"conway\":0},\
    \\"genesis\":{\"epochLength\":120,\"activeSlotsCoeff\":0.05,\"securityParam\":10,\"k\":1,\"maxLovelaceSupply\":1000000000},\
    \\"pools\":[{\"label\":\"pool-a\",\"pledge\":1000000,\"cost\":340000000,\"margin\":0.05,\"stake\":100000000,\"coldKeyLabel\":\"pool-a-cold\",\"vrfKeyLabel\":\"pool-a-vrf\",\"kesKeyLabel\":\"pool-a-kes\",\"stakeKeyLabel\":\"pool-a-stake\"}],\
    \\"faucets\":[{\"label\":\"faucet\",\"paymentKeyLabel\":\"genesis.1\",\"lovelace\":1000000}],\
    \\"synthesis\":{\"slotCount\":720}\
    \}"

scenarioWithDisabledSynthesis :: ByteString
scenarioWithDisabledSynthesis =
    "{\
    \\"schemaVersion\":1,\
    \\"scenarioId\":\"disabled-synthesis\",\
    \\"seed\":\"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f\",\
    \\"network\":{\"networkMagic\":42,\"networkId\":\"Testnet\"},\
    \\"eraSchedule\":{\"shelley\":0,\"alonzo\":0,\"conway\":0},\
    \\"genesis\":{\"epochLength\":120,\"activeSlotsCoeff\":0.05,\"securityParam\":10,\"k\":1,\"maxLovelaceSupply\":1000000000},\
    \\"pools\":[{\"label\":\"pool-a\",\"pledge\":1000000,\"cost\":340000000,\"margin\":0.05,\"stake\":100000000,\"coldKeyLabel\":\"pool-a-cold\",\"vrfKeyLabel\":\"pool-a-vrf\",\"kesKeyLabel\":\"pool-a-kes\",\"stakeKeyLabel\":\"pool-a-stake\"}],\
    \\"faucets\":[{\"label\":\"faucet\",\"paymentKeyLabel\":\"genesis.1\",\"lovelace\":1000000}],\
    \\"synthesis\":{\"enabled\":false}\
    \}"

scenarioWithSynthesisMissingSlotCount :: ByteString
scenarioWithSynthesisMissingSlotCount =
    "{\
    \\"schemaVersion\":1,\
    \\"scenarioId\":\"bad-synthesis-missing-slot-count\",\
    \\"seed\":\"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f\",\
    \\"network\":{\"networkMagic\":42,\"networkId\":\"Testnet\"},\
    \\"eraSchedule\":{\"shelley\":0,\"alonzo\":0,\"conway\":0},\
    \\"genesis\":{\"epochLength\":120,\"activeSlotsCoeff\":0.05,\"securityParam\":10,\"k\":1,\"maxLovelaceSupply\":1000000000},\
    \\"pools\":[{\"label\":\"pool-a\",\"pledge\":1000000,\"cost\":340000000,\"margin\":0.05,\"stake\":100000000,\"coldKeyLabel\":\"pool-a-cold\",\"vrfKeyLabel\":\"pool-a-vrf\",\"kesKeyLabel\":\"pool-a-kes\",\"stakeKeyLabel\":\"pool-a-stake\"}],\
    \\"faucets\":[{\"label\":\"faucet\",\"paymentKeyLabel\":\"genesis.1\",\"lovelace\":1000000}],\
    \\"synthesis\":{\"enabled\":true}\
    \}"

scenarioWithZeroSynthesisSlotCount :: ByteString
scenarioWithZeroSynthesisSlotCount =
    "{\
    \\"schemaVersion\":1,\
    \\"scenarioId\":\"bad-synthesis-zero-slot-count\",\
    \\"seed\":\"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f\",\
    \\"network\":{\"networkMagic\":42,\"networkId\":\"Testnet\"},\
    \\"eraSchedule\":{\"shelley\":0,\"alonzo\":0,\"conway\":0},\
    \\"genesis\":{\"epochLength\":120,\"activeSlotsCoeff\":0.05,\"securityParam\":10,\"k\":1,\"maxLovelaceSupply\":1000000000},\
    \\"pools\":[{\"label\":\"pool-a\",\"pledge\":1000000,\"cost\":340000000,\"margin\":0.05,\"stake\":100000000,\"coldKeyLabel\":\"pool-a-cold\",\"vrfKeyLabel\":\"pool-a-vrf\",\"kesKeyLabel\":\"pool-a-kes\",\"stakeKeyLabel\":\"pool-a-stake\"}],\
    \\"faucets\":[{\"label\":\"faucet\",\"paymentKeyLabel\":\"genesis.1\",\"lovelace\":1000000}],\
    \\"synthesis\":{\"enabled\":true,\"slotCount\":0}\
    \}"

scenarioWithEmptySynthesisProfile :: ByteString
scenarioWithEmptySynthesisProfile =
    "{\
    \\"schemaVersion\":1,\
    \\"scenarioId\":\"bad-synthesis-empty-profile\",\
    \\"seed\":\"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f\",\
    \\"network\":{\"networkMagic\":42,\"networkId\":\"Testnet\"},\
    \\"eraSchedule\":{\"shelley\":0,\"alonzo\":0,\"conway\":0},\
    \\"genesis\":{\"epochLength\":120,\"activeSlotsCoeff\":0.05,\"securityParam\":10,\"k\":1,\"maxLovelaceSupply\":1000000000},\
    \\"pools\":[{\"label\":\"pool-a\",\"pledge\":1000000,\"cost\":340000000,\"margin\":0.05,\"stake\":100000000,\"coldKeyLabel\":\"pool-a-cold\",\"vrfKeyLabel\":\"pool-a-vrf\",\"kesKeyLabel\":\"pool-a-kes\",\"stakeKeyLabel\":\"pool-a-stake\"}],\
    \\"faucets\":[{\"label\":\"faucet\",\"paymentKeyLabel\":\"genesis.1\",\"lovelace\":1000000}],\
    \\"synthesis\":{\"enabled\":true,\"slotCount\":720,\"profile\":\"\"}\
    \}"

loadScenario :: FilePath -> IO Scenario
loadScenario path = do
    bytes <- LBS.readFile path
    case decodeScenarioBytes bytes of
        Left err -> fail err
        Right scenario -> pure scenario

loadScenarioSchema :: IO Value
loadScenarioSchema = do
    bytes <- LBS.readFile "schemas/scenario/v1.schema.json"
    case eitherDecode' bytes of
        Left err -> fail err
        Right schema -> pure schema

schemaPath :: [Key] -> Value -> Maybe Value
schemaPath [] value = Just value
schemaPath (key : keys) value = lookupKey key value >>= schemaPath keys

rootPropertySchema :: Key -> Value -> Maybe Value
rootPropertySchema key schema =
    case schemaPath ["properties", key] schema of
        Just property ->
            case schemaPath ["$ref"] property of
                Just (String _) -> schemaPath ["$defs", key] schema
                _ -> Just property
        Nothing -> Nothing

requireRootPropertySchema :: Key -> Value -> IO Value
requireRootPropertySchema key schema =
    case rootPropertySchema key schema of
        Just value -> pure value
        Nothing -> fail ("missing root schema property " <> show key)

lookupKey :: Key -> Value -> Maybe Value
lookupKey key (Object object) = KeyMap.lookup key object
lookupKey _ _ = Nothing

stringArray :: Value -> [Text]
stringArray (Array values) =
    [text | String text <- toList values]
stringArray _ = []

hasEnabledSlotCountConditional :: Value -> Bool
hasEnabledSlotCountConditional (Array clauses) =
    any matchesClause clauses
  where
    matchesClause clause =
        schemaPath ["if", "properties", "enabled", "const"] clause
            == Just (Bool True)
            && maybe
                False
                (elem "slotCount" . stringArray)
                (schemaPath ["then", "required"] clause)
hasEnabledSlotCountConditional _ = False
