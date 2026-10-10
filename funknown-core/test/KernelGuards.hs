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
module Main (main) where

import Control.Monad (unless, when)
import Data.IORef
import System.Exit (exitFailure)

import Funknown.Opt
import Funknown.Fault (Fault (..))
import Funknown.Http.Retry (Backoff (..))
import Funknown.Kernel.Bound
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

main :: IO ()
main = do
  bad <- newIORef (0 :: Int)
  let fails msg = modifyIORef' bad (+ 1) >> putStrLn msg
  mapM_ (\p -> do
          let gs = guards p
              d  = reconcile env (asset p)
          case gs of
            [r] -> when (row d /= r) $ fails ("row " ++ show (row d) ++ " taken where the table says " ++ show r ++ ": " ++ show p)
            []  -> fails ("no guard holds: " ++ show p)
            _   -> fails ("guards overlap " ++ show gs ++ ": " ++ show p)) domain
  n <- readIORef bad
  putStrLn ("K7 guards exhaustive, exclusive and followed: " ++ show (length domain) ++ " points checked, " ++ show n ++ " failed")
  unless (n == 0) exitFailure
