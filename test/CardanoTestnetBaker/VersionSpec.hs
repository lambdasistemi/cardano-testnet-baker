{- |
Module      : CardanoTestnetBaker.VersionSpec
Description : Sanity checks for the frozen library version constant.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0
-}
module CardanoTestnetBaker.VersionSpec
    ( spec
    ) where

import CardanoTestnetBaker.Version (libraryVersion)
import Test.Hspec (Spec, describe, it, shouldSatisfy)

spec :: Spec
spec = describe "libraryVersion" $ do
    it "is non-empty" $
        libraryVersion `shouldSatisfy` (not . null)
    it "looks like a semver triple" $
        libraryVersion `shouldSatisfy` (\v -> length (filter (== '.') v) == 3)
