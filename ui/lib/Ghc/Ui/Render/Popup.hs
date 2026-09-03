module Ghc.Ui.Render.Popup where

import Brick (Widget)
import Brick.Widgets.Border (borderWithLabel)
import Brick.Widgets.Center (centerLayer)
import Brick.Widgets.Core (hLimitPercent, txt, vLimitPercent)
import Data.Text (Text)
import Ghc.Ui.Data.Name (Name)

popup :: Int -> Text -> Widget Name -> Widget Name
popup size popupTitle content =
  centerLayer $
  hLimitPercent size $
  vLimitPercent size $
  borderWithLabel (txt $ " " <> popupTitle <> " ") content
