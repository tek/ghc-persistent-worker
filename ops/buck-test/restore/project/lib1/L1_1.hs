{-# language TemplateHaskell #-}

module L1_1 where

import Dep2

l1_1 :: Int
l1_1 = 1 + $(dep2_1)
