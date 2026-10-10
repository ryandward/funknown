-- | Exhaustive checks for Http.Range, Http.Admission, Store.Algorithm and
-- Store.Receipt. Admission and Algorithm enumerate their whole finite
-- domains; the Range diff against Go covers every order cell of its inputs
-- (see 'rangeVsGo'); the edge and boundary checks name their points. Each
-- prints how many points it checked, and any failure fails the suite.
module Main (main) where

import Data.Char (isHexDigit, isSpace, toLower)
import Data.List (nub, sort)
import qualified Data.Map.Strict as Map
import Numeric (readHex)
import System.Environment (lookupEnv)
import System.Exit (exitFailure)
import System.IO (IOMode (ReadMode), hGetContents, hSetEncoding, utf8, withFile)

import Funknown.Http.Admission (Access (..), Admit (..), admit)
import Funknown.Http.Range (RangeSpec (..), Resolved (..), resolve, resolveHeader)
import Funknown.Opt (Opt (..))
import Funknown.Store.Algorithm (ReceiptAlgorithm (..), checksumOf, checksumValue, drsType, drsTypeName, width)
import Funknown.Store.Receipt (SizeDiffers (..), receiptReport, reportSize, size, toHex, vouch)
import Port.GoFsRange (GoAnswer (..), serveRange)

-- | A check's name, how many points it enumerated, and what failed.
data Result = Result String Int [String]

report :: Result -> IO Bool
report (Result name n fs) = do
  putStrLn (name ++ ": " ++ show n ++ " points checked, " ++ show (length fs) ++ " failed")
  mapM_ (putStrLn . ("  " ++)) (take 20 fs)
  pure (null fs)

-- Admission ------------------------------------------------------------------

-- | SF1's "unable to see the file", held by GHC: if admit ever took a second
-- argument, this binding would stop compiling.
admitSeesOnlyAccess :: Access -> Admit
admitSeesOnlyAccess = admit

-- | Every Access: 401 for missing or invalid credentials, 403 for
-- inadequate ones, and only Allowed is clear.
admission :: Result
admission = Result "Admission: admit over every Access" (length domain) bad
  where
    domain = [minBound .. maxBound] :: [Access]
    expected NoCredentials      = A401
    expected InvalidCredentials = A401
    expected Insufficient       = A403
    expected Allowed            = Clear
    bad = [ show a ++ " gave " ++ show (admitSeesOnlyAccess a) | a <- domain, admitSeesOnlyAccess a /= expected a ]

-- Algorithm ------------------------------------------------------------------

algorithm :: Result
algorithm = Result "Algorithm: width and DRS type over every ReceiptAlgorithm" (length domain) bad
  where
    domain = [minBound .. maxBound] :: [ReceiptAlgorithm]
    bad = [ show a | a <- domain, width a /= 64 || drsTypeName (drsType a) /= "crc64nvme" ]

-- | The runtime side of the bound the logic sees as a literal: both edges of
-- [0, 2^64), checked where checksumOf really computes them.
checksumEdges :: Result
checksumEdges = Result "Algorithm: checksumOf at both edges of [0, 2^64)" (length cases) bad
  where
    cases = [(-1, False), (0, True), (2 ^ (64 :: Int) - 1, True), (2 ^ (64 :: Int), False)]
    holds v ok = case checksumOf v of
      Present c -> ok && checksumValue c == v
      Absent    -> not ok
    bad = [ show v | (v, ok) <- cases, not (holds v ok) ]

