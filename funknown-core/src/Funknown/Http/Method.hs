{-# LANGUAGE Safe #-}
{-@ LIQUID "--reflection" @-}
{-@ LIQUID "--ple" @-}
-- | Request methods: the eight RFC 9110 defines, plus PATCH from RFC 5789,
-- because the upload draft appends with PATCH.
module Funknown.Http.Method
  ( Method (..)
  , Recognised (..)
  , safe
  , idempotent
  , safeImpliesIdempotent
  ) where

import Funknown.Proof (Proof)

data Method = GET | HEAD | POST | PUT | DELETE | CONNECT | OPTIONS | TRACE | PATCH
  deriving (Eq, Show, Enum, Bounded)

-- | A method token the shell parsed. A token we don't recognise at all is
-- answered 501 (HS:RFC9110-15.6.2), which is why it is kept apart from a
-- recognised method the resource doesn't support (405, HS:RFC9110-15.5.6).
data Recognised = Known Method | Unrecognised
  deriving (Eq, Show)

-- | R HS:RFC9110-9.2.1-2: GET, HEAD, OPTIONS and TRACE are defined to be safe.
-- R HS:RFC5789-2-1: PATCH is neither safe nor idempotent.
{-@ reflect safe @-}
safe :: Method -> Bool
safe GET     = True
safe HEAD    = True
safe OPTIONS = True
safe TRACE   = True
safe POST    = False
safe PUT     = False
safe DELETE  = False
safe CONNECT = False
safe PATCH   = False

-- | R HS:RFC9110-9.2.2-1: PUT, DELETE and the safe methods are idempotent.
-- R HS:RFC5789-2-1: PATCH is not.
{-@ reflect idempotent @-}
idempotent :: Method -> Bool
idempotent GET     = True
idempotent HEAD    = True
idempotent OPTIONS = True
idempotent TRACE   = True
idempotent PUT     = True
idempotent DELETE  = True
idempotent POST    = False
idempotent CONNECT = False
idempotent PATCH   = False

-- | V9, first half: every safe method is idempotent.
{-@ safeImpliesIdempotent :: m:{Method | safe m} -> {idempotent m} @-}
safeImpliesIdempotent :: Method -> Proof
safeImpliesIdempotent GET     = ()
safeImpliesIdempotent HEAD    = ()
safeImpliesIdempotent OPTIONS = ()
safeImpliesIdempotent TRACE   = ()
safeImpliesIdempotent PUT     = ()
safeImpliesIdempotent DELETE  = ()
safeImpliesIdempotent POST    = ()
safeImpliesIdempotent CONNECT = ()
safeImpliesIdempotent PATCH   = ()
