{-# LANGUAGE NoFieldSelectors #-}

-- TODO Rename to Api
module Types.Instrument where

import Data.Aeson (FromJSON, ToJSON)
import Data.Binary (Binary)
import Data.Map (Map)
import Data.String (IsString)
import qualified Data.Text as Text
import Data.Text (Text)
import qualified GHC
import GHC.Generics (Generic)
import GHC.Unit (Module, mkModuleName, moduleName, moduleNameString, moduleUnitId, unitIdString)
import qualified Types.Target as Worker
import Types.Target (ModuleTarget (..), TargetSpec, UnitTarget (..))

newtype UnitName =
  UnitName { text :: Text }
  deriving stock (Eq, Show)
  deriving newtype (IsString, Ord, Binary, FromJSON, ToJSON)

newtype ModuleName =
  ModuleName { text :: Text }
  deriving stock (Eq, Show)
  deriving newtype (IsString, Ord, Binary, FromJSON, ToJSON)

fromGhcModuleName :: GHC.ModuleName -> ModuleName
fromGhcModuleName name =
  ModuleName (Text.pack (moduleNameString name))

toGhcModuleName :: ModuleName -> GHC.ModuleName
toGhcModuleName name =
  mkModuleName (Text.unpack name.text)

data HomeModule =
  HomeModule {
    unit :: UnitName,
    name :: ModuleName
  }
  deriving stock (Eq, Show, Ord, Generic)
  deriving anyclass (Binary, FromJSON, ToJSON)

homeModuleFromGhc :: Module -> HomeModule
homeModuleFromGhc m =
  HomeModule {
    unit = UnitName (Text.pack (unitIdString (moduleUnitId m))),
    name = fromGhcModuleName (moduleName m)
  }

-- | A unit and its module names, as discovered by @ghc-server@'s project discovery (unit directories /
-- @unit.json@ files, or @.cabal@ parsing) at startup. Module names come from source file basenames, not from a
-- computed module graph -- this is available immediately on connection, before any metadata or compilation runs.
data UnitSummary =
  UnitSummary {
    name :: UnitName,
    modules :: [ModuleName]
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (Binary)

-- | Cache-tracking info for a single lazily-loaded bytecode-cache entry, mirroring the @BcoCacheEntry@ proto
-- message. Unlike that message, values of this type are constructed directly from 'Types.State.Make.MakeState'
-- (see @GhcWorker.Grpc.bytecodeEntries@) and are used both to construct 'BytecodeSnapshot' events.
data TrackedBytecode =
  TrackedBytecode {
    key :: HomeModule,
    size :: Int,
    lastAccess :: Int,
    resident :: Bool,
    pendingEviction :: Bool
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (Binary, FromJSON, ToJSON)

data Target =
  TargetProject
  |
  TargetUnit { name :: UnitName }
  |
  TargetModule { key :: HomeModule }
  deriving stock (Eq, Show, Ord, Generic)
  deriving anyclass (Binary, FromJSON, ToJSON)

homeModuleMatchTarget :: HomeModule -> Target -> Bool
homeModuleMatchTarget candidate = \case
  TargetProject -> True
  TargetUnit {name} -> candidate.unit == name
  TargetModule {key} -> candidate == key

renderTarget :: Target -> Text
renderTarget = \case
  TargetProject -> "the project"
  TargetUnit {name = UnitName name} -> name
  TargetModule {key = HomeModule {unit = UnitName unit, name = ModuleName name}} -> unit <> ":" <> name

-- | Whether the second target is included in the first.
targetContains :: Target -> Target -> Bool
targetContains = \cases
  TargetProject _ -> True
  TargetUnit {name} TargetUnit {name = candidate} -> name == candidate
  TargetUnit {name} TargetModule {key = candidate} -> name == candidate.unit
  reference candidate -> reference == candidate

targetFromWorkerSpec :: TargetSpec -> Maybe Target
targetFromWorkerSpec = \case
  Worker.TargetModule ModuleTarget {module_} -> Just TargetModule {key = homeModuleFromGhc module_}
  Worker.TargetModuleInterp ModuleTarget {module_} -> Just TargetModule {key = homeModuleFromGhc module_}
  Worker.TargetUnit UnitTarget {unit} -> Just TargetUnit {name = UnitName (Text.pack (unitIdString unit))}
  _ -> Nothing

data TaskKind =
  Metadata
  |
  Build { rebuild :: Bool }
  |
  Execute
  deriving stock (Eq, Show, Generic)
  deriving anyclass (Binary, FromJSON, ToJSON)

data TaskTrigger =
  TaskTrigger {
    target :: Target,
    task :: TaskKind
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (Binary, FromJSON, ToJSON)

data ApiRequest =
  TriggerTask TaskTrigger
  |
  EvictBytecode Target
  |
  Clean Target
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

-- | The response counterpart to 'Command', JSON-encoded into the unified @Api@ RPC's response message.
-- 'Ack' answers every command except 'Clean', which reports 'CleanResult'.
--
-- TODO this should be a generic success/failure type, since we don't have dependent types here.
-- Probably more sensible to use multiple grpc endpoints after all.
data ApiResponse =
  Ack
  |
  Failure { message :: Text }
  |
  BytecodeState { entries :: [TrackedBytecode] }
  |
  CleanResult { success :: Bool, message :: Text }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

data Event =
  CompileStart {
    target :: Target,
    debuggable :: Bool,
    requestId :: Int
  }
  |
  CompileEnd {
    target :: Target,
    exitCode :: Int,
    stderr :: String,
    result :: Maybe String,
    requestId :: Int
  }
  |
  Stats {
    memory :: Map Text Int,
    cpuNs :: Int,
    gcCpuNs :: Int
  }
  |
  -- | The project's units and modules, sent once when a client connects to the Instrument service. Populates the
  -- @instrument@ app's task tree view immediately, ahead of any build activity.
  ProjectStructure { units :: [UnitSummary] }
  |
  -- | A snapshot of the lazily-loaded bytecode cache, pushed to the @instrument@ UI whenever it may have changed
  -- (after a compile\/metadata\/execute task finishes), rather than fetched on demand by the UI. See
  -- @GhcWorker.Grpc.pushBytecodeState@.
  BytecodeSnapshot { entries :: [TrackedBytecode] }
  |
  -- | A single log message captured from the server's 'Types.Log.Logger' (debug\/info\/fatal messages and GHC's
  -- own diagnostic output), tagged with the unit\/module target that was active when it was emitted and a
  -- millisecond epoch timestamp. Only emitted when the @instrument@ feature is enabled (see
  -- @GhcServer.Log.instrumentLogger@).
  LogMessage {
    category :: String,
    level :: String,
    message :: String,
    timestampMs :: Integer
  }
  |
  -- | A single pipeline phase (@Hsc@\/@HscPostTc@\/@HscBackend@) firing for a target's compilation, emitted via
  -- GHC's @runPhaseHook@ (see @Internal.Compile.Make.withPhaseEvents@). Named @PhaseEvent@ rather than @Phase@ to
  -- avoid clashing with @GhcServer.Scheduler@'s unrelated @Phase@ type when both are imported unqualified.
  PhaseStart {
    target :: Target,
    phase :: String,
    requestId :: Int
  }
  |
  PhaseEnd {
    target :: Target,
    durationMs :: Word,
    requestId :: Int
  }
  -- | Sent once the scheduler's queue has fully drained -- i.e. every in-flight UI-triggered build request (see
  -- @GhcServer.Grpc.triggerTask@) has completed, not just the one that happened to trigger this event. A single
  -- request fanned out into several concurrent scheduler batches (e.g. a project-wide build across multiple
  -- units) therefore produces exactly one of these, rather than one per batch.
  |
  RequestCompleted { statusMessage :: Text }
  |
  Halt
  deriving stock (Eq, Show, Generic)
  deriving anyclass (Binary)
