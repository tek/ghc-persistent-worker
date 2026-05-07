-- | CLI configuration types for the standalone GHC server and client.
module GhcServer.Data.Config where

import System.OsPath (OsPath)
import Types.FeatureFlags (FeatureFlags (..))

-- | Configuration for the server, parsed from CLI args.
data ServerConfig =
  ServerConfig {
    -- | Absolute path to the project root directory.
    projectRoot :: OsPath,
    -- | Maximum number of concurrent compilation jobs.
    maxJobs :: Int,
    -- | Print the build log even when steps succeed.
    verbose :: Bool,
    -- | Use Cabal file for project discovery instead of @unit.json@ files.
    cabal :: Bool,
    -- | Runtime feature flags.
    featureFlags :: FeatureFlags
  }
  deriving stock (Show)

-- | Configuration for the client, parsed from CLI args.
data ClientConfig =
  ClientConfig {
    -- | Absolute path to the project root directory.
    projectRoot :: OsPath,
    -- | Raw arguments to send to the server, including schedule targets and flags like @--recompile@/@--rebuild@.
    targets :: [String],
    -- | Whether to wait for the build to complete before returning.
    wait :: Bool
  }
  deriving stock (Show)
