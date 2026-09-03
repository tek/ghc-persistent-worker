module Ghc.Ui.Render.Sessions where

import Brick.Types (Widget)
import Brick.Widgets.Core (str)
import Brick.Widgets.List (renderList)
import Ghc.Ui.Data.Name (Name)
import Ghc.Ui.Data.Session (SessionState (..))
import Ghc.Ui.Data.Sessions (SessionsState)
import Ghc.Ui.Render.Popup (popup)

renderSessions :: SessionsState -> Widget Name
renderSessions ss =
  popup 50 "Select session" $ renderList renderOption True ss
 where
  renderOption isSel (_, SessionState {title, workers}) =
    str $
      concat @[]
        [ if isSel then "> " else "  "
        , title
        , " - "
        , show (length workers)
        , " workers"
        ]
