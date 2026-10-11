{-# LANGUAGE Safe #-}
-- | The level-triggered reconciler: compare what an asset should become with
-- what the store was last seen to hold, and decide the one command that
-- closes the gap. Rows R0 to R19 of docs/design/kernel.md. Their guards are
-- mutually exclusive, so each row below is reached by exactly one path.
--
-- Every row returns a 'Step', whose type states the safety claims K0 to K5
-- and K8 to K13 once, so LiquidHaskell holds every row to all of them.
module Funknown.Kernel.Reconcile
  ( reconcile
  , Found (..), isFound, foundRef
  , firstRef, firstOther, listed, isFailed, storeFault, failedOnStore
  ) where

import Funknown.Opt
import Funknown.Fault (Fault (..))
import Funknown.Http.Retry (Wait (..), nextWait)
import Funknown.Kernel.Bound (Bound, bind, boundSize, boundVersion)
import Funknown.Kernel.Types
import Funknown.Upload (Chunk (..), ChunkToken, Chunks, chunkList, offsetOf)

-- | Which of the faults an observation of the store can justify on its own
-- this is: 1 StateLost, 2 Contradiction, 3 SizeMismatch,
-- 4 ObjectWithoutReceipt, 5 Unavailable, and 0 for the rest. The rest name a
-- call's result (SourceUnreachable, SourceAnswered, StoreRefusedUs,
-- CreationInterrupted, FinalizeTimedOut) or a client-side check, and only
-- the client side may set them.
{-@ measure storeFault @-}
{-@ storeFault :: Fault -> {n:Int | 0 <= n && n <= 5} @-}
storeFault :: Fault -> Int
storeFault StateLost            = 1
storeFault Contradiction        = 2
storeFault SizeMismatch         = 3
storeFault ObjectWithoutReceipt = 4
storeFault Unavailable          = 5
storeFault Expired              = 0
storeFault FinalizeTimedOut     = 0
storeFault OutOfRange           = 0
storeFault TooLarge             = 0
storeFault QuotaAtFinalize      = 0
storeFault Revoked              = 0
storeFault Empty                = 0
storeFault CreationRefused      = 0
storeFault CreationInterrupted  = 0
storeFault StoreRefusedUs       = 0
storeFault SourceUnreachable    = 0
storeFault (SourceAnswered _)   = 0
storeFault SourceChanged        = 0

-- | The store fault an ending names, as 'storeFault' numbers it, or 0.
{-@ measure failedOnStore @-}
{-@ failedOnStore :: Outcome -> {n:Int | 0 <= n && n <= 5} @-}
failedOnStore :: Outcome -> Int
failedOnStore (Ended (Failed f)) = storeFault f
failedOnStore (Ended Deleted)    = 0
failedOnStore (Ended Cancelled)  = 0
failedOnStore Ongoing            = 0

{-@ measure isFailed @-}
isFailed :: Outcome -> Bool
isFailed (Ended (Failed _)) = True
isFailed (Ended Deleted)    = False
isFailed (Ended Cancelled)  = False
isFailed Ongoing            = False

