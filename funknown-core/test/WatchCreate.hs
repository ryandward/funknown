-- | Which reply a client gets, and whether the asset moved, for slice 3 of
-- CLIENT.md: 'KernelMoved' and 'Tick' in every phase, and creation. The
-- step contract in Funknown.Client.Contract proves that every owed request
-- is settled or kept, but not which reply settles it, and it lets any step
-- make any move the kernel's adversary could. This test closes that for the
-- rows here: the expected outcome of each point is transcribed from
-- CLIENT.md (slice 3) and core.md (O1, O2, F1, T2, X1, C3 to C7), written
-- apart from Funknown.Client.Watch and Funknown.Client.Create.
--
-- Nothing is sampled. The domain is every phase, every request shape a
-- phase can hold, every goal a phase can meet, with and without a receipt
-- and an unreported write, and the clock before, at and after each instant
-- a Tick compares with. Creation runs over every combination of the fields
-- C3 to C6a read, each at the values either side of every bound.
--
-- Every input an answer reads has a value of its own in the fixtures, so a
-- row that reads the wrong one gives a different answer: the waiter's
-- instant isn't the deadline, one set of limits has max-size above a chunk
-- and the other below it, and the creation stamp isn't the clock.
module WatchCreate (main, suite) where

import Control.Monad (unless)
import Data.IORef
import System.Exit (exitFailure)

import Funknown.Opt
import Funknown.Fault (Fault (..))
import Funknown.Http.Retry (Backoff (..))
import Funknown.Http.Validator (EntityTag (..), OpaqueTag (..))
import Funknown.Kernel.Bound (Bound, Version (..), bind)
import Funknown.Kernel.Types (Asset (..), Goal (..), Assembly (..), Ending (..), Outcome (..), Seen (..), Vouch (..), Write (..), StagingRef (..), Config (..))
import Funknown.Refusal (Refusal (..))
import Funknown.Store.Algorithm (ReceiptAlgorithm (..), checksumOf)
import Funknown.Store.Receipt (ReceiptReport, receiptReport)
import Funknown.Upload (Limits (..), Chunk (..), ChunkToken (..), Chunks, emptyChunks, appendChunk, offsetOf, nChunks, limitsOf)
import Funknown.Client.Types
import Funknown.Client.Watch (kernelMoved, tick)
import Funknown.Client.Create
import Tally (Tally, newTally, record)

-- Fixtures ---------------------------------------------------------------------

-- | O2's read cap is min maxChunk (maxSize - offset), and offset is 0 there,
-- so each set of limits makes a different one of the two bounds bind. The
-- third can seal zero chunks, which is what lets an empty UC ?1 creation
-- complete on adoption (CLIENT.md round 2).
lim, tight, sealing :: Limits
lim     = Limits 2 4 3 10 False
tight   = Limits 2 6 3 4 False
sealing = Limits 2 4 3 10 True

lims :: [Limits]
lims = [lim, tight, sealing]

stg :: StagingRef
stg = StagingRef "s1"

none, four :: Limits -> Chunks
none l = emptyChunks l
four l = appendChunk (none l) (Chunk 4 (ChunkToken "t1"))

report :: Int -> ReceiptReport
report n = case checksumOf 7 of
  Present c -> case receiptReport Crc64Nvme c n of
    Present r -> r
    Absent    -> error "size"
  Absent -> error "checksum"

bound :: Bound
bound = case bind 4 (Version "v1") (report 4) of
  Right b -> b
  Left _  -> error "bind"

fid :: FileId
fid = FileId "f1"

uid :: UploadId
uid = UploadId "u1"

req, ep, waitBy, dl, stamp :: Int
req    = 7
ep     = 3
waitBy = 40
dl     = 50
stamp  = 1000

envAt :: Int -> Env
envAt t = Env t 100 20 5 (Config 3 (Backoff 1 30 2) 60)

-- The domain -----------------------------------------------------------------------

data G = GNone | GAdopted | GAppended | GDone | GDoneVouched | GClear Ending

goals :: [G]
goals = [GNone, GAdopted, GAppended, GDone, GDoneVouched]
     ++ map GClear [Deleted, Cancelled, Failed Expired, Failed StateLost, Failed SizeMismatch, Failed Unavailable
                   , Failed FinalizeTimedOut, Failed QuotaAtFinalize, Failed Contradiction, Failed CreationRefused]

