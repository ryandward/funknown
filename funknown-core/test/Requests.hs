-- | Slice 2's replies and effects, which ClientOut doesn't state: which
-- answer each operation, object and content request gets, and what it does
-- to the file. The expectations below are transcribed from CLIENT.md's
-- Slice 2 rulings, core.md's guards and rows (G3 with X1, G4, Q1-Q3,
-- R1-R7, F1), kernel.md's watch table and RFC 9110 13.2.2, written apart
-- from Funknown.Client.Requests, and checked over every phase each goal
-- allows, both values of opDeleted, a deadline on either side of now,
-- every request kind, and every combination of the precondition fields a
-- DELETE can carry.
-- Nothing is sampled: each dimension is the full set of cases the rulings
-- distinguish.
module Requests (main, suite) where

import Control.Monad (unless)
import Data.IORef
import System.Exit (exitFailure)

import Funknown.Opt
import Funknown.Fault (Fault (..))
import Funknown.Refusal (Refusal (..))
import Funknown.Client.Types
import Funknown.Client.Requests
import Funknown.Http.Precondition (TagField (..), RangeValidator (..))
import Funknown.Http.Range (RangeSpec (..))
import Funknown.Http.Retry (Backoff (..))
import Funknown.Http.Validator (EntityTag (..), OpaqueTag (..))
import Funknown.Kernel.Bound
import Funknown.Kernel.Types (Asset (..), Goal (..), Assembly (..), Ending (..), Outcome (..), Vouch (..), Seen (..), StagingRef (..), Config (..))
import Funknown.Store.Algorithm (ReceiptAlgorithm (..), checksumOf)
import Funknown.Store.Receipt (ReceiptReport, receiptReport)
import Funknown.Upload
import Tally (Tally, newTally, record)

-- Fixtures ---------------------------------------------------------------------

lim :: Limits
lim = Limits 1 10 4 100 False

theChunks :: Chunks
theChunks = appendChunk (appendChunk (emptyChunks lim) (Chunk 10 (ChunkToken "t1"))) (Chunk 3 (ChunkToken "t2"))

report :: Int -> ReceiptReport
report n = case checksumOf 7 of
  Present c -> case receiptReport Crc64Nvme c n of
    Present r -> r
    Absent    -> error "size"
  Absent -> error "checksum"

bound :: Bound
bound = case bind 13 (Version "v1") (report 13) of
  Right b -> b
  Left _  -> error "bind"

cur :: StagingRef
cur = StagingRef "current"

env :: Env
env = Env 100 1000 30 7 (Config 3 (Backoff 1 30 2) 60)

fid :: [Char]
fid = "file-1"

created :: Int
created = 50

-- | The file's ETag, as CLIENT.md rules it: strong, the file id's string.
theTag, weakTag, otherTag :: EntityTag
theTag   = EntityTag False (OpaqueTag fid)
weakTag  = EntityTag True (OpaqueTag fid)
otherTag = EntityTag False (OpaqueTag "other")

-- | The asset's shapes a request can meet: the goal, whether a receipt is
-- held, and for a cleared goal its ending. A Deleted ending without a
-- receipt and a Cancelled one with a receipt are left out, because only a
-- DELETE of an ACTIVE file sets Deleted, a cancel of an ACTIVE file changes
-- nothing (Q1), and the kernel never drops a receipt.
data A = AClear Ending Bool | AAsmNone | AAsmCur | ADone | AActive

instance Show A where
  show (AClear e r) = "Clear " ++ showEnding e ++ (if r then " +receipt" else "")
  show AAsmNone     = "Assembling, nothing adopted"
  show AAsmCur      = "Assembling into current"
  show ADone        = "Assembled, no receipt"
  show AActive      = "ACTIVE"

assets :: [A]
assets =
  [ AClear Deleted True, AClear Cancelled False, AClear (Failed Unavailable) False
  , AClear (Failed SizeMismatch) True, AAsmNone, AAsmCur, ADone, AActive ]

