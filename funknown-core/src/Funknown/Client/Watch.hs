{-# LANGUAGE Safe #-}
-- | The two events that carry no request: 'KernelMoved', delivered after
-- every kernel round, and 'Tick'. Both look at what the asset already shows
-- and answer whatever the client side was holding for it. Neither appends;
-- a Tick past the deadline abandons an assembly the way a cancel would (X1),
-- and KernelMoved completes an empty creation the kernel just adopted, as
-- B4 would. ClientOut's CQuietGoal holds both to that.
--
-- These rows are kernel.md's "Held requests are watches on the asset",
-- adapted by the rulings in CLIENT.md, slice 3 and round 2. Each handler
-- takes only its own event, and each row spec says both what its rows do
-- and that anything else is stale, so a watch can neither invent a row nor
-- skip one.
module Funknown.Client.Watch
  ( kernelMoved
  , tick
  ) where

import Funknown.Opt
import Funknown.Fault (Fault (..))
import Funknown.Client.Contract ()
import Funknown.Client.Core (completeGoal, endedReply, expireFile, fileEtag, idEtag, operationOf, readCapOf, settle, stale)
import Funknown.Client.Types
import Funknown.Kernel.Types (Asset (..), Goal (..), Assembly (..), Ending (..), Outcome (..), Vouch (..), goalTag, goalAdopted, hasReceipt)
import Funknown.Upload (Limits (..), limitsOf, offsetOf)

-- Row specs ------------------------------------------------------------------------

{-@ predicate WatchEvent E = not (isPresent (evReq E)) && not (isMoverReport E) @-}
{-@ predicate GoalOf F = goal (fileAsset F) @-}

-- | A cleared goal settles every unsettled phase: the owed request is told
-- the ending's refusal with UC ?1, the job stopped, nothing is left
-- waiting, and the asset stays as the kernel left it.
{-@ predicate ClearedUnsettled F = goalTag (GoalOf F) == 0 && filePhase F /= 5 @-}
{-@ predicate SettlesCleared F O =
      ClearedUnsettled F
        => (filePhase (after O) == 5 && owedReq (after O) == Absent && owedJob (after O) == 0
            && fileAsset (after O) == fileAsset F
            && SettledAs F O (Present (Refuse (outcomeRefusal (outcome (fileAsset F))) (Present True)))) @-}

-- | Nothing happens: the step is 'stale'.
{-@ predicate Quiet F O =
      after O == F && not (isPresent (owedTo O)) && not (isPresent (stopped O))
      && not (isPresent (started O)) && len (timers O) == 0 @-}

-- | The kernel adopted a staging area while the creation request was held.
{-@ predicate AdoptedHold F =
      goalTag (GoalOf F) == 2 && goalAdopted (GoalOf F) && filePhase F == 0 && fileOwes F @-}

-- | A receipt appeared while the completing request was held (F1).
{-@ predicate ReceiptHeld F =
      goalTag (GoalOf F) == 1 && hasReceipt (vouch (fileAsset F)) && filePhase F == 4 && fileOwes F @-}

-- | KernelMoved's rows. Each says what its row does, and the last says that
-- anything else is stale (CLIENT.md slice 3).
{-@ predicate WatchRows F O =
      SettlesCleared F O
      && ((AdoptedHold F && openContent (phase (client F)))
            => (filePhase (after O) == 2 && optStartTag (started O) == 1))
      && ((AdoptedHold F && not (openContent (phase (client F))) && openUc (phase (client F)) && goalSealsEmpty (GoalOf F))
            => (goalTag (goal (fileAsset (after O))) == 1 && filePhase (after O) == 4 && fileWait (after O) >= 0
                && owedReq (after O) == owedReq F))
      && ((AdoptedHold F && not (openContent (phase (client F)))
           && not (openUc (phase (client F)) && goalSealsEmpty (GoalOf F)))
            => (filePhase (after O) == 1 && isPresent (owedTo O)
                && settleOffset (owedTo O) == goalOffset (goal (fileAsset (after O)))))
      && (ReceiptHeld F
            => (filePhase (after O) == 5 && fileAsset (after O) == fileAsset F
                && owedTo O == Present (Answer (CreatedFile (fileId (meta F)) (idEtag (fileId (meta F)))))))
      && ((not (ClearedUnsettled F) && not (AdoptedHold F) && not (ReceiptHeld F)) => Quiet F O) @-}

-- KernelMoved ---------------------------------------------------------------------

-- | Answer what the client side holds from what the kernel round left in the
-- asset. Only the empty creation's completion moves the goal; every other
-- row leaves the asset exactly as it found it.
{-@ kernelMoved :: env:Env -> ev:{Event | WatchEvent ev && not (isTick ev)} -> f:File
                -> {o:ClientOut env f ev | WatchRows f o} @-}
kernelMoved :: Env -> Event -> File -> Out
kernelMoved env ev f@(File m a@(Asset g _ _ v _ _ _) (Client l op ph d) e) = case g of
  -- The kernel failed the asset (R5, R6, R8, R10, R11, R15) or a client
  -- cleared it: every phase that isn't Settled settles here, a held request
  -- told the ending's refusal (kernel.md's watch table; C CH22).
  Clear -> case ph of
    Settled -> stale env ev f
    _       -> settleCleared env ev f
  Keep (Assembling (Present _) ch) -> case ph of
    -- O2: with content, the creation request's own body is read as the
    -- first append, under a new epoch, and stays owed until B3-B16 answer it.
    -- R UP:RESUMABLE-UPLOAD-13-4.2.2-3; C CH28, CH45
    Opening (Present (Hold r True uc)) ->
      Out (File m a (Client l op (Reading (CreationReq r) uc) d) (e + 1))
          Absent Absent Absent (Present (StartRead (e + 1) (readCapOf ch))) [] Absent
    -- An empty creation that completes: UC ?1, no content, and a store that
    -- can seal zero chunks. As B4 does, the assembly is complete with the
    -- chunks it has, the length is the offset, and the request waits for the
    -- receipt until replyWait, with a Tick at that instant.
    -- R UP:RESUMABLE-UPLOAD-13-4.1.2-3, UP:RESUMABLE-UPLOAD-13-4.2.2-4; C CH15, CH22
    Opening (Present (Hold r False True))
      | sealsEmpty (limitsOf ch) ->
          let t = envNow env + replyWait env
          in Out (File m (completeGoal a) (Client (Known (offsetOf ch)) op (Sealing (Present (Waiter r t))) d) e)
                 Absent Absent Absent Absent [t] Absent
    -- O1: the reconciler adopted a staging area and the creation request
    -- carried no content, so it gets its 201 with the upload resource. The
    -- offset is the goal's own chunk total, the number appendTo maintains.
    -- R UP:RESUMABLE-UPLOAD-13-4.2.2-5, UP:RESUMABLE-UPLOAD-13-4.2.1-8
    Opening (Present (Hold r False _)) ->
      Out (File m a (Client l op Idle d) e)
          (settle (Present r) (Present (CreatedUpload (uploadId m) (limitsOf ch) (offsetOf ch))))
          Absent Absent Absent [] Absent
    _ -> stale env ev f
  Keep (Assembled _ _) -> case ph of
    -- F1: a receipt appeared while the completing request was held, so it
    -- gets the file's 201 with its ETag and UC ?1, and the file is ACTIVE.
    -- C CH1, CH5, CH9; R HS:RFC9110-15.3.2-1; P UP:RESUMABLE-UPLOAD-13-4.4.2-4 (PM11)
    Sealing (Present w) -> case v of
      HasReceipt _ ->
        Out (File m a (Client l op Settled d) e)
            (settle (Present (waiterReq w)) (Present (CreatedFile (fileId m) (fileEtag f))))
            Absent Absent Absent [] Absent
      NoReceipt -> stale env ev f
    _ -> stale env ev f
  Keep (Assembling Absent _) -> stale env ev f

