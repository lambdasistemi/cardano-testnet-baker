{- |
Module      : Cardano.Testnet.Baker.CLI
Description : Command-line interface for the baker executable.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Parses and dispatches scenario validation and bake commands.
-}
module Cardano.Testnet.Baker.CLI
    ( BakeOptions (..)
    , Command (..)
    , ScenarioCommand (..)
    , parseCommandArgs
    , runBakeOptions
    , runCLI
    , runScenarioValidate
    ) where

import Cardano.Testnet.Baker.Bake
    ( BakeError (..)
    , BakeOutput (..)
    , BakeRequest (..)
    , bakeScenarioWithSynthesisRunner
    )
import Cardano.Testnet.Baker.Dress
    ( DressOptions (..)
    , runDress
    )
import Cardano.Testnet.Baker.Scenario (decodeScenarioBytes)
import Cardano.Testnet.Baker.Synthesis
    ( SynthesisError (..)
    , dbSynthesizerRunner
    )
import Cardano.Testnet.Baker.Validation
    ( ValidationFailure (..)
    , validateScenario
    )
import Cardano.Testnet.Baker.Version (libraryVersion)
import Data.ByteString.Lazy qualified as LBS
import Data.Text qualified as Text
import Data.Time.Clock.POSIX (POSIXTime)
import Options.Applicative
    ( Parser
    , ParserInfo
    , ParserResult (..)
    , argument
    , auto
    , command
    , defaultPrefs
    , execParser
    , execParserPure
    , fullDesc
    , header
    , help
    , helper
    , hsubparser
    , info
    , infoOption
    , long
    , metavar
    , option
    , optional
    , progDesc
    , renderFailure
    , str
    , strOption
    , (<**>)
    )
import System.Exit (die)

-- | Top-level CLI command.
data Command
    = CommandScenario ScenarioCommand
    | CommandBake BakeOptions
    | CommandDress DressOptions
    deriving (Eq, Show)

-- | Commands under @scenario@.
newtype ScenarioCommand
    = ScenarioValidate FilePath
    deriving (Eq, Show)

-- | Inputs for @bake@.
data BakeOptions = BakeOptions
    { bakeScenarioPath :: FilePath
    -- ^ Scenario JSON path.
    , bakeOutputDir :: FilePath
    -- ^ Output directory path.
    }
    deriving (Eq, Show)

-- | Parse command-line arguments for focused parser tests.
parseCommandArgs :: [String] -> Either String Command
parseCommandArgs args =
    case execParserPure defaultPrefs parserInfo args of
        Success command -> Right command
        Failure failure ->
            Left . fst $
                renderFailure failure "cardano-testnet-baker"
        CompletionInvoked _ ->
            Left "shell completion is not a runnable command"

-- | Parse and dispatch the executable CLI.
runCLI :: IO ()
runCLI =
    execParser parserInfo >>= runCommand

parserInfo :: ParserInfo Command
parserInfo =
    info
        (commandParser <**> helper <**> versionOption)
        ( fullDesc
            <> progDesc
                "Bake deterministic Cardano testnet artifacts."
            <> header "cardano-testnet-baker"
        )

commandParser :: Parser Command
commandParser =
    hsubparser
        ( command
            "scenario"
            ( info
                (CommandScenario <$> scenarioCommandParser)
                (progDesc "Validate scenario JSON inputs.")
            )
            <> command
                "bake"
                ( info
                    (CommandBake <$> bakeOptionsParser)
                    (progDesc "Bake deterministic artifacts.")
                )
            <> command
                "dress"
                ( info
                    (CommandDress <$> dressOptionsParser)
                    ( progDesc
                        "Dress a baker output for a consumer profile."
                    )
                )
        )

scenarioCommandParser :: Parser ScenarioCommand
scenarioCommandParser =
    hsubparser
        ( command
            "validate"
            ( info
                ( ScenarioValidate
                    <$> argument
                        str
                        (metavar "SCENARIO")
                )
                (progDesc "Run baker semantic validation.")
            )
        )

bakeOptionsParser :: Parser BakeOptions
bakeOptionsParser =
    BakeOptions
        <$> strOption
            ( long "scenario"
                <> metavar "SCENARIO"
                <> help "Scenario JSON file to bake."
            )
        <*> strOption
            ( long "out"
                <> metavar "DIR"
                <> help "Empty output directory for baked artifacts."
            )

dressOptionsParser :: Parser DressOptions
dressOptionsParser =
    DressOptions
        <$> strOption
            ( long "baked"
                <> metavar "DIR"
                <> help "Baker output directory to dress."
            )
        <*> (Text.pack <$> profileFlag)
        <*> strOption
            ( long "out"
                <> metavar "DIR"
                <> help "Runtime output directory."
            )
        <*> optional systemStartOption
  where
    profileFlag =
        strOption
            ( long "profile"
                <> metavar "NAME"
                <> help "Named consumer profile (e.g. antithesis-configurator)."
            )
    systemStartOption :: Parser POSIXTime
    systemStartOption =
        (fromIntegral :: Int -> POSIXTime)
            <$> option
                auto
                ( long "system-start"
                    <> metavar "UNIX"
                    <> help "Pin systemStart to this UNIX seconds value."
                )

