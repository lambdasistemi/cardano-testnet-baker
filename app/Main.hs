{- |
Module      : Main
Description : Entry point for the @cardano-testnet-baker@ CLI.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Thin executable wrapper around the library CLI.
-}
module Main
    ( main
    ) where

import Cardano.Testnet.Baker.CLI (runCLI)

main :: IO ()
main = runCLI
