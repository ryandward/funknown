{-# LANGUAGE Safe #-}
-- | The kernel's state: what an asset should become (its goal), why it is
-- going away (its ending), what the store was last seen to hold, and the
-- receipt. See docs/design/kernel.md.
module Funknown.Kernel.Types
  ( StagingRef (..)
  , Staging (..), stagingRef
  , Stagings (..), refSet, nStagings
  , Vouching (..)
  , ObjectObs (..)
  , Observed (..)
  , objTag, objVersion, objVouchedSize, obsObjTag, obsVersion, obsVouchedSize, obsRefs, obsStagings
  , Seen (..), isSeen, seenObjTag, seenVersion, seenVouchedSize, seenRefs, seenStagings
  , Assembly (..)
  , Goal (..), goalTag, rank, assembledTotal, goalAdopted, assembledRef, goalStaging, gapI
  , Ending (..)
  , Outcome (..), isEnded
  , Vouch (..), hasReceipt, vouchVersion, vouchSize
  , Write (..)
  , Asset (..)
  , Cmd (..), cmdTag, discardRef, removeVersion
  , Config (..)
  , Env (..)
  , Row (..), isFixedRow
  , Decision (..)
  , State (..), isActiveState, stateOf
  ) where

import qualified Data.Set as S
import Funknown.Opt
import Funknown.Fault (Fault)
import Funknown.Http.Retry (Backoff, attemptCap)
import Funknown.Kernel.Bound (Bound, Version (..), boundSize, boundVersion)
import Funknown.Store.Receipt (ReceiptReport, reportSize)
import Funknown.Upload (Chunks, ChunkToken, offsetOf, room)

-- Observed reality ------------------------------------------------------------

-- | Opaque: whatever names a staging area in the store. Store contract rule
-- 1 makes every staging area held for a file discoverable by the file's id.
data StagingRef = StagingRef [Char]
  deriving (Eq, Ord, Show)

-- | A staging area and the tokens of the chunks it holds durably.
data Staging = Staging StagingRef [ChunkToken]

{-@ measure stagingRef @-}
stagingRef :: Staging -> StagingRef
stagingRef (Staging r _) = r

-- | Every staging area an observation found. Its own list type, because a
-- measure over @[Staging]@ clashes with the polymorphic list constructors.
data Stagings = SNil | SCons Staging Stagings

{-@ measure refSet @-}
refSet :: Stagings -> S.Set StagingRef
refSet SNil         = S.empty
refSet (SCons s ss) = S.union (S.singleton (stagingRef s)) (refSet ss)

{-@ measure nStagings @-}
{-@ nStagings :: Stagings -> Nat @-}
nStagings :: Stagings -> Int
nStagings SNil         = 0
nStagings (SCons _ ss) = 1 + nStagings ss

data Vouching
  = Vouched ReceiptReport   -- ^ a full-object CRC-64/NVME checksum of the whole object, and its size
  | Unvouchable             -- ^ an object exists that the store will never vouch for in that algorithm
  | NotYetVouched           -- ^ an object exists, and the answer can still change without a call from us

data ObjectObs = NoObject | HasObject Version Vouching

data Observed = Observed Stagings ObjectObs

-- | Whether the store has been observed since the last command. A command
-- makes the old observation stale, so the kernel decides again only after a
-- new one.
data Seen = Unseen | Seen Observed

{-@ measure isSeen @-}
isSeen :: Seen -> Bool
isSeen Unseen   = False
isSeen (Seen _) = True

-- Measures of an observation, defined on 'ObjectObs' and 'Observed' so the
-- store model (which holds an 'Observed') and an asset's last snapshot are
-- measured the same way.

-- | 0 no object, 1 vouched, 2 unvouchable, 3 not yet vouched.
{-@ measure objTag @-}
{-@ objTag :: ObjectObs -> {t:Int | 0 <= t && t <= 3} @-}
objTag :: ObjectObs -> Int
objTag NoObject                    = 0
objTag (HasObject _ (Vouched _))   = 1
objTag (HasObject _ Unvouchable)   = 2
objTag (HasObject _ NotYetVouched) = 3

{-@ measure objVersion @-}
objVersion :: ObjectObs -> Version
objVersion (HasObject v _) = v
objVersion NoObject        = Version []

{-@ measure objVouchedSize @-}
objVouchedSize :: ObjectObs -> Int
objVouchedSize (HasObject _ (Vouched r))   = reportSize r
objVouchedSize (HasObject _ Unvouchable)   = -1
objVouchedSize (HasObject _ NotYetVouched) = -1
objVouchedSize NoObject                    = -1

{-@ measure obsObjTag @-}
{-@ obsObjTag :: Observed -> {t:Int | 0 <= t && t <= 3} @-}
obsObjTag :: Observed -> Int
obsObjTag (Observed _ o) = objTag o

{-@ measure obsVersion @-}
obsVersion :: Observed -> Version
obsVersion (Observed _ o) = objVersion o

{-@ measure obsVouchedSize @-}
obsVouchedSize :: Observed -> Int
obsVouchedSize (Observed _ o) = objVouchedSize o

{-@ measure obsRefs @-}
obsRefs :: Observed -> S.Set StagingRef
obsRefs (Observed ss _) = refSet ss

{-@ measure obsStagings @-}
{-@ obsStagings :: Observed -> Nat @-}
obsStagings :: Observed -> Int
obsStagings (Observed ss _) = nStagings ss

{-@ measure seenObjTag @-}
{-@ seenObjTag :: Seen -> {t:Int | 0 <= t && t <= 3} @-}
seenObjTag :: Seen -> Int
seenObjTag Unseen   = 0
seenObjTag (Seen o) = obsObjTag o

{-@ measure seenVersion @-}
seenVersion :: Seen -> Version
seenVersion Unseen   = Version []
seenVersion (Seen o) = obsVersion o

{-@ measure seenVouchedSize @-}
seenVouchedSize :: Seen -> Int
seenVouchedSize Unseen   = -1
seenVouchedSize (Seen o) = obsVouchedSize o

{-@ measure seenRefs @-}
seenRefs :: Seen -> S.Set StagingRef
seenRefs Unseen   = S.empty
seenRefs (Seen o) = obsRefs o

{-@ measure seenStagings @-}
{-@ seenStagings :: Seen -> Nat @-}
seenStagings :: Seen -> Int
seenStagings Unseen   = 0
seenStagings (Seen o) = obsStagings o

-- Intent -----------------------------------------------------------------------

-- | The upload draft's distinction: an upload is incomplete until it is
-- explicitly marked complete (R UP:RESUMABLE-UPLOAD-13-4.1.2-1). The staging
-- area is the one the producer writes to, once the kernel has adopted one.
data Assembly = Assembling (Opt StagingRef) Chunks | Assembled StagingRef Chunks

-- | What the store should hold when the asset comes to rest: the assembled
-- object, sealed and vouched (resolves to ACTIVE), or nothing at all.
-- AIP-216's active states resolve on their own into a single expected
-- resting state (R SS:AIP216-Active-1).
data Goal = Keep Assembly | Clear

-- | 0 Clear, 1 Keep an assembled object, 2 Keep an assembly in progress.
{-@ measure goalTag @-}
{-@ goalTag :: Goal -> {t:Int | 0 <= t && t <= 2} @-}
goalTag :: Goal -> Int
goalTag Clear                       = 0
goalTag (Keep (Assembled _ _))      = 1
goalTag (Keep (Assembling _ _))     = 2

-- | The goal's place in its order, the first component of the convergence
-- metric. Every append lowers it, completion lowers it, clearing lowers it.
{-@ measure rank @-}
{-@ rank :: g:Goal -> {v:Nat | (goalTag g == 0 <=> v == 0) && (goalTag g == 1 => v == 1) && (goalTag g == 2 => v >= 2)} @-}
rank :: Goal -> Int
rank Clear                      = 0
rank (Keep (Assembled _ _))     = 1
rank (Keep (Assembling _ c))    = 2 + room c

{-@ measure assembledTotal @-}
assembledTotal :: Goal -> Int
assembledTotal (Keep (Assembled _ c))  = offsetOf c
assembledTotal (Keep (Assembling _ _)) = -1
assembledTotal Clear                   = -1

-- | Whether an assembly in progress has a staging area adopted.
{-@ measure goalAdopted @-}
goalAdopted :: Goal -> Bool
goalAdopted (Keep (Assembling (Present _) _)) = True
goalAdopted (Keep (Assembling Absent _))      = False
goalAdopted (Keep (Assembled _ _))            = True
goalAdopted Clear                             = False

-- | The staging area the goal's chunks are in, once one is adopted.
{-@ measure goalStaging @-}
goalStaging :: Goal -> StagingRef
goalStaging (Keep (Assembling (Present r) _)) = r
goalStaging (Keep (Assembled r _))            = r
goalStaging (Keep (Assembling Absent _))      = StagingRef []
goalStaging Clear                             = StagingRef []

-- | The staging area an assembled goal's chunks are in.
{-@ measure assembledRef @-}
assembledRef :: Goal -> StagingRef
assembledRef (Keep (Assembled r _))  = r
assembledRef (Keep (Assembling _ _)) = StagingRef []
assembledRef Clear                   = StagingRef []

-- | The gap between a goal and what the store holds: how many store
-- commands, at most, are still needed before the goal's resting state, given
-- the goal's kind, whether a staging area is adopted, whether a receipt is
-- held, how many staging areas are held and what object there is.
--
-- * Clear: one Discard per staging area, one Remove for an object.
-- * Assembling, nothing adopted: an Open when nothing is staged, then one
--   adoption; with n staged, one adoption and n - 1 discards of the others.
-- * Assembling into r: the n - 1 others to discard, plus r itself, which
--   stays (a resting state once the others are gone).
-- * Assembled, no receipt: the staging areas, plus the seal and the receipt
--   still to come (2), or just the receipt once an object exists (1).
-- * Assembled, receipt held: the leftover staging areas to discard.
{-@ inline gapI @-}
gapI :: Int -> Bool -> Bool -> Int -> Int -> Int
gapI g adopted rc n obj =
  if g == 0 then n + (if obj /= 0 then 1 else 0)
  else if g == 2 then (if adopted then n else (if n == 0 then 3 else n + 1))
  else if rc then n
  else n + (if obj /= 0 then 1 else 2)

data Ending = Deleted | Cancelled | Failed Fault

-- | Why the asset is going away, once it is. The reconciler never reads it.
data Outcome = Ongoing | Ended Ending

{-@ measure isEnded @-}
isEnded :: Outcome -> Bool
isEnded Ongoing   = False
isEnded (Ended _) = True

data Vouch = NoReceipt | HasReceipt Bound

{-@ measure hasReceipt @-}
hasReceipt :: Vouch -> Bool
hasReceipt NoReceipt      = False
hasReceipt (HasReceipt _) = True

{-@ measure vouchVersion @-}
vouchVersion :: Vouch -> Version
vouchVersion NoReceipt      = Version []
vouchVersion (HasReceipt b) = boundVersion b

{-@ measure vouchSize @-}
vouchSize :: Vouch -> Int
vouchSize NoReceipt      = -1
vouchSize (HasReceipt b) = boundSize b

-- | A chunk write the core started and hasn't seen reported, with the
-- wall-clock instant by which the shell has aborted it (A3).
data Write = Write Int Int

-- | One asset. The ending is set exactly when the goal is Clear; a receipt
-- exists only for an assembled object, and its size is the assembled length.
data Asset = Asset
  { goal       :: Goal
  , outcome    :: Outcome
  , seen       :: Seen
  , vouch      :: Vouch
  , budget     :: Int
  , backoffAt  :: Int
  , authorised :: [Write]
  }
{-@ data Asset = Asset
      { goal       :: Goal
      , outcome    :: {o:Outcome | isEnded o <=> goalTag goal == 0}
      , seen       :: Seen
      , vouch      :: {v:Vouch | (hasReceipt v => goalTag goal /= 2)
                                && ((hasReceipt v && goalTag goal == 1) => vouchSize v == assembledTotal goal)}
      , budget     :: {b:Nat | b <= attemptCap}
      , backoffAt  :: {s:Int | s >= 1}
      , authorised :: [Write] } @-}

-- Decisions --------------------------------------------------------------------

-- | The one command a step may issue. Seal names nothing: the chunks it seals
-- are always the goal's, so it can't seal anything else (K2). Discard and
-- Remove name what the observation showed.
data Cmd = NoCmd | DoObserve | DoOpen | DoSeal | DoDiscard StagingRef | DoRemove Version

-- | 0 none, 1 observe, 2 open, 3 seal, 4 discard, 5 remove.
{-@ measure cmdTag @-}
{-@ cmdTag :: Cmd -> {t:Int | 0 <= t && t <= 5} @-}
cmdTag :: Cmd -> Int
cmdTag NoCmd         = 0
cmdTag DoObserve     = 1
cmdTag DoOpen        = 2
cmdTag DoSeal        = 3
cmdTag (DoDiscard _) = 4
cmdTag (DoRemove _)  = 5

{-@ measure discardRef @-}
discardRef :: Cmd -> StagingRef
discardRef (DoDiscard r) = r
discardRef NoCmd         = StagingRef []
discardRef DoObserve     = StagingRef []
discardRef DoOpen        = StagingRef []
discardRef DoSeal        = StagingRef []
discardRef (DoRemove _)  = StagingRef []

{-@ measure removeVersion @-}
removeVersion :: Cmd -> Version
removeVersion (DoRemove v)  = v
removeVersion NoCmd         = Version []
removeVersion DoObserve     = Version []
removeVersion DoOpen        = Version []
removeVersion DoSeal        = Version []
removeVersion (DoDiscard _) = Version []

data Config = Config { maxAttempts :: Int, backoff :: Backoff, writeDeadline :: Int }
{-@ data Config = Config { maxAttempts :: {n:Int | 1 <= n && n <= attemptCap}, backoff :: Backoff
                         , writeDeadline :: Nat } @-}

data Env = Env { now :: Int, cfg :: Config }
{-@ data Env = Env { now :: Nat, cfg :: Config } @-}

-- | Which row of the decision table decided, for the exhaustive guard test
-- and for the shell's log.
data Row = R0 | R1 | R2 | R3 | R4 | R5 | R6 | R7 | R8 | R9 | R10 | R11 | R12 | R13 | R14 | R15
         | R16 | R17 | R18 | R19
  deriving (Eq, Show, Enum, Bounded)

-- | The rows that are resting states: waiting for the producer (R3),
-- converged (R14, R18), or waiting out a write deadline (R19).
{-@ measure isFixedRow @-}
isFixedRow :: Row -> Bool
isFixedRow R3  = True
isFixedRow R14 = True
isFixedRow R18 = True
isFixedRow R19 = True
isFixedRow _   = False

-- | The asset after the step, the command to issue, how many seconds to wait
-- before issuing it, whether an operator has to be told, and the row.
data Decision = Decision { next :: Asset, command :: Cmd, waitFor :: Int, alarm :: Bool, row :: Row }
{-@ data Decision = Decision { next :: Asset, command :: Cmd, waitFor :: Nat, alarm :: Bool, row :: Row } @-}

-- AIP-216 ----------------------------------------------------------------------

-- | The State a client sees (R SS:AIP216-EnumValues-1 .. -3). It is never
-- stored, only computed, so it is output-only (P SS:AIP216-OutputOnly-1) and
-- can't disagree with the goal, the ending, the receipt or the store.
data State = CREATING | ACTIVE | FAILED Fault | CANCELLED | DELETING | DELETED
  deriving (Eq, Show)

{-@ measure isActiveState @-}
isActiveState :: State -> Bool
isActiveState ACTIVE     = True
isActiveState CREATING   = False
isActiveState (FAILED _) = False
isActiveState CANCELLED  = False
isActiveState DELETING   = False
isActiveState DELETED    = False

-- | K6: ACTIVE exactly when a receipt is held and the goal isn't Clear. A
-- deleted asset is DELETED only once the store was seen holding nothing and
-- no write it started is still unreported.
{-@ stateOf :: a:Asset -> {s:State | isActiveState s <=> (hasReceipt (vouch a) && goalTag (goal a) /= 0)} @-}
stateOf :: Asset -> State
stateOf (Asset (Keep _) _ _ v _ _ _) = case v of
  HasReceipt _ -> ACTIVE
  NoReceipt    -> CREATING
stateOf (Asset Clear o s _ _ _ w) = case o of
  Ended (Failed f) -> FAILED f
  Ended Cancelled  -> CANCELLED
  Ended Deleted    -> if heldNothing s && null w then DELETED else DELETING
  Ongoing          -> DELETING   -- unreachable: the refinement ties Clear to an ending

heldNothing :: Seen -> Bool
heldNothing (Seen (Observed SNil NoObject)) = True
heldNothing _                               = False
