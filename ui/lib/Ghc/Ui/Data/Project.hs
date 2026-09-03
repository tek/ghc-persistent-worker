module Ghc.Ui.Data.Project where

import Brick.Widgets.List (GenericList, list)
import Data.Map.Strict (Map)
import Data.Sequence (Seq)
import Data.Set qualified as Set
import Data.Set (Set)
import GHC.Generics (Generic)
import Ghc.Ui.Data.Name (Name (..))
import Types.Instrument (HomeModule, ModuleName, Target, TrackedBytecode, UnitName)

-- | A unit and its module names, as reported by 'Types.Instrument.ProjectStructure'.
data ProjectUnit =
  ProjectUnit {
    unit :: UnitName,
    modules :: [ModuleName]
  }
  deriving stock (Eq, Show)

-- | A row in the displayed tree: the project-root node (selectable, but not collapsible -- unlike unit headers,
-- "expanding" it doesn't hide/reveal anything, since its children are simply the existing top-level unit
-- headers), a collapsible unit header (carrying its own expanded state for rendering), or a module leaf tagged
-- with whether it is the last child of its unit (to draw the correct L-shaped connector).
data Row =
  Root
  |
  Header { unit :: UnitName, expanded :: Bool, isLast :: Bool }
  |
  ModuleRow { key :: HomeModule, isLast :: Bool, isLastUnit :: Bool }
  deriving stock (Eq, Show)

data ProjectState =
  ProjectState {
    rows :: GenericList Name Seq Row,
    units :: [ProjectUnit],
    expandedUnits :: Set UnitName,
    built :: Set Target,
    failed :: Set Target,
    bco :: Map HomeModule TrackedBytecode
  }
  deriving stock (Generic)

initialState :: ProjectState
initialState =
  ProjectState {
    rows = list Project [] 1,
    units = [],
    expandedUnits = Set.empty,
    built = Set.empty,
    failed = Set.empty,
    bco = []
  }
