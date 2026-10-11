{-# LANGUAGE Safe #-}
-- | The client side's only ways to change the kernel's asset, one per move
-- the adversary in Funknown.Kernel.Converge may make, and the helpers every
-- client row shares. A row that wants to touch the asset goes through one of
-- these, so KMove is proved here once, and each move states its own effect,
-- so a row that calls the wrong one, or calls none, can't meet its spec.
module Funknown.Client.Core
  ( clearGoal, appendTo, completeGoal, startWrite, reportWrite
  , answer, stale, settle, settleWith
  , abandonFile, expireFile, pastDeadline, endingRefusal, endedReply
  , operationOf
  , readCapOf
  , fileEtag, idEtag
  ) where

import Data.Set ()
import Funknown.Opt
import Funknown.Fault (Fault (..))
import Funknown.Refusal (Refusal (..))
import Funknown.Http.Validator (EntityTag (..), OpaqueTag (..))
import Funknown.Client.Contract ()
import Funknown.Client.Types
import Funknown.Kernel.Types (Asset (..), Goal (..), Assembly (..), Ending (..), Outcome (..), Vouch (..), Write (..), goalTag, rank, goalAdopted, goalStaging, isEnded, hasReceipt)
import Funknown.Upload (Chunk (..), Chunks, Limits (..), appendChunk, canAppend, room, limitsOf, offsetOf)

-- Moves on the asset ----------------------------------------------------------------

-- | Abandon: a cancel, a DELETE, expiry or a refused creation clears a goal
-- that still keeps the asset, with that ending.
{-@ clearGoal :: a:{Asset | goalTag (goal a) /= 0} -> e:Ending
              -> {b:Asset | KMove a b && goalTag (goal b) == 0 && authorised b == authorised a
                           && outcome b == Ended e} @-}
clearGoal :: Asset -> Ending -> Asset
clearGoal (Asset _ _ s v b st w) e = Asset Clear (Ended e) s v b st w

-- | Append: a chunk the store acknowledged durable joins the assembly, if
-- the assembly accepts it. The rank drops by one, because the cap leaves
-- room for one fewer chunk.
{-@ appendTo :: a:{Asset | goalTag (goal a) == 2 && goalAdopted (goal a)} -> k:Chunk
             -> Opt {b:Asset | KMove a b && goalTag (goal b) == 2 && goalAdopted (goal b)
                              && goalOffset (goal b) == goalOffset (goal a) + cbytes k
                              && goalCount (goal b) == goalCount (goal a) + 1
                              && authorised b == authorised a && outcome b == outcome a} @-}
appendTo :: Asset -> Chunk -> Opt Asset
appendTo (Asset (Keep (Assembling (Present r) c)) o s v b st w) k
  | canAppend c (cbytes k) = Present (Asset (Keep (Assembling (Present r) (appendChunk c k))) o s v b st w)
appendTo _ _ = Absent

-- | Complete: the assembly is marked complete with exactly the chunks it has.
{-@ completeGoal :: a:{Asset | goalTag (goal a) == 2 && goalAdopted (goal a)}
                 -> {b:Asset | KMove a b && goalTag (goal b) == 1 && goalOffset (goal b) == goalOffset (goal a)
                              && goalCount (goal b) == goalCount (goal a) && authorised b == authorised a
                              && outcome b == outcome a} @-}
completeGoal :: Asset -> Asset
completeGoal (Asset (Keep (Assembling (Present r) c)) o s v b st w) = Asset (Keep (Assembled r c)) o s v b st w
completeGoal a = a

-- | Start a write: one more write the core started and hasn't seen reported,
-- named by the job writing it, with the deadline by which the shell aborts
-- it (A3). Only while assembling.
{-@ startWrite :: a:{Asset | goalTag (goal a) == 2} -> e:Int -> dl:Int
               -> {b:Asset | KMove a b && goal b == goal a && len (authorised b) == len (authorised a) + 1
                            && headWriteEpoch (authorised b) == e && headWriteBy (authorised b) == dl
                            && writeEpochs (authorised b) == Set_cup (Set_sng e) (writeEpochs (authorised a))
                            && outcome b == outcome a} @-}
startWrite :: Asset -> Int -> Int -> Asset
startWrite (Asset g o s v b st w) e dl = Asset g o s v b st (Write e dl : w)

-- | Report a write: every entry under its epoch goes, whatever the report
-- said, and every other epoch keeps its entries. A report under an epoch
-- with no entry changes nothing.
{-@ reportWrite :: a:Asset -> e:Int
                -> {b:Asset | KMove a b && goal b == goal a && outcome b == outcome a
                             && len (authorised b) <= len (authorised a)
                             && writeEpochs (authorised b) == Set_dif (writeEpochs (authorised a)) (Set_sng e)} @-}
reportWrite :: Asset -> Int -> Asset
reportWrite (Asset g o s v b st w) e = Asset g o s v b st (unlist e w)

{-@ unlist :: e:Int -> ws:[Write]
           -> {r:[Write] | len r <= len ws && writeEpochs r == Set_dif (writeEpochs ws) (Set_sng e)} @-}
unlist :: Int -> [Write] -> [Write]
unlist _ [] = []
unlist e (x@(Write e' _) : xs)
  | e == e'   = unlist e xs
  | otherwise = x : unlist e xs

-- The read cap -------------------------------------------------------------------

-- | The read cap for an assembly's chunks, the one value every row that
-- starts a read uses (A9, O2). 'readCap' itself is in "Funknown.Client.Types",
-- because ClientOut states it and the contract can't import this module.
{-@ readCapOf :: c:Chunks -> {v:Int | v == readCap (maxChunk (limitsOf c)) (maxSize (limitsOf c)) (offsetOf c)} @-}
readCapOf :: Chunks -> Int
readCapOf c = readCap (maxChunk (limitsOf c)) (maxSize (limitsOf c)) (offsetOf c)

-- | The file's ETag: strong, with the file id's string as its opaque-tag. A
-- file's bytes never change once it is ACTIVE, so the id identifies them.
{-@ measure idEtag @-}
idEtag :: FileId -> EntityTag
idEtag (FileId s) = EntityTag False (OpaqueTag s)

{-@ fileEtag :: f:File -> {t:EntityTag | t == idEtag (fileId (meta f))} @-}
fileEtag :: File -> EntityTag
fileEtag (File (Meta i _ _ _) _ _ _) = idEtag i

-- Shared rows ------------------------------------------------------------------

-- | The settlement for a request the old state owed, if it owed one.
{-@ settle :: o:Opt ReqId -> a:Opt Reply
           -> {s:Opt Settle | (isPresent s <=> isPresent o)
                             && (isPresent o => (s == Present (settleWith a) && settleOffset s == optReplyOffset a))
                             && ((isPresent o && not (isPresent a)) => s == Present Abandoned)
                             && (not (isPresent o) => (s == Absent && settleOffset s == -1))} @-}
settle :: Opt ReqId -> Opt Reply -> Opt Settle
settle Absent      _           = Absent
settle (Present _) (Present x) = Present (Answer x)
settle (Present _) Absent      = Present Abandoned

-- | Answer the event's own request and change nothing else. G3 comes before
-- any answer, so a goal past its deadline is expired first ('expireFile').
{-@ answer :: env:Env -> ev:{Event | isPresent (evReq ev)} -> f:{File | not (PastDeadline env f)}
           -> x:{Reply | replyOffset x < 0 || replyOffset x == goalOffset (goal (fileAsset f))}
           -> {o:ClientOut env f ev | after o == f && evTo o == Present (Answer x) && not (isPresent (owedTo o))} @-}
answer :: Env -> Event -> File -> Reply -> Out
answer _ _ f x = Out f Absent (Present (Answer x)) Absent Absent [] Absent

-- | A report or Tick the file isn't waiting for. The client side and the goal
-- stay as they are. A mover's report also stops that mover, since nothing
-- else would release what it holds, and reports under its own epoch, so a
-- write the file stopped waiting for (B15) gives up its entry; with no entry
-- under that epoch, nothing changes, and no other epoch's entry goes. A
-- report from the job the file is waiting for is never stale: stopping that
-- job and still waiting for it would leave the file waiting on a job that
-- will never report. A Tick past an assembly's deadline isn't stale either:
-- it is X1's.
{-@ stale :: env:Env -> ev:{Event | not (isPresent (evReq ev))}
          -> f:{File | not (CurrentReport f ev) && not (isTick ev && PastDeadline env f)}
          -> {o:ClientOut env f ev | not (isPresent (owedTo o)) && not (isPresent (evTo o)) && not (isPresent (started o))
                                    && client (after o) == client f && goal (fileAsset (after o)) == goal (fileAsset f)
                                    && outcome (fileAsset (after o)) == outcome (fileAsset f)
                                    && fileEpoch (after o) == fileEpoch f
                                    && (isMoverReport ev
                                          => (writeEpochs (authorised (fileAsset (after o)))
                                                == Set_dif (writeEpochs (authorised (fileAsset f))) (Set_sng (evEpoch ev))
                                              && stopped o == Present (evEpoch ev)))
                                    && (not (isMoverReport ev) => (after o == f && not (isPresent (stopped o))))
                                    && len (timers o) == 0} @-}
stale :: Env -> Event -> File -> Out
stale _ ev f = case f of
  File m a c e
    | isMoverReport ev -> Out (File m (reportWrite a (evEpoch ev)) c e) Absent Absent (Present (evEpoch ev)) Absent [] Absent
    | otherwise        -> Out f Absent Absent Absent Absent [] Absent

-- | The file's google.longrunning Operation: running while the goal keeps an
-- asset without a receipt, done with the DRS object once there is one, and
-- failed or cancelled by the ending.
operationOf :: File -> Op
operationOf (File m a _ _) = case outcome a of
  Ended (Failed f) -> OpFailed f
  Ended Cancelled  -> OpCancelled
  Ended Deleted    -> case vouch a of
    HasReceipt b -> OpSucceeded (fileId m) b
    NoReceipt    -> OpCancelled
  Ongoing -> case vouch a of
    HasReceipt b -> OpSucceeded (fileId m) b
    NoReceipt    -> OpRunning

-- | The reply a request still waiting on the file gets when the goal is
-- cleared under it: the ending's refusal ('endingRefusal', a measure in
-- "Funknown.Client.Types"), with UC ?1, because its upload can't go on. No
-- ending's refusal carries an offset, which the cases below show one by one.
{-@ endedReply :: e:Ending -> {r:Reply | r == Refuse (endingRefusal e) (Present True) && replyOffset r < 0} @-}
endedReply :: Ending -> Reply
endedReply Deleted    = Refuse Gone (Present True)
endedReply Cancelled  = Refuse Gone (Present True)
endedReply (Failed f) = faultReply f

{-@ faultReply :: f:Fault -> {r:Reply | r == Refuse (faultRefusal f) (Present True) && replyOffset r < 0} @-}
faultReply :: Fault -> Reply
faultReply f = case f of
  Expired              -> Refuse Gone (Present True)
  FinalizeTimedOut     -> Refuse (StoreUnavailable Absent) (Present True)
  OutOfRange           -> Refuse Internal (Present True)
  TooLarge             -> Refuse Internal (Present True)
  QuotaAtFinalize      -> Refuse InsufficientStorage (Present True)
  Revoked              -> Refuse Internal (Present True)
  Empty                -> Refuse Internal (Present True)
  CreationRefused      -> Refuse Internal (Present True)
  CreationInterrupted  -> Refuse Internal (Present True)
  StateLost            -> Refuse DataLoss (Present True)
  SizeMismatch         -> Refuse DataLoss (Present True)
  ObjectWithoutReceipt -> Refuse Internal (Present True)
  StoreRefusedUs       -> Refuse Internal (Present True)
  Contradiction        -> Refuse Internal (Present True)
  Unavailable          -> Refuse (StoreUnavailable Absent) (Present True)
  SourceUnreachable    -> Refuse Internal (Present True)
  SourceAnswered _     -> Refuse Internal (Present True)
  SourceChanged        -> Refuse Internal (Present True)

-- | The one way the client side clears a goal: a cancel, a DELETE, expiry, a
-- refused or interrupted creation, or a contradiction from the shell. The
-- goal becomes Clear with the ending, the owed request is settled with
-- @owedAns@ (abandoned when there is none), the event with @evAns@, a
-- running mover job is stopped, and the client side settles. The reconciler
-- then cleans up whatever the store holds.
--
-- A mover's report can end the file only when it comes from the job the
-- file is waiting for (a stale report changes nothing, G2), and a write's
-- report has to be reported before the file ends, so its entry is gone.
-- Once G3 applies, the only ending is X1's, and the owed request is
-- abandoned: every row that clears a goal is held to G3 here, once. Only a
-- request, a report or X1's Tick clears a goal; KernelMoved never does,
-- because the kernel round it answers already did whatever clearing there
-- was (CQuietGoal).
{-@ abandonFile :: env:Env
                -> ev:Event
                -> f:{File | goalTag (goal (fileAsset f)) /= 0
                             && (isPresent (evReq ev) || isMoverReport ev || (isTick ev && PastDeadline env f))
                             && ((isMoverReport ev && not (isPresent (evReq ev))) => CurrentReport f ev)
                             && ((isMoverReport ev && not (isPresent (evReq ev)) && filePhase f /= 2)
                                   => not (Set_mem (evEpoch ev) (writeEpochs (authorised (fileAsset f)))))}
                -> ending:{Ending | G3Applies env f ev => ending == Failed Expired}
                -> owedAns:{Opt Reply | optReplyOffset owedAns < 0 && (G3Applies env f ev => not (isPresent owedAns))}
                -> evAns:{Opt Reply | (isPresent evAns <=> isPresent (evReq ev)) && optReplyOffset evAns < 0}
                -> {o:ClientOut env f ev | goalTag (goal (fileAsset (after o))) == 0
                                          && outcome (fileAsset (after o)) == Ended ending
                                          && authorised (fileAsset (after o)) == authorised (fileAsset f)
                                          && evTo o == optAnswer evAns
                                          && SettledAs f o owedAns && not (isPresent (started o))
                                          && owedJob (after o) == 0 && filePhase (after o) == 5} @-}
abandonFile :: Env -> Event -> File -> Ending -> Opt Reply -> Opt Reply -> Out
abandonFile _ _ (File m a c e) ending owedAns evAns =
  Out (File m (clearGoal a ending) (settled c) (e + 1))
      (settle (phaseReq (phase c)) owedAns)
      (answerWith evAns)
      (if phaseJob (phase c) == 1 then Present e else Absent)
      Absent [] Absent

-- | G3's test, as a value: the goal is still assembling and max-age has
-- run out. An assembled goal never expires (CC6).
{-@ pastDeadline :: env:Env -> f:File -> {b:Bool | b <=> PastDeadline env f} @-}
pastDeadline :: Env -> File -> Bool
pastDeadline env (File m a _ _) = case a of
  Asset (Keep (Assembling _ _)) _ _ _ _ _ _ -> envNow env >= deadline m
  _                                         -> False

-- | X1 (G3): max-age ran out while the upload was still assembling, so the
-- file ends FAILED Expired before the event's own row runs. The held or
-- in-flight request is abandoned and a running mover stopped; when the
-- event is the running job's own report, that job is done, so a write's
-- entry is reported first. The event's request, if any, gets @evAns@, the
-- answer the END column gives it.
-- P UP:RESUMABLE-UPLOAD-13-4.1.4-7 (PM40), PM13; C CH6 (clause 6)
{-@ expireFile :: env:Env -> ev:Event
               -> f:{File | PastDeadline env f && (isPresent (evReq ev) || isMoverReport ev || isTick ev)
                            && ((isMoverReport ev && not (isPresent (evReq ev))) => CurrentReport f ev)}
               -> evAns:{Opt Reply | (isPresent evAns <=> isPresent (evReq ev)) && optReplyOffset evAns < 0}
               -> {o:ClientOut env f ev | goalTag (goal (fileAsset (after o))) == 0
                                         && outcome (fileAsset (after o)) == Ended (Failed Expired)
                                         && evTo o == optAnswer evAns && SettledAs f o Absent
                                         && not (isPresent (started o))} @-}
expireFile :: Env -> Event -> File -> Opt Reply -> Out
expireFile env ev f evAns = case f of
  File m a c e -> case evReq ev of
    Absent
      | isMoverReport ev -> abandonFile env ev (File m (reportWrite a e) c e) (Failed Expired) Absent evAns
      | otherwise        -> abandonFile env ev f (Failed Expired) Absent evAns
    Present _ -> abandonFile env ev f (Failed Expired) Absent evAns

{-@ answerWith :: a:Opt Reply -> {s:Opt Settle | s == optAnswer a && (isPresent s <=> isPresent a)
                                                  && settleOffset s == optReplyOffset a} @-}
answerWith :: Opt Reply -> Opt Settle
answerWith Absent      = Absent
answerWith (Present x) = Present (Answer x)

{-@ settled :: c:Client -> {d:Client | phaseTag (phase d) == 5 && phaseReq (phase d) == Absent
                                      && phaseJob (phase d) == 0 && phaseWait (phase d) == -1} @-}
settled :: Client -> Client
settled (Client l o _ d) = Client l o Settled d
