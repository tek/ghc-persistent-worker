module BuckArgsTest where

import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Hedgehog (TestT, evalEither, (===))
import Test.Run (assertJust, unitTest)
import Test.Tasty (TestTree, testGroup)
import Types.Args (TargetId (..))
import Types.BuckArgs (BuckArgs (..), Mode (..), parseBuckArgsCli)
import Types.Grpc (CommandEnv (..), RequestArgs (..))

-- | Typical metadata command sent by Buck.
metadataCommand :: [String]
metadataCommand =
  [
    "-M",
    "--ghc-dir", "buck/ghc_dir",
    "--worker-target-id", "singleton",
    "--build-plan", "buck/lib1.depends.json",
    "--fields", "exposed_modules,module_graph,package_deps,th_modules,cache",
    "--dep-units", "buck/lib1.json",
    "--unit", "lib1",
    "--ghc-args", "buck/lib1.args"
  ]

-- | Compile-mode command with GHC passthrough flags.
compileCommand :: [String]
compileCommand =
  [
    "-c",
    "--unit", "lib2",
    "--module", "Lib.Module",
    "-O2",
    "-package-db", "buck/db"
  ]

runParser :: [String] -> Either String BuckArgs
runParser cmd =
  parseBuckArgsCli (CommandEnv Map.empty) (RequestArgs cmd)

test_parseMetadata :: TestT IO ()
test_parseMetadata = do
  BuckArgs {..}
    <- evalEither (runParser metadataCommand)
  assertJust ModeMetadata mode
  assertJust "lib1" unit
  assertJust (TargetId "singleton") workerTargetId
  assertJust "buck/ghc_dir" ghcDirFile
  assertJust "buck/lib1.depends.json" buildPlan
  assertJust ("exposed_modules" :| ["module_graph", "package_deps", "th_modules", "cache"]) fields
  assertJust "buck/lib1.json" depUnits
  assertJust "buck/lib1.args" ghcArgsFile
  [] === ghcOptions

test_parseCompile :: TestT IO ()
test_parseCompile = do
  BuckArgs {mode, unit, moduleName, ghcOptions} <- evalEither (runParser compileCommand)
  assertJust ModeCompile mode
  assertJust "lib2" unit
  assertJust "Lib.Module" moduleName
  ["-O2", "-package-db", "buck/db"] === ghcOptions

test_parseBuckArgs :: TestTree
test_parseBuckArgs =
  testGroup "parseBuckArgsCli" [
    unitTest "metadata command" test_parseMetadata,
    unitTest "compile command" test_parseCompile
  ]
