{-# LANGUAGE Safe #-}
-- | A receipt bound to the exact object version it vouched for (store
-- contract rule 4). Only 'bind' builds one, so a bound receipt always came
-- from 'vouch' and always names the version it was observed at; every later
-- read or removal the shell performs is conditional on that version.
module Funknown.Kernel.Bound
  ( Version (..)
  , Bound
  , bind
  , boundVersion
  , boundSize
  , boundReceipt
  ) where

import Funknown.Store.Receipt (Receipt, ReceiptReport, SizeDiffers, reportSize, size, vouch)

-- | Opaque: whatever identifies an object's bytes in the store (an entity-tag
-- or a version id). The core compares versions and never looks inside.
data Version = Version [Char]
  deriving (Eq, Show)

data Bound = Bound Version Receipt
{-@ data Bound = Bound { bVersion :: Version, bReceipt :: Receipt } @-}

{-@ measure boundVersion @-}
boundVersion :: Bound -> Version
boundVersion (Bound v _) = v

{-@ measure boundSize @-}
{-@ boundSize :: Bound -> Nat @-}
boundSize :: Bound -> Int
boundSize (Bound _ r) = size r

boundReceipt :: Bound -> Receipt
boundReceipt (Bound _ r) = r

-- | K1: a bound receipt's size is the expected length and the size the store
-- reported, and its version is the version the store reported with the
-- vouching.
{-@ bind :: expected:Nat -> v:Version -> rep:ReceiptReport
         -> Either SizeDiffers {b:Bound | boundSize b == expected && boundSize b == reportSize rep
                                         && boundVersion b == v} @-}
bind :: Int -> Version -> ReceiptReport -> Either SizeDiffers Bound
bind expected v rep = case vouch expected rep of
  Left d  -> Left d
  Right r -> Right (Bound v r)