versionOption :: Parser (a -> a)
versionOption =
    infoOption
        ("cardano-testnet-baker " <> libraryVersion)
        (long "version" <> help "Show version and exit")

runCommand :: Command -> IO ()
runCommand = \case
    CommandScenario (ScenarioValidate scenarioPath) ->
        runScenarioValidate scenarioPath >>= \case
            Right () -> putStrLn ("valid scenario: " <> scenarioPath)
            Left err -> die err
    CommandBake options ->
        runBakeOptions options >>= \case
            Right (BakeOutput outputDir) ->
                putStrLn ("baked artifacts: " <> outputDir)
            Left err -> die err
    CommandDress options ->
        runDress options >>= \case
            Right () ->
                putStrLn ("dressed runtime: " <> dressOutDir options)
            Left err -> die err

-- | Decode, validate, and bake a scenario from CLI options.
runBakeOptions :: BakeOptions -> IO (Either String BakeOutput)
runBakeOptions BakeOptions{..} = do
    scenarioBytes <- LBS.readFile bakeScenarioPath
    case decodeScenarioBytes scenarioBytes of
        Left err -> pure (Left ("scenario decode failed: " <> err))
        Right scenario -> do
            result <-
                bakeScenarioWithSynthesisRunner
                    (dbSynthesizerRunner "db-synthesizer")
                    BakeRequest
                        { bakeRequestScenario = scenario
                        , bakeRequestScenarioBytes = scenarioBytes
                        , bakeRequestOutputDir = bakeOutputDir
                        , bakeRequestBakerCommit = "unknown"
                        }
            pure $
                case result of
                    Right output -> Right output
                    Left err -> Left (showBakeError err)

-- | Decode and semantically validate a scenario JSON file.
runScenarioValidate :: FilePath -> IO (Either String ())
runScenarioValidate scenarioPath = do
    scenarioBytes <- LBS.readFile scenarioPath
    pure $
        case decodeScenarioBytes scenarioBytes of
            Left err -> Left ("scenario decode failed: " <> err)
            Right scenario ->
                case validateScenario scenario of
                    Right _ -> Right ()
                    Left failures ->
                        Left $
                            "scenario semantic validation failed:\n"
                                <> unlines
                                    (("- " <>) . showValidationFailure <$> failures)

showValidationFailure :: ValidationFailure -> String
showValidationFailure = \case
    NoPools -> "pools must contain at least one pool"
    NoFaucets -> "faucets must contain at least one faucet"
    DuplicatePoolLabel label ->
        "duplicate pool label: " <> Text.unpack label
    DuplicateFaucetLabel label ->
        "duplicate faucet label: " <> Text.unpack label
    FaucetFundingExceedsSupply requested supply ->
        "faucet funding "
            <> show requested
            <> " exceeds max lovelace supply "
            <> show supply
    SynthesisSlotCountRequired ->
        "synthesis slotCount is required when enabled"
    SynthesisSlotCountNotPositive slotCount ->
        "synthesis slotCount must be positive, got " <> show slotCount
    SynthesisProfileEmpty ->
        "synthesis profile must be non-empty when present"

showBakeError :: BakeError -> String
showBakeError = \case
    BakeInvalidScenario failures ->
        "scenario semantic validation failed:\n"
            <> unlines (("- " <>) . showValidationFailure <$> failures)
    BakeOutputDirectoryNotEmpty outputDir ->
        "output directory is not empty: " <> outputDir
    BakeOutputPathExistsAsFile outputDir ->
        "output path exists as a file: " <> outputDir
    BakeSynthesisFailed err ->
        "synthesis failed: " <> showSynthesisError err
    BakeIOException outputDir err ->
        "failed to write bake output at " <> outputDir <> ": " <> err

showSynthesisError :: SynthesisError -> String
showSynthesisError = \case
    SynthesisInvalidTextEnvelope name err ->
        "invalid synthesizer text envelope "
            <> Text.unpack name
            <> ": "
            <> err
    SynthesisInvalidGenesis path err ->
        "invalid synthesizer genesis copy at " <> path <> ": " <> err
    SynthesisProcessFailed executable exitCode stdout stderr ->
        executable
            <> " failed with "
            <> show exitCode
            <> output "stdout" stdout
            <> output "stderr" stderr
    SynthesisProcessException executable err ->
        executable
            <> " could not be started: "
            <> err
            <> "\nensure db-synthesizer is on PATH; with Nix use `nix run` or `nix develop`"
  where
    output label value
        | null value = ""
        | otherwise = "\n" <> label <> ":\n" <> value