toAsset :: A -> Asset
toAsset a = Asset g o Unseen v 1 1 []
  where
    (g, o, v) = case a of
      AClear e r -> (Clear, Ended e, if r then HasReceipt bound else NoReceipt)
      AAsmNone   -> (Keep (Assembling Absent theChunks), Ongoing, NoReceipt)
      AAsmCur    -> (Keep (Assembling (Present cur) theChunks), Ongoing, NoReceipt)
      ADone      -> (Keep (Assembled cur theChunks), Ongoing, NoReceipt)
      AActive    -> (Keep (Assembled cur theChunks), Ongoing, HasReceipt bound)

-- | 0 cleared, 1 assembled, 2 assembling, as the asset's goal tag.
goalOf :: A -> Int
goalOf (AClear _ _) = 0
goalOf ADone        = 1
goalOf AActive      = 1
goalOf _            = 2

owedId :: Int
owedId = 7

-- | Every phase shape, with and without its request where it can have one.
phases :: [Phase]
phases =
  [ Opening Absent, Opening (Present (Hold owedId True False)), Idle
  , Reading (AppendReq owedId) False, Reading (CreationReq owedId) True
  , Writing Absent 5 False, Writing (Present (AppendReq owedId)) 5 True
  , Sealing Absent, Sealing (Present (Waiter owedId 500)), Settled ]

-- | The phases a goal allows, from the comment on 'fitsGoal': a cleared goal
-- allows every phase, an assembly in progress never meets a sealing phase,
-- and a completed one never meets an append.
allowed :: Int -> Phase -> Bool
allowed 0 _ = True
allowed 2 p = case p of { Sealing _ -> False; Settled -> False; _ -> True }
allowed _ p = case p of { Sealing _ -> True; Settled -> True; _ -> False }

theEpoch :: Int
theEpoch = 4

data Fx = Fx { fa :: A, fph :: Phase, fdel :: Bool, fdl :: Int }

-- | The creation deadline one second after now, and exactly now, so both
-- sides of G3's "now >= deadline" are pinned. Every asset gets both,
-- because only an assembly in progress may expire.
deadlines :: [Int]
deadlines = [envNow env + 1, envNow env]

-- | CLIENT.md round 2, the File refinement: a goal still assembling under
-- Idle, Reading or Writing has adopted its staging area, so an assembly
-- with nothing adopted only meets Opening.
adoptedWhereNeeded :: A -> Phase -> Bool
adoptedWhereNeeded AAsmNone p = case p of { Opening _ -> True; _ -> False }
adoptedWhereNeeded _ _        = True

files :: [Fx]
files = [ Fx a p d dl | a <- assets, p <- phases, allowed (goalOf a) p, adoptedWhereNeeded a p, d <- [False, True], dl <- deadlines ]

toFile :: Fx -> File
toFile (Fx a p d dl) =
  File (Meta (FileId fid) (UploadId "up-1") dl created) (toAsset a) (Client (Known 13) True p d) theEpoch

-- Requests -----------------------------------------------------------------------

evId :: Int
evId = 9

noConds :: Conditions
noConds = Conditions Absent Absent Absent Absent Absent Absent False

-- | Every combination a DELETE's preconditions can take relative to the
-- file: If-Match absent, *, the tag, another tag, the tag weakly;
-- If-Unmodified-Since absent, before and at the creation; If-None-Match
-- the same five; If-Modified-Since absent or before (which a GET would
-- answer 304); and Range absent, alone, or with a date If-Range.
deleteConds :: [Conditions]
deleteConds =
  [ Conditions im inm ius ims rng ir False
  | im  <- tagFields
  , inm <- tagFields
  , ius <- [Absent, Present (created - 1), Present created]
  , ims <- [Absent, Present (created - 1)]
  , (rng, ir) <- [(Absent, Absent), (Present someRange, Absent), (Present someRange, Present RangeDate)] ]
  where
    tagFields = [Absent, Present Star, Present (Listed [theTag]), Present (Listed [otherTag]), Present (Listed [weakTag])]

someRange :: RangeSpec
someRange = IntRange 0 4

-- | The request shapes, each with the name of its kind.
requests :: [Event]
requests =
  [ CancelOperation evId, GetOperation evId, DeleteOperation evId, GetObject evId, GetAccessUrl evId ]
  ++ [ GetContent evId c | c <- getConds ]
  ++ [ DeleteFile evId c | c <- deleteConds ]

