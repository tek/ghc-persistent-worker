-- | Pop-up window (triggered by the capital-@L@ key) displaying the log messages captured from the connected
-- @ghc-server@'s 'Types.Log.Logger' (see @GhcServer.Log.instrumentLogger@). Entries are tagged with the
-- unit/module target that was active when a message was emitted and a millisecond timestamp, and are always
-- displayed sorted by time.
--
-- Filtering by unit/module is supported by 'visibleEntries', but there is no key binding wiring a 'Filter' value
-- other than 'noFilter' yet -- this is deliberately dormant infrastructure for a later UI feature.
--
-- Rendering deliberately avoids Brick.Widgets.List: a log entry's 'message' can contain literal newlines (e.g.
-- multi-line diagnostics forwarded verbatim from the server), so messages don't have a uniform height, but
-- 'Brick.Widgets.List.GenericList' assumes every item occupies exactly 'Brick.Widgets.List.listItemHeight' rows,
-- and a taller entry desyncs its row-offset arithmetic and its selection-anchored auto-scroll, clipping whatever
-- part of the entry falls past the assumed height with no way to scroll further to reach it. Instead, the whole
-- log is rendered as one 'vBox' inside a plain 'viewport', whose scroll position Brick tracks independently of
-- the selected entry: 'j'/'k' (and the arrow keys) move the selection and, only when necessary, nudge the
-- viewport just enough to bring the newly selected entry back on screen; 'd'/'u' scroll the viewport by a single
-- line without touching the selection at all.
module Ghc.Ui.Event.Log where

import Brick.Main (lookupViewport, setTop, vScrollBy, viewportScroll)
import Brick.Types (EventM, vpSize, vpTop)
import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.State.Class (get, modify)
import Data.Foldable (for_, toList)
import Data.List (sortOn)
import Data.Sequence qualified as Seq
import Data.Sequence (Seq, (<|), (|>))
import Data.Text qualified as Text
import Data.Text (Text)
import Data.Time.Clock.POSIX (getPOSIXTime)
import Ghc.Ui.Data.Log (LogMessage (..), LogState (..))
import Ghc.Ui.Data.Main (currentSession)
import Ghc.Ui.Data.Name (Name (Log))
import Ghc.Ui.Monad (MonadUi)
import Ghc.Ui.Render.Log (formatEntry)
import Graphics.Vty (Event (..), Key (..))
import Lens.Micro.Platform ((%=), (^.))

-- | Split a target string (@unitName@, @unitName:metadata@, @unitName:moduleName@, or
-- @unitName:moduleName:execute@) into its unit and optional module parts.
targetParts :: Text -> (Text, Maybe Text)
targetParts t = case Text.splitOn (Text.pack ":") t of
  (u : m : _) | m /= Text.pack "metadata" -> (u, Just m)
  (u : _) -> (u, Nothing)
  [] -> (t, Nothing)

-- | Entries matching the filter, sorted by timestamp (oldest first).
--
-- TODO handle on insert
visibleEntries :: [LogMessage] -> [LogMessage]
visibleEntries = sortOn (.timestampMs)

clampSelection :: Seq LogMessage -> Int -> Int
clampSelection es sel
  | null es = 0
  | otherwise = max 0 (min (length es - 1) sel)

-- | Rebuilds 'entries' from 'rawEntries'/'filterBy' and clamps 'selected' to the new bounds. Since new messages
-- are appended at the end (they arrive with increasing timestamps and 'visibleEntries' sorts ascending),
-- 'selected' keeps pointing at the same logical entry across refreshes instead of resetting to the oldest one.
refresh :: LogState -> LogState
refresh s =
  s {
    messages,
    selected = clampSelection messages s.selected
  }
  where
    messages = Seq.fromList (sortOn (.timestampMs) (toList s.messages))

-- | Record a newly received log entry.
logMessage :: LogMessage -> LogState -> LogState
logMessage message s = refresh s {messages = message <| s.messages}

-- | Number of physical rows an entry renders as (at least 1): the number of lines its formatted text is split
-- into by embedded newlines. Entries are never wrapped on width, only split on literal @'\\n'@s.
entryLineCount :: LogMessage -> Int
entryLineCount = length . Text.lines . formatEntry

