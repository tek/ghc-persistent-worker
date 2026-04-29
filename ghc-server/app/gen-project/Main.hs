module Main where

import GhcServer.GenProject (writeProject, writeWideProject, wideUnitCount)
import System.Environment (getArgs)
import System.Directory (createDirectoryIfMissing)

main :: IO ()
main = do
  args <- getArgs
  case args of
    [dir, depthStr]
      | [(depth, "")] <- reads depthStr, depth > 0 -> do
          createDirectoryIfMissing True dir
          writeProject dir depth
          let levels = 2 * depth
              modules = sum [2 ^ (l + 1) | l <- [0 .. levels - 1]] :: Int
              units = 2 * depth
          putStrLn ("Generated project in " ++ dir)
          putStrLn ("  depth:   " ++ show depth ++ " (" ++ show levels ++ " levels)")
          putStrLn ("  units:   " ++ show units)
          putStrLn ("  modules: " ++ show modules)
    ["--wide", dir, depthStr, modsStr]
      | [(depth, "")] <- reads depthStr, depth > 0
      , [(modsPerUnit, "")] <- reads modsStr, modsPerUnit > 0 -> do
          createDirectoryIfMissing True dir
          writeWideProject dir depth modsPerUnit
          let units = wideUnitCount depth
          putStrLn ("Generated wide project in " ++ dir)
          putStrLn ("  depth:          " ++ show depth)
          putStrLn ("  units:          " ++ show units)
          putStrLn ("  modules/unit:   " ++ show modsPerUnit)
          putStrLn ("  total modules:  " ++ show (units * modsPerUnit))
    _ -> do
      putStrLn "Usage: gen-project <directory> <depth>"
      putStrLn "       gen-project --wide <directory> <depth> <modules-per-unit>"
      putStrLn ""
      putStrLn "  Deep mode (default): binary tree of modules, 2*depth units"
      putStrLn "  Wide mode (--wide):  binary tree of units, 2^depth-1 units"
      putStrLn ""
      putStrLn "Example: gen-project /tmp/test-project 2"
      putStrLn "  Creates a project with 4 levels, 4 units, and 30 modules"
      putStrLn ""
      putStrLn "Example: gen-project --wide /tmp/test-project 10 3"
      putStrLn "  Creates a project with 1023 units, 3 modules each"
