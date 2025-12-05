{-# LANGUAGE CPP #-}

module Internal.State.UnitIndex where

#if defined(GHC_UNIT_INDEX)

import Control.Concurrent.MVar
import Control.DeepSeq (force)
import Control.Monad.IO.Class (MonadIO (..))
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map, (!?))
import Data.Maybe
import Data.Semigroup ((<>))
import qualified Data.Set as Set
import Data.Traversable (mapAccumM)
import GHC hiding (SuccessFlag (..))
import GHC.Driver.DynFlags
import GHC.Driver.Env (HscEnv (..))
import GHC.Types.Unique.FM
import GHC.Types.Unique.Map
import GHC.Types.Unique.Set (UniqSet)
import GHC.Unit.Env
import GHC.Unit.Module
import GHC.Unit.State
import GHC.Utils.Misc
import Internal.State.UnitIndex.Update (Provider (..), Providers, unitVisibility, updateProviders)
import Internal.State.UnitStateLegacy (updateIndexDefault)
import Prelude hiding ((<>))
import System.OsPath (OsPath)
import Types.State.Make (MakeState (..))

enableSharedProviders :: Bool
enableSharedProviders = True

enableSharedDatabases :: Bool
enableSharedDatabases = True

data UnitIndexBackend =
  UnitIndexBackend {
    databases :: !(Map OsPath (UnitDatabase UnitId)),
    units :: !(UniqSet UnitId),
    providers :: !Providers,
    visibilities :: !(UniqMap UnitId VisibilityMap),
    pluginVisibilities :: !(UniqMap UnitId VisibilityMap)
  }

newUnitIndexBackend :: UnitIndexBackend
newUnitIndexBackend =
  UnitIndexBackend {
    databases = mempty,
    units = mempty,
    providers = mempty,
    visibilities = mempty,
    pluginVisibilities = mempty
  }

-- TODO are reexported modules visible when the unit is hidden by a renaming flag?
globalOrigin ::
  UnitState ->
  VisibilityMap ->
  Module ->
  Provider ->
  (Module, ModuleOrigin)
globalOrigin UnitState {wireMap} visibility Module {moduleUnit, moduleName} Provider {hidden, reexports} =
  -- trace (showPprUnsafe (moduleUnit, moduleName, origin, vis, moduleUnit)) $
  (mkModule unit moduleName, origin)
  where
    origin
      | hidden
      = ModHidden
      | Just reex <- reexports
      = mkOrigin (uv_expose_all <$> vis) (NonEmpty.partition isVisible reex)
      | otherwise
      = mkOrigin (Just (maybe False uv_expose_all vis)) ([], [])

    vis = lookupUniqMap visibility unit

    isVisible info = elemUniqMap (mkUnit info) visibility

    mkOrigin fromOrigUnit (fromExposedReexport, fromHiddenReexport) =
      ModOrigin {fromPackageFlag = False, ..}

    unit = maybe moduleUnit (RealUnit . Definite) (lookupUniqMap wireMap (toUnitId moduleUnit))

-- TODO the unit's overrides could already be based on the global overrides (though only if an override exists, of
-- course), in order to skip the global lookup if there is an override.
-- But then we wouldn't see suggestions for packages that come after the current unit, I guess, but it would resemble
-- the original more closely.
queryFindOrigin ::
  UnitId ->
  UnitIndexBackend ->
  UnitState ->
  ModuleName ->
  Bool ->
  Maybe (UniqMap Module ModuleOrigin)
queryFindOrigin home UnitIndexBackend {providers, visibilities, pluginVisibilities} state name plugins =
  lookupUniqMap overrides name
  <>
  (applyVisibility <$> lookupUniqMap providers name)
  where
    applyVisibility =
      listToUniqMap . fmap (uncurry (globalOrigin state visibility)) . nonDetUniqMapToList

    visibility = fromMaybe mempty (lookupUniqMap vis home)

    (overrides, vis) =
      if plugins
      then (state.pluginModuleNameProvidersMap, visibilities)
      else (state.moduleNameProvidersMap, pluginVisibilities)

queryFindOriginDefault ::
  UnitIndexBackend ->
  UnitState ->
  ModuleName ->
  Bool ->
  Maybe (UniqMap Module ModuleOrigin)
queryFindOriginDefault _ UnitState {moduleNameProvidersMap, pluginModuleNameProvidersMap} name plugins =
  lookupUniqMap source name
  where
    source = if plugins then pluginModuleNameProvidersMap else moduleNameProvidersMap

newUnitIndexQuery ::
  MonadIO m =>
  MVar UnitIndexBackend ->
  UnitId ->
  m UnitIndexQuery
newUnitIndexQuery ref unit = do
  state <- liftIO $ readMVar ref
  pure UnitIndexQuery {
    findOrigin = (if enableSharedProviders then queryFindOrigin unit else queryFindOriginDefault) state,
    index_all = \ us -> us.moduleNameProvidersMap
  }

