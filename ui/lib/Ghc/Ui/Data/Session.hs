module Ghc.Ui.Data.Session where

import Data.Map qualified as Map
import Data.Map (Map)
import Data.Text (Text)
import Data.Time (UTCTime)
import GHC.Generics (Generic)
import Ghc.Ui.Data.Log qualified as Log
import Ghc.Ui.Data.Log (LogState)
import Ghc.Ui.Data.Project qualified as Project
import Ghc.Ui.Data.Project (ProjectState)
import qualified Ghc.Ui.Data.Tasks as Tasks
import Ghc.Ui.Data.Tasks (TasksState)
import Ghc.Ui.Data.WorkerId (WorkerId)
import Network.GRPC.Client (Connection)
import Types.Instrument qualified as Shared

-- TODO Rename to SessionId
newtype Id =
  Id { text :: Text }
  deriving stock (Eq, Ord, Show)

data Worker =
  Worker {
    workerId :: WorkerId,
    connection :: Connection,
    stats :: Stats
  }
  deriving stock (Generic)

data Stats =
  Stats {
    memory :: Map Text Int, -- in bytes
    gc_cpu_ns :: Int,
    cpu_ns :: Int
  }

instance Semigroup Stats where
  l <> r =
    Stats {
      memory = Map.unionWith (+) l.memory r.memory,
      gc_cpu_ns = l.gc_cpu_ns + r.gc_cpu_ns,
      cpu_ns = l.cpu_ns + r.cpu_ns
    }

instance Monoid Stats where
  mempty =
    Stats {
      memory = [],
      gc_cpu_ns = 0,
      cpu_ns = 0
    }

data SessionState =
  SessionState {
    title :: String,
    workers :: Map WorkerId Worker,
    tasks :: TasksState,
    project :: ProjectState,
    log :: LogState,
    sesStartTime :: UTCTime,
    sesEndTime :: Maybe UTCTime,
    finishedWorkerStats :: Stats
  }
  deriving stock (Generic)

data SessionEvent = InstrEvent WorkerId Shared.Event

initialState :: String -> UTCTime -> SessionState
initialState title startTime =
  SessionState {
    title,
    workers = [],
    tasks = Tasks.initialState,
    project = Project.initialState,
    log = Log.initialState,
    sesStartTime = startTime,
    sesEndTime = Nothing,
    finishedWorkerStats = mempty
  }
