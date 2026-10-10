{-# LANGUAGE Safe #-}
-- | Port diffs for Funknown.Http.Retry, by exhaustion over finite domains.
--
-- Each diff asserts, point by point, that our function and the literal
-- transcription agree exactly off the documented divergence set, and that on
-- it ours gives the answer the divergence promises while theirs gives
-- another. So a new divergence fails, a listed one that stopped differing
-- fails, and so does a listed one that differs the wrong way (say, not
-- retrying where we promised to retry sooner than urllib3).
--
-- What is enumerated, and what makes it the whole domain:
--
-- * onStatus vs urllib3: 9 methods x every status 100..599 x the six
--   Retry-After shapes. A shape stands for every value of its class because
--   of LiquidHaskell lemmas over all values: 'onStatusShapeDecides' on our
--   side, and 'sleepNone', 'sleepDigits' and 'sleepDate' on the
--   transcription's side, while urllib3's is_retry takes only a Bool for
--   Retry-After. The delay values themselves are compared by those lemmas and
--   by 'hintOfDelay', 'hintOfPastOrNow' and 'hintOfFuture', not here.
-- * onConnection vs Go: 9 methods x 4 faults x rewindable, and for each, every
--   Go request and connection that realizes it: body kind, GetBody, both
--   Idempotency-Key names present or absent, and the errors a reused or fresh
--   connection reports. Content-Length takes two values per body; the
--   LiquidHaskell spec on 'outgoingLength' says its result is 0 exactly for a
--   nil or NoBody body whatever the Content-Length, and nothing else reads it.
module Main (main) where

import Control.Monad (unless)
import System.Exit (exitFailure)

import Funknown.Http.Method (Method (..), idempotent)
import Funknown.Http.Retry
import Funknown.Opt (Opt (..))
import qualified Port.GoTransport as Go
import qualified Port.Urllib3 as U

-- onStatus vs urllib3 --------------------------------------------------------

-- | How the shell would hand urllib3 the same field.
toUrllib3 :: RetryAfter -> U.PyOptional U.RetryAfterValue
toUrllib3 NoRetryAfter     = U.PyNone
toUrllib3 (DelaySeconds d) = U.PySome (U.MatchedDigits d)
toUrllib3 (DateDelta n)    = U.PySome (U.ParsedDate n)

isSome :: U.PyOptional a -> Bool
isSome U.PyNone     = False
isSome (U.PySome _) = True

-- | urllib3's outcome for one request: whether it retries, and how long it
-- sleeps first. It has no notion of a new connection.
urllib3Kind :: Method -> Int -> RetryAfter -> Kind
urllib3Kind m c a
  | not (U.is_retry U.retry_DEFAULT (show m) c (isSome h)) = Stop
  | otherwise = case U.sleep U.retry_DEFAULT h of
      U.SleptRetryAfter _ -> AfterHint
      U.SleptBackoff      -> AfterBackoff
  where
    h = toUrllib3 a

-- | The documented divergences of onStatus from urllib3's default Retry.
data StatusDivergence
  = Adds421       -- 421 retries on a new connection for any method (PM5)
  | Adds425       -- 425 retries an idempotent method (PM5)
  | Adds408       -- 408 retries an idempotent method (PM5)
  | ZeroIsNow     -- a Retry-After of 0, a past date or now means retry now;
                  -- urllib3's @if retry_after:@ (retry.py:337) backs off instead (CH31)
  deriving (Eq, Show)

-- | Where a divergence applies, and what our side answers there. The
-- expected kind is written out here rather than read from the library.
statusDivergence :: Method -> Int -> Shape -> Maybe (StatusDivergence, Kind)
statusDivergence m c s
  | c == 421                                     = Just (Adds421, NewConnection)
  | idempotent m && c == 425                     = Just (Adds425, afterFieldOrBackoff)
  | idempotent m && c == 408                     = Just (Adds408, afterFieldOrBackoff)
  | idempotent m && c `elem` [413, 429, 503]
      && s `elem` [ShapeDelayZero, ShapeDatePast, ShapeDateNow] = Just (ZeroIsNow, AfterHint)
  | otherwise                                    = Nothing
  where
    afterFieldOrBackoff = if s == ShapeAbsent then AfterBackoff else AfterHint

statusDiff :: [String]
statusDiff =
  [ show (m, c, s, ours, theirs, listed)
  | m <- [minBound .. maxBound]
  , c <- [100 .. 599]
  , s <- [minBound .. maxBound]
  , let a      = representative s
        ours   = kindOf (onStatus m c a)
        theirs = urllib3Kind m c a
        listed = statusDivergence m c s
  , not (agreesOffAndDiffersOn ours theirs (fmap snd listed))
  ]

statusPoints :: Int
statusPoints = length [minBound .. maxBound :: Method] * 500 * length [minBound .. maxBound :: Shape]

-- At the representatives, the delay both sides wait is the same number
-- wherever both wait for the server's delay. (Over every value this is
-- hintOfDelay/hintOfFuture against sleepDigits/sleepDate.)
hintValueDiff :: [String]
hintValueDiff =
  [ show (m, c, s)
  | m <- [minBound .. maxBound]
  , c <- [100 .. 599]
  , s <- [minBound .. maxBound]
  , let a = representative s
  , RetryIn (Present ours) <- [onStatus m c a]
  , U.is_retry U.retry_DEFAULT (show m) c (isSome (toUrllib3 a))
  , U.SleptRetryAfter theirs <- [U.sleep U.retry_DEFAULT (toUrllib3 a)]
  , ours /= theirs
  ]

