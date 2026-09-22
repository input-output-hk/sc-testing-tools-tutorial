module Main where

import Test.Tasty
import Test.Tasty.HUnit

import Auction.Contract
import PlutusTx.Show qualified as PlutusTx

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "Auction Tests"
    [ testCase "Auction redeemer values are represented correctly" auctionRedeemerExamples
    ]

auctionRedeemerExamples :: Assertion
auctionRedeemerExamples =
  assertEqual "Payout should render as Payout" "Payout" (PlutusTx.show Payout)
