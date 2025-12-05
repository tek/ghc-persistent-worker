{-# LANGUAGE CPP #-}

module Internal.State.UnitIndex.Update where

#if defined(GHC_UNIT_INDEX)

import Control.DeepSeq (NFData (..))
import Control.Monad (foldM, when)
import Data.List.NonEmpty (NonEmpty)
import GHC hiding (SuccessFlag (..))
import GHC.Driver.DynFlags
import GHC.Generics (Generic)
import GHC.Internal.Data.Monoid (First (..))
import GHC.Types.Unique.DFM
import GHC.Types.Unique.FM
import GHC.Types.Unique.Map
import GHC.Types.Unique.Set (UniqSet, elementOfUniqSet, emptyUniqSet, mkUniqSet, unionUniqSets)
import GHC.Unit.Database
import GHC.Unit.Module
import GHC.Unit.State
import GHC.Utils.Error (logInfo)
import GHC.Utils.Logger (LogFlags (..), logFlags)
import GHC.Utils.Outputable (Outputable, ppr, renderWithContext, text, ($$), (<+>))
import GHC.Utils.Panic (pprPanic, throwGhcException)
import Internal.GHC.Orphans ()
import Internal.State.UnitStateLegacy

data Provider =
  Provider {
    hidden :: Bool,
    reexports :: Maybe (NonEmpty UnitInfo)
  }
  deriving stock (Generic)

instance Outputable Provider where
  ppr Provider {..} = if hidden then text "hidden" else text "available"

instance Semigroup Provider where
  l <> r =
    if l.hidden == r.hidden
    then Provider {hidden = l.hidden, reexports = l.reexports <> r.reexports}
    else pprPanic "Provider: package both exposed/hidden" $ text "l:" <+> ppr l.hidden $$ text "r:" <+> ppr r.hidden

instance Monoid Provider where
  mempty = Provider {hidden = False, reexports = Nothing}

instance NFData Provider where

type Providers = UniqMap ModuleName (UniqMap Module Provider)

mkProviderMap :: Unit -> ModuleName -> Provider -> UniqMap Module Provider
mkProviderMap pkg pro = unitUniqMap (mkModule pkg pro)

addProvider :: UnitInfo -> Providers -> Providers
addProvider info@GenericUnitInfo {unitExposedModules, unitHiddenModules} z =
  addListTo z ((export <$> unitExposedModules) ++ hiddens)
  where
    export (name, exposedReexport) =
     let (originUnit, originName, reexports) = checkReexport name exposedReexport
     in (name, mkProviderMap originUnit originName Provider {hidden = False, reexports})

    checkReexport name = \case
      Nothing -> (unit, name, Nothing)
      Just (Module originUnit originName) -> (originUnit, originName, Just (pure info))

    hiddens = [(name, mkProviderMap unit name Provider {hidden = True, reexports = Nothing}) | name <- unitHiddenModules]

    unit = mkUnit info

-- TODO
-- unit-specific transformations that need to be separated from the generic functions:
-- * @mergeDatabases@ uses the order of the initial list of @UnitDatabase@s that corresponds to CLI arguments to compute
--   the precedence map.
--   This is probably fine to have as a byproduct of the generic part.
-- * @validateDatabase@ uses @unitConfigFlagsIgnored@.
--
-- unit-specific transformations that are already separate operations:
-- * @applyTrustFlag@ uses @unitConfigFlagsTrusted@
-- * @compareByPreference@ uses the precedence map to determine the set of preferred units, where a unit with a package
--   name that is higher in the precedence map overrides others by thhat name.
-- * @applyPackageFlag@ uses @unitConfigHideAll@ and @other_flags@ to toggle visibility.
-- * @findWiredInUnits@ uses the available units to select the best candidate for wired-in units.
--   If we used the global set here, we could select different versions of e.g. base because they're available in other
--   units.
updateProviders ::
  Logger ->
  UnitConfig ->
  [PackageFlag] ->
  [UnitDatabase UnitId] ->
  UniqSet UnitId ->
  Providers ->
  IO (Providers, UniqSet UnitId, (UnitInfoMap, UnitPrecedenceMap, UnusableUnits))
updateProviders logger cfg _other_flags dbs oldUnits old = do
  (pkg_map1, unit_prec_map) <- mergeDatabases logger dbs
  let (pkg_map2, unusable, sccs) = validateDatabase cfg pkg_map1
  reportCycles logger sccs
  reportUnusable logger unusable
  let newGlobalUnits = mkUnitInfoMap (nonDetEltsUniqMap (filterWithKeyUniqMap (const . isNewUnit) pkg_map2))
      new = nonDetFoldUniqMap (addProvider . snd) old newGlobalUnits
      newUnits = unionUniqSets (mkUniqSet (nonDetKeysUniqMap newGlobalUnits)) oldUnits
  pure (new, newUnits, (pkg_map2, unit_prec_map, unusable))
  where
    isNewUnit uid = not (elementOfUniqSet uid oldUnits)

invalidRenamedModule ::
  Logger ->
  ModuleName ->
  Unit ->
  GhcException
invalidRenamedModule logger orig pk =
  (CmdLineError (renderWithContext (log_default_user_context (logFlags logger)) message))
  where
    message = text "package flag: could not find module name" <+> ppr orig <+> text "in package" <+> ppr pk

renamingOrigin :: ModuleOrigin
renamingOrigin =
  ModOrigin {
    fromOrigUnit = Nothing,
    fromExposedReexport = [],
    fromHiddenReexport = [],
    fromPackageFlag = True
  }

unitOverrides ::
  Logger ->
  VisibilityMap ->
  UnusableUnits ->
  Providers ->
  ModuleNameProvidersMap
unitOverrides logger vis_map unusable providers =
  renamed <> mkUnusableModuleNameProvidersMap unusable
  where
    renamed = nonDetFoldUniqMap unitRenamings emptyUniqMap vis_map

    unitRenamings (unit, UnitVisibility {uv_renamings}) z =
      addListTo z (moduleRenaming unit <$> uv_renamings)

    moduleRenaming unit (orig, new) =
      case lookupUniqMap providers orig of
        Just r -> (new, renamingOrigin <$ r)
        Nothing -> throwGhcException (invalidRenamedModule logger orig unit)

unitVisibility ::
  Logger ->
  UnitConfig ->
  [PackageFlag] ->
  UnitInfoMap ->
  UnitPrecedenceMap ->
  UnusableUnits ->
  Providers ->
  IO (VisibilityMap, VisibilityMap, WiringMap, UnitInfoMap, UniqFM PackageName UnitId, ModuleNameProvidersMap, ModuleNameProvidersMap)
unitVisibility logger cfg other_flags pkg_map2_all prec_map unusable providers = do

  -- distrust all units if the flag is set
  let distrust_all info = info {unitIsTrusted = False}
      pkg_map2 | unitConfigDistrustAll cfg = distrust_all <$> pkg_map2_all
               | otherwise                 = pkg_map2_all

  let
    dbg :: Outputable a => String -> a -> IO ()
    dbg desc thing =
      when False do
        logInfo logger (text (desc ++ ":") <+> ppr thing)

  dbg "pkg_map2" (nonDetKeysUniqMap pkg_map2)

  -- Apply trust flags (these flags apply regardless of whether
  -- or not packages are visible or not)
  pkgs1 <- mayThrowUnitErr
            $ foldM (applyTrustFlag prec_map unusable)
                 (nonDetEltsUniqMap pkg_map2) (reverse (unitConfigFlagsTrusted cfg))
  let prelim_pkg_db = mkUnitInfoMap pkgs1

  dbg "pkgs1" ((.unitId) <$> pkgs1)

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

  dbg "vis_map1" vis_map1
  dbg "other_flags" other_flags
  dbg "vis_map2" vis_map2

  --
  -- Sort out which packages are wired in. This has to be done last, since
  -- it modifies the unit ids of wired in packages, but when we process
  -- package arguments we need to key against the old versions.
  --
  (pkgs2, wired_map) <- findWiredInUnits logger prec_map pkgs1 vis_map2
  let pkg_db = mkUnitInfoMap pkgs2

  -- Update the visibility map, so we treat wired packages as visible.
  let vis_map = updateVisibilityMap wired_map vis_map2

  dbg "vis_map" vis_map

  let hide_plugin_pkgs = unitConfigHideAllPlugins cfg
  plugin_vis_map <-
    case unitConfigFlagsPlugins cfg of
        [] | not hide_plugin_pkgs -> return vis_map
           | otherwise -> return emptyUniqMap
        _ -> do let plugin_vis_map1
                        | hide_plugin_pkgs = emptyUniqMap
                        | otherwise = vis_map2
                plugin_vis_map2
                    <- mayThrowUnitErr
                        $ foldM (applyPackageFlag prec_map prelim_pkg_db emptyUniqSet unusable
                                hide_plugin_pkgs pkgs1)
                             plugin_vis_map1
                             (reverse (unitConfigFlagsPlugins cfg))
                return (updateVisibilityMap wired_map plugin_vis_map2)

  let pkgname_map = listToUFM [ (unitPackageName p, unitInstanceOf p)
                              | p <- pkgs2
                              ]

  let overrides = unitOverrides logger vis_map unusable providers
      pluginOverrides = unitOverrides logger plugin_vis_map unusable providers

  pure (vis_map, plugin_vis_map, wired_map, pkg_db, pkgname_map, overrides, pluginOverrides)

#endif
