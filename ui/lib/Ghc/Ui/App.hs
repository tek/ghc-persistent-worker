module Ghc.Ui.App where

import Brick (AttrMap)
import Brick.AttrMap (attrMap)
import Brick.Main (App (..), showFirstCursor)
import Brick.Util (on)
import Brick.Widgets.Edit (editFocusedAttr)
import Brick.Widgets.List (listSelectedAttr, listSelectedFocusedAttr)
import Control.Monad.Reader (runReaderT)
import Ghc.Ui.Attr (
  debuggableAttr,
  disabledAttr,
  evictedAttr,
  executeAttr,
  haskellLogoArrowAttr,
  haskellLogoEqualsAttr,
  haskellLogoLambdaAttr,
  metadataAttr,
  moduleNameAttr,
  nodeLabelAttr,
  opLogIndicatorAttr,
  opLogTextAttr,
  pendingEvictionAttr,
  sectionActiveTasksAttr,
  sectionProjectAttr,
  startServerLabelAttr,
  taskFailedAttr,
  taskNameAttr,
  taskPhaseAttr,
  taskResultAttr,
  taskRunningAttr,
  taskSucceededAttr,
  taskTimeAttr,
  )
import Ghc.Ui.Data.Main (MainEvent, MainState)
import Ghc.Ui.Data.Name (Name (..))
import Ghc.Ui.Data.ServerHandlers (ServerHandlers)
import Ghc.Ui.Event.Main (handleUiEvent, initEvent)
import Ghc.Ui.Render.Main (renderMain)
import Graphics.Vty (
  Color (..),
  black,
  blue,
  bold,
  brightBlack,
  brightWhite,
  brightYellow,
  cyan,
  defAttr,
  dim,
  green,
  italic,
  magenta,
  red,
  withBackColor,
  withForeColor,
  withStyle,
  yellow,
  )

attrMapMain :: a -> AttrMap
attrMapMain _ =
  attrMap defAttr [
    (editFocusedAttr, brightWhite `on` blue),
    (listSelectedAttr, brightWhite `on` brightBlack),
    (listSelectedFocusedAttr, withBackColor defAttr black),
    (disabledAttr, style dim),
    (debuggableAttr, bold' defAttr),
    (evictedAttr, italic' (style dim)),
    (pendingEvictionAttr, italic' (style dim)),
    (taskRunningAttr, fg yellow),
    (taskPhaseAttr, italic' (fg yellow)),
    (taskSucceededAttr, fg green),
    (taskFailedAttr, fg red),
    (taskNameAttr, bold' defAttr),
    (taskTimeAttr, style dim),
    (taskResultAttr, fg brightYellow),
    (sectionActiveTasksAttr, bold' (fg yellow)),
    (sectionProjectAttr, bold' (fg cyan)),
    (opLogIndicatorAttr, bold' (fg green)),
    (opLogTextAttr, fg brightWhite),
    (startServerLabelAttr, fg blue),
    (haskellLogoArrowAttr, bold' (fg (RGBColor 0x45 0x3a 0x62))),
    (haskellLogoLambdaAttr, bold' (fg (RGBColor 0x5e 0x50 0x86))),
    (haskellLogoEqualsAttr, fg (RGBColor 0x8f 0x4e 0x8b)),
    (moduleNameAttr, bold' (fg blue)),
    (metadataAttr, bold' (fg magenta)),
    (executeAttr, bold' (fg green)),
    (nodeLabelAttr, bold' defAttr)
  ]
  where
    fg = withForeColor defAttr

    bold' a = withStyle a bold

    italic' a = withStyle a italic

    style = withStyle defAttr

app :: ServerHandlers -> App MainState MainEvent Name
app server =
  App {
    appDraw = renderMain,
    appStartEvent = initEvent,
    appHandleEvent = flip runReaderT server . handleUiEvent,
    appAttrMap = attrMapMain,
    appChooseCursor = showFirstCursor
  }
