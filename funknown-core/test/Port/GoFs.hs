-- | A literal transcription of Go net/http's entity-tag comparison and
-- precondition checks, bugs included, from
-- references/http-semantics/code/go/fs.go. Each function names the lines it
-- transcribes. It exists only so the exhaustive test can diff
-- Funknown.Http.Validator and Funknown.Http.Precondition against Go.
--
-- What the transcription abstracts, without changing any decision Go makes:
--
-- * time.Time is whole Unix seconds or Go's zero Time, so Truncate(time.Second)
--   (fs.go:520, 571) is the identity.
-- * ParseTime parses HTTP-dates in three layouts; here it reads decimal Unix
--   seconds, because date parsing is the shell's in our design and the domain
--   only needs dates that parse and compare.
-- * Header.Get and header.get return the first value of a canonical key, or ""
--   when it is absent; headers are kept under their canonical names.
-- * The ResponseWriter is reduced to the Etag header it carries and the status
--   WriteHeader is given, which checkPreconditions returns alongside its own
--   results.
module Port.GoFs
  ( Time (..)
  , Request (..)
  , Writer (..)
  , CondResult (..)
  , scanETag
  , etagStrongMatch
  , etagWeakMatch
  , checkIfMatch
  , checkIfUnmodifiedSince
  , checkIfNoneMatch
  , checkIfModifiedSince
  , checkIfRange
  , checkPreconditions
  , statusPreconditionFailed
  , statusNotModified
  ) where

import Data.Char (isDigit)
import Data.List (isPrefixOf)

-- | Unix seconds, or Go's zero Time (year 1, before every Unix time here).
data Time = ZeroTime | Unix Integer
  deriving (Eq, Show)

-- time.Time.IsZero
isZero :: Time -> Bool
isZero ZeroTime = True
isZero (Unix _) = False

-- time.Time.Compare
compareTime :: Time -> Time -> Int
compareTime ZeroTime ZeroTime = 0
compareTime ZeroTime (Unix _) = -1
compareTime (Unix _) ZeroTime = 1
compareTime (Unix a) (Unix b) = case compare a b of
  LT -> -1
  EQ -> 0
  GT -> 1

-- time.Time.Unix; Go's zero Time is -62135596800 seconds.
unixOf :: Time -> Integer
unixOf ZeroTime = -62135596800
unixOf (Unix s) = s

-- ParseTime, reduced to decimal seconds (see the module header).
parseTime :: String -> Either String Time
parseTime s
  | not (null s) && all isDigit s = Right (Unix (read s))
  | otherwise                     = Left "parsing time"

data Request = Request { method :: String, header :: [(String, String)] }
  deriving (Show)

-- Header.Get / header.get
hGet :: Request -> String -> String
hGet r k = maybe "" id (lookup k (header r))

-- | The response's Etag header, "" when unset.
newtype Writer = Writer { wEtag :: String }
  deriving (Show)

statusPreconditionFailed, statusNotModified :: Int
statusPreconditionFailed = 412
statusNotModified = 304

-- textproto.TrimString: trims ASCII space, tab, newline and carriage return.
trimString :: String -> String
trimString = reverse . dropWhile isASCIISpace . reverse . dropWhile isASCIISpace
  where
    isASCIISpace c = c == ' ' || c == '\t' || c == '\n' || c == '\r'

-- strings.TrimPrefix
trimPrefix :: String -> String -> String
trimPrefix p s
  | p `isPrefixOf` s = drop (length p) s
  | otherwise        = s

-- fs.go:431-454
scanETag :: String -> (String, String)
scanETag s0 =
  let s = trimString s0
      start = if "W/" `isPrefixOf` s then 2 else 0
  in if length (drop start s) < 2 || s !! start /= '"'
       then ("", "")
       else loop s (start + 1)
  where
    loop s i
      | i >= length s = ("", "")
      | otherwise =
          let c = s !! i
          in if c == '\x21' || c >= '\x23' && c <= '\x7E' || c >= '\x80'
               then loop s (i + 1)
               else if c == '"'
                 then (take (i + 1) s, drop (i + 1) s)
                 else ("", "")

-- fs.go:458-460
etagStrongMatch :: String -> String -> Bool
etagStrongMatch a b = a == b && a /= "" && head' a == '"'
  where
    head' (c : _) = c
    head' []      = '\0'

