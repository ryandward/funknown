{-# LANGUAGE Safe #-}
-- | Provenance, vendor-free and register-free. Each package instantiates it
-- with its own citations and its own registers.
module Funknown.Basis (Basis (..), Side (..)) where

-- | Required cites a MUST or a definition that leaves no choice; Permitted
-- cites a SHOULD, MAY or open option and records the side we took; Chosen is
-- ours, with a rationale and no citation.
data Basis c w r = Required c | Permitted c (Side w) | Chosen r
  deriving (Eq, Show)

data Side w = Took w | Declined w
  deriving (Eq, Show)
