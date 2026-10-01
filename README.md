# Testing Cardano Smart Contracts with sc-testing-tools

Smart contract bugs on Cardano can be exceptionally costly due to immutable ledger deployments and stateful UTxO dynamics. `sc-testing-tools` provides a property-based testing framework built on top of QuickCheck, specifically designed to model, generate, execute, and validate stateful smart contract interactions against simulated blockchain environments (mockchains).

At the core of this framework is the `TestingInterface` abstraction. `TestingInterface` bridges abstract, state-machine models with actual transaction building and on-chain script validation. Rather than relying solely on manually written, deterministic unit tests, property-based testing continuously generates random sequences of interactions, drives the contract through complex state transitions, and uncovers edge-case vulnerabilities.

This hands-on tutorial guides you step-by-step through building, verifying, breaking, and refining property-based tests for Cardano smart contracts using `sc-testing-tools`.

---

## 1. What You Will Build

You will build a complete property-based test suite starting from a minimal contract and progressing to a multi-asset system:

* **Ping-Pong Contract**: A state machine contract alternating between `Ping` and `Pong` actions. You will implement basic action representations, custom generators, preconditions, positive and negative execution paths, state transition models, and intentional bug discovery.
* **Auction Contract**: A multi-user smart contract featuring Ada bidding, min-bid increments, time deadlines, native token payouts, and minting operations. You will build state models, state-dependent action generators, balance tracking properties, and regression test suites.

```
                  QuickCheck
                      |
                      v
              Generated actions
                      |
                      v
              TestingInterface
                      |
                      v
             Transaction creation
                      |
                      v
                   Mockchain
                      |
                      v
              Contract execution
                      |
                      v
               New state / result
                      |
                      v
              Postconditions
                      |
                      v
                  Property

```

---

## 2. Prerequisites

Ensure your development environment meets the following requirements:

| Tool | Version | Purpose |
| --- | --- | --- |
| **GHC** | 9.6+ | Haskell compiler |
| **Cabal** | 3.8+ | Build system and package manager |
| **Nix** | 2.18+ | Reproducible environment setup |
| **Git** | 2.30+ | Source control |

---

## 3. Starting the Tutorial

Clone the playground repository containing the contract source files and testing harnesses:

```bash
git clone https://github.com/input-output-hk/sc-testing-tools-tutorial.git
cd sc-testing-tools-tutorial

```

The repository structure is organized as follows:

```
sc-testing-tools-tutorial/
├── cabal.project
├── sc-testing-tools-tutorial.cabal
├── src/
│   ├── PingPong/
│   │   ├── Contract.hs
│   │   └── Scripts.hs
│   └── Auction/
│       └── Contract.hs
└── test/
    ├── PingPong/
    │   └── Spec.hs
    └── Auction/
        └── Spec.hs

```

---

## 4. Run Before You Change Anything

Before modifying any code, enter the reproducible development environment and verify that all test suites pass.

First initialize the development environment with Nix:

```bash
nix develop
```

Then, from the Nix development environment, run all test suites:

```bash
cabal test all

```

You should see output similar to:

```text
Running 2 test suites...
Test suite tutorial-pingpong-test: PASS
Test suite tutorial-auction-test: PASS
All 2 test suites passed.

```

> **Checkpoint**
> You have confirmed that the bootstrap repository is configured correctly, builds cleanly, and all mockchain tests pass.

---

## 5. Meet the Contract: Types and Transitions

The Ping-Pong contract's state and redeemer types live in `PingPong.Contract`:

```haskell
data PingPongState = Pinged | Ponged | Stopped
data PingPongRedeemer = Ping | Pong | Stop
```

The contract has a terminal state, so only specific `(state, redeemer)` pairs are legal:

| Current state | Valid redeemer(s) | Next state |
| --- | --- | --- |
| `Pinged` | `Pong`, `Stop` | `Ponged` / `Stopped` |
| `Ponged` | `Ping`, `Stop` | `Pinged` / `Stopped` |
| `Stopped` | none | — |

We'll turn this table into two small pure functions once we have a file to put them in: one to check whether a `(state, redeemer)` pair is legal, and one to compute the state that results from applying a redeemer. Keep the table in mind — we're about to write it as code in Section 7.

---

## 6. Two Files, One Model: Splitting `TestingInterface` from `Spec`

