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
import qualified Data.Map.Strict as Map
import FlatParse.Basic (Parser, Result (..), byteString, byteStringOf, eof, runParser, takeRest, (<|>))
import GHC.Data.OsPath (unsafeEncodeUtf)
import GHC.Driver.DynFlags (
  DynFlags (..),
  GeneralFlag (..),
  GhcLink (..),
  Language (..),
  ModRenaming (..),
  PackageArg (..),
  PackageDBFlag (..),
  PackageFlag (..),
  PkgDbRef (..),
  gopt_set,
  gopt_unset,
  lang_set,
  xopt_set,
  xopt_unset,
  )
import GHC.Driver.Session (updOptLevel)
import qualified GHC.LanguageExtensions as LangExt
import GHC.Platform.Ways (Way (..), addWay, wayGeneralFlags, wayUnsetGeneralFlags)
import GHC.Unit.Types (stringToUnit, stringToUnitId)
import GHC.Utils.CliOption (Option (..))

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
  <|> noArgFlag "-fwrite-ide-info" (gopt_set `flip` Opt_WriteHie)
  <|> noArgFlag "-fexternal-dynamic-refs" (gopt_set `flip` Opt_ExternalDynamicRefs)
  <|> noArgFlag "-fpackage-db-byte-code" id
  <|> noArgFlag "-prof" addWayProf
  <|> noArgFlag "-haddock" (gopt_set `flip` Opt_Haddock)
  <|> noArgFlag "-i" (\d -> d {importPaths = []})
  <|> noArgFlag "-Werror" (gopt_set `flip` Opt_WarnIsError)
  <|> noArgFlag "-fdefer-diagnostics" (gopt_set `flip` Opt_DeferDiagnostics)
  <|> extensionFlag
  <|> optimizationFlag
  <|> warningFlag
  <|> prefixLFlag
  <|> prefixlFlag
  <|> eqArgFlag "-fdiagnostics-color" (\_v d -> d)
  <|> oneArgFlag "-osuf" (\v d -> d {objectSuf_ = v})
  <|> oneArgFlag "-hisuf" (\v d -> d {hiSuf_ = v})
  <|> oneArgFlag "-odir" (\v d -> d {objectDir = Just v})
  <|> oneArgFlag "-hidir" (\v d -> d {hiDir = Just v})
  <|> oneArgFlag "-stubdir" (\v d -> d {stubDir = Just v})
  <|> oneArgFlag "-hiedir" (\_v d -> d)
  <|> oneArgFlag "-dumpdir" (\_v d -> d)
  <|> oneArgFlag "-this-unit-id" (\v d -> d {homeUnitId_ = stringToUnitId v})
  <|> noArgFlag "-j" id
  <|> eqArgFlag "-package-env" (\_v d -> d)
  <|> oneArgFlag "-dep-makefile" (\_v d -> d)
  <|> oneArgFlag "-dep-json" (\_v d -> d)
  <|> oneArgFlag "-main-is" (\v d -> d {mainFunIs = Just v})
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

-- | Match a flag with an inline @=value@ argument on the same line.
eqArgFlag :: ByteString -> (String -> DynFlags -> DynFlags) -> Parser () Flag
eqArgFlag name f = do
  byteString name
  byteString "="
  val <- byteStringOf takeRest
  pure (FlagNoArg (f (B8.unpack val)))
{-# inline eqArgFlag #-}

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
-- | Add 'WayProf' to the target ways and apply associated general flag changes.
addWayProf :: DynFlags -> DynFlags
addWayProf dflags =
  let platform = targetPlatform dflags
      dflags1 = dflags {targetWays_ = addWay WayProf (targetWays_ dflags)}
      dflags2 = foldl' gopt_set dflags1 (wayGeneralFlags platform WayProf)
      dflags3 = foldl' gopt_unset dflags2 (wayUnsetGeneralFlags platform WayProf)
  in dflags3

-- | Map from extension name to 'LangExt.Extension', built from all
-- constructors via 'Bounded'/'Enum'.
extensionMap :: Map.Map ByteString LangExt.Extension
extensionMap =
  Map.fromList [(B8.pack (show ext), ext) | ext <- [minBound .. maxBound]]

-- | Map from language name to 'Language'.
languageMap :: Map.Map ByteString Language
languageMap =
  Map.fromList [(B8.pack (show lang), lang) | lang <- [minBound .. maxBound]]

-- | Parse @-X@ extension and language flags.
--
-- Handles @-X\<Name\>@ (enable), @-XNo\<Name\>@ (disable), and language
-- standards like @-XHaskell2010@.
extensionFlag :: Parser () Flag
extensionFlag = do
  byteString "-X"
  name <- byteStringOf takeRest
  case Map.lookup name languageMap of
    Just lang -> pure (FlagNoArg (\d -> lang_set d (Just lang)))
    Nothing
      | Just noName <- B8.stripPrefix "No" name
      , Just ext <- Map.lookup noName extensionMap ->
        pure (FlagNoArg (\d -> xopt_unset d ext))
      | Just ext <- Map.lookup name extensionMap ->
        pure (FlagNoArg (\d -> xopt_set d ext))
      | otherwise ->
        error ("Internal.FastDynFlags: unknown extension: " ++ B8.unpack name)

-- | Parse @-O@ optimization level flags.
--
-- Uses 'updOptLevel' from @GHC.Driver.Session@ to set the appropriate
-- general flags and LLVM opt level.
optimizationFlag :: Parser () Flag
optimizationFlag =
  noArgFlag "-O0" (updOptLevel 0)
  <|> noArgFlag "-O1" (updOptLevel 1)
  <|> noArgFlag "-O2" (updOptLevel 2)
  <|> noArgFlag "-O" (updOptLevel 1)

-- | Parse warning-related flags as no-ops.
--
-- Warnings do not affect code generation, so these are accepted but ignored.
-- @-Werror@ is handled separately above as it sets 'Opt_WarnIsError'.
-- Covers @-Weverything@, @-W\<name\>@, @-Wno-\<name\>@,
-- @-fwarn-\<name\>@, and @-fno-warn-\<name\>@.
warningFlag :: Parser () Flag
warningFlag =
  prefixed "-W" <|> prefixed "-fwarn-" <|> prefixed "-fno-warn-"
  where
    prefixed p = FlagNoArg id <$ (byteString p *> takeRest *> eof)

-- | Parse @-L\<path\>@ library search path flags.
prefixLFlag :: Parser () Flag
prefixLFlag = do
  byteString "-L"
  path <- byteStringOf takeRest
  pure (FlagNoArg (\d -> d {libraryPaths = libraryPaths d ++ [B8.unpack path]}))

-- | Parse @-l\<lib\>@ link library flags.
prefixlFlag :: Parser () Flag
prefixlFlag = do
  byteString "-l"
  lib <- byteStringOf takeRest
  pure (FlagNoArg (\d -> d {ldInputs = ldInputs d ++ [Option ("-l" ++ B8.unpack lib)]}))
