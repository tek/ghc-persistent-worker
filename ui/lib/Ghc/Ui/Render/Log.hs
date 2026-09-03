module Ghc.Ui.Render.Log where

import Brick.Types (ViewportType (Vertical), Widget)
import Brick.Widgets.Core (Padding (Max), padRight, txt, vBox, viewport, withAttr)
import Brick.Widgets.List (listSelectedAttr, listSelectedFocusedAttr)
import Data.Foldable (toList)
import qualified Data.Text as Text
import Data.Text (Text)
import Data.Time (defaultTimeLocale, formatTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Ghc.Ui.Data.Log (LogMessage (..), LogState (..))
import Ghc.Ui.Data.Name (Name (Log))

formatTimestamp :: Integer -> Text
formatTimestamp ms =
  Text.pack $
  formatTime defaultTimeLocale "%H:%M:%S%Q" (posixSecondsToUTCTime (fromIntegral ms / 1000))

formatEntry :: LogMessage -> Text
formatEntry LogMessage {category, level, message, timestampMs} =
  formatTimestamp timestampMs
    <> " ["
    <> level
    <> "] "
    <> category
    <> ": "
    <> message

-- | Renders only the list content; the surrounding frame/title is supplied by the caller
-- ('UI.hs'\'s @L@-key dispatch via 'UI.Utils.popup'), so this must not add its own border.
renderLog :: Name -> LogState -> Widget Name
renderLog current LogState {messages, selected} =
  viewport Log Vertical $
  vBox (zipWith renderRow [0 ..] (toList messages))
  where
    renderRow i e =
      (if i == selected then withAttr selAttr else id) (padRight Max (txt (formatEntry e)))

    -- TODO why does this check the current focus?
    selAttr = if current == Log then listSelectedFocusedAttr else listSelectedAttr
