{-# LANGUAGE QuasiQuotes #-}

-- | Test comparing full vs incremental metadata to ensure they produce identical build plans.
--
-- Uses a static 2×2 project (2 units, 2 modules each). Runs three metadata steps:
--
-- 1. Initial build with full metadata + ACTION_METADATA (establishes baseline and incremental state)
-- 2. After source modification, rebuild with incremental metadata (reuses state from step 1)
-- 3. After source modification, rebuild with full metadata from clean state
--
-- Asserts that the incremental and full rebuilds produce identical build plan JSON for each unit.
module IncrementalMetadataTest where

import Control.Monad.IO.Class (liftIO)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as BSL
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Hedgehog (diff, (===))
import qualified System.File.OsPath as OsPath
import System.OsPath (osp, (</>))
import Test.ActionMetadata (writeAllUnitActionMetadata, writeUnitActionMetadata)
import Test.Build (initialStrategy, runSchedule)
import Test.Data.BuildSystem (BuildResult (..))
import Test.Data.Env (MaxJobs (..), SessionEnv (..))
import Test.Data.Project (BuildModule (..), Component (..), GenUnit (..), ModuleKey (..), TaskKey (..), UnitKey (..))
import Test.Data.Scheduler (Schedule (..), Task (..))
import Test.Data.SourceMode (ModuleSource (..), SourceMode (..))
import Test.Env (newResumeSessionEnv, newSessionEnv, withTestEnv)
import Test.Path (fp, moduleSourcePath, unitOutputDir)
import Test.Run (unitTest)
import Test.Source (moduleSource, writeProjectSources)
import Test.Tasty (TestTree, testGroup)

modulesPerUnit :: Int
modulesPerUnit = 2

-- | Module keys for a unit.
testModuleKeys :: UnitKey -> [ModuleKey]
testModuleKeys unit =
  [ModuleKey {unit, number, errorVariant = Nothing} | number <- [0 .. modulesPerUnit - 1]]

intraUnitDeps :: ModuleKey -> Set.Set ModuleKey
intraUnitDeps ModuleKey {unit, number} =
  Set.fromList [ModuleKey {unit, number = n, errorVariant = Nothing} | n <- [0 .. number - 1]]

crossUnitDeps :: Set.Set UnitKey -> Set.Set ModuleKey
crossUnitDeps depUnits =
  Set.fromList [mk | u <- Set.toList depUnits, mk <- testModuleKeys u]

testModuleDeps :: Set.Set UnitKey -> ModuleKey -> Set.Set ModuleKey
testModuleDeps depUnits key =
  Set.union (intraUnitDeps key) (crossUnitDeps depUnits)

mkTestUnit :: UnitKey -> Set.Set UnitKey -> GenUnit BuildModule
mkTestUnit unitKey depUnits =
  GenUnit {
    key = unitKey,
    depUnits,
    modules = [
      BuildModule {key, deps = testModuleDeps depUnits key, th = False, bindings = 1, extDeps = mempty}
      | key <- testModuleKeys unitKey
    ]
  }

metaTask :: GenUnit BuildModule -> Task TaskKey Component
metaTask unit =
  Task {
    key = TaskMeta unit.key,
    deps = Set.map TaskMeta unit.depUnits,
    value = ComponentUnit unit
  }

moduleTask :: UnitKey -> BuildModule -> Task TaskKey Component
moduleTask unitKey BuildModule {key, deps} =
  Task {
    key = TaskCompile key,
    deps = Set.insert (TaskMeta unitKey) (Set.map TaskCompile deps),
    value = ComponentModule key
  }

unitTasks :: GenUnit BuildModule -> [Task TaskKey Component]
unitTasks unit =
  metaTask unit : [moduleTask unit.key bm | bm <- unit.modules]

testSchedule :: [GenUnit BuildModule] -> Schedule TaskKey Component
testSchedule units =
  Schedule {tasks = concatMap unitTasks units}

-- | The test project: 2 units, 2 modules each. No TH, 1 binding, no ext deps.
-- Unit 0: leaf, Unit 1: depends on Unit 0.
allUnits :: [GenUnit BuildModule]
allUnits =
  [
    mkTestUnit 0 Set.empty,
    mkTestUnit 1 (Set.singleton 0)
  ]

-- | Source map for writing project sources.
sourcesMap :: Map.Map ModuleKey ModuleSource
sourcesMap =
  Map.fromList
    [(m.key, ModuleSource {deps = Set.toList m.deps, th = m.th, bindings = m.bindings, extDeps = m.extDeps})
    | u <- allUnits, m <- u.modules]

-- | All source file paths for the project.
allSourcePaths :: SessionEnv -> [FilePath]
allSourcePaths env =
  [fp (env.sourceDir </> moduleSourcePath m.key) | u <- allUnits, m <- u.modules]

-- | Write per-unit ACTION_METADATA files for the test project.
writeProjectMetadata :: SessionEnv -> IO ()
writeProjectMetadata env =
  writeAllUnitActionMetadata env.tempDir env.sourceDir allUnits

-- | Write per-unit ACTION_METADATA for just the modified unit after a source change.
writeModifiedUnitMetadata :: SessionEnv -> IO ()
writeModifiedUnitMetadata env =
  case [u | u <- allUnits, u.key == modifiedModule.unit] of
    unit : _ -> writeUnitActionMetadata env.tempDir env.sourceDir unit
    [] -> pure ()

-- | The module key we modify between builds.
modifiedModule :: ModuleKey
modifiedModule = ModuleKey {unit = 1, number = 1, errorVariant = Nothing}

-- | Rewrite one module's source to simulate a change.
modifySource :: SessionEnv -> IO ()
modifySource env = do
  let path = env.sourceDir </> moduleSourcePath modifiedModule
      deps = Set.toList (testModuleDeps (Set.singleton 0) modifiedModule)
  OsPath.writeFile path (moduleSource 1 False mempty SourceModified modifiedModule deps)
  writeModifiedUnitMetadata env

-- | Read the build plan JSON written by the metadata step for a unit.
readBuildPlan :: SessionEnv -> UnitKey -> IO Aeson.Value
readBuildPlan env unit = do
  let path = env.tempDir </> unitOutputDir unit </> [osp|build-plan.json|]
  content <- BSL.readFile (fp path)
  case Aeson.decode content of
    Just v -> pure v
    Nothing -> fail ("Failed to decode build plan for unit " ++ show unit)

-- | Read build plans for all units, keyed by unit number.
readAllBuildPlans :: SessionEnv -> IO (Map.Map Int Aeson.Value)
readAllBuildPlans env =
  Map.fromList <$> traverse readOne [0, 1]
  where
    readOne n = (n,) <$> readBuildPlan env (UnitKey n)

-- | Run a build, using incremental metadata when 'useIncremental' is 'True'.
runBuild :: SessionEnv -> Bool -> IO BuildResult
runBuild env useIncremental =
  runSchedule (MaxJobs 1) (initialStrategy env useIncremental) Set.empty (testSchedule allUnits)

test_incrementalMetadata :: TestTree
test_incrementalMetadata =
  withTestEnv \ getTestEnv ->
    unitTest "incremental vs full metadata equivalence" do
      env <- liftIO getTestEnv
      sessionEnv <- liftIO (newSessionEnv env)

      -- Step 1: Initial build with ACTION_METADATA to establish incremental state.
      -- This is a full build (no prior state file), but it writes the state file for the next run.
      liftIO do
        writeProjectSources sessionEnv.sourceDir sourcesMap
        writeProjectMetadata sessionEnv
      initialResult <- liftIO $ runBuild sessionEnv True
      diff initialResult.hasErrors (==) False


      -- Step 2: Modify a source, update ACTION_METADATA, rebuild with incremental (fresh worker state).
      -- The incremental state file from step 1 persists, so buildPlanForSources takes the incremental path.
      -- modifySource also updates the per-unit ACTION_METADATA for unit 1.
      liftIO $ modifySource sessionEnv
      incrementalEnv <- liftIO $ newResumeSessionEnv sessionEnv
      incrementalResult <- liftIO $ runBuild incrementalEnv True
      diff incrementalResult.hasErrors (==) False

      incrementalPlans <- liftIO $ readAllBuildPlans incrementalEnv

      -- Step 3: Same modified sources, but full metadata from a clean state (no ACTION_METADATA).
      fullEnv <- liftIO $ newResumeSessionEnv sessionEnv
      fullResult <- liftIO $ runBuild fullEnv False
      diff fullResult.hasErrors (==) False

      fullPlans <- liftIO $ readAllBuildPlans fullEnv

      -- Core assertion: incremental and full metadata produce the same build plan.
      incrementalPlans === fullPlans

      -- Verify that both builds produced non-empty results (sanity check that the test ran).
      diff (Map.size incrementalPlans) (==) 2
      diff (Map.size fullPlans) (==) 2

test_incremental :: TestTree
test_incremental = testGroup "incremental metadata" [test_incrementalMetadata]
