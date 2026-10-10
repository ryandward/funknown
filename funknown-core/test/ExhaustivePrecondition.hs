-- | Http.Validator and Http.Precondition: proofs by exhaustion over finite
-- domains, and port diffs against the literal transcription in
-- test/Port/GoFs.hs. Nothing here is sampled: every point of each domain is
-- checked, and the count is printed.
module Main (main) where

import Control.Monad (unless, when)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import System.Exit (exitFailure)

import Funknown.Opt (Opt (..))
import Funknown.Http.Validator
import Funknown.Http.Precondition
import qualified Port.GoFs as Go
import Port.GoFs (CondResult (..))

main :: IO ()
main = do
  failures <- newIORef (0 :: Int)
  validatorTable failures
  validatorPort failures
  evaluationPort failures
  ladderPort failures
  n <- readIORef failures
  if n == 0 then putStrLn "all exhaustive checks passed" else do
    putStrLn (show n ++ " exhaustive check(s) failed")
    exitFailure

-- | Records a failure with a message, without stopping the run.
check :: IORef Int -> Bool -> String -> IO ()
check failures ok msg = unless ok $ do
  modifyIORef' failures (+ 1)
  putStrLn ("FAIL: " ++ msg)

-- | Prints how many points a section checked.
report :: String -> Int -> IO ()
report name n = putStrLn (name ++ ": " ++ show n ++ " points checked")

------------------------------------------------------------------------------
-- Http.Validator

tag :: Bool -> String -> EntityTag
tag w o = EntityTag w (OpaqueTag o)

render :: EntityTag -> String
render (EntityTag w (OpaqueTag o)) = (if w then "W/" else "") ++ "\"" ++ o ++ "\""

-- | V11 by exhaustion: the four rows of HS:RFC9110-8.8.3.2-3 exactly as the
-- RFC prints them, and strong implies weak over every pair of tags built from
-- both weaknesses and the table's two opaque-tags.
validatorTable :: IORef Int -> IO ()
validatorTable failures = do
  let rows =
        [ (tag True "1",  tag True "1",  False, True)
        , (tag True "1",  tag True "2",  False, False)
        , (tag True "1",  tag False "1", False, True)
        , (tag False "1", tag False "1", True,  True) ]
  mapM_ (\(a, b, s, w) -> do
          check failures (strongMatch a b == s) ("8.8.3.2 strong " ++ render a ++ " " ++ render b)
          check failures (weakMatch a b == w) ("8.8.3.2 weak " ++ render a ++ " " ++ render b))
        rows
  let pairs = [ (a, b) | a <- tags, b <- tags ]
  mapM_ (\(a, b) -> check failures (not (strongMatch a b) || weakMatch a b)
                          ("strong without weak: " ++ render a ++ " " ++ render b))
        pairs
  report "V11 table rows (HS:RFC9110-8.8.3.2-3)" (length rows)
  report "V11 strong implies weak" (length pairs)
  where
    tags = [ tag w o | w <- [False, True], o <- ["1", "2"] ]

-- | fs.go:458-466 against Validator: the same 16 pairs, rendered for Go. No
-- divergence is documented, so every pair has to agree.
validatorPort :: IORef Int -> IO ()
validatorPort failures = do
  let tags = [ tag w o | w <- [False, True], o <- ["1", "2"] ]
      pairs = [ (a, b) | a <- tags, b <- tags ]
  mapM_ (\(a, b) -> do
          check failures (strongMatch a b == Go.etagStrongMatch (render a) (render b))
            ("etagStrongMatch differs on " ++ render a ++ " " ++ render b)
          check failures (weakMatch a b == Go.etagWeakMatch (render a) (render b))
            ("etagWeakMatch differs on " ++ render a ++ " " ++ render b))
        pairs
  report "port fs.go:458-466 (no divergences)" (length pairs)

------------------------------------------------------------------------------
-- Http.Precondition, header by header

