module Main where

import Test.Tasty
import Test.Tasty.HUnit

import PingPong.Contract

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
