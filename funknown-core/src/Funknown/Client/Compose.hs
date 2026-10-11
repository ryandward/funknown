{-# LANGUAGE Safe #-}
-- | Why convergence carries over from the kernel to the composed system.
--
-- I didn't state this as "a KMove step is a list of the adversary's moves",
-- because it isn't one: starting a write has no adversary move, a write's
-- report removes its entry wherever it sits while Lapse only drops the
-- head, and KMove bounds the goal's rank and offset without naming the
-- chunk appended. What 'converge' actually consumes from a move is that the
-- asset stays coherent with the store model and that its metric
-- (rank, drop allowance, budget, unreported writes, gap, not yet observed)
-- goes down, so 'kmoveMetric' proves the part a client step can honestly
-- promise: coherence with the same model, and a metric that never rises,
-- except for KMove's one write start on an otherwise unchanged assembly.
--
-- A client step issues no store command and drops nothing, so the model
-- and the drop allowance are the same on both sides. The strict decrease
-- comes from the kernel round after the step: 'clientThenRound' and
-- 'stepThenRound' put the lemma next to the kernel's progress lemma, so a
-- client step that starts no persist job, followed by a round, rests or
-- lowers converge's metric. That is kernel.md's claim that between producer
-- actions (the only steps that start a write) the composed system converges.
--
-- The metric counts unreported writes, so a step that drops an entry from
-- 'authorised' scores as progress. That is only honest if the write can no
-- longer land, since converge sees a late landing only through its entry
-- (LateWrite). ClientOut's CWriteKept is what makes it so: an entry leaves
-- only under the epoch of the report the step handles, and a report is its
-- job's last word.
module Funknown.Client.Compose
  ( kmoveMetric
  , clientThenRound
  , Turn (..)
  , stepThenRound
  ) where

import Funknown.Client.Contract ()
import Funknown.Client.Types (Out (..), File, fileAsset, optStartTag)
import Funknown.Client.Step (stepClient)
import qualified Funknown.Client.Types as C
import Funknown.Kernel.Converge ()
import Funknown.Kernel.Model (Model, Round (..), roundWith)
import Funknown.Kernel.Reconcile (reconcile)
import Funknown.Kernel.Types (Asset, Env, isFixedRow, isSeen, rank, goalTag, hasReceipt, goalAdopted)

-- | Converge's metric at (b, n, e) equals the one at (a, m, d), component by
-- component.
{-@ predicate SameMetric A M D B N E =
      rank (goal B) == rank (goal A) && E == D && budget B == budget A
      && len (authorised B) == len (authorised A) && GapA B N == GapA A M
      && isSeen (seen B) == isSeen (seen A) @-}

-- | The one rise KMove allows: a write starts on an assembly that otherwise
-- stays exactly as it was.
{-@ predicate StartsWrite A B =
      goal B == goal A && goalTag (goal A) == 2 && budget B == budget A
      && seen B == seen A && vouch B == vouch A
      && len (authorised B) == len (authorised A) + 1 @-}

-- | A client step against the kernel's metric. The store model and the
-- drop allowance are the same on both sides, because a client step issues
-- no store command and drops nothing.
{-@ kmoveMetric :: a:Asset -> m:{Model | Coherent a m} -> d:Nat -> b:{Asset | KMove a b}
                -> {v:() | Coherent b m
                           && (Smaller a m d b m d || SameMetric a m d b m d || StartsWrite a b)} @-}
kmoveMetric :: Asset -> Model -> Int -> Asset -> ()
kmoveMetric _ _ _ _ = ()

-- | A client step that starts no write, then a kernel round: the round
-- rests, or converge's metric is strictly lower than before the client
-- step, and the asset is coherent with the store again.
{-@ clientThenRound :: env:Env -> a:Asset -> m:{Model | Coherent a m} -> d:Nat
                    -> b:{Asset | KMove a b && len (authorised b) <= len (authorised a)}
                    -> {r:Round | (isFixedRow (rRow r) || Smaller a m d (rAsset r) (rModel r) d)
                                  && Coherent (rAsset r) (rModel r)} @-}
clientThenRound :: Env -> Asset -> Model -> Int -> Asset -> Round
clientThenRound env a m d b = case kmoveMetric a m d b of
  () -> roundWith b m (reconcile env b)

-- | One client step and the kernel round after it.
data Turn = Turn { turnOut :: Out, turnRound :: Round }
{-@ data Turn = Turn { turnOut :: Out, turnRound :: Round } @-}

-- | The dispatcher's step, then a kernel round on the asset it left. Unless
-- the step started a persist job (CWriteJob: the only way 'authorised'
-- grows), the round rests or converge's metric is strictly lower than it
-- was before the step.
{-@ stepThenRound :: kenv:Env -> env:C.Env -> ev:C.Event -> f:File -> m:{Model | Coherent (fileAsset f) m} -> d:Nat
                  -> {t:Turn | Coherent (rAsset (turnRound t)) (rModel (turnRound t))
                               && (optStartTag (started (turnOut t)) /= 2
                                     => (isFixedRow (rRow (turnRound t))
                                         || Smaller (fileAsset f) m d (rAsset (turnRound t)) (rModel (turnRound t)) d))} @-}
stepThenRound :: Env -> C.Env -> C.Event -> File -> Model -> Int -> Turn
stepThenRound kenv env ev f m d =
  let o = stepClient env ev f
      b = fileAsset (after o)
  in case kmoveMetric (fileAsset f) m d b of
       () -> Turn o (roundWith b m (reconcile kenv b))
