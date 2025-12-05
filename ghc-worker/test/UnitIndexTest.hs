{-# LANGUAGE CPP #-}
module UnitIndexTest where

#if defined(GHC_UNIT_INDEX)

import Control.Exception (catch)
import Control.Monad (foldM)
import Control.Monad.IO.Class (MonadIO (..))
import Data.Foldable (toList)
import qualified Data.List.NonEmpty as NonEmpty
import Data.List.NonEmpty (NonEmpty)
import qualified Data.Text as Text
import Data.Text (Text)
import GHC (
  DynFlags (homeUnitId_, packageDBFlags, packageFlags),
  GeneralFlag (..),
  Ghc,
  GhcMonad (..),
  HscEnv,
  ModuleName,
  mkModuleName,
  )
import GHC.Driver.DynFlags (
  ModRenaming (..),
  PackageArg (..),
  PackageDBFlag (..),
  PackageFlag (..),
  PkgDbRef (..),
  gopt_set,
  )
import GHC.Driver.Env.Types (HscEnv (..))
import GHC.Driver.Monad (modifySession)
import GHC.Types.Unique.Map (lookupUniqMap, sizeUniqMap)
import GHC.Unit (UnitState (..), homeUnitId, initUnits, stringToUnit, stringToUnitId, unitIdString)
import GHC.Unit.Env (HomeUnitEnv (..), UnitEnv (..), ue_home_unit_graph, unitEnv_keys, unitEnv_lookup, unitEnv_new)
import GHC.Unit.State (UnitIndexQuery (..), unitIndexQuery)
import qualified GHC.Utils.Logger as GHC
import GHC.Utils.Outputable (hang, ppr, text, vcat)
import Internal.Cache.Metadata (insertHomeUnit)
import Internal.Log (dbgp, dbgs, logFlushDebug, newLogger)
import Internal.Session (runSession)
import Internal.State (newStateWith)
import Internal.State.UnitIndex (newUnitIndex)
import Prelude hiding (log)
import System.Environment (getEnv)
import qualified System.FilePath as FilePath
import TestSetup (Conf (..), ModuleSpec (..), Unit (..), UnitSpec (..), withProject)
import Types.Args (Args, emptyArgs)
import Types.Env (Env (..))
import Types.Log (newLog)
import Types.State.Oneshot (OneshotCacheFeatures (..))

#if defined(MWB_2025_07)
import System.OsPath (unsafeEncodeUtf)
#endif

args :: Args
args =
  emptyArgs []

mkEnv :: IO Env
mkEnv = do
  state <- newStateWith OneshotCacheFeatures {
    loader = False,
    enable = True,
    names = False,
    finder = False,
    eps = False
  }
  log <- newLogger <$> newLog Nothing
  pure Env {
    log,
    state,
    args
  }

depFlagRename :: String -> Bool -> [(ModuleName, ModuleName)] -> PackageFlag
depFlagRename name expose rename =
  ExposePackage ("-package " ++ name) (PackageArg name) (ModRenaming expose rename)

depFlag :: String -> PackageFlag
depFlag name =
  depFlagRename name True []

homeDep :: Word -> [PackageFlag]
homeDep num =
  [ExposePackage ("-package-id " ++ name) (UnitIdArg (stringToUnit name)) (ModRenaming True [])]
  where
    name = "unit" ++ show (num + 1)

dbFlag :: String -> PackageDBFlag
dbFlag path =
#if defined(MWB_2025_07)
  PackageDB (PkgDbPath (unsafeEncodeUtf path))
#else
  PackageDB (PkgDbPath path)
#endif

nixDb ::
  MonadIO m =>
  String ->
  m String
nixDb name = do
  pkg <- liftIO $ getEnv ("pkg_" ++ name)
  pure (pkg FilePath.</> "lib/ghc-9.10.1/lib/package.conf.d")

showUnitState ::
  HomeUnitEnv ->
  UnitIndexQuery ->
  IO ()
showUnitState unit query =
  dbgp $
  hang (ppr (maybe (text "no id") (ppr . homeUnitId) unit.homeUnitEnv_home_unit)) 2 $
  vcat [
    ppr (sizeUniqMap providers),
    ppr (unitProvider "Data.Fix"),
    ppr (unitProvider "Dep1"),
    ppr (unitProvider "DepRenamed1"),
    ppr (unitProvider "Data.Semigroup"),
    ppr (origin "Data.Fix"),
    ppr (origin "Dep1"),
    ppr (origin "DepRenamed1"),
    ppr (origin "Bad"),
    ppr (origin "Data.Semigroup")
  ]
  where
    unitProvider n = lookupUniqMap providers (mkModuleName n)

    origin n = query.findOrigin state (mkModuleName n) False

    providers = state.moduleNameProvidersMap

    state = unit.homeUnitEnv_units

addUnitType1 ::
  GHC.Logger ->
  DynFlags ->
  [PackageFlag] ->
  [PackageDBFlag] ->
  Word ->
  UnitEnv ->
  Word ->
  IO UnitEnv
addUnitType1 logger dflags0 extExpose extDbs firstNumber unit_env (index :: Word) = do
  let dflags = dflags0 {homeUnitId_ = unit, packageFlags, packageDBFlags}
#if defined(GHC_UNIT_INDEX)
  (dbs, unit_state, home_unit, _) <- initUnits logger dflags unit_env.ue_index Nothing allUnitIds
#else
  (dbs, unit_state, home_unit, _) <- initUnits logger dflags Nothing allUnitIds
#endif
  insertHomeUnit unit dflags dbs unit_state home_unit unit_env
  where
    allUnitIds = unitEnv_keys unit_env.ue_home_unit_graph

    (packageFlags, packageDBFlags) =
      if index == firstNumber
      then (extExpose, extDbs)
      else (homeDep index, [])

    unit = stringToUnitId ("unit" ++ show index)

testDepUnits :: Int -> Conf -> IO (NonEmpty UnitSpec)
testDepUnits count Conf {} =
  pure $ NonEmpty.fromList [
    UnitSpec {
      name = "dep" ++ show i,
      deps = [],
      modules = [
        ModuleSpec ("Dep" ++ show i) (content i)
      ]
    }
    |
    i <- [1..count]
  ]
  where
    content i = "module Dep" ++ show i ++ " where"

extDepNames :: [Text]
extDepNames =
  [
    "hashable",
    "data-fix",
    "semigroups"
  ]

homeUnitCount :: Word
homeUnitCount = 1

testUnitIndex ::
  [Text] ->
  NonEmpty (Unit, (Bool, [(ModuleName, ModuleName)])) ->
  HscEnv ->
  Ghc ()
testUnitIndex realDeps synthDeps HscEnv {hsc_logger, hsc_dflags, hsc_unit_env} = do
  realDbs <- traverse (fmap dbFlag . nixDb) [Text.unpack (Text.replace "-" "_" n) | n <- realDeps]
  unit_env <- liftIO $ foldM @[] (addUnitType1 hsc_logger dflags (realDepFlags ++ synthDepFlags) (realDbs ++ synthDbs) homeUnitCount) hsc_unit_env (reverse [1..homeUnitCount])
  let uid1 = stringToUnitId "unit1"
      unit1 = unitEnv_lookup uid1 unit_env.ue_home_unit_graph
  query <- unitIndexQuery uid1 unit_env.ue_index
  liftIO $ showUnitState unit1 query
  pure ()
  where
    realDepFlags = depFlag . Text.unpack <$> ("base" : realDeps)

    synthDepFlags = [uncurry (depFlagRename (unitIdString uid)) rename | (Unit {uid}, rename) <- toList synthDeps]

    synthDbs = [dbFlag db | (Unit {db}, _) <- toList synthDeps]

    dflags = gopt_set hsc_dflags Opt_HideAllPackages

withRenaming :: Unit -> (Unit, (Bool, [(ModuleName, ModuleName)]))
withRenaming unit =
  (unit, renaming unit.name)
  where
    renaming = \case
      "dep1" -> (False, [(mkModuleName "Dep1", mkModuleName "DepRenamed1")])
      _ -> (True, [])

test_unitIndex :: IO ()
test_unitIndex =
  catch main \ (err :: IOError) -> dbgs err
  where
    main =
      withProject (testDepUnits 10) \ _conf units -> do
        env <- mkEnv
        _ <- runSession True env \ _ -> do
          ue_index <- liftIO $ newUnitIndex
          modifySession \ hsc_env ->
            hsc_env {hsc_unit_env = hsc_env.hsc_unit_env {ue_index, ue_home_unit_graph = unitEnv_new []}}
          testUnitIndex extDepNames (withRenaming <$> units) =<< getSession
          pure (Just ())
        logFlushDebug env.log
        pure ()

#endif
