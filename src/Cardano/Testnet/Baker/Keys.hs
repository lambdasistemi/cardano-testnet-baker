{- |
Module      : Cardano.Testnet.Baker.Keys
Description : Deterministic Cardano key derivation.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Derives stake pool and faucet key material from scenario seed input.
-}
module Cardano.Testnet.Baker.Keys
    ( FaucetKeyArtifacts (..)
    , PoolKeyArtifacts (..)
    , deriveFaucetKeyArtifacts
    , derivePoolKeyArtifacts
    , faucetPaymentAddressHex
    , poolColdKeyHashHex
    , poolStakeAddressHex
    , poolStakeKeyHashHex
    , poolVrfKeyHashHex
    ) where

import Cardano.Api qualified as Api
import Cardano.Crypto.Seed qualified as Seed
import Cardano.Testnet.Baker.Determinism
    ( DerivationRole (..)
    , deriveBytes
    )
import Cardano.Testnet.Baker.Scenario
    ( FaucetDeclaration (..)
    , Network (..)
    , PoolDeclaration (..)
    )
import Cardano.Testnet.Baker.TextEnvelope (textEnvelopeBytes)
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text qualified as Text

-- | Deterministic text-envelope key material for one pool.
data PoolKeyArtifacts = PoolKeyArtifacts
    { poolColdSigningEnvelope :: LBS.ByteString
    , poolColdVerificationEnvelope :: LBS.ByteString
    , poolKesSigningEnvelope :: LBS.ByteString
    , poolVrfSigningEnvelope :: LBS.ByteString
    , poolOperationalCertificateEnvelope :: LBS.ByteString
    , poolStakeSigningEnvelope :: LBS.ByteString
    , poolStakeVerificationEnvelope :: LBS.ByteString
    }
    deriving (Eq, Show)

-- | Deterministic text-envelope key material for one faucet.
newtype FaucetKeyArtifacts = FaucetKeyArtifacts
    { faucetPaymentSigningEnvelope :: LBS.ByteString
    }
    deriving (Eq, Show)

-- | Derive all MVP pool key and operational certificate envelopes.
derivePoolKeyArtifacts
    :: ByteString -> PoolDeclaration -> PoolKeyArtifacts
derivePoolKeyArtifacts scenarioSeed pool =
    let coldSigning =
            deriveSigningKey
                Api.AsStakePoolKey
                PoolColdKey
                (poolColdKeyLabel pool)
                scenarioSeed
        kesSigning =
            deriveSigningKey
                Api.AsKesKey
                PoolKesKey
                (poolKesKeyLabel pool)
                scenarioSeed
        vrfSigning =
            deriveSigningKey
                Api.AsVrfKey
                PoolVrfKey
                (poolVrfKeyLabel pool)
                scenarioSeed
        stakeSigning =
            deriveSigningKey
                Api.AsStakeKey
                PoolStakeKey
                (poolStakeKeyLabel pool)
                scenarioSeed
        operationalCertificate =
            issuePoolOperationalCertificate coldSigning kesSigning
    in  PoolKeyArtifacts
            { poolColdSigningEnvelope =
                textEnvelopeBytes "Stake pool cold signing key" coldSigning
            , poolColdVerificationEnvelope =
                textEnvelopeBytes
                    "Stake pool cold verification key"
                    (Api.getVerificationKey coldSigning)
            , poolKesSigningEnvelope =
                textEnvelopeBytes "KES signing key" kesSigning
            , poolVrfSigningEnvelope =
                textEnvelopeBytes "VRF signing key" vrfSigning
            , poolOperationalCertificateEnvelope =
                textEnvelopeBytes
                    "Stake pool operational certificate"
                    operationalCertificate
            , poolStakeSigningEnvelope =
                textEnvelopeBytes "Stake signing key" stakeSigning
            , poolStakeVerificationEnvelope =
                textEnvelopeBytes
                    "Stake verification key"
                    (Api.getVerificationKey stakeSigning)
            }

-- | Derive the faucet payment signing key envelope.
deriveFaucetKeyArtifacts
    :: ByteString -> FaucetDeclaration -> FaucetKeyArtifacts
deriveFaucetKeyArtifacts scenarioSeed faucet =
    FaucetKeyArtifacts
        { faucetPaymentSigningEnvelope =
            textEnvelopeBytes "Faucet payment signing key" paymentSigning
        }
  where
    paymentSigning =
        deriveSigningKey
            Api.AsPaymentKey
            FaucetPaymentKey
            (faucetPaymentKeyLabel faucet)
            scenarioSeed

-- | Hex-encoded Shelley payment address funded by the Shelley genesis file.
faucetPaymentAddressHex
    :: ByteString -> Network -> FaucetDeclaration -> Text
