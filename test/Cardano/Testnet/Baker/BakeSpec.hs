{- |
Module      : Cardano.Testnet.Baker.BakeSpec
Description : Bake output layout tests.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0
-}
module Cardano.Testnet.Baker.BakeSpec
    ( spec
    ) where

import Cardano.Testnet.Baker.Bake
    ( BakeError (..)
    , BakeOutput (..)
    , BakeRequest (..)
    , bakeScenarioWithSynthesisRunner
    , bakeScenarioWithoutSynthesis
    )
import Cardano.Testnet.Baker.Keys
    ( poolColdKeyHashHex
    , poolStakeAddressHex
    , poolStakeKeyHashHex
    , poolVrfKeyHashHex
    )
import Cardano.Testnet.Baker.Metadata
    ( Digest (..)
    , digestBytes
    )
import Cardano.Testnet.Baker.Scenario
    ( PoolDeclaration (..)
    , Scenario (..)
    , decodeScenarioBytes
    )
import Cardano.Testnet.Baker.Synthesis
    ( SynthesisError (..)
    , SynthesisRun (..)
    , SynthesisRunner (..)
    )
import Control.Exception (finally)
import Control.Monad (when)
import Data.Aeson
    ( FromJSON (..)
    , eitherDecode
    , withObject
    , (.:)
    , (.:?)
    )
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Bits ((.&.), (.|.))
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (for_)
import Data.IORef
    ( newIORef
    , readIORef
    , writeIORef
    )
import Data.List
    ( isSuffixOf
    , sort
    , sortOn
    )
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import System.Directory
    ( createDirectoryIfMissing
    , doesDirectoryExist
    , doesPathExist
    , listDirectory
    , removePathForcibly
    )
import System.FilePath
    ( takeDirectory
    , (</>)
    )
import System.Posix.Files
    ( fileMode
    , getFileStatus
    , groupExecuteMode
    , groupReadMode
    , groupWriteMode
    , otherExecuteMode
    , otherReadMode
    , otherWriteMode
    )
import System.Posix.Types (FileMode)
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    , shouldReturn
    , shouldSatisfy
    )

