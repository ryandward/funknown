{-# LANGUAGE Safe #-}
-- | Readers for the vendored registries, written apart from gen-vocab's on
-- purpose: the comparison only means something if a generator bug can't
-- also be a reader bug here.
module Registries.Vendored
  ( csvRows
  , protoEnum
  , aipSections
  , xmlRecords
  , draftRequests
  ) where

import Data.Char (isDigit, isSpace)
import Data.List (isPrefixOf, stripPrefix)

-- | RFC 4180 records: quoted fields may hold commas, "" and line breaks.
csvRows :: String -> [[String]]
csvRows = records . filter (/= '\r')
  where
    records [] = []
    records s = let (r, rest) = record s in r : records rest
    record s = case fieldOf s of
      (f, ',' : rest) -> let (fs, rest') = record rest in (f : fs, rest')
      (f, '\n' : rest) -> ([f], rest)
      (f, rest) -> ([f], rest)
    fieldOf ('"' : s) = quoted s
    fieldOf s = break (`elem` ",\n") s
    quoted ('"' : '"' : s) = let (f, r) = quoted s in ('"' : f, r)
    quoted ('"' : s) = ("", s)
    quoted (c : s) = let (f, r) = quoted s in (c : f, r)
    quoted [] = ("", "")

trim :: String -> String
trim = dropWhile isSpace . reverse . dropWhile isSpace . reverse

-- | (name, number) for each "NAME = N;" line between "enum Code {" and "}".
protoEnum :: String -> [(String, Int)]
protoEnum src =
  [ (name, read (takeWhile isDigit num))
  | l <- takeWhile ((/= "}") . trim) (drop 1 (dropWhile ((/= "enum Code {") . trim) (lines src)))
  , let t = trim l
  , not ("//" `isPrefixOf` t)
  , [name, "=", num] <- [words t]
  ]

-- | Each "### ... codes" heading of AIP-194 with the backquoted names of
-- its bullets.
aipSections :: String -> [(String, [String])]
aipSections = go . lines
  where
    go [] = []
    go (l : ls) = case stripPrefix "### " l of
      Just h | Just _ <- stripPrefix (reverse "codes") (reverse (heading h)) -> sec (heading h) ls
      _ -> go ls
    heading = reverse . dropWhile (== ':') . reverse
    sec h ls =
      let (body, rest) = break ("#" `isPrefixOf`) ls
       in (h, [takeWhile (/= '`') n | b <- body, Just n <- [stripPrefix "- `" b]]) : go rest

-- | (key, status) of each <record>, by plain string search.
xmlRecords :: String -> [(String, String)]
xmlRecords s = case breakOn "<record" s of
  Nothing -> []
  Just rest ->
    let (body, after) = splitOn "</record>" rest
     in (inner "key" body, inner "status" body) : xmlRecords after
  where
    inner tag body = case breakOn ("<" ++ tag ++ ">") body of
      Just r -> trim (fst (splitOn ("</" ++ tag ++ ">") r))
      Nothing -> ""

breakOn :: String -> String -> Maybe String
breakOn p s
  | p `isPrefixOf` s = Just (drop (length p) s)
  | null s = Nothing
  | otherwise = breakOn p (drop 1 s)

splitOn :: String -> String -> (String, String)
splitOn p s
  | p `isPrefixOf` s = ("", drop (length p) s)
  | null s = ("", "")
  | otherwise = let (a, b) = splitOn p (drop 1 s) in (take 1 s ++ a, b)

-- | (type URI, title, recommended status) for each request in section 14.4
-- of the upload draft.
draftRequests :: String -> [(String, String, Int)]
draftRequests src = entries section
  where
    section =
      [ t
      | l <- takeWhile (not . startsDigit) (drop 1 (dropWhile ((/= "14.4.  HTTP Problem Types") . trim) (lines src)))
      , let t = trim l
      , not (null t)
      , not ("Kleidl" `isPrefixOf` t)
      , not ("Internet-Draft" `isPrefixOf` t)
      ]
    startsDigit l = case l of
      c : _ -> isDigit c
      [] -> False
    entries ls = case dropWhile (not . ("Type URI:" `isPrefixOf`)) ls of
      u : cont : more ->
        let uri = trim (drop (length "Type URI:") u) ++ cont
            title = value "Title:" more
            code = value "Recommended HTTP status code:" more
         in (uri, title, read code) : entries more
      _ -> []
    value k ls = case [trim (drop (length k) l) | l <- ls, k `isPrefixOf` l] of
      v : _ -> v
      [] -> ""