-- | The inputs an adversarial review built from plugin-free code, where the
-- old exported constructors let them past every refinement. They now have to
-- go through the checked producers, and resolve and vouch have no
-- precondition left to break. LiquidHaskell proves these over every value;
-- the points show the compiled code a GHC-only caller links agrees.
boundary :: Result
boundary = Result "Boundary: values a caller without LiquidHaskell can build" (length cases) bad
  where
    zero = case checksumOf 0 of
      Present c -> Present c
      Absent    -> Absent
    reportOf s = case zero of
      Present c -> receiptReport Crc64Nvme c s
      Absent    -> Absent
    cases =
      [ ("resolve 10 (IntRange (-3) 2) is Ignore", resolve 10 (IntRange (-3) 2) == Ignore)
      , ("resolve 10 (OpenRange (-1)) is Ignore", resolve 10 (OpenRange (-1)) == Ignore)
      , ("resolve 10 (Suffix (-1)) is Ignore", resolve 10 (Suffix (-1)) == Ignore)
      , ("resolve (-1) (Suffix 5) is Ignore", resolve (-1) (Suffix 5) == Ignore)
      , ("checksumOf (2^64) is Absent", case checksumOf (2 ^ (64 :: Int)) of { Absent -> True; Present _ -> False })
      , ("checksumOf (-1) is Absent", case checksumOf (-1) of { Absent -> True; Present _ -> False })
      , ("receiptReport with size -5 is Absent", case reportOf (-5) of { Absent -> True; Present _ -> False })
      , ("receiptReport with size 0 is Present with size 0", case reportOf 0 of { Present r -> reportSize r == 0; Absent -> False })
      , ("vouch (-5) on a size-0 report is SizeDiffers (-5) 0", case reportOf 0 of
            Present r -> vouch (-5) r == Left (SizeDiffers (-5) 0)
            Absent    -> False)
      , ("vouch 0 on a size-0 report is a size-0 receipt rendered as 16 zeros", case reportOf 0 of
            Present r -> either (const False) (\rc -> size rc == 0 && toHex rc == replicate 16 '0') (vouch 0 r)
            Absent    -> False)
      ]
    bad = [ name | (name, ok) <- cases, not ok ]

-- | The porting plan's check for Store.Algorithm: the NVMe definition and the
-- RevEng catalogue entry agree on every parameter, and the width is ours.
-- The Check value is left out because PD:REVENG-crc.cat.crc-64-nvme-2 says
-- the NVMe document publishes a wrong one.
crcParameters :: String -> Result
crcParameters json = Result "Algorithm: NVMe and RevEng CRC-64/NVME parameters" (length pairs) bad
  where
    nvme   = words (quoteOf "NVME-NVMCS-1.1-5.3.1.3.4-2" json)
    reveng = [ (k, drop 1 v) | w <- words (quoteOf "REVENG-crc.cat.crc-64-nvme-1" json), let (k, v) = break (== '=') w ]
    after k = case dropWhile (/= k) nvme of
      _ : v : _ -> v
      _         -> "missing " ++ k
    nvmeHex = hexOf . filter (/= '_') . takeWhile (/= 'h') . after
    revHex k = maybe (-1) (hexOf . drop 2) (lookup k reveng)
    revStr k = maybe "missing" id (lookup k reveng)
    pairs =
      [ ("width (ours)", toInteger (width Crc64Nvme), read (after "Width"))
      , ("width", read (after "Width"), maybe (-1) read (lookup "width" reveng))
      , ("poly", nvmeHex "Poly", revHex "poly")
      , ("init", nvmeHex "Init", revHex "init")
      , ("xorout", nvmeHex "XorOut", revHex "xorout")
      , ("refin", boolOf (after "RefIn"), boolOf (revStr "refin"))
      , ("refout", boolOf (after "RefOut"), boolOf (revStr "refout"))
      ]
    -- a value that didn't parse is -1, and two of those must not agree
    bad = [ k ++ ": " ++ show a ++ " vs " ++ show b | (k, a, b) <- pairs, a /= b || a < 0 || b < 0 ]
    hexOf s = case readHex s of
      [(v, "")] | all isHexDigit s -> v
      _ -> -1 :: Integer
    boolOf s = case map toLower s of
      "true"  -> 1
      "false" -> 0
      _       -> -1 :: Integer

