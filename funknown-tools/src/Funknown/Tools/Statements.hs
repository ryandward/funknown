{-# LANGUAGE Safe #-}
-- | The five vendored statement groups, and the bases written in generated
-- comments. A generator can only write a citation through 'basis', which
-- refuses an id its group doesn't have and a Required that cites anything
-- other than a MUST, a MUST NOT or a definition.
module Funknown.Tools.Statements
  ( Group (..)
  , groupDir
  , groupTag
  , Statement (..)
  , Statements
  , readStatements
  , statement
  , Part (..)
  , basis
  ) where

import Data.List (intercalate)
import qualified Data.Map.Strict as Map
import Funknown.Tools.Json

data Group = HS | PD | UP | DO | SS
  deriving (Eq, Ord, Show, Enum, Bounded)

groupDir :: Group -> FilePath
groupDir HS = "http-semantics"
groupDir PD = "problems-and-digests"
groupDir UP = "uploads"
groupDir DO = "drive-and-objects"
groupDir SS = "status-and-supervision"

groupTag :: Group -> String
groupTag = show

data Statement = Statement
  { stLevel :: String
  , stSection :: String
  , stQuote :: String
  }
  deriving (Show)

type Statements = Map.Map (Group, String) Statement

-- | Parse one group's statements.json (the caller reads the file).
readStatements :: Group -> String -> Either String Statements
readStatements g src = do
  j <- either (Left . ((groupDir g ++ "/statements.json: ") ++)) Right (parseJson src)
  items <- case j of
    JArray xs -> Right xs
    _ -> Left (groupDir g ++ "/statements.json is not an array")
  Map.fromList <$> mapM one items
  where
    one o = case (str "id", str "level", str "section", str "quote") of
      (Just i, Just l, Just s, Just q) -> Right ((g, i), Statement l s q)
      _ -> Left (groupDir g ++ ": a statement lacks id, level, section or quote")
      where
        str k = field k o >>= string

statement :: Statements -> Group -> String -> Either String Statement
statement sts g i = maybe (Left ("no statement " ++ groupTag g ++ ":" ++ i)) Right (Map.lookup (g, i) sts)

-- | One part of a basis, as the design writes it.
data Part
  = R [(Group, String)]
  | P [(Group, String)] String -- ^ citations and the Permitted register entry
  | C String -- ^ the Chosen register entry

-- | Render a basis after checking every citation in it.
basis :: Statements -> [Part] -> Either String String
basis sts parts = intercalate "; " <$> mapM render parts
  where
    render (R cs) = do
      mapM_ required cs
      pure ("R " ++ cites cs)
    render (P cs pm) = do
      mapM_ (\(g, i) -> statement sts g i) cs
      pure ("P " ++ cites cs ++ " (" ++ pm ++ ")")
    render (C ch) = pure ("C " ++ ch)
    required (g, i) = do
      s <- statement sts g i
      if stLevel s `elem` ["MUST", "MUST NOT", "definition"]
        then Right ()
        else Left ("R cites " ++ groupTag g ++ ":" ++ i ++ ", whose level is " ++ stLevel s)
    cites = intercalate ", " . map (\(g, i) -> groupTag g ++ ":" ++ i)
