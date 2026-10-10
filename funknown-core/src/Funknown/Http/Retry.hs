{-# LANGUAGE Safe #-}
{-@ LIQUID "--reflection" @-}
{-@ LIQUID "--ple" @-}
-- | When a request is repeated, and how long the core waits first.
--
-- Adopting gRFC A6 for calls that aren't gRPC is our choice (C CH31); once
-- adopted, its rules are Required of us, which is why the A6 bases below are R.
-- Origin statuses follow a port of urllib3's rule (test/Port/Urllib3.hs) and
-- connection failures a port of Go's transport (test/Port/GoTransport.hs).
module Funknown.Http.Retry
  ( -- * Retry-After, as the shell hands it over
    RetryAfter (..)
  , Shape (..)
  , shapeOf
  , hintOf
  , hintOfAbsent
  , hintOfDelay
  , hintOfPastOrNow
  , hintOfFuture
    -- * Decisions
  , Decision (..)
  , Kind (..)
  , kindOf
  , onStatus
  , statusSpecDetermines
  , representative
  , representativeHasShape
  , onStatusShapeDecides
  , ConnFault (..)
  , onConnection
  , connSpecDetermines
    -- * Attempts
  , attemptCap
  , maxAttemptsOf
  , maxAttemptsSpecDetermines
    -- * Backoff
  , backoffBound
  , Backoff (..)
  , backoff
  , power
  , backoffClosedForm
  , Wait (..)
  , nextWait
    -- * The store's token bucket
  , milliPerToken
  , Throttle (..)
  , newThrottle
  , Delta (..)
  , applyDelta
  , retryAllowed
  ) where

import Funknown.Http.Method (Method (..), idempotent)
import Funknown.Opt -- whole module: isPresent is used only in specs
import Funknown.Proof (Proof, QED (..), (===), (***), (?))

-- Retry-After ---------------------------------------------------------------

-- | A Retry-After field as the shell parsed it. The field is an HTTP-date or
-- delay-seconds (R HS:RFC9110-10.2.3-5), and
-- delay-seconds is a non-negative integer (R HS:RFC9110-10.2.3-6,
-- HS:RFC9110-10.2.3-7), hence 'Nat'. The core has no clock, so the shell
-- hands a date over as its signed distance from now in seconds: negative is
-- past, zero is now, positive is future. An invalid field arrives as
-- 'NoRetryAfter', because the shell drops invalid fields.
data RetryAfter = NoRetryAfter | DelaySeconds Int | DateDelta Int
  deriving (Eq, Show)
{-@ data RetryAfter = NoRetryAfter | DelaySeconds { delaySeconds :: Nat } | DateDelta { dateDelta :: Int } @-}

-- | The classes of Retry-After values that some rule in this module or in
-- urllib3 tells apart. The port diff enumerates these; 'onStatusShapeDecides'
-- is what makes one value per class stand for the whole class on our side.
data Shape
  = ShapeAbsent
  | ShapeDelayZero
  | ShapeDelayPositive
  | ShapeDatePast
  | ShapeDateNow
  | ShapeDateFuture
  deriving (Eq, Show, Enum, Bounded)

{-@ reflect shapeOf @-}
shapeOf :: RetryAfter -> Shape
shapeOf NoRetryAfter = ShapeAbsent
shapeOf (DelaySeconds d)
  | d == 0    = ShapeDelayZero
  | otherwise = ShapeDelayPositive
shapeOf (DateDelta n)
  | n < 0     = ShapeDatePast
  | n == 0    = ShapeDateNow
  | otherwise = ShapeDateFuture

-- | The delay a retry waits when the server named one. A delay is used as
-- given (R SS:GRFC-A6-Pushback-3, applied to Retry-After by C CH31); a date
-- already reached asks for no wait at all, so it clamps to 0 (C CH31), the
-- same clamp as urllib3's @max(seconds, 0)@ (retry.py:321).
{-@ reflect hintOf @-}
{-@ hintOf :: RetryAfter -> Opt Nat @-}
hintOf :: RetryAfter -> Opt Int
hintOf NoRetryAfter     = Absent
hintOf (DelaySeconds d) = Present d
hintOf (DateDelta n)    = if n > 0 then Present n else Present 0

-- | No field, no hint: the retry waits for backoff.
{-@ hintOfAbsent :: {hintOf NoRetryAfter == Absent} @-}
hintOfAbsent :: Proof
hintOfAbsent = ()

-- | Every delay-seconds value is used exactly, whatever its size.
{-@ hintOfDelay :: d:Nat -> {hintOf (DelaySeconds d) == Present d} @-}
hintOfDelay :: Int -> Proof
hintOfDelay _ = ()

-- | Every date in the past, and a date equal to now, means retry now.
{-@ hintOfPastOrNow :: n:{Int | n <= 0} -> {hintOf (DateDelta n) == Present 0} @-}
hintOfPastOrNow :: Int -> Proof
hintOfPastOrNow _ = ()

-- | Every future date means wait until it.
{-@ hintOfFuture :: n:{Int | n > 0} -> {hintOf (DateDelta n) == Present n} @-}
hintOfFuture :: Int -> Proof
hintOfFuture _ = ()

-- Decisions -----------------------------------------------------------------

-- | What to do about a failed attempt.
--
-- * 'RetryIn' repeats on any usable connection, after the server's delay when
--   it named one ('Present'), and after the next backoff interval otherwise
--   ('Absent'); 'nextWait' consumes the hint as is.
--   Basis: R SS:GRFC-A6-Pushback-3; C CH31.
-- * 'RetryOnNewConnection' repeats over a different connection.
--   Basis: P HS:RFC9110-15.5.20-2 (PM5) for 421; C CH31 for connection faults.
-- * 'DoNotRetry'. Basis: C CH31, every retry rule here is an exception to it.
data Decision = RetryIn (Opt Int) | RetryOnNewConnection | DoNotRetry
  deriving (Eq, Show)
{-@ data Decision = RetryIn { retryHint :: Opt Nat } | RetryOnNewConnection | DoNotRetry @-}

-- | A decision with the delay value forgotten, which is what the port diffs
-- compare once the value itself is proved symbolically.
data Kind = Stop | AfterHint | AfterBackoff | NewConnection
  deriving (Eq, Show, Enum, Bounded)

{-@ reflect kindOf @-}
kindOf :: Decision -> Kind
kindOf DoNotRetry               = Stop
kindOf RetryOnNewConnection     = NewConnection
kindOf (RetryIn Absent)         = AfterBackoff
kindOf (RetryIn (Present _))    = AfterHint

-- | urllib3's Retry-After statuses (retry.py:189), ported as our own rule.
{-@ reflect waitsForRetryAfter @-}
waitsForRetryAfter :: Int -> Bool
waitsForRetryAfter c = c == 413 || c == 429 || c == 503

{-@ reflect hasRetryAfter @-}
hasRetryAfter :: RetryAfter -> Bool
hasRetryAfter NoRetryAfter     = False
hasRetryAfter (DelaySeconds _) = True
hasRetryAfter (DateDelta _)    = True

-- | Whether to repeat a request after a status received from an origin. The
-- store's answers arrive classified by the adapter and never come here. The
-- rules run in order:
--
-- 1. 507 is never repeated: R HS:RFC4918-11.5-2, an import fetch counting as
--    the result of the user's StartImport (C CH31). urllib3's defaults never
--    retry 507 either, so this rule only keeps a later rule from doing it.
-- 2. 421 is repeated on a new connection for any method: P HS:RFC9110-15.5.20-2 (PM5).
-- 3. A non-idempotent method is not repeated: P HS:RFC9110-9.2.2-4 (PM3).
-- 4. 425 is repeated: P HS:RFC8470-5.2-2 (PM5).
-- 5. 408 may be repeated: P HS:RFC9110-15.5.9-2 (PM5).
-- 6. 413, 429 and 503 are repeated when they carry Retry-After, and nothing
--    else is: C CH31, urllib3's rule (retry.py:387-407).
--
-- Rules 4 and 5 honour a Retry-After the server sent with them, since the
-- field says how long to wait before a follow-up request on any response
-- (HS:RFC9110-10.2.3-1); using it there is C CH31.
--
-- The postcondition 'StatusSpec' is the rule list itself, and
-- 'statusSpecDetermines' proves it allows one decision at every point, so no
-- other function could satisfy it. V6's clauses follow from it. It spells
-- the statuses and the field out rather than naming the helpers the code
-- uses, so a change to a helper can't move the code and the spec together.
{-@ predicate StatusSpec M C A V =
         ((C == 507 => V == DoNotRetry)
       && ((C /= 507 && C == 421) => V == RetryOnNewConnection)
       && ((C /= 507 && C /= 421 && not (idempotent M)) => V == DoNotRetry)
       && ((C /= 507 && C /= 421 && idempotent M
            && (C == 425 || C == 408 || ((C == 413 || C == 429 || C == 503) && A /= NoRetryAfter)))
           => V == RetryIn (hintOf A))
       && ((C /= 421 && C /= 425 && C /= 408 && not ((C == 413 || C == 429 || C == 503) && A /= NoRetryAfter))
           => V == DoNotRetry)) @-}
{-@ reflect onStatus @-}
{-@ onStatus :: m:Method -> c:{Int | 100 <= c && c <= 599} -> a:RetryAfter
             -> {v:Decision | StatusSpec m c a v} @-}
onStatus :: Method -> Int -> RetryAfter -> Decision
onStatus m c a = act (statusRule m c (hasRetryAfter a)) (hintOf a)

-- | 'StatusSpec' is complete: any decision it allows is 'onStatus''s.
{-@ statusSpecDetermines :: m:Method -> c:{Int | 100 <= c && c <= 599} -> a:RetryAfter
                         -> v:{Decision | StatusSpec m c a v} -> {v == onStatus m c a} @-}
statusSpecDetermines :: Method -> Int -> RetryAfter -> Decision -> Proof
statusSpecDetermines m c a _ = () ? onStatus m c a

-- | Which of the three things to do. The rules see only whether a
-- Retry-After was sent; its value only reaches the decision as the hint.
data Rule = Halt | Fresh | Again

{-@ reflect statusRule @-}
{-@ statusRule :: m:Method -> c:Int -> p:Bool
               -> {v:Rule | (c == 507 => v == Halt)
                         && ((c /= 507 && c == 421) => v == Fresh)
                         && ((c /= 507 && c /= 421 && not (idempotent m)) => v == Halt)
                         && ((c /= 507 && c /= 421 && idempotent m
                              && (c == 425 || c == 408 || ((c == 413 || c == 429 || c == 503) && p)))
                             => v == Again)
                         && ((c /= 421 && c /= 425 && c /= 408 && not ((c == 413 || c == 429 || c == 503) && p))
                             => v == Halt)
                         && (v == Fresh => c == 421)} @-}
statusRule :: Method -> Int -> Bool -> Rule
statusRule m c present
  | c == 507                               = Halt
  | c == 421                               = Fresh
  | not (idempotent m)                     = Halt
  | c == 425                               = Again
  | c == 408                               = Again
  | waitsForRetryAfter c && present        = Again
  | otherwise                              = Halt

{-@ reflect act @-}
{-@ act :: r:Rule -> h:Opt Nat
        -> {v:Decision | (r == Halt => v == DoNotRetry) && (r == Fresh => v == RetryOnNewConnection)
                      && (r == Again => v == RetryIn h)} @-}
act :: Rule -> Opt Int -> Decision
act Halt  _ = DoNotRetry
act Fresh _ = RetryOnNewConnection
act Again h = RetryIn h

-- The kind of an action depends on the hint only through whether there is one.
{-@ actKind :: r:Rule -> g:Opt Nat -> h:{Opt Nat | isPresent g == isPresent h}
            -> {kindOf (act r g) == kindOf (act r h)} @-}
actKind :: Rule -> Opt Int -> Opt Int -> Proof
actKind Halt  _           _           = ()
actKind Fresh _           _           = ()
actKind Again Absent      Absent      = ()
actKind Again (Present _) (Present _) = ()
actKind Again Absent      (Present _) = ()
actKind Again (Present _) Absent      = ()

-- | One Retry-After value standing for each shape.
{-@ reflect representative @-}
representative :: Shape -> RetryAfter
representative ShapeAbsent        = NoRetryAfter
representative ShapeDelayZero     = DelaySeconds 0
representative ShapeDelayPositive = DelaySeconds 1
representative ShapeDatePast      = DateDelta (-1)
representative ShapeDateNow       = DateDelta 0
representative ShapeDateFuture    = DateDelta 1

-- | Each representative has the shape it stands for.
{-@ representativeHasShape :: s:Shape -> {shapeOf (representative s) == s} @-}
representativeHasShape :: Shape -> Proof
representativeHasShape ShapeAbsent        = ()
representativeHasShape ShapeDelayZero     = ()
representativeHasShape ShapeDelayPositive = ()
representativeHasShape ShapeDatePast      = ()
representativeHasShape ShapeDateNow       = ()
representativeHasShape ShapeDateFuture    = ()

-- | Every Retry-After value gets the same kind of decision as its shape's
-- representative, for every method and status, whatever the delay or the
-- date. With the postcondition on 'onStatus' (the hint is 'hintOf' the field)
-- this is what lets the port diff check one value per shape and still cover
-- every value.
{-@ onStatusShapeDecides :: m:Method -> c:{Int | 100 <= c && c <= 599} -> a:RetryAfter
                         -> {kindOf (onStatus m c a) == kindOf (onStatus m c (representative (shapeOf a)))} @-}
onStatusShapeDecides :: Method -> Int -> RetryAfter -> Proof
onStatusShapeDecides m c a = case sameShapeSamePresence a of
  () -> actKind (statusRule m c (hasRetryAfter a)) (hintOf a) (hintOf r)
  where
    r = representative (shapeOf a)

-- A value and its shape's representative agree on whether a Retry-After was
-- sent and on whether it carries a hint.
{-@ sameShapeSamePresence :: a:RetryAfter
      -> {hasRetryAfter a == hasRetryAfter (representative (shapeOf a))
          && isPresent (hintOf a) == isPresent (hintOf (representative (shapeOf a)))} @-}
sameShapeSamePresence :: RetryAfter -> Proof
sameShapeSamePresence NoRetryAfter = ()
sameShapeSamePresence (DelaySeconds d)
  | d == 0    = ()
  | otherwise = ()
sameShapeSamePresence (DateDelta n)
  | n < 0     = ()
  | n == 0    = ()
  | otherwise = ()

-- | How an attempt failed before any response arrived, as the shell observed it.
--
-- * 'NothingWritten': no byte of the request reached a reused connection, so
--   the request was never applied, which is the "means to detect" that lets a
--   non-idempotent request be repeated: P HS:RFC9110-9.2.2-4 (PM3).
-- * 'ReadFailed': a reused connection failed before the first response byte
--   (go/transport.go:789-793). Only idempotent requests are repeated:
--   R HS:RFC9110-9.2.2-1 (the definition, PUT and DELETE included); P HS:RFC9110-9.2.2-4 (PM3).
-- * 'IdleClosed': the server closed an idle reused connection as the request
--   went out (go/transport.go:794-799); the same rule as 'ReadFailed'.
-- * 'FreshConnClosed': any failure on a connection made for this request.
--   It is never repeated, so a server that hangs up on a request can't drive
--   an endless loop of new connections (go/transport.go:770-779): C CH31.
data ConnFault = NothingWritten | ReadFailed | IdleClosed | FreshConnClosed
  deriving (Eq, Show, Enum, Bounded)

-- | Whether to repeat a request after a connection fault, given whether its
-- body can be sent again. The single automatic retry (P HS:RFC9110-9.2.2-8,
-- PM4) is the caller's flag, not this function's. The postcondition fixes
-- the decision at every input: a retry happens exactly when the body can be
-- re-sent and either nothing was written or a reused connection failed on an
-- idempotent request. V7's "never on a fresh connection" follows from it.
{-@ predicate ConnSpec M F R V =
         ((V == DoNotRetry || V == RetryOnNewConnection)
       && (V == RetryOnNewConnection
           <=> (R && (F == NothingWritten || ((F == ReadFailed || F == IdleClosed) && idempotent M))))) @-}
{-@ reflect onConnection @-}
{-@ onConnection :: m:Method -> f:ConnFault -> rewindable:Bool -> {v:Decision | ConnSpec m f rewindable v} @-}
onConnection :: Method -> ConnFault -> Bool -> Decision
onConnection m f rewindable = if rewindable then onFault m f else DoNotRetry

-- The rule for a body that can be sent again.
{-@ reflect onFault @-}
{-@ onFault :: m:Method -> f:ConnFault
            -> {v:Decision | (v == DoNotRetry || v == RetryOnNewConnection)
                          && (v == RetryOnNewConnection
                              <=> (f == NothingWritten || ((f == ReadFailed || f == IdleClosed) && idempotent m)))} @-}
onFault :: Method -> ConnFault -> Decision
onFault _ FreshConnClosed = DoNotRetry
onFault _ NothingWritten  = RetryOnNewConnection
onFault m ReadFailed      = ifIdempotent m
onFault m IdleClosed      = ifIdempotent m

{-@ reflect ifIdempotent @-}
{-@ ifIdempotent :: m:Method -> {v:Decision | (v == DoNotRetry || v == RetryOnNewConnection)
                                           && (v == RetryOnNewConnection <=> idempotent m)} @-}
ifIdempotent :: Method -> Decision
ifIdempotent m = if idempotent m then RetryOnNewConnection else DoNotRetry

-- | 'ConnSpec' is complete: any decision it allows is 'onConnection''s.
{-@ connSpecDetermines :: m:Method -> f:ConnFault -> r:Bool
                       -> v:{Decision | ConnSpec m f r v} -> {v == onConnection m f r} @-}
connSpecDetermines :: Method -> ConnFault -> Bool -> Decision -> Proof
connSpecDetermines m f r _ = () ? onConnection m f r

-- Attempts ------------------------------------------------------------------

-- | R SS:GRFC-A6-Validation-1: values above 5 are treated as 5.
{-@ inline attemptCap @-}
attemptCap :: Int
attemptCap = 5

{-@ type Attempts    = {n:Nat | n <= attemptCap} @-}
{-@ type MaxAttempts = {n:Int | 1 < n && n <= attemptCap} @-}
{-@ type BackoffStep = {n:Int | n >= 1} @-}

-- | A configured maxAttempts, which A6 requires above 1, as the value the
-- guards use: kept when it is at most 5, and 5 when it is above
-- (R SS:GRFC-A6-Validation-1).
{-@ predicate MaxAttemptsSpec N V =
         (1 < V && V <= 5 && (N <= 5 => V == N) && (N > 5 => V == 5)) @-}
{-@ reflect maxAttemptsOf @-}
{-@ maxAttemptsOf :: n:{Int | n > 1} -> {v:Int | MaxAttemptsSpec n v} @-}
maxAttemptsOf :: Int -> Int
maxAttemptsOf n = if n > attemptCap then attemptCap else n

-- | 'MaxAttemptsSpec' is complete: it allows one value for each n.
{-@ maxAttemptsSpecDetermines :: n:{Int | n > 1} -> v:{Int | MaxAttemptsSpec n v} -> {v == maxAttemptsOf n} @-}
maxAttemptsSpecDetermines :: Int -> Int -> Proof
maxAttemptsSpecDetermines n _ = () ? maxAttemptsOf n

-- Backoff -------------------------------------------------------------------

-- | 2^31. Both the cap and the multiplier stay under it, so the one product
-- 'grow' computes stays under 2^62 and can't overflow a machine Int, which
-- LiquidHaskell's unbounded integers wouldn't notice.
{-@ inline backoffBound @-}
backoffBound :: Int
backoffBound = 2147483648

-- | gRFC A6's backoff parameters, in whatever unit the caller's delay hints
-- use. A6 requires both durations above 0 and the multiplier above 0
-- (references/status-and-supervision/grpc/A6-client-retries.md:125-126). Two
-- refinements are ours (C CH31): the multiplier is a whole number of at least
-- 1, because the core has no fractions without division, and the initial
-- backoff is at most the cap, so A6's first retry after exactly
-- @initialBackoff@ and the design's cap on every wait can both hold.
data Backoff = Backoff { initialBackoff :: Int, maxBackoff :: Int, backoffMultiplier :: Int }
  deriving (Eq, Show)
{-@ data Backoff = Backoff
      { initialBackoff    :: {i:Int | 0 < i}
      , maxBackoff        :: {x:Int | initialBackoff <= x && x <= backoffBound}
      , backoffMultiplier :: {k:Int | 1 <= k && k <= backoffBound} } @-}

-- | One backoff interval after the one before, capped.
{-@ reflect grow @-}
{-@ grow :: c:Backoff -> {b:Int | 0 < b && b <= maxBackoff c} -> {d:Int | 0 < d && d <= maxBackoff c} @-}
grow :: Backoff -> Int -> Int
grow (Backoff _ x k) b = if b * k >= x then x else b * k

-- | The wait before a retry when the server named no delay, without jitter,
-- which is the shell's: R SS:GRFC-A6-Backoff; C CH31. Step 1 is the first
-- retry since the start or since the last delay hint.
{-@ reflect backoff @-}
{-@ backoff :: c:Backoff -> s:BackoffStep -> {d:Int | 0 < d && d <= maxBackoff c} / [s] @-}
backoff :: Backoff -> Int -> Int
backoff c@(Backoff i _ _) s
  | s <= 1    = i
  | otherwise = grow c (backoff c (s - 1))

-- | k^n, for stating A6's formula; never run.
{-@ reflect power @-}
{-@ power :: {k:Int | k >= 1} -> n:Nat -> {v:Int | v >= 1} / [n] @-}
power :: Int -> Int -> Int
power k n = if n == 0 then 1 else k * power k (n - 1)

-- | 'backoff' is A6's @min(initialBackoff*backoffMultiplier**(n-1), maxBackoff)@
-- for every step (R SS:GRFC-A6-Backoff).
{-@ backoffClosedForm :: c:Backoff -> s:BackoffStep
                      -> {backoff c s == (if initialBackoff c * power (backoffMultiplier c) (s - 1) <= maxBackoff c
                                           then initialBackoff c * power (backoffMultiplier c) (s - 1)
                                           else maxBackoff c)} / [s] @-}
backoffClosedForm :: Backoff -> Int -> Proof
backoffClosedForm c@(Backoff i x k) s
  | s <= 1    = backoff c s === i *** QED
  | otherwise =
      backoff c s
        === grow c (backoff c (s - 1)) ? backoffClosedForm c (s - 1) ? growPower i x k (s - 1)
        *** QED

-- The inductive step: capping before or after one more multiplication gives
-- the same result, because the multiplier is at least 1.
{-@ growPower :: i:{Int | 0 < i} -> x:{Int | i <= x} -> k:{Int | 1 <= k} -> n:Nat
              -> {(if (if i * power k n <= x then i * power k n else x) * k >= x
                    then x
                    else (if i * power k n <= x then i * power k n else x) * k)
                  == (if i * power k (n + 1) <= x then i * power k (n + 1) else x)} @-}
growPower :: Int -> Int -> Int -> Int -> Proof
growPower i x k n = monotone (i * power k n) x k ? (power k (n + 1) === k * power k n *** QED)

{-@ monotone :: a:Int -> x:{Int | 0 < x} -> k:{Int | 1 <= k} -> {a >= x => a * k >= x * k && x * k >= x} @-}
monotone :: Int -> Int -> Int -> Proof
monotone _ _ _ = ()

-- | The wait before a retry and the backoff step after it.
data Wait = Wait { waitFor :: Int, nextStep :: Int }
  deriving (Eq, Show)
{-@ data Wait = Wait { waitFor :: Nat, nextStep :: BackoffStep } @-}

-- | RE3: with a delay hint the wait is exactly the hint and the backoff step
-- goes back to 1 (R SS:GRFC-A6-Pushback-3); without one the wait is
-- @backoff c s@, never above the cap, and the step goes up by one
-- (R SS:GRFC-A6-Backoff). C CH31.
{-@ nextWait :: c:Backoff -> h:Opt Nat -> s:BackoffStep
             -> {w:Wait | (isPresent h => (nextStep w == 1 && h == Present (waitFor w)))
                       && (not (isPresent h) => (nextStep w == s + 1 && waitFor w == backoff c s
                                                 && waitFor w <= maxBackoff c))} @-}
nextWait :: Backoff -> Opt Int -> Int -> Wait
nextWait c Absent      s = Wait (backoff c s) (s + 1)
nextWait _ (Present h) _ = Wait h 1

-- The store's token bucket ---------------------------------------------------

-- | A6's tokenRatio keeps three decimal places
-- (references/status-and-supervision/grpc/A6-client-retries.md:199), so the
-- bucket counts in thousandths of a token and stays in whole numbers.
{-@ inline milliPerToken @-}
milliPerToken :: Int
milliPerToken = 1000

-- | The bucket for the store, in milli-tokens: R SS:GRFC-A6-Throttling-1,
-- SS:GRFC-A6-Throttling-2; C CH31. The cap is a field of its own so the
-- refinement on 'tokens' can name it (rule 9).
data Throttle = Throttle { maxTokens :: Int, tokenRatio :: Int, tokens :: Int }
  deriving (Eq, Show)
{-@ data Throttle = Throttle
      { maxTokens  :: {m:Int | m > 0}
      , tokenRatio :: {r:Int | r > 0}
      , tokens     :: {t:Int | 0 <= t && t <= maxTokens} } @-}

-- | A full bucket, which is where A6 starts it: R SS:GRFC-A6-Throttling-1.
{-@ newThrottle :: m:{Int | m > 0} -> r:{Int | r > 0}
                -> {v:Throttle | maxTokens v == m && tokenRatio v == r && tokens v == m} @-}
newThrottle :: Int -> Int -> Throttle
newThrottle m r = Throttle m r m

-- | How one store answer moves the bucket. Only a failure that a retry could
-- fix counts as failed (R SS:GRFC-A6-Throttling-3); which answers those are
-- is decided by @stepFile@, and stale reports are 'NoCall'.
data Delta = NoCall | CallFailed | CallSucceeded
  deriving (Eq, Show, Enum, Bounded)

-- | RE4, the bucket half: a failure takes one token and a success adds
-- tokenRatio, both clamped to [0, maxTokens] (R SS:GRFC-A6-Throttling-1).
-- The arithmetic is arranged so no intermediate value can overflow: @m - t@
-- and @t - 1000@ stay in range because @0 <= t <= m@. The spec writes the
-- token as 1000 rather than 'milliPerToken', so changing the constant fails it.
{-@ applyDelta :: d:Delta -> b:Throttle
               -> {v:Throttle | maxTokens v == maxTokens b && tokenRatio v == tokenRatio b
                             && (d == NoCall => tokens v == tokens b)
                             && ((d == CallFailed && tokens b >= 1000) => tokens v == tokens b - 1000)
                             && ((d == CallFailed && tokens b < 1000) => tokens v == 0)
                             && ((d == CallSucceeded && tokens b + tokenRatio b <= maxTokens b) => tokens v == tokens b + tokenRatio b)
                             && ((d == CallSucceeded && tokens b + tokenRatio b > maxTokens b) => tokens v == maxTokens b)} @-}
applyDelta :: Delta -> Throttle -> Throttle
applyDelta NoCall        b                = b
applyDelta CallFailed    (Throttle m r t) = Throttle m r (if t >= milliPerToken then t - milliPerToken else 0)
applyDelta CallSucceeded (Throttle m r t) = Throttle m r (if r <= m - t then t + r else m)

-- | RE4: retries are allowed exactly while the count is above maxTokens / 2
-- (R SS:GRFC-A6-Throttling-2). The test @t > m - t@ is @2t > m@ without a
-- division and without a product that could overflow.
{-@ retryAllowed :: b:Throttle -> {v:Bool | v <=> 2 * tokens b > maxTokens b} @-}
retryAllowed :: Throttle -> Bool
retryAllowed (Throttle m _ t) = t > m - t
