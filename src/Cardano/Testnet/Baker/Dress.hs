{- |
Module      : Cardano.Testnet.Baker.Dress
Description : IO orchestrator that turns a bake into a dressed runtime tree.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Loads a baker output directory into the pure 'BakedOutput' type,
asks the chosen 'Profile' to compute the in-memory 'DressedOutput',
and writes the result to disk.

This module is the only place in the dressing pipeline that does
IO.  Determinism is owned by the pure 'applyProfile' function in
"Cardano.Testnet.Baker.Dressing.Profile"; the only run-time
non-determinism is the wall-clock reading used when the caller
does not supply @--system-start@.
-}
module Cardano.Testnet.Baker.Dress
    ( DressOptions (..)
    , runDress
    , dressProfiles
    ) where

import Cardano.Testnet.Baker.Dressing.Profile
    ( BakedOutput (..)
    , DressedOutput (..)
    , PoolBaked (..)
    , Profile (..)
    , applyProfile
    )
import Cardano.Testnet.Baker.Dressing.Profiles.AntithesisConfigurator
    ( antithesisConfigurator
    )
import Cardano.Testnet.Baker.Dressing.Runtime
    ( Now (..)
    , runtimeOverrides
    )
import Control.Exception (IOException, try)
import Data.Aeson (Value, eitherDecodeStrict')
import Data.Aeson qualified as Aeson
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.List (sort)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock.POSIX (POSIXTime, getPOSIXTime)
import System.Directory
    ( createDirectoryIfMissing
    , doesDirectoryExist
    , doesFileExist
    , listDirectory
    )
import System.FilePath
    ( takeDirectory
    , (</>)
    )
import System.Posix.Files (setFileMode)
import System.Posix.Types (FileMode)

-- | Inputs for the @dress@ subcommand.
data DressOptions = DressOptions
    { dressBakedDir :: !FilePath
    -- ^ Path to a baker output directory.
    , dressProfile :: !Text
    -- ^ Profile selector (e.g. @antithesis-configurator@).
    , dressOutDir :: !FilePath
    -- ^ Output runtime directory (created if absent).
    , dressNow :: !(Maybe POSIXTime)
    {- ^ Optional clock override, in UNIX seconds.  When 'Nothing',
    the runtime mold consumes the current wall-clock reading.
    -}
    }
    deriving (Eq, Show)

{- | The closed set of profiles the CLI knows about.  Library
consumers can construct their own 'Profile' values and call
'applyProfile' directly; the CLI surface is intentionally
conservative.
-}
dressProfiles :: Map Text Profile
dressProfiles =
    Map.fromList
        [ (profileName antithesisConfigurator, antithesisConfigurator)
        ]

{- | Run the @dress@ pipeline.  Returns @Left@ on any error so the
CLI can render a friendly message and exit non-zero.
-}
runDress :: DressOptions -> IO (Either String ())
runDress DressOptions{..} = case Map.lookup dressProfile dressProfiles of
    Nothing ->
        pure
            ( Left
                ( "unknown profile: "
                    <> T.unpack dressProfile
                    <> "\nknown profiles: "
                    <> show (Map.keys dressProfiles)
                )
            )
    Just profile -> do
        baked <- readBakedOutput dressBakedDir
        case baked of
            Left err -> pure (Left err)
            Right b -> do
                now <- maybe getPOSIXTime pure dressNow
                let ro = runtimeOverrides (profileRuntime profile) (Now now)
                    dressed = applyProfile profile b ro
                writeDressed dressOutDir dressed

------------------------------------------------------------------------
-- Reading a baker output directory

readBakedOutput :: FilePath -> IO (Either String BakedOutput)
readBakedOutput bakedDir = do
    exists <- doesDirectoryExist bakedDir
    if not exists
        then
            pure
                ( Left
                    ("baker output directory not found: " <> bakedDir)
                )
        else do
            genesisFiles <-
                loadJsonDir (bakedDir </> "genesis") expectedGenesisFiles
            let poolsDir = bakedDir </> "pools"
            poolsExist <- doesDirectoryExist poolsDir
            pools <-
                if poolsExist
                    then loadPools poolsDir
                    else pure []
            utxoKeys <- loadUtxoKeys (bakedDir </> "utxo-keys")
            pure $ case genesisFiles of
                Left err -> Left err
                Right gf ->
                    Right
                        BakedOutput
                            { bakedGenesisFiles = gf
                            , bakedPools = pools
                            , bakedUtxoKeys = utxoKeys
                            }

expectedGenesisFiles :: [FilePath]
expectedGenesisFiles =
    [ "config.json"
    , "alonzo-genesis.json"
    , "byron-genesis.json"
    , "conway-genesis.json"
    , "shelley-genesis.json"
    ]

loadJsonDir
    :: FilePath -> [FilePath] -> IO (Either String (Map FilePath Value))
loadJsonDir dir names = do
    pairs <- mapM (loadJsonOne dir) names
    case sequence pairs of
        Left err -> pure (Left err)
        Right kvs -> pure (Right (Map.fromList kvs))

loadJsonOne
    :: FilePath -> FilePath -> IO (Either String (FilePath, Value))
loadJsonOne dir name = do
    let path = dir </> name
    e <- try (BS.readFile path) :: IO (Either IOException ByteString)
    case e of
        Left err -> pure (Left (show err))
        Right bs -> case eitherDecodeStrict' bs of
            Left err -> pure (Left (path <> ": " <> err))
            Right v -> pure (Right (name, v))

{- | Walk @pools/@ in sorted order and read each pool's @keys/@
directory.  Sorted ordering is what assigns 'PoolIx' positions
1..N.
-}
loadPools :: FilePath -> IO [PoolBaked]
loadPools poolsDir = do
    entries <- listDirectory poolsDir
    poolDirs <-
        filterM (\e -> doesDirectoryExist (poolsDir </> e)) (sort entries)
    mapM (readPool poolsDir) poolDirs

readPool :: FilePath -> FilePath -> IO PoolBaked
readPool poolsDir label = do
    let keysDir = poolsDir </> label </> "keys"
    keysExist <- doesDirectoryExist keysDir
    keys <-
        if keysExist
            then readKeyDir keysDir
            else pure Map.empty
    pure
        PoolBaked
            { poolBakedLabel = T.pack label
            , poolBakedKeys = keys
            }

readKeyDir :: FilePath -> IO (Map FilePath ByteString)
readKeyDir dir = do
    entries <- listDirectory dir
    files <- filterM (\e -> doesFileExist (dir </> e)) entries
    Map.fromList
        <$> mapM
            ( \name -> do
                bs <- BS.readFile (dir </> name)
                pure (name, bs)
            )
            files

loadUtxoKeys :: FilePath -> IO (Map FilePath ByteString)
loadUtxoKeys dir = do
    exists <- doesDirectoryExist dir
    if not exists
        then pure Map.empty
        else readKeyDir dir

------------------------------------------------------------------------
-- Writing the dressed output

writeDressed :: FilePath -> DressedOutput -> IO (Either String ())
writeDressed outDir DressedOutput{..} = do
    createDirectoryIfMissing True outDir
    e1 <-
        try
            ( mapM_
                (\(rel, v) -> writeJsonFile (outDir </> rel) v)
                (Map.toList dressedJsonFiles)
            )
            :: IO (Either IOException ())
    case e1 of
        Left err -> pure (Left (show err))
        Right () -> do
            e2 <-
                try
                    ( mapM_
                        (\(rel, bs) -> writeBytesFile (outDir </> rel) bs)
                        (Map.toList dressedByteFiles)
                    )
                    :: IO (Either IOException ())
            case e2 of
                Left err -> pure (Left (show err))
                Right () -> pure (Right ())

writeJsonFile :: FilePath -> Value -> IO ()
writeJsonFile path v = do
    createDirectoryIfMissing True (takeDirectory path)
    LBS.writeFile path (Aeson.encode v <> "\n")

{- | Permissions cardano-node tolerates for KES / VRF / opcert files.
The bash adapter preserved baker output permissions (0o600) via
@cp@; we set them explicitly so that 'cardano-node' does not
raise @OtherPermissionsExist@ on the dressed runtime tree.
-}
keyFileMode :: FileMode
keyFileMode = 0o600

writeBytesFile :: FilePath -> ByteString -> IO ()
writeBytesFile path bs = do
    createDirectoryIfMissing True (takeDirectory path)
    BS.writeFile path bs
    setFileMode path keyFileMode

-- We avoid pulling in Control.Monad.Extra for a single filterM.
filterM :: (Monad m) => (a -> m Bool) -> [a] -> m [a]
filterM p = go
  where
    go [] = pure []
    go (x : xs) = do
        keep <- p x
        rest <- go xs
        pure (if keep then x : rest else rest)