A `TestingInterface` instance can grow large — state, actions, generators, preconditions, and the transaction-building logic all live together. Mixed into the same file as the Tasty test tree, that quickly becomes hard to navigate. So from the start, we'll keep two files with distinct responsibilities:

```
test/PingPong/
├── TestingInterface.hs   -- the model: state, actions, instance methods
└── Spec.hs               -- wiring: imports the model, builds the TestTree
```

`TestingInterface.hs` owns the state-machine model and transaction-building code. `Spec.hs` owns the Tasty test runner and small examples. The compiled validator script is kept separately in `src/PingPong/Scripts.hs` so the test interface can submit it to the mockchain.

Let's create that file now, before writing any model code, so we can confirm the build is wired correctly at every step.

### Step 1: Create the file

```bash
touch test/PingPong/TestingInterface.hs
```

Give it a module header and nothing else for now:

```haskell
module PingPong.TestingInterface where
```

### Step 2: Register the module in the `.cabal` file

Open `sc-testing-tools-tutorial.cabal` and find the `tutorial-pingpong-test` test suite stanza. The current source directories and test modules are:

```cabal
test-suite tutorial-pingpong-test
  hs-source-dirs: test src
  main-is: PingPong/Spec.hs
  other-modules:
    PingPong.Scripts
    PingPong.TestingInterface
  build-depends:
    , aeson
    , base
    , cardano-api
    , containers
    , convex-base
    , convex-coin-selection
    , convex-mockchain
    , convex-tasty-streaming
    , convex-testing-interface
    , convex-wallet
    , plutus-ledger-api
    , plutus-tx
    , plutus-tx-plugin
    , sc-testing-tools-tutorial
    , tasty
    , tasty-hunit
    , QuickCheck
```

If `other-modules` already lists something else (it may not yet, if `Spec.hs` has been the only file so far), just add `PingPong.TestingInterface` as a new line — Cabal accepts a list of modules here, one per line.

### Step 3: Import it from `Spec.hs`

Open `test/PingPong/Spec.hs` and add the import, even though nothing from it is used yet:

```haskell
import PingPong.TestingInterface
```

### Step 4: Confirm it still builds

```bash
cabal build tutorial-pingpong-test
```

This should succeed with no errors — an empty module that exports nothing is still a valid module. If Cabal complains it can't find `PingPong.TestingInterface`, double check the file lives at `test/PingPong/TestingInterface.hs` (matching the module's dotted name) and that `other-modules` was saved.

> **Checkpoint**
> You now have two linked, empty-but-compiling files instead of one large one. From here, every following section only ever edits `TestingInterface.hs` — `Spec.hs` won't need to change again until Section 12, when we wire up the actual property test.

---

## 7. Define the Model

Open `test/PingPong/TestingInterface.hs`. We track only what the test actually needs: the contract's current state, and whether the game has started (there's no script UTxO to spend before the first transaction).

Start the file with a single import — the contract types we're wrapping:

```haskell
module PingPong.TestingInterface where

import PingPong.Contract qualified as PingPong
```

Now add the model itself:

```haskell
data PingPongModel = PingPongModel
  { modelState       :: PingPong.PingPongState
  , modelInitialized :: Bool
  }
  deriving (Show, Eq)
```

`TestingInterface` needs to be able to render the model (and the states inside it) as JSON — it uses this to report what happened at each step of a run, which is invaluable when a property fails and you're reading the counterexample output. That means `PingPong.PingPongState` and `PingPongModel` both need a `ToJSON` instance. `PingPong.PingPongState` doesn't derive one on the contract side, so we provide a minimal one here based on its `Show` instance, and do the same for the model:

```haskell
import Data.Aeson (ToJSON (..))

instance ToJSON PingPong.PingPongState where
  toJSON = toJSON . show

instance ToJSON PingPongModel where
  toJSON = toJSON . show
```

This is a convenience shortcut, not a "real" JSON encoding — it just wraps whatever `Show` already produces as a JSON string, so you get readable output without hand-writing a schema for a type this small.

Now let's turn the transition table from Section 5 into code, right here alongside the model. These two pure helpers will be reused by `precondition` (Section 9) and `perform` (Section 10), and need no new imports — they only use the `PingPong` types already in scope:

```haskell
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
```