spec :: Spec
spec = describe "bake output layout" $ do
    it "publishes the required MVP artifact paths" $
        withScratch "layout" $ \root -> do
            (scenarioBytes, scenario) <- loadMinimalScenario
            let outputDir = root </> "out"

            result <- runBake scenarioBytes scenario outputDir

            result `shouldBe` Right (BakeOutput outputDir)
            for_ requiredPaths $ \relativePath ->
                doesPathExist (outputDir </> relativePath)
                    `shouldReturn` True

    it "writes faucet funding to Shelley initialFunds" $
        withScratch "shelley-initial-funds" $ \root -> do
            (scenarioBytes, scenario) <- loadMinimalScenario
            let outputDir = root </> "out"

            result <- runBake scenarioBytes scenario outputDir

            result `shouldBe` Right (BakeOutput outputDir)
            initialFunds <-
                readShelleyInitialFundAmounts $
                    outputDir </> "genesis/shelley-genesis.json"
            initialFunds `shouldBe` [1000000000, 1000000000]

    it "stages synthesized ChainDB while preserving Shelley initial funds" $
        withScratch "synthesis-output" $ \root -> do
            (scenarioBytes, scenario) <-
                loadScenario "examples/scenarios/local-fast.json"
            let outputDir = root </> "out"
                runner =
                    SynthesisRunner $ \SynthesisRun{..} -> do
                        synthesisRunSlotCount `shouldBe` 720
                        synthesisRunNodeConfigPath
                            `shouldSatisfy` isSuffixOf
                                ".synthesis/genesis/config.json"
                        doesPathExist synthesisRunNodeConfigPath
                            `shouldReturn` True
                        scratchShelley <-
                            LBS.readFile $
                                takeDirectory synthesisRunNodeConfigPath
                                    </> "shelley-genesis.json"
                        scratchShelley
                            `shouldSatisfy` containsBytes
                                "\"systemStart\":\"1970-01-01T00:00:00Z\""
                        doesPathExist synthesisRunBulkCredentialsPath
                            `shouldReturn` True
                        createDirectoryIfMissing
                            True
                            (synthesisRunChainDbPath </> "immutable")
                        createDirectoryIfMissing
                            True
                            (synthesisRunChainDbPath </> "ledger")
                        createDirectoryIfMissing
                            True
                            (synthesisRunChainDbPath </> "volatile")
                        writeFile
                            ( synthesisRunChainDbPath
                                </> "immutable/fake.chunk"
                            )
                            "seed"
                        pure (Right ())

            result <-
                runBakeWithSynthesisRunner
                    runner
                    scenarioBytes
                    scenario
                    outputDir

            result `shouldBe` Right (BakeOutput outputDir)
            doesPathExist
                (outputDir </> "chain-db/immutable/fake.chunk")
                `shouldReturn` True
            initialFunds <-
                readShelleyInitialFundAmounts $
                    outputDir </> "genesis/shelley-genesis.json"
            initialFunds `shouldBe` [1000000000, 1000000000000]
            doesPathExist (outputDir </> ".synthesis")
                `shouldReturn` False
            finalShelley <-
                LBS.readFile $
                    outputDir </> "genesis/shelley-genesis.json"
            finalShelley
                `shouldSatisfy` not . containsBytes "systemStart"

    it "does not publish output when synthesis fails" $
        withScratch "synthesis-failure" $ \root -> do
            (scenarioBytes, scenario) <-
                loadScenario "examples/scenarios/local-fast.json"
            let outputDir = root </> "out"
                stagingDir = root </> ".out.staging"
                failure =
                    SynthesisInvalidTextEnvelope "runner" "boom"
                runner =
                    SynthesisRunner $ \SynthesisRun{..} -> do
                        createDirectoryIfMissing
                            True
                            (synthesisRunChainDbPath </> "immutable")
                        writeFile
                            ( synthesisRunChainDbPath
                                </> "immutable/partial.chunk"
                            )
                            "partial"
                        pure (Left failure)

            result <-
                runBakeWithSynthesisRunner
                    runner
                    scenarioBytes
                    scenario
                    outputDir

            result `shouldBe` Left (BakeSynthesisFailed failure)
            doesPathExist outputDir `shouldReturn` False
            doesPathExist stagingDir `shouldReturn` False

    it "does not run synthesis for genesis-only scenarios" $
        withScratch "genesis-only-synthesis-skip" $ \root -> do
            (scenarioBytes, scenario) <- loadMinimalScenario
            called <- newIORef False
            let outputDir = root </> "out"
                runner =
                    SynthesisRunner $ \_ -> do
                        writeIORef called True
                        pure (Right ())

            result <-
                runBakeWithSynthesisRunner
                    runner
                    scenarioBytes
                    scenario
                    outputDir

            result `shouldBe` Right (BakeOutput outputDir)
            readIORef called `shouldReturn` False
            doesPathExist (outputDir </> "chain-db")
                `shouldReturn` False

    it "writes faucet address info matching Shelley initialFunds" $
        withScratch "faucet-address-info" $ \root -> do
            (scenarioBytes, scenario) <- loadMinimalScenario
            let outputDir = root </> "out"

            result <- runBake scenarioBytes scenario outputDir

            result `shouldBe` Right (BakeOutput outputDir)
            addressInfo <-
                readFaucetAddressInfo $
                    outputDir </> "utxo-keys/faucet.addr.info"
            initialFundAddresses <-
                readShelleyInitialFundAddresses $
                    outputDir </> "genesis/shelley-genesis.json"
            initialFundAddresses `shouldSatisfy` elem addressInfo

    it "registers pool stake in Shelley genesis" $
        withScratch "pool-stake-registration" $ \root -> do
            (scenarioBytes, scenario) <- loadMinimalScenario
            let outputDir = root </> "out"

            result <- runBake scenarioBytes scenario outputDir

            result `shouldBe` Right (BakeOutput outputDir)
            ShelleyStakeRegistration pools delegations initialFunds <-
                readShelleyStakeRegistration $
                    outputDir </> "genesis/shelley-genesis.json"
            fmap fst pools
                `shouldBe` sort
                    [ expectedPoolColdKeyHash scenario pool
                    | pool <- scenarioPools scenario
                    ]
            for_ (scenarioPools scenario) $ \pool -> do
                let poolId = expectedPoolColdKeyHash scenario pool
                    stakeKeyHash = expectedPoolStakeKeyHash scenario pool
                    stakeAddress = expectedPoolStakeAddress scenario pool
                lookup poolId pools
                    `shouldBe` Just
                        ShelleyPoolRegistration
                            { shelleyPoolPublicKey = poolId
                            , shelleyPoolVrf =
                                expectedPoolVrfKeyHash scenario pool
                            }
                lookup stakeKeyHash delegations `shouldBe` Just poolId
                lookup stakeAddress initialFunds `shouldBe` Just (poolStake pool)

    it "rejects a non-empty output directory without deleting it" $
        withScratch "non-empty-output" $ \root -> do
            (scenarioBytes, scenario) <- loadMinimalScenario
            let outputDir = root </> "out"
                existingFile = outputDir </> "existing.txt"
            createDirectoryIfMissing True outputDir
            writeFile existingFile "existing"

            result <- runBake scenarioBytes scenario outputDir

            result
                `shouldBe` Left (BakeOutputDirectoryNotEmpty outputDir)
            doesPathExist existingFile `shouldReturn` True

    it "removes a stale staging directory before publishing" $
        withScratch "stale-staging" $ \root -> do
            (scenarioBytes, scenario) <- loadMinimalScenario
            let outputDir = root </> "out"
                stagingDir = root </> ".out.staging"
                staleFile = stagingDir </> "stale.txt"
            createDirectoryIfMissing True stagingDir
            writeFile staleFile "stale"

            result <- runBake scenarioBytes scenario outputDir

            result `shouldBe` Right (BakeOutput outputDir)
            doesPathExist staleFile `shouldReturn` False
            doesPathExist stagingDir `shouldReturn` False
            doesPathExist (outputDir </> "metadata.json")
                `shouldReturn` True

    it "writes metadata artifact digests for generated artifacts" $
        withScratch "metadata-artifact-digests" $ \root -> do
            (scenarioBytes, scenario) <- loadMinimalScenario
            let outputDir = root </> "out"

            result <- runBake scenarioBytes scenario outputDir

            result `shouldBe` Right (BakeOutput outputDir)
            actualDigests <-
                readMetadataArtifactDigests $
                    outputDir </> "metadata.json"
            expectedDigests <-
                sortOn fst
                    <$> traverse
                        (artifactDigest outputDir)
                        requiredGeneratedPaths
            actualDigests `shouldBe` expectedDigests

    it "writes byte-identical output across two runs" $
        withScratch "two-run-determinism" $ \root -> do
            (scenarioBytes, scenario) <- loadMinimalScenario
            let outputA = root </> "out-a"
                outputB = root </> "out-b"

            resultA <- runBake scenarioBytes scenario outputA
            resultB <- runBake scenarioBytes scenario outputB

            resultA `shouldBe` Right (BakeOutput outputA)
            resultB `shouldBe` Right (BakeOutput outputB)
            assertEqualTrees outputA outputB

    it "writes generated key files as text envelopes" $
        withScratch "key-envelopes" $ \root -> do
            (scenarioBytes, scenario) <- loadMinimalScenario
            let outputDir = root </> "out"

            result <- runBake scenarioBytes scenario outputDir

            result `shouldBe` Right (BakeOutput outputDir)
            coldKey <-
                LBS.readFile $
                    outputDir </> "pools/pool-a/keys/cold.skey"
            coldKey `shouldSatisfy` isTextEnvelope

    it "restricts private signing key file permissions" $
        withScratch "private-key-permissions" $ \root -> do
            (scenarioBytes, scenario) <- loadMinimalScenario
            let outputDir = root </> "out"

            result <- runBake scenarioBytes scenario outputDir

            result `shouldBe` Right (BakeOutput outputDir)
            assertNoGroupOrOtherPermissions $
                outputDir </> "pools/pool-a/keys/vrf.skey"
            assertNoGroupOrOtherPermissions $
                outputDir </> "pools/pool-a/keys/kes.skey"

    it "renders deterministic genesis and node config artifacts" $
        withScratch "genesis-config" $ \root -> do
            (scenarioBytes, scenario) <- loadMinimalScenario
            let outputDir = root </> "out"

            result <- runBake scenarioBytes scenario outputDir

            result `shouldBe` Right (BakeOutput outputDir)
            for_ genesisAndConfigPaths $ \relativePath -> do
                artifact <- LBS.readFile (outputDir </> relativePath)
                isPlaceholder artifact `shouldBe` False

    it "renders node config without development network protocol flags" $
        withScratch "node-config-flags" $ \root -> do
            (scenarioBytes, scenario) <- loadMinimalScenario
            let outputDir = root </> "out"

            result <- runBake scenarioBytes scenario outputDir

            result `shouldBe` Right (BakeOutput outputDir)
            nodeConfig <-
                readNodeConfig $
                    outputDir </> "genesis/config.json"
            nodeConfigConsensusMode nodeConfig `shouldBe` "GenesisMode"
            nodeConfigExperimentalProtocolsEnabled nodeConfig `shouldBe` False
            nodeConfigDevelopmentProtocolFlag nodeConfig `shouldBe` Nothing

    it "renders the Alonzo Plutus V1 cost model required by cardano-node" $
        withScratch "alonzo-cost-model" $ \root -> do
            (scenarioBytes, scenario) <- loadMinimalScenario
            let outputDir = root </> "out"

            result <- runBake scenarioBytes scenario outputDir

            result `shouldBe` Right (BakeOutput outputDir)
            costModelLanguages <-
                readAlonzoCostModelLanguages $
                    outputDir </> "genesis/alonzo-genesis.json"
            costModelLanguages `shouldBe` ["PlutusV1"]

    it
        "renders the Conway Plutus V3 cost model length required by cardano-node"
        $ withScratch "conway-cost-model"
        $ \root -> do
            (scenarioBytes, scenario) <- loadMinimalScenario
            let outputDir = root </> "out"

            result <- runBake scenarioBytes scenario outputDir

            result `shouldBe` Right (BakeOutput outputDir)
            costModelLength <-
                readConwayPlutusV3CostModelLength $
                    outputDir </> "genesis/conway-genesis.json"
            costModelLength `shouldBe` 251

