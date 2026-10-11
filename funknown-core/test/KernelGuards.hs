-- | K7: the guards of the decision table in docs/design/kernel.md are
-- exhaustive and pairwise exclusive, and 'reconcile' takes the row whose
-- guard holds. The guards below are transcribed from the table, written
-- apart from Funknown.Kernel.Reconcile, and checked over every shape an
-- observation can take relative to the asset: which staging areas are listed
-- (the current one holding every chunk, the current one missing a chunk, and
-- others, in either order), what object is there (vouched with the right or
-- wrong size, at the receipt's version or another, unvouchable, not yet
-- vouched), budget, and writes still unreported. Nothing is sampled: each
-- dimension is the full set of cases the table distinguishes.
--
-- It also checks the one input claim LiquidHaskell can't state about a single
-- asset: the reconciler never reads why an asset is going away. The ending's
-- faults include names for a call's result (SourceUnreachable,
-- StoreRefusedUs, ...), so this is what keeps those out of every decision.
--
-- And it ties the store actions that Funknown.Kernel.Inputs proves every
-- observation is reached by to the store model the convergence proofs use:
-- for every small model, goal and command, replaying 'modelEvents' gives
-- exactly what 'perform' gives.
module Main (main) where

import Control.Monad (unless, when)
import Data.IORef
import System.Exit (exitFailure)

import Funknown.Opt
import Funknown.Fault (Fault (..))
import Funknown.Http.Retry (Backoff (..))
import Funknown.Kernel.Bound
import Funknown.Kernel.Inputs (modelEvents, replayOn)
import Funknown.Kernel.Model (Model (..), perform)
import Funknown.Kernel.Reconcile (reconcile)
import Funknown.Kernel.Types
import Funknown.Store.Algorithm (ReceiptAlgorithm (..), checksumOf)
import Funknown.Store.Receipt (ReceiptReport, receiptReport)
import Funknown.Upload

lim :: Limits
lim = Limits 1 10 4 100 False

theChunks :: Chunks
theChunks = appendChunk (appendChunk (emptyChunks lim) (Chunk 10 (ChunkToken "t1"))) (Chunk 3 (ChunkToken "t2"))

total' :: Int
total' = 13

cur, oth, oth2 :: StagingRef
cur  = StagingRef "current"
oth  = StagingRef "orphan"
oth2 = StagingRef "orphan2"

v1, v2 :: Version
v1 = Version "v1"
v2 = Version "v2"

report :: Int -> ReceiptReport
report n = case checksumOf 7 of
  Present c -> case receiptReport Crc64Nvme c n of
    Present r -> r
    Absent    -> error "size"
  Absent -> error "checksum"

bound :: Bound
bound = case bind total' v1 (report total') of
  Right b -> b
  Left _  -> error "bind"

-- The dimensions -------------------------------------------------------------

data G = GClear | GAsmNone | GAsmCur | GDone deriving (Eq, Show, Enum, Bounded)
data St = SFull | SPart | SOther | SOther2 deriving (Eq, Show)
data Ob = ONone | OOk1 | OOk2 | OBad1 | OUnv1 | ONyv1 deriving (Eq, Show, Enum, Bounded)

stagingLists :: [[St]]
stagingLists = [[], [SFull], [SPart], [SOther], [SFull, SOther], [SOther, SFull], [SPart, SOther], [SOther, SPart], [SOther, SOther2]]

toStaging :: St -> Staging
toStaging SFull   = Staging cur [ChunkToken "t1", ChunkToken "t2"]
toStaging SPart   = Staging cur [ChunkToken "t1"]
toStaging SOther  = Staging oth []
toStaging SOther2 = Staging oth2 []

toStagings :: [St] -> Stagings
toStagings = foldr (SCons . toStaging) SNil