toGoal :: Limits -> G -> Goal
toGoal l GNone        = Keep (Assembling Absent (none l))
toGoal l GAdopted     = Keep (Assembling (Present stg) (none l))
toGoal l GAppended    = Keep (Assembling (Present stg) (four l))
toGoal l GDone        = Keep (Assembled stg (four l))
toGoal l GDoneVouched = Keep (Assembled stg (four l))
toGoal _ (GClear _)   = Clear

phases :: [Phase]
phases =
  [Opening Absent] ++ [Opening (Present (Hold req b u)) | b <- bools, u <- bools] ++ [Idle]
  ++ [Reading q u | q <- [CreationReq req, AppendReq req], u <- bools]
  ++ [Writing q 4 u | q <- [Absent, Present (CreationReq req), Present (AppendReq req)], u <- bools]
  ++ [Sealing Absent, Sealing (Present (Waiter req waitBy)), Settled]
  where bools = [False, True]

-- | The shapes the client side can actually meet, transcribed from the
-- comment on fitsGoal in Client/Types.hs and from the order of work: a
-- cleared goal meets any phase; an assembly in progress meets the phases
-- before sealing, and the creation request is answered before anything can
-- be appended, so Opening only meets an assembly with no chunks; a completed
-- assembly meets only Sealing and Settled. CLIENT.md round 2 adds the File
-- refinement: under Idle, Reading or Writing an assembly in progress has
-- adopted its staging area.
meets :: G -> Phase -> Bool
meets (GClear _) _ = True
meets g ph = case ph of
  Opening _     -> g == GNone || g == GAdopted
  Idle          -> adopted
  Reading _ _   -> adopted
  Writing _ _ _ -> adopted
  Sealing _     -> done
  Settled       -> done
  where adopted = g == GAdopted || g == GAppended
        done    = g == GDone || g == GDoneVouched

instance Eq G where
  a == b = gName a == gName b

gName :: G -> String
gName GNone        = "assembling, nothing adopted"
gName GAdopted     = "assembling into s1, no chunks"
gName GAppended    = "assembling into s1, 4 bytes"
gName GDone        = "assembled"
gName GDoneVouched = "assembled, receipt"
gName (GClear e)   = "clear, " ++ showEnding e

mkFile :: Limits -> G -> Phase -> Bool -> File
mkFile l g ph w =
  File (Meta fid uid dl stamp)
       (Asset (toGoal l g) (case g of { GClear e -> Ended e; _ -> Ongoing }) Unseen
              (case g of { GDoneVouched -> HasReceipt bound; _ -> NoReceipt }) 3 1
              (if w then [Write ep 99] else []))
       (Client Unknown True ph False)
       ep

-- What a step did, as text -------------------------------------------------------

data Obs = Obs
  { owed :: String, evd :: String, stop :: String, start :: String, phaseAfter :: String
  , epochAfter :: Int, goalAfter :: String, writesAfter :: Int, timersAfter :: [Int], lenAfter :: String }
  deriving (Eq, Show)

observe :: Out -> Obs
observe (Out (File _ a c e) o v s st ts _) =
  Obs (optS showSettle o) (optS showSettle v) (optS show s) (optS showStart st) (showPhase (phase c)) e
      (showGoalOf a) (length (authorised a)) ts (showLen (clientLen c))

-- | What a step that changes nothing looks like.
unchanged :: File -> Obs
unchanged (File _ a c e) = Obs "-" "-" "-" "-" (showPhase (phase c)) e (showGoalOf a) (length (authorised a)) [] (showLen (clientLen c))

-- Expected outcomes, transcribed -------------------------------------------------------

