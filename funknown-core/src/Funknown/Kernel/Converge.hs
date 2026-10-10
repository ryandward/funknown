{-# LANGUAGE Safe #-}
-- | Convergence against every environment the store contract allows.
--
-- A run alternates the reconciler with an adversary's script of moves. The
-- script may be infinite. The adversary may lose a command or an
-- observation, out of a finite drop allowance (fairness, written as a
-- number), land a write the core started and never saw reported, let such a
-- write's deadline pass (A3), or let the producer or a client move the goal
-- (append a chunk, complete, cancel, delete or expire). A move that doesn't
-- apply is an honest round instead.
--
-- 'converge' stops when a round rests (R3, R14, R18, R19). LiquidHaskell's
-- termination checker accepts it with the lexicographic metric
--
--   (rank of the goal, drop allowance, budget, unreported writes, gap, not yet observed)
--
-- and not the length of the script, so no run is infinite, whatever the
-- script: every asset reaches a resting row in finitely many rounds.
module Funknown.Kernel.Converge
  ( Move (..)
  , Run (..)
  , converge
  ) where

import Prelude hiding (round)

import Funknown.Opt
import Funknown.Kernel.Model
import Funknown.Kernel.Reconcile (reconcile)
import Funknown.Kernel.Types
import Funknown.Upload (Chunk (..), ChunkToken, appendChunk, canAppend, room)

data Move
  = Drop                     -- ^ the command or observation of this round is lost
  | LateWrite                -- ^ an unreported write lands, and a staging area reappears
  | Lapse                    -- ^ an unreported write passes its deadline; the shell aborted it
  | Append ChunkToken Int    -- ^ the producer's next chunk is durable
  | Complete                 -- ^ the producer marks the assembly complete
  | Abandon Ending           -- ^ a cancel, a DELETE, or expiry clears the goal

-- | Where a run came to rest.
data Run = Run { runAsset :: Asset, runModel :: Model, runRow :: Row }
{-@ data Run = Run { runAsset :: Asset, runModel :: Model, runRow :: {r:Row | isFixedRow r} } @-}

{-@ predicate GapA A M = gapI (goalTag (goal A)) (goalAdopted (goal A)) (hasReceipt (vouch A))
                              (obsStagings (mObs M)) (obsObjTag (mObs M)) @-}

-- | 1 until the store has been observed, as the metric's last component.
{-@ inline unseenBit @-}
unseenBit :: Bool -> Int
unseenBit seenYet = if seenYet then 0 else 1

-- | The metric, lexicographically smaller.
{-@ predicate Smaller A M D B N E =
      rank (goal B) < rank (goal A)
      || (rank (goal B) == rank (goal A) && E < D)
      || (rank (goal B) == rank (goal A) && E == D && budget B < budget A)
      || (rank (goal B) == rank (goal A) && E == D && budget B == budget A
          && len (authorised B) < len (authorised A))
      || (rank (goal B) == rank (goal A) && E == D && budget B == budget A
          && len (authorised B) == len (authorised A) && GapA B N < GapA A M)
      || (rank (goal B) == rank (goal A) && E == D && budget B == budget A
          && len (authorised B) == len (authorised A) && GapA B N == GapA A M
          && unseenBit (isSeen (seen B)) < unseenBit (isSeen (seen A))) @-}

-- | The state after the adversary's move.
data Next = Next Asset Model Int [Move]
{-@ data Next = Next { nextAsset :: Asset, nextModel :: Model, nextAllowance :: Int, nextMoves :: [Move] } @-}

{-@ converge :: env:Env -> a:Asset -> m:{Model | Coherent a m} -> d:Nat -> [Move] -> Run
              / [rank (goal a), d, budget a, len (authorised a), GapA a m, unseenBit (isSeen (seen a))] @-}
converge :: Env -> Asset -> Model -> Int -> [Move] -> Run
converge env a m d moves = case adversary env a m d moves of
  Present (Next a' m' d' rest) -> case metricNat a' m' of
    () -> converge env a' m' d' rest
  Absent ->
    let r = roundWith a m (reconcile env a)
    in if isFixedRow (rRow r)
         then Run (rAsset r) (rModel r) (rRow r)
         else case metricNat (rAsset r) (rModel r) of
           () -> converge env (rAsset r) (rModel r) d (drop 1 moves)

-- | Every component of the metric is a natural number. The budget's bound
-- is a field refinement, so it is only known once the asset is matched; the
-- gap's comes from counting the staging areas.
{-@ metricNat :: a:Asset -> m:Model
              -> {v:() | budget a >= 0 && rank (goal a) >= 0 && GapA a m >= 0
                         && len (authorised a) >= 0} @-}
metricNat :: Asset -> Model -> ()
metricNat (Asset _ _ s _ _ _ _) (Model (Observed ss _) _ _ _) = case countNat ss of
  () -> case s of
    Unseen -> ()
    Seen _ -> ()

{-@ countNat :: ss:Stagings -> {v:() | nStagings ss >= 0} @-}
countNat :: Stagings -> ()
countNat SNil         = ()
countNat (SCons _ ss) = countNat ss

-- | The adversary's move at the head of the script, if it applies; each one
-- lowers the metric, and leaves the asset's observation either absent or
-- exact, so the progress lemma still applies afterwards.
{-@ adversary :: env:Env -> a:Asset -> m:{Model | Coherent a m} -> d:Nat -> [Move]
              -> Opt {n:Next | Smaller a m d (nextAsset n) (nextModel n) (nextAllowance n)
                               && nextAllowance n >= 0 && Coherent (nextAsset n) (nextModel n)} @-}
adversary :: Env -> Asset -> Model -> Int -> [Move] -> Opt Next
adversary env a m d moves = case moves of
  Drop : rest -> dropped (reconcile env a) m d rest
  LateWrite : rest -> case authorised a of
    _ : ws -> Present (Next (landed a ws) (reappear m) d rest)
    []     -> Absent
  Lapse : rest -> case authorised a of
    _ : ws -> Present (Next (lapsed a ws) m d rest)
    []     -> Absent
  Append tok n : rest -> case appended a tok n of
    Present a' -> Present (Next a' m d rest)
    Absent     -> Absent
  Complete : rest -> case completed a of
    Present a' -> Present (Next a' m d rest)
    Absent     -> Absent
  Abandon e : rest -> case abandoned a e of
    Present a' -> Present (Next a' m d rest)
    Absent     -> Absent
  _ -> Absent