loadMinimalScenario :: IO (LBS.ByteString, Scenario)
loadMinimalScenario =
    loadScenario "test/data/minimal-scenario.json"

loadScenario :: FilePath -> IO (LBS.ByteString, Scenario)
loadScenario path = do
    scenarioBytes <- LBS.readFile path
    case decodeScenarioBytes scenarioBytes of
        Left err -> fail err
        Right scenario -> pure (scenarioBytes, scenario)

newtype ShelleyInitialFunds = ShelleyInitialFunds [(String, Integer)]
    deriving (Eq, Show)

instance FromJSON ShelleyInitialFunds where
    parseJSON = withObject "ShelleyGenesis" $ \object -> do
        initialFunds <- object .: "initialFunds"
        ShelleyInitialFunds . sort . fmap keyTextPair . KeyMap.toList
            <$> withObject "initialFunds" (traverse parseJSON) initialFunds

newtype FaucetAddressInfo = FaucetAddressInfo String
    deriving (Eq, Show)

instance FromJSON FaucetAddressInfo where
    parseJSON = withObject "FaucetAddressInfo" $ \object ->
        FaucetAddressInfo <$> object .: "addressHex"

data ShelleyStakeRegistration
    = ShelleyStakeRegistration
        [(String, ShelleyPoolRegistration)]
        [(String, String)]
        [(String, Integer)]
    deriving (Eq, Show)

