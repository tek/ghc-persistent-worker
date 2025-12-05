{-# OPTIONS_GHC -Wno-orphans #-}
{-# LANGUAGE CPP, DeriveAnyClass #-}

module Internal.GHC.Orphans where

import Control.DeepSeq (NFData (..))
import GHC.Driver.Session (PackageArg (..))
import GHC.Generics (Generic)
import GHC.Types.Unique.FM (UniqFM, seqEltsUFM)
import GHC.Unit (
  GenericUnitInfo (..),
  ModuleOrigin (..),
  PackageId (..),
  PackageName (..),
  UnitId (..),
  UnitState,
  UnitVisibility (..),
  UnusableUnit (..),
  UnusableUnitReason (..),
  )
import GHC.Unit.State (UnitState (..))

#if !defined(MWB)
import GHC.Types.Unique.Set (UniqSet, getUniqSet)
#endif

deriving stock instance Generic UnusableUnitReason
instance NFData UnusableUnitReason

deriving stock instance Generic UnusableUnit
instance NFData UnusableUnit

deriving stock instance Generic UnitVisibility
instance NFData UnitVisibility

deriving stock instance Generic (GenericUnitInfo srcpkgid srcpkgname uid modulename mod)

deriving anyclass instance (
  NFData srcpkgid,
  NFData srcpkgname,
  NFData uid,
  NFData modulename,
  NFData mod
  ) => NFData (GenericUnitInfo srcpkgid srcpkgname uid modulename mod)

deriving newtype instance NFData PackageId
deriving newtype instance NFData PackageName
deriving newtype instance NFData UnitId

deriving stock instance Generic ModuleOrigin
deriving anyclass instance NFData ModuleOrigin

deriving stock instance Generic UnitState

deriving anyclass instance NFData UnitState

instance NFData a => NFData (UniqFM k a) where
  rnf fm = seqEltsUFM rnf fm

#if !defined(MWB)
instance NFData a => NFData (UniqSet a) where
  rnf fm = seqEltsUFM rnf (getUniqSet fm)
#endif

deriving stock instance Generic PackageArg
deriving anyclass instance NFData PackageArg
