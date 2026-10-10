{-# LANGUAGE Safe #-}
{-@ LIQUID "--reflection" @-}
{-@ LIQUID "--ple" @-}
-- | Conditional requests: evaluating each precondition header, then the
-- RFC 9110 13.2.2 ladder that decides between 412, 304 and going ahead.
--
-- The ladder is a port of Go's net/http checkPreconditions
-- (references/http-semantics/code/go/fs.go:640-671) with five fixes, each a
-- sentence of RFC 9110 that Go doesn't follow:
--
--   (a) a date If-Range is false ('ifRange');
--   (b) If-Match and If-Unmodified-Since only count at the origin ('ladder');
--   (c) Range, and with it If-Range, only for GET: Go keeps Range for HEAD
--       and for every unsafe method ('ladder');
--   (d) If-Match: * holds only when a representation exists ('ifMatch');
--   (e) If-None-Match: * fails only when one exists ('ifNoneMatch').
--
-- R HS:RFC9110-13.2.2-1, HS:RFC9110-13.2.1-2
module Funknown.Http.Precondition
  ( Seconds
  , Cond (..)
  , TagField (..)
  , RangeValidator (..)
  , MethodKind (..)
  , RangeReq (..)
  , Ranged (..)
  , Verdict (..)
  , Answer (..)
  , ifMatch
  , ifNoneMatch
  , ifUnmodifiedSince
  , ifModifiedSince
  , ifRange
  , rangeReq
  , preconditioned
  , ladder
    -- * RFC 9110 13.2.2, step by step, for specs
  , consultable
  , getOrHead
  , stepOneFails
  , stepTwoFails
  , passesOneTwo
  , stepFourFails
  , honoursRange
    -- * Theorems
  , nonOriginIgnores
  , goneIgnoresPreconditions
  ) where

import Funknown.Opt (Opt (..))
import Funknown.Proof (Proof, (?))
import Funknown.Http.Validator (EntityTag, strongMatch, weakMatch)

-- | An HTTP-date as whole seconds. The shell parses the date; one that isn't
-- a valid HTTP-date arrives as 'Absent'.
type Seconds = Int

-- | The evaluation of one precondition header. An ignored header is 'CAbsent'.
-- R HS:RFC9110-13.1.1-4, HS:RFC9110-13.1.2-5, HS:RFC9110-13.1.3-4,
--   HS:RFC9110-13.1.4-5, HS:RFC9110-13.1.5-5
data Cond = CAbsent | Holds | Fails
  deriving (Eq, Show)

-- | The value of If-Match or If-None-Match, parsed by the shell.
-- R HS:RFC9110-13.1.1-1, HS:RFC9110-13.1.2-1
data TagField = Star | Listed [EntityTag]
  deriving (Eq, Show)

-- | The value of If-Range: an entity-tag or an HTTP-date. The date itself is
-- never needed, because a date If-Range is always false (see 'ifRange').
-- R HS:RFC9110-13.1.5-4, HS:RFC9110-13.1.5-5
data RangeValidator = RangeTag EntityTag | RangeDate
  deriving (Eq, Show)

-- | The ladder treats GET and HEAD apart from every other method, and GET
-- apart from HEAD for ranges.
-- R HS:RFC9110-13.2.2-4, HS:RFC9110-13.2.2-5, HS:RFC9110-13.2.2-6, HS:RFC9110-14.2-2
data MethodKind = MGet | MHead | MUnsafe
  deriving (Eq, Show)

-- | Range and If-Range together. If-Range without Range is ignored, so it has
-- no constructor.
-- R HS:RFC9110-13.1.5-2
data RangeReq = NoRange | RangeOnly | RangeIfRange Cond
  deriving (Eq, Show)

-- | Whether the Range header field is still to be processed after the ladder.
-- R HS:RFC9110-13.2.2-6, HS:RFC9110-13.1.5-6, HS:RFC9110-14.2-2
data Ranged = Whole | ByRange
  deriving (Eq, Show)

-- | There is no "already applied" verdict: the only row that used one was a
-- DELETE of a deleted file, whose preconditions RFC 9110 requires us to ignore.
-- R HS:RFC9110-13.2.2-2, HS:RFC9110-13.2.2-3, HS:RFC9110-13.2.2-4,
--   HS:RFC9110-13.2.2-5, HS:RFC9110-13.2.2-7, HS:RFC9110-15.5.13
data Verdict = V412 | V304 | Proceed Ranged
  deriving (Eq, Show)

-- | What becomes of a request's preconditions: ignored, because the response
-- without them wouldn't be 2xx or 412, or evaluated.
-- R HS:RFC9110-13.2.1-2
data Answer = Unconditional | Conditional Verdict
  deriving (Eq, Show)

------------------------------------------------------------------------------
-- Evaluating each header

-- | If-Match against the selected representation's entity tag, 'Absent' when
-- there is no current representation. Fix (d): Go answers @*@ true even then.
-- R HS:RFC9110-13.1.1-4, HS:RFC9110-13.1.1-2 (strong comparison)
{-@ reflect ifMatch @-}
ifMatch :: Opt TagField -> Opt EntityTag -> Cond
ifMatch Absent                 _           = CAbsent
ifMatch (Present Star)         Absent      = Fails
ifMatch (Present Star)         (Present _) = Holds
ifMatch (Present (Listed _))   Absent      = Fails
ifMatch (Present (Listed ts))  (Present e) = if anyStrong e ts then Holds else Fails

-- | If-None-Match the same way. Fix (e): Go answers @*@ false even when there
-- is no current representation.
-- R HS:RFC9110-13.1.2-5, HS:RFC9110-13.1.2-2 (weak comparison)
{-@ reflect ifNoneMatch @-}
ifNoneMatch :: Opt TagField -> Opt EntityTag -> Cond
ifNoneMatch Absent                _           = CAbsent
ifNoneMatch (Present Star)        Absent      = Holds
ifNoneMatch (Present Star)        (Present _) = Fails
ifNoneMatch (Present (Listed _))  Absent      = Holds
ifNoneMatch (Present (Listed ts)) (Present e) = if anyWeak e ts then Fails else Holds

{-@ reflect anyStrong @-}
anyStrong :: EntityTag -> [EntityTag] -> Bool
anyStrong _ []       = False
anyStrong e (t : ts) = strongMatch t e || anyStrong e ts

{-@ reflect anyWeak @-}
anyWeak :: EntityTag -> [EntityTag] -> Bool
anyWeak _ []       = False
anyWeak e (t : ts) = weakMatch t e || anyWeak e ts

-- | If-Unmodified-Since against the last modification date. Without a date on
-- either side the header is ignored.
-- R HS:RFC9110-13.1.4-5, HS:RFC9110-13.1.4-2, HS:RFC9110-13.1.4-3
{-@ reflect ifUnmodifiedSince @-}
ifUnmodifiedSince :: Opt Seconds -> Opt Seconds -> Cond
ifUnmodifiedSince (Present d) (Present lm) = if lm <= d then Holds else Fails
ifUnmodifiedSince _           _            = CAbsent

-- | If-Modified-Since likewise. Ignoring it beside If-None-Match or on a
-- method other than GET and HEAD is the ladder's job.
-- R HS:RFC9110-13.1.3-4, HS:RFC9110-13.1.3-2, HS:RFC9110-13.1.3-3
{-@ reflect ifModifiedSince @-}
ifModifiedSince :: Opt Seconds -> Opt Seconds -> Cond
ifModifiedSince (Present d) (Present lm) = if lm <= d then Fails else Holds
ifModifiedSince _           _            = CAbsent

-- | If-Range against the selected representation's entity tag. Fix (a): a
-- date is never a strong validator here, because the rules that could make
-- one strong (HS:RFC9110-8.8.2.2) aren't vendored, so a date If-Range is false.
-- R HS:RFC9110-13.1.5-5, HS:RFC9110-13.1.5-4, HS:RFC9110-8.8.2.2
{-@ reflect ifRange @-}
ifRange :: Opt RangeValidator -> Opt EntityTag -> Cond
ifRange Absent                 _           = CAbsent
ifRange (Present RangeDate)    _           = Fails
ifRange (Present (RangeTag _)) Absent      = Fails
ifRange (Present (RangeTag t)) (Present e) = if strongMatch t e then Holds else Fails

-- | Pairs Range with the evaluated If-Range. If-Range without Range is ignored.
-- R HS:RFC9110-13.1.5-2
{-@ reflect rangeReq @-}
rangeReq :: Bool -> Cond -> RangeReq
rangeReq False _       = NoRange
rangeReq True  CAbsent = RangeOnly
rangeReq True  c       = RangeIfRange c

------------------------------------------------------------------------------
-- The ladder

-- What RFC 9110 13.2.2 says, one predicate per step, for the ladder's type.
-- They are written apart from the ladder's guards on purpose, so the
-- refinement states the RFC rather than restating the code. An inline
-- predicate can't call another one in this LiquidHaskell build ("Unbound
-- symbol"), which is why 'passesOneTwo' and 'stepFourFails' spell theirs out.

{-@ inline getOrHead @-}
getOrHead :: MethodKind -> Bool
getOrHead m = m == MGet || m == MHead

-- Step 1. R HS:RFC9110-13.2.2-2
{-@ inline stepOneFails @-}
stepOneFails :: Bool -> Cond -> Bool
stepOneFails o im = o && im == Fails

-- Step 2. R HS:RFC9110-13.2.2-3
{-@ inline stepTwoFails @-}
stepTwoFails :: Bool -> Cond -> Cond -> Bool
stepTwoFails o im ius = o && im == CAbsent && ius == Fails

{-@ inline passesOneTwo @-}
passesOneTwo :: Bool -> Cond -> Cond -> Bool
passesOneTwo o im ius = not (o && im == Fails) && not (o && im == CAbsent && ius == Fails)

-- Step 4. R HS:RFC9110-13.2.2-5
{-@ inline stepFourFails @-}
stepFourFails :: MethodKind -> Cond -> Cond -> Bool
stepFourFails m inm ims = (m == MGet || m == MHead) && inm == CAbsent && ims == Fails

-- Steps 5 and 6, with Range defined for GET only.
-- R HS:RFC9110-13.2.2-6, HS:RFC9110-13.2.2-7, HS:RFC9110-14.2-2
{-@ inline honoursRange @-}
honoursRange :: MethodKind -> RangeReq -> Bool
honoursRange m r = m == MGet && (r == RangeOnly || r == RangeIfRange Holds)

-- | The response this request would get without its preconditions is the
-- only thing that lets the ladder run at all.
-- R HS:RFC9110-13.2.1-2
{-@ inline consultable @-}
consultable :: Int -> Bool
consultable u = (200 <= u && u <= 299) || u == 412

-- | The ladder. Its first argument is the status the response would have
-- without its preconditions, and the type only accepts a 2xx or 412 there,
-- so no call site can consult a verdict for any other response (V4). The
-- second says whether we are the origin server; every call site passes True.
-- The refinement restates RFC 9110 13.2.2 steps 1 to 6 (V3); it pins the
-- verdict for every input, and a failed step 1 or 2 is always 412.
{-@ reflect ladder @-}
{-@ ladder :: {u:Int | consultable u} -> o:Bool -> m:MethodKind
           -> im:Cond -> ius:Cond -> inm:Cond -> ims:Cond -> r:RangeReq
           -> {v:Verdict |
                   (stepOneFails o im => v == V412)
                && (stepTwoFails o im ius => v == V412)
                && (passesOneTwo o im ius && inm == Fails && getOrHead m => v == V304)
                && (passesOneTwo o im ius && inm == Fails && not (getOrHead m) => v == V412)
                && (passesOneTwo o im ius && stepFourFails m inm ims => v == V304)
                && (passesOneTwo o im ius && inm /= Fails && not (stepFourFails m inm ims)
                      => ((v == Proceed ByRange) <=> honoursRange m r)
                      && ((v == Proceed Whole) <=> not (honoursRange m r))) } @-}
ladder :: Int -> Bool -> MethodKind -> Cond -> Cond -> Cond -> Cond -> RangeReq -> Verdict
ladder _ o m im ius inm ims r
  -- Go fs.go:642-649, with fix (b): only the origin evaluates these two.
  | o && im == Fails                    = V412
  | o && im == CAbsent && ius == Fails  = V412
  -- fs.go:650-658
  | inm == Fails                        = if m == MUnsafe then V412 else V304
  -- fs.go:659-663; Go's checkIfModifiedSince carries the method test.
  | inm == CAbsent && m /= MUnsafe && ims == Fails = V304
  -- fs.go:666-670, with fix (c): only GET processes Range or If-Range.
  | otherwise                           = Proceed (ranged m r)

{-@ reflect ranged @-}
ranged :: MethodKind -> RangeReq -> Ranged
ranged MGet RangeOnly               = ByRange
ranged MGet (RangeIfRange Holds)    = ByRange
ranged _    _                       = Whole

-- | The only way the stateful core consults preconditions: it says what it
-- would answer without them, and gets back either that the preconditions
-- don't apply or the ladder's verdict.
{-@ reflect preconditioned @-}
{-@ preconditioned :: u:{Int | 100 <= u && u <= 599} -> o:Bool -> m:MethodKind
                   -> im:Cond -> ius:Cond -> inm:Cond -> ims:Cond -> r:RangeReq
                   -> {a:Answer | (not (consultable u) => a == Unconditional)
                               && (consultable u => a == Conditional (ladder u o m im ius inm ims r))} @-}
preconditioned :: Int -> Bool -> MethodKind -> Cond -> Cond -> Cond -> Cond -> RangeReq -> Answer
-- The guard restates 'consultable' rather than calling it, so a wrong guard
-- is caught by the ladder's precondition instead of agreeing with itself.
preconditioned u o m im ius inm ims r
  | successful || u == 412 = Conditional (ladder u o m im ius inm ims r)
  | otherwise              = Unconditional
  where
    successful = 200 <= u && u <= 299

-- | A server that isn't the origin ignores If-Match and If-Unmodified-Since.
-- R HS:RFC9110-13.2.2-2, HS:RFC9110-13.2.2-3
{-@ nonOriginIgnores :: u:{Int | consultable u} -> m:MethodKind
      -> im:Cond -> ius:Cond -> inm:Cond -> ims:Cond -> r:RangeReq
      -> {ladder u False m im ius inm ims r == ladder u False m CAbsent CAbsent inm ims r} @-}
nonOriginIgnores :: Int -> MethodKind -> Cond -> Cond -> Cond -> Cond -> RangeReq -> Proof
nonOriginIgnores u m im ius inm ims r =
  () ? ladder u False m im ius inm ims r ? ladder u False m CAbsent CAbsent inm ims r

-- | V4's example: a DELETE on a DELETED file would be 410 without its
-- preconditions, so they are ignored whatever they say.
-- R HS:RFC9110-13.2.1-2, HS:RFC9110-15.5.11-1
{-@ goneIgnoresPreconditions :: o:Bool -> m:MethodKind
      -> im:Cond -> ius:Cond -> inm:Cond -> ims:Cond -> r:RangeReq
      -> {preconditioned 410 o m im ius inm ims r == Unconditional} @-}
goneIgnoresPreconditions :: Bool -> MethodKind -> Cond -> Cond -> Cond -> Cond -> RangeReq -> Proof
goneIgnoresPreconditions o m im ius inm ims r = () ? preconditioned 410 o m im ius inm ims r
