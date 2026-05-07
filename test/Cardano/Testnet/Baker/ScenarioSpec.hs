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
    , decodeScenarioBytes
    )
import Cardano.Testnet.Baker.Validation
    ( ValidatedScenario (..)
    , ValidationFailure (..)
    , validateScenario
    )
import Data.ByteString.Lazy (ByteString)
import Data.Either (isLeft)
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = describe "Scenario decoding and validation" $ do
    it "decodes the MVP scenario fields" $ do
        let decoded = decodeScenarioBytes minimalScenario
        scenarioScenarioId <$> decoded `shouldBe` Right "local-fast"
        scenarioGenesisEpochLength . scenarioGenesis <$> decoded
            `shouldBe` Right 120

    it "validates a minimal scenario" $ do
        let Right scenario = decodeScenarioBytes minimalScenario
        validateScenario scenario
            `shouldBe` Right (ValidatedScenario scenario)

    it "rejects duplicate pool labels after normalization" $ do
        let Right scenario = decodeScenarioBytes duplicatePoolLabels
        validateScenario scenario
            `shouldBe` Left [DuplicatePoolLabel "pool-a"]

    it "rejects faucet funding above declared supply" $ do
        let Right scenario = decodeScenarioBytes overfundedFaucet
        validateScenario scenario
            `shouldBe` Left [FaucetFundingExceedsSupply 2000000 1000000]

    it "rejects run-specific systemStart in the baked scenario" $
        decodeScenarioBytes scenarioWithSystemStart `shouldSatisfy` isLeft

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