-- | The goal was cleared under the client side: the owed request, if any,
-- is told the ending's refusal with UC ?1, a running mover is stopped, and
-- the client side settles under a new epoch, so a late report of the old
-- job is stale by its epoch as well as by the phase. The asset is untouched:
-- the kernel already cleared it, and its unreported writes stay authorised
-- until they are reported or lapse (A3).
{-@ settleCleared :: env:Env -> ev:{Event | WatchEvent ev}
                  -> f:{File | goalTag (goal (fileAsset f)) == 0}
                  -> {o:ClientOut env f ev | SettlesCleared f o && filePhase (after o) == 5} @-}
settleCleared :: Env -> Event -> File -> Out
settleCleared _ _ (File m a (Client l op ph d) e) =
  Out (File m a (Client l op Settled d) (e + 1))
      (settle (phaseReq ph) (Present (endedReply (endingOf a))))
      Absent
      (if phaseJob ph == 1 then Present e else Absent)
      Absent [] Absent

-- | Why a cleared asset went away. The asset's refinement ties a cleared
-- goal to an ending, so the other branch is proved unreachable, not guessed.
{-@ endingOf :: a:{Asset | goalTag (goal a) == 0}
             -> {x:Ending | outcome a == Ended x && outcomeRefusal (outcome a) == endingRefusal x} @-}