-- | The quote of statement @sid@, from statements.json's own layout: an
-- "id" line, then a "quote" line holding one JSON string.
quoteOf :: String -> String -> String
quoteOf sid json =
  case dropWhile (/= ("\"id\": \"" ++ sid ++ "\",")) (map (dropWhile isSpace) (lines json)) of
    [] -> ""
    _ : rest -> case [ l | l <- takeWhile (not . isIdLine) rest, take 9 l == "\"quote\": " ] of
      l : _ -> jsonString (drop 10 l)
      []    -> ""
  where
    isIdLine l = take 6 l == "\"id\": "
    jsonString ('\\' : c : cs) = c : jsonString cs
    jsonString ('"' : _)       = []
    jsonString (c : cs)        = c : jsonString cs
    jsonString []              = []

-- Range against Go ------------------------------------------------------------

-- | Go's answer, in our terms, for a header holding one range-spec. It goes
-- through 'resolveHeader', the entry point the core calls.
ours :: Integer -> RangeSpec -> GoAnswer
ours n s = case resolveHeader (fromInteger n) [s] of
  Satisfied f l   -> Go206 (toInteger f) (toInteger (l - f + 1))
                       ("bytes " ++ show f ++ "-" ++ show l ++ "/" ++ show n)
  Unsatisfiable m -> Go416 (Just ("bytes */" ++ show m))
  Ignore          -> Go200

header :: RangeSpec -> String
header (IntRange f l) = "bytes=" ++ show f ++ "-" ++ show l
header (OpenRange f)  = "bytes=" ++ show f ++ "-"
header (Suffix k)     = "bytes=-" ++ show k

-- | Where we differ from Go on purpose. Each entry names the point set and
-- the sentence that makes us differ.
divergences :: [(String, Integer -> RangeSpec -> Bool)]
divergences =
  [ ( "(a) an invalid int-range (last-pos < first-pos) is ignored, where Go answers 416 \
      \(R HS:RFC9110-14.1.1-2; P HS:RFC9110-14.2-4, PM27)"
    , \n s -> case s of
        IntRange f l -> n > 0 && toInteger l < toInteger f
        _            -> False )
  , ( "(b) a suffix-range on a zero-length representation is ignored, where Go sends a \
      \206 with Content-Range bytes 0--1/0 (P HS:RFC9110-14.2-5, PM27)"
    , \n s -> case s of
        Suffix _ -> n == 0
        _        -> False )
  , ( "(c) a zero suffix-length is 416 with */n, where Go sends a zero-byte 206 with \
      \Content-Range bytes n-(n-1)/n (R HS:RFC9110-14.1.2-5)"
    , \n s -> case s of
        Suffix 0 -> n > 0
        _        -> False )
  ]

-- | The box, and why it is enough. Both functions branch only on order
-- comparisons among 0 and the spec's numbers and n (ours: n <= 0, f < 0,
-- l < f, f < n, l < n, k == 0, k < n; Go's: i >= size, i > j, j >= size,
-- i0 > size, size == 0), and their outputs are affine in those numbers. Go's
-- one other test, sumRangesSize > size, is false for every single range it
-- keeps, because a kept range never runs past size - 1. So on each order
-- cell (one weak ordering of the atoms) each side's answer is one
-- constructor with affine fields, and two affine maps that agree on an
-- affinely spanning set of a cell agree on all of it. 'cellCoverage' checks
-- the box realises every cell with such a set; with the reading above, the
-- diff then covers every non-negative input, not just the box. Negative
-- inputs Go can't express; 'negativePositionIgnored' proves ours.
rangeVsGo :: Result
rangeVsGo = Result "Range: resolveHeader on one range-spec against Go's parseRange, n in 0..10, positions in 0..12" (length box) (bad ++ unhit)
  where
    listed n s = [ name | (name, inSet) <- divergences, inSet n s ]
    bad =
      [ "n=" ++ show n ++ " " ++ header s ++ ": ours " ++ show o ++ ", Go " ++ show g
          ++ (if null names then " (not a listed divergence)" else " (listed, but agrees)")
      | (n, s) <- box
      , let o = ours n s
            g = serveRange (header s) n
            names = listed n s
      , (o /= g) /= not (null names) ]
    unhit = [ "listed divergence never reached: " ++ name
            | (name, inSet) <- divergences, not (any (uncurry inSet) box) ]

