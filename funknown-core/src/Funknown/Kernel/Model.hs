{-# LANGUAGE Safe #-}
-- | The store contract as a pure function, and the progress lemma: against
-- a store that does what the contract says, every round of the reconciler
-- (decide, perform the command, observe) either rests or strictly lowers
-- the metric (goal rank, budget, gap, not yet observed), lexicographically.
-- Step 3 adds an adversary that may drop, fail or delay commands and land
-- late writes; this module is the honest store it deviates from.
module Funknown.Kernel.Model
  ( Model (..)
  , perform
  , observeInto
  , Round (..)
  , round
  , roundWith
  , dropRef
  ) where

import Prelude hiding (round)

import Funknown.Kernel.Bound (Version)
import Funknown.Kernel.Reconcile (reconcile)
import Funknown.Kernel.Types

-- | What the store holds for one file: the staging areas and the object, as
-- an observation would show them (discovery, contract rule 1), plus the
-- names the store will give the next staging area and the next sealed
-- object, and how it will vouch for that object.
data Model = Model { mObs :: Observed, mFresh :: StagingRef, mVersion :: Version, mVouching :: Vouching }
{-@ data Model = Model { mObs :: Observed, mFresh :: StagingRef, mVersion :: Version, mVouching :: Vouching } @-}

-- | Remove every staging area named r: a Discard, or a seal consuming it.
{-@ dropRef :: r:StagingRef -> ss:Stagings
            -> {t:Stagings | nStagings t <= nStagings ss
                            && (Set_mem r (refSet ss) => nStagings t < nStagings ss)} @-}
dropRef :: StagingRef -> Stagings -> Stagings
dropRef _ SNil = SNil
dropRef r (SCons st@(Staging r' _) ss)
  | r == r'   = dropRef r ss
  | otherwise = SCons st (dropRef r ss)

-- | The contract, command by command:
--
-- * Open creates a staging area, discoverable under the file's id;
-- * Seal makes the goal's staging area the object, create-only (rule 2), and
--   a successful seal consumes the staging area;
-- * Discard removes the staging area it names, idempotently, and like Open
--   it leaves the object alone;
-- * Remove removes the object only at the version it names (rule 2);
-- * Observe and no command change nothing.
{-@ perform :: g:Goal -> c:Cmd -> m:Model
            -> {m':Model |
                   (cmdTag c <= 1 => mObs m' == mObs m)
                && (cmdTag c == 2 => (obsStagings (mObs m') == obsStagings (mObs m) + 1
                                      && obsObjTag (mObs m') == obsObjTag (mObs m)))
                && ((cmdTag c == 3 && goalTag g == 1 && obsObjTag (mObs m) == 0
                     && Set_mem (assembledRef g) (obsRefs (mObs m)))
                      => (obsStagings (mObs m') < obsStagings (mObs m) && obsObjTag (mObs m') /= 0))
                && ((cmdTag c == 4 && Set_mem (discardRef c) (obsRefs (mObs m)))
                      => (obsStagings (mObs m') < obsStagings (mObs m) && obsObjTag (mObs m') == obsObjTag (mObs m)))
                && ((cmdTag c == 5 && obsObjTag (mObs m) /= 0 && removeVersion c == obsVersion (mObs m))
                      => (obsStagings (mObs m') == obsStagings (mObs m) && obsObjTag (mObs m') == 0))
                && ((cmdTag c == 2 || cmdTag c == 4)
                      => (obsObjTag (mObs m') == obsObjTag (mObs m) && obsVersion (mObs m') == obsVersion (mObs m))) } @-}
perform :: Goal -> Cmd -> Model -> Model
perform _ NoCmd m = m
perform _ DoObserve m = m
perform _ DoOpen (Model (Observed ss o) fr v vc) = Model (Observed (SCons (Staging fr []) ss) o) fr v vc
perform g DoSeal m@(Model (Observed ss o) fr v vc) = case (g, o) of
  (Keep (Assembled r _), NoObject) -> Model (Observed (dropRef r ss) (HasObject v vc)) fr v vc
  _                                -> m
perform _ (DoDiscard r) (Model (Observed ss o) fr v vc) = Model (Observed (dropRef r ss) o) fr v vc
perform _ (DoRemove v') m@(Model (Observed ss o) fr v vc) = case o of
  HasObject ov _ | ov == v' -> Model (Observed ss NoObject) fr v vc
  _                         -> m

-- | The next observation: the asset sees exactly what the store holds.
{-@ observeInto :: a:Asset -> m:Model
                -> {b:Asset | goal b == goal a && vouch b == vouch a && budget b == budget a
                             && outcome b == outcome a && authorised b == authorised a
                             && isSeen (seen b) && seenStagings (seen b) == obsStagings (mObs m)
                             && seenObjTag (seen b) == obsObjTag (mObs m)
                             && seenRefs (seen b) == obsRefs (mObs m)
                             && seenVersion (seen b) == obsVersion (mObs m)} @-}
observeInto :: Asset -> Model -> Asset
observeInto (Asset g o _ v b st w) m = Asset g o (Seen (mObs m)) v b st w

data Round = Round { rAsset :: Asset, rModel :: Model, rRow :: Row }
{-@ data Round = Round { rAsset :: Asset, rModel :: Model, rRow :: Row } @-}

-- The metric, lexicographic: the goal's rank, then the budget, then the gap
-- measured against the store, then whether the store has been observed.
{-@ predicate GapM A M = gapI (goalTag (goal A)) (goalAdopted (goal A)) (hasReceipt (vouch A))
                              (obsStagings (mObs M)) (obsObjTag (mObs M)) @-}
{-@ predicate Lower A M B N =
      rank (goal B) < rank (goal A)
      || (rank (goal B) == rank (goal A) && budget B < budget A)
      || (rank (goal B) == rank (goal A) && budget B == budget A && GapM B N < GapM A M)
      || (rank (goal B) == rank (goal A) && budget B == budget A && GapM B N == GapM A M
          && not (isSeen (seen A)) && isSeen (seen B)) @-}

{-@ predicate Coherent A M =
      isSeen (seen A)
        => (seenStagings (seen A) == obsStagings (mObs M) && seenObjTag (seen A) == obsObjTag (mObs M)
            && seenRefs (seen A) == obsRefs (mObs M) && seenVersion (seen A) == obsVersion (mObs M)) @-}

-- | Progress: the asset's last observation is either absent or exactly what
-- the store holds, as it is after every round; then one round either rests
-- or lowers the metric, and it leaves the asset's observation exact again.
{-@ round :: Env -> a:Asset -> m:{Model | Coherent a m}
          -> {r:Round | (isFixedRow (rRow r) || Lower a m (rAsset r) (rModel r))
                       && Coherent (rAsset r) (rModel r) && isSeen (seen (rAsset r))} @-}
round :: Env -> Asset -> Model -> Round
round env a m = roundWith a m (reconcile env a)

-- | The round for any decision with the reconciler's guarantees, so the
-- lemma rests on 'Step' alone and not on how 'reconcile' reached it. A
-- store command never rests: it always lowers the metric, so a shell that
-- loses only the command's answer still holds a lower state (see
-- "Funknown.Kernel.Inputs").
{-@ roundWith :: a:Asset -> m:{Model | Coherent a m} -> d:Step a
              -> {r:Round | (isFixedRow (rRow r) || Lower a m (rAsset r) (rModel r))
                           && (cmdTag (command d) >= 2 => Lower a m (rAsset r) (rModel r))
                           && ((cmdTag (command d) /= 3 && cmdTag (command d) /= 5)
                                 => (obsObjTag (mObs (rModel r)) == obsObjTag (mObs m)
                                     && obsVersion (mObs (rModel r)) == obsVersion (mObs m)))
                           && Coherent (rAsset r) (rModel r) && isSeen (seen (rAsset r))
                           && goal (rAsset r) == goal (next d) && vouch (rAsset r) == vouch (next d)
                           && budget (rAsset r) == budget (next d)
                           && authorised (rAsset r) == authorised a && rRow r == row d
                           && (cmdTag (command d) <= 1 => mObs (rModel r) == mObs m)} @-}
roundWith :: Asset -> Model -> Decision -> Round
roundWith a m d = case command d of
  NoCmd         -> finish d (perform (goal a) NoCmd m)
  DoObserve     -> finish d (perform (goal a) DoObserve m)
  DoOpen        -> finish d (perform (goal a) DoOpen m)
  DoSeal        -> finish d (perform (goal a) DoSeal m)
  DoDiscard r   -> finish d (perform (goal a) (DoDiscard r) m)
  DoRemove v    -> finish d (perform (goal a) (DoRemove v) m)

-- | Observe the store after the command: the asset's new observation is
-- exactly the store's state.
{-@ finish :: d:Decision -> n:Model
           -> {r:Round | rModel r == n && rRow r == row d
                        && goal (rAsset r) == goal (next d) && vouch (rAsset r) == vouch (next d)
                        && budget (rAsset r) == budget (next d) && authorised (rAsset r) == authorised (next d)
                        && isSeen (seen (rAsset r)) && Coherent (rAsset r) n} @-}
finish :: Decision -> Model -> Round
finish d n = Round (observeInto (next d) n) n (row d)
