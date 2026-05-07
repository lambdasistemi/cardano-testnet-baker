{- |
Module      : Cardano.Testnet.Baker.Bake
Description : Deterministic scenario bake orchestration.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Coordinates scenario validation, artifact staging, and publication for
the offline bake command.
-}
module Cardano.Testnet.Baker.Bake
    ( BakeError (..)
    , BakeOutput (..)
    , BakeRequest (..)
    , bakeScenarioWithoutSynthesis
    , bakeScenarioWithSynthesisRunner
    ) where

import Cardano.Testnet.Baker.Genesis (genesisArtifactBytes)
import Cardano.Testnet.Baker.Keys
    ( FaucetKeyArtifacts (..)
    , PoolKeyArtifacts (..)
    , deriveFaucetKeyArtifacts
    , derivePoolKeyArtifacts
    , faucetPaymentAddressHex
    )
import Cardano.Testnet.Baker.Metadata
    ( BakeMetadata (..)
    , Digest
    , canonicalJsonBytes
    , digestBytes
    , metadataToValue
    )
import Cardano.Testnet.Baker.Scenario
    ( FaucetDeclaration (..)
    , Network (..)
    , PoolDeclaration (..)
    , Scenario (..)
    , SynthesisRequest (..)
    )
import Cardano.Testnet.Baker.Synthesis
    ( BulkCredential
    , SynthesisError (..)
    , SynthesisRun (..)
    , SynthesisRunner (..)
    , bulkCredentialFromPoolArtifacts
    , renderBulkCredentials
    )
import Cardano.Testnet.Baker.Validation
    ( ValidationFailure
    , validateScenario
    )
import Cardano.Testnet.Baker.Version (libraryVersion)
import Control.Exception
    ( IOException
    , displayException
    , onException
    , try
    )
import Control.Monad (when)
import Data.Aeson
    ( Value (..)
    , eitherDecode
    , object
    , (.=)
    )
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Bits ((.|.))
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (for_)
import Data.List (sort)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import System.Directory
    ( copyFile
    , createDirectoryIfMissing
    , doesDirectoryExist
    , doesPathExist
    , listDirectory
    , removeDirectory
    , removePathForcibly
    , renameDirectory
    )
import System.FilePath
    ( takeDirectory
    , takeExtension
    , takeFileName
    , (</>)
    )
import System.Posix.Files
    ( ownerReadMode
    , ownerWriteMode
    , setFileMode
    )

-- | Inputs for one deterministic bake.
data BakeRequest = BakeRequest
    { bakeRequestScenario :: Scenario
    -- ^ Decoded scenario to bake.
    , bakeRequestScenarioBytes :: LBS.ByteString
    -- ^ Original scenario bytes used for provenance metadata.
    , bakeRequestOutputDir :: FilePath
    -- ^ Final output directory.
    , bakeRequestBakerCommit :: Text
    -- ^ Source revision or @dirty@ marker for metadata.
    }
    deriving (Eq, Show)

-- | Published bake output.
newtype BakeOutput = BakeOutput FilePath
    deriving (Eq, Show)

-- | Expected bake failures.
data BakeError
    = BakeInvalidScenario [ValidationFailure]
    | BakeOutputDirectoryNotEmpty FilePath
    | BakeOutputPathExistsAsFile FilePath
    | BakeSynthesisFailed SynthesisError
    | BakeIOException FilePath String
    deriving (Eq, Show)

-- | Validate, stage, and publish deterministic artifacts without synthesis.
bakeScenarioWithoutSynthesis
    :: BakeRequest -> IO (Either BakeError BakeOutput)
bakeScenarioWithoutSynthesis =
    bakeScenarioWithOptionalSynthesisRunner Nothing

-- | Bake with an injected ChainDB synthesis runner.
bakeScenarioWithSynthesisRunner
    :: SynthesisRunner
    -> BakeRequest
    -> IO (Either BakeError BakeOutput)
bakeScenarioWithSynthesisRunner runner =
    bakeScenarioWithOptionalSynthesisRunner (Just runner)

bakeScenarioWithOptionalSynthesisRunner
    :: Maybe SynthesisRunner
    -> BakeRequest
    -> IO (Either BakeError BakeOutput)