-- The claims every step meets:
--
-- K8   the goal's rank never rises; an ending, once set, never changes; the
--      reconciler moves the goal only by clearing it as Failed, and otherwise
--      leaves its kind, rank and assembled length alone.
-- K1   a receipt appears only for an assembled object the store vouched for,
--      with the assembled length, bound to the version that was observed.
-- K1b  while the goal isn't Clear, a receipt once held is never replaced.
-- K2   Seal only for an assembled goal with no receipt and no object seen.
-- K3   while a receipt is held and the goal isn't Clear, no Remove.
-- K4   when the goal is Clear and anything was seen held, Discard or Remove.
-- K5n  Discard names a staging area that was seen; Remove names the version seen.
-- K0   nothing but Observe before there is an observation, and every store
--      command makes the observation stale.
{-@ predicate K8 A D =
      rank (goal (next D)) <= rank (goal A)
      && (isEnded (outcome A) => outcome (next D) == outcome A)
      && ((goalTag (goal A) /= 0 && goalTag (goal (next D)) == 0) => isFailed (outcome (next D)))
      && (goalTag (goal (next D)) /= 0 => (goalTag (goal (next D)) == goalTag (goal A)
                                          && rank (goal (next D)) == rank (goal A)
                                          && assembledTotal (goal (next D)) == assembledTotal (goal A))) @-}
{-@ predicate K1 A D =
      (hasReceipt (vouch (next D)) && not (hasReceipt (vouch A)))
        => (goalTag (goal A) == 1 && seenObjTag (seen A) == 1
            && seenVouchedSize (seen A) == assembledTotal (goal A)
            && vouchSize (vouch (next D)) == assembledTotal (goal A)
            && vouchVersion (vouch (next D)) == seenVersion (seen A)) @-}
{-@ predicate K1b A D = (hasReceipt (vouch A) && goalTag (goal (next D)) /= 0) => vouch (next D) == vouch A @-}
{-@ predicate K2 A D =
      cmdTag (command D) == 3 => (goalTag (goal A) == 1 && not (hasReceipt (vouch A))
                                  && isSeen (seen A) && seenObjTag (seen A) == 0) @-}
{-@ predicate K3 A D = (hasReceipt (vouch A) && goalTag (goal A) /= 0) => cmdTag (command D) /= 5 @-}
{-@ predicate K4 A D =
      (goalTag (goal A) == 0 && isSeen (seen A) && (seenStagings (seen A) > 0 || seenObjTag (seen A) /= 0))
        => (cmdTag (command D) == 4 || cmdTag (command D) == 5) @-}
{-@ predicate K5n A D =
      (cmdTag (command D) == 4 => Set_mem (discardRef (command D)) (seenRefs (seen A)))
      && (cmdTag (command D) == 5 => (removeVersion (command D) == seenVersion (seen A) && seenObjTag (seen A) /= 0)) @-}
{-@ predicate K0 A D =
      (not (isSeen (seen A)) => cmdTag (command D) == 1)
      && (cmdTag (command D) >= 1 => not (isSeen (seen (next D)))) @-}
-- K9   while a receipt is held for an assembled goal, an observation that
--      shows no object, or an object at another version, clears the goal:
--      the asset can't stay ACTIVE once the store lost what it vouched for.
{-@ predicate K9 A D =
      (goalTag (goal A) == 1 && hasReceipt (vouch A) && isSeen (seen A)
       && (seenObjTag (seen A) == 0 || seenVersion (seen A) /= vouchVersion (vouch A)))
        => goalTag (goal (next D)) == 0 @-}
-- Prog, what the progress lemma needs from each step:
--   a step that issues nothing leaves the observation and budget alone and,
--   unless it rests, lowers the goal's rank or, at equal rank, the gap
--   measured on the same observation; an Observe is the first look, a spent
--   attempt, or the write wait; Open only with nothing staged for an
--   unadopted assembly; Seal only of a staging area that was seen; and a store
--   command leaves goal, receipt and budget alone.
{-@ predicate Prog A D =
      (cmdTag (command D) == 0
         => (seen (next D) == seen A && budget (next D) == budget A
             && (isFixedRow (row D) || rank (goal (next D)) < rank (goal A)
                 || (rank (goal (next D)) == rank (goal A)
                     && gapI (goalTag (goal (next D))) (goalAdopted (goal (next D))) (hasReceipt (vouch (next D)))
                             (seenStagings (seen A)) (seenObjTag (seen A))
                        < gapI (goalTag (goal A)) (goalAdopted (goal A)) (hasReceipt (vouch A))
                             (seenStagings (seen A)) (seenObjTag (seen A))))))
      && (cmdTag (command D) == 1
         => (goal (next D) == goal A && vouch (next D) == vouch A
             && (not (isSeen (seen A)) && budget (next D) == budget A
                 || (isSeen (seen A) && budget (next D) < budget A)
                 || (isFixedRow (row D) && budget (next D) == budget A))))
      && (cmdTag (command D) == 2
         => (goalTag (goal A) == 2 && not (goalAdopted (goal A)) && seenStagings (seen A) == 0 && seenObjTag (seen A) == 0))
      && (cmdTag (command D) == 3 => Set_mem (assembledRef (goal A)) (seenRefs (seen A)))
      && (cmdTag (command D) == 4 => (goalTag (goal A) /= 2 || goalAdopted (goal A)))
      && (cmdTag (command D) == 5 => goalTag (goal A) == 0)
      && (cmdTag (command D) >= 2 => (goal (next D) == goal A && vouch (next D) == vouch A && budget (next D) == budget A)) @-}

