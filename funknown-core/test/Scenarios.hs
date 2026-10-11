-- | Composed sequences through 'stepClient' that no single slice suite runs,
-- and single steps on states the slice suites' domains never reach. Every
-- expectation is transcribed from CLIENT.md (round 2 overriding) and core.md,
-- on test-side values; the module is only called to run the step.
--
-- The second integration verifier wrote this suite. Two of its steps wait
-- on rulings CLIENT.md doesn't give, so they are left out here and listed
-- in INTEGRATION.md's open questions: whether KernelMoved over an adopted
-- Opening runs G3 (CLIENT.md slice 3 lists KernelMoved's rows without a
-- deadline, and they aren't core.md rows), and whether F9's DELETE gets
-- core.md's 202 or the 204 A11 and B15 give once the cancel is enacted.
module Main (main) where

import Control.Monad (unless)
import Data.IORef
import System.Exit (exitFailure)

import Funknown.Opt
import Funknown.Fault (Fault (..))
import Funknown.Refusal (Refusal (..))
import Funknown.Http.Retry (Backoff (..))
import Funknown.Kernel.Bound (Bound, Version (..), bind)
import Funknown.Kernel.Types (Asset (..), Goal (..), Assembly (..), Ending (..), Outcome (..), Seen (..), Vouch (..), Write (..), StagingRef (..), Config (..))
import Funknown.Store.Algorithm (ReceiptAlgorithm (..), checksumOf)
import Funknown.Store.Receipt (receiptReport)
import Funknown.Upload (Limits (..), Chunk (..), ChunkToken (..), Chunks, emptyChunks, appendChunk, offsetOf)
import Funknown.Client.Types
import Funknown.Client.Create (CreateUpload (..), CreationBody (..), Opened (..), create)
import Funknown.Client.Step (stepClient)

-- Fixtures --------------------------------------------------------------------

lim :: Limits
lim = Limits 4 10 3 25 False

maxAge, wdl :: Int
maxAge = 1000   -- deadline = 0 + 1000
wdl = 60

envAt :: Int -> Env
envAt t = Env t 1000 30 5 (Config 3 (Backoff 1 30 2) wdl)

ref :: StagingRef
ref = StagingRef "s1"

patch :: Int -> Int -> Bool -> Int -> Patch
patch r off uc n = Patch r (Present off) (Present uc) Absent (Present n) True False

chunksOf :: [Int] -> Chunks
chunksOf = foldl (\c (i, n) -> appendChunk c (Chunk n (ChunkToken ("t" ++ show i)))) (emptyChunks lim) . zip [(1 :: Int) ..]

boundFor :: Int -> Bound
boundFor n = case checksumOf 7 of
  Present c -> case receiptReport Crc64Nvme c n of
    Present r -> case bind n (Version "v1") r of
      Right b -> b
      Left _  -> error "bind"
    Absent -> error "report"
  Absent -> error "checksum"

-- | The kernel's own moves, as the kernel would make them (test side).
adopt :: File -> File
adopt (File m (Asset (Keep (Assembling Absent c)) o s v b st w) cl e) = File m (Asset (Keep (Assembling (Present ref) c)) o s v b st w) cl e
adopt _ = error "adopt"

kernelClears :: Fault -> File -> File
kernelClears x (File m (Asset _ _ s v b st w) cl e) = File m (Asset Clear (Ended (Failed x)) s v b st w) cl e

-- Rendering ---------------------------------------------------------------------

settleS :: Settle -> String
settleS (Answer r) = replyS r
settleS Abandoned  = "Abandoned"
settleS Deferred   = "Deferred"

replyS :: Reply -> String
replyS r = case r of
  CreatedUpload (UploadId u) _ n -> "CreatedUpload " ++ u ++ " " ++ show n
  CreatedFile (FileId f) _       -> "CreatedFile " ++ f
  AppendAccepted n               -> "AppendAccepted " ++ show n
  OffsetIs uc n l _              -> "OffsetIs " ++ show uc ++ " " ++ show n ++ " " ++ show l
  NoContent                      -> "NoContent"
  CancelAccepted                 -> "CancelAccepted"
  OperationIs _                  -> "OperationIs"
  Pending o _ uc                 -> "Pending " ++ (case o of { Present (OpSucceeded _ _) -> "done"; Present OpRunning -> "running"; Present _ -> "ended"; Absent -> "-" }) ++ " " ++ show uc
  ObjectIs {}                    -> "ObjectIs"
  AccessIs {}                    -> "AccessIs"
  Content {}                     -> "Content"
  Refuse x uc                    -> "Refuse " ++ refusalS x ++ (if uc == Present True then " ?1" else "")

refusalS :: Refusal -> String
refusalS x = case x of
  NotFound -> "NotFound"; Gone -> "Gone"; OffsetMismatch n -> "OffsetMismatch " ++ show n
  AlreadyComplete -> "AlreadyComplete"; InsufficientStorage -> "InsufficientStorage"
  StoreUnavailable _ -> "StoreUnavailable"; OperationInProgress -> "OperationInProgress"
  _ -> "other"

phaseS :: Phase -> String
phaseS ph = case ph of
  Opening h      -> "Opening" ++ (case h of { Present _ -> " hold"; Absent -> "" })
  Idle           -> "Idle"
  Reading q uc   -> "Reading " ++ reqS q ++ " " ++ show uc
  Writing q n uc -> "Writing " ++ (case q of { Present x -> reqS x; Absent -> "-" }) ++ " " ++ show n ++ " " ++ show uc
  Sealing w      -> "Sealing" ++ (case w of { Present (Waiter r t) -> " " ++ show r ++ "@" ++ show t; Absent -> "" })
  Settled        -> "Settled"
  where reqS (AppendReq r) = "append " ++ show r
        reqS (CreationReq r) = "create " ++ show r

goalS :: Asset -> String
goalS a = case (goal a, outcome a) of
  (Keep (Assembling r c), _) -> "Assembling " ++ (case r of { Present _ -> "s1 "; Absent -> "- " }) ++ show (offsetOf c)
  (Keep (Assembled _ c), _)  -> "Assembled " ++ show (offsetOf c)
  (Clear, Ended Deleted)     -> "Clear Deleted"
  (Clear, Ended Cancelled)   -> "Clear Cancelled"
  (Clear, Ended (Failed f))  -> "Clear " ++ show f
  (Clear, Ongoing)           -> "Clear ?"

-- | What a step did, as one comparable record.
data Obs = Obs { oEv :: String, oOwed :: String, oPhase :: String, oGoal :: String
               , oStart :: String, oStop :: String, oWrites :: [Int] }
  deriving (Eq, Show)

observe :: Out -> Obs
observe (Out (File _ a c _) ow ev st sr _ _) =
  Obs (opt settleS ev) (opt settleS ow) (phaseS (phase c)) (goalS a)
      (opt startS sr) (opt show st) [ e | Write e _ <- authorised a ]
  where
    opt :: (x -> String) -> Opt x -> String
    opt f (Present x) = f x
    opt _ Absent      = "-"
    startS (StartRead e n) = "Read " ++ show e ++ " " ++ show n
    startS (StartPersist e1 e2 _ k) = "Persist " ++ show e1 ++ " " ++ show e2 ++ " " ++ show k

-- Running ------------------------------------------------------------------------

type Check = String -> Obs -> Out -> IO File

mkCheck :: IORef Int -> Check
mkCheck bad what want o = do
  let got = observe o
  if got == want
    then putStrLn ("ok    " ++ what)
    else do
      modifyIORef' bad (+ 1)
      putStrLn ("FAIL  " ++ what ++ "\n      want " ++ show want ++ "\n      got  " ++ show got)
  return (after o)

-- | A file built from creation, with the kernel's adoption applied.
created :: File
created = case create (envAt 0) lim maxAge (CreateUpload 1 (FileId "f1") (UploadId "u1") False Absent Bodiless False False 7) of
  Right (Opened f _) -> f
  Left _ -> error "creation refused"

main :: IO ()
main = do
  bad <- newIORef (0 :: Int)
  let chk = mkCheck bad
      t0 = envAt 10

  ----------------------------------------------------------------------------
  putStrLn "A. create, adopt, append, cancel while writing, late write report, KernelMoved"
  f1 <- chk "KernelMoved after adoption: O1, 201 with offset 0, Idle"
          (Obs "-" "CreatedUpload u1 0" "Idle" "Assembling s1 0" "-" "-" [])
          (stepClient t0 KernelMoved (adopt created))
  f2 <- chk "Append r2 10 bytes: A9 reads under e+1 with min maxChunk (maxSize - 0)"
          (Obs "-" "-" "Reading append 2 False" "Assembling s1 0" "Read 1 10" "-" [])
          (stepClient t0 (Append (patch 2 0 False 10)) f1)
  f3 <- chk "BodyReceived 1 10: B3 persists as job 2, authorised gets epoch 2"
          (Obs "-" "-" "Writing append 2 10 False" "Assembling s1 0" "Persist 1 2 1" "-" [2])
          (stepClient t0 (BodyReceived 1 10) f2)
  f4 <- chk "CancelUpload r3: B15, Cancelled, r2 abandoned, 204, write stopped, entry kept"
          (Obs "NoContent" "Abandoned" "Settled" "Clear Cancelled" "-" "2" [2])
          (stepClient t0 (CancelUpload 3) f3)
  f5 <- chk "late ChunkPersisted 2: stale, stops 2, removes its own entry"
          (Obs "-" "-" "Settled" "Clear Cancelled" "-" "2" [])
          (stepClient t0 (ChunkPersisted 2 (Chunk 10 (ChunkToken "k"))) f4)
  _ <- chk "KernelMoved after: nothing to settle"
          (Obs "-" "-" "Settled" "Clear Cancelled" "-" "-" [])
          (stepClient t0 KernelMoved f5)

  putStrLn "A2. the same with CancelOperation"
  g4 <- chk "CancelOperation r3 while writing: owed r2 told Gone ?1, 200"
          (Obs "CancelAccepted" "Refuse Gone ?1" "Settled" "Clear Cancelled" "-" "2" [2])
          (stepClient t0 (CancelOperation 3) f3)
  _ <- chk "late ChunkFailed 2: stale, removes its own entry"
          (Obs "-" "-" "Settled" "Clear Cancelled" "-" "2" [])
          (stepClient t0 (ChunkFailed 2) g4)

  putStrLn "A3. the kernel clears the goal while writing"
  h4 <- chk "KernelMoved over a cleared goal: owed r2 told the ending's refusal ?1, writer stopped"
          (Obs "-" "Refuse StoreUnavailable ?1" "Settled" "Clear Unavailable" "-" "2" [2])
          (stepClient t0 KernelMoved (kernelClears Unavailable f3))
  _ <- chk "late ChunkPersisted 2 removes the entry"
          (Obs "-" "-" "Settled" "Clear Unavailable" "-" "2" [])
          (stepClient t0 (ChunkPersisted 2 (Chunk 10 (ChunkToken "k"))) h4)

  putStrLn "A4. B2 then the write's report"
  i4 <- chk "Append r3 while writing: B2, r2 abandoned, r3 deferred"
          (Obs "Deferred" "Abandoned" "Writing - 10 False" "Assembling s1 0" "-" "-" [2])
          (stepClient t0 (Append (patch 3 0 False 10)) f3)
  i5 <- chk "ChunkPersisted 2: B10 with no request, Idle at 10"
          (Obs "-" "-" "Idle" "Assembling s1 10" "-" "-" [])
          (stepClient t0 (ChunkPersisted 2 (Chunk 10 (ChunkToken "k"))) i4)
  _ <- chk "r3 re-delivered: A2, OffsetMismatch 10"
          (Obs "Refuse OffsetMismatch 10" "-" "Idle" "Assembling s1 10" "-" "-" [])
          (stepClient t0 (Append (patch 3 0 False 10)) i5)

  ----------------------------------------------------------------------------
  -- G3 (core.md guards; CLIENT.md round 2 "Expiry is a guard on requests
  -- too"): past the deadline on a goal still assembling, X1 runs first
  -- (FAILED Expired, owed request abandoned, mover stopped), and the request
  -- is then answered by the END column: 410 for every upload-resource request.
  putStrLn "B. G3 on upload-resource requests"
  let late = envAt 1000
  _ <- chk "Idle, Append past the deadline: X1, then 410"
          (Obs "Refuse Gone" "-" "Settled" "Clear Expired" "-" "-" [])
          (stepClient late (Append (patch 4 0 False 10)) f1)
  _ <- chk "Idle, OffsetQuery past the deadline: X1, then 410"
          (Obs "Refuse Gone" "-" "Settled" "Clear Expired" "-" "-" [])
          (stepClient late (OffsetQuery 4) f1)
  _ <- chk "Reading, Append past the deadline: X1 (r2 abandoned, reader 1 stopped), then 410"
          (Obs "Refuse Gone" "Abandoned" "Settled" "Clear Expired" "-" "1" [])
          (stepClient late (Append (patch 4 0 False 10)) f2)
  _ <- chk "Writing, OffsetQuery past the deadline: X1 (r2 abandoned, writer 2 stopped), then 410"
          (Obs "Refuse Gone" "Abandoned" "Settled" "Clear Expired" "-" "2" [2])
          (stepClient late (OffsetQuery 4) f3)
  _ <- chk "Requests' own G3 for comparison: GetOperation in Idle past the deadline"
          (Obs "OperationIs" "-" "Settled" "Clear Expired" "-" "-" [])
          (stepClient late (GetOperation 4) f1)

  ----------------------------------------------------------------------------
  -- G3 runs before any cell in Opening and Receiving, reports included
  -- (core.md "Guards, in order, before any cell"; only G2 comes before it).
  putStrLn "C. G3 on a current report, and what follows"
  w1 <- chk "Append r2 UC ?1 with 3 bytes (before the deadline)"
          (Obs "-" "-" "Reading append 2 True" "Assembling s1 0" "Read 1 10" "-" [])
          (stepClient t0 (Append (patch 2 0 True 3)) f1)
  w2 <- chk "BodyReceived 1 3: B3"
          (Obs "-" "-" "Writing append 2 3 True" "Assembling s1 0" "Persist 1 2 1" "-" [2])
          (stepClient t0 (BodyReceived 1 3) w1)
  w3 <- chk "ChunkPersisted 2 past the deadline: X1 first (r2 abandoned, StopMover 2 as X1 in PER), not B11"
          (Obs "-" "Abandoned" "Settled" "Clear Expired" "-" "2" [])
          (stepClient late (ChunkPersisted 2 (Chunk 3 (ChunkToken "k"))) w2)
  _ <- chk "Tick past the deadline afterwards"
          (Obs "-" "-" "Settled" "Clear Expired" "-" "-" [])
          (stepClient late Tick w3)

  ----------------------------------------------------------------------------
  -- CLIENT.md slice 1, Sealing: "If a receipt is already held, treat the
  -- file as ACTIVE." ACTIVE's rows are V1 (replay F1's 201, unchanged) and V3
  -- (204 with the offset, unchanged). A held completing request whose receipt
  -- already came is owed F1's 201 (kernel.md's watch table), which is what
  -- Requests' DeleteFile gives it.
  putStrLn "D. Sealing with a receipt already held"
  let sealedWithReceipt =
        File (Meta (FileId "f1") (UploadId "u1") 1000 7)
             (Asset (Keep (Assembled ref (chunksOf [10, 3]))) Ongoing Unseen (HasReceipt (boundFor 13)) 3 1 [])
             (Client (Known 13) True (Sealing (Present (Waiter 1 500))) False) 3
  _ <- chk "empty UC ?1 PATCH at offset 13: V1, replay 201, held request untouched"
          (Obs "CreatedFile f1" "-" "Sealing 1@500" "Assembled 13" "-" "-" [])
          (stepClient t0 (Append (patch 9 13 True 0)) sealedWithReceipt)
  _ <- chk "OffsetQuery: V3, 204 with the offset, held request untouched"
          (Obs "OffsetIs True 13 Known 13" "-" "Sealing 1@500" "Assembled 13" "-" "-" [])
          (stepClient t0 (OffsetQuery 9) sealedWithReceipt)
  _ <- chk "Requests' DeleteFile on the same file, for comparison: held request gets its 201"
          (Obs "Pending - False" "CreatedFile f1" "Settled" "Clear Deleted" "-" "-" [])
          (stepClient t0 (DeleteFile 9 (Conditions Absent Absent Absent Absent Absent Absent False)) sealedWithReceipt)

  ----------------------------------------------------------------------------
  putStrLn "E. G3 in Opening"
  let opening = adopt created
  _ <- chk "Opening, Append past the deadline: X1 (held creation request abandoned), then 410"
          (Obs "Refuse Gone" "Abandoned" "Settled" "Clear Expired" "-" "-" [])
          (stepClient late (Append (patch 4 0 False 10)) opening)

  ----------------------------------------------------------------------------
  putStrLn "D2. T2's 202, then the receipt, then the client asks again"
  let sealing = File (Meta (FileId "f1") (UploadId "u1") 1000 7)
                     (Asset (Keep (Assembled ref (chunksOf [10, 3]))) Ongoing Unseen NoReceipt 3 1 [])
                     (Client (Known 13) True (Sealing (Present (Waiter 1 40))) False) 3
      vouched (File m (Asset g o s _ b st w) c e) = File m (Asset g o s (HasReceipt (boundFor 13)) b st w) c e
  s1 <- chk "Tick at 40: T2, 202"
          (Obs "-" "Pending running True" "Sealing" "Assembled 13" "-" "-" [])
          (stepClient (envAt 40) Tick sealing)
  s2 <- chk "receipt appears; KernelMoved has nobody to answer"
          (Obs "-" "-" "Sealing" "Assembled 13" "-" "-" [])
          (stepClient (envAt 41) KernelMoved (vouched s1))
  _ <- chk "the client's empty UC ?1 PATCH: the file is ACTIVE, so V1 replays 201"
          (Obs "CreatedFile f1" "-" "Sealing" "Assembled 13" "-" "-" [])
          (stepClient (envAt 42) (Append (patch 9 13 True 0)) s2)

  n <- readIORef bad
  putStrLn (show n ++ " scenario steps differ from the rulings")
  unless (n == 0) exitFailure
