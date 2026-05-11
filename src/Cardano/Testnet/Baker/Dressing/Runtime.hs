{- |
Module      : Cardano.Testnet.Baker.Dressing.Runtime
Description : Runtime-overrides (systemStart / startTime) for the dressing.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

A 'RuntimeMold' captures the rule a consumer applies to derive
runtime fields (@systemStart@, byron @startTime@) from a clock
reading.  The antithesis configurator rounds the wall-clock down to a
120 s boundary; alternative consumers may use a different alignment
or skip the override entirely.

The clock is passed as a 'Now' value rather than read inside the
mold so the function is pure and property tests can assert
determinism without faking the global clock.
-}
module Cardano.Testnet.Baker.Dressing.Runtime
    ( Now (..)
    , RuntimeMold (..)
    , RuntimeOverrides (..)
    , runtimeOverrides
    , antithesisRuntime
    ) where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock.POSIX
    ( POSIXTime
    , posixSecondsToUTCTime
    )
import Data.Time.Format
    ( defaultTimeLocale
    , formatTime
    )

{- | An injected clock reading.  The caller of 'runtimeOverrides' is
responsible for choosing this value — production callers read the
system clock once at the top of the IO orchestrator; tests pass a
fixed value.
-}
newtype Now = Now {unNow :: POSIXTime}
    deriving (Eq, Ord, Show)

{- | The rule for deriving runtime overrides from a clock value.

@runtimeAlign@ is the alignment quantum in seconds: the aligned
UNIX time is @(floor (unNow / runtimeAlign)) * runtimeAlign@.
-}
newtype RuntimeMold = RuntimeMold
    { runtimeAlign :: Int
    }
    deriving (Eq, Show)

{- | The values written into the shelley genesis (@systemStart@) and
the byron genesis (@startTime@) at dressing time.
-}
data RuntimeOverrides = RuntimeOverrides
    { systemStartUnix :: !Int
    -- ^ Aligned UNIX seconds since the epoch.
    , systemStartIso :: !Text
    {- ^ The same instant in ISO-8601 with second precision
    (@YYYY-MM-DDTHH:MM:SSZ@).
    -}
    }
    deriving (Eq, Show)

-- | Apply the mold's alignment rule to the supplied clock reading.
runtimeOverrides :: RuntimeMold -> Now -> RuntimeOverrides
runtimeOverrides RuntimeMold{..} (Now t) =
    RuntimeOverrides
        { systemStartUnix = aligned
        , systemStartIso = isoFromUnix aligned
        }
  where
    secondsFloor :: Int
    secondsFloor = floor t
    aligned :: Int
    aligned = (secondsFloor `div` runtimeAlign) * runtimeAlign

isoFromUnix :: Int -> Text
isoFromUnix unix =
    T.pack $
        formatTime
            defaultTimeLocale
            "%Y-%m-%dT%H:%M:%SZ"
            (posixSecondsToUTCTime (fromIntegral unix))

{- | Mold used by the @antithesis-configurator@ profile: 120 s
alignment, matching @configurator.sh@'s
@( $(date +%s) / 120 ) * 120@.
-}
antithesisRuntime :: RuntimeMold
antithesisRuntime = RuntimeMold{runtimeAlign = 120}
