{-# language TemplateHaskell #-}

module M3 where

import Dep1
import Hybrid.M1

m2 :: Int
m2 = 1 + 0 + $(m1) + 0 + $(dep1_1)

use :: String
use = $(runThExe)