getConds :: [Conditions]
getConds =
  [ noConds
  , Conditions (Present (Listed [otherTag])) Absent Absent Absent Absent Absent False
  , Conditions Absent (Present Star) Absent (Present 1) (Present someRange) (Present (RangeTag theTag)) True ]

run :: Env -> Event -> File -> Out
run e ev@(CancelOperation _) = cancelOperation e ev
run e ev@(GetOperation _)    = getOperation e ev
run e ev@(DeleteOperation _) = deleteOperation e ev
run e ev@(GetObject _)       = getObject e ev
run e ev@(GetAccessUrl _)    = getAccessUrl e ev
run e ev@(GetContent _ _)    = getContent e ev
run e ev@(DeleteFile _ _)    = deleteFile e ev
run _ _                      = error "not a slice 2 request"

-- What the rulings say -------------------------------------------------------------

data Expect = Expect
  { xEv    :: Reply
  , xOwed  :: Maybe Settle   -- ^ what the owed request gets, if the step settles it
  , xEnds  :: Maybe Ending   -- ^ the ending, if the step clears the goal
  , xForgets :: Bool         -- ^ whether the step sets opDeleted
  }

unchanged :: Reply -> Expect
unchanged x = Expect x Nothing Nothing False

data Standing' = SActive | SCreating | SCleared deriving Eq

standing :: A -> Standing'
standing (AClear _ _) = SCleared
standing AActive      = SActive
standing _            = SCreating

owes :: Phase -> Bool
owes p = case p of
  Opening (Present _)    -> True
  Reading _ _            -> True
  Writing (Present _) _ _ -> True
  Sealing (Present _)    -> True
  _                      -> False

-- | What the owed request is told when a cancel clears the goal under it:
-- the ending's refusal with UC ?1, which for a cancel is Gone.
cancelledWith :: Phase -> Maybe Settle
cancelledWith p = if owes p then Just (Answer (Refuse Gone (Present True))) else Nothing

-- | What the owed request is told when a DELETE clears the goal of an
-- ACTIVE file. Only a completing request held in Sealing can be owed
-- there, and its receipt came first, so it gets F1's reply: 201 with
-- Location (the file) and the ETag, UC ?1. kernel.md's watch table says
-- the same: "a receipt appears" answers it before "the goal is cleared".
deletedWith :: Phase -> Maybe Settle
deletedWith p = if owes p then Just (Answer (CreatedFile (FileId fid) theTag)) else Nothing

-- | G3: "In phases Opening and Receiving, if now >= deadline, row X1 runs
-- before anything else". Opening and Receiving are the client phases of
-- a goal still assembling, the same test CLIENT.md gives the Tick's expiry.
pastDeadline :: Fx -> Bool
pastDeadline fx = goalOf (fa fx) == 2 && envNow env >= fdl fx

-- | X1, then the request's cell in the END column. X1 makes the file FAILED
-- Expired and abandons "the held request or the slot's request, if any";
-- the cell then sees a cleared file whose operation is FAILED Expired.
expect :: Fx -> Event -> Expect
expect fx ev
  | pastDeadline fx = x1 (cell SCleared (OpFailed Expired) fx ev)
  | otherwise       = cell (standing (fa fx)) (op (fa fx)) fx ev
  where
    x1 x = x { xEnds = Just (Failed Expired), xOwed = if owes (fph fx) then Just Abandoned else Nothing }

