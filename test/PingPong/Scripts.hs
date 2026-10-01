{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE TemplateHaskell #-}

module PingPong.Scripts where

import Cardano.Api qualified as C
import Convex.PlutusTx (compiledCodeToScript)
import PingPong.Contract qualified as PingPong
import PlutusTx (CompiledCode)
import PlutusTx.Prelude (BuiltinData, BuiltinUnit)
import PlutusTx qualified

pingPongValidatorCompiled :: CompiledCode (BuiltinData -> BuiltinUnit)
pingPongValidatorCompiled = $$(PlutusTx.compile [||PingPong.validator||])

pingPongValidatorScript :: C.PlutusScript C.PlutusScriptV3
pingPongValidatorScript = compiledCodeToScript pingPongValidatorCompiled

scriptHash :: C.ScriptHash
scriptHash = C.hashScript (C.PlutusScript C.PlutusScriptV3 pingPongValidatorScript)