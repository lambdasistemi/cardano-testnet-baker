{- |
Module      : Main
Description : Entry point for the @cardano-testnet-baker@ CLI.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Minimal scaffold CLI. Real subcommands (@bake@, @synth@,
@verify@, @scenario@) are introduced via Spec-Driven Development;
this entry point currently exposes only @--version@.
-}
module Main
    ( main
    ) where

import Cardano.Testnet.Baker (libraryVersion)
import Options.Applicative
    ( Parser
    , ParserInfo
    , execParser
    , fullDesc
    , header
    , help
    , helper
    , info
    , infoOption
    , long
    , progDesc
    , (<**>)
    )

main :: IO ()
main = do
    () <- execParser opts
    putStrLn $
        "cardano-testnet-baker "
            <> libraryVersion
            <> " — scaffold; subcommands not yet wired."

opts :: ParserInfo ()
opts =
    info
        (pure () <**> helper <**> versionOption)
        ( fullDesc
            <> progDesc
                "Bake deterministic Cardano testnet artifacts."
            <> header "cardano-testnet-baker"
        )

versionOption :: Parser (a -> a)
versionOption =
    infoOption
        ("cardano-testnet-baker " <> libraryVersion)
        (long "version" <> help "Show version and exit")
