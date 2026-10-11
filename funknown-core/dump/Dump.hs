-- | Differential dump: runs the proved Haskell kernel on a fixed set of
-- inputs and writes each input with the Haskell result as one JSON line, so
-- the TypeScript port can be fed the same inputs and compared.
--
-- Three kinds of record:
--
-- * "step": one call of 'reconcile'. The whole domain of test/Guards.hs
--   (1320 points), then one step per generated asset below.
-- * "round": one call of 'round' (decide, perform against the store model,
--   observe) on a Coherent pair. Generated pairs, each followed for up to
--   five rounds, every round its own record.
-- * "converge": one call of 'converge' on a generated pair, drop allowance
--   and script of adversary moves.
--
-- Generation is a splitmix64 stream over a fixed seed, so the dump is the
-- same on every run. Only base is used; the JSON is written by hand.
module Main (main) where

import Prelude hiding (round)

import Data.Bits (shiftR, xor)
import Data.List (intercalate)
import Data.Word (Word64)

import Funknown.Opt
import Funknown.Fault (Fault (..))
import Funknown.Http.Retry (Backoff (..))
import Funknown.Kernel.Bound
import Funknown.Kernel.Converge (Move (..), Run (..), converge)
import Funknown.Kernel.Model (Model (..), Round (..), round)
import Funknown.Kernel.Reconcile (reconcile)
import Funknown.Kernel.Types
import Funknown.Store.Algorithm (ReceiptAlgorithm (..), checksumOf, checksumValue)
import qualified Funknown.Store.Receipt as R
import Funknown.Upload

-- JSON, by hand ------------------------------------------------------------------

str :: String -> String
str s = "\"" ++ concatMap esc s ++ "\""
  where esc '"' = "\\\""
        esc '\\' = "\\\\"
        esc c | fromEnum c < 0x20 = "\\u00" ++ [hex (fromEnum c `div` 16), hex (fromEnum c `mod` 16)]
              | otherwise = [c]
        hex n = "0123456789abcdef" !! n

obj :: [(String, String)] -> String
obj kvs = "{" ++ intercalate "," [str k ++ ":" ++ v | (k, v) <- kvs] ++ "}"

arr :: [String] -> String
arr xs = "[" ++ intercalate "," xs ++ "]"

int :: Int -> String
int = show

bool :: Bool -> String
bool True = "true"
bool False = "false"

tag :: String -> [(String, String)] -> String
tag t kvs = obj (("t", str t) : kvs)

-- Encoders -------------------------------------------------------------------------

refS :: StagingRef -> String
refS (StagingRef r) = str r

verS :: Version -> String
verS (Version v) = str v

tokS :: ChunkToken -> String
tokS (ChunkToken t) = str t

encLimits :: Limits -> String
encLimits (Limits a b c d e) = arr [int a, int b, int c, int d, bool e]

-- Chunks newest first, as chunkList gives them.
encChunks :: Chunks -> String
encChunks c = obj [("limits", encLimits (limitsOf c)), ("list", arr [arr [int n, tokS t] | Chunk n t <- chunkList c])]

encGoal :: Goal -> String
encGoal Clear = tag "Clear" []
encGoal (Keep (Assembling o c)) =
  tag "Assembling" [("staging", case o of { Absent -> "null"; Present r -> refS r }), ("chunks", encChunks c)]
encGoal (Keep (Assembled r c)) = tag "Assembled" [("staging", refS r), ("chunks", encChunks c)]

encFault :: Fault -> String
encFault (SourceAnswered n) = tag "SourceAnswered" [("status", int n)]
encFault f = tag (show f) []

encEnding :: Ending -> String
encEnding Deleted = tag "Deleted" []
encEnding Cancelled = tag "Cancelled" []
encEnding (Failed f) = tag "Failed" [("fault", encFault f)]

encOutcome :: Outcome -> String
encOutcome Ongoing = "null"
encOutcome (Ended e) = encEnding e

