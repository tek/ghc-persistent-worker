{-# LANGUAGE CPP #-}

module Internal.BuildPlan where

#if defined(MWB_2025_10)

import GHC.Types.Error (mkUnknownDiagnostic)

#endif

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
import GHC.Driver.Env (HscEnv (..), hscActiveUnitId, hsc_units)
import GHC.Driver.Errors.Types (DriverMessages, GhcMessage (GhcDriverMessage))
import GHC.Driver.Make (downsweep)
import GHC.Driver.Monad (GhcMonad (..), liftIO, withSession)
import GHC.Driver.Phases (Phase (Unlit), StopPhase (..), startPhase)
import GHC.Driver.Pipeline (TPhase (..), mkPipeEnv, runPipeline, use)
import GHC.Driver.Pipeline.Monad (PipelineOutput (..))
import GHC.Driver.Session (pgm_F)
import GHC.Types.Error (unionManyMessages)
import GHC.Types.SourceError (throwErrors)
import GHC.Types.Unique.Map (UniqMap)
import GHC.Unit (UnitState (..))
import GHC.Unit.Env (UnitEnv (..))
import GHC.Unit.Module (IsBootInterface (..), ModLocation (..), ModuleName (..), UnitId (..))
import GHC.Unit.Module.Graph (ModuleGraph, ModuleGraphNode (..), NodeKey (..), mgModSummaries', msKey)
import GHC.Unit.Module.ModSummary (ModSummary (..), isBootSummary, msHsFilePath, ms_mod_name, ms_unitid)
import GHC.Utils.Error (isEmptyMessages)
import Internal.BuildPlan.External (packageName, unitImports)
import Internal.BuildPlan.Incremental (
  incrementalTargets,
  loadCachedGraph,
  mergeBuildPlanJson,
  mergeModuleGraphs,
  writeIncrementalState,
  )
import Internal.BuildPlan.Json (assembleFields)
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
  moduleKeyBoot,
  packageKey,
  summaryModuleKey,
  )
import Types.CachedDeps (JsonFs (..))
import Types.Log (Logger (..))

#if !MIN_VERSION_GLASGOW_HASKELL(9,10,0,0)

import GHC.Utils.Panic.Plain

#endif

#if defined(MWB) || defined(MWB_2025_10)

import GHC.Unit.Home.Graph (unitEnv_keys)

#else

import GHC.Unit.Env (unitEnv_keys)

#endif

#if defined(MWB_2025_10)

import GHC.Unit.Module.ModSummary (isTemplateHaskellOrQQNonBoot)

#else

import GHC.Unit.Module.Graph (isTemplateHaskellOrQQNonBoot, mkModuleGraph)

#endif

#if defined(FIXED_NODES)

import GHC.Unit (gwib_isBoot, gwib_mod)
import GHC.Unit.Module.Graph (ModNodeKeyWithUid (..), ModuleNodeInfo (..))

#endif

#if defined(DOWNSWEEP_CACHE)

import GHC.Unit.Module.Graph (mgModSummaries)

#endif

#if !defined(MWB) && !defined(MWB_2025_10)

ms_opts :: ModSummary -> [String]
ms_opts _ = []

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
    options = Set.fromList (ms_opts summary),
    thEnabled = isTemplateHaskellOrQQNonBoot summary,
    preprocessor
  }
  pure (summaryModuleKey summary, bpModule)
  where
    source = msHsFilePath summary

    (modules, modulesBoot) = partitionEithers $ Map.elems $ Map.restrictKeys env.homeModules depKeys

-- | Extract interesting nodes and tag them 'Left' if they're part of the home unit.
--
-- We're only interested in module nodes.
buildPlanNode ::
  HscEnv ->
  ModuleGraphNode ->
  Maybe (Either (ModSummary, Set NodeKey) (ModSummary, Set NodeKey))
buildPlanNode hsc_env = \case
#if defined(FIXED_NODES)
  ModuleNode !node_deps (ModuleNodeCompile node)
#else
  ModuleNode !node_deps node
#endif
    | hscActiveUnitId hsc_env == ms_unitid node
    -> Just (Left (node, Set.fromList node_deps))
    | otherwise
    -> Just (Right (node, Set.fromList node_deps))
  _ -> Nothing

indexWith :: (ModSummary -> a) -> [ModSummary] -> Map NodeKey a
indexWith f =
  Map.fromList . fmap \ summary -> (NodeKey_Module (msKey summary), f summary)

-- | Separate boot modules from regular modules.
localIndex :: [ModSummary] -> Map NodeKey (Either (ModuleKey, JsonFs ModuleName) (ModuleKey, JsonFs ModuleName))
localIndex =
  indexWith \ summary -> decide summary (summaryModuleKey summary, JsonFs (ms_mod_name summary))
  where
    decide summary = if isBoot summary then Right else Left

packageIndex :: [ModSummary] -> Map NodeKey Dep
packageIndex =
  indexWith \ summary ->
    Dep {
      name = ms_mod_name summary,
      unit = ms_unitid summary
    }

#if defined(FIXED_NODES)

