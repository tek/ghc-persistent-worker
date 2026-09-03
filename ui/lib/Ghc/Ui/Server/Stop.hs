module Ghc.Ui.Server.Stop where

import Control.Concurrent.Async.Lifted (async, cancel)
import Control.Concurrent.Lifted (readMVar)
import Control.Monad (unless, void)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask)
import Ghc.Ui.Cli (Options (..))
import Ghc.Ui.Data.Main (MainEvent (..))
import Ghc.Ui.Data.ServerProcess (ServerConfig (..), ServerProcess (..), ServerStatus (..), canonicalServerRoot)
import Ghc.Ui.Server.Monad (ServerEnv (..), ServerM, logError, logOp, trySendEvent, withProcess)
import Ghc.Ui.Server.Process (cleanGhcServer, killGhcServer)
import Types.Instrument (Target (..))

-- | Send @Clean@ RPC, log, and notify the UI.
cleanServer :: Target -> ServerM ()
cleanServer target = do
  ServerEnv {process} <- ask
  readMVar process >>= \case
    Just ServerProcess {config = ServerConfig {root}} -> do
      logOp "Cleaning output directories"
      path <- liftIO $ canonicalServerRoot root
      liftIO (cleanGhcServer path target) >>= \case
        Right _ ->
          trySendEvent CleanCompleted {target}
        Left msg ->
          logOp ("Clean failed: " <> msg)
    Nothing ->
      logOp "No tracked ghc-server project root to clean"

-- | The order of cancellations is critical here, otherwise the stdio readers will block 'stopProcess' and the listener
-- will be waiting for a request on an intact connection, apparently in a blocking operation.
--
-- The 'ServerConnected' case must return 'Nothing' to signal that the server cannot be restarted.
stopServer :: ServerM (Maybe ServerConfig)
stopServer =
  withProcess \case
    ServerProcess {config, status = ServerStarted {process, listener, stdoutReader, stderrReader}} -> do
      logOp "Killing ghc-server process"
      cancel stdoutReader
      cancel stderrReader
      killGhcServer process
      cancel listener
      trySendEvent ServerStopped {failedPath = Nothing, stderr = "Server killed successfully"}
      pure (Just ServerProcess {config, status = ServerInactive}, Just config)
    old@ServerProcess {status = ServerConnected} -> do
      logError "kill" "Cannot stop a ghc-server process that wasn't started by this session"
      pure (Just old, Nothing)
    process ->
      pure (Just process, Nothing)

cleanAndStop :: Options -> ServerM ()
cleanAndStop options =
  unless options.remain do
    cleanServer TargetProject
    void stopServer

-- TODO do we need async here?
requestShutdown :: Options -> ServerM ()
requestShutdown options =
  void $ async do
    cleanAndStop options
    trySendEvent ShutdownComplete
