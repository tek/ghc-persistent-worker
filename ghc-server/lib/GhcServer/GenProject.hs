-- | Generate a synthetic binary-tree multi-unit Haskell project for ghc-server testing.
--
-- === Deep mode (original)
--
-- The generated project has a binary tree of modules. Two tree levels are grouped into
-- two units, split horizontally (left half of modules in one unit, right half in another).
--
-- At level @l@, there are @2^(l+1)@ modules. Each module at level @l@, index @i@ imports
-- two children at @(l+1, 2*i)@ and @(l+1, 2*i+1)@. Leaf modules have no imports.
--
-- The CLI depth argument @d@ produces @2*d@ levels and @2*d@ units.
-- Module count grows exponentially.
--
-- === Wide mode
--
-- A binary tree of /units/, each with a fixed number of modules.
-- Depth @d@ produces @2^d - 1@ units (e.g. depth 10 = 1023 units).
-- Each non-leaf unit depends on its two children.
-- Module 0 of each unit imports module 0 from both child units.
module GhcServer.GenProject where

import Data.Aeson (encode)
import qualified Data.ByteString.Lazy as LBS
import Data.Foldable (traverse_)
import Data.List (intercalate)
import qualified Data.Map.Strict as Map
import GhcServer.Data.UnitConfig (UnitConfig (..))
import System.Directory (createDirectoryIfMissing)

-- ---------------------------------------------------------------------------
-- Tree geometry
-- ---------------------------------------------------------------------------

-- | Total number of tree levels.
totalLevels :: Int -> Int
totalLevels depth = 2 * depth

-- | Number of modules at a given level.
levelSize :: Int -> Int
levelSize level = 2 ^ (level + 1)

-- | The group index for a level (two levels per group).
levelGroup :: Int -> Int
levelGroup level = div level 2

-- | Number of groups.
totalGroups :: Int -> Int
totalGroups depth = depth

-- | Whether a level is the top (even) or bottom (odd) within its group.
isTopLevel :: Int -> Bool
isTopLevel level = even level

-- | The unit index for a module at a given level and position.
--
-- Each group has two units: the left unit (even) and the right unit (odd).
-- The left half of modules at each level goes to the left unit; the right half to the right.
moduleUnit :: Int -> Int -> Int
moduleUnit level index =
  2 * levelGroup level + side
  where
    halfSize = div (levelSize level) 2
    side = if index < halfSize then 0 else 1

-- | The module number within its unit.
--
-- Modules from the top level of the group come first, then the bottom level.
moduleNumber :: Int -> Int -> Int
moduleNumber level index =
  offset + localIndex
  where
    group = levelGroup level
    halfSize = div (levelSize level) 2
    localIndex = mod index halfSize
    offset
      | isTopLevel level = 0
      | otherwise = div (levelSize (2 * group)) 2

-- | A module in the tree, identified by its tree coordinates.
data TreeModule =
  TreeModule {
    level :: Int,
    index :: Int,
    unitIndex :: Int,
    modNumber :: Int
  }
  deriving stock (Show)

-- | The name of a unit.
unitName :: Int -> String
unitName i = "unit" ++ show i

-- | The name of a module given its unit and module number.
moduleName :: Int -> Int -> String
moduleName u m = "U" ++ show u ++ "M" ++ show m

-- | Compute all modules in the tree.
allModules :: Int -> [TreeModule]
allModules depth =
  [ TreeModule {level, index, unitIndex, modNumber}
  | level <- [0 .. totalLevels depth - 1]
  , index <- [0 .. levelSize level - 1]
  , let unitIndex = moduleUnit level index
  , let modNumber = moduleNumber level index
  ]

