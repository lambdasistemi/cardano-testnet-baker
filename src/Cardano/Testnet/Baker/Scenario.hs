{- |
Module      : Cardano.Testnet.Baker.Scenario
Description : Scenario JSON model and decoding.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Defines the versioned scenario document consumed by validation and bake
commands.
-}
module Cardano.Testnet.Baker.Scenario
    ( EraSchedule (..)
    , FaucetDeclaration (..)
    , Network (..)
    , PoolDeclaration (..)
    , Scenario (..)
    , ScenarioGenesis (..)
    , decodeScenarioBytes
    ) where

import Data.Aeson
    ( FromJSON (..)
    , Value
    , eitherDecode
    , withObject
    , (.:)
    , (.:?)
    )
import Data.Aeson.Key (Key)
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy (ByteString)
import Data.Foldable (for_)
import Data.Text (Text)

-- | Versioned declarative input for one deterministic testnet bake.
data Scenario = Scenario
    { scenarioSchemaVersion :: Int
    -- ^ Published scenario schema major version.
    , scenarioScenarioId :: Text
    -- ^ Stable human-readable scenario identifier.
    , scenarioSeed :: Text
    -- ^ Base16 seed material for deterministic derivation.
    , scenarioNetwork :: Network
    -- ^ Network magic and network id.
    , scenarioEraSchedule :: EraSchedule
    -- ^ Era activation schedule.
    , scenarioGenesis :: ScenarioGenesis
    -- ^ Genesis parameters that affect output.
    , scenarioPools :: [PoolDeclaration]
    -- ^ Stake pool declarations.
    , scenarioFaucets :: [FaucetDeclaration]
    -- ^ Faucet funding declarations.
    }
    deriving (Eq, Show)

instance FromJSON Scenario where
    parseJSON = withObject "Scenario" $ \object -> do
        rejectUnknownKeys
            "Scenario"
            [ "schemaVersion"
            , "scenarioId"
            , "seed"
            , "network"
            , "eraSchedule"
            , "genesis"
            , "pools"
            , "faucets"
            ]
            object
        Scenario
            <$> object .: "schemaVersion"
            <*> object .: "scenarioId"
            <*> object .: "seed"
            <*> object .: "network"
            <*> object .: "eraSchedule"
            <*> object .: "genesis"
            <*> object .: "pools"
            <*> object .: "faucets"

-- | Network identity for generated genesis and node configuration.
data Network = Network
    { networkMagic :: Int
    -- ^ Cardano network magic.
    , networkId :: Text
    -- ^ Cardano network id, for example @Testnet@.
    }
    deriving (Eq, Show)

instance FromJSON Network where
    parseJSON = withObject "Network" $ \object -> do
        rejectUnknownKeys "Network" ["networkMagic", "networkId"] object
        Network
            <$> object .: "networkMagic"
            <*> object .: "networkId"

-- | MVP hard-fork activation schedule.
data EraSchedule = EraSchedule
    { eraScheduleShelley :: Int
    -- ^ Shelley activation epoch.
    , eraScheduleAlonzo :: Int
    -- ^ Alonzo activation epoch.
    , eraScheduleConway :: Int
    -- ^ Conway activation epoch.
    }
    deriving (Eq, Show)

instance FromJSON EraSchedule where
    parseJSON = withObject "EraSchedule" $ \object -> do
        rejectUnknownKeys "EraSchedule" ["shelley", "alonzo", "conway"] object
        EraSchedule
            <$> object .: "shelley"
            <*> object .: "alonzo"
            <*> object .: "conway"

-- | Genesis parameters that are deterministic bake inputs.
data ScenarioGenesis = ScenarioGenesis
    { scenarioGenesisEpochLength :: Int
    -- ^ Epoch length in slots.
    , scenarioGenesisActiveSlotsCoeff :: Double
    -- ^ Active slots coefficient.
    , scenarioGenesisSecurityParam :: Int
    -- ^ Security parameter.
    , scenarioGenesisK :: Int
    -- ^ Desired pool count parameter.
    , scenarioGenesisMaxLovelaceSupply :: Integer
    -- ^ Declared maximum lovelace supply.
    }
    deriving (Eq, Show)