endingOf :: Asset -> Ending
endingOf (Asset _ (Ended x) _ _ _ _ _) = x
endingOf (Asset _ Ongoing _ _ _ _ _)   = unreachable ()

{-@ unreachable :: {u:() | false} -> a @-}
unreachable :: () -> a
unreachable _ = error "unreachable"

-- Tick ------------------------------------------------------------------------------

-- | T2's instant has come for the held completing request.
{-@ predicate T2Due V F =
      filePhase F == 4 && goalTag (GoalOf F) /= 0 && fileOwes F && envNow V >= fileWait F @-}

-- | Tick's rows: a cleared goal settles exactly as KernelMoved settles it;
-- T2 answers a waiter once its instant has come, and only then; anything
-- else is stale. X1 is ClientOut's own CExpires, which holds every request,
-- report and Tick to G3 in one place.
{-@ predicate TickRows V F O =
      SettlesCleared F O
      && ((filePhase F == 4 && goalTag (GoalOf F) /= 0 && isPresent (owedTo O)) => envNow V >= fileWait F)
      && (T2Due V F
            => (isPresent (owedTo O) && filePhase (after O) == 4 && fileWait (after O) == -1
                && fileAsset (after O) == fileAsset F))
      && ((not (ClearedUnsettled F) && not (T2Due V F) && not (PastDeadline V F)) => Quiet F O) @-}

-- | A Tick only makes the step look at the clock. A cleared goal comes
-- first, so a held request gets the ending's refusal and never a 202. Then
-- at most one row can hold: T2 needs a sealing phase, which only an
-- assembled goal allows, and X1 needs an assembly still in progress.
{-@ tick :: env:Env -> ev:{Event | WatchEvent ev && isTick ev} -> f:File -> {o:ClientOut env f ev | TickRows env f o} @-}
tick :: Env -> Event -> File -> Out
tick env ev f@(File m a@(Asset g _ _ _ _ _ _) (Client l op ph d) e) = case g of
  Clear -> case ph of
    Settled -> stale env ev f
    _       -> settleCleared env ev f
  _ -> case ph of
    -- T2: the completing request has waited `replyWait`, so it gets 202 with
    -- the operation as its body and UC ?1, and the file keeps sealing.
    -- R HS:RFC9110-15.3.3-1; P HS:RFC9110-15.3.3-3 (PM45); C CH22
    Sealing (Present w) | envNow env >= waiterBy w ->
      Out (File m a (Client l op (Sealing Absent) d) e)
          (settle (Present (waiterReq w)) (Present (Pending (Present (operationOf f)) Absent True)))
          Absent Absent Absent [] Absent
    _ -> case g of
      -- X1: max-age ran out while the upload was still assembling. The held
      -- or in-flight request is abandoned and any mover stopped, by the one
      -- way the client side clears a goal.
      -- P UP:RESUMABLE-UPLOAD-13-4.1.4-7 (PM40), PM13; C CH6
      Keep (Assembling _ _) | envNow env >= deadline m -> expireFile env ev f Absent
      _ -> stale env ev f