Neither function touches the mockchain or QuickCheck — they're ordinary Haskell, which makes them easy to test on their own if you ever want a plain unit test alongside the property test.

### Compile to check

```haskell
module PingPong.TestingInterface where

import Data.Aeson (ToJSON (..))
import PingPong.Contract qualified as PingPong

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
```

That's the whole file so far. Build it before moving on:

```bash
cabal build tutorial-pingpong-test
```

It should compile cleanly. If you get an error about a missing `aeson` package, add `aeson` to `build-depends` in the `tutorial-pingpong-test` stanza of your `.cabal` file (Section 6, Step 2) and try again.

---

## 8. Declare Actions, and `initialize`

`TestingInterface` uses an **associated data family** for actions — each model declares its own `Action` type inside the instance, rather than a separate top-level datatype. Add the import for the class itself:

```haskell
import Convex.TestingInterface (TestingInterface (..))
```

Then open the instance:

```haskell
instance TestingInterface PingPongModel where
  data Action PingPongModel
    = StartGame
    | PlayRound PingPong.PingPongRedeemer
    deriving (Show, Eq)

  initialize =
    pure PingPongModel
      { modelState       = PingPong.Pinged
      , modelInitialized = False
      }
```

`initialize` just describes the model's starting belief — `Pinged`, not yet on-chain. No transaction is built here.

A couple of layout details that are easy to trip over here: `data Action PingPongModel = ...` and its `deriving` clause must be indented **inside** the `instance ... where` block, at the same indentation level as `initialize` — not flush against the left margin. And the whole `instance` declaration needs a blank line (or at least consistent indentation) separating it from the top-level `isValidTransition`/`nextStateFor` definitions above it, or GHC will misparse where one declaration ends and the next begins.

### Compile to check

At this point `TestingInterface.hs` should look like:

```haskell
module PingPong.TestingInterface where

import Convex.TestingInterface (TestingInterface (..))
import Data.Aeson (ToJSON (..))
import PingPong.Contract qualified as PingPong

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
      { modelState       = PingPong.Pinged
      , modelInitialized = False
      }
```

```bash
cabal build tutorial-pingpong-test
```

The compiler will likely complain here that the `TestingInterface` instance is incomplete — `arbitraryAction`, `precondition`, `perform`, and `validate` don't have definitions yet. That's expected; we're filling them in over the next three sections. If instead you see an indentation error around `data Action PingPongModel`, check it against the block above — that's almost always a stray left-margin declaration escaping the `instance` block.

---

## 9. Generate Actions, and Guard Them with Preconditions

`arbitraryAction` proposes what to try next; `precondition` decides whether that proposal is legal given the model's current belief. Keeping them separate (rather than only generating legal actions) is what lets negative testing exist later — QuickCheck can still *propose* an illegal action, and something has to say "no."

Add the QuickCheck import, since `arbitraryAction` needs a generator:

```haskell
import Test.QuickCheck qualified as QC
```

Then fill in the two methods, inside the same `instance TestingInterface PingPongModel where` block from Section 8:

```haskell
  arbitraryAction model
    | not (modelInitialized model) = pure StartGame
    | otherwise =
        PlayRound <$> QC.elements [PingPong.Ping, PingPong.Pong, PingPong.Stop]

  precondition PingPongModel{modelState, modelInitialized} action =
    case action of
      StartGame      -> not modelInitialized
      PlayRound r    -> modelInitialized && isValidTransition modelState r
```

`isValidTransition` — defined in Section 7, right next to the model — is doing the real work here: it's the same table the on-chain validator encodes, expressed as a pure Haskell function. Section 11's `validate` step is where we'll confirm the two never drift apart.

### Compile to check

```bash
cabal build tutorial-pingpong-test
```

The instance is still incomplete — `perform` and `validate` are next — so expect the compiler to list exactly those two as missing. If `QC.elements` isn't found, confirm the `Test.QuickCheck qualified as QC` import landed at the top of the file alongside the others.

---

## 10. `perform`: Building and Submitting the Transaction

`perform` turns an accepted action into an actual balanced, submitted transaction, then returns the model's next belief. This is the only place that talks to the mockchain, so it pulls in the bulk of the file's remaining imports:

