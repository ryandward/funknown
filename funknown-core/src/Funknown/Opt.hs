{-# LANGUAGE Safe #-}
-- | Optional values the logic can see. Specs can't name 'Maybe' in this
-- LiquidHaskell build ('isJust' isn't a logic name), so the core uses its own.
module Funknown.Opt (Opt (..), isPresent, Len (..), isKnown, lenOr) where

data Opt a = Absent | Present a
  deriving (Eq, Show)

{-@ measure isPresent @-}
isPresent :: Opt a -> Bool
isPresent Absent      = False
isPresent (Present _) = True

-- | A length that is either known or not yet known. It replaces tusd's
-- @Size@ plus @SizeIsDeferred@, so a meaningless size can't exist.
data Len = Unknown | Known Int
  deriving (Eq, Show)
{-@ data Len = Unknown | Known {knownLen :: Nat} @-}

{-@ measure isKnown @-}
isKnown :: Len -> Bool
isKnown Unknown   = False
isKnown (Known _) = True

{-@ measure lenOr @-}
{-@ lenOr :: l:Len -> {v:Int | (isKnown l => v >= 0) && (not (isKnown l) => v == -1)} @-}
lenOr :: Len -> Int
lenOr Unknown   = -1
lenOr (Known n) = n
