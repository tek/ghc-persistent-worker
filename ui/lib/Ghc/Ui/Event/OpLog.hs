module Ghc.Ui.Event.OpLog where

import Control.Monad.IO.Class (liftIO)
import Data.Text (Text)
import Data.Time.Clock.POSIX (getPOSIXTime)
import Ghc.Ui.Data.Log (LogMessage (..))
import Ghc.Ui.Data.Main (currentSession)
import Ghc.Ui.Data.OpLog (OpMessage (..))
import Ghc.Ui.Event.Log (logMessage)
import Ghc.Ui.Monad (MonadUi)
import Lens.Micro.Platform ((%=))

-- | Add a message to the global operation log and the current session's debug log.
logOp ::
  MonadUi m =>
  Text ->
  m ()
logOp message = do
  #opLog . #messages %= (OpMessage message :)
  timestampMs <- liftIO $ round . (* 1000) <$> getPOSIXTime
  currentSession . #log %= logMessage LogMessage {category = "operational", level = "info", message, timestampMs}