-- | The request's cell, given where the file stands and its operation.
cell :: Standing' -> Op -> Fx -> Event -> Expect
cell st o (Fx _ p d _) ev = case ev of
  -- G4, then Q1 or the cancel of a file still being created.
  CancelOperation _
    | d               -> unchanged (Refuse NotFound Absent)
    | st == SCreating -> Expect CancelAccepted (cancelledWith p) (Just Cancelled) False
    | otherwise       -> unchanged CancelAccepted
  -- G4, then Q2, with the operation transcribed from core.md's mapping.
  GetOperation _
    | d         -> unchanged (Refuse NotFound Absent)
    | otherwise -> unchanged (OperationIs o)
  -- G4, then Q3.
  DeleteOperation _
    | d         -> unchanged (Refuse NotFound Absent)
    | otherwise -> Expect NoContent Nothing Nothing True
  -- R1, R2, R3, and 404 once cleared.
  GetObject _    -> unchanged (drs ObjectIs)
  GetAccessUrl _ -> unchanged (drs AccessIs)
  -- R4, 404 while creating, 410 once cleared.
  GetContent _ cs -> unchanged $ case st of
    SActive   -> Content bound cs
    SCreating -> Refuse NotFound Absent
    SCleared  -> Refuse Gone Absent
  -- R5, 409 while creating, R7 once cleared.
  DeleteFile _ cs -> case st of
    SActive
      | deleteFails cs -> unchanged (Refuse PreconditionFailed Absent)
      | otherwise      -> Expect (Pending Absent Absent False) (deletedWith p) (Just Deleted) False
    SCreating -> unchanged (Refuse OperationInProgress Absent)
    SCleared  -> unchanged (Refuse Gone Absent)
  _ -> error "not a slice 2 request"
  where
    drs ready = case st of
      SActive   -> ready (FileId fid) bound
      SCreating -> Pending Absent (Present (pendingDelay env)) False
      SCleared  -> Refuse NotFound Absent

-- | core.md, "The DRS object and the operation": CREATING is in progress;
-- ACTIVE, DELETING and DELETED are done with the object; FAILED f is
-- failed with f; CANCELLED is cancelled.
op :: A -> Op
op (AClear Deleted _)      = OpSucceeded (FileId fid) bound
op (AClear Cancelled _)    = OpCancelled
op (AClear (Failed f) _)   = OpFailed f
op AActive                 = OpSucceeded (FileId fid) bound
op _                       = OpRunning

-- | RFC 9110 13.2.2 for a DELETE at the origin of a file that exists, with
-- this file's tag and its creation as the last modification. Steps 4 to 6
-- only concern GET and HEAD.
deleteFails :: Conditions -> Bool
deleteFails cs = step1 || step2 || step3
  where
    -- Step 1: If-Match is false. * is true when a representation exists;
    -- otherwise a strong comparison against each listed tag.
    step1 = case cIfMatch cs of
      Present Star        -> False
      Present (Listed ts) -> not (any strong ts)
      Absent            -> False
    -- Step 2: no If-Match, and If-Unmodified-Since is false.
    step2 = case (cIfMatch cs, cIfUnmodSince cs) of
      (Absent, Present dt) -> created > dt
      _                    -> False
    -- Step 3: If-None-Match is false, which for a method other than GET or
    -- HEAD is 412. * is false when a representation exists; otherwise a
    -- weak comparison.
    step3 = case cIfNoneMatch cs of
      Present Star        -> True
      Present (Listed ts) -> any weakly ts
      Absent            -> False
    strong (EntityTag w o) = not w && o == OpaqueTag fid
    weakly (EntityTag _ o) = o == OpaqueTag fid

-- Describing what came back ------------------------------------------------------
--
-- Reply, Refusal, Op and Conditions have no Show or Eq, so each is rendered
-- structurally here and expectations are compared as renderings.

showEnding :: Ending -> String
showEnding Deleted    = "Deleted"
showEnding Cancelled  = "Cancelled"
showEnding (Failed f) = "Failed " ++ show f

showBound :: Bound -> String
showBound b = "receipt " ++ show (boundVersion b) ++ " size " ++ show (boundSize b)

showOp :: Op -> String
showOp OpRunning           = "running"
showOp (OpSucceeded i b)   = "succeeded " ++ show i ++ " " ++ showBound b
showOp (OpFailed f)        = "failed " ++ show f
showOp OpCancelled         = "cancelled"