data ShelleyPoolRegistration = ShelleyPoolRegistration
    { shelleyPoolPublicKey :: String
    , shelleyPoolVrf :: String
    }
    deriving (Eq, Ord, Show)

instance FromJSON ShelleyStakeRegistration where
    parseJSON = withObject "ShelleyGenesis" $ \object -> do
        staking <- object .: "staking"
        initialFunds <- object .: "initialFunds"
        (pools, delegations) <-
            withObject "staking" parseStakingRegistration staking
        funds <-
            sort . fmap keyTextPair . KeyMap.toList
                <$> withObject "initialFunds" (traverse parseJSON) initialFunds
        pure $ ShelleyStakeRegistration pools delegations funds
      where
        parseStakingRegistration object = do
            pools <- object .: "pools"
            stake <- object .: "stake"
            parsedPools <-
                sort . fmap keyTextPair . KeyMap.toList
                    <$> withObject "pools" (traverse parseJSON) pools
            parsedStake <-
                sort . fmap keyTextPair . KeyMap.toList
                    <$> withObject "stake" (traverse parseJSON) stake
            pure (parsedPools, parsedStake)

instance FromJSON ShelleyPoolRegistration where
    parseJSON = withObject "ShelleyPool" $ \object ->
        ShelleyPoolRegistration
            <$> object .: "publicKey"
            <*> object .: "vrf"

