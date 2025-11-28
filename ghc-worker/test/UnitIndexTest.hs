{-# LANGUAGE CPP #-}
module UnitIndexTest where

import Control.Exception (catch)
import Control.Monad (foldM)
import Control.Monad.IO.Class (MonadIO (..))
import qualified Data.Text as Text
import Data.Text (Text)
import GHC (DynFlags (homeUnitId_, packageDBFlags, packageFlags), Ghc, GhcMonad (..), HscEnv, mkModuleName)
import GHC.Driver.DynFlags (ModRenaming (..), PackageArg (..), PackageDBFlag (..), PackageFlag (..), PkgDbRef (..))
import GHC.Driver.Env.Types (HscEnv (..))
import GHC.Driver.Monad (modifySession)
import GHC.Types.Unique.Map (lookupUniqMap, sizeUniqMap)
import GHC.Unit (UnitState (..), homeUnitId, initUnits, stringToUnit, stringToUnitId, unitIdString)
import GHC.Unit.Env (HomeUnitEnv (..), UnitEnv (..), ue_home_unit_graph, unitEnv_keys, unitEnv_lookup, unitEnv_new)
import GHC.Utils.Outputable (hang, ppr, text, ($$))
import Internal.Cache.Metadata (insertHomeUnit)
import Internal.Log (dbgp, dbgs, logFlushDebug, newLogger)
import Internal.Session (runSession)
import Internal.State (newStateWith)
import Prelude hiding (log)
import System.Environment (getEnv)
import qualified System.FilePath as FilePath
import Types.Args (Args, emptyArgs)
import Types.Env (Env (..))
import Types.Log (newLog)
import Types.State.Oneshot (OneshotCacheFeatures (..))

#if defined(MWB_2025_07)
import Data.Foldable (toList)
import qualified Data.List.NonEmpty as NonEmpty
import Data.List.NonEmpty (NonEmpty)
import Internal.State.UnitIndex (newUnitIndex)
import System.OsPath (unsafeEncodeUtf)
import TestSetup (Conf (..), ModuleSpec (..), Unit (..), UnitSpec (..), withProject)
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

depFlag :: String -> PackageFlag
depFlag name =
  ExposePackage ("-package " ++ name) (PackageArg name) (ModRenaming True [])

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

showUnitState :: HomeUnitEnv -> IO ()
showUnitState unit =
  dbgp $
  hang (ppr (maybe (text "no id") (ppr . homeUnitId) unit.homeUnitEnv_home_unit))
  2
  (ppr (sizeUniqMap providers) $$ ppr (lookupUniqMap providers (mkModuleName "Data.Fix")))
  where
    providers = unit.homeUnitEnv_units.moduleNameProvidersMap

addUnitType1 ::
  [PackageFlag] ->
  [PackageDBFlag] ->
  Word ->
  UnitEnv ->
  Word ->
  Ghc UnitEnv
addUnitType1 extExpose extDbs firstNumber unit_env (index :: Word) = do
  HscEnv {hsc_logger, hsc_dflags} <- getSession
  let dflags = hsc_dflags {homeUnitId_ = unit, packageFlags, packageDBFlags}
  liftIO do
#if defined(GHC_UNIT_INDEX)
    (dbs, unit_state, home_unit, _) <- initUnits hsc_logger dflags unit_env.ue_index Nothing allUnitIds
#else
    (dbs, unit_state, home_unit, _) <- initUnits hsc_logger dflags Nothing allUnitIds
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
  NonEmpty Unit ->
  HscEnv ->
  Ghc ()
testUnitIndex realDeps synthDeps HscEnv {hsc_unit_env} = do
  realDbs <- traverse (fmap dbFlag . nixDb) [Text.unpack (Text.replace "-" "_" n) | n <- realDeps]
  unit_env <- foldM @[] (addUnitType1 (realDepFlags ++ synthDepFlags) (realDbs ++ synthDbs) homeUnitCount) hsc_unit_env (reverse [1..homeUnitCount])
  let unit1 = unitEnv_lookup (stringToUnitId "unit1") unit_env.ue_home_unit_graph
  liftIO $ showUnitState unit1
  pure ()
  where
    realDepFlags = depFlag . Text.unpack <$> realDeps

    synthDepFlags = [depFlag (unitIdString uid) | Unit {uid} <- toList synthDeps]

    synthDbs = [dbFlag db | Unit {db} <- toList synthDeps]

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
          testUnitIndex extDepNames units =<< getSession
          pure (Just ())
        logFlushDebug env.log
        pure ()
