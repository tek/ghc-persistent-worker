module Ghc.Ui.Server.Api where

import BuckWorkerProto ()
import Control.Concurrent.Async.Lifted (async)
import Control.Exception (SomeException, displayException)
import Control.Monad (void)
import Control.Monad.Catch (catch)
import Control.Monad.Reader (MonadReader (..), ReaderT, liftIO, runReaderT)
import Data.Aeson (encode)
import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (for_)
import Data.Text qualified as Text
import GHC.Generics (Generic)
import Ghc.Ui.Data.Main (MainEvent (OpLogMessage))
import Ghc.Ui.Data.ServerApi (ServerApi (..))
import Ghc.Ui.Server.Monad (ServerEnv, ServerM, trySendEvent)
import Network.GRPC.Client (Connection, rpc)
import Network.GRPC.Client.StreamType.IO (nonStreaming)
import Network.GRPC.Common.Protobuf (Protobuf, defMessage, (&), (.~))
import Proto.GhcServer (GhcServer)
import Proto.GhcServer_Fields qualified as Fields
import Types.Instrument (ApiRequest (..), Target, TaskKind (..), TaskTrigger (..))

data ServerApiEnv =
  ServerApiEnv {
    connections :: [Connection],
    server :: ServerEnv
  }
  deriving stock (Generic)

type ServerApiM a = ReaderT ServerApiEnv IO a

liftServer :: ServerM a -> ServerApiM a
liftServer ma = do
  ServerApiEnv {server} <- ask
  liftIO (runReaderT ma server)

-- TODO Is the rpc endpoint really called Send? Then rename to ApiRequest.
--
-- TODO Move this module to @Server.Api@
--
-- TODO SomeException
sendCommand :: ApiRequest -> ServerApiM ()
sendCommand command =
  void $ async do
    catch (void send) \ (err :: SomeException) ->
      liftServer $ trySendEvent (OpLogMessage ("ApiRequest failed: " <> Text.pack (displayException err)))
  where
    send = do
      ServerApiEnv {connections} <- ask
      for_ connections \ connection ->
        liftIO $ nonStreaming connection (rpc @(Protobuf GhcServer "api")) message

    message =
      defMessage
      & Fields.payload
      .~ LBS.toStrict (encode command)

triggerTask :: Target -> TaskKind -> ServerApiM ()
triggerTask target task =
  sendCommand (TriggerTask (TaskTrigger {..}))

-- | Request eviction of a module (or, if empty, an entire unit) from the bytecode cache.
evictBytecode :: Target -> ServerApiM ()
evictBytecode target =
  sendCommand (EvictBytecode target)

serverApi :: ServerEnv -> [Connection] -> ServerApi
serverApi server connections =
  ServerApi {
    triggerTask = \ t t' -> run (triggerTask t t'),
    evictBytecode = run . evictBytecode
  }
  where
    run = flip runReaderT ServerApiEnv {..}
