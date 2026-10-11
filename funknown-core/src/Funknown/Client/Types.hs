{-# LANGUAGE Safe #-}
-- | The client-facing half of a file: the upload draft's request handling,
-- attached to the kernel's 'Asset'. See "Reattaching the client side" in
-- docs/design/kernel.md.
--
-- The asset keeps everything the store side needs; the client keeps only
-- what the upload protocol needs on top of it. The offset a client is told
-- is the goal's chunk total, so the client has no offset of its own.
module Funknown.Client.Types
  ( Instant, ReqId, Epoch
  , FileId (..), UploadId (..)
  , Req (..), reqId
  , Hold (..), holdReq
  , Waiter (..), waiterReq, waiterBy
  , Phase (..), phaseTag, phaseReq, phaseOwes, phaseJob, phaseWait, fitsGoal
  , holdContent, holdUc, openContent, openUc, goalSealsEmpty
  , Meta (..)
  , Client (..)
  , File (..), owedReq, fileOwes, owedJob, fileEpoch, fileWait, fileAsset, filePhase
  , goalOffset, goalCount, goalMaxChunk, goalMaxSize, readCap
  , writeEpoch, writeBy, headWriteEpoch, headWriteBy, writeEpochs
  , Patch (..), Broken (..), Conditions (..)
  , Event (..), evReq, evEpoch, isMoverReport, isTick, readOnlyReport, writeOnlyReport
  , Op (..), Reply (..), replyOffset, refusalOffset
  , faultRefusal, endingRefusal, outcomeRefusal
  , Settle (..), settleWith, optAnswer, settleOffset, optReplyOffset
  , Start (..), startEpoch, startBytes, Alarm (..)
  , Out (..), optStartEpoch, optStartTag, optStartBytes, optStartChunk, optStartStaging, optEpoch
  , Env (..)
  ) where

import Funknown.Opt
import Funknown.Fault (Fault (..))
import Funknown.Http.Precondition (TagField, RangeValidator, Seconds)
import Funknown.Http.Range (RangeSpec)
import Funknown.Http.Validator (EntityTag)
import Funknown.Kernel.Bound (Bound)
import qualified Data.Set as S
import Funknown.Kernel.Types (Asset (..), Goal (..), Assembly (..), StagingRef (..), Write (..), Ending (..), Outcome (..), goalTag, goalAdopted, Config)
import Funknown.Refusal (Refusal (..))
import Funknown.Upload (Chunk, Chunks, Limits (..), limitsOf, offsetOf, nChunks)

type Instant = Int
type ReqId   = Int
type Epoch   = Int

data FileId   = FileId [Char]   deriving (Eq, Show)
data UploadId = UploadId [Char] deriving (Eq, Show)

-- | Whether a request in flight is the creation request's own content. That
-- request is answered with 201 and Location, and a failure of it ends the
-- file, because its client never learned the upload resource.
data Req = CreationReq ReqId | AppendReq ReqId

{-@ measure reqId @-}
reqId :: Req -> ReqId
reqId (CreationReq r) = r
reqId (AppendReq r)   = r

-- | The creation request, held until the reconciler adopts a staging area:
-- its id, whether it carries content, and whether that content completes.
data Hold = Hold ReqId Bool Bool

{-@ measure holdReq @-}
holdReq :: Hold -> ReqId
holdReq (Hold r _ _) = r

-- | The completing request, held until a receipt appears, and when it gets
-- a 202 instead.
data Waiter = Waiter ReqId Instant

{-@ measure waiterReq @-}
waiterReq :: Waiter -> ReqId
waiterReq (Waiter r _) = r

{-@ measure waiterBy @-}
waiterBy :: Waiter -> Instant
waiterBy (Waiter _ t) = t

-- | What the client side is doing. Each phase carries only the request and
-- job it can have, so the file owes at most one request at a time.
data Phase
  = Opening (Opt Hold)          -- ^ waiting for a staging area; the creation request, if held
  | Idle                        -- ^ assembling, nothing in flight
  | Reading Req Bool            -- ^ reading an append's body (a mover job); whether it completes
  | Writing (Opt Req) Int Bool  -- ^ writing a chunk of n bytes (a mover job); its request, if still waiting
  | Sealing (Opt Waiter)        -- ^ complete; waiting for the receipt; the completing request, if held
  | Settled                     -- ^ nothing pending: ACTIVE, or the goal is cleared
{-@ data Phase
      = Opening { openHold :: Opt Hold }
      | Idle
      | Reading { readReq :: Req, readUc :: Bool }
      | Writing { writeReq :: Opt Req, writeBytes :: {n:Int | n >= 1}, writeUc :: Bool }
      | Sealing { sealWaiter :: Opt Waiter }
      | Settled @-}

{-@ measure phaseTag @-}
{-@ phaseTag :: Phase -> {t:Int | 0 <= t && t <= 5} @-}
phaseTag :: Phase -> Int
phaseTag (Opening _)      = 0
phaseTag Idle             = 1
phaseTag (Reading _ _)    = 2
phaseTag (Writing _ _ _)  = 3
phaseTag (Sealing _)      = 4
phaseTag Settled          = 5

{-@ measure phaseReq @-}
phaseReq :: Phase -> Opt ReqId
phaseReq (Opening Absent)              = Absent
phaseReq (Opening (Present h))         = Present (holdReq h)
phaseReq Idle                          = Absent
phaseReq (Reading q _)                 = Present (reqId q)
phaseReq (Writing Absent _ _)          = Absent
phaseReq (Writing (Present q) _ _)     = Present (reqId q)
phaseReq (Sealing Absent)              = Absent
phaseReq (Sealing (Present w))         = Present (waiterReq w)
phaseReq Settled                       = Absent

-- | Whether the phase holds a request: 'phaseReq' is present. A row spec
-- that has to decide which row ran reads this, because z3 only learns
-- 'isPresent' of an 'Opt' that code built, and a matched phase's request
-- isn't rebuilt.
{-@ measure phaseOwes @-}
phaseOwes :: Phase -> Bool
phaseOwes (Opening (Present _))     = True
phaseOwes (Opening Absent)          = False
phaseOwes Idle                      = False
phaseOwes (Reading _ _)             = True
phaseOwes (Writing (Present _) _ _) = True
phaseOwes (Writing Absent _ _)      = False
phaseOwes (Sealing (Present _))     = True
phaseOwes (Sealing Absent)          = False
phaseOwes Settled                   = False

-- | 1 when a mover job runs under the file's epoch, 0 otherwise.
{-@ measure phaseJob @-}
phaseJob :: Phase -> Int
phaseJob (Opening _)     = 0
phaseJob Idle            = 0
phaseJob (Reading _ _)   = 1
phaseJob (Writing _ _ _) = 1
phaseJob (Sealing _)     = 0
phaseJob Settled         = 0

-- | The instant a held completing request gets its 202, or -1.
{-@ measure phaseWait @-}
phaseWait :: Phase -> Int
phaseWait (Sealing (Present w)) = waiterBy w
phaseWait (Sealing Absent)      = -1
phaseWait (Opening _)           = -1
phaseWait Idle                  = -1
phaseWait (Reading _ _)         = -1
phaseWait (Writing _ _ _)       = -1
phaseWait Settled               = -1

-- | What the held creation request carries: content, and UC ?1. Both
-- are False outside Opening or with nothing held.

{-@ measure holdContent @-}
holdContent :: Hold -> Bool
holdContent (Hold _ c _) = c

{-@ measure holdUc @-}
holdUc :: Hold -> Bool
holdUc (Hold _ _ u) = u

{-@ measure openContent @-}
openContent :: Phase -> Bool
openContent (Opening (Present h)) = holdContent h
openContent (Opening Absent)      = False
openContent Idle                  = False
openContent (Reading _ _)         = False
openContent (Writing _ _ _)       = False
openContent (Sealing _)           = False
openContent Settled               = False

{-@ measure openUc @-}
openUc :: Phase -> Bool
openUc (Opening (Present h)) = holdUc h
openUc (Opening Absent)      = False
openUc Idle                  = False
openUc (Reading _ _)         = False
openUc (Writing _ _ _)       = False
openUc (Sealing _)           = False
openUc Settled               = False

-- | Whether the store can seal zero chunks, under the goal's limits.
{-@ measure goalSealsEmpty @-}
goalSealsEmpty :: Goal -> Bool
goalSealsEmpty (Keep (Assembling _ c)) = sealsEmpty (limitsOf c)
goalSealsEmpty (Keep (Assembled _ c))  = sealsEmpty (limitsOf c)
goalSealsEmpty Clear                   = False

-- | The phases a goal allows. The kernel can clear a goal at any time, so
-- every phase allows a cleared goal until the next step settles it; only
-- the client ever completes an assembly, so an assembly in progress never
-- meets a sealing phase, and a completed one never meets an append.
{-@ inline fitsGoal @-}
fitsGoal :: Int -> Int -> Bool
fitsGoal g p =
  g == 0
  || (g == 2 && p <= 3)
  || (g == 1 && (p == 4 || p == 5))

-- | The total of the chunks the goal holds, whether still assembling or
-- complete; -1 when the goal is clear.
{-@ measure goalOffset @-}
goalOffset :: Goal -> Int
goalOffset (Keep (Assembling _ c)) = offsetOf c
goalOffset (Keep (Assembled _ c))  = offsetOf c
goalOffset Clear                   = -1

-- | How many chunks the goal holds, whether still assembling or complete;
-- -1 when the goal is clear. B11 appends and completes in one step, which
-- KMove admits as exactly one chunk more.
{-@ measure goalCount @-}
goalCount :: Goal -> Int
goalCount (Keep (Assembling _ c)) = nChunks c
goalCount (Keep (Assembled _ c))  = nChunks c
goalCount Clear                   = -1

-- | How many bytes the next append's read may take: one chunk, and never
-- past max-size (A9, PM16). O2 reads the creation request's content with
-- the same bound, at offset 0. ClientOut states every read against it, and
-- 'Funknown.Client.Core.readCapOf' is the one place code computes it.
{-@ inline readCap @-}
readCap :: Int -> Int -> Int -> Int
readCap maxC maxS off = if maxC <= maxS - off then maxC else maxS - off

-- | The goal's chunk-size and max-size limits, which the read cap in
-- "Funknown.Client.Core" is computed from; -1 when the goal is clear.
{-@ measure goalMaxChunk @-}
goalMaxChunk :: Goal -> Int
goalMaxChunk (Keep (Assembling _ c)) = maxChunk (limitsOf c)
goalMaxChunk (Keep (Assembled _ c))  = maxChunk (limitsOf c)
goalMaxChunk Clear                   = -1

{-@ measure goalMaxSize @-}
goalMaxSize :: Goal -> Int
goalMaxSize (Keep (Assembling _ c)) = maxSize (limitsOf c)
goalMaxSize (Keep (Assembled _ c))  = maxSize (limitsOf c)
goalMaxSize Clear                   = -1

data Meta = Meta { fileId :: FileId, uploadId :: UploadId, deadline :: Instant, createdAt :: Int }
{-@ data Meta = Meta { fileId :: FileId, uploadId :: UploadId, deadline :: Nat, createdAt :: Int } @-}

-- | 'clientLen' is the Upload-Length a request declared. It isn't named
-- @uploadLen@, because "Funknown.Upload" has a field of that name, and
-- LiquidHaskell resolves logic names across every loaded module.
data Client = Client
  { clientLen  :: Len       -- ^ Upload-Length, once a request declared it
  , uploadOpen :: Bool      -- ^ the upload resource still accepts requests
  , phase      :: Phase
  , opDeleted  :: Bool      -- ^ the client deleted the operation (DeleteOperation)
  }
{-@ data Client = Client { clientLen :: Len, uploadOpen :: Bool, phase :: Phase, opDeleted :: Bool } @-}

-- | A goal still assembling under Idle, Reading or Writing has adopted its
-- staging area: Opening is the only phase that waits for one, and it leaves
-- only once the kernel adopted one, so an append always has somewhere to go.
data File = File { meta :: Meta, asset :: Asset, client :: Client, epoch :: Int }
{-@ data File = File
      { meta   :: Meta
      , asset  :: Asset
      , client :: {c:Client | fitsGoal (goalTag (goal asset)) (phaseTag (phase c))
                              && ((goalTag (goal asset) == 2 && 1 <= phaseTag (phase c) && phaseTag (phase c) <= 3)
                                    => goalAdopted (goal asset))}
      , epoch  :: Nat } @-}

{-@ measure owedReq @-}
owedReq :: File -> Opt ReqId
owedReq (File _ _ c _) = phaseReq (phase c)

{-@ measure fileOwes @-}
fileOwes :: File -> Bool
fileOwes (File _ _ c _) = phaseOwes (phase c)

{-@ measure owedJob @-}
owedJob :: File -> Int
owedJob (File _ _ c _) = phaseJob (phase c)

{-@ measure fileEpoch @-}
fileEpoch :: File -> Int
fileEpoch (File _ _ _ e) = e

{-@ measure fileWait @-}
fileWait :: File -> Int
fileWait (File _ _ c _) = phaseWait (phase c)

{-@ measure fileAsset @-}
fileAsset :: File -> Asset
fileAsset (File _ a _ _) = a

-- | Which phase the file is in, as 'phaseTag' numbers it.
{-@ measure filePhase @-}
filePhase :: File -> Int
filePhase (File _ _ c _) = phaseTag (phase c)

-- Writes the core authorised -----------------------------------------------------

-- | A write the core authorised names the job writing it and the instant
-- by which the shell aborts it (A3).
{-@ measure writeEpoch @-}
writeEpoch :: Write -> Int
writeEpoch (Write e _) = e

{-@ measure writeBy @-}
writeBy :: Write -> Int
writeBy (Write _ t) = t

-- | The write authorised last, which 'startWrite' puts at the head; -1 when
-- there is none.
{-@ measure headWriteEpoch @-}
headWriteEpoch :: [Write] -> Int
headWriteEpoch (w : _) = writeEpoch w
headWriteEpoch []      = -1

{-@ measure headWriteBy @-}
headWriteBy :: [Write] -> Int
headWriteBy (w : _) = writeBy w
headWriteBy []      = -1

-- | The epochs of every write still authorised. A write's report removes
-- its own epoch from this set.
{-@ measure writeEpochs @-}
writeEpochs :: [Write] -> S.Set Int
writeEpochs []      = S.empty
writeEpochs (w : ws) = S.union (S.singleton (writeEpoch w)) (writeEpochs ws)

-- Events -----------------------------------------------------------------------

-- | A PATCH to the upload resource, its fields already parsed by the shell.
data Patch = Patch
  { aReq      :: ReqId
  , aOffset   :: Opt Int    -- ^ Upload-Offset
  , aComplete :: Opt Bool   -- ^ Upload-Complete
  , aLength   :: Opt Int    -- ^ Upload-Length
  , aContent  :: Opt Int    -- ^ Content-Length
  , aMediaOk  :: Bool       -- ^ Content-Type is application/partial-upload
  , aDigest   :: Bool       -- ^ any integrity field was sent
  }
{-@ data Patch = Patch { aReq :: ReqId, aOffset :: Opt Nat, aComplete :: Opt Bool, aLength :: Opt Nat
                       , aContent :: Opt Nat, aMediaOk :: Bool, aDigest :: Bool } @-}

data Broken = ExceededLength | ExceededLimit | Interrupted

-- | A request's conditional header fields and Range, parsed by the shell.
data Conditions = Conditions
  { cIfMatch :: Opt TagField, cIfNoneMatch :: Opt TagField, cIfUnmodSince :: Opt Seconds
  , cIfModSince :: Opt Seconds, cRange :: Opt RangeSpec, cIfRange :: Opt RangeValidator, cHead :: Bool }

-- | Everything that can happen to an existing file on the client side.
-- 'KernelMoved' is delivered after every kernel round, so held requests can
-- be answered; it carries nothing, because the asset already shows it.
data Event
  = Append Patch
  | OffsetQuery ReqId
  | CancelUpload ReqId
  | CancelOperation ReqId
  | GetOperation ReqId
  | DeleteOperation ReqId
  | GetObject ReqId
  | GetAccessUrl ReqId
  | GetContent ReqId Conditions
  | DeleteFile ReqId Conditions
  | BodyReceived Epoch Int
  | BodyBroken Epoch Broken
  | ChunkPersisted Epoch Chunk
  | ChunkFailed Epoch
  | MoverDied Epoch
  | KernelMoved
  | Tick

{-@ measure evReq @-}
evReq :: Event -> Opt ReqId
evReq (Append a)          = Present (aReq a)
evReq (OffsetQuery r)     = Present r
evReq (CancelUpload r)    = Present r
evReq (CancelOperation r) = Present r
evReq (GetOperation r)    = Present r
evReq (DeleteOperation r) = Present r
evReq (GetObject r)       = Present r
evReq (GetAccessUrl r)    = Present r
evReq (GetContent r _)    = Present r
evReq (DeleteFile r _)    = Present r
evReq (BodyReceived _ _)  = Absent
evReq (BodyBroken _ _)    = Absent
evReq (ChunkPersisted _ _) = Absent
evReq (ChunkFailed _)     = Absent
evReq (MoverDied _)       = Absent
evReq KernelMoved         = Absent
evReq Tick                = Absent

{-@ measure evEpoch @-}
evEpoch :: Event -> Int
evEpoch (BodyReceived e _)   = e
evEpoch (BodyBroken e _)     = e
evEpoch (ChunkPersisted e _) = e
evEpoch (ChunkFailed e)      = e
evEpoch (MoverDied e)        = e
evEpoch _                    = -1

{-@ measure isMoverReport @-}
isMoverReport :: Event -> Bool
isMoverReport (BodyReceived _ _)   = True
isMoverReport (BodyBroken _ _)     = True
isMoverReport (ChunkPersisted _ _) = True
isMoverReport (ChunkFailed _)      = True
isMoverReport (MoverDied _)        = True
isMoverReport _                    = False

-- | Reports only a reader sends, and reports only a writer sends.
-- 'MoverDied' is either job's. The contract reads these to tell a
-- current report of the wrong kind (G2, CH42) from one G3 stands before.
{-@ measure readOnlyReport @-}
readOnlyReport :: Event -> Bool
readOnlyReport (BodyReceived _ _) = True
readOnlyReport (BodyBroken _ _)   = True
readOnlyReport _                  = False

{-@ measure writeOnlyReport @-}
writeOnlyReport :: Event -> Bool
writeOnlyReport (ChunkPersisted _ _) = True
writeOnlyReport (ChunkFailed _)      = True
writeOnlyReport _                    = False

-- | The clock's event. KernelMoved and a Tick are the two events that carry
-- no request and report no job, and the contract tells them apart by this:
-- only a Tick reads the clock (T2, X1), and only KernelMoved reads what the
-- kernel round left (CQuietGoal).
{-@ measure isTick @-}
isTick :: Event -> Bool
isTick Tick = True
isTick _    = False

-- Replies and the step's output -----------------------------------------------

-- | A google.longrunning Operation's state: done and a result go together.
data Op = OpRunning | OpSucceeded FileId Bound | OpFailed Fault | OpCancelled

-- | What a request is answered with, as values; the projection renders it.
data Reply
  = CreatedUpload UploadId Limits Int     -- ^ 201, Location, Upload-Limit, Upload-Offset, UC ?0
  | CreatedFile FileId EntityTag          -- ^ 201, Location, ETag, UC ?1
  | AppendAccepted Int                    -- ^ 204, Upload-Offset, UC ?0
  | OffsetIs Bool Int Len Limits          -- ^ 204 to an offset retrieval
  | NoContent                             -- ^ 204
  | CancelAccepted                        -- ^ 200 to CancelOperation
  | OperationIs Op                        -- ^ 200 to GetOperation
  | Pending (Opt Op) (Opt Int) Bool       -- ^ 202: the operation as its body, Retry-After, UC ?1 when true
  | ObjectIs FileId Bound                 -- ^ 200, the DRS object
  | AccessIs FileId Bound                 -- ^ 200, the access URL
  | Content Bound Conditions              -- ^ the ladder, then the range
  | Refuse Refusal (Opt Bool)             -- ^ 4xx or 5xx, with Upload-Complete when given

-- | The offset a reply tells the client: the Upload-Offset of AppendAccepted,
-- CreatedUpload, an offset retrieval's OffsetIs (A10, F6, V3), and A2's
-- OffsetMismatch refusal; -1 for every other reply.
{-@ measure replyOffset @-}
replyOffset :: Reply -> Int
replyOffset (CreatedUpload _ _ n) = n
replyOffset (AppendAccepted n)    = n
replyOffset (CreatedFile _ _)     = -1
replyOffset (OffsetIs _ n _ _)    = n
replyOffset NoContent             = -1
replyOffset CancelAccepted        = -1
replyOffset (OperationIs _)       = -1
replyOffset (Pending _ _ _)       = -1
replyOffset (ObjectIs _ _)        = -1
replyOffset (AccessIs _ _)        = -1
replyOffset (Content _ _)         = -1
replyOffset (Refuse x _)          = refusalOffset x

-- | The Upload-Offset a refusal carries: only A2's 409 has one.
{-@ measure refusalOffset @-}
refusalOffset :: Refusal -> Int
refusalOffset (OffsetMismatch n) = n
refusalOffset _                  = -1

-- | What a request still waiting on the file is told when the goal is
-- cleared under it. Every ending maps to exactly one refusal here, so no two
-- rows can tell a client different things about the same ending. It is a
-- measure so a row's spec can name the refusal it owes (a cleared goal's
-- settlement, CancelOperation's owed request).
{-@ measure faultRefusal @-}
faultRefusal :: Fault -> Refusal
faultRefusal Expired              = Gone
faultRefusal FinalizeTimedOut     = StoreUnavailable Absent
faultRefusal OutOfRange           = Internal
faultRefusal TooLarge             = Internal
faultRefusal QuotaAtFinalize      = InsufficientStorage
faultRefusal Revoked              = Internal
faultRefusal Empty                = Internal
faultRefusal CreationRefused      = Internal
faultRefusal CreationInterrupted  = Internal
faultRefusal StateLost            = DataLoss
faultRefusal SizeMismatch         = DataLoss
faultRefusal ObjectWithoutReceipt = Internal
faultRefusal StoreRefusedUs       = Internal
faultRefusal Contradiction        = Internal
faultRefusal Unavailable          = StoreUnavailable Absent
faultRefusal SourceUnreachable    = Internal
faultRefusal (SourceAnswered _)   = Internal
faultRefusal SourceChanged        = Internal

{-@ measure endingRefusal @-}
endingRefusal :: Ending -> Refusal
endingRefusal Deleted    = Gone
endingRefusal Cancelled  = Gone
endingRefusal (Failed f) = faultRefusal f

-- | The refusal a cleared asset's ending gives; an asset whose goal is
-- cleared always has an ending ('Asset''s refinement), so 'Internal' for
-- 'Ongoing' is never read.
{-@ measure outcomeRefusal @-}
outcomeRefusal :: Outcome -> Refusal
outcomeRefusal (Ended e) = endingRefusal e
outcomeRefusal Ongoing   = Internal

data Settle = Answer Reply | Abandoned | Deferred

-- | How a request is settled given its answer, if it has one.
{-@ measure settleWith @-}
settleWith :: Opt Reply -> Settle
settleWith (Present x) = Answer x
settleWith Absent      = Abandoned

-- | The event's own settlement when it is answered with what is given.
{-@ measure optAnswer @-}
optAnswer :: Opt Reply -> Opt Settle
optAnswer Absent      = Absent
optAnswer (Present x) = Present (Answer x)

-- | The offset an answer, if there is one, tells its client, or -1.
{-@ measure optReplyOffset @-}
optReplyOffset :: Opt Reply -> Int
optReplyOffset (Present x) = replyOffset x
optReplyOffset Absent      = -1

-- | The offset a settlement tells its client, or -1.
{-@ measure settleOffset @-}
settleOffset :: Opt Settle -> Int
settleOffset (Present (Answer x)) = replyOffset x
settleOffset (Present Abandoned)  = -1
settleOffset (Present Deferred)   = -1
settleOffset Absent               = -1

-- | The one mover job a client step may start, under the epoch it names.
data Start
  = StartRead Epoch Int                    -- ^ read at most n bytes of the owed request's body
  | StartPersist Epoch Epoch StagingRef Int -- ^ the buffer read under e1 becomes job e2: write it as chunk k

{-@ measure startEpoch @-}
startEpoch :: Start -> Epoch
startEpoch (StartRead e _)        = e
startEpoch (StartPersist _ e _ _) = e

-- | How many bytes a read may take; -1 for a persist.
{-@ measure startBytes @-}
startBytes :: Start -> Int
startBytes (StartRead _ n)        = n
startBytes (StartPersist _ _ _ _) = -1

data Alarm = ShellContract | DataLossAlarm | InternalAlarm

data Out = Out
  { after   :: File
  , owedTo  :: Opt Settle    -- ^ the request the old state owed
  , evTo    :: Opt Settle    -- ^ the request this event carried
  , stopped :: Opt Epoch     -- ^ stop the job under this epoch and release its buffer
  , started :: Opt Start
  , timers  :: [Instant]
  , alert   :: Opt Alarm
  }
{-@ data Out = Out { after :: File, owedTo :: Opt Settle, evTo :: Opt Settle, stopped :: Opt Epoch
                   , started :: Opt Start, timers :: [Instant], alert :: Opt Alarm } @-}

{-@ measure optStartEpoch @-}
optStartEpoch :: Opt Start -> Int
optStartEpoch Absent      = -1
optStartEpoch (Present s) = startEpoch s

-- | 0 no job, 1 a read, 2 a persist.
{-@ measure optStartTag @-}
optStartTag :: Opt Start -> Int
optStartTag (Present (StartPersist _ _ _ _)) = 2
optStartTag (Present (StartRead _ _))        = 1
optStartTag Absent                           = 0

{-@ measure optStartBytes @-}
optStartBytes :: Opt Start -> Int
optStartBytes (Present s) = startBytes s
optStartBytes Absent      = -1

-- | A persist's chunk number and staging area.
{-@ measure optStartChunk @-}
optStartChunk :: Opt Start -> Int
optStartChunk (Present (StartPersist _ _ _ k)) = k
optStartChunk (Present (StartRead _ _))        = -1
optStartChunk Absent                           = -1

{-@ measure optStartStaging @-}
optStartStaging :: Opt Start -> StagingRef
optStartStaging (Present (StartPersist _ _ r _)) = r
optStartStaging (Present (StartRead _ _))        = StagingRef []
optStartStaging Absent                           = StagingRef []

{-@ measure optEpoch @-}
optEpoch :: Opt Int -> Int
optEpoch Absent      = -1
optEpoch (Present e) = e

-- | The step's clock and settings. The clock is 'envNow', not @now@, because
-- "Funknown.Kernel.Types"' own Env has a @now@, and a spec would otherwise
-- have to qualify it.
data Env = Env { envNow :: Instant, quotaRemaining :: Int, replyWait :: Int, pendingDelay :: Int, kernel :: Config }
{-@ data Env = Env { envNow :: Nat, quotaRemaining :: Nat, replyWait :: Nat, pendingDelay :: Nat, kernel :: Config } @-}