-- K10  while the goal keeps the asset and no receipt is held, no Discard
--      names the staging area holding the goal's chunks: the producer's
--      acknowledged chunks are never thrown away by the reconciler.
{-@ predicate K10 A D =
      (goalTag (goal A) /= 0 && goalAdopted (goal A) && not (hasReceipt (vouch A)) && cmdTag (command D) == 4)
        => discardRef (command D) /= goalStaging (goal A) @-}

-- K11  an asset with no observation comes back exactly as it went in, with
--      no alarm: a shell that turns a failed observe call into Unseen loses
--      nothing but the call. With K0 the command is an Observe.
{-@ predicate K11 A D = not (isSeen (seen A)) => (next D == A && not (alarm D)) @-}

-- K12  a fault the reconciler sets is one of the five an observation can
--      justify, and the observation it was decided on shows exactly that:
--      StateLost, no object, or an object at a version other than the
--      receipt's; Contradiction, an object; SizeMismatch, a vouched object;
--      ObjectWithoutReceipt, an object the store will never vouch for; and
--      Unavailable, an object not yet vouched with the budget spent. With K0
--      it is decided only on an observation, so a call can end an asset
--      through the reconciler only if the shell reads a failed call as an
--      observation, which A1 rules out ("Funknown.Kernel.Inputs" lifts K12
--      from the observation to the store under that premise).
{-@ predicate K12 A D =
      (not (isEnded (outcome A)) && isEnded (outcome (next D)))
        => (failedOnStore (outcome (next D)) /= 0 && isSeen (seen A)
            && (failedOnStore (outcome (next D)) == 1
                  => (seenObjTag (seen A) == 0
                      || (hasReceipt (vouch A) && seenVersion (seen A) /= vouchVersion (vouch A))))
            && (failedOnStore (outcome (next D)) == 2 => seenObjTag (seen A) /= 0)
            && (failedOnStore (outcome (next D)) == 3 => seenObjTag (seen A) == 1)
            && (failedOnStore (outcome (next D)) == 4 => seenObjTag (seen A) == 2)
            && (failedOnStore (outcome (next D)) == 5 => (seenObjTag (seen A) == 3 && budget A == 0))) @-}

-- K13  the converse of K9: while a receipt is held for an assembled goal and
--      the observation shows the object at the receipt's version, the goal
--      and the receipt stay as they are.
{-@ predicate K13 A D =
      (goalTag (goal A) == 1 && hasReceipt (vouch A) && isSeen (seen A)
       && seenObjTag (seen A) /= 0 && seenVersion (seen A) == vouchVersion (vouch A))
        => (goal (next D) == goal A && vouch (next D) == vouch A) @-}

{-@ type Step A = {d:Decision | authorised (next d) == authorised A && K11 A d && K10 A d && K8 A d && K1 A d && K1b A d && K2 A d && K3 A d && K4 A d && K5n A d && K0 A d && K9 A d
                               && K12 A d && K13 A d && Prog A d} @-}

-- Looking things up in an observation ------------------------------------------

data Found = None | Found StagingRef

{-@ measure isFound @-}
isFound :: Found -> Bool
isFound None      = False
isFound (Found _) = True

{-@ measure foundRef @-}
foundRef :: Found -> StagingRef
foundRef None      = StagingRef []
foundRef (Found r) = r

{-@ firstRef :: ss:Stagings
             -> {f:Found | (isFound f => Set_mem (foundRef f) (refSet ss)) && (not (isFound f) => nStagings ss == 0)} @-}
firstRef :: Stagings -> Found
firstRef SNil                     = None
firstRef (SCons (Staging r _) _)  = Found r

{-@ firstOther :: r:StagingRef -> ss:Stagings
               -> {f:Found | isFound f => (Set_mem (foundRef f) (refSet ss) && foundRef f /= r)} @-}
