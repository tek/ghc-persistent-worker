module Ghc.Ui.Render.Session where

import Brick (Padding (..), Widget, hBox, hLimitPercent, padBottom, padLeft, padRight, padTop, txt, vBox)
import Brick.Widgets.Border (hBorder)
import Data.Map qualified as Map
import qualified Data.Text as Text
import Data.Time (UTCTime)
import Ghc.Ui.Data.Name (Name)
import Ghc.Ui.Data.OpLog (OpLogState)
import Ghc.Ui.Data.Session (SessionState (..), Stats (..), Worker (..))
import Ghc.Ui.Render.Format (formatBytes, formatPs)
import Ghc.Ui.Render.OpLog (renderOpLog)
import Ghc.Ui.Render.Project (renderProject)
import Ghc.Ui.Render.Tasks (renderTasks)
import Types.Text (showText)

renderStats :: Int -> Stats -> Widget Name
renderStats workerCount Stats{..} =
  vBox
    [ txt $
        " Worker count: "
          <> showText workerCount
          <> " | Memory:"
          <> Text.concat [" " <> k <> "=" <> formatBytes v | (k, v) <- Map.toList memory]
    , txt $
        " CPU Time: "
          <> formatPs (1000 * cpu_ns)
          <> " | GC Time: "
          <> formatPs (1000 * gc_cpu_ns)
    ]

-- | Draws the session panel: the project task tree on the left and the active-tasks list on the right (the
-- bytecode-cache browser that used to occupy a third column has been merged into the project tree, see
-- 'UI.Project'), then the worker stats footer, and finally the operational message log (see 'UI.OpLog'),
-- capped to its 5 most recent entries and flexibly sized (no minimum height, growing up to that cap). The two
-- top panels (project\/active tasks) are delimited by colored headers and a whitespace gutter rather than
-- borders, and are inset on all four sides by a two-cell margin -- 'hBorder' is reserved for the boundaries
-- around the two bottom panels (the stats footer and the operational log, plus the key-legend bar drawn by
-- the caller, see 'UI.drawUI'), which stay flush with the screen edges.
renderSession :: Name -> UTCTime -> OpLogState -> SessionState -> Widget Name
renderSession current now opLog SessionState {project, tasks, workers, finishedWorkerStats} =
  vBox
    [ padLeft (Pad 2) $
        padRight (Pad 2) $
          padTop (Pad 2) $
            padBottom (Pad 2) $
              hBox
                [ hLimitPercent 50 $ padRight (Pad 3) $ renderProject current project
                , renderTasks current now tasks
                ]
    , hBorder
    , renderStats (length workers) (foldMap (.stats) workers <> finishedWorkerStats)
    , hBorder
    , renderOpLog 5 opLog
    ]
