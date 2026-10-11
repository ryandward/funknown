-- | Which reply a client gets, and what the step leaves behind, for every
-- request and report Funknown.Client.Upload handles. The contract in
-- Funknown.Client.Contract proves that every owed request is settled or
-- kept and every job is accounted for, but it says nothing about which reply
-- is sent, which offset the client is told, or which row ran. This test does.
--
-- The expected outcome is transcribed from CLIENT.md and the A, B, F and V
-- rows of docs/design/core.md, on a test-side description of each file ('S'),
-- and never calls into the module except to run the step. Every phase the
-- slice handles is covered, crossed with every request shape the rows tell
-- apart: each PATCH field takes a value on each side of every boundary the
-- rows test (absent, the offset, one past it; below, at and above each
-- chunk limit; past max-size), every body length B3 to B8 distinguishes, and
-- every report kind under the current epoch and a stale one. The writes the
-- core authorised are compared entry by entry, epoch and deadline, so a
-- write recorded under the wrong job, or reported under the wrong one,
-- shows up even when the count comes out right. Every shape is also run
-- with its max-age deadline one second after the clock and at the clock, so
-- G3 is checked on both sides of its boundary.
module UploadReplies (main, suite) where

import Control.Monad (forM_, unless, when)
import Data.IORef
import Data.List (intercalate)
import System.Exit (exitFailure)

import Funknown.Opt
import Funknown.Refusal (Refusal (..))
import Funknown.Http.Retry (Backoff (..))
import Funknown.Kernel.Bound (Bound, Version (..), bind)
import Funknown.Kernel.Types (Asset (..), Goal (..), Assembly (..), Ending (..), Outcome (..), Vouch (..), Write (..), Seen (..), StagingRef (..), Config (..))
import Funknown.Store.Algorithm (ReceiptAlgorithm (..), checksumOf)
import Funknown.Store.Receipt (receiptReport)
import Funknown.Upload (Limits (..), Chunk (..), ChunkToken (..), Chunks, emptyChunks, appendChunk, offsetOf)
import Funknown.Client.Types
import Funknown.Client.Upload
import Tally (Tally, newTally, record)

-- Fixtures -------------------------------------------------------------------------

-- | Chunks of 4 to 10 bytes, at most 3 of them, at most 25 bytes in all, so
-- that after two full chunks the read limit is max-size's 5, not a chunk's 10.
limitsFor :: Bool -> Limits
limitsFor = Limits 4 10 3 25

minC, maxC, maxN, maxS :: Int
minC = 4
maxC = 10
maxN = 3
maxS = 25

nowT, replyW, writeDl, waiterBy0 :: Int
nowT = 100
replyW = 30
writeDl = 60
waiterBy0 = 500

envWith :: Int -> Env
envWith quota = Env nowT quota replyW 5 (Config 3 (Backoff 1 30 2) writeDl)

owedId, evId :: Int
owedId = 7
evId = 9

chunksFrom :: Bool -> [Int] -> Chunks
chunksFrom seals = foldl (\c (i, n) -> appendChunk c (Chunk n (ChunkToken ("t" ++ show i)))) (emptyChunks (limitsFor seals)) . zip [(1 :: Int) ..]

boundFor :: Int -> Bound
boundFor n = case checksumOf 7 of
  Present c -> case receiptReport Crc64Nvme c n of
    Present r -> case bind n (Version "v1") r of
      Right b -> b
      Left _  -> error "bind"
    Absent -> error "report"
  Absent -> error "checksum"

-- The test's own description of a file -----------------------------------------------

data Q = QAppend | QCreate deriving (Eq, Show)

data Ph
  = POpening Bool              -- holds the creation request
  | PIdle
  | PReading Q Bool            -- request, UC ?1
  | PWriting (Maybe Q) Int Bool
  | PSealing Bool              -- holds a waiter
  | PSettled
  deriving (Eq, Show)

data GoalS
  = GAsm Bool [Int]            -- staging area adopted, chunk sizes oldest first
  | GDone [Int] Bool           -- chunk sizes, receipt held
  | GClear
  deriving (Eq, Show)

data S = S { sPh :: Ph, sGoal :: GoalS, sOpen :: Bool, sLen :: Maybe Int, sEpoch :: Int, sSeals :: Bool
           , sDeadline :: Int }
  deriving (Show)