readDatabasesShared ::
  MVar UnitIndexBackend ->
  GHC.Logger ->
  UnitId ->
  UnitConfig ->
  IO [UnitDatabase UnitId]
readDatabasesShared ref logger _ cfg =
  modifyMVar ref \ state -> do
    conf_refs <- getUnitDbRefs cfg
    confs <- catMaybes <$> mapM (resolveUnitDatabase cfg) conf_refs
    let
      loadDb z path =
        if enableSharedDatabases
        then case z !? path of
          Just db -> pure (z, db)
          Nothing -> do
            db <- readUnitDatabase logger cfg path
            pure (Map.insert path db z, db)
        else do
          db <- readUnitDatabase logger cfg path
          pure (z, db)
    (newDatabases, dbs) <- mapAccumM loadDb state.databases confs
    pure (state {databases = newDatabases}, dbs)

updateIndex ::
  MVar UnitIndexBackend ->
  Logger ->
  UnitId ->
  UnitConfig ->
  [UnitDatabase UnitId] ->
  [PackageFlag] ->
  IO (ModuleNameProvidersMap, ModuleNameProvidersMap, UnitInfoMap, [(Unit, Maybe PackageArg)], [UnitId], UniqMap ModuleName [InstantiatedModule], UniqFM PackageName UnitId, UniqMap UnitId UnitId)
updateIndex ref logger unit cfg raw_dbs other_flags = do
  (newProviders, (pkg_map2, prec_map, unusable)) <- liftIO $ modifyMVar ref \ UnitIndexBackend {..} -> do
    (newProviders, newUnits, unitData) <- updateProviders logger cfg other_flags raw_dbs units providers
    pure $! (UnitIndexBackend {
      providers = force newProviders,
      units = newUnits,
      ..
    }, (newProviders, unitData))

  (vis_map, plugin_vis_map, wired_map, pkg_db, pkgname_map, overrides, pluginOverrides) <- unitVisibility logger cfg other_flags pkg_map2 prec_map unusable newProviders

  modifyMVar_ ref \ UnitIndexBackend {..} ->
    pure $! UnitIndexBackend {
      visibilities = force (addToUniqMap visibilities unit vis_map),
      pluginVisibilities = force (addToUniqMap pluginVisibilities unit plugin_vis_map),
      ..
    }

  -- The explicitUnits accurately reflects the set of units we have turned
  -- on; as such, it also is the only way one can come up with requirements.
  -- The requirement context is directly based off of this: we simply
  -- look for nested unit IDs that are directly fed holes: the requirements
  -- of those units are precisely the ones we need to track
  let explicit_pkgs = [(k, uv_explicit v) | (k, v) <- nonDetUniqMapToList vis_map]
      req_ctx = mapUniqMap (Set.toList)
              $ plusUniqMapListWith Set.union (map uv_requirements (nonDetEltsUniqMap vis_map))

  --
  -- Here we build up a set of the packages mentioned in -package
  -- flags on the command line; these are called the "preload"
  -- packages.  we link these packages in eagerly.  The preload set
  -- should contain at least rts & base, which is why we pretend that
  -- the command line contains -package rts & -package base.
  --
  -- NB: preload IS important even for type-checking, because we
  -- need the correct include path to be set.
  --
  let preload1 = nonDetKeysUniqMap (filterUniqMap (isJust . uv_explicit) vis_map)

      -- add default preload units if they can be found in the db
      basicLinkedUnits = fmap (RealUnit . Definite)
                         $ filter (flip elemUniqMap pkg_db)
                         $ unitConfigAutoLink cfg
      preload3 = ordNub $ (basicLinkedUnits ++ preload1)

  -- Close the preload packages with their dependencies
  dep_preload <- mayThrowUnitErr
                    $ closeUnitDeps pkg_db
                    $ zip (map toUnitId preload3) (repeat Nothing)

  pure (overrides, pluginOverrides, pkg_db, explicit_pkgs, dep_preload, req_ctx, pkgname_map, wired_map)

newUnitIndex :: IO UnitIndex
newUnitIndex = do
  ref <- liftIO $ newMVar newUnitIndexBackend
  pure UnitIndex {
    query = newUnitIndexQuery ref,
    readDatabases = readDatabasesShared ref,
    update = if enableSharedProviders then updateIndex ref else updateIndexDefault
  }

restoreUnitIndex :: MakeState -> HscEnv -> HscEnv
restoreUnitIndex state hsc_env =
  hsc_env {hsc_unit_env = hsc_env.hsc_unit_env {ue_index = state.unitIndex}}

#else

import GHC (HscEnv)
import Types.State.Make (MakeState, UnitIndex (..))

newUnitIndex :: IO UnitIndex
newUnitIndex = pure UnitIndex

restoreUnitIndex :: MakeState -> HscEnv -> HscEnv
restoreUnitIndex _ = id

#endif
