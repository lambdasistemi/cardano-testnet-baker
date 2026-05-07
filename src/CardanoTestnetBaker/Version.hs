{- |
Module      : CardanoTestnetBaker.Version
Description : Compile-time version of the @cardano-testnet-baker@ library.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0
-}
module CardanoTestnetBaker.Version
    ( libraryVersion
    ) where

{- | Human-readable version, sourced from the @.cabal@ file at build time
via the bundled @Paths_cardano_testnet_baker@ module would normally
supply this. We deliberately hold a frozen string here until the first
feature spec wires the cabal-derived version into the CLI; bumping
this constant in lockstep with the @.cabal@ file is enforced by the
release tooling described in the constitution.
-}
libraryVersion :: String
libraryVersion = "0.1.0.0"