instance FromJSON ScenarioGenesis where
    parseJSON = withObject "ScenarioGenesis" $ \object -> do
        rejectUnknownKeys
            "ScenarioGenesis"
            [ "epochLength"
            , "activeSlotsCoeff"
            , "securityParam"
            , "k"
            , "maxLovelaceSupply"
            ]
            object
        ScenarioGenesis
            <$> object .: "epochLength"
            <*> object .: "activeSlotsCoeff"
            <*> object .: "securityParam"
            <*> object .: "k"
            <*> object .: "maxLovelaceSupply"

-- | Stake pool declaration from the scenario.
data PoolDeclaration = PoolDeclaration
    { poolLabel :: Text
    -- ^ Stable pool label.
    , poolPledge :: Integer
    -- ^ Pool pledge in lovelace.
    , poolCost :: Integer
    -- ^ Pool fixed cost in lovelace.
    , poolMargin :: Double
    -- ^ Pool margin.
    , poolStake :: Integer
    -- ^ Initial stake delegated to the pool.
    , poolColdKeyLabel :: Text
    -- ^ Deterministic cold key label.
    , poolVrfKeyLabel :: Text
    -- ^ Deterministic VRF key label.
    , poolKesKeyLabel :: Text
    -- ^ Deterministic KES key label.
    , poolStakeKeyLabel :: Text
    -- ^ Deterministic stake key label.
    }
    deriving (Eq, Show)

instance FromJSON PoolDeclaration where
    parseJSON = withObject "PoolDeclaration" $ \object -> do
        rejectUnknownKeys
            "PoolDeclaration"
            [ "label"
            , "pledge"
            , "cost"
            , "margin"
            , "stake"
            , "coldKeyLabel"
            , "vrfKeyLabel"
            , "kesKeyLabel"
            , "stakeKeyLabel"
            ]
            object
        PoolDeclaration
            <$> object .: "label"
            <*> object .: "pledge"
            <*> object .: "cost"
            <*> object .: "margin"
            <*> object .: "stake"
            <*> object .: "coldKeyLabel"
            <*> object .: "vrfKeyLabel"
            <*> object .: "kesKeyLabel"
            <*> object .: "stakeKeyLabel"

-- | Faucet declaration represented later as Shelley initial funds.
data FaucetDeclaration = FaucetDeclaration
    { faucetLabel :: Text
    -- ^ Stable faucet label.
    , faucetPaymentKeyLabel :: Text
    -- ^ Deterministic payment key label.
    , faucetLovelace :: Integer
    -- ^ Faucet funding amount.
    , faucetMetadata :: Maybe Value
    -- ^ Optional scenario-owned faucet metadata.
    }
    deriving (Eq, Show)

instance FromJSON FaucetDeclaration where
    parseJSON = withObject "FaucetDeclaration" $ \object -> do
        rejectUnknownKeys
            "FaucetDeclaration"
            ["label", "paymentKeyLabel", "lovelace", "metadata"]
            object
        FaucetDeclaration
            <$> object .: "label"
            <*> object .: "paymentKeyLabel"
            <*> object .: "lovelace"
            <*> object .:? "metadata"

-- | Decode a scenario JSON document from lazy bytes.
decodeScenarioBytes :: ByteString -> Either String Scenario
decodeScenarioBytes = eitherDecode

rejectUnknownKeys
    :: (MonadFail m)
    => String
    -> [Key]
    -> KeyMap.KeyMap Value
    -> m ()
rejectUnknownKeys name allowed object =
    for_ (filter (`notElem` allowed) (KeyMap.keys object)) $ \key ->
        fail $
            name
                <> " does not support field "
                <> show (Key.toString key)