-- | CLIENT.md slice 3, KernelMoved, with round 2's rows.
expectKM :: Limits -> G -> Phase -> File -> Obs
expectKM l g ph f = case (g, ph) of
  -- the goal is Clear: every unsettled phase settles (round 2: that includes
  -- Opening and Sealing with nothing held), the owed request told the
  -- ending's refusal with UC ?1, the job stopped
  (GClear e, _) | settles ph -> clearedSettles e ph f
  -- round 2, an empty creation that completes: UC ?1, no content, and
  -- sealsEmpty, so the goal completes on adoption as B4 does (the length is
  -- the offset, 0) and the request waits as a Waiter until now + replyWait,
  -- with a Tick at that instant
  (GAdopted, Opening (Present (Hold r False True))) | r == req && sealsEmpty l ->
    base { phaseAfter = showPhase (Sealing (Present (Waiter req (0 + 20))))
         , goalAfter = "Assembled s1 0", timersAfter = [0 + 20], lenAfter = showLen (Known 0) }
  -- adopted, no content: CreatedUpload uploadId limits 0, Idle
  (GAdopted, Opening (Present (Hold r False _))) | r == req ->
    base { owed = "answer " ++ showReply (CreatedUpload uid l 0), phaseAfter = "Idle" }
  -- adopted, with content: StartRead (e+1) m, Reading (CreationReq r) uc;
  -- m = min maxChunk (maxSize - offset), at offset 0
  (GAdopted, Opening (Present (Hold r True u))) | r == req ->
    base { start = "read e" ++ show (ep + 1) ++ " max " ++ show (min (maxChunk l) (maxSize l - 0))
         , phaseAfter = showPhase (Reading (CreationReq req) u)
         , epochAfter = ep + 1 }
  -- a receipt appeared: CreatedFile fid etag, settle
  (GDoneVouched, Sealing (Present _)) ->
    base { owed = "answer " ++ showReply (CreatedFile fid (EntityTag False (OpaqueTag "f1"))), phaseAfter = "Settled" }
  _ -> base
  where
    base = unchanged f

-- | Every phase but Settled is unsettled.
settles :: Phase -> Bool
settles Settled = False
settles _       = True

-- | A cleared goal settles the client side (CLIENT.md slice 3, and round 2
-- for Tick): the owed request is told the ending's refusal with UC ?1, a
-- running job is stopped, the phase is Settled under the next epoch, and
-- the asset is left as the kernel left it.
clearedSettles :: Ending -> Phase -> File -> Obs
clearedSettles e ph f =
  (unchanged f) { owed = if owes ph then "answer " ++ showReply (Refuse (endingRefusal e) (Present True)) else "-"
                , stop = if job ph then show ep else "-"
                , phaseAfter = "Settled", epochAfter = ep + 1 }

-- | CLIENT.md slice 3, Tick: T2, then expiry (X1), otherwise stale. Round 2
-- puts a cleared goal first: it settles exactly as KernelMoved would, so a
-- held request gets the ending's refusal, never a 202.
expectTick :: Int -> G -> Phase -> File -> Obs
expectTick t g ph f = case ph of
  _ | GClear e <- g, settles ph -> clearedSettles e ph f
  Sealing (Present (Waiter _ by)) | t >= by ->
    base { owed = "answer " ++ showReply (Pending (Present (expectedOp g)) Absent True), phaseAfter = "Sealing -" }
  _ | assembling g && t >= dl ->
    base { owed = if owes ph then "abandon" else "-", stop = if job ph then show ep else "-"
         , phaseAfter = "Settled", epochAfter = ep + 1, goalAfter = "Clear, " ++ showEnding (Failed Expired) }
  _ -> base
  where
    base = unchanged f
    assembling x = x == GNone || x == GAdopted || x == GAppended

-- | core.md's operation: CREATING is running; ACTIVE (and a deleted file
-- that had been ACTIVE) succeeded; FAILED f failed with f; CANCELLED, and a
-- deleted file that never had a receipt, cancelled.
expectedOp :: G -> Op
expectedOp GDoneVouched              = OpSucceeded fid bound
expectedOp (GClear (Failed x))       = OpFailed x
expectedOp (GClear Cancelled)        = OpCancelled
expectedOp (GClear Deleted)          = OpCancelled
expectedOp _                         = OpRunning

owes :: Phase -> Bool
owes p = case p of
  Opening (Present _)       -> True
  Reading _ _               -> True
  Writing (Present _) _ _   -> True
  Sealing (Present _)       -> True
  _                         -> False

job :: Phase -> Bool
job p = case p of
  Reading _ _   -> True
  Writing _ _ _ -> True
  _             -> False

