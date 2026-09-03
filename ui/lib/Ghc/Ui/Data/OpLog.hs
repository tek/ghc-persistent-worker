module Ghc.Ui.Data.OpLog where

import Data.String (IsString)
import Data.Text (Text)
import GHC.Generics (Generic)

-- | A single operational message.
newtype OpMessage =
  OpMessage { message :: Text }
  deriving stock (Eq, Show)
  deriving newtype (IsString)

-- | All operational messages ever recorded, newest first.
data OpLogState =
  OpLogState { messages :: [OpMessage] }
  deriving stock (Eq, Show, Generic)

initialState :: OpLogState
initialState = OpLogState {messages = ["Waiting for first session"]}
