{-# LANGUAGE Safe #-}
-- | Exhaustive checks of the generated registries against the vendored files
-- they were generated from, and the port diff against http-types. Every
-- check walks its whole finite domain; nothing is sampled.
--
-- The vendored files are read from $FUNKNOWN_REFERENCES, or ../references
-- (cabal runs a test from its package directory).
module Main (main) where

import Control.Monad (unless)
import Data.Char (isDigit)
import Data.List (nub, sort, (\\))
import qualified Data.Map.Strict as Map
import Funknown.Digest
import Funknown.Http.Status
import Funknown.Opt (Opt (..))
import Funknown.Problem
import Funknown.Rpc.Code
import Funknown.Rpc.Recourse
import qualified Port.HttpTypesStatus as Port
import Registries.Vendored
import System.Environment (lookupEnv)
import System.Exit (exitFailure)

-- | A named check: how many points it walked, and what failed.
data Check = Check String Int [String]

check :: String -> [a] -> (a -> [String]) -> Check
check name dom f = Check name (length dom) (concatMap f dom)

expect :: Bool -> String -> [String]
expect ok msg = [msg | not ok]

allOf :: (Bounded a, Enum a) => [a]
allOf = [minBound .. maxBound]

main :: IO ()
main = do
  refs <- maybe "../references" id <$> lookupEnv "FUNKNOWN_REFERENCES"
  let file rel = readFile (refs ++ "/" ++ rel)
  statusCsv <- file "http-semantics/http-status-codes-1.csv"
  proto <- file "status-and-supervision/googleapis/code.proto"
  aip <- file "status-and-supervision/aip/0194.md"
  digestXml <- file "problems-and-digests/iana/http-digest-hash-alg.xml"
  problemCsv <- file "problems-and-digests/iana/http-problem-type-uris.csv"
  draft <- file "uploads/draft-ietf-httpbis-resumable-upload-13.txt"
  let checks =
        statusChecks (drop 1 (csvRows statusCsv))
          ++ [portDiff]
          ++ codeChecks (protoEnum proto)
          ++ recourseChecks (aipSections aip)
          ++ digestChecks (xmlRecords digestXml)
          ++ problemChecks (drop 1 (csvRows problemCsv)) (draftRequests draft)
  failures <- fmap concat . mapM report $ checks
  unless (null failures) $ do
    putStrLn (show (length failures) ++ " failures")
    exitFailure
  putStrLn ("all " ++ show (length checks) ++ " checks passed")
  where
    report (Check name n fs) = do
      putStrLn ((if null fs then "ok   " else "FAIL ") ++ name ++ ": " ++ show n ++ " points")
      mapM_ (putStrLn . ("       " ++)) (take 20 fs)
      pure fs

-- * Http.Status

byCode :: Map.Map Int Status
byCode = Map.fromList [(statusCode s, s) | s <- allOf]

x00 :: Int -> Status
x00 n = byCode Map.! (100 * (n `div` 100))

statusChecks :: [[String]] -> [Check]
statusChecks rows =
  [ Check "status CSV has 75 rows" 1 (expect (length rows == 75) ("rows: " ++ show (length rows)))
  , check "status CSV rows against Http.Status" rows row
  , check "every code in 100..599 decodes as its row says" [100 .. 599 :: Int] perCode
  , check "every constructor comes from exactly one assigned row" allOf ownRow
  , check "V1 round trip fromWire (statusCode s) == s" allOf $ \s ->
      expect (fromWire (statusCode s) == s) (show s)
  , check "V1 statusCode injective" [(a, b) | a <- allOf, b <- allOf] $ \(a, b) ->
      expect (a == b || statusCode a /= statusCode b) (show (a, b))
  , check "V2 respondable is Permanent and not 1xx" allOf $ \s ->
      expect (respondable s == (registration s == Permanent && classOf s /= Informational)) (show s)
  , check "V2 the statuses that aren't respondable are 100-104 and 510" [()] $ \_ ->
      let no = sort [statusCode s | s <- allOf, not (respondable s)]
       in expect (no == [100, 101, 102, 103, 104, 510]) (show no)
  ]
  where
    assigned = Map.fromList [(read v, (d, rg d)) | [v, d, _] <- rows, all isDigit v, d /= "(Unused)", d /= "Unassigned"]
    rg d
      | contains "(TEMPORARY" d = Temporary
      | contains "(OBSOLETED)" d = Obsoleted
      | otherwise = Permanent
    row [v, d, _] = case break (== '-') v of
      (a, '-' : b) -> expect (d == "Unassigned" && all (`Map.notMember` byCode) [read a .. read b :: Int]) ("range " ++ v)
      _ -> case (d, Map.lookup (read v) byCode) of
        ("(Unused)", c) -> expect (c == Nothing) ("Unused " ++ v ++ " has a constructor")
        ("Unassigned", c) -> expect (c == Nothing) ("Unassigned " ++ v ++ " has a constructor")
        (_, Nothing) -> ["assigned " ++ v ++ " has no constructor"]
        (_, Just s) ->
          expect (description s == d) ("description of " ++ v)
            ++ expect (registration s == rg d) ("registration of " ++ v)
            ++ expect (fromEnum (classOf s) + 1 == read (take 1 v)) ("class of " ++ v)
    row r = ["malformed row " ++ show r]
    perCode n = case Map.lookup n assigned of
      Just _ -> expect (statusCode (fromWire n) == n) ("assigned " ++ show n)
      Nothing ->
        expect (fromWire n == x00 n) ("unassigned or Unused " ++ show n ++ " -> " ++ show (fromWire n))
    ownRow s = expect (Map.member (statusCode s) assigned) (show s ++ " has no assigned row")

contains :: String -> String -> Bool
contains p s = any (\k -> take (length p) (drop k s) == p) [0 .. length s - length p]

-- * Port diff: http-types' class predicates against classOf . fromWire, over
-- every code of at most three digits.

portDiff :: Check
portDiff =
  let dom = [0 .. 999 :: Int]
      theirs n = [p (Port.Status n) | p <- [Port.statusIsInformational, Port.statusIsSuccessful, Port.statusIsRedirection, Port.statusIsClientError, Port.statusIsServerError]]
      ours n = [classOf (fromWire n) == c | c <- allOf]
      differs = [n | n <- dom, theirs n /= ours n]
      -- (a) a code outside 100..599: http-types gives it no class, and we
      -- treat it as 500 (HS:RFC9110-15-6, PM38).
      documented = [0 .. 99] ++ [600 .. 999]
   in Check "port diff http-types Status.hs:783-816 vs classOf . fromWire, codes 0..999" (length dom) $
        ["undocumented divergence at " ++ show n | n <- differs \\ documented]
          ++ ["documented divergence no longer differs at " ++ show n | n <- documented \\ differs]

-- * Rpc.Code

codeChecks :: [(String, Int)] -> [Check]
codeChecks proto =
  [ Check "code.proto has 17 codes, and so does Rpc.Code" 1 (expect (length proto == 17 && length (allOf :: [Code]) == 17) "count")
  , check "code.proto names and numbers against Rpc.Code, in declaration order" (zip allOf proto) $ \(c, (name, n)) ->
      expect (show c == name && codeNumber c == n) (show (c, codeNumber c) ++ " vs " ++ show (name, n))
  , check "V8 codeNumber image is 0..16" [()] $ \_ ->
      expect (sort (map codeNumber allOf) == [0 .. 16]) "image"
  , check "V8 codeNumber injective" [(a, b) | a <- allOf, b <- allOf] $ \(a, b) ->
      expect (a == b || codeNumber a /= codeNumber (b :: Code)) (show (a, b))
  , check "V8 codeOfNumber inverts codeNumber" [0 .. 16] $ \n ->
      expect (codeNumber (codeOfNumber n) == n) (show n)
  ]

-- * Rpc.Recourse

recourseChecks :: [(String, [String])] -> [Check]
recourseChecks sections =
  [ check "AIP-194 sections against Recourse" [()] $ \_ ->
      expect (map fst sections == ["Retryable codes", "Non-retryable codes", "Generally non-retryable codes"]) (show (map fst sections))
        ++ expect (length (allOf :: [Recourse]) == 3) "Recourse has three constructors"
  , Check "AIP-194 lists 18 names, and Aip194Name has 18" 1 (expect (length names == 18 && length (allOf :: [Aip194Name]) == 18) (show (length names)))
  , check "AIP-194 names, in order, against Aip194Name" (zip (allOf :: [Aip194Name]) names) $ \(a, n) ->
      expect (show a == "A_" ++ n) (show a ++ " vs " ++ n)
  , check "recourse puts every name in its section" entries $ \(i, n) ->
      expect (fmap (fromEnum . recourse) (lookupName n) == Just i) n
  , check "V8 listedAs names each code by its own name" allOf $ \c ->
      expect (show (listedAs c) == "A_" ++ show c) (show c)
  , check "V8 listedAs injective" [(a, b) | a <- allOf, b <- allOf] $ \(a, b) ->
      expect (a == b || listedAs a /= listedAs b) (show (a, b))
  , check "V8 A_UNAUTHORIZED is the only name listedAs doesn't reach" allOf $ \a ->
      expect ((a `elem` map listedAs allOf) == (a /= A_UNAUTHORIZED)) (show a)
  , check "listing inverts listedAs" allOf $ \a ->
      expect (listing a == maybe Absent Present (lookup a [(listedAs c, c) | c <- allOf])) (show a)
  ]
  where
    names = concatMap snd sections
    entries = [(i, n) | (i, (_, ns)) <- zip [0 :: Int ..] sections, n <- ns]
    lookupName n = lookup ("A_" ++ n) [(show a, a) | a <- allOf :: [Aip194Name]]

-- * Digest

digestChecks :: [(String, String)] -> [Check]
digestChecks records =
  [ Check "digest registry has 8 records, and DigestKey has 8" 1 (expect (length records == 8 && length (allOf :: [DigestKey]) == 8) (show (length records)))
  , check "digest registry records against Digest, in order" (zip allOf records) $ \(k, (key, st)) ->
      expect (keyToken k == key && show (keyStatus k) == st) (show k ++ " vs " ++ key)
  , check "KeyStatus is exactly the statuses in use" [()] $ \_ ->
      expect (map show (allOf :: [KeyStatus]) == nub (map snd records)) "statuses"
  , check "DC16 forwardable is Absent for every key" allOf $ \k ->
      expect (absent (forwardable (ClientDigest k (Octets [])))) (show k)
  ]
  where
    absent Absent = True
    absent (Present _) = False

-- * Problem

problemChecks :: [[String]] -> [(String, String, Int)] -> [Check]
problemChecks rows requests =
  [ check "problem types against the registry or the draft" allOf $ \t ->
      case [(u, ti, st) | (u, ti, st) <- registryRows ++ drafted, u == typeUri t] of
        [(_, ti, st)] ->
          expect (registryTitle t == ti) ("title of " ++ show t)
            ++ expect (fmapOpt statusCode (recommended t) == st) ("status of " ++ show t)
            ++ expect (isDraft t == any (\(u, _, _) -> u == typeUri t) drafted) ("isDraft " ++ show t)
        found -> [show t ++ " matches " ++ show (length found) ++ " rows"]
  , check "digest-invalid-values and digest-mismatched-values have no ProblemType" ["digest-invalid-values", "digest-mismatched-values"] $ \f ->
      expect (all ((/= prefix ++ f) . typeUri) allOf) f
  , check "sample reaches every ProblemType" allOf $ \t ->
      expect (problemType (sample t) == t) (show t)
  , check "SF8 each problem fits the statuses its row recommends, all 62 for about:blank" (map sample allOf) $ \p ->
      let fitting = [statusCode s | s <- allOf, fits p s]
          rowStatus = [st | (u, _, st) <- registryRows ++ drafted, u == typeUri (problemType p)]
       in case rowStatus of
            [Nothing] -> expect (length fitting == 62) (show p)
            [Just n] -> expect (fitting == [n]) (show p ++ " fits " ++ show fitting)
            _ -> [show p ++ " has no single row"]
  , check "draftProblemTypes is off, and the core's way of building each type gives Blank for the draft's" allOf $ \t ->
      expect (not draftProblemTypes) "flag on"
        ++ expect (built t == (if isDraft t then Blank else sample t)) (show t ++ " built as " ++ show (built t))
  ]
  where
    prefix = "https://iana.org/assignments/http-problem-types#"
    registryRows = [(u, t, if s == "N/A" then Nothing else Just (read s)) | [u, t, s, _] <- rows]
    drafted = [(u, t, Just s) | (u, t, s) <- requests]

-- | One problem of each type, from the raw constructors. fits and problemType
-- read only the constructor, so one value per type covers their domain. This
-- suite runs without LiquidHaskell, so it can build the draft's types, which
-- the core can't while the flag is off. The case is total over ProblemType, so
-- -Werror=incomplete-patterns stops the build if gen-vocab adds a type, and
-- "sample reaches every ProblemType" fails if a case builds the wrong one.
sample :: ProblemType -> Problem
sample AboutBlank = Blank
sample DigestUnsupportedAlgorithms = UnsupportedAlgorithms []
sample MismatchingUploadOffset = MismatchingOffset DraftOn 0 0
sample InconsistentUploadLength = InconsistentLength DraftOn

-- | The same, built the way a core module has to build them.
built :: ProblemType -> Problem
built AboutBlank = Blank
built DigestUnsupportedAlgorithms = UnsupportedAlgorithms []
built MismatchingUploadOffset = mismatchingOffset 0 0
built InconsistentUploadLength = inconsistentLength

fmapOpt :: (a -> b) -> Opt a -> Maybe b
fmapOpt f (Present a) = Just (f a)
fmapOpt _ Absent = Nothing
