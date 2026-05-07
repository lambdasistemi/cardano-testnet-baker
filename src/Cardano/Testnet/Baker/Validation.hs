{- |
Module      : Cardano.Testnet.Baker.Validation
Description : Scenario semantic validation.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Checks invariants that cannot be represented by the published JSON
Schema alone.
-}
module Cardano.Testnet.Baker.Validation
    ( ValidatedScenario (..)
    , ValidationFailure (..)
    , validateScenario
    ) where

import Cardano.Testnet.Baker.Scenario
    ( FaucetDeclaration (..)
    , PoolDeclaration (..)
    , Scenario (..)
    , ScenarioGenesis (..)
    )
import Data.List (group, sort)
import Data.Text (Text)
import Data.Text qualified as Text

-- | Scenario that has passed semantic validation.
newtype ValidatedScenario = ValidatedScenario Scenario
    deriving (Eq, Show)

-- | Semantic validation failure for scenario invariants.
data ValidationFailure
    = NoPools
    | NoFaucets
    | DuplicatePoolLabel Text
    | DuplicateFaucetLabel Text
    | FaucetFundingExceedsSupply Integer Integer
    deriving (Eq, Show)

-- | Validate cross-field invariants that JSON Schema cannot express.
validateScenario
    :: Scenario -> Either [ValidationFailure] ValidatedScenario
validateScenario scenario =
    case validationFailures scenario of
        [] -> Right (ValidatedScenario scenario)
        failures -> Left failures

validationFailures :: Scenario -> [ValidationFailure]
validationFailures scenario =
    concat
        [ [NoPools | null (scenarioPools scenario)]
        , [NoFaucets | null (scenarioFaucets scenario)]
        , DuplicatePoolLabel
            <$> duplicateLabels poolLabel (scenarioPools scenario)
        , DuplicateFaucetLabel
            <$> duplicateLabels faucetLabel (scenarioFaucets scenario)
        , faucetSupplyFailures scenario
        ]

duplicateLabels :: (a -> Text) -> [a] -> [Text]
duplicateLabels getLabel =
    fmap head
        . filter hasDuplicate
        . group
        . sort
        . fmap (Text.toLower . getLabel)

hasDuplicate :: [a] -> Bool
hasDuplicate (_ : _ : _) = True
hasDuplicate _ = False

faucetSupplyFailures :: Scenario -> [ValidationFailure]
faucetSupplyFailures scenario =
    let requested = sum (faucetLovelace <$> scenarioFaucets scenario)
        supply =
            scenarioGenesisMaxLovelaceSupply $
                scenarioGenesis scenario
    in  [FaucetFundingExceedsSupply requested supply | requested > supply]
