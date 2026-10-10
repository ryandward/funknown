{-# LANGUAGE Safe #-}
{-@ LIQUID "--reflection" @-}
{-@ LIQUID "--ple" @-}
-- | A literal transcription of urllib3's retry rule for a received status,
-- from references/http-semantics/code/urllib3/retry.py, bugs included. Python
-- names are kept. Only what 'is_retry' and 'sleep' read is transcribed.
--
-- Two things cross the boundary already parsed, the way the shell hands them
-- to the core: the Retry-After value (the regex at :311 and email.utils at
-- :314-318 run in the shell), and an HTTP-date's distance from now
-- (@retry_date - time.time()@ at :319), which arrives in whole seconds where
-- Python has a float.
--
-- The specs below are checked by LiquidHaskell in a separate component; the
-- test-suite compiles this file without the plugin, where they are comments.
module Port.Urllib3
  ( PyOptional (..)
  , Total (..)
  , Retry (..)
  , default_allowed_methods
  , retry_after_status_codes
  , retry
  , retry_DEFAULT
  , is_retry
  , RetryAfterValue (..)
  , parse_retry_after
  , get_retry_after
  , sleep_for_retry
  , Sleep (..)
  , sleep
  , sleepNone
  , sleepDigits
  , sleepDate
  ) where

import Data.Char (toUpper)

-- | Python's @X | None@. Not 'Maybe', because LiquidHaskell specs can't name
-- 'Maybe' in this build (design rule 2).
data PyOptional a = PyNone | PySome a
  deriving (Eq, Show)

-- | retry.py:204, @total: bool | int | None = 10@.
data Total = TotalBool Bool | TotalInt Int | TotalNone
  deriving (Eq, Show)

-- Python truthiness of @self.total@ (used at retry.py:403).
truthy_total :: Total -> Bool
truthy_total (TotalBool b) = b
truthy_total (TotalInt n)  = n /= 0
truthy_total TotalNone     = False

-- | The fields of a Retry that is_retry and sleep read (retry.py:223-241).
data Retry = Retry
  { total                      :: Total
  , allowed_methods            :: PyOptional [String]
  , status_forcelist           :: [Int]
  , respect_retry_after_header :: Bool
  }
  deriving (Eq, Show)
{-@ data Retry = Retry
      { total :: Total, allowed_methods :: PyOptional [String], status_forcelist :: [Int]
      , respect_retry_after_header :: Bool } @-}

-- | retry.py:184-186
default_allowed_methods :: [String]
default_allowed_methods = ["HEAD", "GET", "PUT", "DELETE", "OPTIONS", "TRACE"]

-- | retry.py:189
retry_after_status_codes :: [Int]
retry_after_status_codes = [413, 429, 503]

-- | retry.py:202-245, called with @total@ and every other argument at its
-- default: @allowed_methods=DEFAULT_ALLOWED_METHODS@ (:210),
-- @status_forcelist=None@ (:211) so @self.status_forcelist = None or set()@
-- (:234), and @respect_retry_after_header=True@ (:217).
retry :: Total -> Retry
retry t = Retry
  { total                      = t
  , allowed_methods            = PySome default_allowed_methods
  , status_forcelist           = []
  , respect_retry_after_header = True
  }

-- | retry.py:533, @Retry.DEFAULT = Retry(3)@.
retry_DEFAULT :: Retry
retry_DEFAULT = retry (TotalInt 3)

-- | retry.py:379-385
_is_method_retryable :: Retry -> String -> Bool
_is_method_retryable self method =
  case allowed_methods self of
    PySome ms | not (null ms) && map toUpper method `notElem` ms -> False
    _                                                          -> True

-- | retry.py:387-407
is_retry :: Retry -> String -> Int -> Bool -> Bool
is_retry self method status_code has_retry_after
  | not (_is_method_retryable self method) = False
  | not (null (status_forcelist self)) && status_code `elem` status_forcelist self = True
  | otherwise =
      truthy_total (total self)
        && respect_retry_after_header self
        && has_retry_after
        && status_code `elem` retry_after_status_codes

-- | What retry.py:311-319 extracts from the header: the digits matched at
-- :311 (non-negative, since the regex admits only @[0-9]+@), or an
-- HTTP-date's distance from now.
data RetryAfterValue = MatchedDigits Int | ParsedDate Int
  deriving (Eq, Show)
{-@ data RetryAfterValue = MatchedDigits { matchedDigits :: Nat } | ParsedDate { parsedDate :: Int } @-}

-- Python's @max(a, b)@ on numbers: the first argument unless the second is larger.
{-@ reflect py_max @-}
py_max :: Int -> Int -> Int
py_max a b = if b > a then b else a

-- | retry.py:308-323
{-@ reflect parse_retry_after @-}
parse_retry_after :: RetryAfterValue -> Int
parse_retry_after retry_after =
  let seconds = case retry_after of
        MatchedDigits n  -> n           -- :312 seconds = int(retry_after)
        ParsedDate delta -> delta       -- :318-319 seconds = retry_date - time.time()
  in py_max seconds 0                   -- :321 seconds = max(seconds, 0)

-- | retry.py:325-333; the argument is @response.headers.get("Retry-After")@.
{-@ reflect get_retry_after @-}
get_retry_after :: PyOptional RetryAfterValue -> PyOptional Int
get_retry_after PyNone             = PyNone
get_retry_after (PySome retry_after) = PySome (parse_retry_after retry_after)

-- | retry.py:335-341. 'PySome' is how long it slept; 'PyNone' is @return False@.
{-@ reflect sleep_for_retry @-}
sleep_for_retry :: PyOptional RetryAfterValue -> PyOptional Int
sleep_for_retry header =
  case get_retry_after header of
    PySome retry_after | retry_after /= 0 -> PySome retry_after   -- :337 if retry_after:
    _                                     -> PyNone

-- | Which sleep 'sleep' ends in.
data Sleep = SleptRetryAfter Int | SleptBackoff
  deriving (Eq, Show)

-- | retry.py:349-363, for a call with a response (so @and response@ at :358
-- holds).
{-@ reflect sleep @-}
sleep :: Retry -> PyOptional RetryAfterValue -> Sleep
sleep self header =
  if respect_retry_after_header self
    then case sleep_for_retry header of
           PySome s -> SleptRetryAfter s    -- :360-361 if slept: return
           PyNone   -> SleptBackoff         -- :363 self._sleep_backoff()
    else SleptBackoff

-- Lemmas over every value, which let the diff take one value per Retry-After
-- shape. They are about the transcription, not about urllib3's intent.

-- | No Retry-After: backoff.
{-@ sleepNone :: self:{Retry | respect_retry_after_header self} -> {sleep self PyNone == SleptBackoff} @-}
sleepNone :: Retry -> ()
sleepNone _ = ()

-- | Delay-seconds: every positive value is slept as given, and 0 falls through
-- to backoff (the truthiness test at :337).
{-@ sleepDigits :: self:{Retry | respect_retry_after_header self} -> n:Nat
                -> {sleep self (PySome (MatchedDigits n)) == (if n > 0 then SleptRetryAfter n else SleptBackoff)} @-}
sleepDigits :: Retry -> Int -> ()
sleepDigits _ n = if n > 0 then () else ()

-- | An HTTP-date: every future date is slept until, and every past date and
-- now fall through to backoff (:321 clamps to 0, :337 treats 0 as absent).
{-@ sleepDate :: self:{Retry | respect_retry_after_header self} -> d:Int
              -> {sleep self (PySome (ParsedDate d)) == (if d > 0 then SleptRetryAfter d else SleptBackoff)} @-}
sleepDate :: Retry -> Int -> ()
sleepDate _ d = if d > 0 then () else ()