showRefusal :: Refusal -> String
showRefusal r = case r of
  NotFound -> "NotFound"; MethodNotAllowed -> "MethodNotAllowed"; OffsetMismatch n -> "OffsetMismatch " ++ show n
  AlreadyComplete -> "AlreadyComplete"; OperationInProgress -> "OperationInProgress"; ParentMissing -> "ParentMissing"
  Gone -> "Gone"; PreconditionFailed -> "PreconditionFailed"; MissingOffset -> "MissingOffset"
  InconsistentLength -> "InconsistentLength"; AppendTooSmall l -> "AppendTooSmall " ++ show l
  DigestUnsupported -> "DigestUnsupported"; AppendTooLarge l -> "AppendTooLarge " ++ show l
  ExceedsMaxSize l -> "ExceedsMaxSize " ++ show l; OffsetPastLength -> "OffsetPastLength"
  WrongMediaType -> "WrongMediaType"; RateLimited n -> "RateLimited " ++ show n; Internal -> "Internal"
  DataLoss -> "DataLoss"; NotImplemented -> "NotImplemented"; StoreUnavailable d -> "StoreUnavailable " ++ show d
  InsufficientStorage -> "InsufficientStorage"

showConds :: Conditions -> String
showConds (Conditions im inm ius ims rng ir hd) =
  unwords ["If-Match", show im, "If-None-Match", show inm, "IUS", show ius, "IMS", show ims, "Range", show rng, "If-Range", show ir, "HEAD", show hd]

showReply :: Reply -> String
showReply x = case x of
  CreatedUpload u l n -> "CreatedUpload " ++ show u ++ " " ++ show l ++ " " ++ show n
  CreatedFile i t     -> "CreatedFile " ++ show i ++ " " ++ show t
  AppendAccepted n    -> "AppendAccepted " ++ show n
  OffsetIs c n l m    -> "OffsetIs " ++ show c ++ " " ++ show n ++ " " ++ show l ++ " " ++ show m
  NoContent           -> "NoContent"
  CancelAccepted      -> "CancelAccepted"
  OperationIs o       -> "OperationIs " ++ showOp o
  Pending o d uc      -> "Pending " ++ maybeOpt showOp o ++ " " ++ show d ++ " " ++ show uc
  ObjectIs i b        -> "ObjectIs " ++ show i ++ " " ++ showBound b
  AccessIs i b        -> "AccessIs " ++ show i ++ " " ++ showBound b
  Content b cs        -> "Content " ++ showBound b ++ " " ++ showConds cs
  Refuse r uc         -> "Refuse " ++ showRefusal r ++ " " ++ show uc

maybeOpt :: (a -> String) -> Opt a -> String
maybeOpt _ Absent      = "Absent"
maybeOpt f (Present a) = "Present (" ++ f a ++ ")"

showSettle :: Settle -> String
showSettle (Answer x) = "Answer " ++ showReply x
showSettle Abandoned  = "Abandoned"
showSettle Deferred   = "Deferred"

showReq :: Req -> String
showReq (CreationReq r) = "CreationReq " ++ show r
showReq (AppendReq r)   = "AppendReq " ++ show r

showPhase :: Phase -> String
showPhase p = case p of
  Opening h     -> "Opening " ++ maybeOpt (\(Hold r c u) -> unwords ["Hold", show r, show c, show u]) h
  Idle          -> "Idle"
  Reading q u   -> "Reading " ++ showReq q ++ " " ++ show u
  Writing q n u -> "Writing " ++ maybeOpt showReq q ++ " " ++ show n ++ " " ++ show u
  Sealing w     -> "Sealing " ++ maybeOpt (\(Waiter r t) -> unwords ["Waiter", show r, show t]) w
  Settled       -> "Settled"

showGoal :: Goal -> String
showGoal Clear                  = "Clear"
showGoal (Keep (Assembling r c)) = "Assembling " ++ show r ++ " at " ++ show (offsetOf c)
showGoal (Keep (Assembled r c))  = "Assembled " ++ show r ++ " at " ++ show (offsetOf c)

showOutcome :: Outcome -> String
showOutcome Ongoing   = "Ongoing"
showOutcome (Ended e) = "Ended " ++ showEnding e

showVouch :: Vouch -> String
showVouch NoReceipt      = "no receipt"
showVouch (HasReceipt b) = showBound b

-- | Everything a step could change about a file, as one line.
showFile :: File -> String
showFile (File (Meta i u dl c) (Asset g o _ v b st w) (Client l open ph d) e) =
  unwords [ show i, show u, show dl, show c, "|", showGoal g, "|", showOutcome o, "|", showVouch v
          , "| budget", show b, show st, "writes", show (length w)
          , "|", show l, "open", show open, "|", showPhase ph, "| opDeleted", show d, "| epoch", show e ]

