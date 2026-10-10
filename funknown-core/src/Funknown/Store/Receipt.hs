{-# LANGUAGE Safe #-}
{-@ LIQUID "--reflection" @-}
{-@ LIQUID "--ple" @-}
-- | The store's word that it holds a whole file: the only thing that can make
-- a file available (C CH1). 'Receipt' is abstract and 'vouch' is the only
-- way to build one.
--
-- What comes in from outside the core, a 'ReceiptReport' and the
-- 'Checksum' in it, is abstract with one checked producer each, and 'vouch'
-- has no precondition, so every claim here holds for callers LiquidHaskell
-- never checked. 'SizeDiffers' is an answer the core gives, not a value it
-- accepts, so it stays open for pattern matching: building one by hand
-- breaks no claim made here.
module Funknown.Store.Receipt
  ( ReceiptReport
  , receiptReport
  , reportAlg
  , reportChecksum
  , reportSize
  , SizeDiffers (..)
  , Receipt
  , alg
  , checksum
  , size
  , vouch
  , toHex
  , isLowerHex
  , hexValue
  , sameHexSameChecksum
  , pow16
  , pow2
  , widthIsSixteenDigits
  ) where

import Funknown.Opt              -- whole module: isPresent is used only in specs
import Funknown.Proof (Proof, (?))
import Funknown.Store.Algorithm  -- whole module: width is used only in specs

-- | What a store reported for a sealed file, already decoded by its adapter.
-- The adapter owes the store contract (C CH6 (1)): a full-object checksum in
-- the receipt algorithm, at full width, with the size of what it sealed.
-- Abstract like 'Receipt': 'receiptReport' is the only producer, so a
-- report's size is never negative whoever built it.
data ReceiptReport = ReceiptReport
  { repAlg      :: ReceiptAlgorithm
  , repChecksum :: Checksum
  , repSize     :: Int
  }
  deriving (Eq, Show)

{-@ data ReceiptReport = ReceiptReport
      { repAlg      :: ReceiptAlgorithm
      , repChecksum :: Checksum
      , repSize     :: Nat
      }
  @-}

{-@ measure reportAlg @-}
reportAlg :: ReceiptReport -> ReceiptAlgorithm
reportAlg (ReceiptReport a _ _) = a

{-@ measure reportChecksum @-}
reportChecksum :: ReceiptReport -> Checksum
reportChecksum (ReceiptReport _ c _) = c

{-@ measure reportSize @-}
{-@ reportSize :: ReceiptReport -> Nat @-}
reportSize :: ReceiptReport -> Int
reportSize (ReceiptReport _ _ s) = s

-- | The only producer of a 'ReceiptReport': present exactly when the size is
-- a size, and then holding what it was given.
{-@ receiptReport :: a:ReceiptAlgorithm -> c:Checksum -> s:Int
      -> {o:Opt {r:ReceiptReport | reportAlg r == a && reportChecksum r == c && reportSize r == s}
           | isPresent o <=> 0 <= s} @-}
receiptReport :: ReceiptAlgorithm -> Checksum -> Int -> Opt ReceiptReport
receiptReport a c s
  | 0 <= s    = Present (ReceiptReport a c s)
  | otherwise = Absent

-- | A report whose size isn't the upload's length. The two can't be equal.
-- The reported size is a report's, so it is never negative; the expected one
-- is whatever 'vouch' was asked for.
data SizeDiffers = SizeDiffers
  { expectedSize :: Int
  , reportedSize :: Int
  }
  deriving (Eq, Show)

{-@ data SizeDiffers = SizeDiffers
      { expectedSize :: Int
      , reportedSize :: {v:Nat | v /= expectedSize}
      }
  @-}

-- | The field names stay unexported: an exported field would also allow
-- record update, which would forge a receipt from a real one. 'alg',
-- 'checksum' and 'size' are the readers.
data Receipt = Receipt
  { receiptAlg      :: ReceiptAlgorithm
  , receiptChecksum :: Checksum
  , receiptSize     :: Int
  }
  deriving (Eq, Show)

{-@ data Receipt = Receipt
      { receiptAlg      :: ReceiptAlgorithm
      , receiptChecksum :: Checksum
      , receiptSize     :: Nat
      }
  @-}

{-@ measure alg @-}
alg :: Receipt -> ReceiptAlgorithm
alg (Receipt a _ _) = a

{-@ measure checksum @-}
checksum :: Receipt -> Checksum
checksum (Receipt _ c _) = c

{-@ measure size @-}
{-@ size :: Receipt -> Nat @-}
size :: Receipt -> Int
size (Receipt _ _ s) = s

-- | The only producer of 'Receipt' (DC1's construction half). The receipt
-- keeps the report's algorithm, checksum and size, and exists only when that
-- size is the length we expected; otherwise the answer says both sizes.
-- @expected@ needs no refinement: a report's size is never negative, so a
-- negative expectation can only ever be answered 'SizeDiffers'.
{-@ vouch :: expected:Int -> rep:ReceiptReport
          -> Either {d:SizeDiffers | expectedSize d == expected && reportedSize d == reportSize rep}
                    {r:Receipt | size r == expected
                              && size r == reportSize rep
                              && alg r == reportAlg rep
                              && checksum r == reportChecksum rep} @-}
vouch :: Int -> ReceiptReport -> Either SizeDiffers Receipt
vouch expected (ReceiptReport a c s)
  | s == expected = Right (Receipt a c s)
  | otherwise     = Left (SizeDiffers expected s)

-- Hex rendering. 'toHex' uses div and mod, so it is not reflected (rule 6);
-- what is reflected is the decoding, 'hexValue', which only multiplies and
-- adds. toHex's type says hexValue undoes it, which makes toHex injective.

-- | A lowercase hex digit, as an equality table (rule 5).
{-@ inline isLowerHex @-}
isLowerHex :: Char -> Bool
isLowerHex c =
  c == '0' || c == '1' || c == '2' || c == '3' || c == '4' || c == '5' || c == '6' || c == '7' ||
  c == '8' || c == '9' || c == 'a' || c == 'b' || c == 'c' || c == 'd' || c == 'e' || c == 'f'

{-@ type LowerHex = {c:Char | isLowerHex c} @-}

-- | The value of a lowercase hex digit. Anything else counts as 0; it only
-- has to undo 'nibble'.
{-@ reflect digitValue @-}
digitValue :: Char -> Integer
digitValue c =
  if c == '1' then 1 else if c == '2' then 2 else if c == '3' then 3 else
  if c == '4' then 4 else if c == '5' then 5 else if c == '6' then 6 else
  if c == '7' then 7 else if c == '8' then 8 else if c == '9' then 9 else
  if c == 'a' then 10 else if c == 'b' then 11 else if c == 'c' then 12 else
  if c == 'd' then 13 else if c == 'e' then 14 else if c == 'f' then 15 else 0

-- | Horner's rule, most significant digit first.
{-@ reflect hexFrom @-}
{-@ hexFrom :: Integer -> cs:[Char] -> Integer / [len cs] @-}
hexFrom :: Integer -> [Char] -> Integer
hexFrom acc []       = acc
hexFrom acc (c : cs) = hexFrom (16 * acc + digitValue c) cs

{-@ reflect hexValue @-}
hexValue :: [Char] -> Integer
hexValue cs = hexFrom 0 cs

{-@ reflect snoc @-}
{-@ snoc :: xs:[a] -> a -> {v:[a] | len v == len xs + 1} @-}
snoc :: [a] -> a -> [a]
snoc []       y = [y]
snoc (x : xs) y = x : snoc xs y

{-@ reflect pow16 @-}
{-@ pow16 :: Nat -> {v:Integer | 0 < v} @-}
pow16 :: Int -> Integer
pow16 k = if k <= 0 then 1 else 16 * pow16 (k - 1)

-- | Appending a digit shifts the value one place and adds the digit.
{-@ hexFromSnoc :: a:Integer -> xs:[Char] -> c:Char
                -> {hexFrom a (snoc xs c) == 16 * hexFrom a xs + digitValue c} / [len xs] @-}
hexFromSnoc :: Integer -> [Char] -> Char -> Proof
hexFromSnoc _ []       _ = ()
hexFromSnoc a (x : xs) c = hexFromSnoc (16 * a + digitValue x) xs c

{-@ nibble :: d:{Integer | 0 <= d && d < 16} -> {c:LowerHex | digitValue c == d} @-}
nibble :: Integer -> Char
nibble d
  | d == 0 = '0'
  | d == 1 = '1'
  | d == 2 = '2'
  | d == 3 = '3'
  | d == 4 = '4'
  | d == 5 = '5'
  | d == 6 = '6'
  | d == 7 = '7'
  | d == 8 = '8'
  | d == 9 = '9'
  | d == 10 = 'a'
  | d == 11 = 'b'
  | d == 12 = 'c'
  | d == 13 = 'd'
  | d == 14 = 'e'
  | otherwise = 'f'

-- | Exactly k digits, zero-padded, for a value below 16^k.
{-@ hexDigits :: k:Nat -> v:{Integer | 0 <= v && v < pow16 k}
              -> {h:[LowerHex] | len h == k && hexValue h == v} / [k] @-}
hexDigits :: Int -> Integer -> [Char]
hexDigits k v
  | k <= 0    = []
  | otherwise =
      let hs = hexDigits (k - 1) (v `div` 16)
          c  = nibble (v `mod` 16)
      in snoc hs c ? hexFromSnoc 0 hs c

{-@ pow16Is2To64 :: {pow16 16 == 18446744073709551616} @-}
pow16Is2To64 :: Proof
pow16Is2To64 = ()

{-@ reflect pow2 @-}
{-@ pow2 :: Nat -> {v:Integer | 0 < v} @-}
pow2 :: Int -> Integer
pow2 k = if k <= 0 then 1 else 2 * pow2 (k - 1)

-- | Sixteen hex digits hold exactly the algorithm's width: no checksum is
-- cut short and no digit is spare.
{-@ widthIsSixteenDigits :: a:ReceiptAlgorithm -> {pow2 (width a) == pow16 16} @-}
widthIsSixteenDigits :: ReceiptAlgorithm -> Proof
widthIsSixteenDigits Crc64Nvme = ()

-- | The DRS checksum string: R DO:DRS-schemas.Checksum.checksum-1 makes it a
-- hex string. Lowercase and zero-padded to the full width are our choice, so
-- one checksum has one spelling. It renders a number; it reads no file bytes.
{-@ toHex :: r:Receipt
          -> {h:[LowerHex] | len h == 16 && hexValue h == checksumValue (checksum r)} @-}
toHex :: Receipt -> [Char]
toHex (Receipt _ c _) = hexDigits 16 (checksumValue c ? pow16Is2To64)

-- | toHex is injective on the 2^64 checksums: equal strings decode to equal
-- values, because 'hexValue' undoes 'toHex'.
{-@ sameHexSameChecksum :: r1:Receipt -> r2:Receipt
      -> {v:Bool | v => checksumValue (checksum r1) == checksumValue (checksum r2)} @-}
sameHexSameChecksum :: Receipt -> Receipt -> Bool
sameHexSameChecksum r1 r2 = toHex r1 == toHex r2
