{-# LANGUAGE Safe #-}
-- | The contract every client step meets, stated once. Each handler's result
-- type is 'ClientOut', so LiquidHaskell holds every row to all of it:
--
-- * the request the old state owed is still owed or is settled, and nothing
--   is settled that wasn't owed;
-- * the request this event carried is settled, or becomes the owed one, and
--   a report, 'KernelMoved' or a Tick settles nothing;
-- * a mover job reported, is stopped, or is still the job the file waits for;
-- * a job the new state waits for is the old one or the one this step started;
-- * a job a step starts runs under an epoch the file never used (CJobFresh);
-- * a job's report or stop is its end: the file stops waiting for it, and
--   whatever it holds is released or handed to the job started after it
--   (CJobEnded);
-- * an offset a client is told is the goal's chunk total (CToldOffset);
-- * a write the step authorises is the persist job it starts, with A3's
--   deadline (CWriteJob, CWriteEntry), a write's report removes its own
--   entry (CWriteReported), and no other entry leaves (CWriteKept);
-- * a job the file waits for is the kind its phase names (CJobKind);
-- * G3: a request, a Tick, or the running job's report on a goal still
--   assembling past its deadline runs X1 first (CExpires);
-- * a read is capped at what one chunk and max-size still allow (CReadCap);
-- * KernelMoved and a Tick never append; KernelMoved never clears and
--   completes only the empty creation the kernel just adopted, and a Tick
--   never completes and clears only by X1 (CQuietGoal);
-- * a new reply deadline has its Tick asked for;
-- * the epoch never decreases and the metadata never changes;
-- * KMove: the asset changes only as the adversary in Funknown.Kernel.Converge
--   may change it, so convergence carries over to the composed system.
module Funknown.Client.Contract () where

import Data.Set ()
import Funknown.Opt
import Funknown.Client.Types
import Funknown.Fault (Fault (..))
import Funknown.Kernel.Types (Asset (..), Goal (..), Assembly (..), Ending (..), Outcome (..), Vouch (..), Write (..), Config (..), goalTag, rank, goalAdopted, goalStaging, isEnded, hasReceipt)

{-@ predicate CReqKept F O =
      (isPresent (owedReq F) => (owedReq (after O) == owedReq F || isPresent (owedTo O)))
      && (isPresent (owedTo O) => isPresent (owedReq F)) @-}

{-@ predicate CEvKept E O =
      (isPresent (evReq E) => (isPresent (evTo O) || owedReq (after O) == evReq E))
      && (isPresent (evTo O) => isPresent (evReq E)) @-}

{-@ predicate CMoverKept F E O =
      owedJob F == 1 => ((isMoverReport E && evEpoch E == fileEpoch F)
                         || optEpoch (stopped O) == fileEpoch F
                         || (owedJob (after O) == 1 && fileEpoch (after O) == fileEpoch F)) @-}

{-@ predicate CJobIssued F O =
      owedJob (after O) == 1 => ((owedJob F == 1 && fileEpoch (after O) == fileEpoch F)
                                || optStartEpoch (started O) == fileEpoch (after O)) @-}

{-@ predicate CWaitTimed F O =
      (fileWait (after O) >= 0 && fileWait (after O) /= fileWait F)
        => Set_mem (fileWait (after O)) (listElts (timers O)) @-}

-- | A job a step starts runs under an epoch greater than the file's old
-- one, so a late report from any earlier job can't be taken for it.
{-@ predicate CJobFresh F O = isPresent (started O) => optStartEpoch (started O) > fileEpoch F @-}

-- | A report from the job the file is waiting for: a mover report under the
-- file's epoch while a job runs.
{-@ predicate CurrentReport F E =
      isMoverReport E && not (isPresent (evReq E)) && owedJob F == 1 && evEpoch E == fileEpoch F @-}

-- | A job's end. Once a step stops the job the file waits for, or that job
-- reports, the file no longer waits for it, because nothing more will come
-- from it. A report from any other job stops its sender, because nothing
-- else would release what that mover holds. A reader's own report either
-- stops the reader or hands its buffer to the write started under the next
-- epoch, so a read's buffer is never left behind.
{-@ predicate CJobEnded F E O =
      ((owedJob F == 1 && fileEpoch F >= 0
        && (optEpoch (stopped O) == fileEpoch F || CurrentReport F E))
         => not (owedJob (after O) == 1 && fileEpoch (after O) == fileEpoch F))
      && ((isMoverReport E && not (isPresent (evReq E)) && not (CurrentReport F E))
         => (isPresent (stopped O) && optEpoch (stopped O) == evEpoch E))
      && ((CurrentReport F E && filePhase F == 2)
         => ((isPresent (stopped O) && optEpoch (stopped O) == fileEpoch F)
             || optStartEpoch (started O) == fileEpoch F + 1)) @-}

-- | 'authorised' grows only on a step that starts a persist job.
{-@ predicate CWriteJob F O =
      len (authorised (fileAsset (after O))) > len (authorised (fileAsset F)) => optStartTag (started O) == 2 @-}

-- | The write a step authorises is named by the job the step starts, so the
-- write's own report finds it under that job's epoch, and it carries the
-- deadline A3 gives it.
{-@ predicate CWriteEntry V F O =
      len (authorised (fileAsset (after O))) > len (authorised (fileAsset F))
        => (headWriteEpoch (authorised (fileAsset (after O))) == optStartEpoch (started O)
            && headWriteBy (authorised (fileAsset (after O))) == envNow V + writeDeadline (kernel V)) @-}

-- | A write's report removes its own entry: a mover report leaves its epoch
-- out of the new 'authorised'. That covers the running write's own report
-- and a stale report from a write the file stopped waiting for (B15), which
-- would otherwise hold its entry until A3's deadline. A reader's current
-- report is the one exception: it may hand its buffer to a write, and no
-- write runs under a reader's epoch.
{-@ predicate CWriteReported F E O =
      (isMoverReport E && not (isPresent (evReq E)) && not (CurrentReport F E && filePhase F == 2))
        => not (Set_mem (evEpoch E) (writeEpochs (authorised (fileAsset (after O))))) @-}

-- | And nothing else leaves: an entry leaves 'authorised' only under the
-- epoch of the report this step handles. A write that hasn't reported can
-- still land, and converge only ever sees a late landing through its entry
-- (LateWrite), so a step that dropped a live write's entry would hide a
-- write the store may yet show, and Compose would score it as progress.
{-@ predicate CWriteKept F E O =
      (isMoverReport E
         => Set_sub (Set_dif (writeEpochs (authorised (fileAsset F))) (Set_sng (evEpoch E)))
                    (writeEpochs (authorised (fileAsset (after O)))))
      && (not (isMoverReport E)
         => Set_sub (writeEpochs (authorised (fileAsset F))) (writeEpochs (authorised (fileAsset (after O))))) @-}

-- | A job the file waits for is the kind its phase names: a read in
-- Reading, a write in Writing. A job a step starts sets that phase, and a
-- job the step keeps keeps its phase, so a write's report is never judged
-- against a reader, or the reverse.
{-@ predicate CJobKind F O =
      (optStartTag (started O) == 1 => filePhase (after O) == 2)
      && (optStartTag (started O) == 2 => filePhase (after O) == 3)
      && ((owedJob (after O) == 1 && not (isPresent (started O))) => filePhase (after O) == filePhase F) @-}

-- | G3: max-age has run out on a goal still assembling.
{-@ predicate PastDeadline V F = goalTag (goal (fileAsset F)) == 2 && envNow V >= deadline (meta F) @-}

-- | A current report of a kind the running job can't send. core.md handles
-- the store's version of this inside G2 (CH42), and CLIENT.md round 2 has
-- the mover's run "as CH42 does", so it is G2's: it runs the job's failure
-- row, and G3 never sees it.
{-@ predicate WrongKind F E =
      CurrentReport F E && ((filePhase F == 2 && writeOnlyReport E) || (filePhase F == 3 && readOnlyReport E)) @-}

-- | Which events G3 stands before: every request (CLIENT.md round 2), the
-- Tick (slice 3's expiry), and the running job's own report of its own
-- kind, since core.md's guards still apply to the B rows and only G2 comes
-- before G3. KernelMoved isn't one of them: its rows are slice 3's own,
-- not core.md's.
{-@ predicate G3Applies V F E =
      PastDeadline V F && (isPresent (evReq E) || isTick E || (CurrentReport F E && not (WrongKind F E))) @-}

-- | X1 runs first: the file ends FAILED Expired and the owed request, held
-- or in flight, is abandoned.
{-@ predicate CExpires V F E O =
      G3Applies V F E
        => (goalTag (goal (fileAsset (after O))) == 0 && outcome (fileAsset (after O)) == Ended (Failed Expired)
            && (isPresent (owedReq F) => owedTo O == Present Abandoned)) @-}

-- | A read takes at most what one chunk and max-size still allow, the cap
-- A9 and O2 both read with, defined once in "Funknown.Client.Core".
{-@ predicate CReadCap F O =
      optStartTag (started O) == 1
        => optStartBytes (started O) == readCap (goalMaxChunk (goal (fileAsset F)))
                                                (goalMaxSize (goal (fileAsset F)))
                                                (goalOffset (goal (fileAsset F))) @-}

-- | The offset a client is told (AppendAccepted's or CreatedUpload's
-- Upload-Offset) is the goal's chunk total after the step, the one number
-- 'appendTo' maintains, so no row can tell a client an offset the store
-- didn't acknowledge. A cleared goal tells no offset at all.
{-@ predicate CToldOffset O =
      (settleOffset (owedTo O) >= 0 => settleOffset (owedTo O) == goalOffset (goal (fileAsset (after O))))
      && (settleOffset (evTo O) >= 0 => settleOffset (evTo O) == goalOffset (goal (fileAsset (after O)))) @-}

-- | A persist job writes the buffer as the assembly's next chunk, into the
-- staging area the goal adopted (B3).
{-@ predicate CPersistNames F O =
      optStartTag (started O) == 2
        => (optStartChunk (started O) == goalCount (goal (fileAsset F)) + 1
            && optStartStaging (started O) == goalStaging (goal (fileAsset F))) @-}

-- | KernelMoved and a Tick carry no request and report no job, and each
-- moves the goal only by its own row. KernelMoved answers what the kernel
-- round left, so it never clears (the kernel did that already); the one
-- move it makes is round 2's empty UC ?1 creation, held in Opening on a
-- store that can seal zero chunks, which completes with the chunks it has
-- (none, since nothing can be appended before adoption) and keeps its
-- request held. A Tick only reads the clock, so it never completes; the one
-- move it makes is X1, on an assembly whose deadline has passed.
{-@ predicate CQuietGoal V F E O =
      (not (isPresent (evReq E)) && not (isMoverReport E) && not (isTick E))
        => (goal (fileAsset (after O)) == goal (fileAsset F)
            || (goalTag (goal (fileAsset F)) == 2 && goalTag (goal (fileAsset (after O))) == 1
                && goalCount (goal (fileAsset (after O))) == goalCount (goal (fileAsset F))
                && filePhase F == 0 && owedReq (after O) == owedReq F
                && not (openContent (phase (client F))) && openUc (phase (client F))
                && goalSealsEmpty (goal (fileAsset F))))
      && (isTick E
        => (goal (fileAsset (after O)) == goal (fileAsset F)
            || (goalTag (goal (fileAsset (after O))) == 0 && PastDeadline V F))) @-}

-- | The owed request was settled with the answer given (abandoned when
-- there is none), or there was none to settle: 'settle' as a predicate.
{-@ predicate SettledAs F O A =
      (isPresent (owedTo O) <=> isPresent (owedReq F))
      && (isPresent (owedReq F) => owedTo O == Present (settleWith A))
      && (not (isPresent (owedReq F)) => owedTo O == Absent) @-}

-- | The adversary's moves, and only those: the observation, receipt,
-- budget and backoff step are the reconciler's; the goal moves only down its order, keeps
-- its staging area and its chunks (which only grow), completes with exactly
-- the chunks it had or with exactly one more (Append then Complete, which is
-- B11: the completing chunk is acknowledged and completes the upload in one
-- step), and otherwise moves at most once per step; an ending once set
-- stays; and at most one write starts, only while assembling and only on a
-- step that doesn't also move the goal.
{-@ predicate KMove A B =
      seen B == seen A && vouch B == vouch A && budget B == budget A
      && backoffAt B == backoffAt A
      && rank (goal B) <= rank (goal A)
      && (goal B /= goal A => rank (goal B) < rank (goal A))
      && ((goalTag (goal B) /= 0 && goalAdopted (goal A)) => goalStaging (goal B) == goalStaging (goal A))
      && (goalTag (goal B) /= 0 => goalOffset (goal B) >= goalOffset (goal A))
      && ((goalTag (goal A) == 2 && goalTag (goal B) == 1)
          => (goalOffset (goal B) == goalOffset (goal A) || goalCount (goal B) == goalCount (goal A) + 1))
      && (isEnded (outcome A) => outcome B == outcome A)
      && len (authorised B) <= len (authorised A) + 1
      && (len (authorised B) == len (authorised A) + 1 => (goal B == goal A && goalTag (goal A) == 2)) @-}

{-@ type ClientOut V F E = {o:Out | CReqKept F o && CEvKept E o && CMoverKept F E o && CJobIssued F o
                                   && CWaitTimed F o && KMove (fileAsset F) (fileAsset (after o))
                                   && CJobFresh F o && CJobEnded F E o && CWriteJob F o && CWriteEntry V F o
                                   && CWriteReported F E o && CReadCap F o && CPersistNames F o && CQuietGoal V F E o
                                   && CToldOffset o && CWriteKept F E o && CJobKind F o && CExpires V F E o
                                   && fileEpoch (after o) >= fileEpoch F && meta (after o) == meta F} @-}