firstOther :: StagingRef -> Stagings -> Found
firstOther _ SNil = None
firstOther r (SCons (Staging r' _) ss)
  | r' /= r   = Found r'
  | otherwise = case firstOther r ss of
      None     -> None
      Found r2 -> Found r2

{-@ listed :: r:StagingRef -> ss:Stagings -> {b:Bool | b <=> Set_mem r (refSet ss)} @-}
listed :: StagingRef -> Stagings -> Bool
listed _ SNil                     = False
listed r (SCons (Staging r' _) ss) = r == r' || listed r ss

-- | Whether staging area r is listed and durably holds every chunk of c,
-- matched by token, so a late duplicate write can't stand in for a chunk the
-- core acknowledged.
{-@ holds :: r:StagingRef -> Chunks -> ss:Stagings -> {b:Bool | b => Set_mem r (refSet ss)} @-}
holds :: StagingRef -> Chunks -> Stagings -> Bool
holds _ _ SNil = False
holds r c (SCons (Staging r' toks) ss)
  | r == r'   = all (`elem` toks) (map ctoken (chunkList c))
  | otherwise = holds r c ss

-- The rows -------------------------------------------------------------------

-- | R0: nothing is decided before the store has been observed.
{-@ observeNow :: a:{Asset | not (isSeen (seen a))} -> Step a @-}
observeNow :: Asset -> Decision
observeNow a = Decision a DoObserve 0 False R0

-- | Issue a store command; the observation is stale after it.
{-@ issue :: r:Row -> a:Asset -> c:{Cmd | cmdTag c >= 2}
          -> {d:Decision | goal (next d) == goal a && outcome (next d) == outcome a && vouch (next d) == vouch a
                          && budget (next d) == budget a && authorised (next d) == authorised a
                          && not (isSeen (seen (next d))) && command d == c && not (alarm d) && row d == r} @-}
issue :: Row -> Asset -> Cmd -> Decision
issue r a c = Decision (stale a) c 0 False r

{-@ stale :: a:Asset -> {b:Asset | goal b == goal a && outcome b == outcome a && vouch b == vouch a
                                  && budget b == budget a && authorised b == authorised a && not (isSeen (seen b))} @-}
stale :: Asset -> Asset
stale (Asset g o _ v b st w) = Asset g o Unseen v b st w

-- | Nothing to do: the asset is unchanged and nothing is issued.
{-@ rest :: r:Row -> a:Asset -> {d:Decision | next d == a && cmdTag (command d) == 0 && not (alarm d) && row d == r} @-}
rest :: Row -> Asset -> Decision
rest r a = Decision a NoCmd 0 False r

-- | The goal can't be reached: clear it, as Failed. No command yet; the next
-- step, on the same observation, starts the cleanup (R16, R17).
{-@ failWith :: Row -> a:{Asset | goalTag (goal a) /= 0} -> {f:Fault | storeFault f /= 0} -> Bool
             -> {d:Decision | goalTag (goal (next d)) == 0 && rank (goal (next d)) == 0 && isFailed (outcome (next d))
                             && failedOnStore (outcome (next d)) == storeFault f
                             && seen (next d) == seen a && vouch (next d) == vouch a
                             && budget (next d) == budget a && authorised (next d) == authorised a
                             && cmdTag (command d) == 0} @-}
failWith :: Row -> Asset -> Fault -> Bool -> Decision
failWith r (Asset _ _ s v b st w) f al = Decision (Asset Clear (Ended (Failed f)) s v b st w) NoCmd 0 al r

-- | The asset as decided on observation s; every row below receives it with
-- the observation already matched, so its facts are in scope.
{-@ reconcile :: Env -> a:Asset -> Step a @-}
reconcile :: Env -> Asset -> Decision
reconcile env a@(Asset g _ s v _ _ _) = case s of
  Unseen -> observeNow a
  Seen (Observed ss obj) -> case g of
    Clear -> clearing env a
    Keep (Assembling Absent _) -> case obj of
      NoObject -> case firstRef ss of
        None    -> issue R1 a DoOpen                                       -- R1
        Found r -> adopt a r                                            -- R2
      HasObject _ _ -> failWith R6 a Contradiction True                    -- R6
    Keep (Assembling (Present r) _) -> case obj of
      NoObject
        | listed r ss -> case firstOther r ss of
            None     -> rest R3 a                                          -- R3
            Found r' -> issue R4 a (DoDiscard r')                          -- R4
        | otherwise   -> failWith R5 a StateLost True                      -- R5
      HasObject _ _ -> failWith R6 a Contradiction True                    -- R6
    Keep (Assembled r c) -> case v of
      NoReceipt -> case obj of
        NoObject
          | not (holds r c ss) -> failWith R8 a StateLost True             -- R8
          | otherwise -> case firstOther r ss of
              Found r' -> issue R4 a (DoDiscard r')                        -- R4
              None     -> issue R7 a DoSeal                                -- R7
        HasObject ver (Vouched rep) -> case bind (offsetOf c) ver rep of
          Right bnd -> received a bnd                                   -- R9
          Left _    -> failWith R10 a SizeMismatch True                     -- R10
        HasObject _ Unvouchable   -> failWith R11 a ObjectWithoutReceipt True   -- R11
        HasObject _ NotYetVouched -> spend env a                        -- R12
      HasReceipt bnd -> case obj of
        HasObject ver _
          | ver == boundVersion bnd -> case firstRef ss of
              Found r' -> issue R13 a (DoDiscard r')                        -- R13
              None     -> rest R14 a                                        -- R14
        _ -> failWith R15 a StateLost True                                  -- R15

-- | R2: record which staging area the producer's chunks go to. The goal's
-- kind, rank and chunks don't change.
{-@ adopt :: a:{Asset | goalTag (goal a) == 2 && not (goalAdopted (goal a)) && not (hasReceipt (vouch a)) && isSeen (seen a)} -> StagingRef -> Step a @-}
adopt :: Asset -> StagingRef -> Decision
adopt (Asset (Keep (Assembling _ c)) o s v b st w) r = Decision (Asset (Keep (Assembling (Present r) c)) o s v b st w) NoCmd 0 False R2
adopt a _ = rest R2 a

-- | R9: the store vouches for the assembled object; bind the receipt to the
-- version it was seen at.
{-@ received :: a:{Asset | goalTag (goal a) == 1 && not (hasReceipt (vouch a)) && seenObjTag (seen a) == 1 && isSeen (seen a)}
             -> b:{Bound | boundSize b == assembledTotal (goal a) && boundSize b == seenVouchedSize (seen a)
                           && boundVersion b == seenVersion (seen a)}
             -> Step a @-}
received :: Asset -> Bound -> Decision
received (Asset g o s _ b st w) bnd = Decision (Asset g o s (HasReceipt bnd) b st w) NoCmd 0 False R9

-- | R12: the store holds the object but can't vouch yet. Spend one attempt
-- and observe again after backoff (R SS:GRFC-A6-Backoff), or fail when the
-- budget is spent.
{-@ spend :: Env -> a:{Asset | goalTag (goal a) == 1 && rank (goal a) == 1 && not (hasReceipt (vouch a)) && isSeen (seen a)
                            && seenObjTag (seen a) == 3} -> Step a @-}
spend :: Env -> Asset -> Decision
spend env a@(Asset g o _ v b st w)
  | b > 0     = let Wait d st' = nextWait (backoff (cfg env)) Absent st
                in Decision (Asset g o Unseen v (b - 1) st' w) DoObserve d False R12
  | otherwise = failWith R12 a Unavailable True

-- | R16 to R19: the goal is Clear, so everything held goes, staging areas
-- first, then the object; then the asset waits out the writes it started.
{-@ clearing :: Env -> a:{Asset | goalTag (goal a) == 0} -> Step a @-}
clearing :: Env -> Asset -> Decision
clearing env a@(Asset _ _ s _ _ _ w) = case s of
  Unseen -> observeNow a
  Seen (Observed ss obj) -> case firstRef ss of
    Found r -> issue R16 a (DoDiscard r)                                    -- R16
    None -> case obj of
      HasObject ver _ -> issue R17 a (DoRemove ver)                         -- R17
      NoObject -> case pending (now env) w of
        0 -> rest R18 a                                                     -- R18
        d -> Decision (stale a) DoObserve d False R19                       -- R19

-- | Seconds until the last unreported write's deadline, or 0 when every
-- write has reported or passed its deadline (A3).
{-@ pending :: Int -> [Write] -> Nat @-}
pending :: Int -> [Write] -> Int
pending _ [] = 0
pending t (Write _ dl : ws) = max (if dl > t then dl - t else 0) (pending t ws)
