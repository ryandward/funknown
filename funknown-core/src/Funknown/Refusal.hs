{-# LANGUAGE Safe #-}
-- | A request answered with an error now. The status, extra headers and
-- problem type of each are decided in the projection, from this one table.
module Funknown.Refusal (Refusal (..)) where

import Funknown.Opt
import Funknown.Upload (Limits)

data Refusal
  = NotFound
  | MethodNotAllowed
  | OffsetMismatch Int          -- ^ 409, Upload-Offset = the current offset, UC ?0
  | AlreadyComplete             -- ^ 409, UC ?0, no Upload-Offset
  | OperationInProgress         -- ^ 409
  | ParentMissing               -- ^ 409
  | Gone                        -- ^ 410
  | PreconditionFailed          -- ^ 412
  | MissingOffset               -- ^ 400
  | InconsistentLength          -- ^ 400
  | AppendTooSmall Limits       -- ^ 400 with Upload-Limit
  | DigestUnsupported           -- ^ 400, digest-unsupported-algorithms
  | AppendTooLarge Limits       -- ^ 413 with Upload-Limit
  | ExceedsMaxSize Limits       -- ^ 413 with Upload-Limit
  | OffsetPastLength            -- ^ 413
  | WrongMediaType              -- ^ 415 with Accept-Patch
  | RateLimited Int             -- ^ 429 with Retry-After
  | Internal                    -- ^ 500
  | DataLoss                    -- ^ 500, alerted separately
  | NotImplemented              -- ^ 501
  | StoreUnavailable (Opt Int)  -- ^ 503, Retry-After when the store gave a delay
  | InsufficientStorage         -- ^ 507
