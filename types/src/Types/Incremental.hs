{-# LANGUAGE DeriveAnyClass #-}

-- | Types for Buck2 incremental actions metadata.
--
-- Buck provides a JSON file (via environment variable) containing digests of all action inputs.
-- The worker compares these with stored digests from the previous run to identify changed sources.
module Types.Incremental where

import Data.Aeson (FromJSON (..), ToJSON (..), withObject, (.:))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import GHC.Generics (Generic)

-- | A single input entry in Buck's action metadata file.
data InputDigest =
  InputDigest {
    path :: FilePath,
    digest :: String
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

-- | Buck's action metadata JSON structure.
--
-- Created by Buck before action execution, listing all inputs with their content digests.
data ActionMetadata =
  ActionMetadata {
    version :: Int,
    digests :: [InputDigest]
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

-- | The worker's incremental state file, recording digests from the previous successful run.
--
-- This is written by the worker after each metadata step and read on the next run to determine
-- which sources changed.
newtype IncrementalState =
  IncrementalState {
    sourceDigests :: Map FilePath String
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

-- | Convert action metadata to a source digest map, filtering to Haskell source files.
actionMetadataSourceDigests :: ActionMetadata -> Map FilePath String
actionMetadataSourceDigests meta =
  Map.fromList [(d.path, d.digest) | d <- meta.digests, isHaskellSource d.path]

-- | Check if a path is a Haskell source file.
isHaskellSource :: FilePath -> Bool
isHaskellSource path =
  ".hs" `isSuffixOf` path || ".lhs" `isSuffixOf` path
  where
    isSuffixOf suffix s = drop (length s - length suffix) s == suffix

-- | Determine which source files changed between the previous and current state.
--
-- Returns 'Nothing' if incremental mode is not applicable (non-source inputs changed,
-- sources were added or removed).
-- Returns @'Just' changedPaths@ if only existing source files were modified.
changedSources :: IncrementalState -> ActionMetadata -> Maybe [FilePath]
changedSources prev current
  | nonSourceChanged = Nothing
  | not (null addedSources) = Nothing
  | not (null removedSources) = Nothing
  | otherwise = Just modified
  where
    currentSrcDigests = actionMetadataSourceDigests current
    -- We don't track non-source digests, so we can't detect non-source changes.
    -- Buck handles non-source input invalidation by invalidating the entire action.
    nonSourceChanged = False

    addedSources = Map.difference currentSrcDigests prev.sourceDigests
    removedSources = Map.difference prev.sourceDigests currentSrcDigests

    modified =
      [path | (path, dig) <- Map.toList currentSrcDigests, Map.lookup path prev.sourceDigests /= Just dig]
