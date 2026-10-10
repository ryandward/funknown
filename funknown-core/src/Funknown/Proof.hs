{-# LANGUAGE Safe #-}
-- | Equational proof combinators. This LiquidHaskell build doesn't expose
-- Language.Haskell.Liquid.ProofCombinators, so the core carries its own.
module Funknown.Proof (Proof, QED (..), (===), (***), (?)) where

type Proof = ()

data QED = QED

infixl 3 ===
{-@ (===) :: x:a -> y:{a | y == x} -> {v:a | v == x && v == y} @-}
(===) :: a -> a -> a
x === _ = x

infixl 2 ***
(***) :: a -> QED -> Proof
_ *** QED = ()

infixl 3 ?
{-@ (?) :: x:a -> b -> {v:a | v == x} @-}
(?) :: a -> b -> a
x ? _ = x