encVouching :: Vouching -> String
encVouching (Vouched r) =
  tag "Vouched" [("checksum", str (show (checksumValue (R.reportChecksum r)))), ("size", int (R.reportSize r))]
encVouching Unvouchable = tag "Unvouchable" []
encVouching NotYetVouched = tag "NotYetVouched" []

encObj :: ObjectObs -> String
encObj NoObject = "null"
encObj (HasObject v vc) = obj [("version", verS v), ("vouching", encVouching vc)]

stagingList :: Stagings -> [Staging]
stagingList SNil = []
stagingList (SCons s ss) = s : stagingList ss

encObserved :: Observed -> String
encObserved (Observed ss o) =
  obj [ ("stagings", arr [obj [("ref", refS r), ("tokens", arr (map tokS ts))] | Staging r ts <- stagingList ss])
      , ("object", encObj o) ]

encSeen :: Seen -> String
encSeen Unseen = "null"
encSeen (Seen o) = encObserved o

encVouch :: Vouch -> String
encVouch NoReceipt = "null"
encVouch (HasReceipt b) =
  obj [ ("version", verS (boundVersion b)), ("size", int (boundSize b))
      , ("checksum", str (show (checksumValue (R.checksum (boundReceipt b))))) ]

encAsset :: Asset -> String
encAsset (Asset g o s v b st w) =
  obj [ ("goal", encGoal g), ("outcome", encOutcome o), ("seen", encSeen s), ("vouch", encVouch v)
      , ("budget", int b), ("backoffAt", int st), ("authorised", arr [arr [int e, int dl] | Write e dl <- w]) ]

encCmd :: Cmd -> String
encCmd NoCmd = tag "NoCmd" []
encCmd DoObserve = tag "DoObserve" []
encCmd DoOpen = tag "DoOpen" []
encCmd DoSeal = tag "DoSeal" []
encCmd (DoDiscard r) = tag "DoDiscard" [("ref", refS r)]
encCmd (DoRemove v) = tag "DoRemove" [("version", verS v)]

encDecision :: Decision -> String
encDecision (Decision n c w al r) =
  obj [("next", encAsset n), ("command", encCmd c), ("waitFor", int w), ("alarm", bool al), ("row", str (show r))]

encEnv :: Env -> String
encEnv (Env t (Config ma (Backoff i x k) wd)) =
  obj [("now", int t), ("maxAttempts", int ma), ("backoff", arr [int i, int x, int k]), ("writeDeadline", int wd)]

encModel :: Model -> String
encModel (Model o fr v vc) = obj [("obs", encObserved o), ("fresh", refS fr), ("version", verS v), ("vouching", encVouching vc)]

encMove :: Move -> String
encMove Drop = tag "Drop" []
encMove LateWrite = tag "LateWrite" []
encMove Lapse = tag "Lapse" []
encMove (Append t n) = tag "Append" [("token", tokS t), ("n", int n)]
encMove Complete = tag "Complete" []
encMove (Abandon e) = tag "Abandon" [("ending", encEnding e)]

-- Building values through the real producers -----------------------------------------

report :: Integer -> Int -> R.ReceiptReport
report cs n = case checksumOf cs of
  Present c -> case R.receiptReport Crc64Nvme c n of
    Present r -> r
    Absent -> error "report size"
  Absent -> error "checksum"

boundAt :: Integer -> Int -> Version -> Bound
boundAt cs n v = case bind n v (report cs n) of
  Right b -> b
  Left _ -> error "bind"

-- The guard domain, exactly as test/Guards.hs builds it ----------------------------

gLim :: Limits
gLim = Limits 1 10 4 100 False

gChunks :: Chunks
gChunks = appendChunk (appendChunk (emptyChunks gLim) (Chunk 10 (ChunkToken "t1"))) (Chunk 3 (ChunkToken "t2"))

cur, oth, oth2 :: StagingRef
cur = StagingRef "current"
oth = StagingRef "orphan"
oth2 = StagingRef "orphan2"

