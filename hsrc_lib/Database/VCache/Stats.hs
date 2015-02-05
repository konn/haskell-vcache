
module Database.VCache.Stats
    ( VCacheStats(..)
    , vcacheStats
    ) where

import Database.LMDB.Raw
import Database.VCache.Types
import Data.IORef
import qualified Data.Map.Strict as Map


-- | Miscellaneous statistics for a VCache instance. These are not
-- necessarily consistent, current, or useful. But they can say a
-- a bit about the liveliness and health of a VCache system.
data VCacheStats = VCacheStats
        { vcstat_file_size      :: {-# UNPACK #-} !Int  -- ^ estimated database file size (in bytes)
        , vcstat_vref_count     :: {-# UNPACK #-} !Int  -- ^ number of immutable values in the database
        , vcstat_pvar_count     :: {-# UNPACK #-} !Int  -- ^ number of mutable PVars in the database
        , vcstat_root_count     :: {-# UNPACK #-} !Int  -- ^ number of named roots (a subset of PVars)
        , vcstat_mem_vref       :: {-# UNPACK #-} !Int  -- ^ number of VRefs in Haskell process memory
        , vcstat_mem_pvar       :: {-# UNPACK #-} !Int  -- ^ number of PVars in Haskell process memory
        , vcstat_alloc_pos      :: {-# UNPACK #-} !Address -- ^ address to next be used by allocator
        , vcstat_alloc_count    :: {-# UNPACK #-} !Int  -- ^ number of allocations by this process 
        , vcstat_gc_count       :: {-# UNPACK #-} !Int  -- ^ number of addresses GC'd by this process
        , vcstat_cache_target   :: {-# UNPACK #-} !Int  -- ^ target VRef-layer cache size (in bytes)
        , vcstat_cache_size     :: {-# UNPACK #-} !Int  -- ^ estimated VRef-layer cache size (in bytes)
        , vcstat_write_pvars    :: {-# UNPACK #-} !Int  -- ^ number of PVar updates to disk (after batching)
        , vcstat_write_sync     :: {-# UNPACK #-} !Int  -- ^ number of sync requests (~ durable transactions)
        , vcstat_write_frames   :: {-# UNPACK #-} !Int  -- ^ number of LMDB-layer transactions by this process
        } deriving (Show, Ord, Eq)

-- | Compute some miscellaneous statistics for a VCache instance at
-- runtime. These aren't really useful for anything, except to gain
-- some confidence about activity or comprehension of performance. 
vcacheStats :: VCache -> IO VCacheStats
vcacheStats (VCache vc _) = withRdOnlyTxn vc $ \ txnStat -> do
    let db = vcache_db_env vc
    envInfo <- mdb_env_info db
    envStat <- mdb_env_stat db
    memStat <- mdb_stat' txnStat (vcache_db_memory vc)
    rootStat <- mdb_stat' txnStat (vcache_db_vroots vc)
    hashStat <- mdb_stat' txnStat (vcache_db_caddrs vc)
    allocator <- readIORef (vcache_allocator vc)
    collector <- readIORef (vcache_collector vc)
    cTgtLim <- readIORef (vcache_c_limit vc)
    cSize <- readIORef (vcache_c_size vc)
    gcCount <- readIORef (vcache_gc_count vc)
    wct <- readIORef (vcache_ct_writes vc)
    let fileSize = (1 + (fromIntegral $ me_last_pgno envInfo)) 
                 * (fromIntegral $ ms_psize envStat)
    let vrefCount = (fromIntegral $ ms_entries hashStat) 
    let pvarCount = (fromIntegral $ ms_entries memStat) - vrefCount
    let rootCount = (fromIntegral $ ms_entries rootStat)
    let memVRefsMap = c_mem_vrefs collector
    let memPVarsMap = c_mem_pvars collector
    let memVRefsCount = Map.foldl' (\ a b -> a + Map.size b) 0 memVRefsMap
    let memPVarsCount = Map.size memPVarsMap
    let allocPos = alloc_new_addr allocator
    let allocCount = fromIntegral $ (allocPos - vcache_alloc_init vc) `div` 2
    return $ VCacheStats
        { vcstat_file_size = fileSize
        , vcstat_vref_count = vrefCount
        , vcstat_pvar_count = pvarCount
        , vcstat_root_count = rootCount
        , vcstat_mem_vref = memVRefsCount
        , vcstat_mem_pvar = memPVarsCount
        , vcstat_alloc_pos = allocPos
        , vcstat_alloc_count = allocCount
        , vcstat_cache_target = cTgtLim
        , vcstat_cache_size = cSize
        , vcstat_write_sync = wct_sync wct
        , vcstat_write_pvars = wct_pvars wct
        , vcstat_write_frames = wct_frames wct
        , vcstat_gc_count = gcCount
        }

