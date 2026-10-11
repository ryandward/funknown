{-# LANGUAGE Safe #-}
-- | Slice 1 of the client side: the three requests to the upload resource
-- (PATCH, HEAD and DELETE) in every phase, and the mover's reports on the
-- body it reads and the chunk it writes. The rows are the A, B, F and V rows
-- of docs/design/core.md, adapted to the kernel by CLIENT.md.
--
-- Every entry point's result is 'ClientOut', so LiquidHaskell holds each row
-- to the whole client contract, and the asset only ever changes through the
-- moves in "Funknown.Client.Core". Which reply a client gets is not in the
-- contract; test/UploadReplies.hs checks that part against the design.
module Funknown.Client.Upload
  ( uploadEventKind
  , appendCheck
  , onAppend, onOffsetQuery, onCancelUpload
  , onBodyReceived, onBodyBroken, onChunkPersisted, onChunkFailed, onMoverDied
  ) where

import Funknown.Opt
import Funknown.Fault (Fault (..))
import Funknown.Refusal (Refusal (..))
import Funknown.Client.Contract ()
import Funknown.Client.Core
import Funknown.Client.Types
import Funknown.Kernel.Types (Asset (..), Goal (..), Assembly (..), Ending (..), Outcome (..), Vouch (..), Config (..), goalTag, goalAdopted, goalStaging, hasReceipt, isEnded)
import Funknown.Upload (Chunk (..), Chunks, Limits (..), limitsOf, offsetOf, nChunks)

-- What this slice handles --------------------------------------------------------

-- | Which of this slice's events an event is: 0 to 2 are the upload
-- resource's requests, 3 to 7 the mover's reports, -1 anything else. The
-- entry points' preconditions name it, so a dispatcher that matches the
-- event's constructor has already established it.
{-@ measure uploadEventKind @-}
uploadEventKind :: Event -> Int
uploadEventKind (Append _)           = 0
uploadEventKind (OffsetQuery _)      = 1
uploadEventKind (CancelUpload _)     = 2
uploadEventKind (BodyReceived _ _)   = 3
uploadEventKind (BodyBroken _ _)     = 4
uploadEventKind (ChunkPersisted _ _) = 5
uploadEventKind (ChunkFailed _)      = 6
uploadEventKind (MoverDied _)        = 7
uploadEventKind _                    = -1

-- | Whether the request in flight is the creation request's own content,
-- whose failures end the file (B16).
{-@ measure reqCreation @-}
reqCreation :: Req -> Bool
reqCreation (CreationReq _) = True
reqCreation (AppendReq _)   = False

{-@ measure phaseCreation @-}
phaseCreation :: Phase -> Bool
phaseCreation (Reading q _)             = reqCreation q
phaseCreation (Writing (Present q) _ _) = reqCreation q
phaseCreation (Writing Absent _ _)      = False
phaseCreation (Opening _)               = False
phaseCreation Idle                      = False
phaseCreation (Sealing _)               = False
phaseCreation Settled                   = False

-- | The bytes the running write was handed, or -1.
{-@ measure phaseBytes @-}
phaseBytes :: Phase -> Int
phaseBytes (Writing _ n _) = n
phaseBytes (Opening _)     = -1
phaseBytes Idle            = -1
phaseBytes (Reading _ _)   = -1
phaseBytes (Sealing _)     = -1
phaseBytes Settled         = -1

{-@ predicate FileCreation F = phaseCreation (phase (client F)) @-}
{-@ predicate EndsAs F O X = goalTag (goal (fileAsset (after O))) == 0 && outcome (fileAsset (after O)) == Ended X @-}

-- | B9's effect, and B16's for the creation request: nothing of the read is
-- kept and its request is abandoned, never answered.
{-@ predicate ReaderDiedRow F O =
      (FileCreation F => (EndsAs F O (Failed CreationInterrupted) && SettledAs F O Absent))
      && (not (FileCreation F) => (fileAsset (after O) == fileAsset F && filePhase (after O) == 1 && SettledAs F O Absent)) @-}

-- | B12's effect, and B16's for the creation request: the offset is
-- unchanged and the request still waiting is told the store is unavailable.
{-@ predicate WriteFailedRow F O =
      (FileCreation F => (EndsAs F O (Failed Unavailable)
                          && SettledAs F O (Present (Refuse (StoreUnavailable Absent) (Present True)))))
      && (not (FileCreation F) => (goal (fileAsset (after O)) == goal (fileAsset F) && filePhase (after O) == 1
                                   && SettledAs F O (Present (Refuse (StoreUnavailable Absent) Absent)))) @-}

-- | A current report of a kind the running job can't send ('WrongKind' in
-- the contract) runs that job's failure row with ShellContract (CH42,
-- CLIENT.md round 2): B9 while Reading, B12 while Writing, B16 for the
-- creation request, and nothing else, so it never starts a job. It is
-- G2's, as CH42 is, so it runs past the deadline too; the next Tick
-- expires what is left.
{-@ predicate WrongKindAlerts V F E O =
      WrongKind F E
        => (alert O == Present ShellContract && not (isPresent (started O))
            && ((GoalTagIs F 2 && filePhase F == 2) => ReaderDiedRow F O)
            && ((GoalTagIs F 2 && filePhase F == 3) => WriteFailedRow F O)) @-}

