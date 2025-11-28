{-# LANGUAGE CPP #-}

module Internal.State.UnitIndex where

#if defined(GHC_UNIT_INDEX)

import Control.Concurrent.MVar
import Control.Monad (foldM, when)
import Control.Monad.IO.Class (MonadIO (..))
import Data.Coerce (coerce)
import Data.Foldable
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map, (!?))
import Data.Maybe
import qualified Data.Semigroup as Semigroup
import qualified Data.Set as Set
import Data.Traversable (mapAccumM)
import GHC hiding (SuccessFlag (..))
import GHC.Driver.DynFlags
import GHC.Driver.Env (HscEnv (..))
import GHC.Internal.Data.Monoid (First (..))
import GHC.Types.Unique.DFM
import GHC.Types.Unique.FM
import GHC.Types.Unique.Map
import GHC.Types.Unique.Set (emptyUniqSet)
import GHC.Unit.Database
import GHC.Unit.Env
import GHC.Unit.Module
import GHC.Unit.State
import GHC.Utils.Error (logInfo)
import GHC.Utils.Misc
import qualified GHC.Utils.Outputable as Outputable
import GHC.Utils.Outputable (Outputable, ppr, text)
import Internal.State.UnitStateLegacy
import Prelude hiding ((<>))
import System.OsPath (OsPath)
import Types.State.Make (MakeState (..))

data UnitIndexBackend =
  UnitIndexBackend {
    moduleNameProviders :: !ModuleNameProvidersMap,
    pluginModuleNameProviders :: !ModuleNameProvidersMap,
    databases :: Map OsPath (UnitDatabase UnitId)
  }

newUnitIndexBackend :: UnitIndexBackend
newUnitIndexBackend =
  UnitIndexBackend {
    moduleNameProviders = mempty,
    pluginModuleNameProviders = mempty,
    databases = mempty
  }

queryFindOrigin ::
  UnitIndexBackend ->
  UnitState ->
  ModuleName ->
  Bool ->
  Maybe (UniqMap Module ModuleOrigin)
queryFindOrigin _ UnitState {moduleNameProvidersMap, pluginModuleNameProvidersMap} name plugins =
  lookupUniqMap source name
  where
    source = if plugins then pluginModuleNameProvidersMap else moduleNameProvidersMap

newUnitIndexQuery ::
  MonadIO m =>
  MVar UnitIndexBackend ->
  m UnitIndexQuery
newUnitIndexQuery ref = do
  state <- liftIO $ readMVar ref
  pure UnitIndexQuery {
    findOrigin = queryFindOrigin state,
    index_all = \ us -> us.moduleNameProvidersMap
  }

updateIndex ::
  MonadIO m =>
  MVar UnitIndexBackend ->
  ModuleNameProvidersMap ->
  m ()
updateIndex ref new =
  liftIO $ modifyMVar_ ref \ UnitIndexBackend {..} ->
    pure UnitIndexBackend {
      moduleNameProviders = new Semigroup.<> moduleNameProviders,
      ..
    }

readDatabasesShared ::
  MVar UnitIndexBackend ->
  GHC.Logger ->
  UnitConfig ->
  IO [UnitDatabase UnitId]
readDatabasesShared ref logger cfg =
  modifyMVar ref \ state -> do
    conf_refs <- getUnitDbRefs cfg
    confs     <- catMaybes <$> mapM (resolveUnitDatabase cfg) conf_refs
    let
      loadDb z path =
        case z !? path of
          Just db | enable -> pure (z, db)
          Nothing -> do
            db <- readUnitDatabase logger cfg path
            pure (Map.insert path db z, db)
    (newDatabases, dbs) <- mapAccumM loadDb state.databases confs
    pure (state {databases = newDatabases}, dbs)
  where
    enable = True

newUnitIndex :: IO UnitIndex
newUnitIndex = do
  ref <- liftIO $ newMVar newUnitIndexBackend
  pure UnitIndex {
    query = newUnitIndexQuery ref,
    readDatabases = readDatabasesShared ref,
    update = updateIndex1 ref
  }

restoreUnitIndex :: MakeState -> HscEnv -> HscEnv
restoreUnitIndex state hsc_env =
  hsc_env {hsc_unit_env = ue {ue_index = state.unitIndex}}
  where
    ue = hsc_env.hsc_unit_env

newtype PprUnitInfo =
  PprUnitInfo UnitInfo

instance Outputable PprUnitInfo where
  ppr = pprUnitInfo . coerce

updateIndex1 ::
  MVar UnitIndexBackend ->
  Logger ->
  UnitConfig ->
  [UnitDatabase UnitId] ->
  [PackageFlag] ->
  IO (ModuleNameProvidersMap, ModuleNameProvidersMap, UnitInfoMap, [(Unit, Maybe PackageArg)], [UnitId], UniqMap ModuleName [InstantiatedModule], UniqFM PackageName UnitId, UniqMap UnitId UnitId)
