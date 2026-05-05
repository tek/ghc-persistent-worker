{-# LANGUAGE CPP #-}

-- | Incremental build plan computation.
--
-- When Buck's action metadata is available (via environment variable), this module
-- determines which source files changed since the previous run and restricts downsweep
-- to only those files, merging the result with the cached module graph.
module Internal.BuildPlan.Incremental where

import Data.Aeson (eitherDecodeFileStrict', encodeFile)
import Data.Foldable (fold)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import GHC.Driver.Env (HscEnv (..), hscActiveUnitId)
#if !defined(FIXED_NODES)
import GHC.Driver.Errors.Types (GhcMessage (..))
#endif
import GHC.Unit (UnitId)
import GHC.Unit.Home (GenHomeUnit (DefiniteHomeUnit))
import GHC.Unit.Module (ModuleName)
import GHC.Unit.Module.Graph (ModuleGraph, ModuleGraphNode (..), mgModSummaries', mkModuleGraph, mkNodeKey)

#if defined(FIXED_NODES)
import GHC.Data.OsPath (unsafeEncodeUtf)
import GHC.Driver.Config.Finder (initFinderOpts)
import GHC.Driver.Make (ModNodeKeyWithUid (..))
import GHC.Types.SourceFile (HscSource (HsSrcFile))
import GHC.Unit (GenWithIsBoot (..), IsBootInterface (..))
import GHC.Unit.Finder (addHomeModuleToFinder, mkHomeModLocation)
import GHC.Unit.Module.Graph (ModuleNodeInfo (..), NodeKey (..))
import System.FilePath (splitExtension)
#else
import GHC.Driver.Make (ModNodeKeyWithUid (..))
import GHC.Unit (GenWithIsBoot (..), IsBootInterface (..))
import GHC.Unit.Module.Graph (NodeKey (..))
#endif

#if !defined(FIXED_NODES)
import GHC.Driver.Make (summariseFile)
#endif

#if !defined(FIXED_NODES)
import Internal.Error (eitherMessages)
#endif
import System.Directory (doesFileExist)
import System.Environment (lookupEnv)
import System.IO (hPutStrLn, stderr)
import qualified System.OsPath as OsPath
import System.OsPath (OsPath)
import Types.BuildPlan (BuildPlanJson (..), BuildPlanSchema (..), PackageDeps (..))
import Types.CachedDeps (CachedModule (..), CachedPackageDep (..), CachedUnit (..), JsonFs (..))
import Types.Incremental (ActionMetadata, IncrementalState (..), actionMetadataSourceDigests, changedSources)

-- | The environment variable name that Buck uses to communicate the metadata file path.
actionMetadataEnvVar :: String
actionMetadataEnvVar = "ACTION_METADATA"

-- | Derive the incremental state file path from the build plan path.
--
-- The state file is stored as a sibling of the build plan output.
stateFilePath :: OsPath -> FilePath
stateFilePath buildPlanPath =
  case OsPath.decodeUtf buildPlanPath of
    Right fp -> fp ++ ".incremental-state.json"
    Left _ -> ""

-- | Attempt to compute incremental targets.
--
-- If the @ACTION_METADATA@ env var is set and a previous state file exists,
-- compares digests to find changed source files. Returns only those as targets.
--
-- Returns 'Nothing' if incremental mode is not applicable (no env var, no state,
-- non-trivial changes like added/removed files).
--
-- On success, also returns the current metadata for writing the state file after
-- the build plan is computed, and the cached 'BuildPlanJson' from the
-- previous run for unchanged modules.
incrementalTargets ::
  OsPath ->
  [FilePath] ->
  IO (Maybe ([FilePath], ActionMetadata, Maybe BuildPlanJson))
incrementalTargets buildPlan _allSources = do
  lookupEnv actionMetadataEnvVar >>= \case
    Nothing -> pure Nothing
    Just metaPath -> do
      eitherDecodeFileStrict' metaPath >>= \case
        Left _ -> pure Nothing
        Right meta -> do
          let statePath = stateFilePath buildPlan
          doesFileExist statePath >>= \case
            False -> pure Nothing
            True -> do
              eitherDecodeFileStrict' statePath >>= \case
                Left _ -> pure Nothing
                Right prevState ->
                  case changedSources prevState meta of
                    Nothing -> pure Nothing
                    Just changed
                      | null changed -> Just ([], meta, prevState.buildPlanJson) <$ pure ()
                      | otherwise -> pure (Just (changed, meta, prevState.buildPlanJson))

-- | Write the incremental state file after a successful metadata computation.
writeIncrementalState :: OsPath -> ActionMetadata -> BuildPlanJson -> IO ()
writeIncrementalState buildPlan meta json = do
  let statePath = stateFilePath buildPlan
      state = IncrementalState {
        sourceDigests = actionMetadataSourceDigests meta,
        buildPlanJson = Just json
      }
  encodeFile statePath state

-- | Merge the result of an incremental downsweep (targeting only changed modules)
-- with the full cached module graph (containing all modules from the previous run).
--
-- Nodes from the fresh graph take precedence; cached nodes not present in the fresh
-- graph are retained.
mergeModuleGraphs :: ModuleGraph -> ModuleGraph -> ModuleGraph
mergeModuleGraphs freshGraph cachedGraph =
  mkModuleGraph (mgModSummaries' freshGraph ++ retainedCachedNodes)
  where
    freshKeys = Set.fromList (map mkNodeKey (mgModSummaries' freshGraph))
    retainedCachedNodes =
      filter (\ n -> not (mkNodeKey n `Set.member` freshKeys)) (mgModSummaries' cachedGraph)

-- | Merge a freshly computed 'BuildPlanJson' (for changed modules) with a cached one
-- (from the previous run). Fresh entries take precedence for changed modules.
--
-- For map-structured fields, uses 'Map.union' (left-biased).
-- For list-structured fields, combines and deduplicates.
mergeBuildPlanJson :: BuildPlanJson -> BuildPlanJson -> BuildPlanJson
mergeBuildPlanJson fresh cached =
  BuildPlanJson {
    legacy = mergeMaybe Map.union fresh.legacy cached.legacy,
    schema = mergeBuildPlanSchema fresh.schema cached.schema
  }

mergeBuildPlanSchema :: BuildPlanSchema -> BuildPlanSchema -> BuildPlanSchema
mergeBuildPlanSchema fresh cached =
  BuildPlanSchema {
    exposed_modules = mergeList fresh.exposed_modules cached.exposed_modules,
    module_graph = mergeMaybe Map.union fresh.module_graph cached.module_graph,
    package_deps = mergeMaybe mergePackageDeps fresh.package_deps cached.package_deps,
    project_deps = mergeMaybe mergePackageDeps fresh.project_deps cached.project_deps,
    toolchain_deps = mergeMaybe mergePackageDeps fresh.toolchain_deps cached.toolchain_deps,
    th_modules = mergeList fresh.th_modules cached.th_modules,
    cache = mergeMaybe Map.union fresh.cache cached.cache
  }
  where
    mergePackageDeps (PackageDeps a) (PackageDeps b) = PackageDeps (Map.union a b)

mergeMaybe :: (a -> a -> a) -> Maybe a -> Maybe a -> Maybe a
mergeMaybe f (Just a) (Just b) = Just (f a b)
mergeMaybe _ a Nothing = a
mergeMaybe _ Nothing b = b

mergeList :: Eq a => Maybe [a] -> Maybe [a] -> Maybe [a]
mergeList = mergeMaybe unionList
  where
    unionList a b = a ++ filter (\x -> not (elem x a)) b

-- | Load the module graph from the previous build plan JSON file.
--
-- On FIXED_NODES GHC, creates 'ModuleNodeFixed' nodes without parsing source files.
-- Otherwise, creates 'ModuleNodeCompile' nodes via 'summariseFile'.
loadCachedGraph :: HscEnv -> OsPath -> IO (Maybe ModuleGraph)
loadCachedGraph hsc_env buildPlanPath = do
  let filePath = case OsPath.decodeUtf buildPlanPath of
                   Right p -> p
                   Left _ -> ""
  doesFileExist filePath >>= \case
    False -> pure Nothing
    True ->
      eitherDecodeFileStrict' filePath >>= \case
        Left err -> do
          hPutStrLn stderr ("loadCachedGraph: decode error: " ++ err)
          pure Nothing
        Right (cachedUnit :: CachedUnit) -> do
          let entries = Map.toList (fold (cachedUnit.cache <> cachedUnit.build_plan))
          case entries of
            [] -> do
              hPutStrLn stderr "loadCachedGraph: empty cache in build plan"
              pure Nothing
            _ -> do
              let unit = hscActiveUnitId hsc_env
              nodes <- traverse (uncurry (loadCachedGraphNode hsc_env unit)) entries
              pure (Just (mkModuleGraph nodes))

-- | Create a graph node for a cached module entry.
--
-- On FIXED_NODES GHC, creates a 'ModuleNodeFixed' with dependency edges but no 'ModSummary',
-- avoiding source parsing entirely.
-- On other GHCs, falls back to 'summariseFile'.
loadCachedGraphNode :: HscEnv -> UnitId -> JsonFs ModuleName -> CachedModule -> IO ModuleGraphNode

#if defined(FIXED_NODES)

loadCachedGraphNode hsc_env unit (JsonFs modName) CachedModule {source, modules, packages} = do
  _ <- addHomeModuleToFinder hsc_env.hsc_FC (DefiniteHomeUnit unit Nothing) modName location HsSrcFile
  pure $ ModuleNode (homeDeps ++ packageDeps) $
    ModuleNodeFixed (ModNodeKeyWithUid (GWIB modName NotBoot) unit) location
  where
    fopts = initFinderOpts (hsc_dflags hsc_env)
    (basename, extension) = splitExtension source
    location = mkHomeModLocation fopts modName (unsafeEncodeUtf basename) (unsafeEncodeUtf extension) HsSrcFile

    homeDeps =
      [NodeKey_Module (ModNodeKeyWithUid (GWIB depName NotBoot) unit) | JsonFs depName <- modules]

    packageDeps =
      [
        NodeKey_Module (ModNodeKeyWithUid (GWIB depName NotBoot) depUnit)
        | CachedPackageDep {id = JsonFs depUnit, modules = depModules} <- packages
        , JsonFs depName <- depModules
      ]

#else

loadCachedGraphNode hsc_env unit (JsonFs _modName) CachedModule {source} = do
  summResult <- summariseFile hsc_env (DefiniteHomeUnit unit Nothing) mempty source Nothing Nothing
  summary <- eitherMessages GhcDriverMessage summResult
  pure (ModuleNode [] summary)

#endif
