module MetadataTest where

import Control.Monad (unless, when)
import qualified Data.List.NonEmpty as NonEmpty
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.Map.Strict as Map
import Data.Map.Strict ((!?))
import Data.Maybe (catMaybes)
import GHC (GhcException (..))
import GHC.Utils.Monad (MonadIO (..))
import GHC.Utils.Outputable (ppr, showPprUnsafe, text, (<+>))
import GHC.Utils.Panic (throwGhcExceptionIO)
import Internal.Log (dbgp, newLogger, showLog)
import Internal.Metadata (computeMetadata)
import Internal.State (dumpState)
import Prelude hiding (log)
import System.Directory (createDirectoryIfMissing, listDirectory)
import System.FilePath (takeExtension, (</>))
import TestSetup (Conf (..), ModuleSpec (..), Unit (..), UnitSpec (..), withProject)
import Types.Args (Args (..))
import Types.Env (Env (..))
import Types.Log (newLog)

stepMetadata :: Conf -> Unit -> [Unit] -> IO ()
stepMetadata Conf {state, tmp, args0} unit deps = do
  logVar <- newLog Nothing
  createDirectoryIfMissing False sessionTmpDir
  names <- listDirectory unit.dir
  let srcs = [unit.dir </> name | name <- names, takeExtension name == ".hs"]
      env = Env {log = newLogger logVar, state, args = args srcs}
  dbgp (text ">>> metadata for" <+> ppr unit.uid)
  (success, _) <- computeMetadata env
  unless success do
    liftIO $ throwGhcExceptionIO (ProgramError "Metadata failed")
  plan <- readFile jsonPath
  when False do
    putStrLn plan
    dumpState env.log state Nothing
  showLog env.log
  where
    args srcs = args0 {
      ghcOptions = mkDependArgs ++ unitDepArgs ++ args0.ghcOptions ++ srcs,
      tempDir = Just sessionTmpDir
    }

    -- unitDepArgs = concat [["-package-id", name]  | Unit {name} <- deps]

    unitDepArgs = concat [["-package-id", name, "-package-db", db]  | Unit {name, db} <- deps]

    mkDependArgs = [
      "-i",
      "-hide-all-packages",
      "-this-unit-id",
      showPprUnsafe unit.uid,
      "-dep-json=" ++ jsonPath,
      "-dep-makefile=" ++ (sessionTmpDir </> "dep.make"),
      "-include-pkg-deps",
      "-package", "template-haskell"
      ]

    jsonPath = sessionTmpDir </> "dep.json"

    sessionTmpDir = tmp </> "tmp" </> unit.name

targets1 :: NonEmpty UnitSpec
targets1 =
  [
    UnitSpec {
      name = "unit1",
      deps = [],
      modules = [
        ModuleSpec "M1_1" $ unlines [
          "module M1_1 where"
        ]
      ]
    },
    UnitSpec {
      name = "unit2",
      deps = ["unit1"],
      modules = [
        ModuleSpec "M2_1" $ unlines [
          "module M2_1 where",
          "import M1_1"
        ]
      ]
    }
  ]

testMetadata :: (Conf -> NonEmpty UnitSpec) -> IO ()
testMetadata mkSpecs = do
  log <- newLog Nothing
  let _logger = newLogger log
  withProject (pure . mkSpecs) \ conf units ->
    case units of
      [u1, u2] -> do
        let byName = Map.fromList [(unit.name, unit) | unit <- NonEmpty.toList units]
            run u = stepMetadata conf u (catMaybes [byName !? dep | dep <- u.deps])
        print u1
        print u2
        run u1
        run u2
        putStrLn =<< readFile (u2.db </> "unit2.conf")
      _ -> pure ()

-- | A very simple test consisting of two home units, using a transitive TH dependency across unit boundaries.
test_metadata :: IO ()
test_metadata =
  testMetadata (const targets1)