-- Creation ------------------------------------------------------------------------

data Case = Case Int Limits CreateUpload

cases :: [Case]
cases =
  [ Case q l (CreateUpload req fid uid uc n b dg pm stamp)
  | q  <- [5, 100]
  , l  <- [lim, lim { sealsEmpty = True }]
  , uc <- [False, True]
  , n  <- [Absent, Present 0, Present 1, Present 4, Present 5, Present 10, Present 11]
  , b  <- [Bodiless, BodyOf 1, BodyOf 2, BodyOf 4, BodyOf 5, BodyOf 10, BodyOf 11, BodyUnsized]
  , dg <- [False, True]
  , pm <- [False, True] ]

-- | C3 to C6a of core.md, first match wins, as the table reads. C6a is
-- written as core.md's prose under the table has it: every check A4 and A6
-- would make on the content, at offset 0. A4 refuses length indicators that
-- disagree with each other or with the length: under UC ?1 the content is
-- the whole upload, a request with no content being 0 bytes of it, and
-- under UC ?0 it is a first part, so it can't exceed the declared length.
expectCreate :: Case -> Either String ()
expectCreate (Case q l (CreateUpload _ _ _ uc n b dg pm _)) =
  case [ r | (True, r) <- rows ] of
    (r : _) -> Left (showRefusal r)
    []      -> Right ()
  where
    declared  = case n of { Present v -> Just v; Absent -> Nothing }
    clen      = case b of { BodyOf v -> Just v; _ -> Nothing }
    whole     = case b of { Bodiless -> Just 0; BodyOf v -> Just v; BodyUnsized -> Nothing }
    content   = case b of { Bodiless -> False; _ -> True }
    gt x m    = maybe False (> m) x
    rows =
      [ (gt declared (maxSize l) || gt clen (maxSize l), ExceedsMaxSize l)                  -- C3
      , (pm, ParentMissing)                                                                  -- C3
      , (gt declared q, InsufficientStorage)                                                 -- C4
      , (uc && not content && not (sealsEmpty l), NotImplemented)                            -- C5
      , (dg, DigestUnsupported)                                                              -- C6
      , (uc && maybe False id ((/=) <$> declared <*> whole), InconsistentLength)            -- C6a (A4)
      , (not uc && maybe False id ((>) <$> clen <*> declared), InconsistentLength)          -- C6a (A4)
      , (content && gt clen (maxChunk l), AppendTooLarge l)                                  -- C6a
      , (content && not uc && maybe False (< minChunk l) clen, AppendTooSmall l) ]           -- C6a

-- | C7, and everything CLIENT.md lists for the new file.
checkOpened :: Case -> Opened -> [String]
checkOpened (Case _ l x) (Opened (File m a c e) ts) =
  [ "goal is not Keep (Assembling Absent (emptyChunks limits))"
  | case goal a of { Keep (Assembling Absent ch) -> not (offsetOf ch == 0 && nChunks ch == 0 && limitsOf ch == l); _ -> True } ]
  ++ [ "outcome is not Ongoing" | case outcome a of { Ongoing -> False; _ -> True } ]
  ++ [ "seen is not Unseen" | case seen a of { Unseen -> False; _ -> True } ]
  ++ [ "vouch is not NoReceipt" | case vouch a of { NoReceipt -> False; _ -> True } ]
  ++ [ "budget is not maxAttempts" | budget a /= 3 ]
  ++ [ "backoff step is not 1" | backoffAt a /= 1 ]
  ++ [ "writes were authorised" | not (null (authorised a)) ]
  ++ [ "phase is " ++ showPhase (phase c) | showPhase (phase c) /= showPhase (Opening (Present (Hold (cuReq x) content (cuComplete x)))) ]
  ++ [ "upload resource not open" | not (uploadOpen c) ]
  ++ [ "operation already deleted" | opDeleted c ]
  ++ [ "Upload-Length not recorded" | showLen (clientLen c) /= showLen (case cuLength x of { Present v -> Known v; Absent -> Unknown }) ]
  ++ [ "ids differ" | fileId m /= fid || uploadId m /= uid ]
  ++ [ "createdAt is not the World's stamp" | createdAt m /= stamp ]
  ++ [ "deadline is not now + maxAge" | deadline m /= 100 + 30 ]
  ++ [ "the deadline has no timer" | deadline m `notElem` ts ]
  ++ [ "epoch is not 0" | e /= 0 ]
  where content = case cuBody x of { Bodiless -> False; _ -> True }

