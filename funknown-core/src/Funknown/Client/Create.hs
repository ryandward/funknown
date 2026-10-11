{-# LANGUAGE Safe #-}
-- | Creating an upload (C3 to C7 of core.md, with C6a): refuse a creation
-- request that can't succeed before anything exists, or build the new file
-- with the creation request held until the reconciler adopts a staging area.
--
-- This is the one place outside the kernel that builds an 'Asset', and it
-- only builds the initial one. Its spec states the whole initial asset and
-- client side, so a file that starts anywhere else can't be created. C1 (an
-- id already known) and C2 (the owner's rate limit) need the World's maps,
-- so they stay in the World.
module Funknown.Client.Create
  ( CreationBody (..), hasBody
  , CreateUpload (..)
  , Opened (..)
  , assemblyLimits
  , create
  , creationRefusal
  ) where

import Data.Set ()
import Funknown.Opt
import Funknown.Client.Types
import Funknown.Kernel.Types (Asset (..), Goal (..), Assembly (..), Outcome (..), Seen (..), Vouch (..), Config (..), goalTag, goalAdopted)
import Funknown.Refusal (Refusal (..))
import Funknown.Upload (Limits (..), emptyChunks, limitsOf)

-- The request ---------------------------------------------------------------------

-- | The creation request's content, as the shell parsed it. A body of known
-- length has at least one byte; a request that declares Content-Length: 0
-- carries no content, which is how the draft recommends creating an upload
-- (UP:RESUMABLE-UPLOAD-13-4.2.1-8).
data CreationBody
  = Bodiless           -- ^ no content
  | BodyOf Int         -- ^ content with this Content-Length
  | BodyUnsized        -- ^ content without a Content-Length; only the read can size it (B16)
{-@ data CreationBody = Bodiless | BodyOf {bodyLen :: {n:Int | n >= 1}} | BodyUnsized @-}

{-@ measure hasBody @-}
hasBody :: CreationBody -> Bool
hasBody Bodiless     = False
hasBody (BodyOf _)   = True
hasBody BodyUnsized  = True

-- | The content's length as C3 to C6a read it: 0 for none, -1 when only the
-- read can tell. -1 sits below every bound, so an unsized body passes each
-- size check here and is judged by B16 once read.
{-@ measure contentLen @-}
{-@ contentLen :: CreationBody -> {v:Int | v >= -1} @-}
contentLen :: CreationBody -> Int
contentLen Bodiless    = 0
contentLen (BodyOf n)  = n
contentLen BodyUnsized = -1

-- | A POST to the upload-creation resource, its fields already parsed. An
-- invalid header field has already become absent (UP:RESUMABLE-UPLOAD-13-4.1.1-4).
data CreateUpload = CreateUpload
  { cuReq           :: ReqId
  , cuFileId        :: FileId       -- ^ chosen by the World, unused by C1
  , cuUploadId      :: UploadId
  , cuComplete      :: Bool         -- ^ UC ?1; the shell reads an absent Upload-Complete as ?0
  , cuLength        :: Opt Int      -- ^ Upload-Length
  , cuBody          :: CreationBody
  , cuDigest        :: Bool         -- ^ any integrity field was sent
  , cuParentMissing :: Bool         -- ^ the destination verdict
  , cuCreatedAt     :: Int          -- ^ the wall-clock second the World stamps on the file
  }
{-@ data CreateUpload = CreateUpload
      { cuReq :: ReqId, cuFileId :: FileId, cuUploadId :: UploadId, cuComplete :: Bool
      , cuLength :: Opt Nat, cuBody :: CreationBody, cuDigest :: Bool, cuParentMissing :: Bool
      , cuCreatedAt :: Int } @-}

-- | A file that was created, and the instants it needs a Tick at.
data Opened = Opened { openedFile :: File, openedTimers :: [Instant] }
{-@ data Opened = Opened { openedFile :: File, openedTimers :: [Instant] } @-}

-- Measures for the spec -------------------------------------------------------------

-- | The limits the goal's chunks are held to, fixed at creation.
{-@ measure assemblyLimits @-}
assemblyLimits :: Goal -> Opt Limits
assemblyLimits (Keep (Assembling _ c)) = Present (limitsOf c)
assemblyLimits (Keep (Assembled _ c))  = Present (limitsOf c)
assemblyLimits Clear                   = Absent

-- | The initial asset: an assembly with no staging area adopted and no
-- chunks under the creation's limits, ongoing, never observed, no receipt,
-- the whole store budget, the first backoff step and no writes.
{-@ predicate FreshAsset V L A =
      goalTag (goal A) == 2 && not (goalAdopted (goal A))
      && goalOffset (goal A) == 0 && goalCount (goal A) == 0 && assemblyLimits (goal A) == Present L
      && outcome A == Ongoing && seen A == Unseen && vouch A == NoReceipt
      && budget A == maxAttempts (kernel V) && backoffAt A == 1 && len (authorised A) == 0 @-}

-- | The initial client side: the creation request held, with whether it
-- carries content and whether that content completes; the upload resource
-- open; the operation not deleted.
{-@ predicate FreshClient X C =
      phase C == Opening (Present (Hold (cuReq X) (hasBody (cuBody X)) (cuComplete X)))
      && uploadOpen C && not (opDeleted C) @-}

-- | The whole new file, every field named from the input it comes from, and
-- the deadline's Tick among its timers (C CH5). createdAt is what slice 2's
-- DeleteFile ladder compares If-(Un)Modified-Since with, and the recorded
-- Upload-Length is what every later A4 compares the content with.
{-@ predicate FreshFile V L M X O =
      FreshAsset V L (fileAsset (openedFile O)) && FreshClient X (client (openedFile O))
      && clientLen (client (openedFile O)) == declared (cuLength X)
      && fileEpoch (openedFile O) == 0
      && fileId (meta (openedFile O)) == cuFileId X && uploadId (meta (openedFile O)) == cuUploadId X
      && deadline (meta (openedFile O)) == envNow V + M
      && createdAt (meta (openedFile O)) == cuCreatedAt X
      && Set_mem (deadline (meta (openedFile O))) (listElts (openedTimers O)) @-}

-- | No row of C3 to C6a refuses the request. C6a is A4 and A6 at offset 0
-- (core.md's prose under the creation table): under UC ?1 the content is the
-- whole upload, so a declared length is its length, none counting as 0; under
-- UC ?0 the content can't run past a declared length; and the content is one
-- chunk. -1 for an absent length or an unsized body passes every bound.
{-@ predicate Admitted V L X =
      declaredLen (cuLength X) <= maxSize L && contentLen (cuBody X) <= maxSize L && not (cuParentMissing X)
      && declaredLen (cuLength X) <= quotaRemaining V
      && not (cuComplete X && contentLen (cuBody X) == 0 && not (sealsEmpty L))
      && not (cuDigest X)
      && ((cuComplete X && declaredLen (cuLength X) >= 0 && contentLen (cuBody X) >= 0)
            => declaredLen (cuLength X) == contentLen (cuBody X))
      && ((not (cuComplete X) && declaredLen (cuLength X) >= 0) => contentLen (cuBody X) <= declaredLen (cuLength X))
      && contentLen (cuBody X) <= maxChunk L
      && ((not (cuComplete X) && contentLen (cuBody X) >= 1) => contentLen (cuBody X) >= minChunk L) @-}

-- Creation ---------------------------------------------------------------------------

-- | C3 to C7. A refusal creates nothing, so it carries no Upload-Complete.
-- A file exists only for a request every row admitted; which refusal a
-- request gets, by the table's order, is test/WatchCreate.hs's to check.
{-@ create :: env:Env -> lim:Limits -> maxAge:Nat -> x:CreateUpload
           -> Either Reply {o:Opened | FreshFile env lim maxAge x o && Admitted env lim x} @-}
create :: Env -> Limits -> Int -> CreateUpload -> Either Reply Opened
create env lim maxAge x = case creationRefusal env lim x of
  Present r -> Left (Refuse r Absent)
  Absent    -> Right (opened env lim maxAge x)

-- | The first of C3 to C6a that refuses the request, in the table's order.
-- Each guard reads the two lengths through the same measures 'Admitted'
-- states, so dropping or narrowing a guard leaves a created file the spec
-- of 'create' rejects.
{-@ creationRefusal :: env:Env -> lim:Limits -> x:CreateUpload
                    -> {r:Opt Refusal | not (isPresent r) => Admitted env lim x} @-}
creationRefusal :: Env -> Limits -> CreateUpload -> Opt Refusal
creationRefusal env lim x
  -- C3: P UP:RESUMABLE-UPLOAD-13-4.1.4-3 (PM16); C CH13
  | declaredLen (cuLength x) > maxSize lim || contentLen (cuBody x) > maxSize lim = Present (ExceedsMaxSize lim)
  | cuParentMissing x = Present ParentMissing
  -- C4: R HS:RFC4918-11.5-1; C CH14
  | declaredLen (cuLength x) > quotaRemaining env = Present InsufficientStorage
  -- C5: a complete upload of total length 0, which the store can't seal.
  -- R HS:RFC9110-15.6.2; C CH15
  | cuComplete x && contentLen (cuBody x) == 0 && not (sealsEmpty lim) = Present NotImplemented
  -- C6: no client digest can be forwarded. P PD:DIGEST-PROBLEMS-3.1-1, PD:RFC9530-2-2 (PM24)
  | cuDigest x = Present DigestUnsupported
  -- C6a: every check A4 and A6 would make on the creation request's content,
  -- made while a refusal still leaves nothing behind. The row's own guard
  -- names only the UC ?1 disagreement, but A4 also refuses content that runs
  -- past the declared length, and at creation nothing later would: the read
  -- is capped by max-size, not by the length (CLIENT.md, A9).
  -- R UP:RESUMABLE-UPLOAD-13-4.1.3-6; P UP:RESUMABLE-UPLOAD-13-4.1.4-5, UP:RESUMABLE-UPLOAD-13-4.1.4-6 (PM16); C CH28, CH45
  | lengthsDisagree (cuComplete x) (declaredLen (cuLength x)) (contentLen (cuBody x)) = Present InconsistentLength
  | contentLen (cuBody x) > maxChunk lim = Present (AppendTooLarge lim)
  | not (cuComplete x) && contentLen (cuBody x) >= 1 && contentLen (cuBody x) < minChunk lim = Present (AppendTooSmall lim)
  | otherwise = Absent

-- | C7: the file starts CREATING with the creation request held and a
-- deadline max-age away. R UP:RESUMABLE-UPLOAD-13-4.2.2-5; C CH2, CH5, CH6
--
-- Matching 'Env' and 'Config' is what makes their field refinements known:
-- the budget is a natural number within the attempt cap, and the deadline a
-- natural number, only because 'envNow' and 'maxAttempts' are.
{-@ opened :: env:Env -> lim:Limits -> maxAge:Nat -> x:CreateUpload -> {o:Opened | FreshFile env lim maxAge x o} @-}
opened :: Env -> Limits -> Int -> CreateUpload -> Opened
opened (Env t _ _ _ (Config attempts _ _)) lim maxAge x =
  Opened (File (Meta (cuFileId x) (cuUploadId x) (t + maxAge) (cuCreatedAt x))
               (Asset (Keep (Assembling Absent (emptyChunks lim))) Ongoing Unseen NoReceipt attempts 1 [])
               (Client (declared (cuLength x)) True
                       (Opening (Present (Hold (cuReq x) (hasBody (cuBody x)) (cuComplete x))))
                       False)
               0)
         [t + maxAge]

-- Lengths ------------------------------------------------------------------------------

-- | The Upload-Length the file records.
{-@ measure declared @-}
{-@ declared :: Opt Nat -> Len @-}
declared :: Opt Int -> Len
declared (Present n) = Known n
declared Absent      = Unknown

-- | The Upload-Length as C3, C4 and C6a read it, -1 when none was sent.
{-@ measure declaredLen @-}
{-@ declaredLen :: Opt Nat -> {v:Int | v >= -1} @-}
declaredLen :: Opt Int -> Int
declaredLen (Present n) = n
declaredLen Absent      = -1

-- | A4 at offset 0, given UC, the declared length and the content's length
-- (each -1 when unknown). Under UC ?1 the content is the whole upload, so
-- the two lengths must be equal, and a request with no content says the
-- upload is 0 bytes long; under UC ?0 the content is a first part, so it
-- can't be longer than the whole. R UP:RESUMABLE-UPLOAD-13-4.1.3-6
{-@ lengthsDisagree :: uc:Bool -> l:Int -> n:Int
                    -> {v:Bool | v <=> ((uc && l >= 0 && n >= 0 && l /= n) || (not uc && l >= 0 && n > l))} @-}
lengthsDisagree :: Bool -> Int -> Int -> Bool
lengthsDisagree uc l n
  | l < 0 || n < 0 = False
  | uc             = l /= n
  | otherwise      = n > l
