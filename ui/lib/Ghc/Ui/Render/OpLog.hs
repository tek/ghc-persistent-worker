-- | Operational message log: a small set of high-visibility, prominently displayed status\/lifecycle lines (e.g.
-- @ghc-server@ startup, shutdown steps), distinct from the fine-grained per-target entries in 'UI.LogViewer'. This
-- generalizes the earlier single-label placeholder text (\"Waiting for first session\") into an append-only list.
--
-- Stored at the top level of 'UI.State' rather than per-session ('UI.Session.State'), since operational events can
-- occur outside any session's lifetime (server startup before a session connects, shutdown after the session list
-- has been cleared).
module Ghc.Ui.Render.OpLog where

import Brick.Types (Widget)
import Brick.Widgets.Core (hBox, strWrap, txt, vBox, vLimit, withAttr)
import Data.Coerce (coerce)
import qualified Data.Text as Text
import Data.Text (Text)
import Ghc.Ui.Attr (opLogIndicatorAttr, opLogTextAttr)
import Ghc.Ui.Data.OpLog (OpLogState (..), OpMessage (..))

-- | Prefix rendered ahead of the latest message line.
indicator :: Text
indicator = "🮥 "

-- | Renders the @n@ most recent messages, newest at the bottom prefixed by 'indicator' (green) with the
-- message text in bright white. Left-aligned and unbordered; callers are responsible for placement (centering,
-- width limits, panes). Each message is word-wrapped to the available width and clamped to at most three
-- widget lines, so a single very long message cannot push older entries off screen.
renderOpLog :: Int -> OpLogState -> Widget n
renderOpLog n =
  vBox . reverse . drawEntries . take n . (.messages)
 where
   drawEntries = \case
      [] -> []
      h : t -> drawLatest h : (txt . coerce <$> t)

   drawLatest (OpMessage msg) =
     hBox [
       withAttr opLogIndicatorAttr (txt indicator),
       drawMessage (OpMessage msg)
     ]

   drawMessage (OpMessage msg) =
     vLimit 3 (withAttr opLogTextAttr (strWrap (Text.unpack msg)))
