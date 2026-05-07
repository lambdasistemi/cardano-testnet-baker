{- |
Module      : Cardano.Testnet.Baker.TextEnvelope
Description : Cardano text-envelope rendering.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Provides helpers for writing deterministic Cardano text-envelope JSON
artifacts.
-}
module Cardano.Testnet.Baker.TextEnvelope
    ( textEnvelopeBytes
    ) where

import Cardano.Api.Serialise.TextEnvelope
    ( HasTextEnvelope
    , TextEnvelopeDescr
    , textEnvelopeToJSON
    )
import Data.ByteString.Lazy (ByteString)

-- | Render a Cardano value as text-envelope JSON bytes.
textEnvelopeBytes
    :: (HasTextEnvelope a) => TextEnvelopeDescr -> a -> ByteString
textEnvelopeBytes description =
    textEnvelopeToJSON (Just description)
