{-# LANGUAGE Safe #-}
{-@ LIQUID "--reflection" @-}
{-@ LIQUID "--ple" @-}
-- | The upload resource's state: the chunks the store acknowledged durable,
-- the length, and completion. The offset is a measure of the chunks, never a
-- field, so it can't disagree with what the store acknowledged.
module Funknown.Upload
  ( Limits (..)
  , ChunkToken (..)
  , Chunk (..)
  , Chunks
  , limitsOf, chunkList, offsetOf, nChunks, lastBytes, room
  , total, older, headBytes, allAtMost, allAtLeast, olderAtLeast
  , emptyChunks
  , appendChunk
  , canAppend
  , Upload (..)
  , upOffset, upLen, upComplete, upChunks
  ) where

import Funknown.Opt

-- | What the store and the plan allow, fixed at creation and never changed
-- (P UP:RESUMABLE-UPLOAD-13-4.1.4-8 .. -11, PM17). This record is the only
-- place these numbers live: the Upload-Limit a client is told is rendered from
-- it, and 'appendChunk' checks against it, so the two can't diverge.
data Limits = Limits
  { minChunk   :: Int    -- ^ every chunk but the last has at least this many bytes
  , maxChunk   :: Int    -- ^ no chunk has more
  , maxChunks  :: Int    -- ^ the most chunks one seal can name
  , maxSize    :: Int    -- ^ the plan's max-size
  , sealsEmpty :: Bool   -- ^ whether the store can seal zero chunks
  } deriving (Eq, Show)
{-@ data Limits = Limits
      { minChunk   :: {v:Int | v >= 1}
      , maxChunk   :: {v:Int | v >= minChunk}
      , maxChunks  :: {v:Int | v >= 1}
      , maxSize    :: Nat
      , sealsEmpty :: Bool } @-}

-- | Opaque; built only by an adapter from whatever the store hands back for a
-- durable chunk. The seal names every chunk's token, so a late duplicate write
-- of a chunk can't be sealed in place of the write the core acknowledged.
newtype ChunkToken = ChunkToken [Char]
  deriving (Eq, Show)

data Chunk = Chunk { cbytes :: Int, ctoken :: ChunkToken }
  deriving (Eq, Show)
{-@ data Chunk = Chunk { cbytes :: {v:Int | v >= 1}, ctoken :: ChunkToken } @-}

{-@ measure total @-}
{-@ total :: [Chunk] -> Nat @-}
total :: [Chunk] -> Int
total []       = 0
total (c : cs) = cbytes c + total cs

{-@ measure headBytes @-}
headBytes :: [Chunk] -> Int
headBytes []      = 0
headBytes (c : _) = cbytes c

{-@ measure older @-}
older :: [Chunk] -> [Chunk]
older []       = []
older (_ : cs) = cs

{-@ reflect allAtMost @-}
allAtMost :: Int -> [Chunk] -> Bool
allAtMost _ []       = True
allAtMost m (c : cs) = cbytes c <= m && allAtMost m cs

-- | Every chunk but the newest has at least m bytes.
{-@ reflect olderAtLeast @-}
olderAtLeast :: Int -> [Chunk] -> Bool
olderAtLeast _ []       = True
olderAtLeast m (_ : cs) = allAtLeast m cs

{-@ reflect allAtLeast @-}
allAtLeast :: Int -> [Chunk] -> Bool
allAtLeast _ []       = True
allAtLeast m (c : cs) = cbytes c >= m && allAtLeast m cs

-- | Newest chunk first. Every chunk is within the chunk-size bounds, except
-- that only the newest may be short, the count is within the cap, and the
-- total is within max-size.
data Chunks = Chunks Limits [Chunk]
{-@ data Chunks = Chunks
      { limitsF :: Limits
      , listF   :: {l:[Chunk] | total l <= maxSize limitsF && len l <= maxChunks limitsF
                               && allAtMost (maxChunk limitsF) l
                               && olderAtLeast (minChunk limitsF) l} } @-}

{-@ measure limitsOf @-}
limitsOf :: Chunks -> Limits
limitsOf (Chunks lim _) = lim

{-@ measure chunkList @-}
chunkList :: Chunks -> [Chunk]
chunkList (Chunks _ l) = l

{-@ measure offsetOf @-}
{-@ offsetOf :: Chunks -> Nat @-}
offsetOf :: Chunks -> Int
offsetOf (Chunks _ l) = total l

{-@ measure nChunks @-}
{-@ nChunks :: Chunks -> Nat @-}
nChunks :: Chunks -> Int
nChunks (Chunks _ l) = len' l

-- | How many more chunks the cap allows. Defined on the constructor, so the
-- cap's field refinement makes it a natural number.
{-@ measure room @-}
{-@ room :: Chunks -> Nat @-}
room :: Chunks -> Int
room (Chunks lim l) = maxChunks lim - len' l

{-@ measure lastBytes @-}
lastBytes :: Chunks -> Int
lastBytes (Chunks _ l) = headBytes l

-- 'len' clashes with LiquidHaskell's list measure (rule 10), so the count
-- goes through a measure of our own that the logic equates with it.
{-@ measure len' @-}
{-@ len' :: l:[a] -> {v:Nat | v == len l} @-}
len' :: [a] -> Int
len' []       = 0
len' (_ : xs) = 1 + len' xs

{-@ emptyChunks :: lim:Limits -> {c:Chunks | offsetOf c == 0 && nChunks c == 0 && limitsOf c == lim} @-}
emptyChunks :: Limits -> Chunks
emptyChunks lim@(Limits _ _ _ _ _) = Chunks lim []

-- | Whether a chunk of n bytes may be appended: within the chunk size, within
-- max-size and the cap, and the newest chunk so far is not a short one.
{-@ reflect canAppend @-}
canAppend :: Chunks -> Int -> Bool
canAppend (Chunks lim l) n =
  1 <= n && n <= maxChunk lim
    && total l + n <= maxSize lim
    && len' l < maxChunks lim
    && (len' l == 0 || headBytes l >= minChunk lim)

{-@ appendChunk :: x:Chunks -> c:{Chunk | canAppend x (cbytes c)}
                -> {y:Chunks | offsetOf y == offsetOf x + cbytes c && nChunks y == nChunks x + 1
                              && limitsOf y == limitsOf x && lastBytes y == cbytes c
                              && room y == room x - 1} @-}
appendChunk :: Chunks -> Chunk -> Chunks
-- The case split lets PLE unfold 'allAtLeast' on the list that becomes older.
appendChunk (Chunks lim [])      c = Chunks lim [c]
appendChunk (Chunks lim (h : t)) c = Chunks lim (c : h : t)

-- | The upload resource. Length and completion invariants are data
-- refinements (R UP:RESUMABLE-UPLOAD-13-4.4.2-7, 13-4.1.3-1); completion is
-- set only by an explicit event, never from offset == length
-- (R UP:RESUMABLE-UPLOAD-13-4.1.3-8).
data Upload = Upload { chunks :: Chunks, uploadLen :: Len, complete :: Bool }
{-@ data Upload = Upload
      { chunks    :: Chunks
      , uploadLen :: {l:Len  | isKnown l => (offsetOf chunks <= lenOr l && lenOr l <= maxSize (limitsOf chunks))}
      , complete  :: {c:Bool | c => (isKnown uploadLen && lenOr uploadLen == offsetOf chunks)} } @-}

{-@ measure upOffset @-}
{-@ upOffset :: Upload -> Nat @-}
upOffset :: Upload -> Int
upOffset (Upload c _ _) = offsetOf c

{-@ measure upLen @-}
upLen :: Upload -> Len
upLen (Upload _ l _) = l

{-@ measure upComplete @-}
upComplete :: Upload -> Bool
upComplete (Upload _ _ c) = c

{-@ measure upChunks @-}
upChunks :: Upload -> Chunks
upChunks (Upload c _ _) = c