bakeScenarioWithOptionalSynthesisRunner runner request =
    case validateScenario (bakeRequestScenario request) of
        Left failures -> pure (Left (BakeInvalidScenario failures))
        Right _ -> do
            readiness <- checkOutputDirectory (bakeRequestOutputDir request)
            case readiness of
                Left failure -> pure (Left failure)
                Right () -> publishStagedOutput runner request

checkOutputDirectory :: FilePath -> IO (Either BakeError ())
checkOutputDirectory outputDir = do
    exists <- doesPathExist outputDir
    if exists
        then do
            isDirectory <- doesDirectoryExist outputDir
            if isDirectory
                then do
                    entries <- listDirectory outputDir
                    pure $
                        if null entries
                            then Right ()
                            else Left (BakeOutputDirectoryNotEmpty outputDir)
                else pure (Left (BakeOutputPathExistsAsFile outputDir))
        else pure (Right ())

publishStagedOutput
    :: Maybe SynthesisRunner
    -> BakeRequest
    -> IO (Either BakeError BakeOutput)
publishStagedOutput runner request = do
    result <- try (writeThenRename runner request)
    pure $
        case result of
            Right output -> output
            Left err ->
                Left $
                    BakeIOException
                        (bakeRequestOutputDir request)
                        (displayException (err :: IOException))

writeThenRename
    :: Maybe SynthesisRunner
    -> BakeRequest
    -> IO (Either BakeError BakeOutput)
writeThenRename runner request = do
    let outputDir = bakeRequestOutputDir request
        stageDir = stagingDirectory outputDir
    createDirectoryIfMissing True (takeDirectory outputDir)
    removeIfExists stageDir
    result <-
        writeStagedOutput runner request stageDir
            `onException` removeIfExists stageDir
    case result of
        Left err -> do
            removeIfExists stageDir
            pure (Left err)
        Right () -> do
            publish stageDir outputDir
            pure (Right (BakeOutput outputDir))

publish :: FilePath -> FilePath -> IO ()
publish stageDir outputDir = do
    outputExists <- doesDirectoryExist outputDir
    when outputExists $
        removeDirectory outputDir
    renameDirectory stageDir outputDir

writeStagedOutput
    :: Maybe SynthesisRunner
    -> BakeRequest
    -> FilePath
    -> IO (Either BakeError ())
writeStagedOutput runner request stageDir = do
    let scenario = bakeRequestScenario request
        artifactPaths = requiredArtifactPaths scenario
        generatedArtifacts =
            genesisArtifactBytes scenario <> keyArtifactBytes scenario
    createDirectoryIfMissing True stageDir
    for_ artifactPaths $ \relativePath ->
        writeArtifact stageDir scenario generatedArtifacts relativePath
    synthesisResult <- runRequestedSynthesis runner scenario stageDir
    case synthesisResult of
        Left err -> pure (Left (BakeSynthesisFailed err))
        Right () -> do
            artifactDigests <- traverse (digestArtifact stageDir) artifactPaths
            LBS.writeFile
                (stageDir </> "metadata.json")
                ( canonicalJsonBytes $
                    metadataToValue $
                        metadataFor request artifactDigests
                )
            pure (Right ())

runRequestedSynthesis
    :: Maybe SynthesisRunner
    -> Scenario
    -> FilePath
    -> IO (Either SynthesisError ())
runRequestedSynthesis Nothing _ _ =
    pure (Right ())
runRequestedSynthesis (Just runner) scenario stageDir =
    case requestedSlotCount scenario of
        Nothing -> pure (Right ())
        Just slotCount -> do
            let scratchDir = stageDir </> ".synthesis"
                bulkCredentialsPath =
                    scratchDir </> "bulk-credentials.json"
                chainDbPath = stageDir </> "chain-db"
            createDirectoryIfMissing True scratchDir
            case renderBulkCredentials (poolBulkCredentials scenario) of
                Left err -> pure (Left err)
                Right bytes -> do
                    LBS.writeFile bulkCredentialsPath bytes
                    configResult <-
                        prepareSynthesisGenesisCopy stageDir scratchDir
                    case configResult of
                        Left err -> pure (Left err)
                        Right configPath -> do
                            result <-
                                runSynthesis
                                    runner
                                    SynthesisRun
                                        { synthesisRunNodeConfigPath =
                                            configPath
                                        , synthesisRunBulkCredentialsPath =
                                            bulkCredentialsPath
                                        , synthesisRunChainDbPath =
                                            chainDbPath
                                        , synthesisRunSlotCount =
                                            slotCount
                                        }
                            case result of
                                Left err -> pure (Left err)
                                Right () -> do
                                    removeIfExists scratchDir
                                    pure (Right ())

