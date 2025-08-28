module UI.ActiveTasks where

import Brick (attrName, padLeft, txt)
import Brick.Types (EventM, Widget)
import Brick.Widgets.Core (Padding (..), padRight, str, strWrap, withAttr, (<+>), (<=>))
import Brick.Widgets.List (GenericList, list, listElementsL, listSelectedElementL, listSelectedL, renderList)
import Control.Monad.IO.Class (liftIO)
import Data.Foldable (for_)
import Data.Maybe (fromMaybe)
import Data.Sequence qualified as Seq
import Data.Text (Text)
import Data.Time (UTCTime, diffUTCTime, getCurrentTime, nominalDiffTimeToSeconds)
import Lens.Micro.Platform (modifying, preuse, use, (.=))
import Types.State (TargetSpec (..), renderTargetSpec)
import UI.Types (Name (ActiveTasks), WorkerId, disabledAttr)
import UI.Utils (formatPico, popup)

type State = GenericList Name Seq.Seq Task

initialState :: State
initialState = list ActiveTasks Seq.empty 3

data Task = Task
  { _taskTarget :: TargetSpec
  , _taskStartTime :: UTCTime
  , _failure :: Maybe String
  , _fromWorker :: WorkerId
  , _canDebug :: Bool
  , _progressMessage :: Text
  , _progressInfo :: Text
  }

draw :: Name -> UTCTime -> State -> Widget Name
draw current now = renderList drawTask (current == ActiveTasks)
 where
  drawTask _ Task{_taskTarget = name, ..} =
      (padRight Max (withAttr (attrName "headline") (str (renderTargetSpec name))) <+> str (maybe (formatPico $ nominalDiffTimeToSeconds (max 0 (diffUTCTime now _taskStartTime))) (const "Failure") _failure))
      <=>
      padLeft (Pad 2) (txt "● " <+> withAttr disabledAttr (txt _progressMessage))
      <=>
      padLeft (Pad 4) (withAttr disabledAttr (txt _progressInfo))

drawTaskDetails :: Task -> Widget Name
drawTaskDetails Task{_taskTarget = name,..} =
  popup 70 (renderTargetSpec name) $ strWrap $ maybe "" id _failure

addTask :: TargetSpec -> WorkerId -> Bool -> EventM Name State ()
addTask name wid canDebug = do
  time <- liftIO $ getCurrentTime
  tasks <- use listElementsL
  let i = if canDebug then 0 else fromMaybe 0 (Seq.findIndexL (not . _canDebug) tasks)
  listElementsL .= Seq.insertAt i (Task name time Nothing wid canDebug "Added" "") tasks
  modifying listSelectedL (Just . maybe i (\i' -> if i' >= i then i' + 1 else i'))

removeTask :: TargetSpec -> EventM Name State (Maybe UTCTime)
removeTask target = do
  tasks <- use listElementsL
  case Seq.breakl ((== target) . _taskTarget) tasks of
    (before, (Task { _taskStartTime = start }) Seq.:<| after) -> do
      listElementsL .= before <> after
      modifying listSelectedL (\i -> if length before + length after == 0 then Nothing else i)
      pure $ Just start
    _ -> pure Nothing

taskFailure :: TargetSpec -> String -> EventM Name State ()
taskFailure target content = do
  tasks <- use listElementsL
  case Seq.breakl ((== target) . _taskTarget) tasks of
    (before, task Seq.:<| after) ->
      listElementsL .= before <> (task{_failure = Just content} Seq.<| after)
    _ -> pure ()

getSelectedTarget :: EventM Name State (Maybe (WorkerId, TargetSpec))
getSelectedTarget = do
  mtask <- preuse listSelectedElementL
  pure $ (\Task{_fromWorker = wid, _taskTarget = target} -> (wid, target)) <$> mtask

updateProgress ::
  TargetSpec ->
  Text ->
  Text ->
  EventM Name State ()
updateProgress target message info = do
  tasks <- use listElementsL
  for_ (Seq.findIndexL ((== target) . _taskTarget) tasks) \ i ->
    listElementsL .= Seq.adjust update i tasks
  where
    update task = task {_progressMessage = message, _progressInfo = info}