-- | The inclusive, 0-based (startLine, endLine) row range each entry occupies in the rendered 'vBox', in order.
entryRanges :: Seq LogMessage -> Seq (Int, Int)
entryRanges = snd . foldl' step (0, Seq.empty) . toList
  where
    step (start, acc) e =
      let h = entryLineCount e
       in (start + h, acc |> (start, start + h - 1))

-- | Move the selection by 'delta' messages (negative moves up), clamping at the ends, then scroll the viewport
-- just enough to bring the newly selected entry back into view if it isn't already.
moveSelection :: Int -> EventM Name LogState ()
moveSelection delta = do
  s <- get
  let newSelected = clampSelection s.messages (s.selected + delta)
  modify \st -> st {selected = newSelected}
  scrollIntoView newSelected

-- | Adjusts the 'LogViewer' viewport's scroll offset, if necessary, so that the entry at 'idx' is fully visible.
-- Does nothing if the viewport hasn't been rendered yet or the index is out of range.
scrollIntoView :: Int -> EventM Name LogState ()
scrollIntoView idx = do
  s <- get
  mvp <- lookupViewport Log
  for_ ((,) <$> Seq.lookup idx (entryRanges s.messages) <*> mvp) $ \((startLine, endLine), vp) -> do
    let top = vp ^. vpTop
        height = snd (vp ^. vpSize)
        itemHeight = endLine - startLine + 1
    if startLine < top
      then setTop (viewportScroll Log) startLine
      else
        if endLine > top + height - 1
          then
            setTop
              (viewportScroll Log)
              -- If the entry itself is taller than the viewport, prefer showing its start (the user can
              -- keep reading the rest with 'd') over showing its tail with the start already scrolled past.
              (if itemHeight <= height then max 0 (endLine - height + 1) else startLine)
          else pure ()

-- | Scroll the viewport by 'delta' lines (independent of the selection), then, if the previously selected entry
-- has scrolled out of view, move the selection to the first entry now visible -- so the selection never points
-- at an off-screen entry after a 'd'\/'u' scroll.
scrollAndClampSelection :: Int -> EventM Name LogState ()
scrollAndClampSelection delta = do
  vScrollBy (viewportScroll Log) delta
  s <- get
  mvp <- lookupViewport Log
  for_ mvp \ vp -> do
    let top = vp ^. vpTop
        height = snd (vp ^. vpSize)
        ranges = entryRanges s.messages
        inView (startLine, endLine) = endLine >= top && startLine <= top + height - 1
        stillVisible = maybe False inView (Seq.lookup s.selected ranges)
    unless stillVisible $
      for_ (Seq.findIndexL inView ranges) \ i -> modify \ st -> st {selected = i}

-- | Handles input while the log viewer is focused: 'j'/'k' (and the arrow keys) move the selection, 'd'/'u'
-- scroll the viewport by one line independent of the selection (see 'scrollAndClampSelection' for what happens
-- when this scrolls the selected entry out of view). Any other key is ignored here; Esc/@q@/@L@ (closing the
-- popup) are handled by the caller before reaching this function.
handleEvent :: Event -> EventM Name LogState ()
handleEvent = \case
  EvKey (KChar 'j') [] -> moveSelection 1
  EvKey KDown [] -> moveSelection 1
  EvKey (KChar 'k') [] -> moveSelection (-1)
  EvKey KUp [] -> moveSelection (-1)
  EvKey (KChar 'd') [] -> scrollAndClampSelection 10
  EvKey (KChar 'u') [] -> scrollAndClampSelection (-10)
  _ -> pure ()

-- | Append an entry to the current session's server-log viewer, tagged as coming from the ui (as opposed to
-- messages pushed by the server via 'Instr.LogMessage'). Used to replace ad hoc @hPutStrLn stderr@ debug prints,
-- which corrupt a running Brick app's terminal rendering.
--
-- TODO is posix time necessary?
addMessage ::
  MonadUi m =>
  Text ->
  Text ->
  m ()
addMessage level message = do
  ms <- liftIO $ round . (* 1000) <$> getPOSIXTime
  currentSession . #log %= logMessage LogMessage {category = "ui", level, message, timestampMs = ms}
