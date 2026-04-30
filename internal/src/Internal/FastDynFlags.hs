{-# LANGUAGE CPP #-}
-- | Fast GHC flag parser for cache restoration.
--
-- Replaces 'GHC.parseDynamicFlags' with direct 'DynFlags' field updates,
-- avoiding the O(n*m) flag table scan in 'GHC.Driver.CmdLine.processArgs'.
--
-- Uses flatparse to operate directly on 'ByteString', avoiding String
-- allocation for the input.  String conversion happens only at the GHC
-- API boundary (DynFlags fields that require 'String').
--
-- Only handles the flags that appear in cached unit args files.
-- Unknown flags trigger 'error' \u2013 the caller should verify that all flags
-- used by Buck are covered here.
module Internal.FastDynFlags (
  parseFlagsFast,
) where

import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as B8
import FlatParse.Basic (Parser, Result (..), byteString, runParser, takeRest, eof, (<|>), byteStringOf)
import GHC.Data.OsPath (unsafeEncodeUtf)
import GHC.Driver.DynFlags (
  DynFlags (..),
  GeneralFlag (..),
  GhcLink (..),
  ModRenaming (..),
  PackageArg (..),
  PackageDBFlag (..),
  PackageFlag (..),
  PkgDbRef (..),
  gopt_set,
  gopt_unset,
  )
import GHC.Platform.Ways (Way (..), addWay, wayGeneralFlags, wayUnsetGeneralFlags)
import GHC.Unit.Types (stringToUnit, stringToUnitId)

-- | A parsed flag with its effect on 'DynFlags'.
data Flag
  = FlagNoArg (DynFlags -> DynFlags)
  -- ^ A standalone flag that modifies 'DynFlags' directly.
  | FlagOneArg (ByteString -> DynFlags -> DynFlags)
  -- ^ A flag that consumes the next line as its argument.
  | FlagSource ByteString
  -- ^ A source file path (non-flag positional argument).

-- | Parse a single line as a flag.
--
-- Tries each known flag prefix in turn.  Unknown flags starting with @-@
-- trigger 'error'; other lines are treated as source file paths.
parseLine :: Parser () Flag
parseLine =
  noArgFlag "-hide-all-packages" (gopt_set `flip` Opt_HideAllPackages)
  <|> noArgFlag "-include-pkg-deps" (\d -> d {depIncludePkgDeps = True})
  <|> noArgFlag "-no-link" (\d -> d {ghcLink = NoLink})
  <|> noArgFlag "-dynamic" addWayDyn
  <|> noArgFlag "-fbyte-code-and-object-code" (gopt_set `flip` Opt_ByteCodeAndObjectCode)
  <|> noArgFlag "-fprefer-byte-code" (gopt_set `flip` Opt_UseBytecodeRatherThanObjects)
  <|> noArgFlag "-fPIC" (gopt_set `flip` Opt_PIC)
  <|> noArgFlag "-i" (\d -> d {importPaths = []})
  <|> oneArgFlag "-osuf" (\v d -> d {objectSuf_ = v})
  <|> oneArgFlag "-hisuf" (\v d -> d {hiSuf_ = v})
  <|> oneArgFlag "-odir" (\v d -> d {objectDir = Just v})
  <|> oneArgFlag "-hidir" (\v d -> d {hiDir = Just v})
  <|> oneArgFlag "-stubdir" (\v d -> d {stubDir = Just v})
  <|> oneArgFlag "-this-unit-id" (\v d -> d {homeUnitId_ = stringToUnitId v})
  <|> oneArgFlag "-dep-makefile" (\_v d -> d)
  <|> oneArgFlag "-tmpdir" (\_v d -> d)
  <|> oneArgFlag "-package-db" addPackageDB
  <|> oneArgFlag "-package-id" (\v d -> addExpose d ("-package-id " ++ v) (UnitIdArg (stringToUnit v)))
  <|> oneArgFlag "-package" (\v d -> addExpose d ("-package " ++ v) (PackageArg v))
  <|> sourceOrUnknown

-- | Match a standalone flag (no argument).
noArgFlag :: ByteString -> (DynFlags -> DynFlags) -> Parser () Flag
noArgFlag name f = FlagNoArg f <$ (byteString name *> eof)
{-# inline noArgFlag #-}

-- | Match a flag that expects the next line as its argument.
oneArgFlag :: ByteString -> (String -> DynFlags -> DynFlags) -> Parser () Flag
oneArgFlag name f = FlagOneArg (\bs -> f (B8.unpack bs)) <$ (byteString name *> eof)
{-# inline oneArgFlag #-}

-- | A non-flag line (source file) or an unrecognized flag.
sourceOrUnknown :: Parser () Flag
sourceOrUnknown = do
  line <- byteStringOf takeRest
  case B8.uncons line of
    Just ('-', _) -> error ("Internal.FastDynFlags: unrecognized flag: " ++ B8.unpack line)
    _ -> pure (FlagSource line)

-- | Parse cached GHC CLI args by directly updating 'DynFlags' fields.
--
-- This is a replacement for @parseDynamicFlags@ that avoids the O(n*m) linear
-- scan through hundreds of flag definitions.  It supports only the flags known
-- to appear in cached unit args files written by Buck / the standalone server.
--
-- Operates directly on the raw 'ByteString' content of the args file
-- (newline-delimited).  Source file arguments (positional args) are collected
-- and returned as the second component.
parseFlagsFast :: DynFlags -> ByteString -> (DynFlags, [ByteString])
parseFlagsFast dflags0 input =
  let dflags1 = dflags0 {ghcLink = LinkBinary, verbosity = 0}
      linesBs = B8.lines input
  in go dflags1 linesBs []
  where
    go dflags [] leftover = (dflags, reverse leftover)
    go dflags (line : rest) leftover
      | B8.null line = go dflags rest leftover
      | otherwise = case runParser parseLine line of
          OK (FlagNoArg f) _ -> go (f dflags) rest leftover
          OK (FlagOneArg f) _ -> case rest of
            [] -> error "Internal.FastDynFlags: flag requires an argument"
            (arg : rest') -> go (f arg dflags) rest' leftover
          OK (FlagSource src) _ -> go dflags rest (src : leftover)
          Fail -> error ("Internal.FastDynFlags: failed to parse flag: " ++ B8.unpack line)
          Err () -> error ("Internal.FastDynFlags: error parsing flag: " ++ B8.unpack line)

-- | Add an 'ExposePackage' flag to 'DynFlags'.
addExpose :: DynFlags -> String -> PackageArg -> DynFlags
addExpose dflags doc pkgArg =
  dflags {packageFlags = ExposePackage doc pkgArg (ModRenaming True []) : packageFlags dflags}

-- | Append a @-package-db@ entry, mirroring 'addPkgDbRef' in @GHC.Driver.Session@.
addPackageDB :: String -> DynFlags -> DynFlags
addPackageDB path dflags =
  dflags {packageDBFlags = PackageDB (PkgDbPath (unsafeEncodeUtf path)) : packageDBFlags dflags}

-- | Add 'WayDyn' to the target ways and apply associated general flag changes.
addWayDyn :: DynFlags -> DynFlags
addWayDyn dflags =
  let platform = targetPlatform dflags
      dflags1 = dflags {targetWays_ = addWay WayDyn (targetWays_ dflags)}
      dflags2 = foldl' gopt_set dflags1 (wayGeneralFlags platform WayDyn)
      dflags3 = foldl' gopt_unset dflags2 (wayUnsetGeneralFlags platform WayDyn)
  in dflags3
