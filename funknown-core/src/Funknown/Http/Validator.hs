{-# LANGUAGE Safe #-}
{-@ LIQUID "--reflection" @-}
{-@ LIQUID "--ple" @-}
-- | Entity tags and the two ways RFC 9110 compares them. Scanning a tag out
-- of a header field stays in the shell (it needs character ranges, which z3
-- can't order), so the core only ever sees tags that are already parsed.
module Funknown.Http.Validator
  ( OpaqueTag (..)
  , EntityTag (..)
  , strongMatch
  , weakMatch
  , strongImpliesWeak
  , matchesSymmetric
  , comparisonTable
  ) where

import Funknown.Proof (Proof)

-- | The characters between the quotes of an opaque-tag, without the quotes.
-- R HS:RFC9110-8.8.3-3
newtype OpaqueTag = OpaqueTag [Char]
  deriving (Eq, Show)

-- | An opaque quoted string, possibly prefixed by the weakness indicator W/.
-- R HS:RFC9110-8.8.3-2, HS:RFC9110-8.8.3-3
data EntityTag = EntityTag { weak :: Bool, opaque :: OpaqueTag }
  deriving (Eq, Show)

-- | Equivalent when both are not weak and their opaque-tags match.
-- R HS:RFC9110-8.8.3.2-1
{-@ reflect strongMatch @-}
strongMatch :: EntityTag -> EntityTag -> Bool
strongMatch (EntityTag wa oa) (EntityTag wb ob) = not wa && not wb && oa == ob

-- | Equivalent when their opaque-tags match, whatever either one's weakness.
-- R HS:RFC9110-8.8.3.2-2
{-@ reflect weakMatch @-}
weakMatch :: EntityTag -> EntityTag -> Bool
weakMatch (EntityTag _ oa) (EntityTag _ ob) = oa == ob

-- | V11, first half: two tags that match strongly also match weakly.
-- R HS:RFC9110-8.8.3.2-1, HS:RFC9110-8.8.3.2-2
{-@ strongImpliesWeak :: a:EntityTag -> b:{EntityTag | strongMatch a b} -> {weakMatch a b} @-}
strongImpliesWeak :: EntityTag -> EntityTag -> Proof
strongImpliesWeak (EntityTag _ _) (EntityTag _ _) = ()

-- | Both comparisons say when "two entity tags are equivalent", so neither
-- may depend on which tag comes first. The table alone can't see this: its
-- third row only puts the weak tag first.
-- R HS:RFC9110-8.8.3.2-1, HS:RFC9110-8.8.3.2-2
{-@ matchesSymmetric :: a:EntityTag -> b:EntityTag
      -> {strongMatch a b == strongMatch b a && weakMatch a b == weakMatch b a} @-}
matchesSymmetric :: EntityTag -> EntityTag -> Proof
matchesSymmetric (EntityTag _ _) (EntityTag _ _) = ()

-- | V11, second half: the four rows of the RFC's example table, for any two
-- distinct opaque-tags rather than only "1" and "2". Each conjunct is one row,
-- strong column then weak column.
-- R HS:RFC9110-8.8.3.2-3
{-@ comparisonTable :: o1:OpaqueTag -> {o2:OpaqueTag | o1 /= o2} ->
      { not (strongMatch (EntityTag True o1) (EntityTag True o1))
          && weakMatch (EntityTag True o1) (EntityTag True o1)
     && not (strongMatch (EntityTag True o1) (EntityTag True o2))
          && not (weakMatch (EntityTag True o1) (EntityTag True o2))
     && not (strongMatch (EntityTag True o1) (EntityTag False o1))
          && weakMatch (EntityTag True o1) (EntityTag False o1)
     && strongMatch (EntityTag False o1) (EntityTag False o1)
          && weakMatch (EntityTag False o1) (EntityTag False o1) } @-}
comparisonTable :: OpaqueTag -> OpaqueTag -> Proof
comparisonTable _ _ = ()
