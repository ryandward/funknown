{-# LANGUAGE Safe #-}
-- Reflection (without PLE) only so the logic knows the ladder's method
-- constructors are distinct, which is what lets 'deletion' state that a
-- DELETE never gets 304.
{-@ LIQUID "--reflection" @-}
-- | Slice 2 of the client side: the requests a client makes about the file
-- rather than about its upload resource. That is the google.longrunning
-- Operation (CancelOperation, GetOperation, DeleteOperation), the DRS object
-- (GetObject, GetAccessUrl), and the file's content (GetContent, DeleteFile),
-- each in every phase. CLIENT.md's rulings decide where they differ from
-- docs/design/core.md.
--
-- None of these requests waits on a mover job or a store call. Each one is
-- answered at once from where the file stands, and only three things move
-- the asset: a cancel while the file is still being created, a DELETE that
-- its preconditions let through, and G3's expiry, which runs before any of
-- them once the deadline has passed. All three go through 'endFile', so the
-- owed request, the running job and the goal are handled the one way the
-- client side clears a goal.
--
-- Where the file stands is computed once, by 'standingAt', and no handler
-- reads the goal, the receipt or the clock for itself. The standing is
-- what core.md's guards and kernel.md's watches would make of the file
-- before any cell runs, not just what the asset showed after the last
-- kernel round: a deadline that has passed is X1 still to run, and a
-- receipt is a held completing request the watch still has to release.
module Funknown.Client.Requests
  ( -- * One entry point per request kind
    cancelOperation
  , getOperation
  , deleteOperation
  , getObject
  , getAccessUrl
  , getContent
  , deleteFile
    -- * What the entry points share
  , requestKind
  , Standing (..), Live (..), standingTag, liveTag, standingAt
  , conditionsOf
  ) where

import Funknown.Opt
import Funknown.Fault (Fault (..))
import Funknown.Refusal (Refusal (..))
import Funknown.Client.Contract ()
import Funknown.Client.Core (answer, abandonFile, expireFile, endedReply, fileEtag, idEtag, operationOf)
import Funknown.Client.Types
import Funknown.Http.Precondition
  ( MethodKind (..), Verdict (..), ladder, ifMatch, ifNoneMatch, ifUnmodifiedSince
  , ifModifiedSince, ifRange, rangeReq )
import Funknown.Kernel.Bound (Bound)
import Funknown.Kernel.Types (Asset (..), Goal (..), Assembly (..), Ending (..), Outcome (..), Vouch (..), goalTag, hasReceipt)

-- Per-row effects, stated over the strengthened Core ---------------------------

{-@ measure fileForgotten @-}
fileForgotten :: File -> Bool
fileForgotten (File _ _ (Client _ _ _ d) _) = d

{-@ predicate Untouched F O = fileAsset (after O) == fileAsset F @-}
{-@ predicate StillCreating F = goalTag (goal (fileAsset F)) /= 0 && not (hasReceipt (vouch (fileAsset F))) @-}
-- G3 for every request (past the deadline, X1 has ended the file FAILED
-- Expired and abandoned the owed request) is ClientOut's own CExpires now,
-- which holds every slice's requests to it, so RequestOut is ClientOut.
-- A row that only answers leaves the asset alone unless G3 ran.
{-@ predicate AnswersOnly V F O = not (PastDeadline V F) => Untouched F O @-}
{-@ type RequestOut V F E = ClientOut V F E @-}

-- Which request ---------------------------------------------------------------

-- | Which of this slice's requests an event is, or 0. Each entry point
-- requires its own kind, so a dispatcher can't hand GetContent's handler an
-- Append and have it answered with content.
{-@ measure requestKind @-}
requestKind :: Event -> Int
requestKind (CancelOperation _) = 1
requestKind (GetOperation _)    = 2
requestKind (DeleteOperation _) = 3
requestKind (GetObject _)       = 4
requestKind (GetAccessUrl _)    = 5
requestKind (GetContent _ _)    = 6
requestKind (DeleteFile _ _)    = 7
requestKind _                   = 0

-- | A request's conditional header fields and Range. A request that carries
-- none has none, which is also what the shell would parse from a GET or
-- DELETE that sent none, so this is total without inventing anything.
{-@ conditionsOf :: Event -> Conditions @-}
conditionsOf :: Event -> Conditions
conditionsOf (GetContent _ cs) = cs
conditionsOf (DeleteFile _ cs) = cs
conditionsOf _                 = Conditions Absent Absent Absent Absent Absent Absent False

-- Where the file stands ---------------------------------------------------------

-- | The four things a request can find. A file is 'Cleared' or 'Live',
-- and only a live file can be ended, which 'endFile''s type says.
--
-- * 'Active': the goal keeps the asset and a receipt is held. A completing
--   request still held in Sealing is owed the watch's 201, because the
--   receipt came before anything else (kernel.md's watch table; core.md F1).
-- * 'Creating': the goal keeps the asset and no receipt is held yet.
-- * 'Expiring': G3. The goal is still assembling and the deadline has
--   passed, so X1 runs before the request's own cell, and the request is
--   then answered as the END column answers it.
-- * 'Cleared': the goal is cleared. A cleared goal can still hold a receipt,
--   between a DELETE and the store's removal, and that file is cleared, not
--   ACTIVE (K6).
--
-- Every handler matches all four, so the compiler holds each of them to
-- G3, and no handler can answer a file whose deadline has passed as if
-- it were still being created.
data Standing = Cleared | Live Live

-- | Where a file whose goal still keeps the asset stands.
data Live = Active Bound | Creating | Expiring

-- | 1 creating, 2 ACTIVE, 3 expiring.
{-@ measure liveTag @-}
{-@ liveTag :: Live -> {t:Int | 1 <= t && t <= 3} @-}
liveTag :: Live -> Int
liveTag Creating   = 1
liveTag (Active _) = 2
liveTag Expiring   = 3

-- | 0 cleared, otherwise the live standing's tag.
{-@ measure standingTag @-}
standingTag :: Standing -> Int
standingTag Cleared  = 0
standingTag (Live l) = liveTag l

-- | G3 is "in phases Opening and Receiving", which on the client side is a
-- goal still assembling, the same test the Tick's expiry uses (CLIENT.md,
-- slice 3). An assembled goal never expires (CC6). G3 is checked before the
-- receipt, as the Tick checks it, though a receipt for an assembly still in
-- progress can't arise: the kernel only vouches a sealed object.
-- P UP:RESUMABLE-UPLOAD-13-4.1.4-7 (PM40), PM13. 'PastDeadline' is the
-- contract's own predicate, the one CExpires reads.

{-@ standingAt :: env:Env -> f:File
               -> {s:Standing | (standingTag s == 0 <=> goalTag (goal (fileAsset f)) == 0)
                             && (standingTag s == 3 <=> PastDeadline env f)
                             && (standingTag s == 2 <=> (goalTag (goal (fileAsset f)) /= 0
                                                         && hasReceipt (vouch (fileAsset f))
                                                         && not (PastDeadline env f)))} @-}
standingAt :: Env -> File -> Standing
standingAt env (File m a _ _) = case a of
  Asset Clear _ _ _ _ _ _                 -> Cleared
  Asset (Keep (Assembling _ _)) _ _ _ _ _ _
    | envNow env >= deadline m            -> Live Expiring
  Asset (Keep _) _ _ NoReceipt _ _ _      -> Live Creating
  Asset (Keep _) _ _ (HasReceipt b) _ _ _ -> Live (Active b)

{-@ fileIdOf :: f:File -> {i:FileId | i == fileId (meta f)} @-}
fileIdOf :: File -> FileId
fileIdOf (File (Meta i _ _ _) _ _ _) = i

{-@ lastModified :: File -> Int @-}
lastModified :: File -> Int
lastModified (File (Meta _ _ _ t) _ _ _) = t

-- Ending the file -----------------------------------------------------------------

-- | The one way this slice ends a live file before its deadline: the goal
-- is cleared with the ending, the event gets its row's reply, and the
-- request the file owes gets what the standing says it is owed at that
-- moment. Past the deadline G3 ends it instead ('expire').
{-@ endFile :: env:Env -> ev:{Event | isPresent (evReq ev)}
            -> f:{File | goalTag (goal (fileAsset f)) /= 0 && not (PastDeadline env f)}
            -> s:{Live | liveTag s /= 3} -> e:Ending -> r:{Reply | replyOffset r < 0}
            -> {o:ClientOut env f ev | goalTag (goal (fileAsset (after o))) == 0
                                    && outcome (fileAsset (after o)) == Ended e
                                    && evTo o == Present (Answer r)
                                    && ((liveTag s == 1 && isPresent (owedReq f))
                                          => owedTo o == Present (Answer (Refuse (endingRefusal e) (Present True))))
                                    && ((liveTag s == 2 && isPresent (owedReq f))
                                          => owedTo o == Present (Answer (CreatedFile (fileId (meta f)) (idEtag (fileId (meta f))))))} @-}
endFile :: Env -> Event -> File -> Live -> Ending -> Reply -> Out
endFile env ev f s ending r = abandonFile env ev f ending (owedOnEnd s f ending) (Present r)

-- | What the request the file owes is told when one of this slice's rows
-- clears the goal under it.
--
-- * ACTIVE: the only request an ACTIVE file can owe is a completing request
--   held in Sealing, and its receipt appeared before the goal was cleared,
--   so it gets the watch's 201 with the ETag and UC ?1, as KernelMoved
--   would have answered it. kernel.md's watch table; core.md F1 ("ACTIVE,
--   even if cancelRequested"). R HS:RFC9110-15.3.2-1
-- * Still being created: the ending's refusal with UC ?1, because its upload
--   can't go on (CLIENT.md, CancelOperation).
-- * Expiring: X1 abandons the held request or the slot's request, as the
--   Tick's expiry does. P UP:RESUMABLE-UPLOAD-13-4.1.4-7 (PM40); C CH6
{-@ owedOnEnd :: l:Live -> f:File -> e:Ending
              -> {r:Opt Reply | optReplyOffset r < 0 && (liveTag l == 3 => (r == Absent && settleWith r == Abandoned))
                               && (liveTag l == 1 => settleWith r == Answer (Refuse (endingRefusal e) (Present True)))
                               && (liveTag l == 2 => settleWith r == Answer (CreatedFile (fileId (meta f)) (idEtag (fileId (meta f)))))} @-}
owedOnEnd :: Live -> File -> Ending -> Opt Reply
owedOnEnd (Active _) f _      = Present (CreatedFile (fileIdOf f) (fileEtag f))
owedOnEnd Creating   _ ending = Present (endedReply ending)
owedOnEnd Expiring   _ _      = Absent

-- | G3: X1 runs first, through the one X1 every slice shares, and the event
-- gets r, the reply its row gives in the END column, since that is where X1
-- leaves the file. X1's ending is FAILED Expired.
-- P UP:RESUMABLE-UPLOAD-13-4.1.4-7 (PM40), PM13; C CH6 (clause 6)
{-@ expire :: env:Env -> ev:{Event | isPresent (evReq ev)} -> f:{File | PastDeadline env f}
           -> r:{Reply | replyOffset r < 0}
           -> {o:ClientOut env f ev | goalTag (goal (fileAsset (after o))) == 0
                                     && outcome (fileAsset (after o)) == Ended (Failed Expired)
                                     && evTo o == Present (Answer r)
                                     && (isPresent (owedReq f) => owedTo o == Present Abandoned)} @-}
expire :: Env -> Event -> File -> Reply -> Out
expire env ev f r = expireFile env ev f (Present r)

-- The operation ------------------------------------------------------------------

-- | G4: once the client deleted the operation, every operation request is
-- 404. DeleteOperation only says the client "is no longer interested in the
-- operation result", so the 404 afterwards is our choice. G4 comes after
-- G3, so an expired file is still ended first. C CH38
{-@ operationForgotten :: f:File -> {b:Bool | b <=> fileForgotten f} @-}
operationForgotten :: File -> Bool
operationForgotten (File _ _ (Client _ _ _ d) _) = d

-- | An operation request's reply after G4.
{-@ unlessForgotten :: File -> r:Reply -> {v:Reply | replyOffset r < 0 => replyOffset v < 0} @-}
unlessForgotten :: File -> Reply -> Reply
unlessForgotten f r
  | operationForgotten f = Refuse NotFound Absent
  | otherwise            = r

-- | Cancelling a file that is still being created ends it, and a cancel of a
-- done operation is accepted and changes nothing.
--
-- * G3 first: an expired file is FAILED Expired, not cancelled, and the
--   cancel then meets a done operation (Q1), or G4.
-- * G4. C CH38
-- * O6, A11, B1, B15, F9, I12: while the goal keeps the asset without a
--   receipt, the file is CANCELLED through 'endFile', which stops a
--   running mover. The owed request gets the cancel's ending refusal with
--   UC ?1, because its upload can't go on, and the cancel gets 200.
--   R SS:LRO-CancelOperation-3; P HS:RFC9110-9.3.5-3 (PM29); C CH6, CH9
-- * Q1: ACTIVE, or the goal already cleared: the operation is done, so the
--   cancel is answered 200 and nothing changes. A completing request still
--   held stays held, for the watch to answer. R SS:LRO-CancelOperation-1
{-@ cancelOperation :: env:Env -> ev:{Event | requestKind ev == 1 && isPresent (evReq ev)} -> f:File
                    -> {o:RequestOut env f ev |
                         ((not (PastDeadline env f) && not (fileForgotten f) && StillCreating f)
                            => outcome (fileAsset (after o)) == Ended Cancelled)
                         && ((not (PastDeadline env f) && not (fileForgotten f) && StillCreating f && isPresent (owedReq f))
                            => owedTo o == Present (Answer (Refuse (endingRefusal Cancelled) (Present True))))
                         && ((not (PastDeadline env f) && not (not (fileForgotten f) && StillCreating f))
                            => Untouched f o)} @-}
cancelOperation :: Env -> Event -> File -> Out
cancelOperation env ev f = case standingAt env f of
  Live Expiring            -> expire env ev f (unlessForgotten f CancelAccepted)
  _ | operationForgotten f -> answer env ev f (Refuse NotFound Absent)
  Live l@Creating          -> endFile env ev f l Cancelled CancelAccepted
  Live (Active _)          -> answer env ev f CancelAccepted
  Cleared                  -> answer env ev f CancelAccepted

-- | Q2: the operation as the asset shows it, in every phase, after G3 and
-- G4. After X1 that is FAILED Expired, which is how 'operationOf' reads the
-- ending X1 sets. R SS:LRO-GetOperation, SS:LRO-Operation-done; C CH38 (G4)
{-@ getOperation :: env:Env -> ev:{Event | requestKind ev == 2 && isPresent (evReq ev)} -> f:File
                 -> {o:RequestOut env f ev | AnswersOnly env f o} @-}
getOperation :: Env -> Event -> File -> Out
getOperation env ev f = case standingAt env f of
  Live Expiring   -> expire env ev f (unlessForgotten f (OperationIs (OpFailed Expired)))
  Live (Active _) -> answer env ev f (unlessForgotten f (OperationIs (operationOf f)))
  Live Creating   -> answer env ev f (unlessForgotten f (OperationIs (operationOf f)))
  Cleared         -> answer env ev f (unlessForgotten f (OperationIs (operationOf f)))

-- | Q3: the client is no longer interested in the result. Only 'opDeleted'
-- changes; the file's life goes on, or ends by X1 if G3 ran first.
-- R SS:LRO-DeleteOperation; P HS:RFC9110-9.3.5-3 (PM29); C CH38 (G4)
{-@ deleteOperation :: env:Env -> ev:{Event | requestKind ev == 3 && isPresent (evReq ev)} -> f:File
                    -> {o:RequestOut env f ev | AnswersOnly env f o && (not (fileForgotten f) => fileForgotten (after o))} @-}
deleteOperation :: Env -> Event -> File -> Out
deleteOperation env ev f = case standingAt env f of
  Live Expiring
    | operationForgotten f -> expire env ev f (Refuse NotFound Absent)
    | otherwise            -> forgetAfter env ev f (expire env ev f NoContent)
  _
    | operationForgotten f -> answer env ev f (Refuse NotFound Absent)
    | otherwise            -> forgetAfter env ev f (answer env ev f NoContent)

-- | A step's output with the operation deleted in the file it leaves. The
-- contract only reads what 'forgetOperation' keeps, so the step's proof
-- carries over.
{-@ forgetAfter :: env:Env -> ev:Event -> f:File -> o:ClientOut env f ev
                -> {p:ClientOut env f ev | fileAsset (after p) == fileAsset (after o) && evTo p == evTo o
                                        && fileForgotten (after p)} @-}
forgetAfter :: Env -> Event -> File -> Out -> Out
forgetAfter _ _ _ (Out g ow et st sr tm al) = Out (forgetOperation g) ow et st sr tm al

-- | The file with its operation deleted and everything else as it was.
{-@ forgetOperation :: f:File
                    -> {g:File | fileAsset g == fileAsset f && owedReq g == owedReq f && owedJob g == owedJob f
                              && fileWait g == fileWait f && fileEpoch g == fileEpoch f && meta g == meta f
                              && filePhase g == filePhase f
                              && fileForgotten g} @-}
forgetOperation :: File -> File
forgetOperation (File m a (Client l o ph _) e) = File m a (Client l o ph True) e

-- The DRS object -------------------------------------------------------------------

-- | GetObject and GetAccessUrl differ only in what an ACTIVE file answers,
-- so both go through this one split.
--
-- * R1: still being created: 202 with Retry-After. P
--   DO:DRS-responses.202Accepted-1 (PM36); R DO:DRS-responses.202Accepted.Retry-After-1
-- * The goal cleared, or cleared by X1 first: 404, because DRS's tables
--   have no 410. R DO:DRS-responses.404NotFoundDrsObject-1; P PM30, PM41
{-@ drs :: env:Env -> ev:{Event | isPresent (evReq ev)} -> f:File -> (FileId -> Bound -> {r:Reply | replyOffset r < 0})
        -> {o:RequestOut env f ev | AnswersOnly env f o} @-}
drs :: Env -> Event -> File -> (FileId -> Bound -> Reply) -> Out
drs env ev f ready = case standingAt env f of
  Live (Active b) -> answer env ev f (ready (fileIdOf f) b)
  Live Creating   -> answer env ev f (Pending Absent (Present (pendingDelay env)) False)
  Live Expiring   -> expire env ev f (Refuse NotFound Absent)
  Cleared         -> answer env ev f (Refuse NotFound Absent)

-- | R2 when ACTIVE: the DRS object. R DO:DRS-schemas.DrsObject-1,
-- DO:DRS-paths.objects.{object_id}.get-1
{-@ getObject :: env:Env -> ev:{Event | requestKind ev == 4 && isPresent (evReq ev)} -> f:File
              -> {o:RequestOut env f ev | AnswersOnly env f o} @-}
getObject :: Env -> Event -> File -> Out
getObject env ev f = drs env ev f ObjectIs

-- | R3 when ACTIVE: the access URL. R
-- DO:DRS-paths.objects.{object_id}.access.{access_id}.get-2
{-@ getAccessUrl :: env:Env -> ev:{Event | requestKind ev == 5 && isPresent (evReq ev)} -> f:File
                 -> {o:RequestOut env f ev | AnswersOnly env f o} @-}
getAccessUrl :: Env -> Event -> File -> Out
getAccessUrl env ev f = drs env ev f AccessIs

-- The content ----------------------------------------------------------------------

-- | GetContent.
--
-- * R4, ACTIVE: the receipt and the request's conditions; the projection
--   runs the ladder and then the range. R HS:RFC9110-13.2.2-1,
--   HS:RFC9110-15.3.7.1, HS:RFC9110-15.4.5-2
-- * Still being created: there is no content yet, the table's 404 cell.
-- * The goal cleared, or cleared by X1 first: 410, the table's END and DEL
--   cells, which CLIENT.md extends to a delete still in progress.
--   R HS:RFC9110-15.5.11-1; P PM41
{-@ getContent :: env:Env -> ev:{Event | requestKind ev == 6 && isPresent (evReq ev)} -> f:File
               -> {o:RequestOut env f ev | AnswersOnly env f o} @-}
getContent :: Env -> Event -> File -> Out
getContent env ev f = case standingAt env f of
  Live (Active b) -> answer env ev f (Content b (conditionsOf ev))
  Live Creating   -> answer env ev f (Refuse NotFound Absent)
  Live Expiring   -> expire env ev f (Refuse Gone Absent)
  Cleared         -> answer env ev f (Refuse Gone Absent)

-- | DeleteFile.
--
-- * R5, ACTIVE: the ladder decides. Going ahead clears the goal with the
--   ending Deleted and answers 202, because the store still has to remove
--   the object. A completing request still held gets its 201 first
--   ('owedOnEnd'). A failed precondition is 412 and nothing changes.
--   P HS:RFC9110-9.3.5-3 (PM29); R HS:RFC9110-13.1.1-5
-- * Still being created: 409, the table's cell.
-- * R7, the goal cleared, or cleared by X1 first: 410 whatever the
--   preconditions say, because 410 is the unconditional answer. CLIENT.md
--   gives a delete still in progress the same answer in place of R6.
--   R HS:RFC9110-15.5.11-1, HS:RFC9110-13.2.1-2; P PM41
{-@ deleteFile :: env:Env -> ev:{Event | requestKind ev == 7 && isPresent (evReq ev)} -> f:File
               -> {o:RequestOut env f ev |
                    ((not (PastDeadline env f) && not (hasReceipt (vouch (fileAsset f)) && goalTag (goal (fileAsset f)) /= 0))
                       => Untouched f o)
                    && ((not (PastDeadline env f) && goalTag (goal (fileAsset (after o))) == 0 && goalTag (goal (fileAsset f)) /= 0)
                       => evTo o == Present (Answer (Pending Absent Absent False)))
                    && ((not (PastDeadline env f) && goalTag (goal (fileAsset (after o))) == 0
                         && goalTag (goal (fileAsset f)) /= 0 && isPresent (owedReq f))
                       => owedTo o == Present (Answer (CreatedFile (fileId (meta f)) (idEtag (fileId (meta f))))))} @-}
deleteFile :: Env -> Event -> File -> Out
deleteFile env ev f = case standingAt env f of
  Live l@(Active _) -> case deletion (conditionsOf ev) f of
    Proceed _ -> endFile env ev f l Deleted (Pending Absent Absent False)
    V412      -> answer env ev f (Refuse PreconditionFailed Absent)
    -- Unreachable, by 'deletion''s type. RFC 9110 13.2.2 step 3 answers
    -- 304 only to GET and HEAD and 412 to every other method.
    V304      -> answer env ev f (Refuse PreconditionFailed Absent)
  Live Creating -> answer env ev f (Refuse OperationInProgress Absent)
  Live Expiring -> expire env ev f (Refuse Gone Absent)
  Cleared       -> answer env ev f (Refuse Gone Absent)

-- | The ladder for a DELETE at the origin of an ACTIVE file, whose response
-- without preconditions would be 202. Every header is evaluated against the
-- file's entity tag and its creation as the last modification; the ladder
-- itself ignores the ones RFC 9110 doesn't consult for a DELETE.
-- R HS:RFC9110-13.2.2-1, HS:RFC9110-13.2.1-2
{-@ deletion :: Conditions -> File -> {v:Verdict | v /= V304} @-}
deletion :: Conditions -> File -> Verdict
deletion (Conditions im inm ius ims rng ir _) f =
  ladder 202 True MUnsafe
    (ifMatch im (Present (fileEtag f)))
    (ifUnmodifiedSince ius (Present (lastModified f)))
    (ifNoneMatch inm (Present (fileEtag f)))
    (ifModifiedSince ims (Present (lastModified f)))
    (rangeReq (isPresent rng) (ifRange ir (Present (fileEtag f))))