```haskell
import Cardano.Api qualified as C
import Convex.BuildTx qualified as BuildTx
import Convex.Class (MonadMockchain, getUtxo)
import Convex.CoinSelection (ChangeOutputPosition (TrailingChange))
import Convex.MockChain.CoinSelection (tryBalanceAndSubmit)
import Convex.MockChain.Defaults qualified as Defaults
import Convex.Wallet.MockWallet qualified as Wallet
import Control.Monad (void)
import Data.Map qualified as Map
import PingPong.Scripts qualified as Scripts
```

(Check these module paths against the `convex` version pinned in your `.cabal` file — some of these moved between releases, and your editor's "go to definition" is the fastest way to confirm the current location if a name doesn't resolve.)

The script hash and compiled script come from `PingPong.Scripts`, which wraps the validator from `PingPong.Contract`:

```haskell
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
                  BuildTx.spendPlutusInlineDatum
                    txIn
                    Scripts.pingPongValidatorScript
                    redeemer
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
```

Note `PlayRound Stop` still creates a continuation output, just like `Ping`/`Pong`. The on-chain validator (Section 5's transition table, enforced in `PingPong.Contract`) requires the number of script inputs and script outputs to match for *every* valid transition — there's no special case that lets a spending transaction walk away with the funds. So `Stop` doesn't withdraw anything; it re-locks the same value at the script address under the `Stopped` datum. Because the validator's transition table has no case starting from `Stopped`, that UTxO can never be spent again — the funds are locked there permanently. Keep this in mind for Section 11: the model's `validate` step needs to expect that locked UTxO to still be there, not expect it to vanish.

`perform` also calls `getScriptUtxosSorted`, which we haven't written yet — that arrives in Section 11 alongside `validate`, since both need to query the chain for the script's UTxOs. Expect the compiler to flag it as out of scope until then.

### Compile to check

```bash
cabal build tutorial-pingpong-test
```

At this point you should see exactly two problems: `validate` still missing from the instance, and `getScriptUtxosSorted` out of scope. Both get resolved in Section 11. Anything else — an import that doesn't resolve, an unrecognized `BuildTx` or `C` function — is worth fixing now, before the file gets any bigger.

> **Checkpoint**
> The model can now propose an action, check it against its own belief, and actually drive the mockchain — but nothing yet double-checks that the on-chain result *matches* the model's new belief. That's `validate`.

---

## 11. `validate`: Keeping Model and Chain in Sync

`validate` runs after every step and asks: does the real chain state actually agree with what the model *thinks* just happened? This is what catches a validator that's more permissive (or more restrictive) than the model believes.

The UTxO query uses `fromLedgerUTxO` and `getUtxo`, plus `Data.Map` to keep the result ordered:

```haskell
import Convex.MockChain (fromLedgerUTxO)
import Convex.Class (getUtxo)
import Data.Map qualified as Map
```

```haskell
  validate PingPongModel{modelInitialized} = do
    if not modelInitialized
      then pure True
      else do
        utxos <- getScriptUtxosSorted
        case utxos of
          [_] -> pure True   -- exactly one UTxO must always remain, even once Stopped
          _   -> pure False

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
```

Since `Stop` re-locks the funds rather than removing them (Section 10), exactly one UTxO must remain at the script address in *every* reachable state — running or stopped. That's why `validate` doesn't branch on `modelState` at all: the invariant is the same regardless of which state the model believes it's in. A version that special-cased `Stopped` to expect zero UTxOs would fail the very first time a run reaches that state, since the chain never actually empties the script address.

`getUtxo` comes from the same `MonadMockchain` typeclass already imported in Section 10 — no new import needed for it.

### Compile to check

The full accumulated import block at the top of `TestingInterface.hs` should now read:

```haskell
module PingPong.TestingInterface where

import PingPong.Contract qualified as PingPong
import Convex.TestingInterface (TestingInterface (..))
import Test.QuickCheck qualified as QC
import Cardano.Api qualified as C
import Convex.BuildTx qualified as BuildTx
import Convex.Class (MonadMockchain, getUtxo)
import Convex.CoinSelection (ChangeOutputPosition (TrailingChange))
import Convex.MockChain (fromLedgerUTxO)
import Convex.MockChain.CoinSelection (tryBalanceAndSubmit)
import Convex.MockChain.Defaults qualified as Defaults
import Convex.Wallet.MockWallet qualified as Wallet
import Control.Monad (void)
import Data.Map qualified as Map
import PingPong.Scripts qualified as Scripts
```

Build the whole file:

```bash
cabal build tutorial-pingpong-test
```

This should now compile with no errors at all — `initialize`, `arbitraryAction`, `precondition`, `perform`, and `validate` are all defined, and `getScriptUtxosSorted` is in scope for both `perform` and `validate` to share. If anything's still unresolved, it's worth stepping back through Sections 8–11 one method at a time rather than debugging the whole instance at once.

## 12. Wiring the Test in `Spec.hs`

Start with a deliberately small executable check: `Spec.hs` imports the contract and model modules and runs Tasty/HUnit examples for the state and redeemer display helpers. The transaction-building model is compiled as part of the same test suite, so import and type errors in `TestingInterface.hs` are still caught by the test build.

Open `test/PingPong/Spec.hs`:

```haskell
module Main where

import Test.Tasty
import Test.Tasty.HUnit

import PingPong.Contract
import PingPong.TestingInterface

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "PingPong Tests"
    [ testCase "PingPong state values are represented correctly" pingPongStateExamples
    ]

pingPongStateExamples :: Assertion
pingPongStateExamples = do
  assertEqual "Pinged should render as Pinged" "Pinged " (showState Pinged)
  assertEqual "Ponged should render as Ponged" "Ponged " (showState Ponged)
  assertEqual "Ping action should render as Ping" "Ping " (showAction Ping)
  assertEqual "Pong action should render as Pong" "Pong " (showAction Pong)
```

### Run it

```bash
cabal test tutorial-pingpong-test
```

```text
PingPong Tests
  PingPong state values are represented correctly: OK
```

> **Checkpoint**
> You now have a reproducible test command that compiles the complete PingPong model and runs the current Tasty test. The `TestingInterface` instance from Sections 7–11 is fully defined but nothing has driven it through QuickCheck yet — that's `propRunActions`, next.

---

## 13. Wiring `propRunActions`

`sc-testing-tools` ships a ready-made property, `propRunActions`, that does the work you'd otherwise hand-write around a `TestingInterface` instance: generate a sequence of actions with `arbitraryAction`, filter them with `precondition`, run each one through `perform` against a fresh mockchain, call `validate` after every step, and shrink the sequence to a minimal counterexample on failure. It also runs the whole sequence twice — once keeping only actions that satisfy their precondition (**positive** testing) and once deliberately letting precondition-violating actions through (**negative** testing) — so a single call gives you both directions for free.

Add the import to `test/PingPong/Spec.hs`:

```haskell
import Convex.TestingInterface (propRunActions)
```

Then add it to the `testGroup`, next to the existing `testCase`:

```haskell
tests :: TestTree
tests =
  testGroup
    "PingPong Tests"
    [ testCase "PingPong state values are represented correctly" pingPongStateExamples
    , propRunActions @PingPongModel "Property-based testing of PingPong contract"
    ]
```

The `@PingPongModel` type application is what tells `propRunActions` which `TestingInterface` instance to drive — there's no value of that type passed in, since `initialize` already knows how to produce one. Everything else (how many actions to generate per run, how many runs to try, how to shrink a failure) comes from the `TestingInterface` instance and QuickCheck's defaults.

`propRunActions` also needs a `ThreatModelsFor` instance for the model. Besides generating and checking ordinary actions, `propRunActions` replays every successfully-submitted transaction through a library of generic attacks (`Convex.ThreatModel.*`) — mutating it (redirecting an output, bloating a datum, forging a token...) and asserting the validator still rejects the mutated version. `threatModels` is the list of attacks to run; each one is evaluated independently and must still reject against every generated transaction it applies to.

Pick the attacks that make sense for a single-script, single-asset state machine like this one, importing each from its own `Convex.ThreatModel.*` module:

```haskell
import Convex.ThreatModel.InvalidDatumIndex (invalidDatumIndexAttack)
import Convex.ThreatModel.InvalidScriptPurpose (invalidScriptPurposeAttack)
import Convex.ThreatModel.LargeData (largeDataAttack)
import Convex.ThreatModel.LargeValue (largeValueAttack)
import Convex.ThreatModel.MissingOutputDatum (missingOutputDatumAttack)
import Convex.ThreatModel.OutputDatumHashMissing (outputDatumHashMissingAttack)
import Convex.ThreatModel.UnprotectedScriptOutput (unprotectedScriptOutput)
```

```haskell
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
```

`invalidScriptPurposeAttack` takes the compiled script as a parameter (it needs to invoke the validator directly with a mismatched script purpose), which is why it's applied to `Scripts.pingPongValidatorScript` rather than listed bare like the others. `expectedVulnerabilities` stays empty here — that list is for attacks the contract is *known* to be vulnerable to (a later section of this tutorial); every attack in `threatModels` is expected to fail against this validator.

Add this instance in `TestingInterface.hs`, alongside the `TestingInterface PingPongModel` instance, and import `ThreatModelsFor` from the same `Convex.TestingInterface` module you already import `TestingInterface` from.

### Compile to check

```bash
cabal build tutorial-pingpong-test
```

This should compile cleanly. If GHC complains about a missing `ThreatModelsFor` instance, double-check it was added for `PingPongModel` specifically — `propRunActions` resolves it via the same type application used above.

---

## 14. Running the Full Property Suite

Run the test suite the same way as before — `propRunActions` is just another entry in the same `testGroup`, so no new command is needed:

```bash
cabal test tutorial-pingpong-test
```

```text
PingPong Tests
  PingPong state values are represented correctly: OK
  Property-based testing of PingPong contract
    Positive tests:                                OK (11.52s)
      +++ OK, passed 100 tests.
    Negative tests:                                OK (1.56s)
      +++ OK, passed 100 tests.
    Threat models
      Large Data Attack:                           OK
        Tested 100/100 tests (0 precondition skipped, 0 phase 1/rebalance skipped, 0 errors)
      Large Value Attack:                          OK
        Tested 100/100 tests (0 precondition skipped, 0 phase 1/rebalance skipped, 0 errors)
      Invalid Datum Index Attack:                  OK
        Tested 100/100 tests (0 precondition skipped, 0 phase 1/rebalance skipped, 0 errors)
      Invalid Script Purpose Attack:               OK
        Tested 100/100 tests (0 precondition skipped, 0 phase 1/rebalance skipped, 0 errors)
      Missing Output Datum Attack:                 OK
        Tested 100/100 tests (0 precondition skipped, 0 phase 1/rebalance skipped, 0 errors)
      Output Datum Hash Missing Attack:            OK
        Tested 100/100 tests (0 precondition skipped, 0 phase 1/rebalance skipped, 0 errors)
      Unprotected Script Output:                   OK
        Tested 100/100 tests (0 precondition skipped, 0 phase 1/rebalance skipped, 0 errors)

All 10 tests passed (13.07s)
Test suite tutorial-pingpong-test: PASS
```

Each of the seven listed attacks replayed against every generated transaction it applies to, and all of them still failed to validate — confirming the security claims already documented in `PingPong.Contract`'s module docs (Unprotected Script Output, Large Data, Large Value) and the same for the extra four. An explicitly-listed `threatModels` entry is a coverage claim: if one of these attacks' preconditions never held across all 100 generated transactions, the suite would fail rather than silently skip it.

Each of the 100 generated runs drives the model through a random sequence of `StartGame` and `PlayRound` actions, submitting a real transaction to the mockchain for every accepted step and checking `validate` after each one. "Positive tests" only ever submit actions whose `precondition` holds; "Negative tests" also let QuickCheck propose actions that violate `precondition`, to confirm the validator genuinely rejects anything the model wouldn't allow.

> **A failure to expect**
> If `validate` ever disagrees with what the validator actually enforces, this is where it surfaces — as a `'user error (Blockchain state does not match model state)'` failure with a `--quickcheck-replay` seed you can use to reproduce the exact sequence. That's precisely what happens if `validate` (Section 11) assumes `Stop` empties the script address: the on-chain validator never does that — it re-locks the funds under `Stopped` — so the very first run that reaches `Stop` fails. Finding the implementation that's actually wrong (the model's assumption, not necessarily the validator) is the point of running this property in the first place.

> **Checkpoint**
> `PingPongModel` is now exercised end to end by QuickCheck: generated, preconditioned, executed against a mockchain, and validated — with both positive and negative runs passing. This is the full loop described in Section 1's diagram, now running for real.

---

