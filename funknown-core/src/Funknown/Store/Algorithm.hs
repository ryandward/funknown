{-# LANGUAGE Safe #-}
{-@ LIQUID "--reflection" @-}
{-@ LIQUID "--ple" @-}
-- | The one checksum algorithm a store may vouch with, and the decoded value
-- of a checksum in it. Nothing here, or anywhere in the core, computes a
-- checksum (C CH3).
module Funknown.Store.Algorithm
  ( ReceiptAlgorithm (..)
  , width
  , DrsType
  , drsType
  , drsTypeName
  , Checksum
  , checksumValue
  , checksumOf
  ) where

import Funknown.Opt  -- whole module: isPresent is used only in specs

-- | C CH2 (brief): the only receipt algorithm. What CRC-64/NVME is (width 64,
-- the polynomial and the Rocksoft parameters) is R
-- PD:NVME-NVMCS-1.1-5.3.1.3.4-2, which agrees with PD:REVENG-crc.cat.crc-64-nvme-1
-- on every parameter but Check, whose NVMe value RevEng calls wrong
-- (PD:REVENG-crc.cat.crc-64-nvme-2). The core uses only the width.
data ReceiptAlgorithm = Crc64Nvme
  deriving (Eq, Show, Enum, Bounded)

-- | R PD:NVME-NVMCS-1.1-5.3.1.3.4-2: "Width 64".
{-@ reflect width @-}
{-@ width :: ReceiptAlgorithm -> {w:Nat | w == 64} @-}
width :: ReceiptAlgorithm -> Int
width Crc64Nvme = 64

-- | A DRS checksum type. Abstract, so 'drsType' is the only source of one.
newtype DrsType = DrsType [Char]
  deriving (Eq, Show)

drsTypeName :: DrsType -> [Char]
drsTypeName (DrsType t) = t

-- | P DO:DRS-schemas.Checksum.type-1, DO:DRS-schemas.Checksum.type-2 (PM26):
-- we take the "Other values MAY be used" side and decline both SHOULDs,
-- because neither the Named Information registry nor DRS's list names
-- CRC-64/NVME (C CH2).
drsType :: ReceiptAlgorithm -> DrsType
drsType Crc64Nvme = DrsType "crc64nvme"

-- | A decoded checksum value, below 2^64 (the bound is a literal, because
-- @^@ doesn't parse in a spec). In RFC 9530's terms it is the output of the
-- algorithm over the file's bytes (R HS:RFC9530-1.4), computed by the store.
--
-- Abstract: 'checksumOf' is the only producer, so the bound holds for values
-- built by code LiquidHaskell never checked, and 'checksumValue' is the
-- reader. The field stays unexported, because an exported field would also
-- allow record update.
--
-- It is @data@ rather than @newtype@ because this LiquidHaskell treats a
-- refined newtype badly three ways: a @data@ spec on it is ignored without
-- a word, a reflected recursive function beside it crashes the plugin, and a
-- measure returning it is sorted as the bare Integer.
data Checksum = Checksum { checksumInteger :: Integer }
  deriving (Eq, Show)

{-@ data Checksum = Checksum { checksumInteger :: {v:Integer | 0 <= v && v < 18446744073709551616} } @-}

{-@ measure checksumValue @-}
{-@ checksumValue :: Checksum -> {v:Integer | 0 <= v && v < 18446744073709551616} @-}
checksumValue :: Checksum -> Integer
checksumValue (Checksum v) = v

-- | The only producer of a 'Checksum'. Its refinement pins the literal above
-- from below (a smaller literal would refuse 2^64 - 1 here), and toHex's 16
-- digits pin it from above.
{-@ checksumOf :: v:Integer
               -> {o:Opt {c:Checksum | checksumValue c == v}
                    | isPresent o <=> (0 <= v && v < 18446744073709551616)} @-}
checksumOf :: Integer -> Opt Checksum
checksumOf v
  | 0 <= v && v < checksumBound = Present (Checksum v)
  | otherwise                   = Absent

-- | 2^64. A literal this large compiles to a big-integer constructor that
-- the logic can't read as a number, so the code builds it from two
-- word-sized factors and z3 checks the product.
{-@ checksumBound :: {v:Integer | v == 18446744073709551616} @-}
checksumBound :: Integer
checksumBound = 4294967296 * 4294967296
