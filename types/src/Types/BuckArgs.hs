{-# LANGUAGE ApplicativeDo #-}

module Types.BuckArgs where

import Control.Applicative ((<|>))
import Control.Exception (throwIO)
import Control.Monad (guard, join)
import Data.Aeson (FromJSON, eitherDecodeFileStrict')
import Data.Foldable (toList)
import Data.List (dropWhileEnd, intercalate)
import Data.List.NonEmpty (NonEmpty, nonEmpty)
import Data.List.Split (splitOn)
import Data.Map (Map)
import qualified Data.Map.Strict as Map
import Data.Map.Strict ((!?))
import Data.Maybe (fromMaybe, isJust)
import GHC (mkModule, mkModuleName)
import GHC.Paths (libdir)
import GHC.Unit (Definite (..), GenUnit (RealUnit), stringToUnitId)
import Options.Applicative (
  Parser,
  ParserInfo,
  ParserResult (..),
  ReadM,
  defaultPrefs,
  eitherReader,
  execParserPure,
  flag,
  forwardOptions,
  fullDesc,
  help,
  info,
  long,
  many,
  metavar,
  option,
  optional,
  renderFailure,
  short,
  strArgument,
  strOption,
  switch,
  )
import System.FilePath (takeDirectory)
import System.OsPath (encodeFS)
import Types.Args (
  Args (..),
  BuildPlanField (..),
  TargetId (..),
  UnitName (..),
  buildPlanAll,
  buildPlanKey,
  parseBuildPlanKey,
  )
import Types.Compat.GHC914 (sanitizeGhcArgs)
import Types.FeatureFlags (FeatureFlags, defaultFeatureFlags)
import Types.Grpc (CommandEnv (..), RequestArgs (..))
import Types.Target (ModuleTarget (..))

data Mode =
  ModeCompile
  |
  ModeLink
  |
  ModeMetadata
  deriving stock (Eq, Show)

optionMode :: ReadM Mode
optionMode =
  eitherReader \case
    "compile" -> Right ModeCompile
    "link" -> Right ModeLink
    "metadata" -> Right ModeMetadata
    mode -> Left ("Invalid worker mode '" ++ mode ++ "', must be [compile|link|metdata]")

data IsInterpreted =
  Compiled
  |
  Interpreted
  deriving stock (Eq, Show)

-- | All Buck-specific arguments parsed from a gRPC request.
data BuckArgs =
  BuckArgs {
    topdir :: Maybe String,
    abiOut :: Maybe String,
    buck2Dep :: Maybe String,
    buck2PackageDb :: [String],
    buck2PackageDbDep :: Maybe String,
    unit :: Maybe String,
    buildPlan :: Maybe String,
    -- | The build plan fields included in the JSON.
    fields :: Maybe (NonEmpty String),
    moduleName :: Maybe String,
    depModules :: Maybe String,
    depUnits :: Maybe String,
    homeUnit :: Maybe String,
    workerTargetId :: Maybe TargetId,
    pluginDb :: Maybe String,
    env :: Map String String,
    binPath :: [String],
    tempDir :: Maybe String,
    ghcDirFile :: Maybe String,
    ghcDbFile :: Maybe String,
    ghcArgsFile :: Maybe String,
    ghcOptions :: [String],
    mode :: Maybe Mode,
    closeInput :: Maybe String,
    closeOutput :: Maybe String,
    isBinary :: Bool,
    interp :: IsInterpreted
  }
  deriving stock (Eq, Show)

-- | Shorthand for an optional string option with a long name and uppercase metavar.
opt :: String -> String -> Parser (Maybe String)
opt name var = optional (strOption (long name <> metavar var))

parserBinPath :: Parser FilePath
parserBinPath =
  strOption (long "bin-path" <> metavar "PATH" <> help "Add a directory to $PATH")
  <|>
  (takeDirectory <$> strOption (long "bin-exe" <> metavar "EXE" <> help "Add the directory containing EXE to $PATH"))

-- | Parser for all known Buck worker options.
--
-- Unknown flags are collected as positional arguments via 'forwardOptions' on the 'ParserInfo'.
--
-- @-B@, @-c@ and @-M@ are recognized directly as short flags to avoid capturing them as GHC passthrough.
buckArgsParser :: CommandEnv -> Parser BuckArgs
buckArgsParser (CommandEnv baseEnv) = do
  topdir <- optional (strOption (short 'B' <> metavar "PATH"))
  abiOut <- opt "abi-out" "PATH"
  buck2Dep <- opt "buck2-dep" "PATH"
  buck2PackageDb <- many (strOption (long "buck2-package-db" <> metavar "PATH"))
  buck2PackageDbDep <- opt "buck2-packagedb-dep" "PATH"
  depModules <- opt "dep-modules" "FILE"
  depUnits <- opt "dep-units" "FILE"
  homeUnit <- opt "home-unit" "FILE"
  envKeys <- many (strOption (long "extra-env-key" <> metavar "KEY"))
  envValues <- many (strOption (long "extra-env-value" <> metavar "VALUE"))
  workerTargetId <- optional (option (TargetId <$> eitherReader Right) (long "worker-target-id" <> metavar "ID"))
  pluginDb <- opt "plugin-db" "PATH"
  ghcDirFile <- opt "ghc-dir" "FILE"
  unit <- opt "unit" "NAME"
  buildPlan <- opt "build-plan" "FILE"
  rawFields <- opt "fields" "FIELDS"
  moduleName <- opt "module" "MODULE"
  ghcArgsFile <- opt "ghc-args" "FILE"
  ghcDbFile <- opt "extra-pkg-db" "PATH"
  binPath <- many parserBinPath
  workerMode <- optional (option optionMode (long "worker-mode" <> metavar "MODE"))
  modeCompile <- switch (short 'c')
  modeMetadata <- switch (short 'M')
  isBinary <- switch (long "unit-is-binary")
  closeInput <- opt "close-input" "PATH"
  closeOutput <- opt "close-output" "PATH"
  interp <- flag Compiled Interpreted (long "interp")
  ghcOptions <- many (strArgument (metavar "GHC_ARGS"))
  pure BuckArgs {
    fields = nonEmpty . splitOn "," =<< rawFields,
    env = Map.union (Map.fromList (zip envKeys envValues)) baseEnv,
    tempDir = Map.lookup "TMPDIR" baseEnv,
    mode =
      workerMode
      <|> (ModeCompile <$ guard modeCompile)
      <|> (ModeMetadata <$ guard modeMetadata)
      <|> (ModeCompile <$ moduleName),
    ..
  }

buckArgsCli :: CommandEnv -> ParserInfo BuckArgs
buckArgsCli env =
  info (buckArgsParser env) (fullDesc <> forwardOptions)

parseBuckArgsCli :: CommandEnv -> RequestArgs -> Either String BuckArgs
parseBuckArgsCli env (RequestArgs args) =
  case execParserPure defaultPrefs (buckArgsCli env) args of
    Success a -> Right a
    Failure f -> Left (fst (renderFailure f "ghc-worker"))
    CompletionInvoked _ -> Left "completion invoked"

decodeJsonArg ::
  FromJSON a =>
  String ->
  String ->
  IO a
decodeJsonArg desc file =
  eitherDecodeFileStrict' file >>= \case
    Right a -> pure a
    Left err -> throwIO (userError ("Invalid JSON in file for " ++ desc ++ ": " ++ err ++ " (" ++ file ++ ")"))

-- | @CompileHpt@ can either process a source file or pick a previously constructed @ModSummary@ from the module graph.
-- In the latter case, we need both a unit ID and a module name, which is ensured here.
checkModuleTarget ::
  BuckArgs ->
  IO (Maybe ModuleTarget)
checkModuleTarget args =
  case (args.unit, args.moduleName) of
    (Nothing, Just _) ->
      throwIO (userError "Specified --module without --unit")
    (Just unit, Just name) ->
      pure (Just (ModuleTarget (mkModule (RealUnit (Definite (stringToUnitId unit))) (mkModuleName name))))
    _ ->
      pure Nothing

parseField :: String -> IO (NonEmpty BuildPlanField)
parseField = \case
  "all" -> pure buildPlanAll
  key -> maybe (invalid key) (pure . pure) (parseBuildPlanKey key)
  where
    invalid key =
      throwIO (userError ("Invalid value for --fields: " ++ key ++ ". Possible choices: " ++ keys))

    keys = intercalate " | " ("all" : (buildPlanKey <$> toList buildPlanAll))

toGhcArgs :: BuckArgs -> Maybe FeatureFlags -> IO Args
toGhcArgs args featureFlags = do
  cachedDeps <- traverse (decodeJsonArg "--dep-modules") args.depModules
  cachedBuildPlans <- traverse (decodeJsonArg "--dep-units") args.depUnits
  -- Buck specifies @-B@, which can be used to include more packages in the global package DB.
  -- While this is done by @ghcWithPackages@ from nixpkgs, it is likely redundant, but doesn't hurt.
  -- In any case, we default to @libdir@ from @ghc-paths@, which returns the directory in the distribution used by the
  -- GHC that compiled this binary.
  topdir <- (<|> (args.topdir <|> Just libdir)) <$> readPath args.ghcDirFile
  buildPlan <- traverse encodeFS args.buildPlan
  fields <- fmap join <$> traverse (traverse parseField) args.fields
  packageDb <- readPath args.ghcDbFile
  -- When a module name was specified, we don't read any args because we can't use them when picking @ModSummary@ from
  -- the module graph.
  ghcArgs <-
    if isJust args.moduleName
    then pure []
    else maybe args.ghcOptions lines <$> traverse readFile args.ghcArgsFile
  moduleTarget <- checkModuleTarget args
  pure Args {
    topdir,
    workerTargetId = args.workerTargetId,
    binPath = args.binPath,
    tempDir = args.tempDir,
    unit = UnitName . stringToUnitId <$> args.unit,
    buildPlan,
    fields,
    moduleTarget,
    ghcOptions = sanitizeGhcArgs ghcArgs ++ foldMap packageDbArg packageDb ++ foldMap packageDbArg args.buck2PackageDb,
    cachedBuildPlans,
    cachedDeps,
    homeUnit = args.homeUnit,
    isBinary = args.isBinary,
    featureFlags = fromMaybe defaultFeatureFlags featureFlags,
    -- TODO can this be an arg?
    actionMetadata = args.env !? "ACTION_METADATA"
  }
  where
    packageDbArg path = ["-package-db", path]
    readPath = fmap (fmap (dropWhileEnd ('\n' ==))) . traverse readFile

-- | Arguments interpreted by the worker directly that need to be applied again when restoring module graphs from cache.
data CachedBuckArgs =
  CachedBuckArgs {
    cachedBinPath :: [String]
  }
  deriving stock (Eq, Show)

cachedBuckArgsParser :: Parser CachedBuckArgs
cachedBuckArgsParser = do
  cachedBinPath <- many parserBinPath
  pure CachedBuckArgs {..}

cachedBuckArgsCli :: ParserInfo CachedBuckArgs
cachedBuckArgsCli = info cachedBuckArgsParser fullDesc

parseCachedBuckArgsCli :: [String] -> Either String CachedBuckArgs
parseCachedBuckArgsCli args =
  case execParserPure defaultPrefs cachedBuckArgsCli args of
    Success a -> Right a
    Failure f -> Left (fst (renderFailure f "ghc-worker"))
    CompletionInvoked _ -> Left "completion invoked"