v1, v2 :: Version
v1 = Version "v1"
v2 = Version "v2"

data G = GClear | GAsmNone | GAsmCur | GDone deriving (Eq, Show, Enum, Bounded)
data St = SFull | SPart | SOther | SOther2 deriving (Eq, Show)
data Ob = ONone | OOk1 | OOk2 | OBad1 | OUnv1 | ONyv1 deriving (Eq, Show, Enum, Bounded)

stagingLists :: [[St]]
stagingLists = [[], [SFull], [SPart], [SOther], [SFull, SOther], [SOther, SFull], [SPart, SOther], [SOther, SPart], [SOther, SOther2]]

toStaging :: St -> Staging
toStaging SFull = Staging cur [ChunkToken "t1", ChunkToken "t2"]
toStaging SPart = Staging cur [ChunkToken "t1"]
toStaging SOther = Staging oth []
toStaging SOther2 = Staging oth2 []

toStagings :: [St] -> Stagings
toStagings = foldr (SCons . toStaging) SNil

toObj :: Ob -> ObjectObs
toObj ONone = NoObject
toObj OOk1 = HasObject v1 (Vouched (report 7 13))
toObj OOk2 = HasObject v2 (Vouched (report 7 13))
toObj OBad1 = HasObject v1 (Vouched (report 7 12))
toObj OUnv1 = HasObject v1 Unvouchable
toObj ONyv1 = HasObject v1 NotYetVouched

toGoal :: G -> Goal
toGoal GClear = Clear
toGoal GAsmNone = Keep (Assembling Absent gChunks)
toGoal GAsmCur = Keep (Assembling (Present cur) gChunks)
toGoal GDone = Keep (Assembled cur gChunks)

guardAssets :: [Asset]
guardAssets =
  [ Asset (toGoal g) (if g == GClear then Ended (Failed Unavailable) else Ongoing)
          (maybe Unseen (\(ss, o) -> Seen (Observed (toStagings ss) (toObj o))) sn)
          (if rc then HasReceipt (boundAt 7 13 v1) else NoReceipt) b 1
          (if pw then [Write 1 200] else [])
  | g <- [minBound .. maxBound]
  , rc <- [False, True], not rc || g == GDone || g == GClear
  , sn <- Nothing : [Just (ss, o) | ss <- stagingLists, o <- [minBound .. maxBound]]
  , b <- [0, 1]
  , pw <- [False, True] ]

guardEnv :: Env
guardEnv = Env 100 (Config 3 (Backoff 1 30 2) 60)

-- A deterministic generator (splitmix64) --------------------------------------------

newtype Gen a = Gen (Word64 -> (a, Word64))

instance Functor Gen where
  fmap f (Gen g) = Gen (\s -> let (a, s') = g s in (f a, s'))
instance Applicative Gen where
  pure a = Gen (\s -> (a, s))
  Gen f <*> Gen g = Gen (\s -> let (h, s1) = f s; (a, s2) = g s1 in (h a, s2))
instance Monad Gen where
  Gen g >>= k = Gen (\s -> let (a, s1) = g s; Gen g' = k a in g' s1)

runGen :: Word64 -> Gen a -> a
runGen seed (Gen g) = fst (g seed)

