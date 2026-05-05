{-# LANGUAGE QuasiQuotes #-}

-- | Write Buck-style ACTION_METADATA JSON files for testing incremental metadata.
module Test.ActionMetadata where

import Data.Aeson (encodeFile)
import qualified Data.ByteString.Lazy as BSL
import Data.Foldable (traverse_)
import Data.Traversable (for)
import System.Directory.OsPath (createDirectoryIfMissing)
import System.OsPath (OsPath, osp, (</>))
import Test.Data.Project (BuildModule (..), GenUnit (..))
import Test.Path (fp, moduleSourcePath, unitDir)
import Types.Incremental (ActionMetadata (..), InputDigest (..))

-- | Compute a deterministic digest string from file content.
-- Uses a simple hash based on content bytes, matching the format used by Buck (@hash:size@).
fileDigest :: BSL.ByteString -> String
fileDigest content =
  show contentHash ++ ":" ++ show len
  where
    len = BSL.length content
    contentHash = BSL.foldl' (\ h b -> h * 31 + fromIntegral b) (0 :: Int) content

-- | Compute digests for all source files in the project.
computeSourceDigests :: OsPath -> [GenUnit BuildModule] -> IO [InputDigest]
computeSourceDigests sourceDir units =
  concat <$> for units \ unit ->
    for unit.modules \ m -> do
      let path = fp (sourceDir </> moduleSourcePath m.key)
      content <- BSL.readFile path
      pure InputDigest {path, digest = fileDigest content}

-- | Write an ACTION_METADATA JSON file with digests of all source files.
-- Returns the path to the written file.
writeActionMetadata :: OsPath -> OsPath -> [GenUnit BuildModule] -> IO FilePath
writeActionMetadata metadataDir sourceDir units = do
  digests <- computeSourceDigests sourceDir units
  let meta = ActionMetadata {version = 1, digests}
      metaPath = fp (metadataDir </> [osp|action_metadata.json|])
  encodeFile metaPath meta
  pure metaPath

-- | Write an ACTION_METADATA JSON file from a list of source file paths.
writeActionMetadataFromPaths :: FilePath -> [FilePath] -> IO ()
writeActionMetadataFromPaths metaPath paths = do
  digests <- for paths \ path -> do
    content <- BSL.readFile path
    pure InputDigest {path, digest = fileDigest content}
  encodeFile metaPath ActionMetadata {version = 1, digests}

-- | Write per-unit ACTION_METADATA JSON files under the temp dir.
-- Each unit gets its own file at @tempDir/unitN/action_metadata.json@ containing only that unit's sources.
-- This matches the ghc-server setup where each unit's metadata request has its own ACTION_METADATA.
writeUnitActionMetadata :: OsPath -> OsPath -> GenUnit BuildModule -> IO ()
writeUnitActionMetadata tempDir sourceDir unit = do
  let metaDir = tempDir </> unitDir unit.key
      paths = [fp (sourceDir </> moduleSourcePath m.key) | m <- unit.modules]
      metaPath = fp (metaDir </> [osp|action_metadata.json|])
  createDirectoryIfMissing True metaDir
  writeActionMetadataFromPaths metaPath paths

-- | Write per-unit ACTION_METADATA files for all units in the project.
writeAllUnitActionMetadata :: OsPath -> OsPath -> [GenUnit BuildModule] -> IO ()
writeAllUnitActionMetadata tempDir sourceDir units =
  traverse_ (writeUnitActionMetadata tempDir sourceDir) units
