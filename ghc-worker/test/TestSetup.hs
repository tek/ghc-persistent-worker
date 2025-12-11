{-# LANGUAGE NoFieldSelectors #-}

module TestSetup where

import Control.Concurrent (MVar)
import Data.Foldable (for_, toList)
import Data.Functor ((<&>))
import Data.List.NonEmpty (NonEmpty (..))
import Data.Traversable (for)
import GHC.Unit (UnitId, stringToUnitId, unitIdString)
import Internal.State (newStateWith)
import Prelude hiding (log)
import System.Directory (createDirectoryIfMissing, listDirectory, withCurrentDirectory)
import System.Environment (getEnv)
import System.FilePath ((<.>), (</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process.Typed (proc, runProcess_)
import Types.Args (Args (..), TargetId (..))
import Types.State (WorkerState (..))
import Types.State.Oneshot (OneshotCacheFeatures (..))
import Data.List (intersperse)

-- | Global configuration for a worker compilation test.
data Conf =
  Conf {
    -- | Root directory of the test in @/tmp@.
    tmp :: FilePath,

    -- | The worker state.
    state :: MVar WorkerState,

    -- | The base cli args used for all modules.
    args0 :: Args,

    -- | The directory containing the GHC(-pkg) binaries at @bin/@ and the settings (topdir) at @lib/ghc-*/lib/@.
    ghcDir :: FilePath,

    -- | The relative path to the topdir in 'ghcDir', with the version number spelled out.
    libPath :: FilePath
  }

-- | Config for a single test module.
data ModuleSpec =
  ModuleSpec {
    -- | Module name.
    name :: String,

    -- | The module's source code.
    content :: String
  }
  deriving stock (Eq, Show)

data Reexport =
  Reexport {
    unit :: String,
    moduleName :: String
  }
  deriving stock (Eq, Show)

-- | Config for a single test home unit.
data UnitSpec =
  UnitSpec {
    -- | Unit ID.
    name :: String,

    -- | Names of home units on which this unit depends.
    deps :: [String],

    -- | The modules belonging to this unit.
    modules :: NonEmpty ModuleSpec,

    reexports :: [Reexport],

    extraDbConf :: [String]
  }
  deriving stock (Eq, Show)

-- | Generated data for a test module.
data Module =
  Module {
    -- | Module name.
    name :: String,

    -- | Path to the source file.
    src :: FilePath,

    -- | Home unit to which this module belongs.
    unit :: String
  }
  deriving stock (Eq, Show)

-- | Generated data for a test unit.
data Unit =
  Unit {
    -- | Unit ID.
    uid :: UnitId,

    -- | Unit ID.
    name :: String,

    -- | Root source directory of this unit.
    dir :: FilePath,

    -- | Names of home units on which this unit depends.
    deps :: [String],

    -- | Path to the dummy package DB created for the metadata step, analogous to what's created by Buck.
    db :: FilePath,

    -- | The modules belonging to this unit.
    modules :: NonEmpty Module
  }
  deriving stock (Eq)

instance Show Unit where
  showsPrec d Unit {..} =
    showParen (d > 5) (
      showString "Unit { uid = "
      .
      showsPrec 5 (unitIdString uid)
      .
      showString ", name = "
      .
      showsPrec 5 name
      .
      showString ", dir = "
      .
      showsPrec 5 dir
      .
      showString ", db = "
      .
      showsPrec 5 db
      .
      showString ", modules = "
      .
      showsPrec 5 modules
      .
      showString " }"
    )

-- | General CLI args used by each module job.
baseArgs :: FilePath -> FilePath -> Args
baseArgs topdir tmp =
  Args {
    topdir = Just topdir,
    workerTargetId = Just (TargetId "test"),
    binPath = [],
    tempDir = Nothing,
    unit = Nothing,
    moduleTarget = Nothing,
    ghcOptions = (artifactDir =<< ["o", "hie", "dump"]) ++ [
      "-fwrite-ide-info",
      "-no-link",
      "-dynamic",
      -- "-fwrite-if-simplified-core",
      "-fbyte-code-and-object-code",
      "-fprefer-byte-code",
      -- "-shared",
      "-fPIC",
      "-osuf",
      "dyn_o",
      "-hisuf",
      "dyn_hi",
      "-package",
      "base"
      -- , "-v"
      -- , "-ddump-if-trace"
    ],
    cachedDeps = Nothing,
    cachedBuildPlans = Nothing,
    homeUnit = Nothing
  }
  where
    artifactDir a = ["-" ++ a ++ "dir", tmp </> "out"]

-- | A package DB config file for the given unit.
dbConf ::
  FilePath ->
  String ->
  NonEmpty Module ->
  [Reexport] ->
  [String] ->
  String
dbConf srcDir unit modules reexports extra =
  unlines $ [
    "name: " ++ unit,
    "version: 1.0",
    "id: " ++ unit,
    "key: " ++ unit,
    "import-dirs: " ++ srcDir,
    "exposed: True",
    "exposed-modules: " ++ mconcat (intersperse ", " (exposed ++ (formatReexport <$> reexports)))
  ] ++ extra
  where
    exposed = [name | Module {name} <- toList modules]

    formatReexport Reexport {unit = runit, ..} =
      moduleName ++ " from " ++ runit ++ ":" ++ moduleName

-- | Write a fresh package DB without a library to the specified directory, using @ghc-pkg@ from the directory in
-- 'Conf'.
createDb :: Conf -> String -> String -> IO String
createDb conf dir confFile = do
  createDirectoryIfMissing False db
  runProcess_ (proc ghcPkg ["-v0", "--package-db", db, "recache"])
  runProcess_ (proc ghcPkg ["-v0", "--package-db", db, "register", "--force", confFile])
  pure db
  where
    db = dir </> "package.conf.d"
    ghcPkg = conf.ghcDir </> "bin/ghc-pkg"

writeDb :: Conf -> UnitSpec -> FilePath -> String -> IO FilePath
writeDb conf unit dir db = do
  writeFile confFile db
  createDb conf dir confFile
  where
    confFile = dir </> unit.name <.> "conf"

-- | Create a package DB for a set of 'ModuleSpec' and assemble everything into a 'Unit'.
-- This is used for home units that are part of the build – like Buck, we create a package DB without any interfaces so
-- downsweep can see dependencies.
-- This is gonna be legacy soon, since we've changed metadata to use the actual home units instead, pending some
-- performance optimizations.
createEmptyHomeUnitDb :: Conf -> UnitSpec -> FilePath -> NonEmpty Module -> IO FilePath
createEmptyHomeUnitDb conf unit dir modules =
  writeDb conf unit dir (dbConf dir unit.name modules unit.reexports unit.extraDbConf)

withTmp ::
  (FilePath -> IO a) ->
  IO a
withTmp use =
  withSystemTempDirectory "buck-worker-test" \ tmp -> do
    withCurrentDirectory tmp do
      for_ @[] ["src", "tmp", "out"] \ dir ->
        createDirectoryIfMissing False (tmp </> dir)
      use tmp

-- | Set up an environment with dummy package DBs for the set of modules returned by the first argument, then run the
-- second argument with the resulting unit configurations.
withProject ::
  (Conf -> IO (NonEmpty UnitSpec)) ->
  (Conf -> NonEmpty Unit -> IO a) ->
  IO a
withProject mkTargets use =
  withTmp \ tmp -> do
    state <- newStateWith OneshotCacheFeatures {
      loader = False,
      enable = True,
      names = False,
      finder = False,
      eps = False
    }
    ghcDir <- getEnv "ghc_dir"
    libPath <- listDirectory (ghcDir </> "lib") <&> \case
      [d] -> "lib" </> d </> "lib"
      ds -> error ("weird GHC lib dir contains /= 1 entries: " ++ show ds)
    let topdir = ghcDir </> libPath
        conf = Conf {tmp, state, args0 = baseArgs topdir tmp, ..}
    targets <- mkTargets conf
    units <- for targets \ unit -> do
      let dir = tmp </> "src" </> unit.name
      createDirectoryIfMissing False dir
      modules <- for unit.modules \ ModuleSpec {name, content} -> do
        let src = dir </> name <.> "hs"
        writeFile src content
        pure Module {unit = unit.name, ..}
      db <- createEmptyHomeUnitDb conf unit dir modules
      pure Unit {
        uid = stringToUnitId unit.name,
        name = unit.name,
        deps = unit.deps,
        dir,
        db,
        modules
      }
    use conf units
