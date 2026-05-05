{-# LANGUAGE CPP, PatternSynonyms #-}

module Internal.BuildPlan where

import Control.Monad (unless)
import Data.Aeson (eitherDecodeFileStrict')
import Data.Either (partitionEithers)
import Data.Foldable (toList)
import Data.List.NonEmpty (NonEmpty (..), groupAllWith)
import Data.Map (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Set (Set)
import Data.Traversable (for)
import qualified GHC
import GHC (Target)
import GHC.Data.Maybe (mapMaybe)
import GHC.Driver.Backend (noBackend)
import GHC.Driver.DynFlags (backend)
import GHC.Driver.Env (HscEnv (..), hscActiveUnitId, hsc_units)
import GHC.Driver.Errors.Types (DriverMessages, GhcMessage (..))
import GHC.Driver.Monad (GhcMonad (..), liftIO, withSession)
import GHC.Driver.Phases (Phase (Unlit), StopPhase (..), startPhase)
import GHC.Driver.Pipeline (TPhase (..), mkPipeEnv, runPipeline, use)
import GHC.Driver.Pipeline.Monad (PipelineOutput (..))
import GHC.Driver.Session (pgm_F)
import GHC.Types.Error (unionManyMessages)
import GHC.Types.SourceError (throwErrors)
import GHC.Types.Unique.Map (UniqMap)
import GHC.Unit (GenWithIsBoot (..), UnitState (..))
import GHC.Unit.Env (UnitEnv (..))
import GHC.Unit.Module (IsBootInterface (..), ModLocation (..), ModuleName (..), UnitId (..))
import GHC.Unit.Home.Graph (unitEnv_keys)
import GHC.Unit.Module.Graph (
  ModNodeKeyWithUid (..),
  ModuleGraph,
  ModuleGraphNode (..),
  NodeKey (..),
  mgModSummaries',
  msKey,
  )
import GHC.Unit.Module.ModSummary (ModSummary (..), isBootSummary, msHsFilePath, ms_mod_name, ms_unitid)
import GHC.Utils.Error (isEmptyMessages)
import Internal.BuildPlan.External (packageName, unitImports)
import Internal.BuildPlan.Incremental (
  incrementalGraphCache,
  incrementalTargets,
  loadCachedGraph,
  mergeBuildPlanJson,
  mergeModuleGraphs,
  writeIncrementalState,
  )
import Internal.BuildPlan.Json (assembleFields)
import qualified Internal.Compat.FixedNodes as FixedNodes
import Internal.Compat.FixedNodes (pattern CompileNode, pattern FixedNode, downsweepCompat)
import Internal.Compat.GHC914 (edgeTarget)
import Internal.Error (eitherMessages)
import Internal.Log (logTimed)
import System.FilePath (splitExtension)
import System.OsPath (OsPath)
import Types.Args (BuildPlanField (..))
import Types.BuildPlan (
  BuildPlan (..),
  BuildPlanEnv (..),
  BuildPlanJson (..),
  BuildPlanModule (..),
  Dep (..),
  ModuleKey,
  PackageDep (..),
  PackageKey,
  Preprocessor (..),
  moduleKey,
  packageKey,
  summaryModuleKey,
  )
import Types.CachedDeps (JsonFs (..))
import Types.Log (Logger (..))

#if MIN_VERSION_GLASGOW_HASKELL(9,14,0,0)

import GHC.Unit.Module.ModSummary (isTemplateHaskellOrQQNonBoot)

#else

import GHC.Unit.Module.Graph (isTemplateHaskellOrQQNonBoot)

#endif

#if defined(FIXED_NODES)

import GHC.Unit.Module.Graph (ModuleNodeInfo (..))
import Types.BuildPlan (moduleKeyBoot)

#endif

#if defined(DOWNSWEEP_CACHE)

import GHC.Unit.Module.Graph (mgModSummaries)

#endif

isBoot :: ModSummary -> Bool
isBoot summary = isBootSummary summary == IsBoot

modulePreprocessor :: HscEnv -> Preprocessor -> ModSummary -> IO Preprocessor
modulePreprocessor hsc_env globalPreprocessor summary
  | Just src <- ml_hs_file (ms_location summary)
  = runPipeline (hsc_hooks hsc_env) $ do
    let (_, suffix) = splitExtension src
        lit | Unlit _ <- startPhase suffix = True
            | otherwise = False
        pipe_env = mkPipeEnv StopPreprocess src Nothing NoOutputFile
    unlit_fn <- if lit then use (T_Unlit pipe_env hsc_env src) else pure src
    (dflags1, _, _) <- use (T_FileArgs hsc_env unlit_fn)
    let pp = pgm_F dflags1
    pure (if null pp then globalPreprocessor else Preprocessor (Just pp))
  | otherwise
  = pure globalPreprocessor

modulePackageDeps ::
  UniqMap UnitId PackageKey ->
  Map NodeKey Dep ->
  Set NodeKey ->
  [PackageDep]
modulePackageDeps unitNames deps keys =
  fmap packageDep $
  groupAllWith (.unit) $
  Map.elems $
  Map.restrictKeys deps keys
  where
    packageDep ds@(Dep {unit} :| _) =
      PackageDep {
        id = JsonFs unit,
        name = packageName unitNames unit,
        modules = [JsonFs name | Dep {name} <- toList ds]
      }

buildPlanModule ::
  BuildPlanEnv ->
  (ModSummary, Set NodeKey) ->
  IO (ModuleKey, BuildPlanModule)
buildPlanModule env (summary, depKeys) = do
  preprocessor <- modulePreprocessor env.hsc_env env.globalPreprocessor summary
  let bpModule = BuildPlanModule {
    source,
    sources = [source],
    boot = isBoot summary,
    modules,
    modulesBoot,
    packages = modulePackageDeps env.unitNames env.packageModules depKeys,
    thEnabled = isTemplateHaskellOrQQNonBoot summary,
    preprocessor
  }
  pure (summaryModuleKey summary, bpModule)
  where
    source = msHsFilePath summary

    (modules, modulesBoot) = partitionEithers $ Map.elems $ Map.restrictKeys env.homeModules depKeys

-- | Classify a module graph node for the build plan.
--
-- Module graphs contain several different node types.
-- The build plan's purpose is to provide dependency information between the project's modules to the external build
-- tool, so we're only interested in nodes that represent modules.
--
-- There are two subtypes of module node:
-- - Compile nodes, which represent modules that are intended to be compiled in a later action.
--   These contain a 'ModSummary' with the parsed AST and other data required for compilation.
-- - Fixed nodes, representing modules that are already built.
--   These only contain a 'ModLocation', through which their interface files may be located while compiling dependents.
--
-- Both need to be included in the build plan, since the build tool processes the dependencies of the entire unit even
-- when only parts of it have changed, and we don't want any inconsistencies between the two builds.
--
-- The results of this function are used to construct memory-efficient lookup indexes, which is why the return avoids
-- new, more expressive types:
--
-- - 'Nothing' is a node that's of no use to Buck.
--   Aside from Backpack and link nodes, these include fixed nodes in the unit for which we're constructing the build
--   plan, which isn't supported yet.
-- - 'Left' is a module belonging to the build plan (home) unit, containing the full 'ModSummary'.
-- - 'Right' is a module from a different unit, which is only required to resolve dependencies from the home unit.
--   If this module was present as a compile node (i.e. it was built earlier in the same process), it will be in the
--   shape of a 'ModSummary' as well.
--   If it was restored from cache as a fixed node, it will only provide its unit ID and module name.
--   That information is sufficient for the build plan.
--
-- In both cases, the return value also comprises the dependencies as a 'Set' of 'NodeKey'.
--
-- The data is shaped like it is because it allows 'buildPlanEnv' to partition the entirety of the modules.
buildPlanNode ::
  HscEnv ->
  ModuleGraphNode ->
  Maybe (Either (ModSummary, Set NodeKey) ((ModNodeKeyWithUid, Maybe ModSummary), Set NodeKey))
buildPlanNode hsc_env = \case
  CompileNode {deps, summary}
    | hscActiveUnitId hsc_env == ms_unitid summary
    -> Just (Left (summary, construct deps))
    | otherwise
    -> Just (Right ((msKey summary, Just summary), construct deps))
  -- TODO check if the later commit handles home unit modules here as well, or determine how it should be done
  FixedNode {deps, key = key@(ModNodeKeyWithUid _ unit)}
    | hscActiveUnitId hsc_env /= unit
    -> Just (Right ((key, Nothing), construct deps))
  _ -> Nothing
  where
    construct deps = Set.fromList (edgeTarget <$> deps)

-- | Convert a list of module metadata to a 'Map' using a value constructor function.
indexWith ::
  (ModNodeKeyWithUid -> Maybe ModSummary -> a) ->
  [(ModNodeKeyWithUid, Maybe ModSummary)] ->
  Map NodeKey a
indexWith f =
  Map.fromList . fmap \ (key, summary) -> (NodeKey_Module key, f key summary)

-- | Create a lookup index for all modules in the build plan home unit that allow sharing constructor closures for
-- memory efficiency.
-- This is indexed later with the 'NodeKey's from each module's dependency set.
--
-- For easier partioning, boot modules are wrapped in 'Right' and regular modules in 'Left'.
-- If 'indexWith' passes 'Nothing' for the 'ModSummary' argument to the callback, we're dealing with a fixed node.
localIndex :: [ModSummary] -> Map NodeKey (Either (ModuleKey, JsonFs ModuleName) (ModuleKey, JsonFs ModuleName))
localIndex =
  indexWith classifyFixedAndBoot
  .
  fmap \ summary -> (msKey summary, Just summary)
  where
    classifyFixedAndBoot ::
      ModNodeKeyWithUid ->
      Maybe ModSummary ->
      Either (ModuleKey, JsonFs ModuleName) (ModuleKey, JsonFs ModuleName)
    classifyFixedAndBoot (ModNodeKeyWithUid GWIB {gwib_mod} _) = \case
      Just summary -> classify summary (summaryModuleKey summary, JsonFs (ms_mod_name summary))
      Nothing -> Left (moduleKey gwib_mod, JsonFs gwib_mod)

    classify summary = if isBoot summary then Right else Left

-- | Create a lookup index for all units in the module graph that allow sharing constructor closures for memory
-- efficiency.
packageIndex :: [(ModNodeKeyWithUid, Maybe ModSummary)] -> Map NodeKey Dep
packageIndex =
  indexWith \ (ModNodeKeyWithUid (GWIB {gwib_mod = name}) unit) _ -> Dep {name, unit}

#if defined(FIXED_NODES)

-- | Extract home-unit module entries from 'ModuleNodeFixed' graph nodes.
--
-- During incremental metadata, unchanged modules appear as 'ModuleNodeFixed' in the merged graph.
-- This function provides their entries for 'homeModules' so that changed modules can resolve
-- intra-unit dependencies to them.
fixedNodeHomeModules ::
  HscEnv ->
  [ModuleGraphNode] ->
  Map NodeKey (Either (ModuleKey, JsonFs ModuleName) (ModuleKey, JsonFs ModuleName))
fixedNodeHomeModules hsc_env =
  Map.fromList . mapMaybe fixedHome
  where
    fixedHome = \case
      ModuleNode _ (ModuleNodeFixed (ModNodeKeyWithUid mnwib uid) _)
        | uid == hscActiveUnitId hsc_env
        -> let name = gwib_mod mnwib
               mk = if gwib_isBoot mnwib == IsBoot then moduleKeyBoot name else moduleKey name
               entry = (mk, JsonFs name)
               nk = NodeKey_Module (ModNodeKeyWithUid mnwib uid)
           in Just (nk, if gwib_isBoot mnwib == IsBoot then Right entry else Left entry)
      _ -> Nothing

#endif

-- | Precompute lookup indexes and module metadata for the build plan.
--
-- JSON data structures for a module graph with thousands of modules and tens of thousands of dependencies can cause
-- significant memory overhead when each dependency allocates a fresh constructor closure, or even a string, if that
-- dependency is present in many modules.
--
-- To mitigate this, we create indexes of the data structures that are most commonly shared, like 'ModuleKey' and
-- 'PackageKey', so that they can be looked up and reused rather than recreated from the GHC types in 'ModuleGraph'.
--
-- The data for each module is constructed in 'buildPlanNode', which is then fed into 'localIndex' and 'packageIndex' to
-- create the lookup indexes.
-- In 'buildPlanModule', these indexes are then queried to replace the 'NodeKey' values from the 'ModuleGraph' with
-- those shared closures.
--
-- Aside from the 'BuildPlanEnv', this also returns the full set of nodes belonging to the home unit, as 'ModSummary'
-- and set of dependency 'NodeKey's.
buildPlanEnv ::
  HscEnv ->
  ModuleGraph ->
  (BuildPlanEnv, [(ModSummary, Set NodeKey)])
buildPlanEnv hsc_env graph =
  (env, local)
  where
    env = BuildPlanEnv {
      unitNames,
      homeUnitIds,
#if defined(FIXED_NODES)
      homeModules = localIndex (fst <$> local) <> fixedNodeHomeModules hsc_env (mgModSummaries' graph),
#else
      homeModules = localIndex (fst <$> local),
#endif
      packageModules = packageIndex (fst <$> packages),
      ..
    }

    unitNames = packageKey <$> (hsc_units hsc_env).unitInfoMap

    homeUnitIds = unitEnv_keys hsc_env.hsc_unit_env.ue_home_unit_graph

    (local, packages) = partitionEithers (mapMaybe (buildPlanNode hsc_env) (mgModSummaries' graph))

    globalPreprocessor
      | let pp = pgm_F hsc_env.hsc_dflags
      , not (null pp)
      = Preprocessor (Just pp)
      | otherwise
      = Preprocessor Nothing

-- | Compute lookup indexes for a module graph and construct a JSON build plan payload for an external build tool for
-- all modules in the active home unit.
-- Look up all imports of modules that aren't present in the graph in the external package databases.
buildPlanModules ::
  GhcMonad m =>
  Set BuildPlanField ->
  HscEnv ->
  ModuleGraph ->
  m BuildPlanJson
buildPlanModules fields hsc_env graph = do
  toolchainDeps <-
    if includeToolchainDeps
    then eitherMessages GhcDriverMessage =<< liftIO (unitImports env (fst <$> modules))
    else pure []
  assembleFields fields toolchainDeps . Map.fromList <$> liftIO (traverse (buildPlanModule env) modules)
  where
    (env, modules) = buildPlanEnv hsc_env graph

    includeToolchainDeps = FieldToolchainDeps `elem` fields || FieldPackageDeps `elem` fields

downsweepWithCache :: HscEnv -> IO ([DriverMessages], ModuleGraph)

#if defined(DOWNSWEEP_CACHE)

downsweepWithCache hsc_env = do
  let cachedGraph = hsc_env.hsc_mod_graph
  downsweepCompat hsc_env (mgModSummaries cachedGraph) (Just cachedGraph) [] True

#else

downsweepWithCache hsc_env = downsweepCompat hsc_env [] Nothing [] True

#endif

-- | Extract old summaries from a cached graph for downsweep timestamp comparison.
-- On FIXED_NODES, cached graphs contain fixed nodes without 'ModSummary', so this returns @[]@.
-- On other GHCs, cached graphs contain compile nodes with 'ModSummary'.
oldSummaries :: ModuleGraph -> [ModSummary]
#if defined(FIXED_NODES)
oldSummaries _ = []
#elif defined(DOWNSWEEP_CACHE)
oldSummaries = mgModSummaries
#else
oldSummaries graph = [s | ModuleNode _ s <- mgModSummaries' graph]
#endif

-- | Disabling the backend, in conjunction with setting `ghcMode = MkDepend`, prevents
--   downsweep from performing TH dependency analysis, which is the external build tool's
--   responsibility.
useNoBackend :: HscEnv -> HscEnv
useNoBackend hsc_env =
  let dflags = hsc_dflags hsc_env
   in hsc_env { hsc_dflags = dflags {backend = noBackend}}

buildPlanForTargets ::
  GhcMonad m =>
  Logger ->
  Set BuildPlanField ->
  [Target] ->
  m BuildPlan
buildPlanForTargets logger fields targets = do
  GHC.setTargets targets
  (errs, graph) <- logTimed logger "Downsweep" $ withSession (liftIO . downsweepWithCache . useNoBackend)
  let msgs = unionManyMessages errs
  unless (isEmptyMessages msgs) $ throwErrors (fmap GhcDriverMessage msgs)
  hsc_env <- getSession
  json <- logTimed logger "Build plan modules" $ buildPlanModules fields hsc_env graph
  pure BuildPlan {graph, json}

-- | Toggle for incremental metadata.
-- When 'True', 'buildPlanForSources' uses the incremental path when a previous state file exists.
-- When 'False', always runs full downsweep.
-- Flip for A/B profiling comparisons.
buildPlanForSources ::
  GhcMonad m =>
  Bool ->
  Logger ->
  Set BuildPlanField ->
  Maybe OsPath ->
  Maybe FilePath ->
  [FilePath] ->
  m BuildPlan
buildPlanForSources useIncrementalMetadata logger fields mbBuildPlan actionMetadata srcs = do
  case mbBuildPlan of
    Just buildPlan | useIncrementalMetadata -> do
      result <- liftIO $ incrementalTargets buildPlan actionMetadata srcs
      case result of
        Just (changed, meta, cachedJson) -> do
          liftIO $ logger.debug ("Incremental metadata: " ++ show (length changed) ++ " changed source(s)")
          plan <- buildPlanIncremental logger fields buildPlan changed allSources cachedJson
          liftIO $ writeIncrementalState buildPlan meta plan.json
          pure plan
        Nothing -> do
          liftIO $ logger.debug "No incremental state available, running full metadata"
          plan <- buildPlanFull logger fields srcs
          liftIO $ writeIncrementalStateFromSources buildPlan actionMetadata plan.json
          pure plan
    Just buildPlan -> do
      plan <- buildPlanFull logger fields srcs
      liftIO $ writeIncrementalStateFromSources buildPlan actionMetadata plan.json
      pure plan
    Nothing -> buildPlanFull logger fields srcs
  where
    allSources = srcs

-- | Full downsweep targeting all sources.
buildPlanFull ::
  GhcMonad m =>
  Logger ->
  Set BuildPlanField ->
  [FilePath] ->
  m BuildPlan
buildPlanFull logger fields srcs = do
  targets <- for srcs \ src -> GHC.guessTarget src Nothing Nothing
  buildPlanForTargets logger fields targets

-- | Write incremental state when no previous state existed (first run).
writeIncrementalStateFromSources :: OsPath -> Maybe FilePath -> BuildPlanJson -> IO ()
writeIncrementalStateFromSources buildPlan actionMetadata json =
  case actionMetadata of
    Nothing -> pure ()
    Just metaPath ->
      eitherDecodeFileStrict' metaPath >>= \case
        Left _ -> pure ()
        Right meta -> writeIncrementalState buildPlan meta json

-- | Incremental build plan: pre-load cached graph, downsweep only changed sources, merge.
--
-- On FIXED_NODES GHC, unchanged modules are loaded as 'ModuleNodeFixed' (no source parsing).
-- The build plan for changed modules is computed normally, then merged with the cached
-- 'BuildPlanJson' from the previous run.
--
-- On other GHCs, unchanged modules are loaded via 'summariseFile' as before.
buildPlanIncremental ::
  GhcMonad m =>
  Logger ->
  Set BuildPlanField ->
  OsPath ->
  [FilePath] ->
  [FilePath] ->
  Maybe BuildPlanJson ->
  m BuildPlan
buildPlanIncremental logger fields buildPlan changed allSources cachedJson
  | null changed = do
    -- Nothing changed: run full build (rare edge case)
    buildPlanFull logger fields allSources
  | otherwise = do
    hsc_env0 <- getSession
    mbCachedGraph <- logTimed logger "Load cached graph" $ liftIO $ loadCachedGraph hsc_env0 buildPlan
    case mbCachedGraph of
      Nothing -> do
        liftIO $ logger.debug "Cached graph unavailable, falling back to full metadata"
        buildPlanFull logger fields allSources
      Just cachedGraph -> do
        -- Target only changed sources
        targets <- traverse (\ src -> GHC.guessTarget src Nothing Nothing) changed
        GHC.setTargets targets
        -- Build a graph cache containing dep-unit modules AND unchanged current-unit
        -- modules. Only changed modules are excluded, so downsweep only re-processes
        -- those. This makes downsweep near-instant for single-module changes.
        (errs, freshGraph) <- logTimed logger ("Downsweep (" ++ show (length changed) ++ " changed)") $
          withSession \ hsc_env -> liftIO $ do
            let cache = incrementalGraphCache hsc_env cachedGraph changed
            downsweepCompat hsc_env (oldSummaries cachedGraph) (Just cache) [] True
        let msgs = unionManyMessages errs
        unless (isEmptyMessages msgs) $ throwErrors (fmap GhcDriverMessage msgs)
        -- Merge: fresh nodes (changed modules + their transitive imports from downsweep)
        -- take precedence over cached nodes
        let graph = mergeModuleGraphs freshGraph cachedGraph
        hsc_env <- getSession
        freshJson <- logTimed logger "Build plan modules" $ buildPlanModules fields hsc_env graph
        let json = maybe freshJson (mergeBuildPlanJson freshJson) cachedJson
        pure BuildPlan {graph, json}
