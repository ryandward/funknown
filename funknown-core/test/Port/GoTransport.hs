{-# LANGUAGE Safe #-}
-- | A literal transcription of Go's decision to retry a request on a new
-- connection, from references/http-semantics/code/go/request.go and
-- transport.go, bugs included. Go names are kept where Haskell allows.
--
-- The spec on 'outgoingLength' is checked by LiquidHaskell in a separate
-- component; the test-suite compiles this file without the plugin.
module Port.GoTransport
  ( Body (..)
  , Request (..)
  , valueOrDefault
  , has
  , isReplayable
  , outgoingLength
  , Err (..)
  , PersistConn (..)
  , isReused
  , shouldRetryRequest
  ) where

-- | @r.Body@: nil, the @NoBody@ sentinel, or a reader the caller supplied.
data Body = Nil | NoBody | Reader
  deriving (Eq, Show, Enum, Bounded)

-- | The fields of a Request that the transcribed functions read.
-- @getBody@ is @r.GetBody != nil@; @header@ lists the header field names
-- present, which is all @Header.has@ looks at.
data Request = Request
  { method        :: String
  , body          :: Body
  , getBody       :: Bool
  , contentLength :: Int
  , header        :: [String]
  }
  deriving (Eq, Show)
{-@ data Request = Request
      { method :: String, body :: Body, getBody :: Bool, contentLength :: Int, header :: [String] } @-}

-- | request.go:542-549
valueOrDefault :: String -> String -> String
valueOrDefault value def = if value /= "" then value else def

-- | @Header.has@ is a plain key lookup (@_, ok := h[key]@); header.go isn't
-- vendored.
has :: [String] -> String -> Bool
has h key = key `elem` h

-- | request.go:1543-1557
isReplayable :: Request -> Bool
isReplayable r =
  if body r == Nil || body r == NoBody || getBody r
    then case valueOrDefault (method r) "GET" of
      "GET"     -> True
      "HEAD"    -> True
      "OPTIONS" -> True
      "TRACE"   -> True
      _         -> has (header r) "Idempotency-Key" || has (header r) "X-Idempotency-Key"
    else False

-- | request.go:1559-1569. The spec is what lets the diff take one
-- Content-Length per body: the result is 0 exactly for a nil or NoBody body,
-- whatever the Content-Length, and 'shouldRetryRequest' reads Content-Length
-- only through this function.
{-@ outgoingLength :: r:Request -> {v:Int | (v == 0) <=> (body r == Nil || body r == NoBody)} @-}
outgoingLength :: Request -> Int
outgoingLength r
  | body r == Nil || body r == NoBody = 0
  | contentLength r /= 0              = contentLength r
  | otherwise                         = -1

-- | The errors 'shouldRetryRequest' tells apart (transport.go:757-799), and
-- every other error.
data Err
  = Http2NoCachedConnError
  | ErrMissingHost
  | NothingWrittenError
  | TransportReadFromServerError
  | ErrServerClosedIdle
  | OtherError
  deriving (Eq, Show, Enum, Bounded)

newtype PersistConn = PersistConn { reused :: Bool }
  deriving (Eq, Show)

-- | transport.go:2076-2082
isReused :: PersistConn -> Bool
isReused = reused

-- | transport.go:756-801
shouldRetryRequest :: PersistConn -> Request -> Err -> Bool
shouldRetryRequest pc req err
  | err == Http2NoCachedConnError = True                                   -- :757-765
  | err == ErrMissingHost         = False                                  -- :766-769
  | not (isReused pc)             = False                                  -- :770-779
  | err == NothingWrittenError    = outgoingLength req == 0 || getBody req -- :780-784
  | not (isReplayable req)        = False                                  -- :785-788
  | err == TransportReadFromServerError = True                             -- :789-793
  | err == ErrServerClosedIdle    = True                                   -- :794-799
  | otherwise                     = False                                  -- :800
