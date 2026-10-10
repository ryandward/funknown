{-# LANGUAGE Safe #-}
-- | Funknown.Problem from the IANA HTTP Problem Types registry and the upload
-- draft's section 14.4. Which rows the core uses, and the members each one
-- carries, are the core's choice and live in 'used' below; everything the
-- registry or the draft says about a row is read from the vendored files.
module Funknown.Tools.Gen.Problem (ProblemRow (..), problemRows, draftRows, genProblem) where

import Data.Char (isDigit, isSpace, toLower)
import Data.List (intercalate, isPrefixOf)
import Funknown.Tools.Csv (parseCsv)
import Funknown.Tools.Emit
import Funknown.Tools.Gen.Status (Reg (..), Row (..), conName, statusRows)
import Funknown.Tools.Statements

data ProblemRow = ProblemRow {prUri :: String, prTitle :: String, prStatus :: Maybe Int}
  deriving (Show)

problemRows :: String -> Either String [ProblemRow]
problemRows src = do
  rows <- parseCsv src
  case rows of
    ["Type URI", "Title", "Recommended HTTP Status Code", "Reference"] : body -> mapM row body
    _ -> Left "problem types CSV: unexpected header"
  where
    row [u, t, s, _] = ProblemRow u t <$> status s
    row r = Left ("problem types CSV: expected four fields in " ++ show r)
    status "N/A" = Right Nothing
    status s
      | not (null s) && all isDigit s = Right (Just (read s))
      | otherwise = Left ("problem types CSV: bad status " ++ s)

-- | The draft's IANA requests in section 14.4. A Type URI is wrapped after a
-- hyphen, so its continuation line is joined without a space.
draftRows :: String -> Either String [ProblemRow]
draftRows src = case break (("14.4.  HTTP Problem Types" ==) . trim) (lines src) of
  (_, []) -> Left "draft: no section 14.4"
  (_, _ : rest) -> entries (filter (not . pageFurniture) (takeWhile (not . nextSection) rest))
  where
    nextSection l = case l of
      c : _ -> isDigit c
      [] -> False
    pageFurniture l = "Kleidl, et al." `isPrefixOf` l || "Internet-Draft" `isPrefixOf` l || "\f" `isPrefixOf` l
    entries ls = case dropWhile (not . ("Type URI:" `isPrefixOf`) . trim) ls of
      [] -> Right []
      u : more -> do
        let uriHead = trim (drop (length "Type URI:") (trim u))
            (cont, after) = span (\l -> not (null (trim l)) && not (':' `elem` takeWhile (/= ' ') (trim l))) more
            uri = uriHead ++ concatMap trim cont
        title <- valueOf "Title:" after
        code <- valueOf "Recommended HTTP status code:" after
        if all isDigit code && not (null code)
          then (ProblemRow uri title (Just (read code)) :) <$> entries after
          else Left ("draft: bad status " ++ code)
    valueOf k ls = case [trim (drop (length k) (trim l)) | l <- takeWhile (not . ("Type URI:" `isPrefixOf`) . trim) ls, k `isPrefixOf` trim l] of
      [v] -> Right v
      _ -> Left ("draft: expected one " ++ k)

trim :: String -> String
trim = dropWhile isSpace . reverse . dropWhile isSpace . reverse

-- | A problem type the core uses: its type URI, whether it comes from the
-- draft, the constructor of 'Problem' that carries it and that constructor's
-- members, and its basis.
data Use = Use
  { uUri :: String
  , uDraft :: Bool
  , uCon :: String
  , uFields :: [(String, String, String)] -- ^ field, Haskell type, refinement type
  , uMembers :: String -- ^ the members' wire names, for the comment
  , uBasis :: [Part]
  }

prefix :: String
prefix = "https://iana.org/assignments/http-problem-types#"

used :: [Use]
used =
  [ Use "about:blank" False "Blank" [] "none"
      [R [(PD, "IANA-PROBLEM-TYPES-about:blank-1"), (PD, "RFC9457-4.2.1-1"), (PD, "RFC9457-3.1.1-2")], P [(PD, "RFC9457-4.2.1-2")] "PM35"]
  , Use (prefix ++ "digest-unsupported-algorithms") False "UnsupportedAlgorithms"
      [("unsupportedAlgorithms", "[Unsupported]", "[Unsupported]")] "unsupported_algorithms"
      [R [(PD, "IANA-PROBLEM-TYPES-digest-unsupported-algorithms-1"), (PD, "DIGEST-PROBLEMS-3.1-2")], P [(PD, "DIGEST-PROBLEMS-3.1-1")] "PM24"]
  , Use (prefix ++ "mismatching-upload-offset") True "MismatchingOffset"
      [("expectedOffset", "Int", "Nat"), ("providedOffset", "Int", "Nat")] "expected-offset, provided-offset"
      [R [(UP, "RESUMABLE-UPLOAD-13-14.4-1")], P [(UP, "RESUMABLE-UPLOAD-13-7.1-1"), (UP, "RESUMABLE-UPLOAD-13-7.1-2")] "PM23"]
  , Use (prefix ++ "inconsistent-upload-length") True "InconsistentLength" [] "none"
      [R [(UP, "RESUMABLE-UPLOAD-13-14.4-2")], P [(UP, "RESUMABLE-UPLOAD-13-7.2-1")] "PM23"]
  ]

typeCon :: String -> String
typeCon uri
  | prefix `isPrefixOf` uri = pascal (drop (length prefix) uri)
  | otherwise = pascal uri

genProblem :: Statements -> [Source] -> Bool -> String -> String -> String -> Either String String
genProblem sts srcs draftOn statusCsv csv draft = do
  srows <- statusRows statusCsv
  registered <- problemRows csv
  requested <- draftRows draft
  let statusCon n = case [c | Assigned m d r <- srows, m == n, r == Permanent, let c = conName m d] of
        [c] -> Right c
        _ -> Left ("no Permanent status " ++ show n ++ " for a recommended problem status")
      find u = case [r | r <- (if uDraft u then requested else registered), prUri r == uUri u] of
        [r] -> Right r
        _ -> Left ("no single " ++ (if uDraft u then "draft" else "registry") ++ " row for " ++ uUri u)
  rows <- mapM find used
  recs <- mapM (\r -> maybe (Right "Absent") (fmap ("Present " ++) . statusCon) (prStatus r)) rows
  bases <- mapM (basis sts . uBasis) used
  uris <- mapM (hsString . prUri) rows
  titles <- mapM (hsString . prTitle) rows
  noStatusBasis <- basis sts [R [(PD, "RFC9457-3.1.2-2")]]
  memberBasis <- basis sts [R [(PD, "DIGEST-PROBLEMS-3.1-3"), (PD, "DIGEST-PROBLEMS-3.1-4")]]
  flagBasis <- basis sts [P [(UP, "RESUMABLE-UPLOAD-13-7.1-1"), (UP, "RESUMABLE-UPLOAD-13-7.1-2"), (UP, "RESUMABLE-UPLOAD-13-7.2-1")] "PM23"]
  let tcons = map (typeCon . uUri) used
      w = maximum (map length tcons)
      padTo s = s ++ replicate (w - length s) ' '
      pcons = map uCon used
      ww = maximum (map (length . paren . wildcard) used)
      wpad s = s ++ replicate (ww - length s) ' '
      wildcard u = unwords (uCon u : replicate (length (allFields u)) "_")
      drafts = filter uDraft used
  checkIdentifiers (tcons ++ pcons ++ [f | u <- used, (f, _, _) <- allFields u] ++ map smart drafts ++ ["Unsupported", "unsupportedKey", "unsupportedField", "DraftOn"])
  pure . unlines $
    header "the IANA HTTP Problem Types registry and draft-ietf-httpbis-resumable-upload-13 section 14.4" srcs
      ++ [ "{-# LANGUAGE Safe #-}"
         , "{-@ LIQUID \"--reflection\" @-}"
         , "{-@ LIQUID \"--ple\" @-}"
         , "-- | The problem types the core emits: the registered rows it uses, and the"
         , "-- upload draft's two IANA requests, which the core can't build while"
         , "-- 'draftProblemTypes' is off. A Problem has no status field: the renderer"
         , "-- copies the response's status in, so the two can't disagree (" ++ noStatusBasis ++ ")."
         , "-- The core never writes detail or instance."
         , "module Funknown.Problem"
         , "  ( ProblemType (..)"
         , "  , typeUri"
         , "  , registryTitle"
         , "  , recommended"
         , "  , isDraft"
         , "  , draftProblemTypes"
         , "  , Unsupported (..)"
         , "  , DraftOn (..)"
         , "  , Problem (..)"
         , "  , problemType"
         , "  , fits"
         , "  , emittable"
         ]
      ++ [ "  , " ++ smart u | u <- drafts ]
      ++ [ "  , recommendedOk"
         , "  , recommendedRespondable"
         , "  ) where"
         , ""
         , "import Funknown.Http.Status (Status (..), respondable)"
         , "import Funknown.Opt (Opt (..))"
         , "import Funknown.Proof (Proof)"
         , ""
         , "data ProblemType"
         ]
      ++ [ (if i == 0 then "  = " else "  | ") ++ padTo c ++ " -- " ++ b
         | (i, c, b) <- zip3 [0 :: Int ..] tcons bases
         ]
      ++ [ "  deriving (Eq, Show, Enum, Bounded)"
         , ""
         , "typeUri :: ProblemType -> String"
         ]
      ++ [ "typeUri " ++ padTo c ++ " = " ++ u | (c, u) <- zip tcons uris ]
      ++ [ ""
         , "-- | The Title column. For about:blank it says to use the status phrase (PM35)."
         , "registryTitle :: ProblemType -> String"
         ]
      ++ [ "registryTitle " ++ padTo c ++ " = " ++ t | (c, t) <- zip tcons titles ]
      ++ [ ""
         , "-- | The Recommended HTTP Status Code column; about:blank has none (\"N/A\"), it"
         , "-- takes the response's own."
         , "{-@ reflect recommended @-}"
         , "recommended :: ProblemType -> Opt Status"
         ]
      ++ [ "recommended " ++ padTo c ++ " = " ++ r | (c, r) <- zip tcons recs ]
      ++ [ ""
         , "{-@ reflect isDraft @-}"
         , "isDraft :: ProblemType -> Bool"
         ]
      ++ [ "isDraft " ++ padTo c ++ " = " ++ show (uDraft u) | (c, u) <- zip tcons used ]
      ++ [ ""
         , "-- | Whether the draft's problem types are sent. They are IANA requests, not"
         , "-- registrations, so this is off (" ++ flagBasis ++ "; open question 2)."
         , "-- gen-vocab --draft-problem-types turns it on."
         , "{-@ inline draftProblemTypes @-}"
         , "draftProblemTypes :: Bool"
         , "draftProblemTypes = " ++ show draftOn
         , ""
         , "-- | One entry of unsupported_algorithms: the key and the field that named it,"
         , "-- as the client sent them (" ++ memberBasis ++ ")."
         , "data Unsupported = Unsupported {unsupportedKey :: String, unsupportedField :: String}"
         , "  deriving (Eq, Show)"
         , ""
         , "-- | What a draft type's constructor carries besides its members. The field's"
         , "-- refinement is 'draftProblemTypes', so while the flag is off LiquidHaskell"
         , "-- refuses every construction of a draft type in every core module, whether"
         , "-- or not the value later passes through any particular function. The"
         , "-- constructor is exported for the exhaustive test, which runs without"
         , "-- LiquidHaskell and has to reach every constructor."
         , "data DraftOn = DraftOn"
         , "  deriving (Eq, Show)"
         , ""
         , "-- | A problem details object without its status. One constructor per type,"
         , "-- carrying that type's members, and a 'DraftOn' if the type is the draft's."
         , "data Problem"
         ]
      ++ [ (if i == 0 then "  = " else "  | ") ++ hsDecl u ++ " -- " ++ typeCon (uUri u) ++ "; members: " ++ uMembers u
         | (i, u) <- zip [0 :: Int ..] used
         ]
      ++ [ "  deriving (Eq, Show)"
         , "{-@ data Problem"
         ]
      ++ [ (if i == 0 then "      = " else "      | ") ++ lhDecl u | (i, u) <- zip [0 :: Int ..] used ]
      ++ [ "  @-}"
         , ""
         , "{-@ reflect problemType @-}"
         , "problemType :: Problem -> ProblemType"
         ]
      ++ [ "problemType " ++ wpad (paren (wildcard u)) ++ " = " ++ c | (u, c) <- zip used tcons ]
      ++ [ ""
         , "-- | A non-about:blank problem fits only its recommended status; about:blank"
         , "-- fits any."
         , "{-@ reflect fits @-}"
         , "fits :: Problem -> Status -> Bool"
         , "fits p s = case recommended (problemType p) of"
         , "  Absent -> True"
         , "  Present r -> r == s"
         , ""
         , "-- | SF8, the flag half, for every Problem the core holds, however it was"
         , "-- built: a draft type exists only while 'draftProblemTypes' is on. It"
         , "-- follows from the 'DraftOn' field's refinement, which a match brings into"
         , "-- scope."
         , "{-@ emittable :: p:Problem -> {draftProblemTypes || not (isDraft (problemType p))} @-}"
         , "emittable :: Problem -> Proof"
         ]
      ++ [ "emittable " ++ wpad (paren (wildcard u)) ++ " = ()" | u <- used ]
      ++ concat
        [ [ ""
          , "-- | How the core builds the " ++ typeCon (uUri u) ++ " problem: that problem while"
          , "-- 'draftProblemTypes' is on, about:blank otherwise, so the response keeps the"
          , "-- status the draft requires either way."
          , "{-@ reflect " ++ smart u ++ " @-}"
          , "{-@ " ++ smart u ++ " :: " ++ concat [a ++ ":" ++ r ++ " -> " | (a, (_, _, r)) <- zip args (uFields u)]
              ++ "{v:Problem | (draftProblemTypes => v == " ++ built u ++ ") && (not draftProblemTypes => v == Blank)} @-}"
          , smart u ++ " :: " ++ concat [t ++ " -> " | (_, t, _) <- uFields u] ++ "Problem"
          , unwords (smart u : take (length (uFields u)) args) ++ " = if draftProblemTypes then " ++ built u ++ " else Blank"
          ]
        | u <- drafts
        ]
      ++ [ ""
         , "{-@ reflect recommendedOk @-}"
         , "recommendedOk :: ProblemType -> Bool"
         , "recommendedOk t = case recommended t of"
         , "  Absent -> True"
         , "  Present s -> respondable s"
         , ""
         , "-- | V2 for problems: every recommended status is one a response may carry."
         , "{-@ recommendedRespondable :: t:ProblemType -> {recommendedOk t} @-}"
         , "recommendedRespondable :: ProblemType -> Proof"
         ]
      ++ [ "recommendedRespondable " ++ c ++ " = ()" | c <- tcons ]
  where
    -- A draft type's constructor takes a DraftOn first, refined by the flag.
    allFields u = [(lowerFirst (uCon u) ++ "On", "DraftOn", "{w:DraftOn | draftProblemTypes}") | uDraft u] ++ uFields u
    smart = lowerFirst . uCon
    args = ["m" ++ show i | i <- [1 :: Int ..]]
    built u = unwords (uCon u : "DraftOn" : take (length (uFields u)) args)
    lowerFirst (c : cs) = toLower c : cs
    lowerFirst [] = []
    hsDecl u = case allFields u of
      [] -> uCon u
      fs -> uCon u ++ " {" ++ intercalate ", " [f ++ " :: " ++ t | (f, t, _) <- fs] ++ "}"
    lhDecl u = case allFields u of
      [] -> uCon u
      fs -> uCon u ++ " {" ++ intercalate ", " [f ++ " :: " ++ r | (f, _, r) <- fs] ++ "}"
    paren s = if ' ' `elem` s then "(" ++ s ++ ")" else s
