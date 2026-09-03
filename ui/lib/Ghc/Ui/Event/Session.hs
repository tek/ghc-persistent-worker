module Ghc.Ui.Event.Session where

import Brick.Types (EventM)
import Control.Lens ((%%=), (<>=))
import Data.Foldable (for_)
import qualified Data.Map.Strict as Map
import Data.Text qualified as Text
import Ghc.Ui.Data.Log (LogMessage (..))
import Ghc.Ui.Data.Name (Name)
import Ghc.Ui.Data.Project (ProjectUnit (..))
import Ghc.Ui.Data.Session (SessionEvent (..), SessionState (..), Stats (..), Worker (..))
import qualified Ghc.Ui.Data.Tasks as Tasks
import Ghc.Ui.Data.WorkerId (WorkerId)
import Ghc.Ui.Event.Log (logMessage)
import Ghc.Ui.Event.Project qualified as Project
import Ghc.Ui.Event.Tasks qualified as Tasks
import Lens.Micro.Platform (each, filtered, modifying, zoom)
import Types.Instrument qualified as Instr

stripEscSeqs :: String -> String
stripEscSeqs [] = []
stripEscSeqs ('\ESC' : '[' : xs) = stripEscSeqs (drop 1 (dropWhile (/= 'm') xs))
stripEscSeqs (x : xs) = x : stripEscSeqs xs

handleEvent :: SessionEvent -> EventM Name SessionState ()
handleEvent (InstrEvent wid evt) =
  case evt of
    Instr.CompileStart {..} -> do
      zoom #tasks $ Tasks.addTask target wid debuggable requestId
    Instr.CompileEnd {..} -> do
      let content = stripEscSeqs stderr
          (outcome, mark) =
            if exitCode == 0
            then (Tasks.Succeeded result, Project.markBuilt)
            else (Tasks.Failed content, Project.markFailed)
      zoom #tasks $ Tasks.completeTask requestId outcome
      zoom #project $ mark target
    Instr.Stats {..} -> do
      modifying (#workers . each . filtered (\ w -> w.workerId == wid) . #stats) \ st ->
        st {
          memory,
          gc_cpu_ns = gcCpuNs,
          cpu_ns = cpuNs
        }
    Instr.ProjectStructure {..} ->
      zoom #project $ Project.load [ProjectUnit u.name u.modules | u <- units]
    Instr.Halt -> pure ()
    Instr.PhaseStart {phase, requestId} -> zoom #tasks $ Tasks.phaseStart requestId phase
    Instr.PhaseEnd {durationMs, requestId} -> zoom #tasks $ Tasks.phaseEnd requestId durationMs
    Instr.RequestCompleted {..} ->
      zoom #tasks $ Tasks.addSeparator statusMessage
    Instr.LogMessage {..} ->
      modifying #log $
      logMessage LogMessage {
        category = Text.pack category,
        level = Text.pack level,
        message = Text.pack message,
        timestampMs
      }
    Instr.BytecodeSnapshot {..} ->
      zoom #project (Project.updateBytecode entries)

removeWorker :: WorkerId -> EventM Name SessionState ()
removeWorker target = do
  removed <- #workers %%= Map.updateLookupWithKey (\ _ _ -> Nothing) target
  for_ removed \ worker ->
    #finishedWorkerStats <>= worker.stats {memory = mempty}