newtype MetadataArtifactDigests = MetadataArtifactDigests [(FilePath, Digest)]
    deriving (Eq, Show)

instance FromJSON MetadataArtifactDigests where
    parseJSON = withObject "BakeMetadata" $ \object -> do
        artifactDigests <- object .: "artifactDigests"
        MetadataArtifactDigests
            . sortOn fst
            . fmap digestKeyTextPair
            . KeyMap.toList
            <$> withObject
                "artifactDigests"
                (traverse parseJSON)
                artifactDigests

data NodeConfigFields = NodeConfigFields
    { nodeConfigConsensusMode :: String
    , nodeConfigExperimentalProtocolsEnabled :: Bool
    , nodeConfigDevelopmentProtocolFlag :: Maybe Bool
    }
    deriving (Eq, Show)

instance FromJSON NodeConfigFields where
    parseJSON = withObject "NodeConfig" $ \object ->
        NodeConfigFields
            <$> object .: "ConsensusMode"
            <*> object .: "ExperimentalProtocolsEnabled"
            <*> object .:? "TestEnableDevelopmentNetworkProtocols"

newtype AlonzoCostModelLanguages = AlonzoCostModelLanguages [String]
    deriving (Eq, Show)

instance FromJSON AlonzoCostModelLanguages where
    parseJSON = withObject "AlonzoGenesis" $ \object -> do
        costModels <- object .: "costModels"
        AlonzoCostModelLanguages
            . sort
            . fmap (Key.toString . fst)
            . KeyMap.toList
            <$> withObject "costModels" pure costModels

newtype ConwayPlutusV3CostModelLength = ConwayPlutusV3CostModelLength Int
    deriving (Eq, Show)

instance FromJSON ConwayPlutusV3CostModelLength where
    parseJSON = withObject "ConwayGenesis" $ \object -> do
        costModel <- object .: "plutusV3CostModel"
        let values = costModel :: [Int]
        pure (ConwayPlutusV3CostModelLength (length values))

readShelleyInitialFundAmounts :: FilePath -> IO [Integer]
readShelleyInitialFundAmounts path =
    fmap snd <$> readShelleyInitialFunds path

readShelleyInitialFundAddresses :: FilePath -> IO [String]
readShelleyInitialFundAddresses path =
    fmap fst <$> readShelleyInitialFunds path

readShelleyInitialFunds :: FilePath -> IO [(String, Integer)]
readShelleyInitialFunds path = do
    bytes <- LBS.readFile path
    case eitherDecode bytes of
        Left err -> fail err
        Right (ShelleyInitialFunds initialFunds) ->
            pure initialFunds