faucetPaymentAddressHex scenarioSeed network faucet =
    Api.serialiseToRawBytesHexText $
        Api.makeShelleyAddress
            (toApiNetworkId network)
            (Api.PaymentCredentialByKey paymentKeyHash)
            Api.NoStakeAddress
  where
    paymentSigning =
        deriveSigningKey
            Api.AsPaymentKey
            FaucetPaymentKey
            (faucetPaymentKeyLabel faucet)
            scenarioSeed
    paymentKeyHash =
        Api.verificationKeyHash (Api.getVerificationKey paymentSigning)

-- | Hex-encoded stake pool cold verification key hash.
poolColdKeyHashHex :: ByteString -> PoolDeclaration -> Text
poolColdKeyHashHex scenarioSeed pool =
    serialiseVerificationKeyHashHex coldSigning
  where
    coldSigning =
        deriveSigningKey
            Api.AsStakePoolKey
            PoolColdKey
            (poolColdKeyLabel pool)
            scenarioSeed

-- | Hex-encoded pool VRF verification key hash.
poolVrfKeyHashHex :: ByteString -> PoolDeclaration -> Text
poolVrfKeyHashHex scenarioSeed pool =
    serialiseVerificationKeyHashHex vrfSigning
  where
    vrfSigning =
        deriveSigningKey
            Api.AsVrfKey
            PoolVrfKey
            (poolVrfKeyLabel pool)
            scenarioSeed

-- | Hex-encoded pool stake verification key hash.
poolStakeKeyHashHex :: ByteString -> PoolDeclaration -> Text
poolStakeKeyHashHex scenarioSeed pool =
    serialiseVerificationKeyHashHex stakeSigning
  where
    stakeSigning =
        deriveSigningKey
            Api.AsStakeKey
            PoolStakeKey
            (poolStakeKeyLabel pool)
            scenarioSeed

-- | Hex-encoded Shelley base address that carries the pool's delegated stake.
poolStakeAddressHex
    :: ByteString -> Network -> PoolDeclaration -> Text
poolStakeAddressHex scenarioSeed network pool =
    Api.serialiseToRawBytesHexText $
        Api.makeShelleyAddress
            (toApiNetworkId network)
            (Api.PaymentCredentialByKey paymentKeyHash)
            (Api.StakeAddressByValue (Api.StakeCredentialByKey stakeKeyHash))
  where
    -- Reuse the stake label deliberately: role tags separate payment and
    -- stake key derivation while preserving a stable per-pool address.
    paymentSigning =
        deriveSigningKey
            Api.AsPaymentKey
            PoolStakePaymentKey
            (poolStakeKeyLabel pool)
            scenarioSeed
    stakeSigning =
        deriveSigningKey
            Api.AsStakeKey
            PoolStakeKey
            (poolStakeKeyLabel pool)
            scenarioSeed
    paymentKeyHash =
        Api.verificationKeyHash (Api.getVerificationKey paymentSigning)
    stakeKeyHash =
        Api.verificationKeyHash (Api.getVerificationKey stakeSigning)

issuePoolOperationalCertificate
    :: Api.SigningKey Api.StakePoolKey
    -> Api.SigningKey Api.KesKey
    -> Api.OperationalCertificate
issuePoolOperationalCertificate coldSigning kesSigning =
    case Api.issueOperationalCertificate
        (Api.getVerificationKey kesSigning)
        (Left (Api.AnyStakePoolNormalSigningKey coldSigning))
        (Api.KESPeriod 0)
        ( Api.OperationalCertificateIssueCounter
            0
            (Api.getVerificationKey coldSigning)
        ) of
        Right (certificate, _) -> certificate
        Left err ->
            error $
                "failed to issue deterministic operational certificate: "
                    <> show err

deriveSigningKey
    :: (Api.Key keyrole)
    => Api.AsType keyrole
    -> DerivationRole
    -> Text
    -> ByteString
    -> Api.SigningKey keyrole
deriveSigningKey asType role label scenarioSeed =
    Api.deterministicSigningKey asType $
        Seed.mkSeedFromBytes $
            deriveBytes
                scenarioSeed
                role
                label
                (fromIntegral (Api.deterministicSigningKeySeedSize asType))

serialiseVerificationKeyHashHex
    :: (Api.HasTypeProxy keyrole, Api.Key keyrole)
    => Api.SigningKey keyrole
    -> Text
serialiseVerificationKeyHashHex =
    Api.serialiseToRawBytesHexText
        . Api.verificationKeyHash
        . Api.getVerificationKey

toApiNetworkId :: Network -> Api.NetworkId
toApiNetworkId network =
    case Text.toCaseFold (networkId network) of
        "mainnet" -> Api.Mainnet
        _ ->
            Api.Testnet . Api.NetworkMagic . fromIntegral $ networkMagic network
