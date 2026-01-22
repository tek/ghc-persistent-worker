{-# language MagicHash, UnliftedFFITypes #-}

module L1 where

import Control.Monad.Primitive
import Data.Functor (void)
import Data.Primitive.ByteArray
import Data.UUID.Types.Internal (UUID (..))
import Data.Word
import Language.Haskell.TH
import Language.Haskell.TH.Syntax

l1_uuid :: ExpQ
l1_uuid = do
  u <- runIO $ getRawV1UUID (void . pure)
  lift u

getRawV1UUID :: (MutableByteArray (PrimState IO) -> IO ()) -> IO UUID
getRawV1UUID setBytes = do
  safeBuf@(MutableByteArray buf) <- newPinnedByteArray uuidSize
  -- Make the FFI call to populate the value
  uuid_generate_time buf
  -- Make any required edits
  setBytes safeBuf
  -- Read the UUID out
  unsafeReadUUIDFromByteArray safeBuf
  where
    uuidSize :: Int
    uuidSize = 16

unsafeReadUUIDFromByteArray :: MutableByteArray (PrimState IO) -> IO UUID
unsafeReadUUIDFromByteArray buf = do
  -- Pull out the two underlying values
  !w0 <- fmap byteSwap64 $ readByteArray buf 0
  !w1 <- fmap byteSwap64 $ readByteArray buf 1
  -- Return a constructed UUID value
  pure $! UUID w0 w1

foreign import ccall safe "uuid_generate_time"
  uuid_generate_time :: MutableByteArray# s -> IO ()