-- fs.go:464-466
etagWeakMatch :: String -> String -> Bool
etagWeakMatch a b = trimPrefix "W/" a == trimPrefix "W/" b

-- fs.go:470-476
data CondResult = CondNone | CondTrue | CondFalse
  deriving (Eq, Show, Enum, Bounded)

-- fs.go:478-506
checkIfMatch :: Writer -> Request -> CondResult
checkIfMatch w r =
  let im = hGet r "If-Match"
  in if im == "" then CondNone else loop im
  where
    loop im0 =
      let im = trimString im0
      in case im of
           []        -> CondFalse                     -- break; return condFalse
           (',' : t) -> loop t
           ('*' : _) -> CondTrue
           _ ->
             let (etag, remain) = scanETag im
             in if etag == ""
                  then CondFalse                      -- break; return condFalse
                  else if etagStrongMatch etag (wEtag w)
                    then CondTrue
                    else loop remain

-- fs.go:508-525
checkIfUnmodifiedSince :: Request -> Time -> CondResult
checkIfUnmodifiedSince r modtime =
  let ius = hGet r "If-Unmodified-Since"
  in if ius == "" || isZeroTime modtime
       then CondNone
       else case parseTime ius of
              Left _  -> CondNone
              Right t -> if compareTime modtime t <= 0 then CondTrue else CondFalse

-- fs.go:527-555
checkIfNoneMatch :: Writer -> Request -> CondResult
checkIfNoneMatch w r =
  let inm = hGet r "If-None-Match"
  in if inm == "" then CondNone else loop inm
  where
    loop buf0 =
      let buf = trimString buf0
      in case buf of
           []        -> CondTrue                      -- break; return condTrue
           (',' : t) -> loop t
           ('*' : _) -> CondFalse
           _ ->
             let (etag, remain) = scanETag buf
             in if etag == ""
                  then CondTrue                       -- break; return condTrue
                  else if etagWeakMatch etag (wEtag w)
                    then CondFalse
                    else loop remain

-- fs.go:557-576
checkIfModifiedSince :: Request -> Time -> CondResult
checkIfModifiedSince r modtime
  | method r /= "GET" && method r /= "HEAD" = CondNone
  | otherwise =
      let ims = hGet r "If-Modified-Since"
      in if ims == "" || isZeroTime modtime
           then CondNone
           else case parseTime ims of
                  Left _  -> CondNone
                  Right t -> if compareTime modtime t <= 0 then CondFalse else CondTrue

-- fs.go:578-607
checkIfRange :: Writer -> Request -> Time -> CondResult
checkIfRange w r modtime
  | method r /= "GET" && method r /= "HEAD" = CondNone
  | otherwise =
      let ir = hGet r "If-Range"
      in if ir == ""
           then CondNone
           else
             let (etag, _) = scanETag ir
             in if etag /= ""
                  then if etagStrongMatch etag (wEtag w) then CondTrue else CondFalse
                  else if isZero modtime
                    then CondFalse
                    else case parseTime ir of
                           Left _  -> CondFalse
                           Right t -> if unixOf t == unixOf modtime then CondTrue else CondFalse

-- fs.go:609-614
isZeroTime :: Time -> Bool
isZeroTime t = isZero t || t == unixEpochTime
  where
    unixEpochTime = Unix 0

-- | fs.go:640-671. Returns the status WriteHeader was given, if any, then
-- Go's own (done, rangeHeader).
checkPreconditions :: Writer -> Request -> Time -> (Maybe Int, Bool, String)
checkPreconditions w r modtime =
  let ch0 = checkIfMatch w r
      ch = if ch0 == CondNone then checkIfUnmodifiedSince r modtime else ch0
  in if ch == CondFalse
       then (Just statusPreconditionFailed, True, "")
       else case checkIfNoneMatch w r of
              CondFalse ->
                if method r == "GET" || method r == "HEAD"
                  then (Just statusNotModified, True, "")     -- writeNotModified
                  else (Just statusPreconditionFailed, True, "")
              CondNone
                | checkIfModifiedSince r modtime == CondFalse ->
                    (Just statusNotModified, True, "")        -- writeNotModified
              _ ->
                let rangeHeader0 = hGet r "Range"
                    rangeHeader =
                      if rangeHeader0 /= "" && checkIfRange w r modtime == CondFalse
                        then ""
                        else rangeHeader0
                in (Nothing, False, rangeHeader)