-- | Extract package dependency entries from 'ModuleNodeFixed' graph nodes.
--
-- When dep units are loaded from cache, their modules appear as 'ModuleNodeFixed'
-- rather than 'ModuleNodeCompile'. These lack a 'ModSummary', so 'buildPlanNode'
-- skips them. This function extracts their module name and unit ID directly from
-- the 'ModNodeKeyWithUid', providing the data that 'modulePackageDeps' needs.
fixedNodePackageDeps :: HscEnv -> [ModuleGraphNode] -> Map NodeKey Dep
fixedNodePackageDeps hsc_env =
  Map.fromList . mapMaybe fixedDep
  where
    fixedDep = \case
      ModuleNode _ (ModuleNodeFixed (ModNodeKeyWithUid mnwib uid) _)
        | uid /= hscActiveUnitId hsc_env
        -> Just (NodeKey_Module (ModNodeKeyWithUid mnwib uid), Dep {name = gwib_mod mnwib, unit = uid})
      _ -> Nothing

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
#if defined(FIXED_NODES)
      packageModules = packageIndex (fst <$> packages) <> fixedNodePackageDeps hsc_env (mgModSummaries' graph),
#else
      packageModules = packageIndex (fst <$> packages),
#endif
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

buildPlanModules ::
  Set BuildPlanField ->
  HscEnv ->
  ModuleGraph ->
  IO BuildPlanJson
buildPlanModules fields hsc_env graph = do
  toolchainDeps <-
    if includeToolchainDeps
    then unitImports env (fst <$> modules)
    else mempty
  assembleFields fields toolchainDeps . Map.fromList <$> traverse (buildPlanModule env) modules
  where
    (env, modules) = buildPlanEnv hsc_env graph

    includeToolchainDeps = FieldToolchainDeps `elem` fields || FieldPackageDeps `elem` fields

downsweepCompat ::
  HscEnv ->
  [ModSummary] ->
  Maybe ModuleGraph ->
  [ModuleName] ->
  Bool ->
  IO ([DriverMessages], ModuleGraph)

#if defined(FIXED_NODES)

#if defined(MWB)

downsweepCompat hsc_env summaries cache excl dup =
  fmap mkModuleGraph <$> downsweep hsc_env summaries cache excl dup

#else

downsweepCompat hsc_env summaries _ =
  downsweep hsc_env mkUnknownDiagnostic Nothing summaries

#endif

#elif defined(MWB)

downsweepCompat hsc_env summaries cache excl dup =
  fmap mkModuleGraph <$> downsweep hsc_env summaries cache excl dup

#else

downsweepCompat hsc_env summaries _ excl dup =
  fmap mkModuleGraph <$> downsweep hsc_env summaries excl dup

#endif

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

buildPlanForTargets ::
  GhcMonad m =>
  Logger ->
  Set BuildPlanField ->
  [Target] ->
  m BuildPlan
buildPlanForTargets logger fields targets = do
  GHC.setTargets targets
  (errs, graph) <- logTimed logger "Downsweep" $ withSession (liftIO . downsweepWithCache)
  let msgs = unionManyMessages errs
  unless (isEmptyMessages msgs) $ throwErrors (fmap GhcDriverMessage msgs)
  hsc_env <- getSession
  json <- logTimed logger "Build plan modules" $ liftIO $ buildPlanModules fields hsc_env graph
  pure BuildPlan {graph, json}

-- | Toggle for incremental metadata.
-- When 'True', 'buildPlanForSources' uses the incremental path when a previous state file exists.
-- When 'False', always runs full downsweep.
-- Flip for A/B profiling comparisons.
useIncrementalMetadata :: Bool
useIncrementalMetadata = True

buildPlanForSources ::
  GhcMonad m =>
  Logger ->
  Set BuildPlanField ->
  Maybe OsPath ->
  Maybe FilePath ->
  [FilePath] ->
  m BuildPlan
buildPlanForSources logger fields mbBuildPlan actionMetadata srcs = do
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
        -- Run downsweep without graph cache (so downsweep fully processes imported modules).
        -- On non-FIXED_NODES, old summaries enable timestamp comparison.
        -- On FIXED_NODES, old summaries are empty (fixed nodes have no ModSummary).
        (errs, freshGraph) <- logTimed logger ("Downsweep (" ++ show (length changed) ++ " changed)") $
          withSession \ hsc_env -> liftIO $
            downsweepCompat hsc_env (oldSummaries cachedGraph) Nothing [] True
        let msgs = unionManyMessages errs
        unless (isEmptyMessages msgs) $ throwErrors (fmap GhcDriverMessage msgs)
        -- Merge: fresh nodes (changed modules + their transitive imports from downsweep)
        -- take precedence over cached nodes
        let graph = mergeModuleGraphs freshGraph cachedGraph
        hsc_env <- getSession
        freshJson <- logTimed logger "Build plan modules" $ liftIO $ buildPlanModules fields hsc_env graph
        let json = maybe freshJson (mergeBuildPlanJson freshJson) cachedJson
        pure BuildPlan {graph, json}