prepareSynthesisGenesisCopy
    :: FilePath
    -> FilePath
    -> IO (Either SynthesisError FilePath)
prepareSynthesisGenesisCopy stageDir scratchDir = do
    let sourceGenesisDir = stageDir </> "genesis"
        targetGenesisDir = scratchDir </> "genesis"
        sourceShelley = sourceGenesisDir </> "shelley-genesis.json"
        targetShelley = targetGenesisDir </> "shelley-genesis.json"
    createDirectoryIfMissing True targetGenesisDir
    for_ synthesizerGenesisFiles $ \fileName ->
        copyFile
            (sourceGenesisDir </> fileName)
            (targetGenesisDir </> fileName)
    shelleyBytes <- LBS.readFile sourceShelley
    case eitherDecode shelleyBytes of
        Left err -> pure (Left (SynthesisInvalidGenesis sourceShelley err))
        Right (Object shelley) -> do
            LBS.writeFile targetShelley $
                canonicalJsonBytes $
                    Object $
                        KeyMap.insert
                            "systemStart"
                            (String "1970-01-01T00:00:00Z")
                            shelley
            pure (Right (targetGenesisDir </> "config.json"))
        Right _ ->
            pure $
                Left $
                    SynthesisInvalidGenesis
                        sourceShelley
                        "expected Shelley genesis JSON object"

synthesizerGenesisFiles :: [FilePath]
synthesizerGenesisFiles =
    [ "config.json"
    , "byron-genesis.json"
    , "alonzo-genesis.json"
    , "conway-genesis.json"
    ]

requestedSlotCount :: Scenario -> Maybe Int
requestedSlotCount scenario =
    case scenarioSynthesis scenario of
        Just synthesis
            | synthesisEnabled synthesis -> synthesisSlotCount synthesis
        _ -> Nothing

poolBulkCredentials :: Scenario -> [BulkCredential]
poolBulkCredentials scenario =
    bulkCredentialFromPoolArtifacts
        . derivePoolKeyArtifacts seed
        <$> scenarioPools scenario
  where
    seed = TextEncoding.encodeUtf8 (scenarioSeed scenario)

writeArtifact
    :: FilePath
    -> Scenario
    -> [(FilePath, LBS.ByteString)]
    -> FilePath
    -> IO ()
writeArtifact stageDir scenario keyArtifacts relativePath = do
    let path = stageDir </> relativePath
    createDirectoryIfMissing True (takeDirectory path)
    LBS.writeFile path $
        fromMaybe
            (placeholderArtifact scenario relativePath)
            (lookup relativePath keyArtifacts)
    when (isPrivateKeyPath relativePath) $
        setFileMode path (ownerReadMode .|. ownerWriteMode)

keyArtifactBytes :: Scenario -> [(FilePath, LBS.ByteString)]
keyArtifactBytes scenario =
    concatMap (poolKeyArtifactBytes seed) (scenarioPools scenario)
        <> concatMap
            (faucetKeyArtifactBytes seed (scenarioNetwork scenario))
            (scenarioFaucets scenario)
  where
    seed = TextEncoding.encodeUtf8 (scenarioSeed scenario)

poolKeyArtifactBytes
    :: ByteString -> PoolDeclaration -> [(FilePath, LBS.ByteString)]
poolKeyArtifactBytes seed pool =
    let PoolKeyArtifacts{..} = derivePoolKeyArtifacts seed pool
    in  [ (poolKeyPath pool "cold.skey", poolColdSigningEnvelope)
        , (poolKeyPath pool "cold.vkey", poolColdVerificationEnvelope)
        , (poolKeyPath pool "kes.skey", poolKesSigningEnvelope)
        , (poolKeyPath pool "vrf.skey", poolVrfSigningEnvelope)
        , (poolKeyPath pool "opcert.cert", poolOperationalCertificateEnvelope)
        , (poolKeyPath pool "stake.skey", poolStakeSigningEnvelope)
        , (poolKeyPath pool "stake.vkey", poolStakeVerificationEnvelope)
        ]

