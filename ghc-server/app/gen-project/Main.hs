module Main where

import GhcServer.GenProject (ExtDepsConfig (..), writeProject, writeWideProject, writeFlatProject, wideUnitCount)
import System.Directory (createDirectoryIfMissing)
import System.Environment (getArgs, lookupEnv)

-- | Build an 'ExtDepsConfig' from the @resource_test_ext_deps@ environment variable.
--
-- Uses ext dep indexes 0\u20134 (the 5 independent leaf packages from @test-ext-deps.nix@).
getExtDepsConfig :: IO (Maybe ExtDepsConfig)
getExtDepsConfig =
  lookupEnv "resource_test_ext_deps" >>= \case
    Nothing -> pure Nothing
    Just dir -> pure (Just ExtDepsConfig {extDepsDir = dir, extDepIndexes = [0 .. 4]})

main :: IO ()
main = do
  args <- getArgs
  extDeps <- getExtDepsConfig
  case args of
    [dir, depthStr]
      | [(depth, "")] <- reads depthStr, depth > 0 -> do
          createDirectoryIfMissing True dir
          writeProject dir depth extDeps
          let levels = 2 * depth
              modules = sum [2 ^ (l + 1) | l <- [0 .. levels - 1]] :: Int
              units = 2 * depth
          putStrLn ("Generated project in " ++ dir)
          putStrLn ("  depth:   " ++ show depth ++ " (" ++ show levels ++ " levels)")
          putStrLn ("  units:   " ++ show units)
          putStrLn ("  modules: " ++ show modules)
          putStrLn ("  ext deps: " ++ maybe "none" (\c -> show (length c.extDepIndexes)) extDeps)
    ["--wide", dir, depthStr, modsStr]
      | [(depth, "")] <- reads depthStr, depth > 0
      , [(modsPerUnit, "")] <- reads modsStr, modsPerUnit > 0 -> do
          createDirectoryIfMissing True dir
          writeWideProject dir depth modsPerUnit extDeps
          let units = wideUnitCount depth
          putStrLn ("Generated wide project in " ++ dir)
          putStrLn ("  depth:          " ++ show depth)
          putStrLn ("  units:          " ++ show units)
          putStrLn ("  modules/unit:   " ++ show modsPerUnit)
          putStrLn ("  total modules:  " ++ show (units * modsPerUnit))
          putStrLn ("  ext deps: " ++ maybe "none" (\c -> show (length c.extDepIndexes)) extDeps)
    ["--flat", dir, numModsStr]
      | [(numModules, "")] <- reads numModsStr, numModules > 0 -> do
          createDirectoryIfMissing True dir
          writeFlatProject dir numModules extDeps
          putStrLn ("Generated flat project in " ++ dir)
          putStrLn ("  units:          1")
          putStrLn ("  total modules:  " ++ show numModules)
          putStrLn ("  ext deps: " ++ maybe "none" (\c -> show (length c.extDepIndexes)) extDeps)
    _ -> do
      putStrLn "Usage: gen-project <directory> <depth>"
      putStrLn "       gen-project --wide <directory> <depth> <modules-per-unit>"
      putStrLn "       gen-project --flat <directory> <num-modules>"
      putStrLn ""
      putStrLn "  Deep mode (default): binary tree of modules, 2*depth units"
      putStrLn "  Wide mode (--wide):  binary tree of units, 2^depth-1 units"
      putStrLn "  Flat mode (--flat):   single unit, module 0 imports all others"
      putStrLn ""
      putStrLn "  Set resource_test_ext_deps to add external dependency packages."
      putStrLn ""
      putStrLn "Example: gen-project /tmp/test-project 2"
      putStrLn "  Creates a project with 4 levels, 4 units, and 30 modules"
      putStrLn ""
      putStrLn "Example: gen-project --wide /tmp/test-project 10 3"
      putStrLn "  Creates a project with 1023 units, 3 modules each"
      putStrLn ""
      putStrLn "Example: gen-project --flat /tmp/test-project 1000"
      putStrLn "  Creates a project with 1 unit, 1000 modules (M0 imports M1..M999)"