updateIndex1 _ref logger cfg raw_dbs other_flags = do

  -- distrust all units if the flag is set
  let distrust_all db = db { unitDatabaseUnits = distrustAllUnits (unitDatabaseUnits db) }
      dbs | unitConfigDistrustAll cfg = map distrust_all raw_dbs
          | otherwise                 = raw_dbs


  -- Merge databases together, without checking validity
  (pkg_map1, prec_map) <- mergeDatabases logger dbs
  when False do
    logInfo logger (text "pkg_map1:" Outputable.<> ppr (sizeUniqMap pkg_map1))

  -- Now that we've merged everything together, prune out unusable
  -- packages.
  let (pkg_map2, unusable, sccs) = validateDatabase cfg pkg_map1

  reportCycles   logger sccs
  reportUnusable logger unusable

  -- Apply trust flags (these flags apply regardless of whether
  -- or not packages are visible or not)
  pkgs1 <- mayThrowUnitErr
            $ foldM (applyTrustFlag prec_map unusable)
                 (nonDetEltsUniqMap pkg_map2) (reverse (unitConfigFlagsTrusted cfg))
  let prelim_pkg_db = mkUnitInfoMap pkgs1

  --
  -- Calculate the initial set of units from package databases, prior to any package flags.
  --
  -- Conceptually, we select the latest versions of all valid (not unusable) *packages*
  -- (not units). This is empty if we have -hide-all-packages.
  --
  -- Then we create an initial visibility map with default visibilities for all
  -- exposed, definite units which belong to the latest valid packages.
  --
  let preferLater unit unit' =
        case compareByPreference prec_map unit unit' of
            GT -> unit
            _  -> unit'
      addIfMorePreferable m unit = addToUDFM_C preferLater m (fsPackageName unit) unit
      -- This is the set of maximally preferable packages. In fact, it is a set of
      -- most preferable *units* keyed by package name, which act as stand-ins in
      -- for "a package in a database". We use units here because we don't have
      -- "a package in a database" as a type currently.
      mostPreferablePackageReps = if unitConfigHideAll cfg
                    then emptyUDFM
                    else foldl' addIfMorePreferable emptyUDFM pkgs1
      -- When exposing units, we want to consider all of those in the most preferable
      -- packages. We can implement that by looking for units that are equi-preferable
      -- with the most preferable unit for package. Being equi-preferable means that
      -- they must be in the same database, with the same version, and the same package name.
      --
      -- We must take care to consider all these units and not just the most
      -- preferable one, otherwise we can end up with problems like #16228.
      mostPreferable u =
        case lookupUDFM mostPreferablePackageReps (fsPackageName u) of
          Nothing -> False
          Just u' -> compareByPreference prec_map u u' == EQ
      vis_map1 = foldl' (\vm p ->
                            -- Note: we NEVER expose indefinite packages by
                            -- default, because it's almost assuredly not
                            -- what you want (no mix-in linking has occurred).
                            if unitIsExposed p && unitIsDefinite (mkUnit p) && mostPreferable p
                               then addToUniqMap vm (mkUnit p)
                                               UnitVisibility {
                                                 uv_expose_all = True,
                                                 uv_renamings = [],
                                                 uv_package_name = First (Just (fsPackageName p)),
                                                 uv_requirements = emptyUniqMap,
                                                 uv_explicit = Nothing
                                               }
                               else vm)
                         emptyUniqMap pkgs1
  --
  -- Compute a visibility map according to the command-line flags (-package,
  -- -hide-package).  This needs to know about the unusable packages, since if a
  -- user tries to enable an unusable package, we should let them know.
  --
  vis_map2 <- mayThrowUnitErr
                $ foldM (applyPackageFlag prec_map prelim_pkg_db emptyUniqSet unusable
                        (unitConfigHideAll cfg) pkgs1)
                            vis_map1 other_flags

  --
  -- Sort out which packages are wired in. This has to be done last, since
  -- it modifies the unit ids of wired in packages, but when we process
  -- package arguments we need to key against the old versions.
  --
  (pkgs2, wired_map) <- findWiredInUnits logger prec_map pkgs1 vis_map2
  let pkg_db = mkUnitInfoMap pkgs2

  -- Update the visibility map, so we treat wired packages as visible.
  let vis_map = updateVisibilityMap wired_map vis_map2

  let hide_plugin_pkgs = unitConfigHideAllPlugins cfg
  plugin_vis_map <-
    case unitConfigFlagsPlugins cfg of
        -- common case; try to share the old vis_map
        [] | not hide_plugin_pkgs -> return vis_map
           | otherwise -> return emptyUniqMap
        _ -> do let plugin_vis_map1
                        | hide_plugin_pkgs = emptyUniqMap
                        -- Use the vis_map PRIOR to wired in,
                        -- because otherwise applyPackageFlag
                        -- won't work.
                        | otherwise = vis_map2
                plugin_vis_map2
                    <- mayThrowUnitErr
                        $ foldM (applyPackageFlag prec_map prelim_pkg_db emptyUniqSet unusable
                                hide_plugin_pkgs pkgs1)
                             plugin_vis_map1
                             (reverse (unitConfigFlagsPlugins cfg))
                -- Updating based on wired in packages is mostly
                -- good hygiene, because it won't matter: no wired in
                -- package has a compiler plugin.
                -- TODO: If a wired in package had a compiler plugin,
                -- and you tried to pick different wired in packages
                -- with the plugin flags and the normal flags... what
                -- would happen?  I don't know!  But this doesn't seem
                -- likely to actually happen.
                return (updateVisibilityMap wired_map plugin_vis_map2)

  let pkgname_map = listToUFM [ (unitPackageName p, unitInstanceOf p)
                              | p <- pkgs2
                              ]
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

  let mod_map1 = mkModuleNameProvidersMap logger cfg pkg_db emptyUniqSet vis_map
      mod_map2 = mkUnusableModuleNameProvidersMap unusable
      mod_map = mod_map2 `plusUniqMap` mod_map1
      pluginModuleNameProviders = mkModuleNameProvidersMap logger cfg pkg_db emptyUniqSet plugin_vis_map
    in pure (mod_map, pluginModuleNameProviders, pkg_db, explicit_pkgs, dep_preload, req_ctx, pkgname_map, wired_map)

#else

import GHC (HscEnv)
import Types.State.Make (MakeState, UnitIndex (..))

newUnitIndex :: IO UnitIndex
newUnitIndex = pure UnitIndex

restoreUnitIndex :: MakeState -> HscEnv -> HscEnv
restoreUnitIndex _ = id

#endif
