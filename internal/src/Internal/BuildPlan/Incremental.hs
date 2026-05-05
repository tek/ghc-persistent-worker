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
import GHC.Driver.Errors.Types (GhcMessage (..))
import GHC.Driver.Make (summariseFile)
import GHC.Unit (UnitId)
import GHC.Unit.Home (GenHomeUnit (DefiniteHomeUnit))
import GHC.Unit.Module (ModuleName)
import GHC.Unit.Module.Graph (ModuleGraph, ModuleGraphNode (..), mgModSummaries', mkModuleGraph, mkNodeKey)

#if defined(FIXED_NODES)
import GHC.Unit.Module.Graph (ModuleNodeInfo (..))
#endif

import Internal.Error (eitherMessages)
import System.Environment (lookupEnv)
import System.Directory (doesFileExist)
import System.IO (hPutStrLn, stderr)
import System.OsPath (OsPath)
import qualified System.OsPath as OsPath
import Types.CachedDeps (CachedModule (..), CachedUnit (..), JsonFs (..))
import Types.Incremental (
  ActionMetadata,
  IncrementalState (..),
  actionMetadataSourceDigests,
  changedSources,
  )

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
-- the build plan is computed.
incrementalTargets ::
  OsPath ->
  [FilePath] ->
  IO (Maybe ([FilePath], ActionMetadata))
incrementalTargets buildPlan allSources = do
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
                      | null changed -> Just ([], meta) <$ pure ()
                      | otherwise -> pure (Just (changed, meta))

-- | Write the incremental state file after a successful metadata computation.
writeIncrementalState :: OsPath -> ActionMetadata -> IO ()
writeIncrementalState buildPlan meta = do
  let statePath = stateFilePath buildPlan
      state = IncrementalState {sourceDigests = actionMetadataSourceDigests meta}
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

-- | Load the module graph from the previous build plan JSON file.
--
-- Creates 'ModuleNodeCompile' nodes (via 'summariseFile') rather than 'ModuleNodeFixed',
-- because 'downsweepWithCache' uses 'mgModSummaries' which only returns compile nodes.
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
              nodes <- traverse (uncurry (loadCachedModuleCompile hsc_env unit)) entries
              pure (Just (mkModuleGraph nodes))

-- | Load a cached module entry as a 'ModuleNodeCompile' node.
--
-- Unlike 'Internal.Cache.Metadata.loadCachedModule' which creates 'ModuleNodeFixed' on
-- supported GHC versions, this always calls 'summariseFile' to produce a full 'ModSummary'.
-- This is needed because 'downsweepWithCache' passes 'mgModSummaries' (which skips
-- fixed nodes) to downsweep as the old summaries cache.
loadCachedModuleCompile :: HscEnv -> UnitId -> JsonFs ModuleName -> CachedModule -> IO ModuleGraphNode
loadCachedModuleCompile hsc_env unit (JsonFs _modName) CachedModule {source} = do
  summResult <- summariseFile hsc_env (DefiniteHomeUnit unit Nothing) mempty source Nothing Nothing
  summary <- eitherMessages GhcDriverMessage summResult
#if defined(FIXED_NODES)
  pure (ModuleNode [] (ModuleNodeCompile summary))
#else
  pure (ModuleNode [] summary)
#endif
