-- | A literal transcription of Go's single-range handling, bugs included:
-- parseRange (references/http-semantics/code/go/fs.go:1005-1079) and the
-- part of serveContent that turns its result into a status
-- (fs.go:311-360), plus the helpers they call (contentRange, fs.go:994-996;
-- sumRangesSize, fs.go:1103-1108). Go's int64 is 'Integer' here, with
-- ParseInt's 64-bit range check kept.
module Port.GoFsRange
  ( HttpRange (..)
  , GoAnswer (..)
  , parseRange
  , serveRange
  ) where

import Data.Char (isDigit)
import Data.List (isPrefixOf)

-- fs.go:990-992
data HttpRange = HttpRange { start :: Integer, rangeLength :: Integer }
  deriving (Eq, Show)

-- | What serveContent sends, as far as Range is concerned: a full 200, a
-- 206 with its Content-Range, or a 416 with the Content-Range it set, if any.
data GoAnswer
  = Go200
  | Go206 Integer Integer String
  | Go416 (Maybe String)
  | GoMultipart
  deriving (Eq, Show)

data GoErr = ErrNoOverlap | ErrInvalid
  deriving (Eq, Show)

-- fs.go:994-996
contentRange :: HttpRange -> Integer -> String
contentRange r size =
  "bytes " ++ show (start r) ++ "-" ++ show (start r + rangeLength r - 1) ++ "/" ++ show size

-- fs.go:1103-1108
sumRangesSize :: [HttpRange] -> Integer
sumRangesSize = sum . map rangeLength

-- textproto.TrimString: trims ASCII space and tab at both ends.
trimString :: String -> String
trimString = reverse . dropWhile isASCIISpace . reverse . dropWhile isASCIISpace
  where isASCIISpace c = c == ' ' || c == '\t' || c == '\n' || c == '\r'

-- strings.Cut
cut :: String -> Char -> (String, String, Bool)
cut s sep = case break (== sep) s of
  (before, _ : after) -> (before, after, True)
  (before, [])        -> (before, "", False)

-- strings.Split on a one-character separator
split :: String -> Char -> [String]
split s sep = case break (== sep) s of
  (a, _ : rest) -> a : split rest sep
  (a, [])       -> [a]

-- strconv.ParseInt(s, 10, 64): optional sign, then one or more digits, and
-- an error when the value doesn't fit in int64.
parseInt :: String -> Either () Integer
parseInt s0 = case s0 of
  '+' : ds -> digits 1 ds
  '-' : ds -> digits (-1) ds
  ds       -> digits 1 ds
  where
    digits sign ds
      | null ds || not (all isDigit ds) = Left ()
      | otherwise =
          let v = sign * read ds
          in if v < -9223372036854775808 || v > 9223372036854775807 then Left () else Right v

-- fs.go:1007-1079
parseRange :: String -> Integer -> Either GoErr [HttpRange]
parseRange s size
  | s == "" = Right [] -- header not present
  | not (b `isPrefixOf` s) = Left ErrInvalid
  | otherwise = go (split (drop (length b) s) ',') [] False
  where
    b = "bytes="
    go [] ranges noOverlap
      | noOverlap && null ranges = Left ErrNoOverlap
      | otherwise = Right (reverse ranges)
    go (ra0 : rest) ranges noOverlap =
      let ra = trimString ra0
      in if ra == "" then go rest ranges noOverlap else
         let (start0, end0, ok) = cut ra '-'
         in if not ok then Left ErrInvalid else
            let st = trimString start0
                en = trimString end0
            in if st == ""
                 then
                   if en == "" || take 1 en == "-" then Left ErrInvalid else
                   case parseInt en of
                     Left () -> Left ErrInvalid
                     Right i0
                       | i0 < 0 -> Left ErrInvalid
                       | otherwise ->
                           let i = if i0 > size then size else i0
                               rStart = size - i
                               rLen = size - rStart
                           in go rest (HttpRange rStart rLen : ranges) noOverlap
                 else
                   case parseInt st of
                     Left () -> Left ErrInvalid
                     Right i
                       | i < 0 -> Left ErrInvalid
                       | i >= size -> go rest ranges True -- does not overlap; continue
                       | en == "" -> go rest (HttpRange i (size - i) : ranges) noOverlap
                       | otherwise -> case parseInt en of
                           Left () -> Left ErrInvalid
                           Right j
                             | i > j -> Left ErrInvalid
                             | otherwise ->
                                 let j' = if j >= size then size - 1 else j
                                 in go rest (HttpRange i (j' - i + 1) : ranges) noOverlap

-- fs.go:311-360, for the outcomes Range decides. The multipart branch
-- (len(ranges) > 1, fs.go:361) only says that it was taken.
serveRange :: String -> Integer -> GoAnswer
serveRange rangeReq size =
  case parseRange rangeReq size of
    Left ErrNoOverlap
      | size == 0 -> afterParse []
      | otherwise -> Go416 (Just ("bytes */" ++ show size))
    Left ErrInvalid -> Go416 Nothing
    Right ranges -> afterParse ranges
  where
    afterParse ranges0 =
      let ranges = if sumRangesSize ranges0 > size then [] else ranges0
      in case ranges of
           [ra] -> Go206 (start ra) (rangeLength ra) (contentRange ra size)
           [] -> Go200
           _ -> GoMultipart
