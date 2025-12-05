{-# LANGUAGE CPP #-}
{-# options_ghc -Wno-name-shadowing #-}

module Internal.State.UnitStateLegacy where

#if defined(GHC_UNIT_INDEX)

import Control.Monad (foldM)
import Data.Foldable
import Data.Graph (stronglyConnComp)
import Data.List (intersperse, partition, sortBy, sortOn)
import Data.Maybe
import qualified Data.Set as Set
import Data.Set (Set)
import GHC hiding (SuccessFlag (..))
import GHC.Data.FastString
import GHC.Data.Graph.Directed (SCC (..))
import GHC.Data.Maybe
import qualified GHC.Data.OsPath as OsPath
import qualified GHC.Data.ShortText as ST
import GHC.Driver.DynFlags
import GHC.Internal.Data.Monoid (First (..))
import GHC.LanguageExtensions
import GHC.Types.Unique
import GHC.Types.Unique.FM
import GHC.Types.Unique.Map
import GHC.Types.Unique.Set (elementOfUniqSet, emptyUniqSet)
import GHC.Unit.Database
import GHC.Unit.Module
import GHC.Unit.Ppr
import GHC.Unit.State
import GHC.Utils.Error (debugTraceMsg)
import GHC.Utils.Logger
import GHC.Utils.Misc
import GHC.Utils.Outputable
import GHC.Utils.Panic
import Prelude hiding ((<>))
import System.OsPath (OsPath)
import GHC.Types.Unique.DFM

mkModuleNameProvidersMap
  :: GHC.Logger
  -> UnitConfig
  -> UnitInfoMap
  -> PreloadUnitClosure
  -> VisibilityMap
  -> ModuleNameProvidersMap
mkModuleNameProvidersMap logger cfg pkg_map closure vis_map =
    -- What should we fold on?  Both situations are awkward:
    --
    --    * Folding on the visibility map means that we won't create
    --      entries for packages that aren't mentioned in vis_map
    --      (e.g., hidden packages, causing #14717)
    --
    --    * Folding on pkg_map is awkward because if we have an
    --      Backpack instantiation, we need to possibly add a
    --      package from pkg_map multiple times to the actual
    --      ModuleNameProvidersMap.  Also, we don't really want
    --      definite package instantiations to show up in the
    --      list of possibilities.
    --
    -- So what will we do instead?  We'll extend vis_map with
    -- entries for every definite (for non-Backpack) and
    -- indefinite (for Backpack) package, so that we get the
    -- hidden entries we need.
    nonDetFoldUniqMap extend_modmap emptyMap vis_map_extended
 where
  vis_map_extended = {- preferred -} default_vis `plusUniqMap` vis_map

  default_vis = listToUniqMap
                  [ (mkUnit pkg, mempty)
                  | (_, pkg) <- nonDetUniqMapToList pkg_map
                  -- Exclude specific instantiations of an indefinite
                  -- package
                  , unitIsIndefinite pkg || null (unitInstantiations pkg)
                  ]

  emptyMap = emptyUniqMap
  setOrigins m os = fmap (const os) m
  extend_modmap (uid, UnitVisibility { uv_expose_all = b, uv_renamings = rns }) modmap
    = addListTo modmap theBindings
   where
    pkg = unit_lookup uid

    theBindings :: [(ModuleName, UniqMap Module ModuleOrigin)]
    theBindings = newBindings b rns

    newBindings :: Bool
                -> [(ModuleName, ModuleName)]
                -> [(ModuleName, UniqMap Module ModuleOrigin)]
    newBindings e rns  = es e ++ hiddens ++ map rnBinding rns

    rnBinding :: (ModuleName, ModuleName)
              -> (ModuleName, UniqMap Module ModuleOrigin)
    rnBinding (orig, new) = (new, setOrigins origEntry fromFlag)
     where origEntry = case lookupUFM esmap orig of
            Just r -> r
            Nothing -> throwGhcException (CmdLineError (renderWithContext
                        (log_default_user_context (logFlags logger))
                        (text "package flag: could not find module name" <+>
                            ppr orig <+> text "in package" <+> ppr pk)))

    es :: Bool -> [(ModuleName, UniqMap Module ModuleOrigin)]
    es e = do
     (m, exposedReexport) <- exposed_mods
     let (pk', m', origin') =
          case exposedReexport of
           Nothing -> (pk, m, fromExposedModules e)
           Just (Module pk' m') ->
              (pk', m', fromReexportedModules e pkg)
     return (m, mkModMap pk' m' origin')

    esmap :: UniqFM ModuleName (UniqMap Module ModuleOrigin)
    esmap = listToUFM (es False) -- parameter here doesn't matter, orig will
                                 -- be overwritten

    hiddens = [(m, mkModMap pk m ModHidden) | m <- hidden_mods]

    pk = mkUnit pkg
    unit_lookup uid = lookupUnit' (unitConfigAllowVirtual cfg) pkg_map closure uid
                        `orElse` pprPanic "unit_lookup" (ppr uid)

    exposed_mods = unitExposedModules pkg
    hidden_mods  = unitHiddenModules pkg

-- | Make a 'ModuleNameProvidersMap' covering a set of unusable packages.
mkUnusableModuleNameProvidersMap :: UnusableUnits -> ModuleNameProvidersMap
mkUnusableModuleNameProvidersMap unusables =
    nonDetFoldUniqMap extend_modmap emptyUniqMap unusables
 where
    extend_modmap (_uid, (unit_info, reason)) modmap = addListTo modmap bindings
      where bindings :: [(ModuleName, UniqMap Module ModuleOrigin)]
            bindings = exposed ++ hidden

            origin_reexport =  ModUnusable (UnusableUnit unit reason True)
            origin_normal   =  ModUnusable (UnusableUnit unit reason False)
            unit = mkUnit unit_info

            exposed = map get_exposed exposed_mods
            hidden = [(m, mkModMap unit m origin_normal) | m <- hidden_mods]

            -- with re-exports, c:Foo can be reexported from two (or more)
            -- unusable packages:
            --  Foo -> a:Foo (unusable reason A) -> c:Foo
            --      -> b:Foo (unusable reason B) -> c:Foo
            --
            -- We must be careful to not record the following (#21097):
            --  Foo -> c:Foo (unusable reason A)
            --      -> c:Foo (unusable reason B)
            -- But:
            --  Foo -> a:Foo (unusable reason A)
            --      -> b:Foo (unusable reason B)
            --
            get_exposed (mod, Just _) = (mod, mkModMap unit mod origin_reexport)
            get_exposed (mod, _) = (mod, mkModMap unit mod origin_normal)
              -- in the reexport case, we create a virtual module that doesn't
              -- exist but we don't care as it's only used as a key in the map.

            exposed_mods = unitExposedModules unit_info
            hidden_mods  = unitHiddenModules  unit_info

addListTo :: (Monoid a, Uniquable k1)
          => UniqMap k1 (UniqMap k2 a)
          -> [(k1, UniqMap k2 a)]
          -> UniqMap k1 (UniqMap k2 a)
addListTo = foldl' merge
  where merge m (k, v) = addToUniqMap_C (plusUniqMap_C mappend) m k v

fromFlag :: ModuleOrigin
fromFlag = ModOrigin Nothing [] [] True

mkModMap :: Unit -> ModuleName -> ModuleOrigin -> UniqMap Module ModuleOrigin
mkModMap pkg mod = unitUniqMap (mkModule pkg mod)

fromExposedModules :: Bool -> ModuleOrigin
fromExposedModules e = ModOrigin (Just e) [] [] False

fromReexportedModules :: Bool -> UnitInfo -> ModuleOrigin
fromReexportedModules True pkg = ModOrigin Nothing [pkg] [] False
fromReexportedModules False pkg = ModOrigin Nothing [] [pkg] False

-- | Is the name from the import actually visible? (i.e. does it cause
-- ambiguity, or is it only relevant when we're making suggestions?)
originVisible :: ModuleOrigin -> Bool
originVisible ModHidden = False
originVisible (ModUnusable _) = False
originVisible (ModOrigin b res _ f) = b == Just True || not (null res) || f

-- | Are there actually no providers for this module?  This will never occur
-- except when we're filtering based on package imports.
originEmpty :: ModuleOrigin -> Bool
originEmpty (ModOrigin Nothing [] [] False) = True
originEmpty _ = False

distrustAllUnits :: [UnitInfo] -> [UnitInfo]
distrustAllUnits pkgs = map distrust pkgs
  where
    distrust pkg = pkg{ unitIsTrusted = False }

-- TODO: Can we help it with this one? it comes from the ghc-boot package
mungeUnitInfo :: OsPath -> OsPath
                   -> UnitInfo -> UnitInfo
mungeUnitInfo top_dir pkgroot =
    mungeDynLibFields
  . mungeUnitInfoPaths (ST.pack (OsPath.unsafeDecodeUtf top_dir)) (ST.pack (OsPath.unsafeDecodeUtf pkgroot))

mungeDynLibFields :: UnitInfo -> UnitInfo
mungeDynLibFields pkg =
    pkg {
      unitLibraryDynDirs = case unitLibraryDynDirs pkg of
         [] -> unitLibraryDirs pkg
         ds -> ds
    }

-- -----------------------------------------------------------------------------
-- Modify our copy of the unit database based on trust flags,
-- -trust and -distrust.

applyTrustFlag
   :: UnitPrecedenceMap
   -> UnusableUnits
   -> [UnitInfo]
   -> TrustFlag
   -> MaybeErr UnitErr [UnitInfo]
applyTrustFlag prec_map unusable pkgs flag =
  case flag of
    -- we trust all matching packages. Maybe should only trust first one?
    -- and leave others the same or set them untrusted
    TrustPackage str ->
       case selectPackages prec_map (PackageArg str) pkgs unusable of
         Left ps       -> Failed (TrustFlagErr flag ps)
         Right (ps,qs) -> Succeeded (map trust ps ++ qs)
          where trust p = p {unitIsTrusted=True}

    DistrustPackage str ->
       case selectPackages prec_map (PackageArg str) pkgs unusable of
         Left ps       -> Failed (TrustFlagErr flag ps)
         Right (ps,qs) -> Succeeded (distrustAllUnits ps ++ qs)

applyPackageFlag
   :: UnitPrecedenceMap
   -> UnitInfoMap
   -> PreloadUnitClosure
   -> UnusableUnits
   -> Bool -- if False, if you expose a package, it implicitly hides
           -- any previously exposed packages with the same name
   -> [UnitInfo]
   -> VisibilityMap           -- Initially exposed
   -> PackageFlag             -- flag to apply
   -> MaybeErr UnitErr VisibilityMap -- Now exposed

applyPackageFlag prec_map pkg_map closure unusable no_hide_others pkgs vm flag =
  case flag of
    ExposePackage _ arg (ModRenaming b rns) ->
       case findPackages prec_map pkg_map closure arg pkgs unusable of
         Left ps     -> Failed (PackageFlagErr flag ps)
         Right ps@(p0:_) -> Succeeded vm'
          where
           p | PackageArg _ <- arg = fromMaybe p0 mainPackage
             | otherwise = p0

           mainPackage = find (\ u -> isNothing (unitComponentName u)) matchFirst

           matchFirst = filter (\ u -> unitPackageName u == firstName && unitPackageVersion u == firstVersion) ps

           firstName = unitPackageName p0
           firstVersion = unitPackageVersion p0

           n = fsPackageName p

           -- If a user says @-unit-id p[A=<A>]@, this imposes
           -- a requirement on us: whatever our signature A is,
           -- it must fulfill all of p[A=<A>]:A's requirements.
           -- This method is responsible for computing what our
           -- inherited requirements are.
           reqs | UnitIdArg orig_uid <- arg = collectHoles orig_uid
                | otherwise                 = emptyUniqMap

           collectHoles uid = case uid of
             HoleUnit       -> emptyUniqMap
             RealUnit {}    -> emptyUniqMap -- definite units don't have holes
             VirtUnit indef ->
                  let local = [ unitUniqMap
                                  (moduleName mod)
                                  (Set.singleton $ Module indef mod_name)
                              | (mod_name, mod) <- instUnitInsts indef
                              , isHoleModule mod ]
                      recurse = [ collectHoles (moduleUnit mod)
                                | (_, mod) <- instUnitInsts indef ]
                  in plusUniqMapListWith Set.union $ local ++ recurse

           uv = UnitVisibility
                { uv_expose_all = b
                , uv_renamings = rns
                , uv_package_name = First (Just n)
                , uv_requirements = reqs
                , uv_explicit = Just arg
                }
           vm' = addToUniqMap_C mappend vm_cleared (mkUnit p) uv
           -- In the old days, if you said `ghc -package p-0.1 -package p-0.2`
           -- (or if p-0.1 was registered in the pkgdb as exposed: True),
           -- the second package flag would override the first one and you
           -- would only see p-0.2 in exposed modules.  This is good for
           -- usability.
           --
           -- However, with thinning and renaming (or Backpack), there might be
           -- situations where you legitimately want to see two versions of a
           -- package at the same time, and this behavior would make it
           -- impossible to do so.  So we decided that if you pass
           -- -hide-all-packages, this should turn OFF the overriding behavior
           -- where an exposed package hides all other packages with the same
           -- name.  This should not affect Cabal at all, which only ever
           -- exposes one package at a time.
           --
           -- NB: Why a variable no_hide_others?  We have to apply this logic to
           -- -plugin-package too, and it's more consistent if the switch in
           -- behavior is based off of
           -- -hide-all-packages/-hide-all-plugin-packages depending on what
           -- flag is in question.
           vm_cleared | no_hide_others = vm
                      -- NB: renamings never clear
                      | (_:_) <- rns = vm
                      | otherwise = filterWithKeyUniqMap
                            (\k uv -> k == mkUnit p
                                   || First (Just n) /= uv_package_name uv) vm
         _ -> panic "applyPackageFlag"

    HidePackage str ->
       case findPackages prec_map pkg_map closure (PackageArg str) pkgs unusable of
         Left ps  -> Failed (PackageFlagErr flag ps)
         Right ps -> Succeeded $ foldl' delFromUniqMap vm (map mkUnit ps)

-- | Like 'selectPackages', but doesn't return a list of unmatched
-- packages.  Furthermore, any packages it returns are *renamed*
-- if the 'UnitArg' has a renaming associated with it.
findPackages :: UnitPrecedenceMap
             -> UnitInfoMap
             -> PreloadUnitClosure
             -> PackageArg -> [UnitInfo]
             -> UnusableUnits
             -> Either [(UnitInfo, UnusableUnitReason)]
                [UnitInfo]
findPackages prec_map pkg_map closure arg pkgs unusable
  = let ps = mapMaybe (finder arg) pkgs
    in if null ps
        then Left (mapMaybe (\(x,y) -> finder arg x >>= \x' -> return (x',y))
                            (nonDetEltsUniqMap unusable))
        else Right (sortByPreference prec_map ps)
  where
    finder (PackageArg str) p
      = if matchingStr str p
          then Just p
          else Nothing
    finder (UnitIdArg uid) p
      = case uid of
          RealUnit (Definite iuid)
            | iuid == unitId p
            -> Just p
          VirtUnit inst
            | instUnitInstanceOf inst == unitId p
            -> Just (renameUnitInfo pkg_map closure (instUnitInsts inst) p)
          _ -> Nothing

selectPackages :: UnitPrecedenceMap -> PackageArg -> [UnitInfo]
               -> UnusableUnits
               -> Either [(UnitInfo, UnusableUnitReason)]
                  ([UnitInfo], [UnitInfo])
selectPackages prec_map arg pkgs unusable
  = let matches = matching arg
        (ps,rest) = partition matches pkgs
    in if null ps
        then Left (filter (matches . fst) (nonDetEltsUniqMap unusable))
        else Right (sortByPreference prec_map ps, rest)

-- | Rename a 'UnitInfo' according to some module instantiation.
renameUnitInfo :: UnitInfoMap -> PreloadUnitClosure -> [(ModuleName, Module)] -> UnitInfo -> UnitInfo
renameUnitInfo pkg_map closure insts conf =
    let hsubst = listToUFM insts
        smod  = renameHoleModule' pkg_map closure hsubst
        new_insts = map (\(k,v) -> (k,smod v)) (unitInstantiations conf)
    in conf {
        unitInstantiations = new_insts,
        unitExposedModules = map (\(mod_name, mb_mod) -> (mod_name, fmap smod mb_mod))
                             (unitExposedModules conf)
    }


-- A package named on the command line can either include the
-- version, or just the name if it is unambiguous.
matchingStr :: String -> UnitInfo -> Bool
matchingStr str p
        =  str == unitPackageIdString p
        || str == unitPackageNameString p
        || matchSublibrary
  where
    matchSublibrary
      | Just (PackageName c) <- unitComponentName p
      = str == (unitPackageNameString p ++ ":" ++ unpackFS c)
      | otherwise
      = False

matchingId :: UnitId -> UnitInfo -> Bool
matchingId uid p = uid == unitId p

matching :: PackageArg -> UnitInfo -> Bool
matching (PackageArg str) = matchingStr str
matching (UnitIdArg (RealUnit (Definite uid))) = matchingId uid
matching (UnitIdArg _)  = \_ -> False -- TODO: warn in this case

-- | This sorts a list of packages, putting "preferred" packages first.
-- See 'compareByPreference' for the semantics of "preference".
sortByPreference :: UnitPrecedenceMap -> [UnitInfo] -> [UnitInfo]
sortByPreference prec_map = sortBy (flip (compareByPreference prec_map))

-- | Returns 'GT' if @pkg@ should be preferred over @pkg'@ when picking
-- which should be "active".  Here is the order of preference:
--
--      1. First, prefer the latest version
--      2. If the versions are the same, prefer the package that
--      came in the latest package database.
--
-- Pursuant to #12518, we could change this policy to, for example, remove
-- the version preference, meaning that we would always prefer the units
-- in later unit database.
compareByPreference
    :: UnitPrecedenceMap
    -> UnitInfo
    -> UnitInfo
    -> Ordering
compareByPreference prec_map pkg pkg'
  = case comparing unitPackageVersion pkg pkg' of
        GT -> GT
        EQ | Just prec  <- lookupUniqMap prec_map (unitId pkg)
           , Just prec' <- lookupUniqMap prec_map (unitId pkg')
           -- Prefer the unit from the later DB flag (i.e., higher
           -- precedence)
           -> compare prec prec'
           | otherwise
           -> EQ
        LT -> LT

comparing :: Ord a => (t -> a) -> t -> t -> Ordering
comparing f a b = f a `compare` f b

pprFlag :: PackageFlag -> SDoc
pprFlag flag = case flag of
    HidePackage p   -> text "-hide-package " <> text p
    ExposePackage doc _ _ -> text doc

pprTrustFlag :: TrustFlag -> SDoc
pprTrustFlag flag = case flag of
    TrustPackage p    -> text "-trust " <> text p
    DistrustPackage p -> text "-distrust " <> text p

-- -----------------------------------------------------------------------------
-- Wired-in units
--
-- See Note [Wired-in units] in GHC.Unit.Types

type WiringMap = UniqMap UnitId UnitId

findWiredInUnits
   :: Logger
   -> UnitPrecedenceMap
   -> [UnitInfo]           -- database
   -> VisibilityMap             -- info on what units are visible
                                -- for wired in selection
   -> IO ([UnitInfo],  -- unit database updated for wired in
          WiringMap)   -- map from unit id to wired identity

findWiredInUnits logger prec_map pkgs vis_map = do
  -- Now we must find our wired-in units, and rename them to
  -- their canonical names (eg. base-1.0 ==> base), as described
  -- in Note [Wired-in units] in GHC.Unit.Types
  let
        matches :: UnitInfo -> UnitId -> Bool
        pc `matches` pid = unitPackageName pc == PackageName (unitIdFS pid)

        -- find which package corresponds to each wired-in package
        -- delete any other packages with the same name
        -- update the package and any dependencies to point to the new
        -- one.
        --
        -- When choosing which package to map to a wired-in package
        -- name, we try to pick the latest version of exposed packages.
        -- However, if there are no exposed wired in packages available
        -- (e.g. -hide-all-packages was used), we can't bail: we *have*
        -- to assign a package for the wired-in package: so we try again
        -- with hidden packages included to (and pick the latest
        -- version).
        --
        -- You can also override the default choice by using -ignore-package:
        -- this works even when there is no exposed wired in package
        -- available.
        --
        findWiredInUnit :: [UnitInfo] -> UnitId -> IO (Maybe (UnitId, UnitInfo))
        findWiredInUnit pkgs wired_pkg = firstJustsM @_ @[] [try all_exposed_ps, try all_ps, notfound]
          where
                all_ps = [ p | p <- pkgs, p `matches` wired_pkg ]
                all_exposed_ps = [ p | p <- all_ps, (mkUnit p) `elemUniqMap` vis_map ]

                try ps = case sortByPreference prec_map ps of
                    p:_ -> Just <$> pick p
                    _ -> pure Nothing

                notfound = do
                          debugTraceMsg logger 2 $
                            text "wired-in package "
                                 <> ftext (unitIdFS wired_pkg)
                                 <> text " not found."
                          return Nothing
                pick :: UnitInfo -> IO (UnitId, UnitInfo)
                pick pkg = do
                        debugTraceMsg logger 2 $
                            text "wired-in package "
                                 <> ftext (unitIdFS wired_pkg)
                                 <> text " mapped to "
                                 <> ppr (unitId pkg)
                        return (wired_pkg, pkg)


  mb_wired_in_pkgs <- mapM (findWiredInUnit pkgs) wiredInUnitIds
  let
        wired_in_pkgs = catMaybes mb_wired_in_pkgs

        wiredInMap :: UniqMap UnitId UnitId
        wiredInMap = listToUniqMap
          [ (unitId realUnitInfo, wiredInUnitId)
          | (wiredInUnitId, realUnitInfo) <- wired_in_pkgs
          , not (unitIsIndefinite realUnitInfo)
          ]

        updateWiredInDependencies pkgs = map (upd_deps . upd_pkg) pkgs
          where upd_pkg pkg
                  | Just wiredInUnitId <- lookupUniqMap wiredInMap (unitId pkg)
                  = pkg { unitId         = wiredInUnitId
                        , unitInstanceOf = wiredInUnitId
                           -- every non instantiated unit is an instance of
                           -- itself (required by Backpack...)
                           --
                           -- See Note [About units] in GHC.Unit
                        }
                  | otherwise
                  = pkg
                upd_deps pkg = pkg {
                      unitDepends = map (upd_wired_in wiredInMap) (unitDepends pkg),
                      unitExposedModules
                        = map (\(k,v) -> (k, fmap (upd_wired_in_mod wiredInMap) v))
                              (unitExposedModules pkg)
                    }


  return (updateWiredInDependencies pkgs, wiredInMap)

-- Helper functions for rewiring Module and Unit.  These
-- rewrite Units of modules in wired-in packages to the form known to the
-- compiler, as described in Note [Wired-in units] in GHC.Unit.Types.
--
-- For instance, base-4.9.0.0 will be rewritten to just base, to match
-- what appears in GHC.Builtin.Names.

upd_wired_in_mod :: WiringMap -> Module -> Module
upd_wired_in_mod wiredInMap (Module uid m) = Module (upd_wired_in_uid wiredInMap uid) m

upd_wired_in_uid :: WiringMap -> Unit -> Unit
upd_wired_in_uid wiredInMap u = case u of
   HoleUnit -> HoleUnit
   RealUnit (Definite uid) -> RealUnit (Definite (upd_wired_in wiredInMap uid))
   VirtUnit indef_uid ->
      VirtUnit $ mkInstantiatedUnit
        (instUnitInstanceOf indef_uid)
        (map (\(x,y) -> (x,upd_wired_in_mod wiredInMap y)) (instUnitInsts indef_uid))

upd_wired_in :: WiringMap -> UnitId -> UnitId
upd_wired_in wiredInMap key
    | Just key' <- lookupUniqMap wiredInMap key = key'
    | otherwise = key

updateVisibilityMap :: WiringMap -> VisibilityMap -> VisibilityMap
updateVisibilityMap wiredInMap vis_map = foldl' f vis_map (nonDetUniqMapToList wiredInMap)
  where f vm (from, to) = case lookupUniqMap vis_map (RealUnit (Definite from)) of
                    Nothing -> vm
                    Just r -> addToUniqMap (delFromUniqMap vm (RealUnit (Definite from)))
                              (RealUnit (Definite to)) r

type UnusableUnits = UniqMap UnitId (UnitInfo, UnusableUnitReason)

reportCycles :: Logger -> [SCC UnitInfo] -> IO ()
reportCycles logger sccs = mapM_ report sccs
  where
    report (AcyclicSCC _) = return ()
    report (CyclicSCC vs) =
        debugTraceMsg logger 2 $
          text "these packages are involved in a cycle:" $$
            nest 2 (hsep (map (ppr . unitId) vs))

reportUnusable :: Logger -> UnusableUnits -> IO ()
reportUnusable logger pkgs = mapM_ report (nonDetUniqMapToList pkgs)
  where
    report (ipid, (_, reason)) =
       debugTraceMsg logger 2 $
         pprReason
           (text "package" <+> ppr ipid <+> text "is") reason

ignoreUnits :: [IgnorePackageFlag] -> [UnitInfo] -> UnusableUnits
ignoreUnits flags pkgs = listToUniqMap (concatMap doit flags)
  where
  doit (IgnorePackage str) =
     case partition (matchingStr str) pkgs of
         (ps, _) -> [ (unitId p, (p, IgnoredWithFlag))
                    | p <- ps ]
        -- missing unit is not an error for -ignore-package,
        -- because a common usage is to -ignore-package P as
        -- a preventative measure just in case P exists.

-- ----------------------------------------------------------------------------
--
-- Merging databases
--

-- | For each unit, a mapping from uid -> i indicates that this
-- unit was brought into GHC by the ith @-package-db@ flag on
-- the command line.  We use this mapping to make sure we prefer
-- units that were defined later on the command line, if there
-- is an ambiguity.
type UnitPrecedenceMap = UniqMap UnitId Int

-- | Given a list of databases, merge them together, where
-- units with the same unit id in later databases override
-- earlier ones.  This does NOT check if the resulting database
-- makes sense (that's done by 'validateDatabase').
mergeDatabases :: Logger -> [UnitDatabase UnitId]
               -> IO (UnitInfoMap, UnitPrecedenceMap)
mergeDatabases logger = foldM merge (emptyUniqMap, emptyUniqMap) . zip [1..]
  where
    merge (pkg_map, prec_map) (i, UnitDatabase db_path db) = do
      debugTraceMsg logger 2 $
          text "loading package database" <+> OsPath.pprOsPath db_path
      forM_ (Set.toList override_set) $ \pkg ->
          debugTraceMsg logger 2 $
              text "package" <+> ppr pkg <+>
              text "overrides a previously defined package"
      return (pkg_map', prec_map')
     where
      db_map = mk_pkg_map db
      mk_pkg_map = listToUniqMap . map (\p -> (unitId p, p))

      -- The set of UnitIds which appear in both db and pkgs.  These are the
      -- ones that get overridden.  Compute this just to give some
      -- helpful debug messages at -v2
      override_set :: Set UnitId
      override_set = Set.intersection (nonDetUniqMapToKeySet db_map)
                                      (nonDetUniqMapToKeySet pkg_map)

      -- Now merge the sets together (NB: in case of duplicate,
      -- first argument preferred)
      pkg_map' :: UnitInfoMap
      pkg_map' = pkg_map `plusUniqMap` db_map

      prec_map' :: UnitPrecedenceMap
      prec_map' = prec_map `plusUniqMap` (mapUniqMap (const i) db_map)

-- | A reverse dependency index, mapping an 'UnitId' to
-- the 'UnitId's which have a dependency on it.
type RevIndex = UniqMap UnitId [UnitId]

-- | Compute the reverse dependency index of a unit database.
reverseDeps :: UnitInfoMap -> RevIndex
reverseDeps db = nonDetFoldUniqMap go emptyUniqMap db
  where
    go :: (UnitId, UnitInfo) -> RevIndex -> RevIndex
    go (_uid, pkg) r = foldl' (go' (unitId pkg)) r (unitDepends pkg)
    go' from r to = addToUniqMap_C (++) r to [from]

-- | Given a list of 'UnitId's to remove, a database,
-- and a reverse dependency index (as computed by 'reverseDeps'),
-- remove those units, plus any units which depend on them.
-- Returns the pruned database, as well as a list of 'UnitInfo's
-- that was removed.
removeUnits :: [UnitId] -> RevIndex
               -> UnitInfoMap
               -> (UnitInfoMap, [UnitInfo])
removeUnits uids index m = go uids (m,[])
  where
    go [] (m,pkgs) = (m,pkgs)
    go (uid:uids) (m,pkgs)
        | Just pkg <- lookupUniqMap m uid
        = case lookupUniqMap index uid of
            Nothing    -> go uids (delFromUniqMap m uid, pkg:pkgs)
            Just rdeps -> go (rdeps ++ uids) (delFromUniqMap m uid, pkg:pkgs)
        | otherwise
        = go uids (m,pkgs)

-- | Given a 'UnitInfo' from some 'UnitInfoMap', return all entries in 'depends'
-- which correspond to units that do not exist in the index.
depsNotAvailable :: UnitInfoMap
                 -> UnitInfo
                 -> [UnitId]
depsNotAvailable pkg_map pkg = filter (not . (`elemUniqMap` pkg_map)) (unitDepends pkg)

-- | Given a 'UnitInfo' from some 'UnitInfoMap' return all entries in
-- 'unitAbiDepends' which correspond to units that do not exist, OR have
-- mismatching ABIs.
depsAbiMismatch :: UnitInfoMap
                -> UnitInfo
                -> [UnitId]
depsAbiMismatch pkg_map pkg = map fst . filter (not . abiMatch) $ unitAbiDepends pkg
  where
    abiMatch (dep_uid, abi)
        | Just dep_pkg <- lookupUniqMap pkg_map dep_uid
        = unitAbiHash dep_pkg == abi
        | otherwise
        = False

-- | Validates a database, removing unusable units from it
-- (this includes removing units that the user has explicitly
-- ignored.)  Our general strategy:
--
-- 1. Remove all broken units (dangling dependencies)
-- 2. Remove all units that are cyclic
-- 3. Apply ignore flags
-- 4. Remove all units which have deps with mismatching ABIs
--
validateDatabase :: UnitConfig -> UnitInfoMap
                 -> (UnitInfoMap, UnusableUnits, [SCC UnitInfo])
validateDatabase cfg pkg_map1 =
    (pkg_map5, unusable, sccs)
  where
    ignore_flags = reverse (unitConfigFlagsIgnored cfg)

    -- Compute the reverse dependency index
    index = reverseDeps pkg_map1

    -- Helper function
    mk_unusable mk_err dep_matcher m uids =
      listToUniqMap [ (unitId pkg, (pkg, mk_err (dep_matcher m pkg)))
                    | pkg <- uids
                    ]

    -- Find broken units
    directly_broken = filter (not . null . depsNotAvailable pkg_map1)
                             (nonDetEltsUniqMap pkg_map1)
    (pkg_map2, broken) = removeUnits (map unitId directly_broken) index pkg_map1
    unusable_broken = mk_unusable BrokenDependencies depsNotAvailable pkg_map2 broken

    -- Find recursive units
    sccs = stronglyConnComp [ (pkg, unitId pkg, unitDepends pkg)
                            | pkg <- nonDetEltsUniqMap pkg_map2 ]
    getCyclicSCC (CyclicSCC vs) = map unitId vs
    getCyclicSCC (AcyclicSCC _) = []
    (pkg_map3, cyclic) = removeUnits (concatMap getCyclicSCC sccs) index pkg_map2
    unusable_cyclic = mk_unusable CyclicDependencies depsNotAvailable pkg_map3 cyclic

    -- Apply ignore flags
    directly_ignored = ignoreUnits ignore_flags (nonDetEltsUniqMap pkg_map3)
    (pkg_map4, ignored) = removeUnits (nonDetKeysUniqMap directly_ignored) index pkg_map3
    unusable_ignored = mk_unusable IgnoredDependencies depsNotAvailable pkg_map4 ignored

    -- Knock out units whose dependencies don't agree with ABI
    -- (i.e., got invalidated due to shadowing)
    directly_shadowed = filter (not . null . depsAbiMismatch pkg_map4)
                               (nonDetEltsUniqMap pkg_map4)
    (pkg_map5, shadowed) = removeUnits (map unitId directly_shadowed) index pkg_map4
    unusable_shadowed = mk_unusable ShadowedDependencies depsAbiMismatch pkg_map5 shadowed

    -- combine all unusables. The order is important for shadowing.
    -- plusUniqMapList folds using plusUFM which is right biased (opposite of
    -- Data.Map.union) so the head of the list should be the least preferred
    unusable = plusUniqMapList [ unusable_shadowed
                               , unusable_cyclic
                               , unusable_broken
                               , unusable_ignored
                               , directly_ignored
                               ]

-- -----------------------------------------------------------------------------
-- Package Utils

-- | Takes a 'ModuleName', and if the module is in any package returns
-- list of modules which take that name.
lookupModuleInAllUnits :: UnitState
                          -> UnitIndexQuery
                          -> ModuleName
                          -> [(Module, UnitInfo)]
lookupModuleInAllUnits pkgs query m
  = case lookupModuleWithSuggestions pkgs query m NoPkgQual of
      LookupFound a b -> [(a,fst b)]
      LookupMultiple rs -> map f rs
        where f (m,_) = (m, expectJust "lookupModule" (lookupUnit pkgs
                                                         (moduleUnit m)))
      _ -> []

-- | The package which the module **appears** to come from, this could be
-- the one which reexports the module from it's original package. This function
-- is currently only used for -Wunused-packages
lookupModulePackage ::
  UnitState ->
  UnitIndexQuery ->
  ModuleName ->
  PkgQual ->
  Maybe [UnitInfo]
lookupModulePackage pkgs query mn mfs =
    case lookupModuleWithSuggestions' pkgs query mn False mfs of
      LookupFound _ (orig_unit, origin) ->
        case origin of
          ModOrigin {fromOrigUnit, fromExposedReexport} ->
            case fromOrigUnit of
              -- Just True means, the import is available from its original location
              Just True ->
                pure [orig_unit]
              -- Otherwise, it must be available from a reexport
              _ -> pure fromExposedReexport

          _ -> Nothing

      _ -> Nothing

lookupPluginModuleWithSuggestions :: UnitState
                                  -> UnitIndexQuery
                                  -> ModuleName
                                  -> PkgQual
                                  -> LookupResult
lookupPluginModuleWithSuggestions pkgs query name
  = lookupModuleWithSuggestions' pkgs query name True

lookupModuleWithSuggestions' :: UnitState
                            -> UnitIndexQuery
                            -> ModuleName
                            -> Bool
                            -> PkgQual
                            -> LookupResult
lookupModuleWithSuggestions' pkgs query m onlyPlugins mb_pn
  = case query.findOrigin pkgs m onlyPlugins of
        Nothing -> LookupNotFound suggestions
        Just xs ->
          case foldl' classify ([],[],[], []) (sortOn fst $ nonDetUniqMapToList xs) of
            ([], [], [], []) -> LookupNotFound suggestions
            (_, _, _, [(m, o)])             -> LookupFound m (mod_unit m, o)
            (_, _, _, exposed@(_:_))        -> LookupMultiple exposed
            ([], [], unusable@(_:_), [])    -> LookupUnusable unusable
            (hidden_pkg, hidden_mod, _, []) ->
              LookupHidden hidden_pkg hidden_mod
  where
    classify (hidden_pkg, hidden_mod, unusable, exposed) (m, origin0) =
      let origin = filterOrigin mb_pn (mod_unit m) origin0
          x = (m, origin)
      in case origin of
          ModHidden
            -> (hidden_pkg, x:hidden_mod, unusable, exposed)
          ModUnusable _
            -> (hidden_pkg, hidden_mod, x:unusable, exposed)
          _ | originEmpty origin
            -> (hidden_pkg,   hidden_mod, unusable, exposed)
            | originVisible origin
            -> (hidden_pkg, hidden_mod, unusable, x:exposed)
            | otherwise
            -> (x:hidden_pkg, hidden_mod, unusable, exposed)

    unit_lookup p = lookupUnit pkgs p `orElse` pprPanic "lookupModuleWithSuggestions" (ppr p <+> ppr m)
    mod_unit = unit_lookup . moduleUnit

    -- Filters out origins which are not associated with the given package
    -- qualifier.  No-op if there is no package qualifier.  Test if this
    -- excluded all origins with 'originEmpty'.
    filterOrigin :: PkgQual
                 -> UnitInfo
                 -> ModuleOrigin
                 -> ModuleOrigin
    filterOrigin NoPkgQual _ o = o
    filterOrigin (ThisPkg _) _ o = o
    filterOrigin (OtherPkg u) pkg o =
      let match_pkg p = u == unitId p
      in case o of
          ModHidden
            | match_pkg pkg -> ModHidden
            | otherwise     -> mempty
          ModUnusable _
            | match_pkg pkg -> o
            | otherwise     -> mempty
          ModOrigin { fromOrigUnit = e, fromExposedReexport = res,
                      fromHiddenReexport = rhs }
            -> ModOrigin
                { fromOrigUnit        = if match_pkg pkg then e else Nothing
                , fromExposedReexport = filter match_pkg res
                , fromHiddenReexport  = filter match_pkg rhs
                , fromPackageFlag     = False -- always excluded
                }

    suggestions = fuzzyLookup (moduleNameString m) all_mods

    all_mods :: [(String, ModuleSuggestion)]     -- All modules
    all_mods = sortBy (comparing fst) $
        [ (moduleNameString m, suggestion)
        | (m, e) <- nonDetUniqMapToList (query.index_all pkgs)
        , suggestion <- map (getSuggestion m) (nonDetUniqMapToList e)
        ]
    getSuggestion name (mod, origin) =
        (if originVisible origin then SuggestVisible else SuggestHidden)
            name mod origin

listVisibleModuleNames :: UnitState -> UnitIndexQuery -> [ModuleName]
listVisibleModuleNames us query =
    map fst (filter visible (nonDetUniqMapToList (query.index_all us)))
  where visible (_, ms) = anyUniqMap originVisible ms

-- | Similar to closeUnitDeps but takes a list of already loaded units as an
-- additional argument.
closeUnitDeps' :: UnitInfoMap -> [UnitId] -> [(UnitId,Maybe UnitId)] -> MaybeErr UnitErr [UnitId]
closeUnitDeps' pkg_map current_ids ps = foldM (uncurry . add_unit pkg_map) current_ids ps

-- | Add a UnitId and those it depends on (recursively) to the given list of
-- UnitIds if they are not already in it. Return a list in reverse dependency
-- order (a unit appears before those it depends on).
--
-- The UnitId is looked up in the given UnitInfoMap (to find its dependencies).
-- It it's not found, the optional parent unit is used to return a more precise
-- error message ("dependency of <PARENT>").
add_unit :: UnitInfoMap
            -> [UnitId]
            -> UnitId
            -> Maybe UnitId
            -> MaybeErr UnitErr [UnitId]
add_unit pkg_map ps p mb_parent
  | p `elem` ps = return ps     -- Check if we've already added this unit
  | otherwise   = case lookupUnitId' pkg_map p of
      Nothing   -> Failed (CloseUnitErr p mb_parent)
      Just info -> do
         -- Add the unit's dependents also
         ps' <- foldM add_unit_key ps (unitDepends info)
         return (p : ps')
        where
          add_unit_key xs key
            = add_unit pkg_map xs key (Just p)

-- | Return this list of requirement interfaces that need to be merged
-- to form @mod_name@, or @[]@ if this is not a requirement.
requirementMerges :: UnitState -> ModuleName -> [InstantiatedModule]
requirementMerges pkgstate mod_name =
  fromMaybe [] (lookupUniqMap (requirementContext pkgstate) mod_name)

-- -----------------------------------------------------------------------------

pprUnitInfoForUser :: UnitInfo -> SDoc
pprUnitInfoForUser info = ppr (mkUnitPprInfo unitIdFS info)

lookupUnitPprInfo :: UnitState -> UnitId -> Maybe UnitPprInfo
lookupUnitPprInfo state uid = fmap (mkUnitPprInfo unitIdFS) (lookupUnitId state uid)

-- -----------------------------------------------------------------------------
-- Displaying packages

-- | Show (very verbose) package info
pprUnits :: UnitState -> SDoc
pprUnits = pprUnitsWith pprUnitInfo

pprUnitsWith :: (UnitInfo -> SDoc) -> UnitState -> SDoc
pprUnitsWith pprIPI pkgstate =
    vcat (intersperse (text "---") (map pprIPI (listUnitInfo pkgstate)))

-- | Show simplified unit info.
--
-- The idea is to only print package id, and any information that might
-- be different from the package databases (exposure, trust)
pprUnitsSimple :: UnitState -> SDoc
pprUnitsSimple = pprUnitsWith pprIPI
    where pprIPI ipi = let i = unitIdFS (unitId ipi)
                           e = if unitIsExposed ipi then text "E" else text " "
                           t = if unitIsTrusted ipi then text "T" else text " "
                       in e <> t <> text "  " <> ftext i

-- | Show the mapping of modules to where they come from.
pprModuleMap :: ModuleNameProvidersMap -> SDoc
pprModuleMap mod_map =
  vcat (map pprLine (nonDetUniqMapToList mod_map))
    where
      pprLine (m,e) = ppr m $$ nest 50 (vcat (map (pprEntry m) (nonDetUniqMapToList e)))
      pprEntry :: Outputable a => ModuleName -> (Module, a) -> SDoc
      pprEntry m (m',o)
        | m == moduleName m' = ppr (moduleUnit m') <+> parens (ppr o)
        | otherwise = ppr m' <+> parens (ppr o)

fsPackageName :: UnitInfo -> FastString
fsPackageName info = fs
   where
      PackageName fs = unitPackageName info

-- | Given a fully instantiated 'InstantiatedUnit', improve it into a
-- 'RealUnit' if we can find it in the package database.
improveUnit' :: UnitInfoMap -> PreloadUnitClosure -> Unit -> Unit
improveUnit' _       _       uid@(RealUnit _) = uid -- short circuit
improveUnit' pkg_map closure uid =
    -- Do NOT lookup indefinite ones, they won't be useful!
    case lookupUnit' False pkg_map closure uid of
        Nothing  -> uid
        Just pkg ->
            -- Do NOT improve if the indefinite unit id is not
            -- part of the closure unique set.  See
            -- Note [VirtUnit to RealUnit improvement]
            if unitId pkg `elementOfUniqSet` closure
                then mkUnit pkg
                else uid

-- | Substitutes holes in a 'Module'.  NOT suitable for being called
-- directly on a 'nameModule', see Note [Representation of module/name variables].
-- @p[A=\<A>]:B@ maps to @p[A=q():A]:B@ with @A=q():A@;
-- similarly, @\<A>@ maps to @q():A@.
renameHoleModule :: UnitState -> ShHoleSubst -> Module -> Module
renameHoleModule state = renameHoleModule' (unitInfoMap state) (preloadClosure state)

-- | Substitutes holes in a 'Unit', suitable for renaming when
-- an include occurs; see Note [Representation of module/name variables].
--
-- @p[A=\<A>]@ maps to @p[A=\<B>]@ with @A=\<B>@.
renameHoleUnit :: UnitState -> ShHoleSubst -> Unit -> Unit
renameHoleUnit state = renameHoleUnit' (unitInfoMap state) (preloadClosure state)

-- | Injects an 'InstantiatedModule' to 'Module' (see also
-- 'instUnitToUnit'.
instModuleToModule :: UnitState -> InstantiatedModule -> Module
instModuleToModule pkgstate (Module iuid mod_name) =
    mkModule (instUnitToUnit pkgstate iuid) mod_name

-- | Print unit-ids with UnitInfo found in the given UnitState
pprWithUnitState :: UnitState -> SDoc -> SDoc
pprWithUnitState state = updSDocContext (\ctx -> ctx
   { sdocUnitIdForUser = \fs -> pprUnitIdForUser state (UnitId fs)
   })

-- | Add package dependencies on the wired-in packages we use
implicitPackageDeps :: DynFlags -> [UnitId]
implicitPackageDeps dflags
   = [thUnitId | xopt TemplateHaskellQuotes dflags]
   -- TODO: Should also include `base` and `ghc-prim` if we use those implicitly, but
   -- it is possible to not depend on base (for example, see `ghc-prim`)

-- | Create a Map UnitId UnitInfo
--
-- For each instantiated unit, we add two map keys:
--    * the real unit id
--    * the virtual unit id made from its instantiation
--
-- We do the same thing for fully indefinite units (which are "instantiated"
-- with module holes).
--
mkUnitInfoMap :: [UnitInfo] -> UnitInfoMap
mkUnitInfoMap infos = foldl' add emptyUniqMap infos
  where
   mkVirt      p = virtualUnitId (mkInstantiatedUnit (unitInstanceOf p) (unitInstantiations p))
   add pkg_map p
      | not (null (unitInstantiations p))
      = addToUniqMap (addToUniqMap pkg_map (mkVirt p) p)
                     (unitId p) p
      | otherwise
      = addToUniqMap pkg_map (unitId p) p

updateIndexDefault ::
  Logger ->
  UnitId ->
  UnitConfig ->
  [UnitDatabase UnitId] ->
  [PackageFlag] ->
  IO (ModuleNameProvidersMap, ModuleNameProvidersMap, UnitInfoMap, [(Unit, Maybe PackageArg)], [UnitId], UniqMap ModuleName [InstantiatedModule], UniqFM PackageName UnitId, WiringMap)
updateIndexDefault logger _ cfg raw_dbs other_flags = do

  -- distrust all units if the flag is set
  let distrust_all db = db { unitDatabaseUnits = distrustAllUnits (unitDatabaseUnits db) }
      dbs | unitConfigDistrustAll cfg = map distrust_all raw_dbs
          | otherwise                 = raw_dbs


  -- Merge databases together, without checking validity
  (pkg_map1, prec_map) <- mergeDatabases logger dbs

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
  pure (mod_map, pluginModuleNameProviders, pkg_db, explicit_pkgs, dep_preload, req_ctx, pkgname_map, wired_map)

#endif