fromGo :: CondResult -> Cond
fromGo CondNone  = CAbsent
fromGo CondTrue  = Holds
fromGo CondFalse = Fails

-- | The representation as each side sees it: Go's Etag header and modtime,
-- and our entity tag and last-modified date.
data Rep = Rep { goEtag :: String, goModtime :: Go.Time, ourEtag :: Opt EntityTag, ourModified :: Opt Seconds }

lastModified :: Int
lastModified = 1000

reps :: [Rep]
reps =
  [ Rep e m t d
  | (e, t) <- [("", Absent), ("\"r\"", Present (tag False "r")), ("W/\"r\"", Present (tag True "r"))]
  , (m, d) <- [(Go.ZeroTime, Absent), (Go.Unix (toInteger lastModified), Present lastModified)] ]

getRequest :: String -> String -> Go.Request
getRequest k v = Go.Request "GET" [(k, v)]

-- | The helpers of fs.go:478-607 against our evaluation of each header, over
-- concrete field values and every representation. The divergences are
-- exactly fixes (a), (d) and (e).
evaluationPort :: IORef Int -> IO ()
evaluationPort failures = do
  let tagFields =
        [ ("*", Star)
        , ("\"r\"", Listed [tag False "r"])
        , ("W/\"r\"", Listed [tag True "r"])
        , ("\"x\"", Listed [tag False "x"])
        , ("\"x\", \"r\"", Listed [tag False "x", tag False "r"])
        , ("W/\"x\", W/\"r\"", Listed [tag True "x", tag True "r"]) ]
      dateFields = [ (show d, d) | d <- [lastModified - 1, lastModified, lastModified + 1] ]
      rangeFields =
        [ ("\"r\"", RangeTag (tag False "r"))
        , ("W/\"r\"", RangeTag (tag True "r"))
        , ("\"x\"", RangeTag (tag False "x")) ]
        ++ [ (s, RangeDate) | (s, _) <- dateFields ]
      noRep rep = case ourEtag rep of
        Absent    -> True
        Present _ -> False
      -- Each case: Go's helper, ours, and whether the point is a documented
      -- divergence.
      cases =
        [ ( "If-Match " ++ s
          , Go.checkIfMatch (Go.Writer (goEtag rep)) (getRequest "If-Match" s)
          , ifMatch (Present f) (ourEtag rep)
          , s == "*" && noRep rep )                                   -- (d)
        | (s, f) <- tagFields, rep <- reps ]
        ++
        [ ( "If-None-Match " ++ s
          , Go.checkIfNoneMatch (Go.Writer (goEtag rep)) (getRequest "If-None-Match" s)
          , ifNoneMatch (Present f) (ourEtag rep)
          , s == "*" && noRep rep )                                   -- (e)
        | (s, f) <- tagFields, rep <- reps ]
        ++
        [ ( "If-Unmodified-Since " ++ s
          , Go.checkIfUnmodifiedSince (getRequest "If-Unmodified-Since" s) (goModtime rep)
          , ifUnmodifiedSince (Present d) (ourModified rep)
          , False )
        | (s, d) <- dateFields, rep <- reps ]
        ++
        [ ( "If-Modified-Since " ++ s
          , Go.checkIfModifiedSince (getRequest "If-Modified-Since" s) (goModtime rep)
          , ifModifiedSince (Present d) (ourModified rep)
          , False )
        | (s, d) <- dateFields, rep <- reps ]
        ++
        [ ( "If-Range " ++ s
          , Go.checkIfRange (Go.Writer (goEtag rep)) (getRequest "If-Range" s) (goModtime rep)
          , ifRange (Present f) (ourEtag rep)
          , f == RangeDate && s == show lastModified
              && goModtime rep == Go.Unix (toInteger lastModified) )   -- (a)
        | (s, f) <- rangeFields, rep <- reps ]
        ++
        -- An absent header is ignored by both, whatever the representation.
        concat
          [ [ ("absent " ++ k, goCheck rep (Go.Request "GET" []), ours rep, False) | rep <- reps ]
          | (k, goCheck, ours) <-
              [ ("If-Match", \rep -> Go.checkIfMatch (Go.Writer (goEtag rep)), ifMatch Absent . ourEtag)
              , ("If-None-Match", \rep -> Go.checkIfNoneMatch (Go.Writer (goEtag rep)), ifNoneMatch Absent . ourEtag)
              , ("If-Unmodified-Since", \rep r -> Go.checkIfUnmodifiedSince r (goModtime rep), ifUnmodifiedSince Absent . ourModified)
              , ("If-Modified-Since", \rep r -> Go.checkIfModifiedSince r (goModtime rep), ifModifiedSince Absent . ourModified)
              , ("If-Range", \rep r -> Go.checkIfRange (Go.Writer (goEtag rep)) r (goModtime rep), ifRange Absent . ourEtag) ] ]
  mapM_ (\(name, go, ours, documented) -> do
          let differs = fromGo go /= ours
          when (differs && not documented) $
            check failures False ("undocumented divergence: " ++ name ++ ": Go " ++ show go ++ ", ours " ++ show ours)
          when (documented && not differs) $
            check failures False ("documented divergence no longer differs: " ++ name))
        cases
  let documentedCount = length [ () | (_, _, _, True) <- cases ]
  report ("port fs.go:478-607 header evaluation (" ++ show documentedCount ++ " documented divergences)") (length cases)

