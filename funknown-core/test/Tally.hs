-- | Which Event constructors a run of a suite actually stepped, so the
-- dispatch suite can say that every constructor reached the dispatcher and
-- not just that every case it happened to run came out right.
module Tally (Tally, newTally, record, kindsSeen, eventKind, eventKinds, kindName) where

import Data.IORef
import Data.List (sort)

import Funknown.Client.Types (Event (..))

newtype Tally = Tally (IORef [Int])

newTally :: IO Tally
newTally = Tally <$> newIORef []

record :: Tally -> Event -> IO ()
record (Tally r) ev = modifyIORef' r (\ks -> let k = eventKind ev in if k `elem` ks then ks else k : ks)

kindsSeen :: Tally -> IO [Int]
kindsSeen (Tally r) = sort <$> readIORef r

-- | The constructor, in declaration order. The match has no wildcard, so a
-- new constructor fails this module's build (-Werror=incomplete-patterns)
-- until it is named here and 'eventKinds' counts it.
eventKind :: Event -> Int
eventKind ev = case ev of
  Append _           -> 0
  OffsetQuery _      -> 1
  CancelUpload _     -> 2
  CancelOperation _  -> 3
  GetOperation _     -> 4
  DeleteOperation _  -> 5
  GetObject _        -> 6
  GetAccessUrl _     -> 7
  GetContent _ _     -> 8
  DeleteFile _ _     -> 9
  BodyReceived _ _   -> 10
  BodyBroken _ _     -> 11
  ChunkPersisted _ _ -> 12
  ChunkFailed _      -> 13
  MoverDied _        -> 14
  KernelMoved        -> 15
  Tick               -> 16

eventKinds :: Int
eventKinds = 17

kindName :: Int -> String
kindName k = case k of
  0 -> "Append"; 1 -> "OffsetQuery"; 2 -> "CancelUpload"; 3 -> "CancelOperation"; 4 -> "GetOperation"
  5 -> "DeleteOperation"; 6 -> "GetObject"; 7 -> "GetAccessUrl"; 8 -> "GetContent"; 9 -> "DeleteFile"
  10 -> "BodyReceived"; 11 -> "BodyBroken"; 12 -> "ChunkPersisted"; 13 -> "ChunkFailed"; 14 -> "MoverDied"
  15 -> "KernelMoved"; 16 -> "Tick"; _ -> "kind " ++ show k