next64 :: Gen Word64
next64 = Gen (\s -> let s' = s + 0x9e3779b97f4a7c15
                        z1 = (s' `xor` (s' `shiftR` 30)) * 0xbf58476d1ce4e5b9
                        z2 = (z1 `xor` (z1 `shiftR` 27)) * 0x94d049bb133111eb
                    in (z2 `xor` (z2 `shiftR` 31), s'))

range :: Int -> Int -> Gen Int
range lo hi = do
  w <- next64
  pure (lo + fromIntegral (w `mod` fromIntegral (hi - lo + 1)))

oneOf :: [a] -> Gen a
oneOf xs = (xs !!) <$> range 0 (length xs - 1)

chance :: Int -> Gen Bool
chance pct = (< pct) <$> range 0 99

listOf :: Int -> Int -> Gen a -> Gen [a]
listOf lo hi g = do
  n <- range lo hi
  mapM (const g) [1 .. n]

-- Generated inputs ----------------------------------------------------------------------

genLimits :: Gen Limits
genLimits = oneOf [Limits 1 10 4 100 False, Limits 2 5 3 12 True, Limits 1 3 6 20 False, Limits 4 4 2 8 False, Limits 1 1 1 1 False]

-- Appends up to k chunks, each only when canAppend allows it (appendChunk's
-- precondition, which nothing checks at run time once LH is off).
genChunks :: Gen Chunks
genChunks = do
  lim <- genLimits
  k <- range 0 (maxChunks lim)
  let go c i | i > k = pure c
             | otherwise = do
                 n <- range 1 (maxChunk lim)
                 let c' = if canAppend c n then appendChunk c (Chunk n (ChunkToken ("t" ++ show i))) else c
                 go c' (i + 1)
  go (emptyChunks lim) 1

refPool :: [StagingRef]
refPool = [cur, oth, oth2, StagingRef "fresh"]

verPool :: [Version]
verPool = [v1, v2, Version "v3"]

genFault :: Gen Fault
genFault = oneOf [StateLost, SizeMismatch, ObjectWithoutReceipt, Contradiction, Unavailable, Expired, SourceAnswered 404]

genEnding :: Gen Ending
genEnding = do
  k <- range 0 2
  case k of
    0 -> pure Deleted
    1 -> pure Cancelled
    _ -> Failed <$> genFault

genVouching :: Int -> Gen Vouching
genVouching total' = do
  k <- range 0 3
  cs <- oneOf [0, 7, 18446744073709551615]
  sz <- oneOf [total', total', total' + 1, max 0 (total' - 1), 0]
  case k of
    0 -> pure Unvouchable
    1 -> pure NotYetVouched
    _ -> pure (Vouched (report cs sz))

genGoal :: Gen Goal
genGoal = do
  c <- genChunks
  k <- range 0 3
  r <- oneOf [cur, cur, cur, oth]
  case k of
    0 -> pure Clear
    1 -> pure (Keep (Assembling Absent c))
    2 -> pure (Keep (Assembling (Present r) c))
    _ -> pure (Keep (Assembled r c))

goalTotal :: Goal -> Int
goalTotal (Keep (Assembling _ c)) = offsetOf c
goalTotal (Keep (Assembled _ c)) = offsetOf c
goalTotal Clear = 13

goalTokens :: Goal -> [ChunkToken]
goalTokens (Keep (Assembling _ c)) = map ctoken (chunkList c)
goalTokens (Keep (Assembled _ c)) = map ctoken (chunkList c)
goalTokens Clear = [ChunkToken "t1"]

-- A staging area: the goal's own chunks (all, some or none), or none at all.
genStaging :: Goal -> Gen Staging
genStaging g = do
  r <- oneOf refPool
  let toks = goalTokens g
  keep <- mapM (\t -> (\b -> (t, b)) <$> chance 80) toks
  extra <- chance 10
  pure (Staging r ([t | (t, True) <- keep] ++ [ChunkToken "late" | extra]))

genObserved :: Goal -> Gen Observed
genObserved g = do
  ss <- listOf 0 3 (genStaging g)
  hasObj <- chance 45
  o <- if hasObj then HasObject <$> oneOf verPool <*> genVouching (goalTotal g) else pure NoObject
  pure (Observed (foldr SCons SNil ss) o)

genVouch :: Goal -> Gen Vouch
genVouch g = case g of
  Keep (Assembling _ _) -> pure NoReceipt
  _ -> do
    has <- chance 50
    v <- oneOf verPool
    cs <- oneOf [0, 7, 18446744073709551615]
    sz <- case g of
      Keep (Assembled _ c) -> pure (offsetOf c)
      _ -> range 0 30
    pure (if has then HasReceipt (boundAt cs sz v) else NoReceipt)