readFaucetAddressInfo :: FilePath -> IO String
readFaucetAddressInfo path = do
    bytes <- LBS.readFile path
    case eitherDecode bytes of
        Left err -> fail err
        Right (FaucetAddressInfo addressHex) -> pure addressHex

readShelleyStakeRegistration
    :: FilePath -> IO ShelleyStakeRegistration
readShelleyStakeRegistration path = do
    bytes <- LBS.readFile path
    case eitherDecode bytes of
        Left err -> fail err
        Right registration -> pure registration

expectedPoolColdKeyHash :: Scenario -> PoolDeclaration -> String
expectedPoolColdKeyHash scenario pool =
    Text.unpack $ poolColdKeyHashHex (scenarioSeedBytes scenario) pool

expectedPoolStakeKeyHash :: Scenario -> PoolDeclaration -> String
expectedPoolStakeKeyHash scenario pool =
    Text.unpack $ poolStakeKeyHashHex (scenarioSeedBytes scenario) pool

expectedPoolVrfKeyHash :: Scenario -> PoolDeclaration -> String
expectedPoolVrfKeyHash scenario pool =
    Text.unpack $ poolVrfKeyHashHex (scenarioSeedBytes scenario) pool

expectedPoolStakeAddress :: Scenario -> PoolDeclaration -> String
expectedPoolStakeAddress scenario pool =
    Text.unpack $
        poolStakeAddressHex
            (scenarioSeedBytes scenario)
            (scenarioNetwork scenario)
            pool

scenarioSeedBytes :: Scenario -> BS.ByteString
scenarioSeedBytes =
    TextEncoding.encodeUtf8 . scenarioSeed

readMetadataArtifactDigests :: FilePath -> IO [(FilePath, Digest)]
readMetadataArtifactDigests path = do
    bytes <- LBS.readFile path
    case eitherDecode bytes of
        Left err -> fail err
        Right (MetadataArtifactDigests artifactDigests) ->
            pure artifactDigests

readNodeConfig :: FilePath -> IO NodeConfigFields
readNodeConfig path = do
    bytes <- LBS.readFile path
    case eitherDecode bytes of
        Left err -> fail err
        Right nodeConfig -> pure nodeConfig

readAlonzoCostModelLanguages :: FilePath -> IO [String]
readAlonzoCostModelLanguages path = do
    bytes <- LBS.readFile path
    case eitherDecode bytes of
        Left err -> fail err
        Right (AlonzoCostModelLanguages costModelLanguages) ->
            pure costModelLanguages

readConwayPlutusV3CostModelLength :: FilePath -> IO Int
readConwayPlutusV3CostModelLength path = do
    bytes <- LBS.readFile path
    case eitherDecode bytes of
        Left err -> fail err
        Right (ConwayPlutusV3CostModelLength costModelLength) ->
            pure costModelLength

keyTextPair :: (Key.Key, value) -> (String, value)
keyTextPair (key, amount) = (Key.toString key, amount)

digestKeyTextPair :: (Key.Key, Text) -> (FilePath, Digest)
digestKeyTextPair (key, digest) = (Key.toString key, Digest digest)

artifactDigest :: FilePath -> FilePath -> IO (FilePath, Digest)
artifactDigest root relativePath = do
    bytes <- LBS.readFile (root </> relativePath)
    pure (relativePath, digestBytes (LBS.toStrict bytes))

assertNoGroupOrOtherPermissions :: FilePath -> IO ()
assertNoGroupOrOtherPermissions path = do
    status <- getFileStatus path
    fileMode status .&. nonOwnerModes `shouldBe` 0

runBake
    :: LBS.ByteString
    -> Scenario
    -> FilePath
    -> IO (Either BakeError BakeOutput)
runBake scenarioBytes scenario outputDir =
    bakeScenarioWithoutSynthesis
        BakeRequest
            { bakeRequestScenario = scenario
            , bakeRequestScenarioBytes = scenarioBytes
            , bakeRequestOutputDir = outputDir
            , bakeRequestBakerCommit = "test"
            }