-- onConnection vs Go ---------------------------------------------------------

-- | Every Go connection state and error that our fault stands for.
goFaults :: ConnFault -> [(Go.PersistConn, Go.Err)]
goFaults NothingWritten  = [(Go.PersistConn True, Go.NothingWrittenError)]
goFaults ReadFailed      = [(Go.PersistConn True, Go.TransportReadFromServerError)]
goFaults IdleClosed      = [(Go.PersistConn True, Go.ErrServerClosedIdle)]
goFaults FreshConnClosed =
  [ (Go.PersistConn False, e)
  | e <- [Go.NothingWrittenError, Go.TransportReadFromServerError, Go.ErrServerClosedIdle] ]

-- | Every Go body that our rewindable flag stands for: a body Go can send
-- again is nil, NoBody, or one with GetBody.
goBodies :: Bool -> [(Go.Body, Bool, Int)]
goBodies True =
  [ (b, g, cl) | b <- [Go.Nil, Go.NoBody], g <- [False, True], cl <- [0, 1] ]
    ++ [ (Go.Reader, True, cl) | cl <- [0, 1] ]
goBodies False = [ (Go.Reader, False, cl) | cl <- [0, 1] ]

idempotencyHeaders :: [[String]]
idempotencyHeaders = [[], ["Idempotency-Key"], ["X-Idempotency-Key"], ["Idempotency-Key", "X-Idempotency-Key"]]

-- | The documented divergences of onConnection from Go's shouldRetryRequest.
data ConnDivergence
  = PutDeleteIdempotent   -- R HS:RFC9110-9.2.2-1 makes PUT and DELETE idempotent;
                          -- Go's isReplayable (request.go:1545-1548) leaves them out
  | IdempotencyKeyDropped -- Go retries any method carrying an Idempotency-Key
                          -- (request.go:1552-1554); we don't read that header
  deriving (Eq, Show)

-- | Where a divergence applies, and whether our side retries there.
connDivergence :: Method -> ConnFault -> Bool -> [String] -> Maybe (ConnDivergence, Bool)
connDivergence m f rewindable hdr
  | f `elem` [ReadFailed, IdleClosed] && rewindable && m `elem` [PUT, DELETE] && null hdr
      = Just (PutDeleteIdempotent, True)
  | f `elem` [ReadFailed, IdleClosed] && rewindable && not (idempotent m) && not (null hdr)
      = Just (IdempotencyKeyDropped, False)
  | otherwise = Nothing

connCases :: [(Method, ConnFault, Bool, Go.PersistConn, Go.Request, Go.Err)]
connCases =
  [ (m, f, rw, pc, Go.Request (show m) b g cl hdr, e)
  | m <- [minBound .. maxBound]
  , f <- [minBound .. maxBound]
  , rw <- [False, True]
  , (pc, e) <- goFaults f
  , (b, g, cl) <- goBodies rw
  , hdr <- idempotencyHeaders
  ]

connDiff :: [String]
connDiff =
  [ show (m, f, rw, pc, req, e, ours, theirs, listed)
  | (m, f, rw, pc, req, e) <- connCases
  , let ours   = onConnection m f rw == RetryOnNewConnection
        theirs = Go.shouldRetryRequest pc req e
        listed = connDivergence m f rw (Go.header req)
  , not (agreesOffAndDiffersOn ours theirs (fmap snd listed))
  ]

-- Driver ---------------------------------------------------------------------

-- | Off the divergence set both sides agree; on it ours is the promised
-- answer and theirs is not.
agreesOffAndDiffersOn :: Eq a => a -> a -> Maybe a -> Bool
agreesOffAndDiffersOn ours theirs Nothing         = ours == theirs
agreesOffAndDiffersOn ours theirs (Just expected) = ours == expected && theirs /= expected

check :: String -> Int -> [String] -> IO Bool
check name points failures = do
  putStrLn (name ++ ": " ++ show points ++ " points checked, " ++ show (length failures) ++ " mismatches")
  mapM_ (putStrLn . ("  " ++)) (take 10 failures)
  pure (null failures)

main :: IO ()
main = do
  a <- check "onStatus vs urllib3 (method x status 100..599 x Retry-After shape)" statusPoints statusDiff
  b <- check "onStatus hint value vs urllib3 sleep, at each shape's representative (all values: LiquidHaskell)" statusPoints hintValueDiff
  c <- check "onConnection vs Go shouldRetryRequest (every realization)" (length connCases) connDiff
  d <- check "every onConnection input (method x fault x rewindable) has a Go realization" (9 * 4 * 2)
         [ show (m, f, rw) | m <- [minBound .. maxBound :: Method], f <- [minBound .. maxBound], rw <- [False, True]
                           , null (goFaults f) || null (goBodies rw) ]
  unless (and [a, b, c, d]) exitFailure