-- | G3 (core.md's guards, "in phases Opening and Receiving, if now >=
-- deadline, row X1 runs before anything else"; CLIENT.md round 2, "a
-- request after the deadline on a goal still assembling runs X1 first"):
-- the goal is still assembling and the clock has reached max-age.
expiring :: S -> Bool
expiring s = case sGoal s of
  GAsm _ _ -> nowT >= sDeadline s
  _        -> False

-- | The two deadlines every shape runs with: one second after the clock,
-- and at it.
deadlines :: [Int]
deadlines = [nowT + 1, nowT]

sOff :: S -> Int
sOff s = case sGoal s of
  GAsm _ cs  -> sum cs
  GDone cs _ -> sum cs
  GClear     -> -1

sCount :: S -> Int
sCount s = case sGoal s of
  GAsm _ cs  -> length cs
  GDone cs _ -> length cs
  GClear     -> -1

-- | The writes the core authorised and hasn't seen reported, newest first,
-- as (epoch, deadline). The running write's entry, if one runs, is under the
-- file's epoch. Every file also keeps an older write that was cancelled
-- (B15) and hasn't reported or lapsed, which no row here may touch.
sWrites :: S -> [(Int, Int)]
sWrites s = [ (sEpoch s, nowT + writeDl) | running ] ++ [orphan]
  where running = case sPh s of { PWriting {} -> True; _ -> False }

-- | The cancelled write, under an epoch every shape is past and no report
-- in the cases names.
orphan :: (Int, Int)
orphan = (1, nowT + 5)

-- | The writes once the running write is reported.
reported :: S -> [(Int, Int)]
reported _ = [orphan]

toFile :: S -> File
toFile s = File (Meta (FileId "f1") (UploadId "u1") (sDeadline s) 0) theAsset theClient (sEpoch s)
  where
    seals = sSeals s
    theAsset = case sGoal s of
      GAsm adopted cs -> Asset (Keep (Assembling (if adopted then Present (StagingRef "r") else Absent) (chunksFrom seals cs)))
                               Ongoing Unseen NoReceipt 3 1 ws
      GDone cs rc -> Asset (Keep (Assembled (StagingRef "r") (chunksFrom seals cs))) Ongoing Unseen
                           (if rc then HasReceipt (boundFor (sum cs)) else NoReceipt) 3 1 ws
      GClear -> Asset Clear (Ended Cancelled) Unseen NoReceipt 3 1 ws
    ws = [Write e t | (e, t) <- sWrites s]
    theClient = Client (maybe Unknown Known (sLen s)) (sOpen s) ph False
    req QAppend = AppendReq owedId
    req QCreate = CreationReq owedId
    ph = case sPh s of
      POpening h      -> Opening (if h then Present (Hold owedId True False) else Absent)
      PIdle           -> Idle
      PReading q uc   -> Reading (req q) uc
      PWriting q n uc -> Writing (maybe Absent (Present . req) q) n uc
      PSealing w      -> Sealing (if w then Present (Waiter owedId waiterBy0) else Absent)
      PSettled        -> Settled

-- What a step leaves behind, rendered so two of them compare ---------------------------

data X = X
  { xEv     :: Maybe String
  , xOwed   :: Maybe String
  , xPhase  :: String
  , xGoal   :: String
  , xOpen   :: Bool
  , xLen    :: Maybe Int
  , xStart  :: Maybe String
  , xStop   :: Maybe Int
  , xTimers :: [Int]
  , xAlert  :: Maybe String
  , xEpoch  :: Int
  , xWrites :: [(Int, Int)]
  } deriving (Eq, Show)

observe :: Out -> X
observe (Out (File _ a (Client l open ph _) e) ow ev st sr ts al) = X
  { xEv = settleS <$> optM ev, xOwed = settleS <$> optM ow
  , xPhase = phaseS ph, xGoal = goalS a, xOpen = open
  , xLen = case l of { Known n -> Just n; Unknown -> Nothing }
  , xStart = startS <$> optM sr, xStop = optM st, xTimers = ts
  , xAlert = alarmS <$> optM al, xEpoch = e, xWrites = [ (we, wt) | Write we wt <- authorised a ] }

optM :: Opt a -> Maybe a
optM (Present x) = Just x
optM Absent      = Nothing

settleS :: Settle -> String
settleS (Answer r) = replyS r
settleS Abandoned  = "Abandoned"
settleS Deferred   = "Deferred"

replyS :: Reply -> String
replyS r = case r of
  CreatedUpload (UploadId u) _ n -> "CreatedUpload " ++ u ++ " " ++ show n
  CreatedFile (FileId f) t       -> "CreatedFile " ++ f ++ " " ++ show t
  AppendAccepted n               -> "AppendAccepted " ++ show n
  OffsetIs uc n l _              -> "OffsetIs " ++ show uc ++ " " ++ show n ++ " " ++ show l
  NoContent                      -> "NoContent"
  CancelAccepted                 -> "CancelAccepted"
  OperationIs _                  -> "OperationIs"
  Pending {}                     -> "Pending"
  ObjectIs {}                    -> "ObjectIs"
  AccessIs {}                    -> "AccessIs"
  Content {}                     -> "Content"
  Refuse x uc                    -> "Refuse " ++ refusalS x ++ (if uc == Present True then " ?1" else if uc == Present False then " ?0" else "")

refusalS :: Refusal -> String
refusalS x = case x of
  NotFound -> "NotFound"; MethodNotAllowed -> "MethodNotAllowed"; OffsetMismatch n -> "OffsetMismatch " ++ show n
  AlreadyComplete -> "AlreadyComplete"; OperationInProgress -> "OperationInProgress"; ParentMissing -> "ParentMissing"
  Gone -> "Gone"; PreconditionFailed -> "PreconditionFailed"; MissingOffset -> "MissingOffset"
  InconsistentLength -> "InconsistentLength"; AppendTooSmall _ -> "AppendTooSmall"; DigestUnsupported -> "DigestUnsupported"
  AppendTooLarge _ -> "AppendTooLarge"; ExceedsMaxSize _ -> "ExceedsMaxSize"; OffsetPastLength -> "OffsetPastLength"
  WrongMediaType -> "WrongMediaType"; RateLimited _ -> "RateLimited"; Internal -> "Internal"; DataLoss -> "DataLoss"
  NotImplemented -> "NotImplemented"; StoreUnavailable _ -> "StoreUnavailable"; InsufficientStorage -> "InsufficientStorage"

phaseS :: Phase -> String
phaseS ph = case ph of
  Opening h      -> "Opening" ++ maybe "" (const " hold") (optM h)
  Idle           -> "Idle"
  Reading q uc   -> "Reading " ++ reqS q ++ " " ++ show uc
  Writing q n uc -> "Writing " ++ maybe "-" reqS (optM q) ++ " " ++ show n ++ " " ++ show uc
  Sealing w      -> "Sealing" ++ maybe "" (\(Waiter r t) -> " " ++ show r ++ "@" ++ show t) (optM w)
  Settled        -> "Settled"
  where
    reqS (AppendReq r)   = "append " ++ show r
    reqS (CreationReq r) = "create " ++ show r

goalS :: Asset -> String
goalS a = case goal a of
  Keep (Assembling r c) -> "Assembling " ++ (if optM r == Nothing then "- " else "r ") ++ show (sumC c)
  Keep (Assembled _ c)  -> "Assembled " ++ show (sumC c)
  Clear -> "Clear " ++ case outcome a of
    Ended en -> endingS en
    Ongoing  -> "?"
  where sumC = offsetOf

endingS :: Ending -> String
endingS Deleted    = "Deleted"
endingS Cancelled  = "Cancelled"
endingS (Failed f) = show f

startS :: Start -> String
startS (StartRead e m)                       = "Read " ++ show e ++ " " ++ show m
startS (StartPersist e1 e2 (StagingRef r) k) = "Persist " ++ show e1 ++ " " ++ show e2 ++ " " ++ r ++ " " ++ show k

alarmS :: Alarm -> String
alarmS ShellContract = "ShellContract"
alarmS DataLossAlarm = "DataLoss"
alarmS InternalAlarm = "Internal"

-- The oracle, transcribed from CLIENT.md and core.md -----------------------------------

-- | Nothing changes.
unchanged :: S -> X
unchanged s = X Nothing Nothing (phaseOf s) (goalOf s) (sOpen s) (sLen s) Nothing Nothing [] Nothing (sEpoch s) (sWrites s)

phaseOf :: S -> String
phaseOf s = phaseS ph where File _ _ (Client _ _ ph _) _ = toFile s

goalOf :: S -> String
goalOf s = goalS (fileAsset (toFile s))

owes :: S -> Bool
owes s = case sPh s of
  POpening h       -> h
  PIdle            -> False
  PReading _ _     -> True
  PWriting q _ _   -> q /= Nothing
  PSealing w       -> w
  PSettled         -> False

runsJob :: S -> Bool
runsJob s = case sPh s of
  PReading {} -> True
  PWriting {} -> True
  _           -> False

-- | abandonFile: the goal is cleared with the ending, the owed request gets
-- its answer (abandoned when there is none), a running job is stopped, the
-- client settles under the next epoch.
abandoned :: S -> String -> Maybe String -> Maybe String -> X
abandoned s ending owedAns evAns = (unchanged s)
  { xEv = evAns, xOwed = if owes s then Just (maybe "Abandoned" id owedAns) else Nothing
  , xPhase = "Settled", xGoal = "Clear " ++ ending, xEpoch = sEpoch s + 1
  , xStop = if runsJob s then Just (sEpoch s) else Nothing }

refuse :: String -> String
refuse x = "Refuse " ++ x

-- | The shared append check (CLIENT.md, "One shared append check"): A8, then
-- A1 to A4, then the size rules against the goal's limits.
check :: S -> Patch -> Maybe String
check s p
  | aDigest p                                   = Just "DigestUnsupported"         -- A8
  | aOffset p == Absent                         = Just "MissingOffset"             -- A1
  | aOffset p /= Present off                    = Just ("OffsetMismatch " ++ show off)  -- A2
  | not (aMediaOk p)                            = Just "WrongMediaType"            -- A3
  | any id disagreements                        = Just "InconsistentLength"        -- A4
  | cl (> maxC)                                 = Just "AppendTooLarge"
  | cl (< minC) && not uc1                      = Just "AppendTooSmall"
  | pastMax || (sCount s == maxN && aContent p /= Present 0) = Just "ExceedsMaxSize"
  | otherwise                                   = Nothing
  where
    off = sOff s
    uc1 = aComplete p == Present True
    cl f = maybe False f (optM (aContent p))
    ul = optM (aLength p)
    end = (off +) <$> optM (aContent p)
    -- Each pair of indicators that must agree (R UP:RESUMABLE-UPLOAD-13-4.1.3-3, -6).
    disagreements =
      [ ul /= Nothing && sLen s /= Nothing && ul /= sLen s                       -- Upload-Length and the recorded length
      , maybe False (< off) ul                                                   -- Upload-Length and the offset
      , ul /= Nothing && end /= Nothing && end > ul                              -- Upload-Length and the content
      , uc1 && end /= Nothing && ul /= Nothing && end /= ul                      -- UC ?1 content and Upload-Length
      , uc1 && end /= Nothing && sLen s /= Nothing && end /= sLen s ]            -- UC ?1 content and the recorded length
    pastMax = maybe False (> maxS) ul || maybe False (> maxS) end
              || (not uc1 && aContent p == Absent && off >= maxS)

-- | The length a PATCH makes known: Upload-Length, or under UC ?1 the offset
-- plus Content-Length.
declared :: S -> Patch -> Maybe Int
declared s p = case optM (aLength p) of
  Just n -> Just n
  Nothing | aComplete p == Present True -> (sOff s +) <$> optM (aContent p)
          | otherwise -> Nothing

-- | A1 to A11 on an Idle upload.
idleRows :: Env -> S -> Event -> X
idleRows env s ev = case ev of
  OffsetQuery _ -> (unchanged s) { xEv = Just ("OffsetIs False " ++ show (sOff s) ++ " " ++ lenS (sLen s)) }   -- A10
  CancelUpload _ -> abandoned s "Cancelled" Nothing (Just "NoContent")                                         -- A11
  Append p
    | Just x <- check s p -> (unchanged s) { xEv = Just (refuse x) }
    | sLen s == Nothing, Just n <- declared s p, n > quotaRemaining env
        -> (unchanged s) { xEv = Just (refuse "InsufficientStorage") }                                          -- A5
    | aComplete p == Present True && aContent p == Present 0 && sOff s == 0 && not (sSeals s)
        -> (unchanged s) { xEv = Just (refuse "NotImplemented") }                                               -- A7
    | otherwise -> (unchanged s)                                                                                -- A9
        { xPhase = "Reading append " ++ show evId ++ " " ++ show (aComplete p == Present True)
        , xLen = if sLen s /= Nothing then sLen s else declared s p
        , xEpoch = sEpoch s + 1
        , xStart = Just ("Read " ++ show (sEpoch s + 1) ++ " " ++ show (min maxC (maxS - sOff s))) }
  _ -> error "idleRows: not a request"

lenS :: Maybe Int -> String
lenS = maybe "Unknown" (\n -> "Known " ++ show n)

-- | F6 to F10 and V1 to V5 on a complete upload. ACTIVE is a goal that
-- keeps the asset with a receipt (CLIENT.md slices 1 and 2), and CLIENT.md
-- slice 1 says of Sealing: "If a receipt is already held, treat the file as
-- ACTIVE." So the receipt picks the V rows, in Sealing as in Settled.
completeRows :: S -> Event -> X
completeRows s ev
  | not (sOpen s) = (unchanged s) { xEv = Just (refuse "Gone") }                                   -- F10, V5
  | otherwise = case ev of
      OffsetQuery _
        | receipt -> (unchanged s)                                                                 -- V3: unchanged
            { xEv = Just ("OffsetIs True " ++ show (sOff s) ++ " " ++ lenS (sLen s)) }
        | otherwise -> (unchanged s)                                                               -- F6
            { xEv = Just ("OffsetIs True " ++ show (sOff s) ++ " " ++ lenS (sLen s))
            , xOwed = if owes s then Just "Abandoned" else Nothing
            , xPhase = if sPh s == PSettled then "Settled" else "Sealing" }
      CancelUpload _
        | receipt   -> (unchanged s) { xEv = Just "NoContent", xOpen = False }                     -- V4
        -- F9: CLIENT.md gives the effect (abandonFile Cancelled) but not the
        -- reply. 204 here is the code's choice; core.md F9 says 202, and
        -- that needs a ruling (INTEGRATION.md, "Open questions").
        | otherwise -> abandoned s "Cancelled" Nothing (Just "NoContent")                         -- F9
      Append p
        | Just x <- check s p -> (unchanged s) { xEv = Just (refuse x) }
        | aComplete p == Present True && aContent p == Present 0 ->
            if receipt
              then (unchanged s) { xEv = Just ("CreatedFile f1 " ++ fileTagOf "f1") }         -- V1
              else (unchanged s)                                                                   -- F7
                     { xOwed = if owes s then Just "Abandoned" else Nothing
                     , xPhase = "Sealing " ++ show evId ++ "@" ++ show (nowT + replyW)
                     , xTimers = [nowT + replyW] }
        | maybe False (> 0) (optM (aContent p)) ->
            (unchanged s) { xEv = Just (refuse "OffsetPastLength"), xOpen = False }                -- F8, V2
        | otherwise -> (unchanged s) { xEv = Just (refuse "AlreadyComplete") }                     -- F8, V2
      _ -> error "completeRows: not a request"
  where
    receipt = case sGoal s of { GDone _ rc -> rc; _ -> False }

-- | The strong ETag of the file id (CLIENT.md, slice 2).
fileTagOf :: String -> String
fileTagOf f = "EntityTag {weak = False, opaque = OpaqueTag " ++ show f ++ "}"

-- | A request to the upload resource, in any phase. G3 comes before any
-- cell: X1 ends the file FAILED Expired (the held or in-flight request
-- abandoned, a running mover stopped, a running write's entry kept until
-- its report, as B15 keeps it), and the request is then answered as the
-- END column answers every upload-resource request: 410.
expectRequest :: Env -> S -> Event -> X
expectRequest env s ev
  | expiring s = abandoned s "Expired" Nothing (Just (refuse "Gone"))
  | otherwise = expectRequest' env s ev

expectRequest' :: Env -> S -> Event -> X
expectRequest' env s ev = case (sPh s, sGoal s) of
  (POpening _, _) -> (unchanged s) { xEv = Just (refuse "NotFound") }
  (_, GClear)     -> (unchanged s) { xEv = Just (refuse "Gone") }
  (PIdle, _)      -> idleRows env s ev
  -- B1: stop the reader, abandon its request, and answer as Idle under e + 1.
  (PReading _ _, _) -> (idleRows env s { sPh = PIdle, sEpoch = sEpoch s + 1 } ev)
                         { xOwed = Just "Abandoned", xStop = Just (sEpoch s) }
  (PWriting q n uc, _) -> case ev of
    CancelUpload _ -> abandoned s "Cancelled" Nothing (Just "NoContent")                          -- B15
    _ -> (unchanged s) { xEv = Just "Deferred"                                                    -- B2
                       , xOwed = if q /= Nothing then Just "Abandoned" else Nothing
                       , xPhase = "Writing - " ++ show n ++ " " ++ show uc }
  (PSealing _, _) -> completeRows s ev
  (PSettled, _)   -> completeRows s ev

-- | B11 and B4: complete, check the quota, then wait for the receipt.
completing :: Env -> S -> Int -> Bool -> X
completing env s off' wrote
  | off' > quotaRemaining env =
      (abandoned s "QuotaAtFinalize" (Just (refuse "InsufficientStorage ?1")) Nothing) { xWrites = reported s }
  | otherwise = (unchanged s)
      { xGoal = "Assembled " ++ show off', xLen = Just off', xWrites = reported s
      , xPhase = if owes s then "Sealing " ++ show owedId ++ "@" ++ show (nowT + replyW) else "Sealing"
      , xTimers = [nowT + replyW | owes s]
      , xStop = if wrote then Nothing else Just (sEpoch s) }

-- | A mover's report, in any phase. A job is named by its epoch, so a
-- report under the file's epoch while a job runs is that job's. A kind the
-- job can't send (a write's report from the reader, or the reverse) can only
-- come from a shell that broke its delivery contract, and it is handled the
-- way core.md's G2 handles a store report of the wrong command (C CH42): the
-- running job's own failure row, with an alert, so the file never waits for
-- a report that won't come. CLIENT.md calls such a report stale, but stale
-- stops the very job the file would still be waiting for.
expectReport :: Env -> S -> Event -> X
expectReport env s ev
  | evEpoch ev /= sEpoch s = staleX                                         -- G2: not current
  -- G3, after G2 and before any cell: the running job's own report past
  -- the deadline is X1's. The job is done, so it is stopped, and a write's
  -- own report removes its entry (CLIENT.md round 2). A report of the
  -- wrong kind is G2's (core.md puts CH42 inside G2, and CLIENT.md round 2
  -- runs the mover's "as CH42 does"), so it runs the failure row below.
  | runsJob s && expiring s && not wrongKind =
      (abandoned s "Expired" Nothing Nothing) { xWrites = if isWriting then reported s else sWrites s }
  | otherwise = case sPh s of
      PReading q uc
        | sGoal s == GClear -> flagged (not readKind) cleared
        | readKind          -> reading q uc
        | otherwise         -> flagged True (died q)                        -- B9, CH42
      PWriting q n uc
        | sGoal s == GClear -> flagged (not writeKind) cleared { xWrites = reported s }
        | writeKind         -> writing q n uc
        | otherwise         -> flagged True (writeFailed q)                 -- B12, CH42
      _ -> staleX                                                           -- G2: no job runs
  where
    flagged b x = if b then x { xAlert = Just "ShellContract" } else x
    e = sEpoch s
    isWriting = case sPh s of { PWriting {} -> True; _ -> False }
    wrongKind = case sPh s of { PReading {} -> not readKind; PWriting {} -> not writeKind; _ -> False }
    -- CLIENT.md round 2: a stale mover report also reports under its own
    -- epoch, so a write the file stopped waiting for (B15) gives up its
    -- entry, and with no entry under that epoch nothing changes.
    staleX = (unchanged s) { xStop = Just (evEpoch ev), xWrites = [ w | w@(we, _) <- sWrites s, we /= evEpoch ev ] }
    readKind = case ev of { BodyReceived {} -> True; BodyBroken {} -> True; MoverDied _ -> True; _ -> False }
    writeKind = case ev of { ChunkPersisted {} -> True; ChunkFailed _ -> True; MoverDied _ -> True; _ -> False }
    off = sOff s
    adopted = case sGoal s of { GAsm a _ -> a; _ -> False }
    -- KernelMoved's settlement, for a goal the kernel already cleared.
    cleared = (abandoned s "Cancelled" (Just (refuse "Gone ?1")) Nothing) { xGoal = "Clear Cancelled" }
    uc1For q = if q == QCreate then " ?1" else ""
    -- B5, B6, B8: Idle with the refusal; B16 for the creation request.
    refused q x
      | q == QCreate = abandoned s "CreationRefused" (Just (refuse x ++ " ?1")) Nothing
      | otherwise = (unchanged s) { xPhase = "Idle", xOwed = Just (refuse x), xStop = Just e }
    -- B9; B16 with CreationInterrupted.
    died q
      | q == QCreate = abandoned s "CreationInterrupted" Nothing Nothing
      | otherwise = (unchanged s) { xPhase = "Idle", xOwed = Just "Abandoned", xStop = Just e }
    -- B7
    past q = abandoned s "OutOfRange" (Just (refuse "OffsetPastLength" ++ uc1For q)) Nothing
    contradicted alarm = (abandoned s "Contradiction" (Just (refuse "Internal ?1")) Nothing) { xAlert = Just alarm }
    reading q uc = case ev of
      BodyReceived _ n
        | n < 0 -> (died q) { xAlert = Just "ShellContract" }
        | n == 0 && not uc -> refused q "AppendTooSmall"                                    -- B5
        | n == 0 && maybe False (/= off) (sLen s) -> refused q "InconsistentLength"         -- B6
        | n == 0 && (off > 0 || sSeals s) ->                                                -- B4
            if adopted then completing env s off False else contradicted "Internal"
        | n == 0 -> refused q "NotImplemented"                                              -- B4
        | not uc && n < minC -> refused q "AppendTooSmall"                                  -- B5
        | uc && maybe False (/= off + n) (sLen s) -> refused q "InconsistentLength"         -- B6
        | not uc && maybe False (< off + n) (sLen s) -> past q                              -- B7
        | n > maxC || off + n > maxS || sCount s >= maxN ->                                 -- read past the limit
            (refused q (if n > maxC then "AppendTooLarge" else "ExceedsMaxSize")) { xAlert = Just "ShellContract" }
        | not adopted -> contradicted "Internal"
        | otherwise -> (unchanged s)                                                        -- B3
            { xPhase = "Writing " ++ (if q == QCreate then "create " else "append ") ++ show owedId ++ " " ++ show n ++ " " ++ show uc
            , xEpoch = e + 1, xWrites = (e + 1, nowT + writeDl) : sWrites s
            , xStart = Just ("Persist " ++ show e ++ " " ++ show (e + 1) ++ " r " ++ show (sCount s + 1)) }
      BodyBroken _ ExceededLength -> past q                                                 -- B7
      BodyBroken _ ExceededLimit -> refused q (if maxC <= maxS - off then "AppendTooLarge" else "ExceedsMaxSize")  -- B8
      BodyBroken _ Interrupted -> died q                                                    -- B9
      MoverDied _ -> died q                                                                 -- B9
      _ -> error "reading"
    sizes = case sGoal s of { GAsm _ cs -> cs; _ -> [] }
    accepts k = adopted && k <= maxC && off + k <= maxS && sCount s < maxN
                && (null sizes || last sizes >= minC)
    writing q n uc = case ev of
      ChunkPersisted _ k
        | cbytes k /= n -> (contradicted "ShellContract") { xWrites = reported s }
        | not (accepts n) -> (contradicted "Internal") { xWrites = reported s }
        | uc -> completing env s (off + n) True                                             -- B11
        | otherwise -> (unchanged s)                                                        -- B10
            { xPhase = "Idle", xGoal = "Assembling r " ++ show (off + n), xWrites = reported s
            , xOwed = case q of
                Nothing      -> Nothing
                Just QAppend -> Just ("AppendAccepted " ++ show (off + n))
                Just QCreate -> Just ("CreatedUpload u1 " ++ show (off + n)) }
      _ -> writeFailed q
    -- B12; B16 with Unavailable.
    writeFailed q
      | q == Just QCreate =
          (abandoned s "Unavailable" (Just (refuse "StoreUnavailable ?1")) Nothing) { xWrites = reported s }
      | otherwise = (unchanged s)
          { xPhase = "Idle", xWrites = reported s, xOwed = if q /= Nothing then Just (refuse "StoreUnavailable") else Nothing }

