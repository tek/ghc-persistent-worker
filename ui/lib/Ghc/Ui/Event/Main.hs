module Ghc.Ui.Event.Main where

import Brick (BrickEvent (..), halt, suspendAndResume')
import Brick.Forms (formState)
import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans (lift)
import Data.Foldable (for_, toList, traverse_)
import Data.Maybe (fromMaybe)
import Data.Monoid (First (..))
import qualified Data.Text as Text
import Data.Text (Text)
import qualified Data.Text.IO as Text
import Ghc.Ui.Data.Log (LogState (..))
import qualified Ghc.Ui.Data.Main as Main
import Ghc.Ui.Data.Main (MainEvent (..), currentSession)
import qualified Ghc.Ui.Data.Name as Name
import Ghc.Ui.Data.Name (Name (..))
import Ghc.Ui.Data.Project (ProjectState)
import Ghc.Ui.Data.ServerApi (ServerApi (..))
import Ghc.Ui.Data.ServerHandlers (ServerHandlers (..))
import Ghc.Ui.Data.ServerProcess (ServerConfig, describeServerRoot)
import qualified Ghc.Ui.Data.Sessions as Sessions
import Ghc.Ui.Data.WorkerId (WorkerId (..))
import qualified Ghc.Ui.Event.Log as Log
import Ghc.Ui.Event.OpLog (logOp)
import Ghc.Ui.Event.Popup (focus, handleForm, handleListEventOf, listKeyEvent, openPopup, popupKeyEvent, staticDialog)
import qualified Ghc.Ui.Event.Project as Project
import qualified Ghc.Ui.Event.Sessions as Sessions
import Ghc.Ui.Event.Tasks qualified as Tasks
import Ghc.Ui.GhcDebug (debug)
import Ghc.Ui.Monad (MainM, MonadUi, UiM, server, withApi)
import qualified Ghc.Ui.Render.Log as Log
import Graphics.Vty (Event (..), Key (..))
import Internal.Debug (debugSocketPathTarget)
import Lens.Micro.Platform (preuse, use, zoom, (.=))
import System.OsPath (OsPath)
import System.OsPath.Extra (toOsPath)
import qualified Types.Instrument as TaskKind
import Types.Instrument (Target (..), TaskKind, renderTarget)
import Types.Text (showText)

withTarget ::
  (WorkerId -> Target -> MainM ()) ->
  MainM ()
withTarget handler = do
  current <- use #currentFocus
  First mtarget <- case current of
    Tasks -> zoom (currentSession . #tasks) (First <$> Tasks.getSelectedTarget)
    _ -> pure (First Nothing)
  case mtarget of
    Nothing -> logOp "No task selected"
    Just (wid, target) -> handler wid target

withProjectTargets ::
  MonadUi m =>
  (ProjectState -> Maybe a) ->
  (a -> m ()) ->
  m ()
withProjectTargets select handle = do
  mtree <- preuse (currentSession . #project)
  case select =<< mtree of
    Just targets ->
      handle targets
    _ ->
      logOp "No project row selected"

inProject :: UiM ProjectState () -> MainM ()
inProject = zoom (currentSession . #project)

-- | Write every log entry captured so far for the current session (server-forwarded scheduler\/build
-- diagnostics as well as client\/operational entries, see 'UI.Log.Entry') to a hardcoded @ui.log@ file in
-- the current working directory, oldest first. Triggered by the 'W' key, primarily to capture the full
-- scheduler decision trace (@GhcServer.Handler@ forwards every 'GhcServer.Scheduler.SchedulerDecision' as a
-- @\"scheduler\"@-tagged debug entry) for offline bug reports.
writeLogToFile ::
  MonadUi m =>
  m ()
writeLogToFile = do
  mentries <- preuse (currentSession . #log)
  case mentries of
    Nothing -> logOp "W key: no session connected, nothing to write"
    Just lv -> do
      let rendered = Log.formatEntry <$> Log.visibleEntries (toList lv.messages)
      liftIO $ Text.writeFile "ui.log" (Text.unlines rendered)
      logOp ("Wrote " <> Text.pack (show (length rendered)) <> " log entries to ui.log")

requestQuit :: MainM ()
requestQuit = do
  #sessions .= Sessions.initialState
  logOp "Shutting down"
  server.shutdown

nonEmptyPath :: Text -> Maybe OsPath
nonEmptyPath = \case
  "" -> Nothing
  path -> Just (toOsPath (Text.unpack path))

triggerTask ::
  Foldable t =>
  (ProjectState -> Maybe (t Target)) ->
  TaskKind ->
  MainM ()
triggerTask select kind =
  withProjectTargets select $ traverse_ \ target -> do
    Log.addMessage "debug" ("Trigger " <> showText kind <> ": " <> showText target)
    withApi \ api -> api.triggerTask target kind

startServer :: ServerConfig -> MainM ()
startServer input = do
  server.start input
  focus Project

evictBytecode ::
  Target ->
  MainM ()
evictBytecode target = do
  withApi \ api -> api.evictBytecode target
  inProject (Project.evictedBco target)

logMessage ::
  MonadUi m =>
  Text ->
  Text ->
  Text ->
  m ()
logMessage level stream line =
  Log.addMessage level (stream <> ": " <> line)

handleMainEvent ::
  MainEvent ->
  MainM ()
handleMainEvent = \case
  SetTime t ->
    #currentTime .= t

  Main.Sessions evt -> do
    lift $ zoom #sessions (Sessions.handleEvent evt)
    -- The first session to appear is auto-selected (see 'Sessions.handleEvent's 'StartSession' case)
    -- without the user dismissing any modal, so the idle screen's initial focus (the start-server form) has to be
    -- moved off explicitly here once that happens, mirroring what the other modals' "hide" logic does on Esc\/Enter.
    current <- use #currentFocus
    when (current == StartServer) $ #currentFocus .= Project

  ProcessLog level stream line ->
    logMessage level stream line

  ServerStopped {..} ->
    for_ failedPath \ path ->
      logOp ("Failed to start ghc-server in " <> describeServerRoot path <> ": " <> stderr)

  OpLogMessage message -> logOp message

  CleanCompleted target -> do
    inProject (Project.clearMarks target)
    lift $ zoom (currentSession . #tasks) (Tasks.addSeparator ("Cleaned " <> renderTarget target))

  ShutdownComplete -> do
    logOp "Shutdown complete"
    lift halt

handleGlobalKey ::
  Name ->
  Event ->
  Key ->
  MainM ()
handleGlobalKey current event = \case
  KEsc -> requestQuit

  KChar 'q' -> requestQuit

  KChar 's' ->
    openPopup Name.Sessions

  KChar 'S' ->
    openPopup StartServer

  KChar 'K' -> do
    Log.addMessage "info" "Killing ghc-server"
    server.stop

  KChar 'R' -> do
    Log.addMessage "info" "Restarting ghc-server"
    server.restart

  KChar 'C' -> do
    mtree <- preuse (currentSession . #project)
    let target = fromMaybe TargetProject (mtree >>= Project.selectedCleanTarget)
    server.clean target

  KChar 'L' ->
    focus Log

  KChar 'W' -> writeLogToFile

  KChar 'd' ->
    withTarget \ _ target -> do
      result <- lift $ suspendAndResume' $ debug (debugSocketPathTarget target)
      either (\ err -> logOp ("ghc-debug: " <> Text.pack err)) pure result

  KChar '\t' ->
    focus case current of
      Tasks -> Project
      Project -> Tasks
      _ -> current

  _ -> case current of
    Tasks -> lift $ handleListEventOf (currentSession . #tasks) event
    Project -> lift $ handleListEventOf (currentSession . #project . #rows) event
    _ -> pure ()

-- | Keys that operate on the project view specifically: build\/execute triggers (which read their targets from
-- the currently selected project-tree row) and eviction\/expand-toggle, which are also meaningful there. Any
-- other key falls through to 'handleGlobalKey'.
projectKey ::
  Event ->
  Key ->
  MainM ()
projectKey event = \case
  KChar 'm' ->
    triggerTask Project.selectedMetadataTargets TaskKind.Metadata

  KChar 'r' ->
    triggerTask Project.selectedCompileTargets (TaskKind.Build True)

  KChar 'b' ->
    triggerTask Project.selectedCompileTargets (TaskKind.Build False)

  KChar 'x' ->
    triggerTask (fmap Just . Project.selectedExecuteTarget) TaskKind.Execute

  KChar 'e' ->
    withProjectTargets Project.selectedEvictTarget \ target ->
      evictBytecode target

  KEnter ->
    inProject Project.toggleExpand

  key -> handleGlobalKey Project event key

-- | Keys that operate on the tasks view specifically: opening task details (either inline, via 'p', or as a
-- popup, via Enter) and eviction, which targets the bytecode owning the currently selected task's target
-- instead of a project-tree row. Any other key falls through to 'handleGlobalKey'.
--
-- TODO wtf is this inline details thing
tasksKey :: Event -> Key -> MainM ()
tasksKey event = \case
  KChar 'p' ->
    withTarget \ _ _ -> #currentFocus .= TaskDetails

  KEnter ->
    -- This ensures the cursor is not on a separator
    -- TODO improve
    withTarget \ _ _ -> openPopup TaskDetails

  key -> handleGlobalKey Tasks event key

keyEvent ::
  (Event -> Key -> MainM ()) ->
  Event ->
  MainM ()
keyEvent handle = \case
  event@(EvKey key []) -> handle event key
  _ -> pure ()

vtyEvent :: Name -> Event -> MainM ()
vtyEvent = \case
  Name.Sessions ->
    lift . listKeyEvent #sessions True

  StartServer -> do
    popupKeyEvent True (lift . handleForm #serverForm) do
      input <- formState <$> use #serverForm
      startServer input

  TaskDetails ->
    staticDialog

  Log ->
    lift . popupKeyEvent False (zoom (currentSession . #log) . Log.handleEvent) (pure ())

  Project ->
    keyEvent projectKey

  Tasks ->
    keyEvent tasksKey

  current ->
    keyEvent (handleGlobalKey current)

handleUiEvent :: BrickEvent Name MainEvent -> MainM ()
handleUiEvent = \case
  AppEvent event -> handleMainEvent event
  VtyEvent event -> do
    current <- use #currentFocus
    vtyEvent current event
  MouseDown {} -> pure ()
  MouseUp {} -> pure ()

initEvent :: MonadUi m => m ()
initEvent = focus StartServer