box :: [(Integer, RangeSpec)]
box = [ (n, s) | n <- [0 .. 10], s <- specs ]
  where
    ps = [0 .. 12] :: [Int]
    specs = [ IntRange f l | f <- ps, l <- ps ] ++ map OpenRange ps ++ map Suffix ps

-- | Each point's kind and the atoms its answer depends on, 0 first.
atoms :: (Integer, RangeSpec) -> (String, [Integer])
atoms (n, IntRange f l) = ("int-range", [0, toInteger f, toInteger l, n])
atoms (n, OpenRange f)  = ("open range", [0, toInteger f, n])
atoms (n, Suffix k)     = ("suffix-range", [0, toInteger k, n])

-- | Every order cell of every kind is realised, and by points that span it.
-- A cell is a weak ordering of the atoms with 0 at the bottom (no input is
-- negative); its dimension is the number of classes above 0's.
cellCoverage :: Result
cellCoverage = Result "Range: every order cell of the box's atoms, realised by points that span it" (length allCells) (miscounted ++ missing ++ thin)
  where
    rankOf xs = let vs = nub (sort xs) in [ length (takeWhile (< x) vs) | x <- xs ]
    found = Map.fromListWith (++) [ ((kind, rankOf xs), [drop 1 xs]) | p <- box, let (kind, xs) = atoms p ]
    kinds = [("int-range", 4), ("open range", 3), ("suffix-range", 3)] :: [(String, Int)]
    allCells = [ (kind, r) | (kind, m) <- kinds, r <- weakOrders m ]
    -- The enumerator, counted against an independent formula: the other
    -- atoms form any weak ordering, and 0 joins their lowest class or sits
    -- below it.
    miscounted = [ "weakOrders " ++ show m ++ " has " ++ show (length (weakOrders m)) ++ " cells, not " ++ show (2 * fubini (m - 1))
                 | (_, m) <- kinds, length (weakOrders m) /= 2 * fubini (m - 1) ]
    missing = [ "order cell never realised: " ++ show c | c <- allCells, not (Map.member c found) ]
    thin = [ "order cell " ++ show c ++ " spans dimension " ++ show (affineRank vs) ++ " of " ++ show (maximum r)
           | (c@(_, r), vs) <- Map.toList found, affineRank vs /= maximum r ]

-- | Rank vectors of length m with the first atom at rank 0 that use every
-- rank from 0 to their maximum: the weak orderings with that atom lowest.
weakOrders :: Int -> [[Int]]
weakOrders m = [ 0 : rs | rs <- mapM (const [0 .. m - 1]) [2 .. m], let r = 0 : rs, sort (nub r) == [0 .. maximum r] ]

-- | Ordered set partitions of n labelled things (the Fubini numbers).
fubini :: Int -> Int
fubini 0 = 1
fubini n = sum [ choose n k * fubini (n - k) | k <- [1 .. n] ]
  where choose a b = product [a - b + 1 .. a] `div` product [1 .. b]

-- | The dimension of the affine hull of a set of integer points.
affineRank :: [[Integer]] -> Int
affineRank [] = -1
affineRank (p : ps) = rank [ zipWith (-) q p | q <- ps ]
  where
    rank rows = case filter (any (/= 0)) rows of
      [] -> 0
      r : rs ->
        let j = length (takeWhile (== 0) r)
            pivot = r !! j
            reduce q = let c = q !! j in zipWith (\a b -> pivot * a - c * b) q r
        in 1 + rank (map reduce rs)

main :: IO ()
main = do
  refs <- maybe "../references" id <$> lookupEnv "FUNKNOWN_REFERENCES"
  json <- withFile (refs ++ "/problems-and-digests/statements.json") ReadMode $ \h -> do
    hSetEncoding h utf8
    s <- hGetContents h
    length s `seq` pure s
  oks <- mapM report
    [ admission
    , algorithm
    , checksumEdges
    , crcParameters json
    , boundary
    , rangeVsGo
    , cellCoverage
    ]
  if and oks then putStrLn "all checks passed" else exitFailure