genEnv :: Gen Env
genEnv = do
  t <- range 0 200
  ma <- range 1 5
  bo <- oneOf [Backoff 1 30 2, Backoff 3 3 1, Backoff 2 1000 3, Backoff 5 2147483648 2147483648, Backoff 1 2147483648 1]
  wd <- range 0 100
  pure (Env t (Config ma bo wd))

-- An asset and a model it is Coherent with: the asset either hasn't observed
-- the store, or observed exactly what the model holds.
genPair :: Gen (Asset, Model)
genPair = do
  g <- genGoal
  obs <- genObserved g
  fresh <- oneOf [StagingRef "fresh", StagingRef "fresh2", cur]
  ver <- oneOf verPool
  vc <- genVouching (goalTotal g)
  let m = Model obs fresh ver vc
  unseen <- chance 30
  o <- case g of
    Clear -> Ended <$> genEnding
    _ -> pure Ongoing
  v <- genVouch g
  b <- range 0 5
  st <- oneOf [1, 1, 2, 3, 5, 9, 33, 64]
  ws <- listOf 0 3 (Write <$> range 0 9 <*> range 50 300)
  pure (Asset g o (if unseen then Unseen else Seen obs) v b st ws, m)

genMove :: Gen Move
genMove = do
  k <- range 0 7
  case k of
    0 -> pure Drop
    1 -> pure LateWrite
    2 -> pure Lapse
    3 -> Append <$> (ChunkToken . ("a" ++) . show <$> range 0 99) <*> range (-1) 12
    4 -> Append <$> (ChunkToken . ("a" ++) . show <$> range 0 99) <*> range 1 4
    5 -> pure Complete
    6 -> Abandon <$> genEnding
    _ -> pure Drop

-- Records -----------------------------------------------------------------------------

stepRec :: String -> Env -> Asset -> String
stepRec src e a = obj [("kind", str "step"), ("src", str src), ("env", encEnv e), ("asset", encAsset a), ("out", encDecision (reconcile e a))]

roundRec :: Env -> Asset -> Model -> Round -> String
roundRec e a m r =
  obj [ ("kind", str "round"), ("env", encEnv e), ("asset", encAsset a), ("model", encModel m)
      , ("out", obj [("asset", encAsset (rAsset r)), ("model", encModel (rModel r)), ("row", str (show (rRow r)))]) ]

-- Up to n rounds from a pair, each its own record; stops after a resting row.
rounds :: Int -> Env -> Asset -> Model -> [String]
rounds 0 _ _ _ = []
rounds n e a m =
  let r = round e a m
  in roundRec e a m r : (if isFixedRow (rRow r) then [] else rounds (n - 1) e (rAsset r) (rModel r))

convergeRec :: Env -> Asset -> Model -> Int -> [Move] -> String
convergeRec e a m d ms =
  let Run a' m' r = converge e a m d ms
  in obj [ ("kind", str "converge"), ("env", encEnv e), ("asset", encAsset a), ("model", encModel m)
         , ("allowance", int d), ("moves", arr (map encMove ms))
         , ("out", obj [("asset", encAsset a'), ("model", encModel m'), ("row", str (show r))]) ]

main :: IO ()
main = do
  mapM_ (putStrLn . stepRec "guards" guardEnv) guardAssets
  let pairs = runGen 20261010 (mapM (const ((,) <$> genEnv <*> genPair)) [1 .. 1500 :: Int])
  mapM_ (\(e, (a, _)) -> putStrLn (stepRec "generated" e a)) pairs
  mapM_ (\(e, (a, m)) -> mapM_ putStrLn (rounds 5 e a m)) pairs
  let runs = runGen 4242 (mapM (const ((,,,) <$> genEnv <*> genPair <*> range 0 4 <*> listOf 0 30 genMove)) [1 .. 1500 :: Int])
  mapM_ (\(e, (a, m), d, ms) -> putStrLn (convergeRec e a m d ms)) runs