-- | The two children of a module (if it's not a leaf).
children :: Int -> TreeModule -> [(Int, Int)]
children depth m
  | m.level + 1 >= totalLevels depth = []
  | otherwise = [(m.level + 1, 2 * m.index), (m.level + 1, 2 * m.index + 1)]

-- ---------------------------------------------------------------------------
-- Unit structure
-- ---------------------------------------------------------------------------

-- | Compute which units each unit depends on.
--
-- A unit @2g@ (left) depends on unit @2(g+1)@ (left of next group).
-- A unit @2g+1@ (right) depends on unit @2(g+1)+1@ (right of next group).
-- The last group has no deps.
unitDeps :: Int -> Int -> [Int]
unitDeps depth unitIdx
  | group + 1 >= totalGroups depth = []
  | otherwise = [2 * (group + 1) + side]
  where
    group = div unitIdx 2
    side = mod unitIdx 2

-- | Total number of units.
totalUnits :: Int -> Int
totalUnits depth = 2 * depth

-- ---------------------------------------------------------------------------
-- Source generation
-- ---------------------------------------------------------------------------

-- | Build a lookup from @(level, index)@ to @(unitIndex, modNumber)@ for import resolution.
buildModuleMap :: Int -> Map.Map (Int, Int) (Int, Int)
buildModuleMap depth =
  Map.fromList
    [ ((m.level, m.index), (m.unitIndex, m.modNumber))
    | m <- allModules depth
    ]

-- | Generate the Haskell source for a module.
moduleSource :: Int -> Map.Map (Int, Int) (Int, Int) -> TreeModule -> String
moduleSource depth modMap m =
  unlines $
    ["module " ++ modName ++ " where"]
    ++ importLines
    ++ [""]
    ++ [valueName ++ " :: Int"]
    ++ [valueName ++ " = " ++ valueExpr]
  where
    modName = moduleName m.unitIndex m.modNumber
    valueName = "value_" ++ show m.unitIndex ++ "_" ++ show m.modNumber

    childMods = [(cu, cm) | (cl, ci) <- children depth m, let (cu, cm) = modMap Map.! (cl, ci)]

    childValue cu cm = "value_" ++ show cu ++ "_" ++ show cm

    importLines =
      ["import " ++ moduleName cu cm ++ " (" ++ childValue cu cm ++ ")" | (cu, cm) <- childMods]

    valueExpr
      | null childMods = "1"
      | otherwise = intercalate " + " [childValue cu cm | (cu, cm) <- childMods] ++ " + 1"

-- ---------------------------------------------------------------------------
-- Project writing
-- ---------------------------------------------------------------------------

-- | Write the entire project to disk.
writeProject :: FilePath -> Int -> IO ()
writeProject root depth = do
  let modMap = buildModuleMap depth
      mods = allModules depth
      numUnits = totalUnits depth
  -- Create unit directories and write unit.json files
  traverse_ (writeUnitDir root depth) ([0 .. numUnits - 1] :: [Int])
  -- Write module source files
  traverse_ (writeModuleSource root depth modMap) mods

-- | Create a unit directory with its @unit.json@.
writeUnitDir :: FilePath -> Int -> Int -> IO ()
writeUnitDir root depth unitIdx = do
  let dir = root ++ "/" ++ unitName unitIdx
  createDirectoryIfMissing True dir
  let deps = unitDeps depth unitIdx
      config = UnitConfig {deps = map unitName deps, args = []}
  LBS.writeFile (dir ++ "/unit.json") (encode config)

-- | Write a single module's source file.
writeModuleSource :: FilePath -> Int -> Map.Map (Int, Int) (Int, Int) -> TreeModule -> IO ()
writeModuleSource root depth modMap m = do
  let uName = unitName m.unitIndex
      mName = moduleName m.unitIndex m.modNumber
      dir = root ++ "/" ++ uName
      source = moduleSource depth modMap m
  writeFile (dir ++ "/" ++ mName ++ ".hs") source

-- ---------------------------------------------------------------------------
-- Wide mode: binary tree of units with fixed module count
-- ---------------------------------------------------------------------------

-- | Total number of units in a wide binary tree: @2^depth - 1@.
wideUnitCount :: Int -> Int
wideUnitCount depth = 2 ^ depth - 1

-- | The two child unit indices for a given unit in a 1-indexed binary heap layout.
-- Unit 1 is the root. Children of unit @i@ are @2*i@ and @2*i+1@.
-- Returns empty list for leaf units.
wideUnitChildren :: Int -> Int -> [Int]
wideUnitChildren totalUnits' uid
  | left > totalUnits' = []
  | otherwise = [left, right]
  where
    left = 2 * uid
    right = 2 * uid + 1

-- | Generate the source for a module in wide mode.
--
-- Module 0 of each non-leaf unit imports @val_0@ from both child units' module 0.
-- All other modules are standalone.
wideModuleSource :: Int -> Int -> Int -> [Int] -> String
wideModuleSource uid mid modsPerUnit childUids =
  unlines $
    ["module " ++ moduleName uid mid ++ " where"]
    ++ importLines
    ++ [""]
    ++ [valName ++ " :: Int"]
    ++ [valName ++ " = " ++ valueExpr]
  where
    valName = "val_" ++ show mid

    importLines
      | mid == 0 =
          [ "import qualified " ++ moduleName cu 0
          | cu <- childUids
          ]
      | otherwise = []

    childRef cu = moduleName cu 0 ++ ".val_0"

    valueExpr
      | mid == 0, not (null childUids) =
          intercalate " + " (map childRef childUids) ++ " + 1"
      | otherwise = show (uid * modsPerUnit + mid)

-- | Write a wide-mode project to disk.
writeWideProject :: FilePath -> Int -> Int -> IO ()
writeWideProject root depth modsPerUnit = do
  let total = wideUnitCount depth
  traverse_ (writeWideUnit root total modsPerUnit) ([1 .. total] :: [Int])

-- | Write a single unit directory for wide mode.
writeWideUnit :: FilePath -> Int -> Int -> Int -> IO ()
writeWideUnit root totalUnits' modsPerUnit uid = do
  let uName = unitName uid
      dir = root ++ "/" ++ uName
      children' = wideUnitChildren totalUnits' uid
      deps = map unitName children'
      config = UnitConfig {deps, args = []}
  createDirectoryIfMissing True dir
  LBS.writeFile (dir ++ "/unit.json") (encode config)
  traverse_ (writeWideModule dir uid modsPerUnit children') ([0 .. modsPerUnit - 1] :: [Int])

-- | Write a single module source file for wide mode.
writeWideModule :: FilePath -> Int -> Int -> [Int] -> Int -> IO ()
writeWideModule dir uid modsPerUnit childUids mid = do
  let mName = moduleName uid mid
      source = wideModuleSource uid mid modsPerUnit childUids
  writeFile (dir ++ "/" ++ mName ++ ".hs") source