-- Checking --------------------------------------------------------------------------

jobRuns :: Phase -> Bool
jobRuns p = case p of { Reading _ _ -> True; Writing _ _ _ -> True; _ -> False }

-- | The file a step should leave behind, built from the fixture rather than
-- from the step's output.
expectedAfter :: Fx -> Expect -> File
expectedAfter fx x = case (xEnds x, xForgets x) of
  (Just e, forgets) -> File m (Asset Clear (Ended e) sn v b st w) (Client l open Settled (d || forgets)) (theEpoch + 1)
  (Nothing, True) -> File m a (Client l open ph True) theEpoch
  (Nothing, False) -> f
  where
    f@(File m a@(Asset _ _ sn v b st w) (Client l open ph d) _) = toFile fx

check :: (Env -> Event -> File -> Out) -> Fx -> Event -> [String]
check step fx ev =
  [ "evTo: got " ++ maybeOpt showSettle (evTo o) ++ ", want " ++ want | maybeOpt showSettle (evTo o) /= want ]
  ++ [ "owedTo: got " ++ maybeOpt showSettle (owedTo o) ++ ", want " ++ wantOwed | maybeOpt showSettle (owedTo o) /= wantOwed ]
  ++ [ "stopped: got " ++ show (stopped o) ++ ", want " ++ show wantStop | stopped o /= wantStop ]
  ++ [ "a job was started" | isPresent (started o) ]
  ++ [ "timers were asked for: " ++ show (timers o) | not (null (timers o)) ]
  ++ [ "an alert was raised" | isPresent (alert o) ]
  ++ [ "after: got  " ++ showFile (after o) ++ "\n         want " ++ showFile wantFile | showFile (after o) /= showFile wantFile ]
  where
    o        = step env ev (toFile fx)
    x        = expect fx ev
    want     = "Present (" ++ showSettle (Answer (xEv x)) ++ ")"
    wantOwed = maybe "Absent" (\s -> "Present (" ++ showSettle s ++ ")") (xOwed x)
    wantStop = if isPresentM (xEnds x) && jobRuns (fph fx) then Present theEpoch else Absent
    wantFile = expectedAfter fx x

isPresentM :: Maybe a -> Bool
isPresentM = maybe False (const True)

kindOf :: Event -> String
kindOf e = case e of
  CancelOperation _ -> "CancelOperation"; GetOperation _ -> "GetOperation"; DeleteOperation _ -> "DeleteOperation"
  GetObject _ -> "GetObject"; GetAccessUrl _ -> "GetAccessUrl"
  GetContent _ c -> "GetContent " ++ showConds c; DeleteFile _ c -> "DeleteFile " ++ showConds c
  _ -> "?"

main :: IO ()
main = do
  t0 <- newTally
  (t, n) <- suite t0 run
  putStrLn ("Slice 2 replies and effects: " ++ show (length files) ++ " files x " ++ show (length requests)
            ++ " requests = " ++ show t ++ " steps checked, " ++ show n ++ " wrong")
  unless (n == 0) exitFailure

-- | Every case above through the step it is given: this slice's entry
-- points for this suite, the dispatcher for test/Dispatch.hs. Returns how
-- many steps ran and how many were wrong.
suite :: Tally -> (Env -> Event -> File -> Out) -> IO (Int, Int)
suite tally step = do
  bad <- newIORef (0 :: Int)
  total' <- newIORef (0 :: Int)
  mapM_ (\(fx, ev) -> do
          modifyIORef' total' (+ 1)
          record tally ev
          let errs = check step fx ev
          unless (null errs) $ do
            modifyIORef' bad (+ 1)
            n <- readIORef bad
            unless (n > 20) $ do
              putStrLn (kindOf ev ++ " on " ++ show (fa fx) ++ ", " ++ showPhase (fph fx) ++ ", opDeleted " ++ show (fdel fx)
                        ++ ", deadline " ++ show (fdl fx))
              mapM_ (putStrLn . ("  " ++)) errs)
        [ (fx, ev) | fx <- files, ev <- requests ]
  n <- readIORef bad
  t <- readIORef total'
  return (t, n)
