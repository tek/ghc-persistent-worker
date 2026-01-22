{-# language TemplateHaskell #-}

module L2 where

import Data.UUID
import L1

l2 :: UUID
l2 = $(l1_uuid)
