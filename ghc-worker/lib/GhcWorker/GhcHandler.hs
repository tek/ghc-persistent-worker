module GhcWorker.GhcHandler where

import Common.Grpc (GrpcHandler (..))
import Control.Concurrent (MVar, forkIO, modifyMVar_, threadDelay)
import Control.Concurrent.STM (TVar, atomically, modifyTVar', readTVar, retry, writeTVar)
import Control.Exception (throwIO, try)
import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Data.Coerce (coerce)
import Data.Foldable (for_)
import Data.Functor ((<&>))
import Data.Int (Int32)
import Data.Map qualified as Map
import GHC (DynFlags (..), Ghc, getSession)
import GHC.Debug.Stub (withGhcDebugUnix)
import GHC.Driver.DynFlags (GhcMode (..))
import GHC.Driver.Env (hscUpdateFlags)
import GHC.Driver.Monad (modifySession, reflectGhc, reifyGhc)
import GhcWorker.CompileResult (CompileResult (..), writeCloseOutput, writeResult)
import GhcWorker.Instrumentation (Hooks (..), InstrumentedHandler (..))
import GhcWorker.Orchestration (FeatureInstrument (..))
import Internal.AbiHash (AbiHash (..), showAbiHash)
import Internal.Compile (compileModuleWithDepsInEps)
import Internal.CompileHpt (compileModuleWithDepsInHpt)
import Internal.Debug (debugSocketPath)
import Internal.Log (Log, TraceId, dbg, logDebug, logFlush, newLogWithProgressHook, setLogTarget)
import Internal.Metadata (computeMetadata)
import Internal.Session (Env (..), moduleTarget, withGhc, withGhcForModule, withGhcMhu)
import Internal.State (ModuleArtifacts (..), WorkerState (..), dumpState)
import Prelude hiding (log)
import System.Exit (ExitCode (ExitSuccess))
import System.Posix.Process (exitImmediately)
import Types.Args (Args (..))
import qualified Types.BuckArgs
import Types.BuckArgs (BuckArgs, Mode (..), parseBuckArgs, toGhcArgs)
import Types.GhcHandler (WorkerMode (..))
import Types.Grpc (RequestArgs (..))
import Types.State (TargetSpec (..))
import Types.Args (UnitName(..))
import Types.State (UnitTarget(..))

data LockState = LockStart | LockFreeze Int | LockThaw Int | LockEnd
  deriving stock (Eq, Show)

withLock :: Int -> TVar LockState -> IO a -> IO a
withLock maxLock lock action = do
  _ <- atomically do
    s <- readTVar lock
    case s of
      LockStart -> writeTVar lock (LockFreeze maxLock) >> pure (LockFreeze maxLock)
      LockFreeze _ -> retry
      LockThaw n | n > 0 -> writeTVar lock (LockFreeze (n - 1)) >> pure (LockFreeze (n - 1))
      LockThaw 0 -> writeTVar lock LockEnd >> pure LockEnd
      x -> pure x
  r <- action
  atomically $ modifyTVar' lock \case
    LockFreeze n -> LockThaw n
    x -> x
  pure r

-- | Compile a single module.
-- Depending on @mode@ this will either use the old EPS-based oneshot-style compilation logic or the HPT-based
-- make-style implementation.
compileAndReadAbiHash ::
  GhcMode ->
  Ghc (Maybe ModuleArtifacts) ->
  BuckArgs ->
  Ghc (Maybe CompileResult)
compileAndReadAbiHash ghcMode compile args = do
  modifySession $ hscUpdateFlags \ d -> d {ghcMode}
  compile >>= traverse \ artifacts -> do
    hsc_env <- getSession
    let
      abiHash :: Maybe AbiHash
      abiHash = do
        path <- args.abiOut
        Just AbiHash {path, hash = showAbiHash hsc_env artifacts.iface}
    pure CompileResult {artifacts, abiHash}

-- | Process a worker request based on the operational mode specified in the request arguments, either compiling a
-- single module for 'ModeCompile' (@-c@), or computing and writing the module graph to a JSON file for 'ModeMetadata'
-- (@-M@).
dispatch ::
  TVar LockState ->
  WorkerMode ->
  Hooks ->
  Env ->
  BuckArgs ->
  (TargetSpec -> IO FeatureInstrument) ->
  IO (Int32, Maybe TargetSpec)
dispatch _ workerMode hooks env args targetCallback =
  case args.mode of
    Just ModeCompile -> do
      let _maxLock = 10 :: Int
      (code, result) <- do
        result <- compile
        code <- writeResult args (fst <$> result)
        pure (code, result)
      pure (code, snd <$> result)
    Just ModeMetadata -> do
      for_ env.args.unit \ (UnitName unit) -> do
        let target = TargetUnit (UnitTarget unit)
        setLogTarget env.log target
        liftIO $ hooks.compileStart args (Just target)
      (success, target) <- computeMetadata env
      pure (if success then 0 else 1, target)
    Just ModeClose -> do
      dbg "in dispatch. Mode Close"
      code <- writeCloseOutput args
      _ <- forkIO $ do
        threadDelay 1_000_000
        exitImmediately ExitSuccess
      pure (code, Nothing)
    Just ModeTerminate ->
      pure (0, Nothing)
    Just m -> error ("worker: mode not implemented: " ++ show m)
    Nothing -> error "worker: no mode specified"
  where
    compile = case workerMode of
      WorkerOneshotMode ->
        withGhc env \ target -> do
          let spec = TargetSource target
          liftIO $ hooks.compileStart args (Just spec)
          withTarget (\ _ -> compileAndReadAbiHash OneShot (compileModuleWithDepsInEps spec) args) spec
      WorkerMakeMode -> do
        logDebug env.log "dispatching make mode"
        case moduleTarget env.args of
          Just mtarget -> do
            let target = TargetModule mtarget
            liftIO $ hooks.compileStart args (Just target)
            withGhcForModule target env $
              withTarget (\ _ -> compileAndReadAbiHash CompManager (compileModuleWithDepsInHpt env.log target) args) target
          Nothing ->
            withGhcMhu env \ _ target -> do
              let spec = TargetSource target
              liftIO $ hooks.compileStart args (Just spec)
              withTarget (\ _ -> compileAndReadAbiHash CompManager (compileModuleWithDepsInHpt env.log spec) args) spec

    withTarget f target =
      reifyGhc $ \session -> do
        setLogTarget env.log target
        instrument <- targetCallback target
        let path = debugSocketPath target
        (if instrument.flag then withGhcDebugUnix path else id) $
          reflectGhc (f target) session <&> fmap \ r -> (r, target)

processResult ::
  Hooks ->
  MVar Log ->
  MVar WorkerState ->
  Either IOError (Int32, Maybe TargetSpec) ->
  IO ([String], Int32)
processResult hooks logVar stateVar result = do
  when (exitCode /= 0) do
    dumpState logVar stateVar exception
  output <- logFlush logVar
  hooks.compileFinish (hookPayload output)
  pure (output, exitCode)
  where
    hookPayload output =
      if exitCode == 0
      then Just (target, output, exitCode)
      else Nothing

    ((exitCode, target), exception) = case result of
      Right out -> (out, Nothing)
      Left err -> ((1, Nothing), Just ("Exception: " ++ show err))

-- | Default implementation of an 'InstrumentedHandler' using our custom persistent worker GHC mode, either using HPT or
-- EPS for local dependency lookup.
--
-- Parses the request args from Buck, creates a new 'Log' and 'Env', and passes all of that to 'dispatch'.
-- Afterwards, extracts the log messages that GHC wrote to 'Log' and calls the instrumentation hook 'compileFinish',
-- providing the log and exit code.
--
-- If an exception was thrown, the hook is called without data.
ghcHandler ::
  -- | first req lock hack
  TVar LockState ->
  MVar WorkerState ->
  WorkerMode ->
  FeatureInstrument ->
  Maybe TraceId ->
  Maybe Double ->
  InstrumentedHandler
ghcHandler lock state workerMode instrument traceId debugDelay =
  InstrumentedHandler \ hooks -> GrpcHandler \ commandEnv argv -> do
    log <- newLogWithProgressHook hooks.progress debugDelay traceId
    result <- try do
      buckArgs <- either parseError pure (parseBuckArgs commandEnv argv)
      args <- toGhcArgs buckArgs
      logDebug log (unlines (coerce argv))
      let env = Env {log, state, args}
      dispatch lock workerMode hooks env buckArgs $ \ target -> do
        when instrument.flag $
          modifyMVar_ state \ st ->
            pure $ st {targetArgs = Map.insert target (commandEnv, argv) st.targetArgs}
        pure instrument
    processResult hooks log state result
  where
    parseError msg =
      throwIO (userError ("Parsing Buck args failed: " ++ msg))