------------------------------------------------------------------------------
-- Http.Precondition, the ladder

-- | One point of the 2916-point domain. Each header is labelled with the
-- result Go's own helper gives it on a GET against the same representation,
-- and the point is made concrete by 'request'; 'labelsRealised' confirms that
-- every label is what Go's helper actually returns.
data Point = Point
  { pIfMatch, pIfUnmodifiedSince, pIfNoneMatch, pIfModifiedSince, pIfRange :: CondResult
  , pMethod :: MethodKind
  , pRange :: Bool
  , pRep :: Bool
  } deriving (Show)

points :: [Point]
points =
  [ Point im ius inm ims ir m rg rep
  | im <- results, ius <- results, inm <- results, ims <- results, ir <- results
  , m <- [MGet, MHead, MUnsafe], rg <- [False, True], rep <- [False, True] ]
  where
    results = [minBound .. maxBound]

-- | The representation: an entity tag "r" when it exists, and a modification
-- date in both cases, so the date labels are realisable either way.
pointRep :: Bool -> Rep
pointRep True  = Rep "\"r\"" (Go.Unix (toInteger lastModified)) (Present (tag False "r")) (Present lastModified)
pointRep False = Rep "" (Go.Unix (toInteger lastModified)) Absent (Present lastModified)

-- | Each header's label made concrete: the field for Go and the same field as
-- our shell would parse it. Without a representation, only * makes If-Match
-- true or If-None-Match false in Go, and only a date makes If-Range true.
ifMatchField, ifNoneMatchField :: CondResult -> Bool -> Maybe (String, TagField)
ifMatchField CondNone  _     = Nothing
ifMatchField CondTrue  True  = Just ("\"r\"", Listed [tag False "r"])
ifMatchField CondTrue  False = Just ("*", Star)
ifMatchField CondFalse _     = Just ("W/\"r\"", Listed [tag True "r"])
ifNoneMatchField CondNone  _     = Nothing
ifNoneMatchField CondTrue  _     = Just ("\"x\"", Listed [tag False "x"])
ifNoneMatchField CondFalse True  = Just ("W/\"r\"", Listed [tag True "r"])
ifNoneMatchField CondFalse False = Just ("*", Star)

