{-# LANGUAGE Safe #-}
-- | Just enough JSON (RFC 8259) to read the vendored statements.json files.
module Funknown.Tools.Json (Json (..), parseJson, field, string) where

import Data.Char (chr, isDigit, isHexDigit, isSpace)
import Numeric (readHex)

data Json
  = JNull
  | JBool Bool
  | JNumber String
  | JString String
  | JArray [Json]
  | JObject [(String, Json)]
  deriving (Eq, Show)

field :: String -> Json -> Maybe Json
field k (JObject kvs) = lookup k kvs
field _ _ = Nothing

string :: Json -> Maybe String
string (JString s) = Just s
string _ = Nothing

parseJson :: String -> Either String Json
parseJson s = case value (skip s) of
  Right (v, rest) | all isSpace rest -> Right v
  Right (_, rest) -> Left ("trailing input: " ++ take 20 rest)
  Left e -> Left e

type P a = String -> Either String (a, String)

skip :: String -> String
skip = dropWhile isSpace

value :: P Json
value ('{' : s) = object (skip s)
value ('[' : s) = array (skip s)
value ('"' : s) = fmap (\(t, r) -> (JString t, r)) (str "" s)
value ('t' : 'r' : 'u' : 'e' : s) = Right (JBool True, s)
value ('f' : 'a' : 'l' : 's' : 'e' : s) = Right (JBool False, s)
value ('n' : 'u' : 'l' : 'l' : s) = Right (JNull, s)
value s@(c : _) | c == '-' || isDigit c = let (n, r) = span (`elem` "+-.eE0123456789") s in Right (JNumber n, r)
value s = Left ("unexpected input: " ++ take 20 s)

object :: P Json
object ('}' : s) = Right (JObject [], s)
object s = members [] s
  where
    members acc ('"' : t) = do
      (k, r1) <- str "" t
      r2 <- expect ':' (skip r1)
      (v, r3) <- value (skip r2)
      case skip r3 of
        ',' : r4 -> members ((k, v) : acc) (skip r4)
        '}' : r4 -> Right (JObject (reverse ((k, v) : acc)), r4)
        r4 -> Left ("expected , or } at " ++ take 20 r4)
    members _ t = Left ("expected a key at " ++ take 20 t)

array :: P Json
array (']' : s) = Right (JArray [], s)
array s = elems [] s
  where
    elems acc t = do
      (v, r1) <- value (skip t)
      case skip r1 of
        ',' : r2 -> elems (v : acc) (skip r2)
        ']' : r2 -> Right (JArray (reverse (v : acc)), r2)
        r2 -> Left ("expected , or ] at " ++ take 20 r2)

expect :: Char -> String -> Either String String
expect c (d : s) | c == d = Right s
expect c s = Left ("expected " ++ show c ++ " at " ++ take 20 s)

str :: String -> P String
str acc ('"' : s) = Right (reverse acc, s)
str acc ('\\' : c : s) = case c of
  '"' -> str ('"' : acc) s
  '\\' -> str ('\\' : acc) s
  '/' -> str ('/' : acc) s
  'b' -> str ('\b' : acc) s
  'f' -> str ('\f' : acc) s
  'n' -> str ('\n' : acc) s
  'r' -> str ('\r' : acc) s
  't' -> str ('\t' : acc) s
  'u' -> do
    (hi, r) <- hex4 s
    if hi >= 0xD800 && hi < 0xDC00
      then case r of
        '\\' : 'u' : r2 -> do
          (lo, r3) <- hex4 r2
          str (chr (0x10000 + (hi - 0xD800) * 0x400 + (lo - 0xDC00)) : acc) r3
        _ -> Left "unpaired surrogate"
      else str (chr hi : acc) r
  _ -> Left ("bad escape " ++ show c)
str acc (c : s) = str (c : acc) s
str _ [] = Left "unterminated string"

hex4 :: String -> Either String (Int, String)
hex4 s = case splitAt 4 s of
  (h, r) | length h == 4 && all isHexDigit h -> case readHex h of
    [(n, "")] -> Right (n, r)
    _ -> Left "bad \\u escape"
  _ -> Left "bad \\u escape"