-- Rendering ---------------------------------------------------------------------------

optS :: (a -> String) -> Opt a -> String
optS _ Absent      = "-"
optS f (Present x) = f x

showSettle :: Settle -> String
showSettle (Answer r) = "answer " ++ showReply r
showSettle Abandoned  = "abandon"
showSettle Deferred   = "defer"

showStart :: Start -> String
showStart (StartRead e n)        = "read e" ++ show e ++ " max " ++ show n
showStart (StartPersist a b _ k) = "persist e" ++ show a ++ " as e" ++ show b ++ " chunk " ++ show k

showPhase :: Phase -> String
showPhase p = case p of
  Opening h      -> "Opening " ++ optS (\(Hold r b u) -> unwords [show r, show b, show u]) h
  Idle           -> "Idle"
  Reading q u    -> "Reading " ++ showReq q ++ " " ++ show u
  Writing q n u  -> "Writing " ++ optS showReq q ++ " " ++ show n ++ " " ++ show u
  Sealing w      -> "Sealing " ++ optS (\(Waiter r t) -> show r ++ " by " ++ show t) w
  Settled        -> "Settled"

showReq :: Req -> String
showReq (CreationReq r) = "creation " ++ show r
showReq (AppendReq r)   = "append " ++ show r

showGoalOf :: Asset -> String
showGoalOf a = case (goal a, outcome a) of
  (Keep (Assembling s ch), _) -> "Assembling " ++ optS (\(StagingRef x) -> x) s ++ " " ++ show (offsetOf ch) ++ "/" ++ show (nChunks ch)
  (Keep (Assembled (StagingRef x) ch), _) -> "Assembled " ++ x ++ " " ++ show (offsetOf ch)
  (Clear, Ended e) -> "Clear, " ++ showEnding e
  (Clear, Ongoing) -> "Clear, no ending"

showEnding :: Ending -> String
showEnding Deleted    = "deleted"
showEnding Cancelled  = "cancelled"
showEnding (Failed x) = "failed " ++ show x

showLen :: Len -> String
showLen = show

showOp :: Op -> String
showOp OpRunning           = "running"
showOp (OpSucceeded i _)   = "succeeded " ++ show i
showOp (OpFailed x)        = "failed " ++ show x
showOp OpCancelled         = "cancelled"

showReply :: Reply -> String
showReply r = case r of
  CreatedUpload u l n  -> unwords ["CreatedUpload", show u, show l, show n]
  CreatedFile i t      -> unwords ["CreatedFile", show i, show t]
  AppendAccepted n     -> "AppendAccepted " ++ show n
  OffsetIs c n l m     -> unwords ["OffsetIs", show c, show n, show l, show m]
  NoContent            -> "NoContent"
  CancelAccepted       -> "CancelAccepted"
  OperationIs o        -> "OperationIs " ++ showOp o
  Pending o n u        -> unwords ["Pending", optS showOp o, optS show n, show u]
  ObjectIs i _         -> "ObjectIs " ++ show i
  AccessIs i _         -> "AccessIs " ++ show i
  Content _ _          -> "Content"
  Refuse x u           -> unwords ["Refuse", showRefusal x, optS show u]

showRefusal :: Refusal -> String
showRefusal x = case x of
  NotFound              -> "NotFound"
  MethodNotAllowed      -> "MethodNotAllowed"
  OffsetMismatch n      -> "OffsetMismatch " ++ show n
  AlreadyComplete       -> "AlreadyComplete"
  OperationInProgress   -> "OperationInProgress"
  ParentMissing         -> "ParentMissing"
  Gone                  -> "Gone"
  PreconditionFailed    -> "PreconditionFailed"
  MissingOffset         -> "MissingOffset"
  InconsistentLength    -> "InconsistentLength"
  AppendTooSmall l      -> "AppendTooSmall " ++ show l
  DigestUnsupported     -> "DigestUnsupported"
  AppendTooLarge l      -> "AppendTooLarge " ++ show l
  ExceedsMaxSize l      -> "ExceedsMaxSize " ++ show l
  OffsetPastLength      -> "OffsetPastLength"
  WrongMediaType        -> "WrongMediaType"
  RateLimited n         -> "RateLimited " ++ show n
  Internal              -> "Internal"
  DataLoss              -> "DataLoss"
  NotImplemented        -> "NotImplemented"
  StoreUnavailable n    -> "StoreUnavailable " ++ optS show n
  InsufficientStorage   -> "InsufficientStorage"