ifUnmodifiedSinceField, ifModifiedSinceField :: CondResult -> Maybe (String, Seconds)
ifUnmodifiedSinceField CondNone  = Nothing
ifUnmodifiedSinceField CondTrue  = Just (show lastModified, lastModified)
ifUnmodifiedSinceField CondFalse = Just (show (lastModified - 1), lastModified - 1)
ifModifiedSinceField CondNone  = Nothing
ifModifiedSinceField CondTrue  = Just (show (lastModified - 1), lastModified - 1)
ifModifiedSinceField CondFalse = Just (show lastModified, lastModified)

ifRangeField :: CondResult -> Bool -> Maybe (String, RangeValidator)
ifRangeField CondNone  _     = Nothing
ifRangeField CondTrue  True  = Just ("\"r\"", RangeTag (tag False "r"))
ifRangeField CondTrue  False = Just (show lastModified, RangeDate)
ifRangeField CondFalse _     = Just ("\"x\"", RangeTag (tag False "x"))

methodName :: MethodKind -> String
methodName MGet    = "GET"
methodName MHead   = "HEAD"
methodName MUnsafe = "DELETE"

request :: Point -> Go.Request
request p = Go.Request (methodName (pMethod p)) (concat
  [ field "If-Match" (fst <$> ifMatchField (pIfMatch p) (pRep p))
  , field "If-Unmodified-Since" (fst <$> ifUnmodifiedSinceField (pIfUnmodifiedSince p))
  , field "If-None-Match" (fst <$> ifNoneMatchField (pIfNoneMatch p) (pRep p))
  , field "If-Modified-Since" (fst <$> ifModifiedSinceField (pIfModifiedSince p))
  , field "If-Range" (fst <$> ifRangeField (pIfRange p) (pRep p))
  , if pRange p then [("Range", "bytes=0-0")] else [] ])
  where
    field k = maybe [] (\v -> [(k, v)])

opt :: Maybe a -> Opt a
opt = maybe Absent Present

goVerdict :: Point -> Either String Verdict
goVerdict p =
  let rep = pointRep (pRep p)
  in case Go.checkPreconditions (Go.Writer (goEtag rep)) (request p) (goModtime rep) of
       (Just 412, True, "") -> Right V412
       (Just 304, True, "") -> Right V304
       (Nothing, False, rh) -> Right (Proceed (if rh /= "" then ByRange else Whole))
       other                -> Left ("unexpected result from Go: " ++ show other)

ourVerdict :: Point -> Answer
ourVerdict p =
  let rep = pointRep (pRep p)
      e = ourEtag rep
      lm = ourModified rep
      im = ifMatch (opt (snd <$> ifMatchField (pIfMatch p) (pRep p))) e
      ius = ifUnmodifiedSince (opt (snd <$> ifUnmodifiedSinceField (pIfUnmodifiedSince p))) lm
      inm = ifNoneMatch (opt (snd <$> ifNoneMatchField (pIfNoneMatch p) (pRep p))) e
      ims = ifModifiedSince (opt (snd <$> ifModifiedSinceField (pIfModifiedSince p))) lm
      ir = ifRange (opt (snd <$> ifRangeField (pIfRange p) (pRep p))) e
  in preconditioned 200 True (pMethod p) im ius inm ims (rangeReq (pRange p) ir)

-- | Where Go's ladder stops, read off the labels: Go evaluates If-Modified-
-- Since and If-Range only for GET and HEAD (fs.go:558, 579).
goProceeds, goKeepsRange :: Point -> Bool
goProceeds p =
  not (pIfMatch p == CondFalse || (pIfMatch p == CondNone && pIfUnmodifiedSince p == CondFalse))
    && pIfNoneMatch p /= CondFalse
    && not (pIfNoneMatch p == CondNone && pMethod p /= MUnsafe && pIfModifiedSince p == CondFalse)
goKeepsRange p = pRange p && not (pMethod p /= MUnsafe && pIfRange p == CondFalse)

