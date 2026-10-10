{-# LANGUAGE Safe #-}
{-@ LIQUID "--reflection" @-}
-- | The access guard (G0), which runs before routing. 'admit' sees only the
-- shell's verdict on the request's credentials: it has no argument through
-- which a file's existence, state or preconditions could reach it, so none
-- of them can change its answer (SF1, admit half).
module Funknown.Http.Admission
  ( Access (..)
  , Admit (..)
  , admit
  ) where

-- | The shell's verdict, per request.
data Access
  = NoCredentials
    -- ^ P HS:RFC9110-11.4-1 (PM2): a request that omits credentials
  | InvalidCredentials
    -- ^ P HS:RFC9110-11.4-1 (PM2): invalid or partial credentials
  | Insufficient
    -- ^ P HS:RFC9110-11.4-2 (PM2): valid credentials that are not adequate
  | Allowed
    -- ^ R SS:AIP193-PermissionDenied-1: permission is decided before any
    -- existence check, so this verdict is the shell's alone
  deriving (Eq, Show, Enum, Bounded)

data Admit
  = A401
    -- ^ R HS:RFC9110-15.5.2-1; its challenge is R HS:RFC9110-15.5.2-2, which
    -- the Refusal that carries it enforces
  | A403
    -- ^ R HS:RFC9110-15.5.4-1, SS:AIP193-PermissionDenied-1
  | Clear
    -- ^ routing may run
  deriving (Eq, Show, Enum, Bounded)

-- | SF1: anything but Allowed is answered 401 or 403 (R SS:AIP193-PermissionDenied-1,
-- HS:RFC9110-15.5.2-2; P HS:RFC9110-11.4-1, HS:RFC9110-11.4-2, PM2), and a
-- forbidden file is never disguised as 404 (P HS:RFC9110-15.5.4-4 declined, PM1).
{-@ reflect admit @-}
{-@ admit :: a:Access
          -> {v:Admit | (v == Clear <=> a == Allowed)
                     && (v == A401 <=> (a == NoCredentials || a == InvalidCredentials))
                     && (v == A403 <=> a == Insufficient)} @-}
admit :: Access -> Admit
admit NoCredentials      = A401
admit InvalidCredentials = A401
admit Insufficient       = A403
admit Allowed            = Clear
