{-# LANGUAGE CPP #-}
-- | Fast GHC flag parser for cache restoration.
--
-- Replaces 'GHC.parseDynamicFlags' with direct 'DynFlags' field updates,
-- avoiding the O(n*m) flag table scan in 'GHC.Driver.CmdLine.processArgs'.
--
-- Only handles the flags that appear in cached unit args files.
-- Unknown flags trigger 'error' \u2013 the caller should verify that all flags
-- used by Buck are covered here.
module Internal.FastDynFlags (
  parseFlagsFast,
) where

import GHC.Driver.DynFlags (
  DynFlags (..),
  GeneralFlag (..),
  GhcLink (..),
  ModRenaming (..),
  PackageArg (..),
  PackageFlag (..),
  gopt_set,
  gopt_unset,
  )
import GHC.Platform.Ways (Way (..), addWay, wayGeneralFlags, wayUnsetGeneralFlags)
import GHC.Unit.Types (stringToUnit, stringToUnitId)

-- | Parse cached GHC CLI args by directly updating 'DynFlags' fields.
--
-- This is a replacement for @parseDynamicFlags@ that avoids the O(n*m) linear
-- scan through hundreds of flag definitions.  It supports only the flags known
-- to appear in cached unit args files written by Buck / the standalone server.
--
-- Source file arguments (positional args) are collected and returned as the
-- second component.
parseFlagsFast :: DynFlags -> [String] -> (DynFlags, [String])
parseFlagsFast dflags0 args =
  let dflags1 = dflags0 {ghcLink = LinkBinary, verbosity = 0}
  in go dflags1 args []

-- | Recursive arg processor.
go :: DynFlags -> [String] -> [String] -> (DynFlags, [String])
go dflags [] leftover = (dflags, reverse leftover)
go dflags (arg : rest) leftover = case arg of
  -- No-argument flags
  "-hide-all-packages"          -> go (gopt_set dflags Opt_HideAllPackages) rest leftover
  "-include-pkg-deps"           -> go (dflags {depIncludePkgDeps = True}) rest leftover
  "-no-link"                    -> go (dflags {ghcLink = NoLink}) rest leftover
  "-dynamic"                    -> go (addWayDyn dflags) rest leftover
  "-fbyte-code-and-object-code" -> go (gopt_set dflags Opt_ByteCodeAndObjectCode) rest leftover
  "-fprefer-byte-code"          -> go (gopt_set dflags Opt_UseBytecodeRatherThanObjects) rest leftover
  "-fPIC"                       -> go (gopt_set dflags Opt_PIC) rest leftover
  "-i"                          -> go (dflags {importPaths = []}) rest leftover

  -- Flags with one argument
  "-osuf"         -> withArg rest \v r -> go (dflags {objectSuf_ = v}) r leftover
  "-hisuf"        -> withArg rest \v r -> go (dflags {hiSuf_ = v}) r leftover
  "-odir"         -> withArg rest \v r -> go (dflags {objectDir = Just v}) r leftover
  "-hidir"        -> withArg rest \v r -> go (dflags {hiDir = Just v}) r leftover
  "-stubdir"      -> withArg rest \v r -> go (dflags {stubDir = Just v}) r leftover
  "-this-unit-id" -> withArg rest \v r -> go (dflags {homeUnitId_ = stringToUnitId v}) r leftover
  "-dep-makefile" -> withArg rest \_v r -> go dflags r leftover  -- ignored
  "-tmpdir"       -> withArg rest \_v r -> go dflags r leftover  -- tmpDir type varies; usually not needed for cache

  "-package"      -> withArg rest \v r -> go (addExpose dflags "-package" (PackageArg v)) r leftover
  "-package-id"   -> withArg rest \v r -> go (addExpose dflags "-package-id" (UnitIdArg (stringToUnit v))) r leftover

  -- Non-flag arguments (source files)
  ('-' : _)       -> error ("Internal.FastDynFlags: unrecognized flag: " ++ arg)
  _               -> go dflags rest (arg : leftover)

-- | Consume the next argument for a flag that requires one.
withArg :: [String] -> (String -> [String] -> a) -> a
withArg [] _ = error "Internal.FastDynFlags: flag requires an argument"
withArg (v : rest) k = k v rest

-- | Add an 'ExposePackage' flag to 'DynFlags'.
addExpose :: DynFlags -> String -> PackageArg -> DynFlags
addExpose dflags doc pkgArg =
  dflags {packageFlags = ExposePackage doc pkgArg (ModRenaming True []) : packageFlags dflags}

-- | Add 'WayDyn' to the target ways and apply associated general flag changes.
addWayDyn :: DynFlags -> DynFlags
addWayDyn dflags =
  let platform = targetPlatform dflags
      dflags1 = dflags {targetWays_ = addWay WayDyn (targetWays_ dflags)}
      dflags2 = foldl' gopt_set dflags1 (wayGeneralFlags platform WayDyn)
      dflags3 = foldl' gopt_unset dflags2 (wayUnsetGeneralFlags platform WayDyn)
  in dflags3