runBakeWithSynthesisRunner
    :: SynthesisRunner
    -> LBS.ByteString
    -> Scenario
    -> FilePath
    -> IO (Either BakeError BakeOutput)
runBakeWithSynthesisRunner runner scenarioBytes scenario outputDir =
    bakeScenarioWithSynthesisRunner
        runner
        BakeRequest
            { bakeRequestScenario = scenario
            , bakeRequestScenarioBytes = scenarioBytes
            , bakeRequestOutputDir = outputDir
            , bakeRequestBakerCommit = "test"
            }

withScratch :: FilePath -> (FilePath -> IO ()) -> IO ()
withScratch name action = do
    let root = "tmp/unit" </> name
    removeIfExists root
    createDirectoryIfMissing True root
    action root `finally` removeIfExists root

removeIfExists :: FilePath -> IO ()
removeIfExists path = do
    exists <- doesPathExist path
    when exists $
        removePathForcibly path

nonOwnerModes :: FileMode
nonOwnerModes =
    groupReadMode
        .|. groupWriteMode
        .|. groupExecuteMode
        .|. otherReadMode
        .|. otherWriteMode
        .|. otherExecuteMode

assertEqualTrees :: FilePath -> FilePath -> IO ()
assertEqualTrees left right = do
    leftFiles <- recursiveFiles left
    rightFiles <- recursiveFiles right
    leftFiles `shouldBe` rightFiles
    for_ leftFiles $ \relativePath -> do
        leftBytes <- LBS.readFile (left </> relativePath)
        rightBytes <- LBS.readFile (right </> relativePath)
        leftBytes `shouldBe` rightBytes

recursiveFiles :: FilePath -> IO [FilePath]
recursiveFiles root =
    go ""
  where
    go relative = do
        let dir = if null relative then root else root </> relative
        entries <- sort <$> listDirectory dir
        concat <$> traverse (collect relative) entries

    collect relative entry = do
        let relativePath =
                if null relative
                    then entry
                    else relative </> entry
            fullPath = root </> relativePath
        isDirectory <- doesDirectoryExist fullPath
        if isDirectory
            then go relativePath
            else pure [relativePath]

requiredPaths :: [FilePath]
requiredPaths =
    [ "genesis/byron-genesis.json"
    , "genesis/shelley-genesis.json"
    , "genesis/alonzo-genesis.json"
    , "genesis/conway-genesis.json"
    , "genesis/config.json"
    , "pools/pool-a/keys/cold.skey"
    , "pools/pool-a/keys/cold.vkey"
    , "pools/pool-a/keys/kes.skey"
    , "pools/pool-a/keys/vrf.skey"
    , "pools/pool-a/keys/opcert.cert"
    , "pools/pool-a/keys/stake.skey"
    , "pools/pool-a/keys/stake.vkey"
    , "utxo-keys/faucet.skey"
    , "utxo-keys/faucet.addr.info"
    , "metadata.json"
    ]

requiredGeneratedPaths :: [FilePath]
requiredGeneratedPaths =
    filter (/= "metadata.json") requiredPaths

genesisAndConfigPaths :: [FilePath]
genesisAndConfigPaths =
    [ "genesis/byron-genesis.json"
    , "genesis/shelley-genesis.json"
    , "genesis/alonzo-genesis.json"
    , "genesis/conway-genesis.json"
    , "genesis/config.json"
    ]

isTextEnvelope :: LBS.ByteString -> Bool
isTextEnvelope bytes =
    BS.isInfixOf "\"type\"" strictBytes
        && BS.isInfixOf "\"description\"" strictBytes
        && BS.isInfixOf "\"cborHex\"" strictBytes
  where
    strictBytes = LBS.toStrict bytes

containsBytes :: BS.ByteString -> LBS.ByteString -> Bool
containsBytes needle bytes =
    BS.isInfixOf needle (LBS.toStrict bytes)

isPlaceholder :: LBS.ByteString -> Bool
isPlaceholder bytes =
    BS.isInfixOf "\"placeholder\"" (LBS.toStrict bytes)