toObj :: Ob -> ObjectObs
toObj ONone = NoObject
toObj OOk1  = HasObject v1 (Vouched (report total'))
toObj OOk2  = HasObject v2 (Vouched (report total'))
toObj OBad1 = HasObject v1 (Vouched (report 12))
toObj OUnv1 = HasObject v1 Unvouchable
toObj ONyv1 = HasObject v1 NotYetVouched

toGoal :: G -> Goal
toGoal GClear   = Clear
toGoal GAsmNone = Keep (Assembling Absent theChunks)
toGoal GAsmCur  = Keep (Assembling (Present cur) theChunks)
toGoal GDone    = Keep (Assembled cur theChunks)

-- | One point of the domain. Receipts only exist for an assembled or cleared
-- goal, as the Asset refinement requires.
data P = P { pg :: G, prc :: Bool, pseen :: Maybe ([St], Ob), pbudget :: Int, ppending :: Bool }
  deriving Show

domain :: [P]
domain =
  [ P g rc sn b pw
  | g <- [minBound .. maxBound]
  , rc <- [False, True], not rc || g == GDone || g == GClear
  , sn <- Nothing : [Just (ss, o) | ss <- stagingLists, o <- [minBound .. maxBound]]
  , b <- [0, 1]
  , pw <- [False, True] ]

asset :: P -> Asset
asset (P g rc sn b pw) =
  Asset (toGoal g) (if g == GClear then Ended (Failed Unavailable) else Ongoing)
        (maybe Unseen (\(ss, o) -> Seen (Observed (toStagings ss) (toObj o))) sn)
        (if rc then HasReceipt bound else NoReceipt) b 1
        (if pw then [Write 1 200] else [])

env :: Env
env = Env 100 (Config 3 (Backoff 1 30 2) 60)

-- The table's guards, transcribed ----------------------------------------------

guards :: P -> [Row]
guards (P g rc sn _ pw) = case sn of
  Nothing -> [R0]
  Just (ss, o) ->
    let listedCur = any (`elem` [SFull, SPart]) ss
        heldC     = SFull `elem` ss
        others    = any (`elem` [SOther, SOther2]) ss
        anyStg    = not (null ss)
        noObj     = o == ONone
        objAtV1   = o `elem` [OOk1, OBad1, OUnv1, ONyv1]
        asm       = g == GAsmNone || g == GAsmCur
        rows =
          [ R1  | g == GAsmNone, not rc, not anyStg, noObj ] ++
          [ R2  | g == GAsmNone, not rc, anyStg, noObj ] ++
          [ R3  | g == GAsmCur, not rc, listedCur, not others, noObj ] ++
          [ R4  | (g == GAsmCur && listedCur) || (g == GDone && heldC), not rc, others, noObj ] ++
          [ R5  | g == GAsmCur, not rc, not listedCur, noObj ] ++
          [ R6  | asm, not rc, not noObj ] ++
          [ R7  | g == GDone, not rc, heldC, not others, noObj ] ++
          [ R8  | g == GDone, not rc, not heldC, noObj ] ++
          [ R9  | g == GDone, not rc, o `elem` [OOk1, OOk2] ] ++
          [ R10 | g == GDone, not rc, o == OBad1 ] ++
          [ R11 | g == GDone, not rc, o == OUnv1 ] ++
          [ R12 | g == GDone, not rc, o == ONyv1 ] ++
          [ R13 | g == GDone, rc, objAtV1, anyStg ] ++
          [ R14 | g == GDone, rc, objAtV1, not anyStg ] ++
          [ R15 | g == GDone, rc, not objAtV1 ] ++
          [ R16 | g == GClear, anyStg ] ++
          [ R17 | g == GClear, not anyStg, not noObj ] ++
          [ R18 | g == GClear, not anyStg, noObj, not pw ] ++
          [ R19 | g == GClear, not anyStg, noObj, pw ]
    in rows

-- The ending is never read --------------------------------------------------------

-- | Every fault, so the check below can't miss one: 'faultIndex' is total
-- under -Werror=incomplete-patterns, and main checks that this list hits
-- every index.
allFaults :: [Fault]
allFaults =
  [ Expired, FinalizeTimedOut, OutOfRange, TooLarge, QuotaAtFinalize, Revoked, Empty
  , CreationRefused, CreationInterrupted, StateLost, SizeMismatch, ObjectWithoutReceipt
  , StoreRefusedUs, Contradiction, Unavailable, SourceUnreachable, SourceAnswered 503
  , SourceAnswered 404, SourceChanged ]

faultIndex :: Fault -> Int
faultIndex Expired              = 0
faultIndex FinalizeTimedOut     = 1
faultIndex OutOfRange           = 2
faultIndex TooLarge             = 3
faultIndex QuotaAtFinalize      = 4
faultIndex Revoked              = 5
faultIndex Empty                = 6
faultIndex CreationRefused      = 7
faultIndex CreationInterrupted  = 8
faultIndex StateLost            = 9
faultIndex SizeMismatch         = 10
faultIndex ObjectWithoutReceipt = 11
faultIndex StoreRefusedUs       = 12
faultIndex Contradiction        = 13
faultIndex Unavailable          = 14
faultIndex SourceUnreachable    = 15
faultIndex (SourceAnswered _)   = 16
faultIndex SourceChanged        = 17

endings :: [Ending]
endings = Deleted : Cancelled : map Failed allFaults

endingS :: Ending -> String
endingS Deleted    = "Deleted"
endingS Cancelled  = "Cancelled"
endingS (Failed f) = "Failed " ++ show f

outcomeS :: Outcome -> String
outcomeS Ongoing   = "Ongoing"
outcomeS (Ended e) = endingS e

withEnding :: Ending -> Asset -> Asset
withEnding e (Asset g _ s v b st w) = Asset g (Ended e) s v b st w

cmdS :: Cmd -> String
cmdS NoCmd         = "none"
cmdS DoObserve     = "observe"
cmdS DoOpen        = "open"
cmdS DoSeal        = "seal"
cmdS (DoDiscard r) = "discard " ++ show r
cmdS (DoRemove v)  = "remove " ++ show v

stagingsS :: Stagings -> String
stagingsS SNil                        = "."
stagingsS (SCons (Staging r ts) rest) = show r ++ show ts ++ " " ++ stagingsS rest

objS :: ObjectObs -> String
objS NoObject                    = "none"
objS (HasObject v (Vouched r))   = show v ++ " vouched " ++ show r
objS (HasObject v Unvouchable)   = show v ++ " unvouchable"
objS (HasObject v NotYetVouched) = show v ++ " not yet"

seenS :: Seen -> String
seenS Unseen                = "unseen"
seenS (Seen (Observed ss o)) = stagingsS ss ++ "/" ++ objS o

vouchS :: Vouch -> String
vouchS NoReceipt      = "no receipt"
vouchS (HasReceipt b) = "receipt " ++ show (boundVersion b) ++ " " ++ show (boundSize b)

-- | Everything a decision says, apart from the ending it carries.
fingerprint :: Decision -> String
fingerprint d = case next d of
  Asset g _ s v b st w ->
    unwords [ cmdS (command d), show (waitFor d), show (alarm d), show (row d)
            , show (goalTag g), show (rank g), seenS s, vouchS v, show b, show st
            , show [(e, dl) | Write e dl <- w] ]

main :: IO ()
main = do
  bad <- newIORef (0 :: Int)
  let fails msg = modifyIORef' bad (+ 1) >> putStrLn msg
  unless (all (`elem` map faultIndex allFaults) [0 .. 17]) $ fails "allFaults misses a fault"
  -- The reconciler never reads why an asset is going away: on every cleared
  -- point, each ending gets the same decision, and the ending passes through.
  let cleared = [p | p <- domain, pg p == GClear]
  mapM_ (\p -> do
          let base = fingerprint (reconcile env (asset p))
          mapM_ (\e -> do
                  let d = reconcile env (withEnding e (asset p))
                  when (fingerprint d /= base) $
                    fails ("the ending " ++ endingS e ++ " changed the decision: " ++ show p)
                  when (outcomeS (outcome (next d)) /= endingS e) $
                    fails ("the ending " ++ endingS e ++ " did not pass through: " ++ show p)) endings) cleared
  putStrLn ("Endings never read: " ++ show (length cleared) ++ " cleared points x " ++ show (length endings)
            ++ " endings = " ++ show (length cleared * length endings) ++ " checks")
  -- The store actions are the store model, only finer. Two of the lists
  -- name one staging area twice, as a late write can leave the store.
  let models = [ Model (Observed (toStagings ss) (toObj o)) fr ver vc
               | ss <- stagingLists ++ [[SFull, SPart], [SOther, SFull, SOther]], o <- [minBound .. maxBound]
               , fr <- [StagingRef "fresh", cur]
               , ver <- [v1, v2], vc <- [Vouched (report total'), Unvouchable, NotYetVouched] ]
      goals = [ Clear, Keep (Assembled cur theChunks), Keep (Assembled oth theChunks)
              , Keep (Assembling Absent theChunks), Keep (Assembling (Present cur) theChunks) ]
      cmds = [NoCmd, DoObserve, DoOpen, DoSeal] ++ map DoDiscard [cur, oth, oth2] ++ map DoRemove [v1, v2]
      obsS (Observed ss o) = stagingsS ss ++ "/" ++ objS o
      ties = [(m, g, c) | m <- models, g <- goals, c <- cmds]
  mapM_ (\(m, g, c) ->
          let byEvents = obsS (replayOn (modelEvents g c m) (mObs m))
              byModel  = obsS (mObs (perform g c m))
          in when (byEvents /= byModel) $
               fails ("store actions and model differ on " ++ cmdS c ++ " from " ++ obsS (mObs m)
                      ++ ": " ++ byEvents ++ " vs " ++ byModel)) ties
  putStrLn ("Store actions match the store model: " ++ show (length ties) ++ " model, goal and command triples checked")
  mapM_ (\p -> do
          let gs = guards p
              d  = reconcile env (asset p)
          case gs of
            [r] -> when (row d /= r) $ fails ("row " ++ show (row d) ++ " taken where the table says " ++ show r ++ ": " ++ show p)
            []  -> fails ("no guard holds: " ++ show p)
            _   -> fails ("guards overlap " ++ show gs ++ ": " ++ show p)) domain
  n <- readIORef bad
  putStrLn ("K7 guards exhaustive, exclusive and followed: " ++ show (length domain) ++ " points checked; "
            ++ show n ++ " checks failed across the suite")
  unless (n == 0) exitFailure
