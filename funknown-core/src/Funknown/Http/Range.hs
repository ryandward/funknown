{-# LANGUAGE Safe #-}
{-@ LIQUID "--reflection" @-}
{-@ LIQUID "--ple" @-}
-- | Byte ranges on a GET for a file's content. The shell parses the Range
-- header into 'RangeSpec's; this module decides what that request selects
-- from a representation of @n@ bytes.
--
-- Nothing here has a precondition. The shell builds 'RangeSpec's without
-- LiquidHaskell, so a refinement on their fields or on @n@ would bind only
-- the callers that are checked; instead 'resolve' takes every 'Int' and
-- its claims hold for any caller GHC accepts.
--
-- RFC 9110 requires recipients to survive numerals of any size (R
-- HS:RFC9110-14.1.2-7), and the shell meets that by saturating an
-- over-long numeral at 'maxBound': every position at or past @n@ already
-- means the same thing to 'resolve', so saturating changes no answer.
module Funknown.Http.Range
  ( RangeSpec (..)
  , Resolved (..)
  , isSatisfied
  , isUnsatisfiable
  , resolve
  , resolveHeader
    -- * RFC 9110 section 14.1, one lemma per sentence
  , zeroLengthIgnored
  , negativeLengthIgnored
  , negativePositionIgnored
  , invalidIgnored
  , lastPosInclusive
  , lastPosClamped
  , lastPosAbsent
  , suffixSelectsLastBytes
  , longSuffixSelectsAll
  , firstPastEndUnsatisfiable
  , emptySuffixUnsatisfiable
    -- * The one-range decision
  , oneRangeResolved
  ) where

import Funknown.Proof (Proof)

-- | One byte-range-spec. The fields are plain 'Int': a negative one is not
-- a 1*DIGIT numeral, so 'resolve' ignores it rather than the type refusing it.
data RangeSpec
  = IntRange { intFirst :: Int, intLast :: Int }
    -- ^ R HS:RFC9110-14.1.1-1: first-pos "-" last-pos
  | OpenRange { openFirst :: Int }
    -- ^ R HS:RFC9110-14.1.1-1: first-pos "-", last-pos absent
  | Suffix { suffixLength :: Int }
    -- ^ R HS:RFC9110-14.1.1-3: "-" suffix-length
  deriving (Eq, Show)

-- | What a GET does with its Range.
data Resolved
  = Satisfied { first :: Int, lastPos :: Int }
    -- ^ a 206 for bytes first..lastPos, inclusive (R HS:RFC9110-14.1.2-1)
  | Unsatisfiable { completeLength :: Int }
    -- ^ a 416 carrying Content-Range: bytes */completeLength
    -- (R HS:RFC9110-15.5.17-1, HS:RFC9110-14.4-7; P HS:RFC9110-14.4-6,
    -- HS:RFC9110-15.5.17-2, PM31)
  | Ignore
    -- ^ served as if Range were absent (P HS:RFC9110-14.2-1,
    -- HS:RFC9110-14.2-4, HS:RFC9110-14.2-5, PM27)
  deriving (Eq, Show)

-- A 416 never answers a zero-length representation, because that is
-- Ignore, so its complete-length is positive.
{-@ data Resolved
      = Satisfied { first :: Nat, lastPos :: {v:Nat | first <= v} }
      | Unsatisfiable { completeLength :: {v:Nat | 0 < v} }
      | Ignore
  @-}

{-@ measure isSatisfied @-}
isSatisfied :: Resolved -> Bool
isSatisfied (Satisfied _ _)   = True
isSatisfied (Unsatisfiable _) = False
isSatisfied Ignore            = False

{-@ measure isUnsatisfiable @-}
isUnsatisfiable :: Resolved -> Bool
isUnsatisfiable (Satisfied _ _)   = False
isUnsatisfiable (Unsatisfiable _) = True
isUnsatisfiable Ignore            = False

-- | V5: a satisfied range lies inside the representation, a zero-length
-- representation ignores Range, and a 416 carries the current length.
--
-- The order of the tests is the order RFC 9110 needs: an invalid range is
-- not a valid ranges-specifier, so it is neither satisfiable nor
-- unsatisfiable (HS:RFC9110-14.1.1-5) and is ignored before the first-pos
-- test could call it unsatisfiable.
{-@ reflect resolve @-}
{-@ resolve :: n:Int -> RangeSpec
            -> {v:Resolved | (n <= 0 => v == Ignore)
                          && (isSatisfied v => lastPos v < n)
                          && (isUnsatisfiable v => completeLength v == n)} @-}
resolve :: Int -> RangeSpec -> Resolved
resolve n s =
  if n <= 0
    -- P HS:RFC9110-14.2-5 (PM27): no zero-byte 206, and no 416 for a
    -- client that sends Range on every request. A length below zero is no
    -- representation at all; it is answered the same way so that resolve
    -- has no precondition (C, no register entry yet).
    then Ignore
    else case s of
      IntRange f l ->
        if f < 0
          -- not a range-spec: first-pos is 1*DIGIT (R HS:RFC9110-14.1.1-1,
          -- HS:RFC9110-14.1.1-4), ignored by P HS:RFC9110-14.2-4 (PM27)
          then Ignore
          else if l < f
            -- invalid by R HS:RFC9110-14.1.1-2, ignored by P HS:RFC9110-14.2-4 (PM27)
            then Ignore
            else if f < n
              -- R HS:RFC9110-14.1.2-5 satisfiable; R HS:RFC9110-14.1.2-3 clamps last-pos
              then Satisfied f (if l < n then l else n - 1)
              else Unsatisfiable n
      OpenRange f ->
        if f < 0
          -- R HS:RFC9110-14.1.1-1, HS:RFC9110-14.1.1-4; P HS:RFC9110-14.2-4 (PM27)
          then Ignore
          else if f < n
            -- R HS:RFC9110-14.1.2-3: an absent last-pos is n - 1
            then Satisfied f (n - 1)
            else Unsatisfiable n
      Suffix k ->
        if k < 0
          -- suffix-length is 1*DIGIT (R HS:RFC9110-14.1.1-3,
          -- HS:RFC9110-14.1.1-4); P HS:RFC9110-14.2-4 (PM27)
          then Ignore
          else if k == 0
            -- R HS:RFC9110-14.1.2-5: only a non-zero suffix-length is satisfiable
            then Unsatisfiable n
            else if k < n
              then Satisfied (n - k) (n - 1)
              -- R HS:RFC9110-14.1.2-4: a long suffix selects the whole representation
              else Satisfied 0 (n - 1)

-- | The whole Range header. We serve exactly one range: several ranges, or
-- none, are served as if Range were absent (P HS:RFC9110-14.2-1,
-- HS:RFC9110-14.2-4, PM27), which keeps multipart/byteranges out of the core.
-- The type states the several-or-none half and 'oneRangeResolved' the one-range half.
{-@ reflect resolveHeader @-}
{-@ resolveHeader :: n:Int -> ss:[RangeSpec]
                  -> {v:Resolved | (len ss /= 1 => v == Ignore)
                                && (n <= 0 => v == Ignore)
                                && (isSatisfied v => lastPos v < n)
                                && (isUnsatisfiable v => completeLength v == n)} @-}
resolveHeader :: Int -> [RangeSpec] -> Resolved
resolveHeader n ss = case ss of
  []       -> Ignore
  s : rest -> case rest of
    []    -> resolve n s
    _ : _ -> Ignore

-- | A header with exactly one range-spec gets that range's answer.
{-@ oneRangeResolved :: n:Int -> s:RangeSpec -> {resolveHeader n [s] == resolve n s} @-}
oneRangeResolved :: Int -> RangeSpec -> Proof
oneRangeResolved _ _ = ()

-- The lemmas below state section 14.1 sentence by sentence, independently of
-- how 'resolve' orders its tests. Every (n, spec) over 'Int' falls under at
-- least one of them, and each fixes the answer, so together they determine
-- 'resolve'.

-- | P HS:RFC9110-14.2-5 (PM27).
{-@ zeroLengthIgnored :: s:RangeSpec -> {resolve 0 s == Ignore} @-}
zeroLengthIgnored :: RangeSpec -> Proof
zeroLengthIgnored _ = ()

-- | A negative length is no representation (C, no register entry yet).
{-@ negativeLengthIgnored :: n:{Int | n < 0} -> s:RangeSpec -> {resolve n s == Ignore} @-}
negativeLengthIgnored :: Int -> RangeSpec -> Proof
negativeLengthIgnored _ _ = ()

-- | R HS:RFC9110-14.1.1-1, HS:RFC9110-14.1.1-3: positions and suffix lengths
-- are 1*DIGIT, so a negative one makes no range-spec, and the specifier is
-- invalid (R HS:RFC9110-14.1.1-4) and ignored (P HS:RFC9110-14.2-4, PM27).
{-@ negativePositionIgnored :: n:Int -> p:{Int | p < 0} -> l:Int
      -> {resolve n (IntRange p l) == Ignore
          && resolve n (OpenRange p) == Ignore
          && resolve n (Suffix p) == Ignore} @-}
negativePositionIgnored :: Int -> Int -> Int -> Proof
negativePositionIgnored n _ _
  | n <= 0    = ()
  | otherwise = ()

-- | R HS:RFC9110-14.1.1-2 defines it as invalid; P HS:RFC9110-14.2-4 (PM27)
-- ignores it, whether or not first-pos is inside the representation.
{-@ invalidIgnored :: n:Int -> f:Nat -> l:{Int | l < f}
                   -> {resolve n (IntRange f l) == Ignore} @-}
invalidIgnored :: Int -> Int -> Int -> Proof
invalidIgnored n _ _
  | n <= 0    = ()
  | otherwise = ()

-- | R HS:RFC9110-14.1.2-1: positions are inclusive offsets from zero, so a
-- last-pos inside the representation is kept as sent.
{-@ lastPosInclusive :: n:Nat -> f:Nat -> l:{Nat | f <= l && l < n}
                     -> {resolve n (IntRange f l) == Satisfied f l} @-}
lastPosInclusive :: Int -> Int -> Int -> Proof
lastPosInclusive _ _ _ = ()

-- | R HS:RFC9110-14.1.2-3: a last-pos at or past the current length is
-- replaced by one less than the length.
{-@ lastPosClamped :: n:Nat -> f:{Nat | f < n} -> l:{Nat | f <= l && n <= l}
                   -> {resolve n (IntRange f l) == Satisfied f (n - 1)} @-}
lastPosClamped :: Int -> Int -> Int -> Proof
lastPosClamped _ _ _ = ()

-- | R HS:RFC9110-14.1.2-3: an absent last-pos is one less than the length.
{-@ lastPosAbsent :: n:Nat -> f:{Nat | f < n}
                  -> {resolve n (OpenRange f) == Satisfied f (n - 1)} @-}
lastPosAbsent :: Int -> Int -> Proof
lastPosAbsent _ _ = ()

-- | R HS:RFC9110-14.1.2-4: a suffix-range selects the last N bytes, N > 0.
-- Stated by what it selects: it ends at the last byte and spans N bytes.
{-@ suffixSelectsLastBytes :: n:Nat -> k:{Nat | 0 < k && k < n}
      -> {isSatisfied (resolve n (Suffix k))
          && lastPos (resolve n (Suffix k)) == n - 1
          && lastPos (resolve n (Suffix k)) - first (resolve n (Suffix k)) + 1 == k} @-}
suffixSelectsLastBytes :: Int -> Int -> Proof
suffixSelectsLastBytes _ _ = ()

-- | R HS:RFC9110-14.1.2-4: a suffix at least as long as the representation
-- selects all of it.
{-@ longSuffixSelectsAll :: n:{Nat | 0 < n} -> k:{Nat | n <= k}
                         -> {resolve n (Suffix k) == Satisfied 0 (n - 1)} @-}
longSuffixSelectsAll :: Int -> Int -> Proof
longSuffixSelectsAll _ _ = ()

-- | R HS:RFC9110-14.1.2-5: a valid int-range is satisfiable only with a
-- first-pos below the length; otherwise the answer is 416 with */n
-- (P HS:RFC9110-14.4-6, PM31).
{-@ firstPastEndUnsatisfiable :: n:{Nat | 0 < n} -> f:{Nat | n <= f} -> l:{Nat | f <= l}
      -> {resolve n (IntRange f l) == Unsatisfiable n && resolve n (OpenRange f) == Unsatisfiable n} @-}
firstPastEndUnsatisfiable :: Int -> Int -> Int -> Proof
firstPastEndUnsatisfiable _ _ _ = ()

-- | R HS:RFC9110-14.1.2-5: a suffix-range with a zero suffix-length is not
-- satisfiable.
{-@ emptySuffixUnsatisfiable :: n:{Nat | 0 < n}
                             -> {resolve n (Suffix 0) == Unsatisfiable n} @-}
emptySuffixUnsatisfiable :: Int -> Proof
emptySuffixUnsatisfiable _ = ()
