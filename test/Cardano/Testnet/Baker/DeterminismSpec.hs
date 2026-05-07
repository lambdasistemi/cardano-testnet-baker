{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.Testnet.Baker.DeterminismSpec
Description : HKDF-based deterministic derivation tests.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0
-}
module Cardano.Testnet.Baker.DeterminismSpec
    ( spec
    ) where

import Cardano.Testnet.Baker.Determinism
    ( DerivationRole (..)
    , derivationDomain
    , deriveBytes
    )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe)

spec :: Spec
spec = describe "deterministic derivation" $ do
    it "uses the v1 baker domain" $
        derivationDomain `shouldBe` "cardano-testnet-baker/v1"

    it "matches the HKDF-SHA256 test vector for a pool cold key" $
        deriveBytes seed PoolColdKey "pool-a" 32
            `shouldBe` expectedPoolColdKey

    it "is stable for identical role and label inputs" $
        deriveBytes seed FaucetPaymentKey "genesis.1" 32
            `shouldBe` deriveBytes seed FaucetPaymentKey "genesis.1" 32

    it "separates roles and labels" $ do
        deriveBytes seed PoolColdKey "pool-a" 32
            `shouldNotBe` deriveBytes seed PoolVrfKey "pool-a" 32
        deriveBytes seed PoolColdKey "pool-a" 32
            `shouldNotBe` deriveBytes seed PoolColdKey "pool-b" 32

    it "honors the requested output length" $
        BS.length (deriveBytes seed PoolKesKey "pool-a" 96) `shouldBe` 96

seed :: ByteString
seed = BS.pack [0 .. 31]

expectedPoolColdKey :: ByteString
expectedPoolColdKey =
    BS.pack
        [ 0xba
        , 0x3e
        , 0x55
        , 0xe5
        , 0x68
        , 0xf3
        , 0xc4
        , 0xe1
        , 0x27
        , 0x85
        , 0xb6
        , 0x14
        , 0x67
        , 0xd4
        , 0xf9
        , 0x82
        , 0xf3
        , 0x7f
        , 0x5e
        , 0xcd
        , 0xf6
        , 0xab
        , 0xa5
        , 0x67
        , 0x6b
        , 0x9f
        , 0xda
        , 0x8d
        , 0xe8
        , 0x8c
        , 0x8a
        , 0xe5
        ]
