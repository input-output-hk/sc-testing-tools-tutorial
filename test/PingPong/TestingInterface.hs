module PingPong.TestingInterface where

import Cardano.Api qualified as C
import Convex.BuildTx qualified as BuildTx
import Convex.Class (MonadMockchain, getUtxo)
import Convex.CoinSelection (ChangeOutputPosition (TrailingChange))
import Convex.MockChain.CoinSelection (tryBalanceAndSubmit)
import Convex.MockChain.Defaults qualified as Defaults
import Convex.MockChain (fromLedgerUTxO)
import Convex.TestingInterface (TestingInterface (..), ThreatModelsFor (..))
import Convex.ThreatModel.InvalidDatumIndex (invalidDatumIndexAttack)
import Convex.ThreatModel.InvalidScriptPurpose (invalidScriptPurposeAttack)
import Convex.ThreatModel.LargeData (largeDataAttack)
import Convex.ThreatModel.LargeValue (largeValueAttack)
import Convex.ThreatModel.MissingOutputDatum (missingOutputDatumAttack)
import Convex.ThreatModel.OutputDatumHashMissing (outputDatumHashMissingAttack)
import Convex.ThreatModel.UnprotectedScriptOutput (unprotectedScriptOutput)
import Convex.Wallet.MockWallet qualified as Wallet
import Control.Monad (void)
import Data.Aeson (ToJSON (..))
import Data.Map qualified as Map
import PingPong.Contract qualified as PingPong
import PingPong.Scripts qualified as Scripts
import Test.QuickCheck qualified as QC

data PingPongModel = PingPongModel
  { modelState       :: PingPong.PingPongState
  , modelInitialized :: Bool
  }
  deriving (Show, Eq)

instance ToJSON PingPong.PingPongState where
  toJSON = toJSON . show

instance ToJSON PingPongModel where
  toJSON = toJSON . show

isValidTransition :: PingPong.PingPongState -> PingPong.PingPongRedeemer -> Bool
isValidTransition st red = case (st, red) of
  (PingPong.Pinged, PingPong.Pong) -> True
  (PingPong.Pinged, PingPong.Stop) -> True
  (PingPong.Ponged, PingPong.Ping) -> True
  (PingPong.Ponged, PingPong.Stop) -> True
  _ -> False

nextStateFor :: PingPong.PingPongRedeemer -> PingPong.PingPongState
nextStateFor PingPong.Ping = PingPong.Pinged
nextStateFor PingPong.Pong = PingPong.Ponged
nextStateFor PingPong.Stop = PingPong.Stopped

instance TestingInterface PingPongModel where
  data Action PingPongModel
    = StartGame 
    | PlayRound PingPong.PingPongRedeemer
    deriving (Show, Eq)

  initialize = 
    pure PingPongModel
      { modelState = PingPong.Pinged 
      , modelInitialized = False
      }

  arbitraryAction model 
    | not (modelInitialized model) = pure StartGame
    | otherwise = PlayRound <$> QC.elements [PingPong.Ping, PingPong.Pong, PingPong.Stop]

  precondition PingPongModel{modelState, modelInitialized} action = 
    case action of 
      StartGame   -> not modelInitialized
      PlayRound r -> modelInitialized && isValidTransition modelState r

  perform model action = case action of
    StartGame -> do
      let value = 10_000_000
      void $
        tryBalanceAndSubmit
          mempty
          Wallet.w1
          ( BuildTx.execBuildTx $
              BuildTx.payToScriptInlineDatum
                Defaults.networkId
                Scripts.scriptHash
                PingPong.Pinged
                C.NoStakeAddress
                (C.lovelaceToValue value)
          )
          TrailingChange
          []
      pure model { modelState = PingPong.Pinged, modelInitialized = True }

    PlayRound redeemer -> do
      utxos <- getScriptUtxosSorted
      case utxos of
        [] -> fail "No UTxO found at script address"
        ((txIn, C.TxOut _ (C.TxOutValueShelleyBased _ val) _ _) : _) -> do
          let lovelace = C.selectLovelace (C.fromMaryValue val)
          void $
            tryBalanceAndSubmit
              mempty
              Wallet.w1
              ( BuildTx.execBuildTx $ do
                  BuildTx.spendPlutusInlineDatum txIn Scripts.pingPongValidatorScript redeemer
                  BuildTx.payToScriptInlineDatum
                    Defaults.networkId
                    Scripts.scriptHash
                    (nextStateFor redeemer)
                    C.NoStakeAddress
                    (C.lovelaceToValue lovelace)
              )
              TrailingChange
              []
          pure model { modelState = nextStateFor redeemer }

  validate PingPongModel{modelInitialized} = do
    if not modelInitialized
      then pure True
      else do
        utxos <- getScriptUtxosSorted
        case utxos of
          [_] -> pure True   -- exactly one UTxO must always remain, even once Stopped
          _   -> pure False

instance ThreatModelsFor PingPongModel where 
  threatModels =
    [ largeDataAttack
    , largeValueAttack
    , invalidDatumIndexAttack
    , invalidScriptPurposeAttack Scripts.pingPongValidatorScript
    , missingOutputDatumAttack
    , outputDatumHashMissingAttack
    , unprotectedScriptOutput
    ]
  expectedVulnerabilities = []

scriptAddress :: C.AddressInEra C.ConwayEra
scriptAddress =
  C.makeShelleyAddressInEra
    C.shelleyBasedEra
    Defaults.networkId
    (C.PaymentCredentialByScript Scripts.scriptHash)
    C.NoStakeAddress

getScriptUtxosSorted :: MonadMockchain C.ConwayEra m => m [(C.TxIn, C.TxOut C.CtxUTxO C.ConwayEra)]
getScriptUtxosSorted = do
  C.UTxO utxos <- fromLedgerUTxO C.shelleyBasedEra <$> getUtxo
  pure
    [ (txIn, txOut)
    | (txIn, txOut@(C.TxOut address _ _ _)) <- Map.toAscList utxos
    , address == scriptAddress
    ]