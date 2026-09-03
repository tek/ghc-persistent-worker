module Ghc.Ui.Data.ServerHandlers where

import GHC.Generics (Generic)
import Ghc.Ui.Data.ServerApi (ServerApi)
import Ghc.Ui.Data.ServerProcess (ServerConfig)
import Network.GRPC.Client (Connection)
import Types.Instrument (Target)

data ServerHandlers =
  ServerHandlers {
    start :: ServerConfig -> IO (),
    stop :: IO (),
    restart :: IO (),
    clean :: Target -> IO (),
    shutdown :: IO (),
    api :: [Connection] -> ServerApi
  }
  deriving stock (Generic)
