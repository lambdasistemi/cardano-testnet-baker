{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.Testnet.Baker.Dressing.AntithesisConfiguratorSpec
Description : Golden test: applyProfile equals the bash adapter's output.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Loads the JSON portion of a deterministic bake from
@test\/fixtures\/dressing\/bake-input\/@, applies the
@antithesis-configurator@ profile with a pinned 'RuntimeOverrides',
and asserts each resulting JSON file equals the bash adapter's
snapshot under @test\/fixtures\/dressing\/antithesis-configurator\/@.
-}
module Cardano.Testnet.Baker.Dressing.AntithesisConfiguratorSpec
    ( spec
    ) where

import Cardano.Testnet.Baker.Dressing.Profile
    ( BakedOutput (..)
    , DressedOutput (..)
    , PoolBaked (..)
    , applyProfile
    )
import Cardano.Testnet.Baker.Dressing.Profiles.AntithesisConfigurator
    ( antithesisConfigurator
    )
import Cardano.Testnet.Baker.Dressing.Runtime
    ( RuntimeOverrides (..)
    )
import Data.Aeson (Value, eitherDecodeFileStrict')
import Data.Map.Strict qualified as Map
import System.FilePath ((</>))
import Test.Hspec
    ( Spec
    , describe
    , it
    , runIO
    , shouldBe
    )

fixtureDir :: FilePath
fixtureDir = "test/fixtures/dressing"

bakeInputDir :: FilePath
bakeInputDir = fixtureDir </> "bake-input"

dressedFixtureDir :: FilePath
dressedFixtureDir = fixtureDir </> "antithesis-configurator"

{- | Runtime overrides matching the bash adapter snapshot
(ACCEPTANCE_START_TIME=1735689600).
-}
fixtureOverrides :: RuntimeOverrides
fixtureOverrides =
    RuntimeOverrides
        { systemStartUnix = 1735689600
        , systemStartIso = "2025-01-01T00:00:00Z"
        }

genesisFiles :: [FilePath]
genesisFiles =
    [ "config.json"
    , "alonzo-genesis.json"
    , "byron-genesis.json"
    , "conway-genesis.json"
    , "shelley-genesis.json"
    ]

loadJson :: FilePath -> IO Value
loadJson path = do
    e <- eitherDecodeFileStrict' path
    case e of
        Right v -> pure v
        Left err -> error ("loadJson " <> path <> ": " <> err)

loadBaked :: IO BakedOutput
loadBaked = do
    files <-
        mapM
            ( \name -> do
                v <- loadJson (bakeInputDir </> "genesis" </> name)
                pure (name, v)
            )
            genesisFiles
    pure
        BakedOutput
            { bakedGenesisFiles = Map.fromList files
            , -- Keys / utxo content are irrelevant for the JSON
              -- golden comparison; supply 3 empty pool stubs so the
              -- positional indexing produces p1 / p2 / p3.
              bakedPools =
                [ PoolBaked label Map.empty
                | label <- ["pool-a", "pool-b", "pool-c"]
                ]
            , bakedUtxoKeys = Map.empty
            }

dressedFixturePath :: FilePath -> FilePath
dressedFixturePath rel = dressedFixtureDir </> rel

spec :: Spec
spec = describe "Cardano.Testnet.Baker.Dressing.AntithesisConfigurator" $ do
    dressed <- runIO $ do
        baked <- loadBaked
        pure (applyProfile antithesisConfigurator baked fixtureOverrides)

    let expectedPaths =
            [ pool </> "configs" </> file
            | pool <- ["p1", "p2", "p3"]
            , file <-
                [ "config.json"
                , "alonzo-genesis.json"
                , "byron-genesis.json"
                , "conway-genesis.json"
                , "shelley-genesis.json"
                , "topology.json"
                ]
            ]

    describe "applyProfile reproduces every dressed JSON file" $
        mapM_
            ( \rel -> it ("matches the golden fixture for " <> rel) $ do
                expected <- loadJson (dressedFixturePath rel)
                Map.lookup rel (dressedJsonFiles dressed) `shouldBe` Just expected
            )
            expectedPaths