-- The adversary's moves on the asset and the model --------------------------------

-- | The round's command or observation is lost. Only a round that issues
-- something can lose it, and only while the allowance lasts.
{-@ dropped :: d':Decision -> m:Model -> d:Nat -> [Move]
            -> Opt {n:Next | (cmdTag (command d') >= 1 && d > 0 && nextAsset n == next d' && nextModel n == m
                              && nextAllowance n == d - 1)} @-}
dropped :: Decision -> Model -> Int -> [Move] -> Opt Next
dropped dec m d rest
  | d > 0 && cmdTag (command dec) >= 1 = Present (Next (next dec) m (d - 1) rest)
  | otherwise                          = Absent

-- | A late write lands: one fewer unreported write, the store shows a staging
-- area again, and the asset's observation is out of date.
{-@ landed :: a:Asset -> ws:{[Write] | len ws + 1 == len (authorised a)}
           -> {b:Asset | goal b == goal a && budget b == budget a && vouch b == vouch a
                        && len (authorised b) < len (authorised a) && not (isSeen (seen b))} @-}
landed :: Asset -> [Write] -> Asset
landed (Asset g o _ v b st _) ws = Asset g o Unseen v b st ws

{-@ reappear :: Model -> Model @-}
reappear :: Model -> Model
reappear (Model (Observed ss o) fr v vc) = Model (Observed (SCons (Staging fr []) ss) o) fr v vc

-- | A write's deadline passes: one fewer unreported write, nothing else.
{-@ lapsed :: a:Asset -> ws:{[Write] | len ws + 1 == len (authorised a)}
           -> {b:Asset | goal b == goal a && budget b == budget a && vouch b == vouch a && seen b == seen a
                        && len (authorised b) < len (authorised a)} @-}
lapsed :: Asset -> [Write] -> Asset
lapsed (Asset g o s v b st _) ws = Asset g o s v b st ws

-- | The producer's next chunk, when the assembly accepts it: the goal's rank
-- drops by one, because the cap leaves room for one fewer chunk.
{-@ appended :: a:Asset -> ChunkToken -> Int
             -> {o:Opt {b:Asset | rank (goal b) < rank (goal a) && seen b == seen a}
                | true} @-}
appended :: Asset -> ChunkToken -> Int -> Opt Asset
appended (Asset (Keep (Assembling r c)) o s v b st w) tok n
  | n >= 1 && canAppend c n = Present (Asset (Keep (Assembling r (appendChunk c (Chunk n tok)))) o s v b st w)
appended _ _ _ = Absent

-- | The producer completes an assembly that has a staging area.
{-@ completed :: a:Asset -> {o:Opt {b:Asset | rank (goal b) < rank (goal a) && seen b == seen a} | true} @-}
completed :: Asset -> Opt Asset
completed (Asset (Keep (Assembling (Present r) c)) o s v b st w) = Present (Asset (Keep (Assembled r c)) o s v b st w)
completed _ = Absent

-- | A cancel, a DELETE or expiry clears a goal that still keeps the asset.
{-@ abandoned :: a:Asset -> Ending -> {o:Opt {b:Asset | rank (goal b) < rank (goal a) && seen b == seen a} | true} @-}
abandoned :: Asset -> Ending -> Opt Asset
abandoned (Asset (Keep _) _ s v b st w) e = Present (Asset Clear (Ended e) s v b st w)
abandoned _ _ = Absent