faucetKeyArtifactBytes
    :: ByteString
    -> Network
    -> FaucetDeclaration
    -> [(FilePath, LBS.ByteString)]
faucetKeyArtifactBytes seed network faucet =
    let FaucetKeyArtifacts{..} = deriveFaucetKeyArtifacts seed faucet
        addressHex = faucetPaymentAddressHex seed network faucet
    in  [ (faucetSigningKeyPath faucet, faucetPaymentSigningEnvelope)
        ,
            ( faucetAddressInfoPath faucet
            , canonicalJsonBytes $
                object
                    [ "addressHex" .= addressHex
                    , "faucetLabel" .= faucetLabel faucet
                    , "networkId" .= networkId network
                    , "networkMagic" .= networkMagic network
                    ]
            )
        ]

-- NOTE: stub for bisect-safety, replaced by the genesis/key generation slices.
placeholderArtifact :: Scenario -> FilePath -> LBS.ByteString
placeholderArtifact scenario relativePath =
    canonicalJsonBytes $
        object
            [ "placeholder" .= ("pending cardano artifact generation" :: Text)
            , "path" .= relativePath
            , "scenarioId" .= scenarioScenarioId scenario
            ]

digestArtifact :: FilePath -> FilePath -> IO (FilePath, Digest)
digestArtifact stageDir relativePath = do
    bytes <- LBS.readFile (stageDir </> relativePath)
    pure (relativePath, digestBytes (LBS.toStrict bytes))

metadataFor :: BakeRequest -> [(FilePath, Digest)] -> BakeMetadata
metadataFor BakeRequest{..} artifactDigests =
    BakeMetadata
        { metadataScenarioId = scenarioScenarioId bakeRequestScenario
        , metadataSchemaVersion = scenarioSchemaVersion bakeRequestScenario
        , metadataBakerVersion = Text.pack libraryVersion
        , metadataBakerCommit = bakeRequestBakerCommit
        , metadataInputDigest =
            digestBytes (LBS.toStrict bakeRequestScenarioBytes)
        , metadataArtifactDigests = artifactDigests
        , metadataDerivationVersion = "v1"
        , metadataCreatedBy = "cardano-testnet-baker"
        }

requiredArtifactPaths :: Scenario -> [FilePath]
requiredArtifactPaths scenario =
    sort $
        genesisPaths
            <> concatMap poolPaths (scenarioPools scenario)
            <> fmap faucetSigningKeyPath (scenarioFaucets scenario)
            <> fmap faucetAddressInfoPath (scenarioFaucets scenario)

genesisPaths :: [FilePath]
genesisPaths =
    [ "genesis/byron-genesis.json"
    , "genesis/shelley-genesis.json"
    , "genesis/alonzo-genesis.json"
    , "genesis/conway-genesis.json"
    , "genesis/config.json"
    ]

poolPaths :: PoolDeclaration -> [FilePath]
poolPaths pool =
    [ poolKeyPath pool "cold.skey"
    , poolKeyPath pool "cold.vkey"
    , poolKeyPath pool "kes.skey"
    , poolKeyPath pool "vrf.skey"
    , poolKeyPath pool "opcert.cert"
    , poolKeyPath pool "stake.skey"
    , poolKeyPath pool "stake.vkey"
    ]

poolKeyPath :: PoolDeclaration -> FilePath -> FilePath
poolKeyPath pool fileName =
    "pools"
        </> Text.unpack (poolLabel pool)
        </> "keys"
        </> fileName

faucetSigningKeyPath :: FaucetDeclaration -> FilePath
faucetSigningKeyPath faucet =
    "utxo-keys"
        </> Text.unpack (faucetLabel faucet)
            <> ".skey"

faucetAddressInfoPath :: FaucetDeclaration -> FilePath
faucetAddressInfoPath faucet =
    "utxo-keys"
        </> Text.unpack (faucetLabel faucet)
            <> ".addr.info"

stagingDirectory :: FilePath -> FilePath
stagingDirectory outputDir =
    takeDirectory outputDir
        </> ("." <> takeFileName outputDir <> ".staging")

removeIfExists :: FilePath -> IO ()
removeIfExists path = do
    exists <- doesPathExist path
    when exists $
        removePathForcibly path

isPrivateKeyPath :: FilePath -> Bool
isPrivateKeyPath path =
    takeExtension path == ".skey"
