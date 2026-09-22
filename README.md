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
sc-testing-tools-playground/
├── cabal.project
├── sc-testing-tools-playground.cabal
├── src/
│   ├── PingPong/
│   │   └── Contract.hs
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