-- Running ---------------------------------------------------------------------------

-- | The file shapes KernelMoved and Tick are checked over, and the clocks
-- each Tick runs at.
points :: [(Limits, G, Phase, Bool)]
points = [ (l, g, ph, w) | l <- lims, g <- goals, ph <- phases, meets g ph, w <- [False, True] ]

clocks :: [Int]
clocks = [waitBy - 1, waitBy, waitBy + 1, dl - 1, dl, dl + 1]

-- | This slice's two watch handlers, by the event they own.
watchEntry :: Env -> Event -> File -> Out
watchEntry e ev f = case ev of
  KernelMoved -> kernelMoved e ev f
  Tick        -> tick e ev f
  _           -> error "watchEntry: not a watch event"

-- | KernelMoved and Tick over every point, through the step it is given:
-- this slice's handlers for this suite, the dispatcher for
-- test/Dispatch.hs. Returns how many steps ran and how many failed.
suite :: Tally -> (Env -> Event -> File -> Out) -> IO (Int, Int)
suite tally step = do
  bad <- newIORef (0 :: Int)
  count <- newIORef (0 :: Int)
  let check what want got = do
        modifyIORef' count (+ 1)
        unless (want == got) $ do
          modifyIORef' bad (+ 1)
          putStrLn (what ++ "\n  want " ++ show want ++ "\n  got  " ++ show got)
  mapM_ (\(l, g, ph, w) -> do
          let f = mkFile l g ph w
              at = show l ++ " / " ++ gName g ++ " / " ++ showPhase ph ++ (if w then " / a write unreported" else "")
          record tally KernelMoved
          check ("KernelMoved: " ++ at) (expectKM l g ph f) (observe (step (envAt 0) KernelMoved f))
          mapM_ (\t -> do
                  record tally Tick
                  check ("Tick at " ++ show t ++ ": " ++ at) (expectTick t g ph f) (observe (step (envAt t) Tick f))) clocks)
        points
  n <- readIORef bad
  total <- readIORef count
  return (total, n)

main :: IO ()
main = do
  t0 <- newTally
  (_, watchBad) <- suite t0 watchEntry
  bad <- newIORef watchBad
  let check what want got = unless (want == got) $ do
        modifyIORef' bad (+ 1)
        putStrLn (what ++ "\n  want " ++ show want ++ "\n  got  " ++ show got)
  mapM_ (\k@(Case q l x) ->
          let at = unwords ["create quota", show q, "sealsEmpty", show (sealsEmpty l), "UC", show (cuComplete x)
                           , "length", optS show (cuLength x), "body", showBody (cuBody x)
                           , "digest", show (cuDigest x), "parent missing", show (cuParentMissing x)]
          in case (expectCreate k, create ((envAt 100) { quotaRemaining = q }) l 30 x) of
               (Left want, Left (Refuse got Absent)) -> check at want (showRefusal got)
               (Left want, Left got)  -> check at want (showReply got)
               (Left want, Right _)   -> check at want "created"
               (Right (), Left got)   -> check at "created" (showReply got)
               (Right (), Right o)    -> check at [] (checkOpened k o))
        cases
  n <- readIORef bad
  putStrLn ("slice 3: " ++ show (length points) ++ " file shapes under KernelMoved and " ++ show (length clocks * length points)
            ++ " under Tick, " ++ show (length cases) ++ " creation requests; " ++ show n ++ " failed")
  unless (n == 0) exitFailure

showBody :: CreationBody -> String
showBody Bodiless    = "none"
showBody (BodyOf n)  = show n
showBody BodyUnsized = "unsized"
