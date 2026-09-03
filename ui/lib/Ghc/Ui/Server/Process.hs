-- | Support for starting a @ghc-server@ instance on demand from the instrument UI (the capital-@S@ key binding, and
-- the @K@\/@R@ lifecycle keys). This module only exposes the low-level primitives (socket probing, process
-- spawning\/killing, cache cleaning); the orchestration -- checking for an existing server, spawning one, polling
-- for it to come up, and waiting for it to terminate -- lives in @Main@, since it requires background threads and
-- app-state bookkeeping that this module has no business owning.
module Ghc.Ui.Server.Process where

import BuckWorkerProto ()
import Control.Concurrent.Async.Lifted (race_)
import Control.Concurrent.Lifted (threadDelay)
import Control.Exception (SomeException, bracket, catch, displayException, try)
import Control.Monad.IO.Class (MonadIO (..))
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Either.Extra (maybeToEither)
import Data.Foldable (traverse_)
import Data.Functor ((<&>))
import Data.Text qualified as Text
import Data.Text (Text)
import Ghc.Ui.Server.Monad (ServerM, logOp)
import Lens.Micro ((&), (.~))
import Network.GRPC.Client (Server (ServerUnix), rpc, withConnection)
import Network.GRPC.Client.StreamType.IO (nonStreaming)
import Network.GRPC.Common (def)
import Network.GRPC.Common.Protobuf (Protobuf, defMessage)
import Network.Socket (Family (AF_UNIX), SockAddr (SockAddrUnix), SocketType (Stream), close, connect, socket)
import Proto.GhcServer (GhcServer)
import Proto.GhcServer_Fields qualified as Fields
import System.Directory (findExecutable)
import System.IO (Handle)
import System.OsPath (OsPath, osp, (</>))
import System.OsPath.Extra (fromOsPath, toOsPath)
import System.Posix (sigKILL, signalProcess)
import System.Process.Typed (
  Process,
  createPipe,
  getPid,
  proc,
  setCreateGroup,
  setStderr,
  setStdout,
  startProcess,
  stopProcess,
  )
import Types.Instrument qualified as Instrument
import Types.Instrument (Target)

-- | Check whether something is listening on the given Unix socket, by attempting an actual @connect(2)@.
--
-- __Note__: this cannot use a lazy gRPC client (e.g. 'Network.GRPC.Client.withConnection') as a substitute, because
-- grapesy's connections are established asynchronously on first use, not by 'openConnection' itself — so a
-- "successful" 'withConnection' says nothing about whether a listener actually exists at the given path.
--
-- TODO Verify that we can't just rely on @serverStreaming@ succeeding instead.
--
-- TODO SomeException
isServerUp ::
  MonadIO m =>
  OsPath ->
  m Bool
isServerUp sock =
  liftIO $ catch tryConnect \ (_ :: SomeException) -> pure False
  where
    tryConnect =
      bracket (socket AF_UNIX Stream 0) close \ s ->
        True <$ connect s (SockAddrUnix (fromOsPath sock))

-- | The default gRPC socket path for a given project root, i.e. @PROJECT_ROOT/socket/server.sock@. Shared with
-- @ghc-server@'s own 'GhcServer.Path.socketPath' -- kept as a literal here (rather than importing that module)
-- since @ghc-ui@ only depends on the @buck-worker-proto@ library, not @ghc-server@'s own library component.
defaultSocketPath :: OsPath -> OsPath
defaultSocketPath root = root </> [osp|socket/server.sock|]

resolveServerExe :: Maybe OsPath -> IO (Either Text OsPath)
resolveServerExe = \case
  Just exe -> pure (Right exe)
  Nothing -> do
    result <- findExecutable "ghc-server"
    pure (toOsPath <$> maybeToEither notFound result)
  where
    notFound = "ghc-server executable not found. Pass --server-exe or ensure it's on PATH"

spawnGhcServer :: OsPath -> OsPath -> [Text] -> IO (Process () Handle Handle)
spawnGhcServer exe root extraArgs =
  startProcess $
  setStdout createPipe $
  setStderr createPipe $
  setCreateGroup True $
  proc (fromOsPath exe) (fromOsPath root : "--enable" : "instrument" : fmap Text.unpack extraArgs)

-- | 'stopProcess' sends TERM, and send KILL if that doesn't manage to terminate the process within two seconds.
killGhcServer ::
  Process () Handle Handle ->
  ServerM ()
killGhcServer process = do
  race_ wait (stopProcess process)
  where
    wait = do
      threadDelay 200_000
      logOp "Server is busy, waiting for 5 seconds..."
      threadDelay 5_000_000
      logOp "Sending signal KILL to the server process"
      liftIO $ traverse_ (signalProcess sigKILL) =<< getPid process

-- | Send a 'Clean' command through the unified 'Api' RPC (@ghc-server.proto@'s @GhcServer@ service no longer has
-- a dedicated @Clean@ RPC -- it was folded into 'Types.Instrument.Command' alongside 'TriggerTask'\/'EvictBytecode',
-- see 'GhcServer.Grpc.runCommand'). JSON-encodes a 'Clean' 'Command' into the request 'Json'\'s @payload@ field,
-- decodes the response 'Json'\'s @payload@ back into a 'Response', and maps 'CleanResult' onto the previous
-- @Either Text Text@ shape expected by 'Ghc.Ui.Server.Stop.cleanServer'.
cleanGhcServer :: OsPath -> Target -> IO (Either Text Text)
cleanGhcServer root target = do
  try @SomeException rpcCall <&> \case
    Left e -> Left (Text.pack (displayException e))
    Right (Left err) -> Left ("Failed to decode response: " <> Text.pack err)
    Right (Right Instrument.CleanResult {success, message}) ->
      (if success then Right else Left) message
    Right (Right resp) -> Left ("Unexpected response to Clean command: " <> Text.pack (show resp))
  where
    rpcCall =
      withConnection def (ServerUnix (fromOsPath sock)) \ connection -> do
        resp <-
          nonStreaming connection (rpc @(Protobuf GhcServer "api")) $
            defMessage & Fields.payload .~ LBS.toStrict (Aeson.encode (Instrument.Clean target))
        pure (Aeson.eitherDecodeStrict resp.payload)

    sock = root </> [osp|socket/server.sock|]