-- | The documented divergence set, fix by fix. Each predicate names the
-- inputs where the fix applies and Go's answer is not already the one the fix
-- produces, so the sets are exact and pairwise disjoint.
divergences :: [(String, Point -> Bool)]
divergences =
  [ ( "(a) a date If-Range is false"
    , \p -> pMethod p == MGet && pRange p && pIfRange p == CondTrue && not (pRep p)
              && pIfMatch p == CondNone && pIfUnmodifiedSince p /= CondFalse
              && (pIfNoneMatch p == CondTrue
                    || (pIfNoneMatch p == CondNone && pIfModifiedSince p /= CondFalse)) )
  , ( "(c) Range, and with it If-Range, only for GET"
    , \p -> pMethod p /= MGet && goProceeds p && goKeepsRange p
              && not (pIfMatch p == CondTrue && not (pRep p)) )
  , ( "(d) If-Match: * holds only when a representation exists"
    , \p -> pIfMatch p == CondTrue && not (pRep p)
              && not (pIfNoneMatch p == CondFalse && pMethod p == MUnsafe) )
  , ( "(e) If-None-Match: * fails only when one exists"
    , \p -> pIfNoneMatch p == CondFalse && not (pRep p)
              && pIfMatch p == CondNone && pIfUnmodifiedSince p /= CondFalse ) ]

-- | Go's checkPreconditions against ladder over all 2916 points. Fix (b)
-- can't differ here, because every point is at the origin, as every call
-- site is; nonOriginIgnores proves it by refinement instead.
ladderPort :: IORef Int -> IO ()
ladderPort failures = do
  -- The labels mean what they say: Go's own helper, on a GET, returns each one.
  let realised =
        [ (name, rep, label, got)
        | rep <- [False, True], label <- [minBound .. maxBound]
        , (name, got) <- labelResults rep label ]
  mapM_ (\(name, rep, label, got) ->
          check failures (got == label)
            (name ++ " label " ++ show label ++ " (rep " ++ show rep ++ ") gives " ++ show got))
        realised
  report "ladder domain labels realised by Go's helpers" (length realised)

  let classify p = [ name | (name, inSet) <- divergences, inSet p ]
  results <- mapM (\p -> do
    let fixes = classify p
    case goVerdict p of
      Left err -> check failures False (err ++ " at " ++ show p) >> return fixes
      Right go -> do
        let ours = ourVerdict p
            differs = ours /= Conditional go
        check failures (length fixes <= 1) ("divergence sets overlap at " ++ show p ++ ": " ++ show fixes)
        when (differs && null fixes) $
          check failures False ("undocumented divergence at " ++ show p ++ ": Go " ++ show go ++ ", ours " ++ show ours)
        when (not differs && not (null fixes)) $
          check failures False ("documented divergence " ++ show fixes ++ " no longer differs at " ++ show p)
        return fixes) points
  mapM_ (\(name, _) -> do
          let n = length (filter (elem name) results)
          check failures (n > 0) ("documented divergence " ++ name ++ " never occurs")
          putStrLn ("  " ++ name ++ ": " ++ show n ++ " points"))
        divergences
  report "port fs.go:640-671 ladder (origin)" (length points)
  where
    labelResults rep label =
      let r = pointRep rep
          w = Go.Writer (goEtag r)
          t = goModtime r
          req k = maybe (Go.Request "GET" []) (getRequest k)
      in [ ("If-Match", Go.checkIfMatch w (req "If-Match" (fst <$> ifMatchField label rep)))
         , ("If-Unmodified-Since", Go.checkIfUnmodifiedSince (req "If-Unmodified-Since" (fst <$> ifUnmodifiedSinceField label)) t)
         , ("If-None-Match", Go.checkIfNoneMatch w (req "If-None-Match" (fst <$> ifNoneMatchField label rep)))
         , ("If-Modified-Since", Go.checkIfModifiedSince (req "If-Modified-Since" (fst <$> ifModifiedSinceField label)) t)
         , ("If-Range", Go.checkIfRange w (req "If-Range" (fst <$> ifRangeField label rep)) t) ]