-- The cases ------------------------------------------------------------------------------

shapes :: [S]
shapes = [ s dl | s <- shapes', dl <- deadlines ]

shapes' :: [Int -> S]
shapes' = concat
  [ [ S (POpening h) g True Nothing 4 False | h <- [False, True], g <- [GAsm False [], GClear] ]
  , [ S PIdle (GAsm True cs) True l 4 seals
    | cs <- [[], [10], [10, 10], [10, 10, 4]], l <- [Nothing, Just (sum cs), Just 23], seals <- [False, True] ]
  , [ S (PReading q uc) (GAsm ad cs) True l 4 seals
    -- CLIENT.md round 2, the File refinement: a goal still assembling under
    -- Idle, Reading or Writing has adopted its staging area, so a read never
    -- runs on an assembly with nowhere to write.
    | q <- [QAppend, QCreate], uc <- [False, True], (ad, cs) <- [(True, []), (True, [10]), (True, [10, 10])]
    , l <- [Nothing, Just 23], seals <- [False, True] ]
  , [ S (PWriting q n uc) (GAsm True cs) True Nothing 4 False
    | q <- [Nothing, Just QAppend, Just QCreate], (n, uc) <- [(10, False), (10, True), (3, True)]
    , cs <- [[], [10], [10, 10]] ]
  , [ S (PSealing w) (GDone [10, 3] rc) open (Just 13) 4 False
    | w <- [False, True], rc <- [False, True], open <- [True, False] ]
  , [ S PSettled (GDone [10, 3] rc) open (Just 13) 4 False | rc <- [False, True], open <- [True, False] ]
  , [ S PSettled GClear False Nothing 4 False ]
  , [ S ph GClear True Nothing 4 False
    | ph <- [PIdle, PReading QAppend False, PWriting (Just QAppend) 10 False, PSealing True] ]
  ]

patches :: S -> [Patch]
patches s =
  [ Patch evId o uc ul cl media dig
  | o <- [Absent, Present off, Present (off + 1)]
  , uc <- [Absent, Present False, Present True]
  , ul <- [Absent, Present off, Present (off + 3), Present 23, Present 26]
  , cl <- [Absent, Present 0, Present 3, Present 4, Present 10, Present 11, Present 15]
  , media <- [True, False]
  , dig <- [False, True] ]
  where off = max 0 (sOff s)

requests :: S -> [Event]
requests s = OffsetQuery evId : CancelUpload evId : map Append (patches s)

reports :: S -> [Event]
reports s = concat
  [ [ BodyReceived e n | n <- [-1, 0, 3, 4, 5, 10, 11] ]
  , [ BodyBroken e b | b <- [ExceededLength, ExceededLimit, Interrupted] ]
  , [ ChunkPersisted e (Chunk k (ChunkToken "k")) | k <- [3, 10, 11] ]
  , [ ChunkFailed e, MoverDied e ]
  ]
  where e = sEpoch s

-- | Every report, also under the epoch before the current one, and under
-- the epoch of the cancelled write every file keeps ('orphan'), whose late
-- report is the one that releases its entry.
reportsBoth :: S -> [Event]
reportsBoth s = reports s ++ reports s { sEpoch = sEpoch s - 1 } ++ reports s { sEpoch = fst orphan }

entry :: Event -> Env -> Event -> File -> Out
entry ev = case ev of
  Append _           -> onAppend
  OffsetQuery _      -> onOffsetQuery
  CancelUpload _     -> onCancelUpload
  BodyReceived _ _   -> onBodyReceived
  BodyBroken _ _     -> onBodyBroken
  ChunkPersisted _ _ -> onChunkPersisted
  ChunkFailed _      -> onChunkFailed
  MoverDied _        -> onMoverDied
  _                  -> error "entry: not this slice's event"

eventS :: Event -> String
eventS ev = case ev of
  Append p -> "Append {off=" ++ show (optM (aOffset p)) ++ " uc=" ++ show (optM (aComplete p)) ++ " len=" ++ show (optM (aLength p))
              ++ " cl=" ++ show (optM (aContent p)) ++ " media=" ++ show (aMediaOk p) ++ " digest=" ++ show (aDigest p) ++ "}"
  OffsetQuery _ -> "OffsetQuery"
  CancelUpload _ -> "CancelUpload"
  BodyReceived e n -> "BodyReceived " ++ show e ++ " " ++ show n
  BodyBroken e b -> "BodyBroken " ++ show e ++ " " ++ (case b of { ExceededLength -> "ExceededLength"; ExceededLimit -> "ExceededLimit"; Interrupted -> "Interrupted" })
  ChunkPersisted e k -> "ChunkPersisted " ++ show e ++ " " ++ show (cbytes k)
  ChunkFailed e -> "ChunkFailed " ++ show e
  MoverDied e -> "MoverDied " ++ show e
  _ -> "other"

diffX :: X -> X -> String
diffX want got = intercalate "; " [ f ++ ": want " ++ w ++ ", got " ++ g | (f, w, g) <- fields, w /= g ]
  where
    fields =
      [ ("ev", show (xEv want), show (xEv got)), ("owed", show (xOwed want), show (xOwed got))
      , ("phase", xPhase want, xPhase got), ("goal", xGoal want, xGoal got)
      , ("open", show (xOpen want), show (xOpen got)), ("len", show (xLen want), show (xLen got))
      , ("start", show (xStart want), show (xStart got)), ("stop", show (xStop want), show (xStop got))
      , ("timers", show (xTimers want), show (xTimers got)), ("alert", show (xAlert want), show (xAlert got))
      , ("epoch", show (xEpoch want), show (xEpoch got)), ("writes", show (xWrites want), show (xWrites got)) ]

main :: IO ()
main = do
  t <- newTally
  (total, n) <- suite t (\env ev -> entry ev env ev)
  putStrLn (show total ++ " steps checked, " ++ show n ++ " differ from the design")
  when (n > 0) exitFailure

-- | Every case above through the step it is given: this slice's entry
-- points for this suite, the dispatcher for test/Dispatch.hs. Returns how
-- many steps ran and how many differ from the design.
suite :: Tally -> (Env -> Event -> File -> Out) -> IO (Int, Int)
suite tally step = do
  failures <- newIORef (0 :: Int)
  count <- newIORef (0 :: Int)
  forM_ [envWith 1000, envWith 12] $ \env ->
    forM_ shapes $ \s ->
      forM_ ([ (ev, expectRequest env s ev) | ev <- requests s ] ++ [ (ev, expectReport env s ev) | ev <- reportsBoth s ]) $ \(ev, want) -> do
        modifyIORef' count (+ 1)
        record tally ev
        let got = observe (step env ev (toFile s))
        unless (got == want) $ do
          n <- readIORef failures
          when (n < 25) $ putStrLn ("FAIL quota=" ++ show (quotaRemaining env) ++ " " ++ show s ++ "\n  " ++ eventS ev ++ "\n  " ++ diffX want got)
          modifyIORef' failures (+ 1)
  n <- readIORef failures
  total <- readIORef count
  return (total, n)
