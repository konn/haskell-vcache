
-- This is the hash function for content addressing.
module Database.VCache.Hash
    (
      hashVal
    ) where

import Data.Hashable
import qualified Data.ByteString.Internal as BSI
import Foreign.ForeignPtr

import Database.LMDB.Raw (MDB_val(..))


hashVal :: MDB_val -> IO Int
hashVal mv = do
    fp <- newForeignPtr_ (mv_data mv) -- no finalizer
    let bs = BSI.PS fp 0 (fromIntegral (mv_size mv))
    return $! hash bs
