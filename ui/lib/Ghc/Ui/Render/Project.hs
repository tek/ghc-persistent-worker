module Ghc.Ui.Render.Project where

import Brick.Types (Widget)
import Brick.Widgets.Core (txt, vBox, withAttr, (<+>))
import Brick.Widgets.List (renderList)
import Data.Functor ((<&>))
import Data.Map.Strict qualified as Map
import Data.Maybe (maybeToList)
import Data.Set qualified as Set
import Ghc.Ui.Attr (
  builtMarker,
  evictedAttr,
  failedMarker,
  moduleNameAttr,
  nodeLabelAttr,
  pendingEvictionAttr,
  sectionProjectAttr,
  taskFailedAttr,
  taskSucceededAttr,
  taskTimeAttr,
  )
import Ghc.Ui.Data.Name (Name (..))
import Ghc.Ui.Data.Project (ProjectState (..), Row (..))
import Ghc.Ui.Render.Format (formatBytes)
import Ghc.Ui.Render.Section (drawSection)
import Types.Instrument (HomeModule (..), ModuleName (..), Target (..), TrackedBytecode (..), UnitName (..))
import Types.Text (showText)

unitTreeInner :: Char
unitTreeInner = '\9500'

unitTreeLast :: Char
unitTreeLast = '\9492'

mark :: ProjectState -> Target -> Widget n
mark ProjectState {built, failed} target
  | Set.member target built = withAttr taskSucceededAttr (txt builtMarker)
  | Set.member target failed = withAttr taskFailedAttr (txt failedMarker)
  | otherwise = txt ""

renderModuleRow :: ProjectState -> HomeModule -> Bool -> Bool -> Widget n
renderModuleRow state@ProjectState {bco} key isLast isLastUnit =
  vBox (main : maybeToList bcoSegment)
  where
    main =
      txt (if isLastUnit then " " else "\9474")
      <+>
      txt ("  " <> (if isLast then "\9492\9472 " else "\9500\9472 "))
      <+>
      withAttr moduleNameAttr (txt key.name.text)
      <+>
      mark state TargetModule {key}


    bcoSegment = Map.lookup key bco <&> \ info -> bcoLine info

    bcoLine TrackedBytecode {size, lastAccess, resident, pendingEviction} =
      withAttr (bcoAttr resident pendingEviction) $
        txt (if isLast then "      " else "  \9474   ")
          <+> txt (formatBytes size <> " BCOs")
          <+> txt
            ( "  access #"
                <> showText lastAccess
                <> if pendingEviction then "  (evicting)" else if resident then "" else "  (evicted)"
            )

    bcoAttr resident pending
      | pending = pendingEvictionAttr
      | not resident = evictedAttr
      | otherwise = taskTimeAttr

renderRow :: ProjectState -> Row -> Widget n
renderRow state = \case
  Root -> txt "\9632 <project>"
  Header {unit, expanded, isLast} ->
    withAttr nodeLabelAttr (txt ((if isLast then "\9492\9472 " else "\9500\9472 ") <> (if expanded then "\9662 " else "\9656 ") <> unit.text)) <+> mark state TargetUnit {name = unit}
  ModuleRow {key, isLast, isLastUnit} ->
    renderModuleRow state key isLast isLastUnit

renderProject :: Name -> ProjectState -> Widget Name
renderProject current state@ProjectState{rows} =
  drawSection sectionProjectAttr (withAttr sectionProjectAttr (txt "Project")) $
  renderList (const (renderRow state)) (current == Project) rows
