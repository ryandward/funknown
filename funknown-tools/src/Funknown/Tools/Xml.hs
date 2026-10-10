{-# LANGUAGE Safe #-}
-- | The subset of XML the IANA registry files use: elements, attributes,
-- text, the five predefined entities, comments and processing instructions.
-- No DTDs, no CDATA; meeting either is an error rather than a guess.
module Funknown.Tools.Xml (Node (..), parseXml, elements, children, textOf) where

import Data.Char (isSpace)
import Data.List (isPrefixOf)

data Node = Element String [(String, String)] [Node] | Text String
  deriving (Eq, Show)

-- | Every element with this name, in document order, at any depth.
elements :: String -> [Node] -> [Node]
elements n = concatMap go
  where
    go e@(Element m _ cs) = [e | m == n] ++ concatMap go cs
    go (Text _) = []

children :: String -> Node -> [Node]
children n (Element _ _ cs) = [c | c@(Element m _ _) <- cs, m == n]
children _ (Text _) = []

-- | The element's text with markup removed and whitespace runs collapsed.
textOf :: Node -> String
textOf = unwords . words . go
  where
    go (Text t) = t
    go (Element _ _ cs) = concatMap go cs

parseXml :: String -> Either String [Node]
parseXml s = do
  (ns, rest) <- nodes s
  if all isSpace rest then Right ns else Left ("unbalanced close tag at " ++ take 30 rest)

nodes :: String -> Either String ([Node], String)
nodes = go []
  where
    go acc [] = Right (reverse acc, [])
    go acc s@('<' : '/' : _) = Right (reverse acc, s)
    go acc s
      | "<?" `isPrefixOf` s = go acc (after "?>" s)
      | "<!--" `isPrefixOf` s = go acc (after "-->" s)
      | "<!" `isPrefixOf` s = Left "DTDs and CDATA are not supported"
    go acc ('<' : s) = do
      let (name, r1) = span nameChar s
      (attrs, selfClosing, r2) <- attributes [] r1
      if selfClosing
        then go (Element name attrs [] : acc) r2
        else do
          (cs, r3) <- nodes r2
          r4 <- closing name r3
          go (Element name attrs cs : acc) r4
    go acc s = do
      let (t, r) = break (== '<') s
      t' <- entities t
      go (Text t' : acc) r

    after end s
      | end `isPrefixOf` s = drop (length end) s
      | null s = s
      | otherwise = after end (drop 1 s)

    closing name s = case stripPrefix' ("</" ++ name) s of
      Just r -> case dropWhile isSpace r of
        '>' : r' -> Right r'
        _ -> Left ("malformed close tag for " ++ name)
      Nothing -> Left ("expected </" ++ name ++ "> at " ++ take 30 s)

    attributes acc s = case dropWhile isSpace s of
      '/' : '>' : r -> Right (reverse acc, True, r)
      '>' : r -> Right (reverse acc, False, r)
      r -> do
        let (k, r1) = span nameChar r
        case dropWhile isSpace r1 of
          '=' : r2 -> case dropWhile isSpace r2 of
            q : r3 | q == '"' || q == '\'' -> do
              let (v, r4) = break (== q) r3
              v' <- entities v
              if null k then Left "empty attribute name" else attributes ((k, v') : acc) (drop 1 r4)
            _ -> Left "unquoted attribute value"
          _ -> Left ("attribute without a value: " ++ k)

nameChar :: Char -> Bool
nameChar c = not (isSpace c) && c `notElem` "<>/='\""

stripPrefix' :: String -> String -> Maybe String
stripPrefix' p s = if p `isPrefixOf` s then Just (drop (length p) s) else Nothing

entities :: String -> Either String String
entities [] = Right []
entities ('&' : s) = case break (== ';') s of
  ("amp", _ : r) -> ('&' :) <$> entities r
  ("lt", _ : r) -> ('<' :) <$> entities r
  ("gt", _ : r) -> ('>' :) <$> entities r
  ("quot", _ : r) -> ('"' :) <$> entities r
  ("apos", _ : r) -> ('\'' :) <$> entities r
  (e, _) -> Left ("unsupported entity &" ++ take 10 e)
entities (c : s) = (c :) <$> entities s