-- | The offset a refusal tells its client, if there is one (A2's).
{-@ measure optRefusalOffset @-}
optRefusalOffset :: Opt Refusal -> Int
optRefusalOffset (Present x) = refusalOffset x
optRefusalOffset Absent      = -1

{-@ predicate UploadRequest E = 0 <= uploadEventKind E && uploadEventKind E <= 2 && isPresent (evReq E) @-}
{-@ predicate UploadReport E  = isMoverReport E && not (isPresent (evReq E)) @-}
-- | A report from the job the file is waiting for: the report is that job's
-- last word, so every row it reaches ends the job.
{-@ predicate RunningReport F E = UploadReport E && owedJob F == 1 && fileEpoch F == evEpoch E @-}
{-@ predicate GoalTagIs F T   = goalTag (goal (fileAsset F)) == T @-}

-- | The request an upload-resource request carries. The contract asks for
-- @isPresent (evReq ev)@, and z3 only learns 'isPresent' of a value built in
-- code, so the 'Present' is built here once for every request kind.
{-@ carriedReq :: ev:{Event | 0 <= uploadEventKind ev && uploadEventKind ev <= 2}
               -> {o:Opt ReqId | o == evReq ev && isPresent o} @-}
carriedReq :: Event -> Opt ReqId
carriedReq (Append p)       = Present (aReq p)
carriedReq (OffsetQuery r)  = Present r
carriedReq (CancelUpload r) = Present r
carriedReq _                = error "carriedReq: the precondition admits only upload-resource requests"

-- | The same for a mover's report, which carries no request.
{-@ reportReq :: ev:{Event | 3 <= uploadEventKind ev}
              -> {o:Opt ReqId | o == evReq ev && not (isPresent o) && isMoverReport ev && not (isTick ev)} @-}
reportReq :: Event -> Opt ReqId
reportReq (BodyReceived _ _)   = Absent
reportReq (BodyBroken _ _)     = Absent
reportReq (ChunkPersisted _ _) = Absent
reportReq (ChunkFailed _)      = Absent
reportReq (MoverDied _)        = Absent
reportReq _                    = error "reportReq: the precondition admits only mover reports"

-- Entry points -----------------------------------------------------------------

{-@ onAppend :: env:Env -> ev:{Event | uploadEventKind ev == 0} -> f:File -> ClientOut env f ev @-}
onAppend :: Env -> Event -> File -> Out
onAppend = uploadRequest

{-@ onOffsetQuery :: env:Env -> ev:{Event | uploadEventKind ev == 1} -> f:File -> ClientOut env f ev @-}
onOffsetQuery :: Env -> Event -> File -> Out
onOffsetQuery = uploadRequest

{-@ onCancelUpload :: env:Env -> ev:{Event | uploadEventKind ev == 2} -> f:File -> ClientOut env f ev @-}
onCancelUpload :: Env -> Event -> File -> Out
onCancelUpload = uploadRequest

{-@ onBodyReceived :: env:Env -> ev:{Event | uploadEventKind ev == 3} -> f:File -> {o:ClientOut env f ev | WrongKindAlerts env f ev o} @-}
onBodyReceived :: Env -> Event -> File -> Out
onBodyReceived = moverReport

{-@ onBodyBroken :: env:Env -> ev:{Event | uploadEventKind ev == 4} -> f:File -> {o:ClientOut env f ev | WrongKindAlerts env f ev o} @-}
onBodyBroken :: Env -> Event -> File -> Out
onBodyBroken = moverReport

{-@ onChunkPersisted :: env:Env -> ev:{Event | uploadEventKind ev == 5} -> f:File -> {o:ClientOut env f ev | WrongKindAlerts env f ev o} @-}
onChunkPersisted :: Env -> Event -> File -> Out
onChunkPersisted = moverReport

{-@ onChunkFailed :: env:Env -> ev:{Event | uploadEventKind ev == 6} -> f:File -> {o:ClientOut env f ev | WrongKindAlerts env f ev o} @-}
onChunkFailed :: Env -> Event -> File -> Out
onChunkFailed = moverReport

{-@ onMoverDied :: env:Env -> ev:{Event | uploadEventKind ev == 7} -> f:File -> ClientOut env f ev @-}
onMoverDied :: Env -> Event -> File -> Out
onMoverDied = moverReport

-- | A request to the upload resource, by phase. G3 comes before any cell
-- (CLIENT.md round 2: "a request after the deadline on a goal still
-- assembling runs X1 first"), Opening's included, and the request is then
-- answered as the END column answers it, 410. Opening comes next, because
-- the creation request's client hasn't been told the URI yet, so nobody
-- can be asking about this upload resource. A goal the kernel has cleared
-- is answered Gone, and the owed request and any job are left for
-- 'KernelMoved', whose ruling settles exactly that case.
{-@ uploadRequest :: env:Env -> ev:{Event | 0 <= uploadEventKind ev && uploadEventKind ev <= 2}
                  -> f:File -> ClientOut env f ev @-}
uploadRequest :: Env -> Event -> File -> Out
uploadRequest env ev f = case carriedReq ev of
  Absent    -> error "uploadRequest: carriedReq is always Present"
  Present _
    -- X1 (P UP:RESUMABLE-UPLOAD-13-4.1.4-7 (PM40), PM13; C CH6), then 410.
    | pastDeadline env f -> expireFile env ev f (Present (Refuse Gone Absent))
    | otherwise -> case f of
    File _ a c _ -> case a of
      Asset g _ _ _ _ _ _ -> case c of
        Client _ _ ph _ -> case (ph, g) of
          (Opening _, _)          -> answer env ev f (Refuse NotFound Absent)
          (_, Clear)              -> answer env ev f (Refuse Gone Absent)
          (Idle, Keep _)          -> idleRequest env ev f
          (Reading _ _, Keep _)   -> supersedeRead env ev f
          (Writing _ _ _, Keep _) -> writingRequest env ev f
          (Sealing _, Keep _)     -> completeRequest env ev f
          (Settled, Keep _)       -> completeRequest env ev f

-- | A mover's report, by phase. A job is named by the epoch it runs under,
-- so a report under the file's epoch while a job runs comes from that job
-- and is its last word: every such report ends the job, whatever its kind.
-- G2: any other report is stale, which also stops the mover that sent it.
-- A current report of the wrong kind is G2's too (CH42): it runs the job's
-- failure row. G3 comes next: core.md's guards still apply to the B rows,
-- and G3 runs X1 before any cell in Receiving, so the job's own report past
-- the deadline ends the file Expired instead of running its row. Without it, a
-- completing chunk reported after max-age would complete the upload, and
-- whether an expired upload ended ACTIVE or FAILED would depend on whether
-- the shell delivered the report or the deadline's Tick first.
{-@ moverReport :: env:Env -> ev:{Event | 3 <= uploadEventKind ev} -> f:File -> {o:ClientOut env f ev | WrongKindAlerts env f ev o} @-}
moverReport :: Env -> Event -> File -> Out
moverReport env ev f = case reportReq ev of
  Present _ -> error "moverReport: reportReq is never Present"
  Absent -> case f of
    File _ a c e -> case a of
      Asset g _ _ _ _ _ _ -> case c of
        Client _ _ ph _
          | evEpochOf ev /= e -> stale env ev f
          | otherwise -> case ph of
              Reading _ _ -> case g of
                Clear  -> wrongKind (not (readReport ev)) (endedUnder env ev f False)
                Keep _
                  | pastDeadline env f && readReport ev -> expireFile env ev f Absent
                  | otherwise -> readingReport env ev f
              Writing _ _ _ -> case g of
                Clear  -> wrongKind (not (writeReport ev)) (endedUnder env ev f True)
                Keep _
                  | pastDeadline env f && writeReport ev -> expireFile env ev f Absent
                  | otherwise -> writingReport env ev f
              -- No job runs, so the job under this epoch already ended:
              -- B5, B6, B8 and B9 stop the reader and stay under its epoch.
              Opening _ -> stale env ev f
              Idle      -> stale env ev f
              Sealing _ -> stale env ev f
              Settled   -> stale env ev f

-- | The epoch a report names, as a value the checker relates to 'evEpoch'.
{-@ evEpochOf :: ev:Event -> {e:Int | e == evEpoch ev} @-}
evEpochOf :: Event -> Int
evEpochOf ev = evEpoch ev

-- | A report under the running job's epoch that the job can't send, such
-- as a ChunkPersisted from a reader. Only a shell that broke its delivery
-- contract sends one. As CH42 does for a store report of the wrong command,
-- the running job is treated as failed and an alert raised, so the file
-- never waits for a report that won't come.
{-@ wrongKind :: b:Bool -> o:Out
              -> {p:Out | after p == after o && owedTo p == owedTo o && evTo p == evTo o
                          && stopped p == stopped o && started p == started o && timers p == timers o
                          && (b => alert p == Present ShellContract)} @-}
wrongKind :: Bool -> Out -> Out
wrongKind True  o = alerting ShellContract o
wrongKind False o = o

-- | The reports a body read sends. 'MoverDied' is either job's.
{-@ readReport :: ev:Event -> {b:Bool | isMoverReport ev => (b <=> not (writeOnlyReport ev))} @-}
readReport :: Event -> Bool
readReport (BodyReceived _ _) = True
readReport (BodyBroken _ _)   = True
readReport (MoverDied _)      = True
readReport _                  = False

-- | The reports a chunk write sends.
{-@ writeReport :: ev:Event -> {b:Bool | isMoverReport ev => (b <=> not (readOnlyReport ev))} @-}
writeReport :: Event -> Bool
writeReport (ChunkPersisted _ _) = True
writeReport (ChunkFailed _)      = True
writeReport (MoverDied _)        = True
writeReport _                    = False

-- The shared append check ----------------------------------------------------------

-- | Every phase that checks a PATCH checks it here, in the order CLIENT.md
-- fixes: the integrity field (A8), then A1 to A4, then the size rules
-- against the goal's 'Limits'. 'Absent' means the request passed; passing
-- means it names the current offset, sent no digest and has the right media
-- type, which is what the rows after the check rely on.
{-@ appendCheck :: ch:Chunks -> l:Len -> p:Patch
                -> {r:Opt Refusal | (not (isPresent r)
                                     => (aOffset p == Present (offsetOf ch) && not (aDigest p) && aMediaOk p))
                                    && (aDigest p => r == Present DigestUnsupported)
                                    && (optRefusalOffset r < 0 || optRefusalOffset r == offsetOf ch)} @-}
appendCheck :: Chunks -> Len -> Patch -> Opt Refusal
appendCheck ch l p
  -- A8: no integrity field can be forwarded to the store, so any is refused
  -- (P PD:DIGEST-PROBLEMS-3.1-1, PM24).
  | aDigest p = Present DigestUnsupported
  | otherwise = case aOffset p of
      -- A1 (R HS:RFC9110-15.5.1; C CH43)
      Absent -> Present MissingOffset
      Present o
        -- A2 (R UP:RESUMABLE-UPLOAD-13-4.4.2-3)
        | o /= offsetOf ch -> Present (OffsetMismatch (offsetOf ch))
        -- A3 (R UP:RESUMABLE-UPLOAD-13-4.4.1-1, HS:RFC5789-2-3; P HS:RFC5789-2.2-1, PM22)
        | not (aMediaOk p) -> Present WrongMediaType
        -- A4 (R UP:RESUMABLE-UPLOAD-13-4.1.3-3, UP:RESUMABLE-UPLOAD-13-4.1.3-6)
        | lengthsDisagree (offsetOf ch) l p -> Present InconsistentLength
        | otherwise -> sizeRefusal ch p

-- | A4: the request's length indicators disagree with each other, with the
-- length already recorded, or with the offset. The indicators are
-- Upload-Length, and the offset plus Content-Length under UC ?1. Content that
-- only runs past a recorded length is not a disagreement between
-- indicators: F8 and V2 answer it with OffsetPastLength, and B7 catches it
-- once the body is read.
{-@ lengthsDisagree :: Int -> Len -> Patch -> Bool @-}
lengthsDisagree :: Int -> Len -> Patch -> Bool
lengthsDisagree off l p = declaredDisagrees off l p || completingDisagrees off l p

-- | Upload-Length against the recorded length, the offset, and the end of
-- this request's content.
{-@ declaredDisagrees :: Int -> Len -> Patch -> Bool @-}
declaredDisagrees :: Int -> Len -> Patch -> Bool
declaredDisagrees off l p = case aLength p of
  Present n -> recordedDiffers l n || n < off || endsPast (contentEnd off p) n
  Absent    -> False

-- | Under UC ?1 the length is the offset plus Content-Length, and it has to
-- match both the recorded length and Upload-Length.
{-@ completingDisagrees :: Int -> Len -> Patch -> Bool @-}
completingDisagrees :: Int -> Len -> Patch -> Bool
completingDisagrees off l p = completes p && case contentEnd off p of
  Present x -> recordedDiffers l x || optDiffers (aLength p) x
  Absent    -> False

-- | Where this request's content ends, when Content-Length says.
{-@ contentEnd :: Int -> Patch -> Opt Int @-}
contentEnd :: Int -> Patch -> Opt Int
contentEnd off p = case aContent p of
  Present c -> Present (off + c)
  Absent    -> Absent

{-@ endsPast :: Opt Int -> Int -> Bool @-}
endsPast :: Opt Int -> Int -> Bool
endsPast (Present x) n = x > n
endsPast Absent      _ = False

{-@ optDiffers :: Opt Int -> Int -> Bool @-}
optDiffers :: Opt Int -> Int -> Bool
optDiffers (Present n) x = x /= n
optDiffers Absent      _ = False

-- | Whether a length differs from the one recorded, if one is.
{-@ recordedDiffers :: Len -> Int -> Bool @-}
recordedDiffers :: Len -> Int -> Bool
recordedDiffers (Known k) x = x /= k
recordedDiffers Unknown   _ = False

-- | Whether a length runs past the one recorded, if one is.
{-@ recordedBelow :: Len -> Int -> Bool @-}
recordedBelow :: Len -> Int -> Bool
recordedBelow (Known k) x = x > k
recordedBelow Unknown   _ = False

-- | The size rules, against the plan's limits (P UP:RESUMABLE-UPLOAD-13-4.1.4-3,
-- -4.1.4-5, -4.1.4-6, PM16; C CH28), in CLIENT.md's order.
{-@ sizeRefusal :: Chunks -> Patch -> {r:Opt Refusal | optRefusalOffset r < 0} @-}
sizeRefusal :: Chunks -> Patch -> Opt Refusal
sizeRefusal ch p
  | contentAbove (maxChunk lim) p                       = Present (AppendTooLarge lim)
  | not (completes p) && contentBelow (minChunk lim) p  = Present (AppendTooSmall lim)
  | pastMaxSize ch p || capFull ch p                    = Present (ExceedsMaxSize lim)
  | otherwise                                           = Absent
  where
    lim = limitsOf ch

{-@ contentAbove :: Int -> Patch -> Bool @-}
contentAbove :: Int -> Patch -> Bool
contentAbove m p = case aContent p of
  Present n -> n > m
  Absent    -> False

{-@ contentBelow :: Int -> Patch -> Bool @-}
contentBelow :: Int -> Patch -> Bool
contentBelow m p = case aContent p of
  Present n -> n < m
  Absent    -> False

-- | The request goes past max-size: a declared length past it, content
-- that ends past it, or, for a request that doesn't complete and doesn't
-- say how much it carries, an offset already at it (A5).
{-@ pastMaxSize :: Chunks -> Patch -> Bool @-}
pastMaxSize :: Chunks -> Patch -> Bool
pastMaxSize ch p =
  endsPast (aLength p) (maxSize (limitsOf ch))
    || endsPast (contentEnd (offsetOf ch) p) (maxSize (limitsOf ch))
    || (not (completes p) && aContent p == Absent && offsetOf ch >= maxSize (limitsOf ch))

-- | The chunk cap is reached and the request may carry content. An empty
-- body adds no chunk, so it still completes a full assembly.
{-@ capFull :: Chunks -> Patch -> Bool @-}
capFull :: Chunks -> Patch -> Bool
capFull ch p = nChunks ch >= maxChunks (limitsOf ch) && aContent p /= Present 0

-- | Upload-Complete: ?1.
{-@ completes :: Patch -> Bool @-}
completes :: Patch -> Bool
completes p = aComplete p == Present True

-- | The length a request makes known: Upload-Length, or under UC ?1 the
-- offset plus Content-Length (R UP:RESUMABLE-UPLOAD-13-4.1.3-3).
{-@ declaredLength :: Nat -> Patch -> Opt Nat @-}
declaredLength :: Int -> Patch -> Opt Int
declaredLength off p = case aLength p of
  Present n -> Present n
  Absent | completes p -> case aContent p of
             Present c -> Present (off + c)
             Absent    -> Absent
         | otherwise -> Absent

-- Idle -------------------------------------------------------------------------------

-- | A1 to A11: the upload is assembling and nothing is in flight.
{-@ idleRequest :: env:Env -> ev:{Event | UploadRequest ev}
                -> f:{File | filePhase f == 1 && GoalTagIs f 2 && not (PastDeadline env f)}
                -> {o:ClientOut env f ev | (uploadEventKind ev == 2 => EndsAs f o Cancelled)
                                          && (uploadEventKind ev == 1 => after o == f)
                                          && (owedJob (after o) == 1 => isPresent (started o))} @-}
idleRequest :: Env -> Event -> File -> Out
idleRequest env ev f = case f of
  File m a c e -> case a of
    Asset (Keep (Assembling _ ch)) _ _ _ _ _ _ -> case c of
      Client l open Idle d -> case ev of
        -- A10 (R UP:RESUMABLE-UPLOAD-13-4.3.2-1; P PM19)
        OffsetQuery _ -> answer env ev f (OffsetIs False (offsetOf ch) l (limitsOf ch))
        -- A11 (P UP:RESUMABLE-UPLOAD-13-4.5.2-1, PM15, HS:RFC9110-9.3.5-3, PM29)
        CancelUpload _ -> abandonFile env ev f Cancelled Absent (Present NoContent)
        Append p -> case idleRefusal env ch l p of
          Present x -> answer env ev f (Refuse x Absent)
          -- A9 (R UP:RESUMABLE-UPLOAD-13-4.4.2-1, -4.4.2-7; P -4.1.4-3, PM16):
          -- read at most what one chunk and max-size allow, under a new epoch.
          Absent ->
            let off = offsetOf ch
                l'  = case l of
                  Known _ -> l
                  Unknown -> case declaredLength off p of
                    Present n -> Known n
                    Absent    -> Unknown
            in Out (File m a (Client l' open (Reading (AppendReq (aReq p)) (completes p)) d) (e + 1))
                   Absent Absent Absent
                   (Present (StartRead (e + 1) (readCapOf ch)))
                   [] Absent
        _ -> error "idleRequest: the precondition admits only upload-resource requests"
      _ -> error "idleRequest: the precondition says the phase is Idle"
    _ -> error "idleRequest: the precondition says the goal is assembling"

-- | The shared append check, then the two Idle rows it doesn't cover: A5's
-- quota (R HS:RFC4918-11.5-1; C CH14), for a length this request makes known,
-- and A7, an empty completing upload the store can't seal (R HS:RFC9110-15.6.2;
-- C CH15).
{-@ idleRefusal :: Env -> ch:Chunks -> Len -> Patch
                -> {r:Opt Refusal | optRefusalOffset r < 0 || optRefusalOffset r == offsetOf ch} @-}
idleRefusal :: Env -> Chunks -> Len -> Patch -> Opt Refusal
idleRefusal env ch l p = case appendCheck ch l p of
  Present x -> Present x
  Absent
    | overQuota env ch l p -> Present InsufficientStorage
    | completes p && aContent p == Present 0 && offsetOf ch == 0 && not (sealsEmpty (limitsOf ch))
        -> Present NotImplemented
    | otherwise -> Absent

-- | A5's quota: only a length this request makes known is checked, so an
-- upload already under way isn't refused because the quota shrank since.
{-@ overQuota :: Env -> Chunks -> Len -> Patch -> Bool @-}
overQuota :: Env -> Chunks -> Len -> Patch -> Bool
overQuota _ _ (Known _) _ = False
overQuota env ch Unknown p = case declaredLength (offsetOf ch) p of
  Present n -> n > quotaRemaining env
  Absent    -> False

-- Reading ------------------------------------------------------------------------------

-- | B1 (P UP:RESUMABLE-UPLOAD-13-4.6-4, -4.6-5, PM8): a new request to the
-- upload resource ends the append whose body is being read. The reader is
-- stopped, its request abandoned, and the Idle rows answer the new request
-- under the next epoch, so a late report from the stopped reader is stale.
{-@ supersedeRead :: env:Env -> ev:{Event | UploadRequest ev}
                  -> f:{File | filePhase f == 2 && GoalTagIs f 2 && not (PastDeadline env f)} -> ClientOut env f ev @-}
supersedeRead :: Env -> Event -> File -> Out
supersedeRead env ev f = case f of
  File m a c e -> case c of
    Client l open ph@(Reading _ _) d -> case idleRequest env ev (File m a (Client l open Idle d) (e + 1)) of
      Out f' _ evAns _ start ts al -> Out f' (settle (phaseReq ph) Absent) evAns (Present e) start ts al
    _ -> error "supersedeRead: the precondition says the phase is Reading"

-- | A report from the reader the file is waiting for.
{-@ readingReport :: env:Env -> ev:Event
                  -> f:{File | filePhase f == 2 && GoalTagIs f 2 && RunningReport f ev && not (G3Applies env f ev)}
                  -> {o:ClientOut env f ev | WrongKindAlerts env f ev o} @-}
readingReport :: Env -> Event -> File -> Out
readingReport env ev f = case ev of
  BodyReceived _ n -> bodyReceived env ev f n
  -- B7 (R UP:RESUMABLE-UPLOAD-13-4.4.2-7): the body ran past the length.
  BodyBroken _ ExceededLength -> pastLength env ev f
  -- B8 (P UP:RESUMABLE-UPLOAD-13-4.1.4-5, -4.1.4-3, PM16): the body ran past
  -- the read limit, which was one chunk or what max-size still allowed.
  BodyBroken _ ExceededLimit -> refuseBody env ev f (readLimitRefusal f)
  -- B9 (R UP:RESUMABLE-UPLOAD-13-4.4.2-2; P PM9)
  BodyBroken _ Interrupted -> readerDied env ev f
  MoverDied _ -> readerDied env ev f
  -- A write's report under the reader's epoch: the read failed (B9).
  ChunkPersisted _ _ -> wrongKind True (readerDied env ev f)
  ChunkFailed _      -> wrongKind True (readerDied env ev f)
  _ -> error "readingReport: the precondition admits only mover reports"

-- | B3 to B6 and B16: the body was read in full, n bytes of it.
{-@ bodyReceived :: env:Env -> ev:{Event | UploadReport ev}
                 -> f:{File | filePhase f == 2 && GoalTagIs f 2 && RunningReport f ev && not (G3Applies env f ev)}
                 -> Int -> ClientOut env f ev @-}
bodyReceived :: Env -> Event -> File -> Int -> Out
bodyReceived env ev f n = case f of
  File m a c e -> case a of
    Asset (Keep (Assembling r ch)) _ _ _ _ _ _ -> case c of
      Client l open ph d -> case ph of
        Reading q uc -> let off = offsetOf ch in case limitsOf ch of
          lim@(Limits minC maxC maxN maxS seals)
            -- A body can't have a negative length: the mover broke its
            -- contract, and the read is treated as broken off (B9).
            | n < 0 -> alerting ShellContract (readerDied env ev f)
            | n == 0 && not uc -> refuseBody env ev f (AppendTooSmall lim)          -- B5
            | n == 0 && recordedDiffers l off -> refuseBody env ev f InconsistentLength  -- B6
            -- B4 (R UP:RESUMABLE-UPLOAD-13-4.4.1-3, HS:RFC9110-15.6.2; C CH15): an
            -- empty completing body completes with the chunks already there.
            | n == 0 && (off > 0 || seals) -> case r of
                Present _ -> finalize env ev f a False
                Absent    -> unadopted env ev f False
            | n == 0 -> refuseBody env ev f NotImplemented
            | not uc && n < minC -> refuseBody env ev f (AppendTooSmall lim)        -- B5
            | uc && recordedDiffers l (off + n) -> refuseBody env ev f InconsistentLength  -- B6
            | not uc && recordedBelow l (off + n) -> pastLength env ev f            -- B7
            -- A9 never asks for more than this, so a longer body means the
            -- mover read past its limit; it is refused as B8 would refuse it.
            | n > maxC || off + n > maxS || nChunks ch >= maxN ->
                alerting ShellContract (refuseBody env ev f (if n > maxC then AppendTooLarge lim else ExceedsMaxSize lim))
            -- B3 (R UP:RESUMABLE-UPLOAD-13-4.4.1-3; P -4.1.4-3, PM16; C CH6
            -- clause 7, CH28, CH29): the buffer read under e becomes the
            -- write job e + 1, into the adopted staging area, as the next
            -- chunk. The write is authorised under e + 1, the job that will
            -- report it, with the deadline A3 aborts it by. 'env' is matched
            -- so the checker sees the same clock the contract names.
            | otherwise -> case (r, env) of
                (Present ref, Env clock _ _ _ cfg) ->
                  Out (File m (startWrite a (e + 1) (clock + writeDeadline cfg))
                              (Client l open (Writing (Present q) n uc) d) (e + 1))
                      Absent Absent Absent
                      (Present (StartPersist e (e + 1) ref (nChunks ch + 1)))
                      [] Absent
                (Absent, _) -> unadopted env ev f False
        _ -> error "bodyReceived: the precondition says the phase is Reading"
    _ -> error "bodyReceived: the precondition says the goal is assembling"

-- | B8's reply: AppendTooLarge when the read limit A9 set was one chunk,
-- ExceedsMaxSize when it was what max-size still allowed.
{-@ readLimitRefusal :: f:{File | GoalTagIs f 2} -> {r:Refusal | refusalOffset r < 0} @-}
readLimitRefusal :: File -> Refusal
readLimitRefusal (File _ (Asset (Keep (Assembling _ ch)) _ _ _ _ _ _) _ _) =
  let lim = limitsOf ch
  in if maxChunk lim <= maxSize lim - offsetOf ch then AppendTooLarge lim else ExceedsMaxSize lim
readLimitRefusal _ = error "readLimitRefusal: the precondition says the goal is assembling"

-- | B5, B6 and B8 refuse an append's body: its request gets the refusal, the
-- buffer is released, and the upload is Idle at the offset it had. For the
-- creation request it's B16 (P UP:RESUMABLE-UPLOAD-13-4.2.3-2, PM44; C CH45):
-- its client never learned the upload resource, so the file ends, and the
-- refusal carries UC ?1.
{-@ refuseBody :: env:Env -> ev:{Event | UploadReport ev}
               -> f:{File | filePhase f == 2 && GoalTagIs f 2 && RunningReport f ev && not (G3Applies env f ev)}
               -> {x:Refusal | refusalOffset x < 0}
               -> {o:ClientOut env f ev | (FileCreation f => EndsAs f o (Failed CreationRefused))
                                         && (not (FileCreation f) => (fileAsset (after o) == fileAsset f && filePhase (after o) == 1))} @-}
refuseBody :: Env -> Event -> File -> Refusal -> Out
refuseBody env ev f x = case f of
  File m a c e -> case c of
    Client l open ph d -> case ph of
      Reading (AppendReq _) _ ->
        Out (File m a (Client l open Idle d) e)
            (settle (phaseReq ph) (Present (Refuse x Absent))) Absent (Present e) Absent [] Absent
      Reading (CreationReq _) _ ->
        abandonFile env ev f (Failed CreationRefused) (Present (Refuse x (Present True))) Absent
      _ -> error "refuseBody: the precondition says the phase is Reading"

-- | B9: the body broke off or the reader died. Nothing of it is kept and the
-- request is abandoned, never answered complete. For the creation request
-- it's B16 with CreationInterrupted.
{-@ readerDied :: env:Env -> ev:{Event | UploadReport ev}
               -> f:{File | filePhase f == 2 && GoalTagIs f 2 && RunningReport f ev && not (G3Applies env f ev)}
               -> {o:ClientOut env f ev | ReaderDiedRow f o && not (isPresent (started o))} @-}
readerDied :: Env -> Event -> File -> Out
readerDied env ev f = case f of
  File m a c e -> case c of
    Client l open ph d -> case ph of
      Reading (AppendReq _) _ ->
        Out (File m a (Client l open Idle d) e) (settle (phaseReq ph) Absent) Absent (Present e) Absent [] Absent
      Reading (CreationReq _) _ -> abandonFile env ev f (Failed CreationInterrupted) Absent Absent
      _ -> error "readerDied: the precondition says the phase is Reading"

-- | B7: the body runs past the upload's length, so the upload resource is
-- invalid and the file fails (R UP:RESUMABLE-UPLOAD-13-4.4.2-7). The
-- creation request's refusal carries UC ?1.
{-@ pastLength :: env:Env -> ev:Event
               -> f:{File | filePhase f == 2 && GoalTagIs f 2 && RunningReport f ev && not (G3Applies env f ev)}
               -> {o:ClientOut env f ev | EndsAs f o (Failed OutOfRange)} @-}
pastLength :: Env -> Event -> File -> Out
pastLength env ev f = case f of
  File _ _ c _ -> case c of
    Client _ _ (Reading q _) _ ->
      abandonFile env ev f (Failed OutOfRange) (Present (Refuse OffsetPastLength (creationUc q))) Absent
    _ -> error "pastLength: the precondition says the phase is Reading"

-- | Upload-Complete on a refusal that ends the file: ?1 for the creation
-- request, whose client must not resume, and nothing for an append.
{-@ creationUc :: Req -> Opt Bool @-}
creationUc :: Req -> Opt Bool
creationUc (CreationReq _) = Present True
creationUc (AppendReq _)   = Absent

-- Writing --------------------------------------------------------------------------------

-- | A request to the upload resource while a chunk is being written.
{-@ writingRequest :: env:Env -> ev:{Event | UploadRequest ev}
                   -> f:{File | filePhase f == 3 && GoalTagIs f 2 && not (PastDeadline env f)}
                   -> {o:ClientOut env f ev | (uploadEventKind ev == 2 => EndsAs f o Cancelled)
                                             && (uploadEventKind ev /= 2 => (fileAsset (after o) == fileAsset f && filePhase (after o) == 3))} @-}
writingRequest :: Env -> Event -> File -> Out
writingRequest env ev f = case f of
  File m a c e -> case c of
    Client l open ph d -> case ph of
      Writing _ n uc -> case ev of
        -- B15 (P UP:RESUMABLE-UPLOAD-13-4.5.2-1, PM15, HS:RFC9110-9.3.5-3,
        -- PM29; C CH6 clause 5, CH30): the write is stopped and its request
        -- abandoned. Its entry stays in 'authorised' until the late report
        -- or the deadline (A3), since nothing here knows whether it landed.
        CancelUpload _ -> abandonFile env ev f Cancelled Absent (Present NoContent)
        -- B2 (P UP:RESUMABLE-UPLOAD-13-4.6-4, PM8; C CH30): the write goes
        -- on without a request to answer, and the new one is re-delivered
        -- after the write's report.
        _ -> Out (File m a (Client l open (Writing Absent n uc) d) e)
                 (settle (phaseReq ph) Absent) (Present Deferred) Absent Absent [] Absent
      _ -> error "writingRequest: the precondition says the phase is Writing"

-- | A report from the write the file is waiting for.
{-@ writingReport :: env:Env -> ev:Event
                  -> f:{File | filePhase f == 3 && GoalTagIs f 2 && RunningReport f ev && not (G3Applies env f ev)}
                  -> {o:ClientOut env f ev | WrongKindAlerts env f ev o} @-}
writingReport :: Env -> Event -> File -> Out
writingReport env ev f = case ev of
  ChunkPersisted _ k -> chunkPersisted env ev f k
  ChunkFailed _ -> writeFailed env ev f
  MoverDied _   -> writeFailed env ev f
  -- A read's report under the write's epoch: the write failed (B12).
  BodyReceived _ _ -> wrongKind True (writeFailed env ev f)
  BodyBroken _ _   -> wrongKind True (writeFailed env ev f)
  _ -> error "writingReport: the precondition admits only mover reports"

-- | B10 and B11. The report is checked before anything is believed: the
-- chunk must be the n bytes that were read, and the assembly must accept
-- it. Either way the write is reported, since the mover is done with it.
{-@ chunkPersisted :: env:Env -> ev:{Event | UploadReport ev}
                   -> f:{File | filePhase f == 3 && GoalTagIs f 2 && RunningReport f ev && not (G3Applies env f ev)}
                   -> k:Chunk
                   -> {o:ClientOut env f ev | (cbytes k /= phaseBytes (phase (client f)) => EndsAs f o (Failed Contradiction))
                                             && (settleOffset (owedTo o) >= 0
                                                   => settleOffset (owedTo o) == goalOffset (goal (fileAsset (after o))))} @-}
chunkPersisted :: Env -> Event -> File -> Chunk -> Out
chunkPersisted env ev f k = case f of
  File m a c e -> let a1 = reportWrite a e in case c of
    Client l open ph d -> case ph of
      Writing q n uc
        -- The store acknowledged a different chunk than the one read: the
        -- shell broke its contract (C CH6, CH42).
        | cbytes k /= n -> alerting ShellContract (contradiction env ev f True)
        | otherwise -> case a1 of
            Asset (Keep (Assembling (Present _) _)) _ _ _ _ _ _ -> case appendTo a1 k of
              Present a2
                -- B11 (R UP:RESUMABLE-UPLOAD-13-4.1.2-3; P -13-7, PM12; C CH5, CH14, CH22)
                | uc -> finalize env ev f a2 True
                -- B10 (R UP:RESUMABLE-UPLOAD-13-4.1.1-6, -4.4.2-5, -4.2.2-5; C CH1):
                -- the offset a client is told is the one the store acknowledged.
                | otherwise ->
                    Out (File m a2 (Client l open Idle d) e)
                        (settle (phaseReq ph) (accepted m q a2)) Absent Absent Absent [] Absent
              -- B3's checks should have kept this from happening; the
              -- assembly refusing the chunk is our own contradiction.
              Absent -> alerting InternalAlarm (contradiction env ev f True)
            _ -> unadopted env ev f True
      _ -> error "chunkPersisted: the precondition says the phase is Writing"

-- | B10's reply to the request still waiting on the chunk, if one is: 204
-- with the new offset, or 201 with Location for the creation request.
{-@ accepted :: Meta -> Opt Req -> a2:{Asset | goalTag (goal a2) == 2}
             -> {r:Opt Reply | optReplyOffset r == -1 || optReplyOffset r == goalOffset (goal a2)} @-}
accepted :: Meta -> Opt Req -> Asset -> Opt Reply
accepted _ Absent _ = Absent
accepted _ (Present (AppendReq _)) a2 = Present (AppendAccepted (assetOffset a2))
accepted m (Present (CreationReq _)) a2 = case a2 of
  Asset (Keep (Assembling _ ch)) _ _ _ _ _ _ -> Present (CreatedUpload (uploadId m) (limitsOf ch) (offsetOf ch))
  _ -> error "accepted: the precondition says the goal is assembling"

-- | B12 (R UP:RESUMABLE-UPLOAD-13-4.1.1-7; C CH1): the write failed or its
-- mover died. The offset is unchanged, so the client resends the same chunk
-- at the same offset. For the creation request it's B16 with Unavailable.
{-@ writeFailed :: env:Env -> ev:{Event | UploadReport ev}
                -> f:{File | filePhase f == 3 && GoalTagIs f 2 && RunningReport f ev && not (G3Applies env f ev)}
                -> {o:ClientOut env f ev | WriteFailedRow f o && not (isPresent (started o))} @-}
writeFailed :: Env -> Event -> File -> Out
writeFailed env ev f = case f of
  File m a c e -> case c of
    Client l open ph d -> case ph of
      Writing (Present (CreationReq _)) _ _ ->
        abandonReported env ev f (Failed Unavailable)
          (Present (Refuse (StoreUnavailable Absent) (Present True))) Absent
      Writing _ _ _ ->
        Out (File m (reportWrite a e) (Client l open Idle d) e)
            (settle (phaseReq ph) (Present (Refuse (StoreUnavailable Absent) Absent))) Absent Absent Absent [] Absent
      _ -> error "writeFailed: the precondition says the phase is Writing"

-- Completing --------------------------------------------------------------------------------

-- | B11, and B4 with no new chunk: the assembly is complete. Past the quota,
-- the file fails in QuotaAtFinalize (507, UC ?1); otherwise the request
-- waits for the receipt until @now + replyWait@, and that instant gets its
-- timer. The length is recorded as the offset.
--
-- @a2@ is the assembly with B11's chunk already appended, and @wrote@ says
-- whether this step reports a write (B11) or releases an empty body's
-- buffer (B4). The quota is checked before the assembly is marked complete,
-- and its failure clears the file's own asset: clearing discards the goal,
-- so the asset that results is the one completing first would leave.
{-@ finalize :: env:Env -> ev:{Event | UploadReport ev}
             -> f:{File | (filePhase f == 2 || filePhase f == 3) && GoalTagIs f 2
                          && RunningReport f ev && not (G3Applies env f ev)}
             -> a2:{Asset | KMove (fileAsset f) a2 && goalTag (goal a2) == 2 && goalAdopted (goal a2)
                           && len (authorised a2) <= len (authorised (fileAsset f))
                           && Set_sub (Set_dif (writeEpochs (authorised (fileAsset f))) (Set_sng (fileEpoch f)))
                                      (writeEpochs (authorised a2))
                           && (filePhase f == 3 => not (Set_mem (fileEpoch f) (writeEpochs (authorised a2))))
                           && (goalOffset (goal a2) == goalOffset (goal (fileAsset f))
                               || goalCount (goal a2) == goalCount (goal (fileAsset f)) + 1)}
             -> {wrote:Bool | wrote <=> filePhase f == 3}
             -> {o:ClientOut env f ev | (goalOffset (goal a2) > quotaRemaining env => EndsAs f o (Failed QuotaAtFinalize))
                                       && (goalOffset (goal a2) <= quotaRemaining env
                                             => (goalTag (goal (fileAsset (after o))) == 1
                                                 && goalOffset (goal (fileAsset (after o))) == goalOffset (goal a2)))} @-}
finalize :: Env -> Event -> File -> Asset -> Bool -> Out
finalize env ev f a2 wrote = case f of
  File m _ c e -> case c of
    Client _ open ph d
      | off > quotaRemaining env ->
          if wrote then abandonReported env ev f (Failed QuotaAtFinalize) (Present (endedReply (Failed QuotaAtFinalize))) Absent
                   else abandonFile env ev f (Failed QuotaAtFinalize) (Present (endedReply (Failed QuotaAtFinalize))) Absent
      | otherwise ->
          let a3   = completeGoal a2
              stop = if wrote then Absent else Present e
          in case phaseReq ph of
               Present r ->
                 let t = envNow env + replyWait env
                 in Out (File m a3 (Client (Known off) open (Sealing (Present (Waiter r t))) d) e)
                        Absent Absent stop Absent [t] Absent
               Absent ->
                 Out (File m a3 (Client (Known off) open (Sealing Absent) d) e)
                     Absent Absent stop Absent [] Absent
  where
    off = assetOffset a2

-- Sealing and Settled ------------------------------------------------------------------------

-- | F6 to F10 while the upload is complete and waiting for its receipt, and
-- V1 to V5 once it is ACTIVE ('uploadOpen' is "upload retained"). ACTIVE is
-- a goal that keeps the asset with a receipt (CLIENT.md slices 1 and 2), so
-- the receipt picks the rows, not the phase: a Sealing file whose receipt
-- already came is treated as ACTIVE (CLIENT.md slice 1, Sealing), and its
-- held completing request, which the watch owes F1's 201, is left for the
-- watch rather than abandoned. The upload is complete, so its offset is its
-- length. A Settled file with an assembled goal but no receipt isn't named
-- by the rulings; it is still waiting for its receipt, so the F rows
-- answer it.
{-@ completeRequest :: env:Env -> ev:{Event | UploadRequest ev}
                    -> f:{File | (filePhase f == 4 || filePhase f == 5) && GoalTagIs f 1}
                    -> {o:ClientOut env f ev |
                         (not (uploadOpen (client f)) => after o == f)
                         && ((uploadEventKind ev == 2 && uploadOpen (client f) && hasReceipt (vouch (fileAsset f)))
                               => fileAsset (after o) == fileAsset f)
                         && ((uploadEventKind ev == 2 && uploadOpen (client f) && not (hasReceipt (vouch (fileAsset f))))
                               => EndsAs f o Cancelled)
                         && ((uploadEventKind ev == 1 && uploadOpen (client f) && not (hasReceipt (vouch (fileAsset f))))
                               => owedReq (after o) == Absent)
                         && (hasReceipt (vouch (fileAsset f))
                               => (not (isPresent (owedTo o)) && owedReq (after o) == owedReq f
                                   && fileWait (after o) == fileWait f && fileAsset (after o) == fileAsset f))
                         && ((uploadEventKind ev == 1 && hasReceipt (vouch (fileAsset f))) => after o == f)} @-}
completeRequest :: Env -> Event -> File -> Out
completeRequest env ev f = case f of
  File m a c e -> case a of
    Asset (Keep (Assembled _ ch)) _ _ v _ _ _ -> case c of
      Client l open ph d
        | not (sealedNoJob ph) -> error "completeRequest: sealedNoJob is always True"
        -- F10, V5 (R UP:RESUMABLE-UPLOAD-13-4.4.2-7, -4.1.1-9, HS:RFC9110-15.5.11-1; P PM15, PM41)
        | not open -> answer env ev f (Refuse Gone Absent)
        | otherwise -> case ev of
            OffsetQuery _ -> case v of
              -- V3 (R UP:RESUMABLE-UPLOAD-13-4.3.2-1; P -4-3, PM14, PM19):
              -- ACTIVE, so nothing changes.
              HasReceipt _ -> answer env ev f (OffsetIs True (offsetOf ch) l (limitsOf ch))
              -- F6 (R UP:RESUMABLE-UPLOAD-13-4.3.2-1; P -4.6-4, PM8, PM19):
              -- a held completing request is abandoned for the new one.
              NoReceipt ->
                Out (File m a (Client l open (unheld ph) d) e)
                    (settle (phaseReq ph) Absent)
                    (Present (Answer (OffsetIs True (offsetOf ch) l (limitsOf ch)))) Absent Absent [] Absent
            CancelUpload _ -> case v of
              -- V4 (P UP:RESUMABLE-UPLOAD-13-4.5.2-1, PM15): a receipt is
              -- held, so the file is ACTIVE and stays so; only the upload
              -- resource closes.
              HasReceipt _ -> Out (File m a (Client l False ph d) e)
                                  Absent (Present (Answer NoContent)) Absent Absent [] Absent
              -- F9 (P HS:RFC9110-9.3.5-3, PM29; R SS:LRO-CancelOperation-1, -2):
              -- no receipt yet, so the cancel wins. Whatever the seal left,
              -- the reconciler removes, because Clear always removes the object.
              NoReceipt -> abandonFile env ev f Cancelled Absent (Present NoContent)
            Append p -> case appendCheck ch l p of
              Present x -> answer env ev f (Refuse x Absent)
              Absent
                | completes p && aContent p == Present 0 -> case v of
                    -- V1 (P UP:RESUMABLE-UPLOAD-13-4.4.2-6, PM14): replay F1's 201.
                    HasReceipt _ -> answer env ev f (CreatedFile (fileId m) (fileEtag f))
                    -- F7 (P UP:RESUMABLE-UPLOAD-13-4.4.2-6, PM14; C CH22): the new
                    -- completing request replaces the one held, with its own deadline.
                    NoReceipt -> let t = envNow env + replyWait env
                         in Out (File m a (Client l open (Sealing (Present (Waiter (aReq p) t))) d) e)
                                (settle (phaseReq ph) Absent) Absent Absent Absent [t] Absent
                -- F8, V2 (R UP:RESUMABLE-UPLOAD-13-4.4.2-7; P -4.1.2-6, PM21): content
                -- past the length invalidates the upload resource.
                | carriesContent p ->
                    Out (File m a (Client l False ph d) e)
                        Absent (Present (Answer (Refuse OffsetPastLength Absent))) Absent Absent [] Absent
                | otherwise -> answer env ev f (Refuse AlreadyComplete Absent)
            _ -> error "completeRequest: the precondition admits only upload-resource requests"
    _ -> error "completeRequest: the precondition says the goal is assembled"

-- | Sealing and Settled run no job.
{-@ sealedNoJob :: p:{Phase | phaseTag p == 4 || phaseTag p == 5} -> {v:Bool | v && phaseJob p == 0} @-}
sealedNoJob :: Phase -> Bool
sealedNoJob (Sealing _) = True
sealedNoJob Settled     = True
sealedNoJob _           = error "sealedNoJob: the precondition admits only Sealing and Settled"

-- | The phase once a held completing request is dropped.
{-@ unheld :: p:{Phase | phaseTag p == 4 || phaseTag p == 5}
           -> {q:Phase | phaseTag q == phaseTag p && phaseWait q == -1 && phaseReq q == Absent && phaseJob q == 0} @-}
unheld :: Phase -> Phase
unheld (Sealing _) = Sealing Absent
unheld Settled     = Settled
unheld _           = error "unheld: the precondition admits only Sealing and Settled"

-- | Content-Length announces at least one byte.
{-@ carriesContent :: Patch -> Bool @-}
carriesContent :: Patch -> Bool
carriesContent p = case aContent p of
  Present n -> n > 0
  Absent    -> False

-- Shared moves ----------------------------------------------------------------------------

-- | The goal's chunk total, as a value.
{-@ assetOffset :: a:Asset -> {v:Int | v == goalOffset (goal a) && (goalTag (goal a) /= 0 => v >= 0)} @-}
assetOffset :: Asset -> Int
assetOffset (Asset (Keep (Assembling _ ch)) _ _ _ _ _ _) = offsetOf ch
assetOffset (Asset (Keep (Assembled _ ch)) _ _ _ _ _ _)  = offsetOf ch
assetOffset (Asset Clear _ _ _ _ _ _)                    = -1

-- | 'abandonFile', for a step that ends the file on its write's own report.
-- The write is reported first and the goal cleared after: reporting keeps
-- the goal and the client side, so the file 'abandonFile' sees owes, waits
-- and runs exactly what @f@ does, and clearing keeps 'authorised'.
{-@ abandonReported :: env:Env -> ev:Event -> f:{File | GoalTagIs f 2 && RunningReport f ev && not (G3Applies env f ev)}
                    -> ending:Ending -> owed:{Opt Reply | optReplyOffset owed < 0}
                    -> r:{Opt Reply | (isPresent r <=> isPresent (evReq ev)) && optReplyOffset r < 0}
                    -> {o:ClientOut env f ev | EndsAs f o ending && SettledAs f o owed && not (isPresent (started o))} @-}
abandonReported :: Env -> Event -> File -> Ending -> Opt Reply -> Opt Reply -> Out
abandonReported env ev f ending owed evAns = case f of
  File m a c e -> abandonFile env ev (File m (reportWrite a e) c e) ending owed evAns

-- | A report that contradicts what the core knows: the file fails in
-- Contradiction, and its request gets that ending's refusal with UC ?1. A
-- write report also reports the write.
{-@ contradiction :: env:Env -> ev:Event -> f:{File | GoalTagIs f 2 && RunningReport f ev && (filePhase f == 2 || filePhase f == 3)
                                                     && not (G3Applies env f ev)}
                  -> {wrote:Bool | wrote <=> filePhase f == 3}
                  -> {o:ClientOut env f ev | EndsAs f o (Failed Contradiction)} @-}
contradiction :: Env -> Event -> File -> Bool -> Out
contradiction env ev f wrote
  | wrote     = abandonReported env ev f ending owed Absent
  | otherwise = abandonFile env ev f ending owed Absent
  where
    ending = Failed Contradiction
    owed   = Present (endedReply ending)

-- | An append in flight on an assembly with no staging area adopted. The
-- types admit it, but Opening only leaves for Idle once one is adopted, so a
-- chunk with nowhere to go is our own contradiction.
{-@ unadopted :: env:Env -> ev:Event -> f:{File | GoalTagIs f 2 && RunningReport f ev && (filePhase f == 2 || filePhase f == 3)
                                                 && not (G3Applies env f ev)}
              -> {wrote:Bool | wrote <=> filePhase f == 3}
              -> {o:ClientOut env f ev | EndsAs f o (Failed Contradiction)} @-}
unadopted :: Env -> Event -> File -> Bool -> Out
unadopted env ev f wrote = alerting InternalAlarm (contradiction env ev f wrote)

-- | A current report on a goal the kernel has already cleared: the file
-- settles as 'KernelMoved' would settle it (the owed request gets the
-- ending's refusal with UC ?1, the job is stopped), and a report under a
-- write's epoch, being that write's last word, also releases its entry in
-- 'authorised', which nothing else could do before the write's deadline.
{-@ endedUnder :: env:Env -> ev:Event -> f:{File | GoalTagIs f 0 && RunningReport f ev && (filePhase f == 2 || filePhase f == 3)}
               -> {wrote:Bool | wrote <=> filePhase f == 3} -> {o:ClientOut env f ev | not (isPresent (started o))} @-}
endedUnder :: Env -> Event -> File -> Bool -> Out
endedUnder _ _ f wrote = case f of
  File m a c e -> case a of
    Asset _ o _ _ _ _ _ -> case c of
      Client l open ph d ->
        Out (File m (if wrote then reportWrite a e else a) (Client l open Settled d) (e + 1))
            (settle (phaseReq ph) (Present (endedReply (endingOf o))))
            Absent
            (if phaseJob ph == 1 then Present e else Absent)
            Absent [] Absent

-- | The ending of an asset whose goal is cleared.
{-@ endingOf :: {o:Outcome | isEnded o} -> Ending @-}
endingOf :: Outcome -> Ending
endingOf (Ended en) = en
endingOf Ongoing    = error "endingOf: the precondition says the outcome is ended"

-- | Raise an alarm on a step's output, changing nothing else.
{-@ alerting :: x:Alarm -> o:Out
             -> {p:Out | after p == after o && owedTo p == owedTo o && evTo p == evTo o
                         && stopped p == stopped o && started p == started o && timers p == timers o
                         && alert p == Present x} @-}
alerting :: Alarm -> Out -> Out
alerting x (Out f ow ev st sr ts _) = Out f ow ev st sr ts (Present x)
