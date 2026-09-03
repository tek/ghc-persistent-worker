module Ghc.Ui.Render.Tasks where

import Brick (AttrName, Padding (..), padLeft, str, strWrap, txt, vBox, vLimit, withAttr, (<+>))
import Brick.Types (Widget)
import Brick.Widgets.List (renderList)
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Time (UTCTime, defaultTimeLocale, diffUTCTime, formatTime, nominalDiffTimeToSeconds)
import Ghc.Ui.Attr (
  debuggableAttr,
  disabledAttr,
  opLogIndicatorAttr,
  sectionActiveTasksAttr,
  taskFailedAttr,
  taskNameAttr,
  taskPhaseAttr,
  taskResultAttr,
  taskRunningAttr,
  taskSucceededAttr,
  taskTimeAttr,
  )
import Ghc.Ui.Data.Name (Name (Tasks))
import Ghc.Ui.Data.Tasks (Outcome (..), PhaseInfo (..), Task (..), TasksRow (..), TasksState)
import Ghc.Ui.Render.Format (formatPico)
import qualified Ghc.Ui.Render.OpLog as OpLog
import Ghc.Ui.Render.Popup (popup)
import Ghc.Ui.Render.Section (drawSection)
import Ghc.Ui.Render.Target (styledTarget)
import Types.Instrument (renderTarget)

-- | The marker string and attribute used to indicate a task's current state.
--
-- Plain, single-width characters (an ellipsis for "still running", a check mark for success, a ballot X for
-- failure).
stateMarker :: Task -> (String, AttrName)
stateMarker Task {outcome, phase} =
  case (outcome, phase) of
    (Nothing, Just p) -> (p, taskPhaseAttr)
    (Nothing, Nothing) -> ("...", taskRunningAttr)
    (Just (Succeeded _), _) -> ("\10004", taskSucceededAttr) -- \x2714 heavy check mark
    (Just (Failed _), _) -> ("\10008", taskFailedAttr) -- \x2718 heavy ballot X

-- | The task's target name, outcome (if finished), and recorded phases (see 'Task'\'s @phases@ field), in a
-- single fixed-size popup (merging what used to be two separate popups bound to 'p'\/'Enter' -- they largely
-- duplicated each other's purpose, and neither made sense without the other: the outcome view had no way to
-- show timing, and the phase view had no way to show the failure\/result text). The target name is always
-- shown first, unconditionally -- not just in the popup's border label -- so a metadata task with neither an
-- outcome yet nor any recorded phases still shows something rather than an empty body.
renderTaskDetails :: Task -> Widget Name
renderTaskDetails Task {target, phases, outcome} =
  popup 30 (renderTarget target) $
    vBox $
      withAttr taskNameAttr (styledTarget (renderTarget target))
        : outcomeLines
        ++ phaseLines
 where
  outcomeLines = case outcome of
    Just (Failed content) -> [strWrap content]
    Just (Succeeded (Just result)) -> [strWrap ("Result: " ++ result)]
    _ -> []
  phaseLines
    | null phases = []
    | otherwise = str " " : (drawPhase <$> (sortOn ((.order) . snd) (Map.toList phases)))
  drawPhase (p, PhaseInfo {durationMs}) =
    str p <+> str (replicate 2 ' ') <+> withAttr taskTimeAttr (str (show durationMs ++ "ms"))

-- | Header line replacing the border that used to delimit this panel; see 'UI.Types.sectionActiveTasksAttr'.
-- Uses 'UI.Utils.drawSection's permanent placeholder rectangle for visual structure.
renderTasks :: Name -> UTCTime -> TasksState -> Widget Name
renderTasks current now state =
  drawSection sectionActiveTasksAttr (withAttr sectionActiveTasksAttr (str "Tasks")) $
    renderList drawRow (current == Tasks) state
 where
  drawRow _ (Separator msg) =
    withAttr disabledAttr $ txt ("\9472\9472 " <> msg <> " \9472\9472")
  drawRow _ (TaskRow task@Task {target, ..}) =
    let (status, attr) = stateMarker task
        elapsed = nominalDiffTimeToSeconds (max 0 (diffUTCTime (fromMaybe now endTime) startTime))
        progress = case outcome of
          Just (Failed _) -> "Failure"
          _ -> formatPico elapsed
        timestamp = withAttr taskTimeAttr (str (formatTime defaultTimeLocale "%H:%M:%S" startTime ++ " "))
        header =
          (if debuggable then withAttr debuggableAttr else id) $
            -- The timestamp (subdued\/dim, mirroring 'progressLine' below) leads the label; the marker
            -- ('stateMarker') is a plain single-width character, moved to the end of the row instead of
            -- leading it. The target name itself is rendered via 'UI.Utils.styledTarget' for the
            -- module\/metadata syntax highlighting, with 'taskNameAttr' as its default for the unrecognized
            -- (unit-name) part.
            timestamp
              <+> withAttr taskNameAttr (styledTarget (renderTarget target))
              <+> str " "
              <+> withAttr attr (str status)
        -- Status (elapsed time or "Failure") is rendered on its own indented line below the target name,
        -- rather than right-aligned on the same line: right-aligning it made it hard to visually associate
        -- with the target it belongs to, especially once lines wrap or targets vary in length, and there is
        -- no need for rows to stretch to the panel's full width just to right-align one word. This mirrors
        -- how an execute task's result is already shown on its own line below ('drawResult').
        progressLine = padLeft (Pad 2) (withAttr taskTimeAttr (txt progress))
        result = case outcome of
          Just (Succeeded (Just r)) -> Just r
          _ -> Nothing
     in vBox ([header, progressLine] ++ maybe [] (pure . drawResult) result)

  -- A successful execute task's exfiltrated result, rendered on the lines following its row: wrapped to the
  -- available width, truncated to 4 lines, indented by two cells, and left uncolored (unlike the marker/status
  -- above it).
  drawResult r = padLeft (Pad 2) (vLimit 4 (withAttr opLogIndicatorAttr (txt OpLog.indicator) <+> withAttr taskResultAttr (strWrap r)))
