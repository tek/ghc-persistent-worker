{-# LANGUAGE CPP #-}

module UnitIndexTest where

#if defined(UNIT_INDEX)

import Control.Exception (catch)
import Control.Monad (foldM)
import Control.Monad.IO.Class (MonadIO (..))
import Data.Foldable (for_, toList)
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
import GHC.Unit.Env (HomeUnitEnv (..), UnitEnv (..), ue_home_unit_graph)
import GHC.Unit.State (UnitIndexQuery (..), unitIndexQuery)
import qualified GHC.Utils.Logger as GHC
import GHC.Utils.Outputable (hang, parens, ppr, text, vcat, (<+>))
import Internal.Cache.Metadata (insertHomeUnit)
import Internal.Log (dbgp, dbgs, logFlushDebug, newLogger)
import Internal.Session (runSession)
import Internal.State (newStateWith)
import Internal.State.UnitIndex (newUnitIndex)
import Prelude hiding (log)
import TestSetup (Conf (..), ModuleSpec (..), Reexport (..), Unit (..), UnitSpec (..), withProject)
import Types.Args (Args, emptyArgs)
import Types.Env (Env (..))
import Types.Log (newLog)
import Types.State.Oneshot (OneshotCacheFeatures (..))

#if defined(MWB)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes)
import GHC.Unit.Home.Graph (unitEnv_keys, unitEnv_lookup, unitEnv_new)
import System.OsPath (unsafeEncodeUtf)

#else

import GHC.Unit.Env (unitEnv_keys, unitEnv_lookup, unitEnv_new)

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
    name = "unit" ++ show (num - 1)

dbFlag :: String -> PackageDBFlag
dbFlag path =
#if defined(MWB)
  PackageDB (PkgDbPath (unsafeEncodeUtf path))
#else
  PackageDB (PkgDbPath path)
#endif

testDepUnits :: Int -> Conf -> IO (NonEmpty UnitSpec)
testDepUnits count Conf {} =
  pure $ NonEmpty.fromList $ [
    UnitSpec {
      name = "dep" ++ show i,
      deps = [],
      modules = [
        ModuleSpec ("Dep" ++ show i) (content i)
      ],
      reexports = [],
      extraDbConf = []
    }
    |
    i <- [1..count]
  ] ++ [
    UnitSpec {
      name = "depre",
      deps = ["dep2"],
      modules = [
        ModuleSpec "DepRe" "module DepRe where"
      ],
      reexports = [Reexport {unit = "dep2", moduleName = "Dep2"}],
      extraDbConf = [
        "depends: dep2"
      ]
    }
  ]
  where
    content i = "module Dep" ++ show i ++ " where"

homeUnits1 :: NonEmpty (String, [Text])
homeUnits1 =
  [
    ("unit1", ["dep1", "dep2"]),
    ("unit2", ["unit1", "depre"])
  ]

homeUnitCount :: Word
homeUnitCount = 2

addUnit ::
  GHC.Logger ->
  DynFlags ->
  [PackageFlag] ->
  [PackageDBFlag] ->
  String ->
  UnitEnv ->
  IO UnitEnv
addUnit logger dflags0 packageFlags packageDBFlags name unit_env = do
  let dflags = dflags0 {homeUnitId_ = unit, packageFlags, packageDBFlags}
#if defined(UNIT_INDEX)
  (dbs, unit_state, home_unit, _) <- initUnits logger dflags unit_env.ue_index Nothing allUnitIds
#else
  (dbs, unit_state, home_unit, _) <- initUnits logger dflags Nothing allUnitIds
#endif
  insertHomeUnit unit dflags dbs unit_state home_unit unit_env
  where
    allUnitIds = unitEnv_keys unit_env.ue_home_unit_graph

    unit = stringToUnitId name

addUnitType1 ::
  GHC.Logger ->
  DynFlags ->
  [PackageFlag] ->
  [PackageDBFlag] ->
  Word ->
  UnitEnv ->
  Word ->
  IO UnitEnv
addUnitType1 logger dflags0 extExpose extDbs firstNumber unit_env (index :: Word) =
  addUnit logger dflags0 packageFlags packageDBFlags ("unit" ++ show index) unit_env
  where
    (packageFlags, packageDBFlags) =
      if index == firstNumber
      then (baseFlag : extExpose, extDbs)
      else (baseFlag : homeDep index, extDbs)

    baseFlag = depFlag "base"

withRenaming :: Unit -> (Unit, (Bool, [(ModuleName, ModuleName)]))
withRenaming unit =
  (unit, renaming unit.name)
  where
    renaming = \case
      "dep1" -> (False, [(mkModuleName "Dep1", mkModuleName "DepRenamed1")])
      _ -> (True, [])

showUnitStateDepChain ::
  HomeUnitEnv ->
  UnitIndexQuery ->
  IO ()
showUnitStateDepChain unit query =
  dbgp $
  hang (ppr (maybe (text "no id") (ppr . homeUnitId) unit.homeUnitEnv_home_unit)) 2 $
  vcat [
    ppr (sizeUniqMap providers),
    ppr (unitProvider "Dep1"),
    ppr (unitProvider "DepRenamed1"),
    ppr (unitProvider "Data.Semigroup"),
    ppr (unitProvider "Dep2"),
    ppr (origin "Dep1") <+> parens "hidden due to being renamed",
    ppr (origin "DepRenamed1") <+> parens "visible in unit1 via rename",
    ppr (origin "Bad") <+> parens "nonexistent module",
    ppr (origin "Data.Semigroup") <+> parens "visible, base",
    ppr (origin "Dep2") <+> parens ""
  ]
  where
    unitProvider n = lookupUniqMap providers (mkModuleName n)

    origin n = query.findOrigin state (mkModuleName n) False

    providers = state.moduleNameProvidersMap

    state = unit.homeUnitEnv_units

testUnitIndexDepChain ::
  NonEmpty (Unit, (Bool, [(ModuleName, ModuleName)])) ->
  HscEnv ->
  Ghc ()
testUnitIndexDepChain synthDeps HscEnv {hsc_logger, hsc_dflags, hsc_unit_env} = do
  unit_env <- liftIO $ foldM @[] (addUnitType1 hsc_logger dflags depFlags dbs 1) hsc_unit_env [1..homeUnitCount]
  for_ @[] ["unit1", "unit2"] \ name -> do
    let uid = stringToUnitId name
        unit = unitEnv_lookup uid unit_env.ue_home_unit_graph
    query <- liftIO $ unitIndexQuery unit_env.ue_index uid
    liftIO $ showUnitState unit query
  where
    depFlags = [uncurry (depFlagRename (unitIdString uid)) rename | (Unit {uid}, rename) <- toList synthDeps]

    dbs = [dbFlag db | (Unit {db}, _) <- toList synthDeps]

    dflags = gopt_set hsc_dflags Opt_HideAllPackages

synthDepFlag :: (Unit, (Bool, [(ModuleName, ModuleName)])) -> PackageFlag
synthDepFlag (Unit {uid}, rename) =
  uncurry (depFlagRename (unitIdString uid)) rename

showUnitState ::
  HomeUnitEnv ->
  UnitIndexQuery ->
  IO ()
showUnitState unit query =
  dbgp $
  hang (ppr (maybe (text "no id") (ppr . homeUnitId) unit.homeUnitEnv_home_unit)) 2 $
  vcat [
    ppr (unitProvider "Dep2"),
    ppr (origin "Dep2") <+> parens "available in unit1, reexport in unit2"
  ]
  where
    unitProvider n = lookupUniqMap providers (mkModuleName n)

    origin n = query.findOrigin state (mkModuleName n) False

    providers = state.moduleNameProvidersMap

    state = unit.homeUnitEnv_units

testUnitIndex ::
  NonEmpty (Unit, (Bool, [(ModuleName, ModuleName)])) ->
  NonEmpty (String, [Text]) ->
  HscEnv ->
  Ghc ()
testUnitIndex synthDeps homeUnits HscEnv {hsc_logger, hsc_dflags, hsc_unit_env} = do
  unit_env <- liftIO $ foldM add hsc_unit_env homeUnits
  for_ @[] ["unit1", "unit2"] \ name -> do
    let uid = stringToUnitId name
        unit = unitEnv_lookup uid unit_env.ue_home_unit_graph
    query <- liftIO $ unitIndexQuery unit_env.ue_index uid
    liftIO $ showUnitState unit query
  where
    add ue (name, deps) =
      addUnit hsc_logger dflags (catMaybes ((depFlagsByName Map.!?) <$> deps)) dbs name ue

    depFlagsByName =
      Map.fromList [(Text.pack name, synthDepFlag dep) | dep@(Unit {name}, (_, _)) <- toList synthDeps]

    dbs = [dbFlag db | (Unit {db}, _) <- toList synthDeps]

    dflags = gopt_set hsc_dflags Opt_HideAllPackages

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
          testUnitIndex (withRenaming <$> units) homeUnits1 =<< getSession
          pure (Just ())
        logFlushDebug env.log

#endif
