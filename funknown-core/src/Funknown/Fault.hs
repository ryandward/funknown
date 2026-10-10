{-# LANGUAGE Safe #-}
-- | Why a transfer ended in FAILED. Each Fault's google.rpc.Code is chosen in
-- the projection (C CH36); the code's definition is what the Fault has to fit.
module Funknown.Fault (Fault (..)) where

data Fault
  = Expired               -- ^ max-age passed while opening or receiving
  | FinalizeTimedOut      -- ^ the finalize budget ran out
  | OutOfRange            -- ^ content past the upload length
  | TooLarge              -- ^ an import longer than max-size
  | QuotaAtFinalize       -- ^ over quota when the upload completed
  | Revoked               -- ^ access was gone when an import finished
  | Empty                 -- ^ a zero-length import the store can't seal
  | CreationRefused       -- ^ the creation request's own content was refused once the upload existed
  | CreationInterrupted   -- ^ the creation request's content broke off before its 201
  | StateLost             -- ^ the store lost the staging area
  | SizeMismatch          -- ^ the store's size differs from the upload length
  | ObjectWithoutReceipt  -- ^ a file exists that the store will never vouch for
  | StoreRefusedUs        -- ^ a deterministic store refusal
  | Contradiction         -- ^ the store contradicted itself or the shell broke its contract
  | Unavailable           -- ^ store retries exhausted
  | SourceUnreachable     -- ^ the origin couldn't be reached
  | SourceAnswered Int    -- ^ the origin answered with a status we don't retry
  | SourceChanged         -- ^ the origin's representation changed under a resume
  deriving (Eq, Show)
