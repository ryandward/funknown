{-# LANGUAGE Safe #-}
-- | Funknown.Rpc.Code from googleapis code.proto, and Funknown.Rpc.Recourse
-- from AIP-194's three code sections.
module Funknown.Tools.Gen.Rpc (protoCodes, aip194Sections, genCode, genRecourse) where

import Data.Char (isDigit, isSpace, isUpper)
import Data.List (intercalate, isPrefixOf, sortOn)
import Funknown.Tools.Emit
import Funknown.Tools.Statements

-- | The values of @enum Code@, in declaration order. Comments are skipped,
-- and a line inside the enum that isn't @NAME = N;@ is an error.
protoCodes :: String -> Either String [(String, Int)]
protoCodes src = case dropWhile (not . ("enum Code {" `isPrefixOf`) . trim) (lines src) of
  [] -> Left "code.proto: no enum Code"
  _ : body -> go (takeWhile ((/= "}") . trim) body)
  where
    go ls = mapM value [l | l <- map (trim . stripComment) ls, not (null l)]
    value l = case words (filter (/= ';') l) of
      [name, "=", n]
        | all (\c -> isUpper c || c == '_') name && not (null n) && all isDigit n && last l == ';' -> Right (name, read n)
      _ -> Left ("code.proto: unexpected line in enum Code: " ++ l)
    stripComment l = case breakOn "//" l of (a, _) -> a
    breakOn p s = case s of
      [] -> ([], [])
      c : t
        | p `isPrefixOf` s -> ([], s)
        | otherwise -> let (a, b) = breakOn p t in (c : a, b)

-- | AIP-194's code sections, in order: the heading of each "###" section
-- that lists codes (without a trailing colon), and the codes it lists.
aip194Sections :: String -> Either String [(String, [String])]
aip194Sections src = check (go (lines src))
  where
    go [] = []
    go (l : ls)
      | Just h <- heading l, isCodes h =
          let (body, rest) = break isHeading ls
           in (h, [n | b <- body, Just n <- [bullet b]]) : go rest
      | otherwise = go ls
    heading l
      | "### " `isPrefixOf` l = Just (dropColon (trim (drop 4 l)))
      | otherwise = Nothing
    isHeading l = "#" `isPrefixOf` l
    isCodes h = reverse "codes" `isPrefixOf` reverse h
    dropColon h = if not (null h) && last h == ':' then init h else h
    bullet b = case b of
      '-' : ' ' : '`' : rest
        | (n, '`' : ':' : _) <- break (== '`') rest, all (\c -> isUpper c || c == '_') n -> Just n
      _ -> Nothing
    check [] = Left "0194.md: no code sections"
    check ss
      | any (null . snd) ss = Left "0194.md: a code section lists no codes"
      | otherwise = Right ss

trim :: String -> String
trim = dropWhile isSpace . reverse . dropWhile isSpace . reverse

-- | "Non-retryable codes" -> "NonRetryable": the section's constructor, which
-- is also the infix of its statement ids.
sectionCon :: String -> String
sectionCon h = pascal (take (length h - length " codes") h)

genCode :: Statements -> Source -> String -> Either String String
genCode sts src proto = do
  codes <- protoCodes proto
  bases <- mapM (\(c, _) -> basis sts [R [(SS, "GRPC-STATUSCODES-" ++ c)]]) codes
  useBasis <- basis sts [R [(SS, "AIP151-Errors-2")]]
  checkIdentifiers (map fst codes)
  let nums = map snd codes
      lo = minimum nums
      hi = maximum nums
      w = maximum (map (length . fst) codes)
      padTo s = s ++ replicate (w - length s) ' '
      byNumber = sortOn snd codes
      names = map fst codes
  if null codes then Left "code.proto: empty enum" else Right ()
  pure . unlines $
    header "googleapis google/rpc/code.proto" [src]
      ++ [ "{-# LANGUAGE Safe #-}"
         , "{-@ LIQUID \"--reflection\" @-}"
         , "{-@ LIQUID \"--ple\" @-}"
         , "-- | The canonical error codes, as code.proto declares them. The core uses a"
         , "-- Code only in Operation.error (" ++ useBasis ++ "). code.proto's HTTP mapping"
         , "-- is not ported, because it needs 499, which the status registry doesn't have."
         , "module Funknown.Rpc.Code"
         , "  ( Code (..)"
         , "  , codeNumber"
         , "  , codeOfNumber"
         , "  , numberRoundTrip"
         , "  , numberOnto"
         , "  , codeNumberInjective"
         , "  ) where"
         , ""
         , "import Funknown.Proof (Proof, (?))"
         , ""
         , "-- | In declaration order, which isn't number order: UNAUTHENTICATED = 16 is"
         , "-- declared after PERMISSION_DENIED."
         , "data Code"
         ]
      ++ [ (if i == 0 then "  = " else "  | ") ++ padTo c ++ " -- " ++ b
         | (i, c, b) <- zip3 [0 :: Int ..] names bases
         ]
      ++ [ "  deriving (Eq, Show, Enum, Bounded)"
         , ""
         , "{-@ reflect codeNumber @-}"
         , "{-@ codeNumber :: Code -> {v:Int | " ++ show lo ++ " <= v && v <= " ++ show hi ++ "} @-}"
         , "codeNumber :: Code -> Int"
         ]
      ++ [ "codeNumber " ++ padTo c ++ " = " ++ show n | (c, n) <- codes ]
      ++ [ ""
         , "-- | The inverse of 'codeNumber' on its range, as the witness for V8."
         , "{-@ reflect codeOfNumber @-}"
         , "{-@ codeOfNumber :: {n:Int | " ++ show lo ++ " <= n && n <= " ++ show hi ++ "} -> Code @-}"
         , "codeOfNumber :: Int -> Code"
         , "codeOfNumber n"
         ]
      ++ [ "  | n == " ++ show n ++ " = " ++ c | (c, n) <- init byNumber ]
      ++ [ "  | otherwise = " ++ fst (last byNumber) ++ " -- " ++ show (snd (last byNumber))
         , ""
         , "-- | V8: 'codeOfNumber' undoes 'codeNumber', so 'codeNumber' is injective."
         , "{-@ numberRoundTrip :: c:Code -> {codeOfNumber (codeNumber c) == c} @-}"
         , "numberRoundTrip :: Code -> Proof"
         ]
      ++ [ "numberRoundTrip " ++ c ++ " = ()" | c <- names ]
      ++ [ ""
         , "-- | V8: every number in " ++ show lo ++ ".." ++ show hi ++ " is some code's number, so the image is the whole range."
         , "{-@ numberOnto :: n:{Int | " ++ show lo ++ " <= n && n <= " ++ show hi ++ "} -> {codeNumber (codeOfNumber n) == n} @-}"
         , "numberOnto :: Int -> Proof"
         , "numberOnto n"
         ]
      ++ [ "  | n == " ++ show n ++ " = ()" | (_, n) <- init byNumber ]
      ++ [ "  | otherwise = ()"
         , ""
         , "{-@ codeNumberInjective :: a:Code -> b:{Code | codeNumber a == codeNumber b} -> {a == b} @-}"
         , "codeNumberInjective :: Code -> Code -> Proof"
         , "codeNumberInjective a b = () ? numberRoundTrip a ? numberRoundTrip b"
         ]

genRecourse :: Statements -> [Source] -> String -> String -> Either String String
genRecourse sts srcs proto aip = do
  codes <- map fst <$> protoCodes proto
  sections <- aip194Sections aip
  let entries = [(sectionCon h, h, n) | (h, ns) <- sections, n <- ns]
      con n = "A_" ++ n
      names = [n | (_, _, n) <- entries]
      unlisted = [n | n <- names, n `notElem` codes]
      w = maximum (map (length . con) names)
      padTo s = s ++ replicate (w - length s) ' '
  -- every entry's statement exists and sits in the section we read it from
  mapM_
    ( \(sc, h, n) -> do
        s <- statement sts SS ("AIP194-" ++ sc ++ "-" ++ n)
        if stSection s == h then Right () else Left ("AIP194-" ++ sc ++ "-" ++ n ++ " is in section " ++ stSection s)
    )
    entries
  case [c | c <- codes, c `notElem` names] of
    [] -> Right ()
    missing -> Left ("AIP-194 lists no entry for the codes " ++ show missing ++ ", so listedAs can't be total")
  nameBases <- mapM (\(sc, _, n) -> basis sts [P [(SS, "AIP194-" ++ sc ++ "-" ++ n)] "PM42"]) entries
  secBases <- mapM (\(h, ns) -> basis sts [P [(SS, sectionId (sectionCon h) ns)] "PM42"]) sections
  checkIdentifiers (map (sectionCon . fst) sections ++ map con names)
  pure . unlines $
    header "AIP-194 and googleapis google/rpc/code.proto" srcs
      ++ [ "{-# LANGUAGE Safe #-}"
         , "{-@ LIQUID \"--reflection\" @-}"
         , "{-@ LIQUID \"--ple\" @-}"
         , "-- | What a client that follows AIP-194 does with each code. Every sentence"
         , "-- AIP-194 has here tells a client what to do and none binds our server, so"
         , "-- every constructor is Permitted under PM42: we design for that client. A"
         , "-- Recourse is never sent as a token."
         , "module Funknown.Rpc.Recourse"
         , "  ( Recourse (..)"
         , "  , Aip194Name (..)"
         , "  , recourse"
         , "  , listedAs"
         , "  , listing"
         , "  , listedAsInjective"
         , "  , listingSound"
         , "  , unlistedNames"
         , "  ) where"
         , ""
         , "import Funknown.Opt (Opt (..))"
         , "import Funknown.Proof (Proof)"
         , "import Funknown.Rpc.Code (Code (..))"
         , ""
         , "-- | AIP-194's three sections, by their own headings."
         , "data Recourse"
         ]
      ++ [ (if i == 0 then "  = " else "  | ") ++ sectionCon h ++ " -- " ++ show h ++ "; " ++ b
         | (i, (h, _), b) <- zip3 [0 :: Int ..] sections secBases
         ]
      ++ [ "  deriving (Eq, Show, Enum, Bounded)"
         , ""
         , "-- | One constructor per name AIP-194 lists, in its order. Names no"
         , "-- google.rpc.Code carries (" ++ intercalate ", " unlisted ++ ") are kept as AIP-194 lists them,"
         , "-- and 'listedAs' never reaches them."
         , "data Aip194Name"
         ]
      ++ [ (if i == 0 then "  = " else "  | ") ++ padTo (con n) ++ " -- " ++ b
         | (i, n, b) <- zip3 [0 :: Int ..] names nameBases
         ]
      ++ [ "  deriving (Eq, Show, Enum, Bounded)"
         , ""
         , "{-@ reflect recourse @-}"
         , "recourse :: Aip194Name -> Recourse"
         ]
      ++ [ "recourse " ++ padTo (con n) ++ " = " ++ sc | (sc, _, n) <- entries ]
      ++ [ ""
         , "-- | The AIP-194 entry that names each code."
         , "{-@ reflect listedAs @-}"
         , "listedAs :: Code -> Aip194Name"
         ]
      ++ [ "listedAs " ++ padTo c ++ " = " ++ con c | c <- codes ]
      ++ [ ""
         , "-- | The code an AIP-194 entry names, if google.rpc has one by that name."
         , "{-@ reflect listing @-}"
         , "listing :: Aip194Name -> Opt Code"
         ]
      ++ [ "listing " ++ padTo (con n) ++ " = " ++ (if n `elem` codes then "Present " ++ n else "Absent") | n <- names ]
      ++ [ ""
         , "-- | V8: 'listing' undoes 'listedAs', so 'listedAs' is injective."
         , "{-@ listedAsInjective :: c:Code -> {listing (listedAs c) == Present c} @-}"
         , "listedAsInjective :: Code -> Proof"
         ]
      ++ [ "listedAsInjective " ++ c ++ " = ()" | c <- codes ]
      ++ [ ""
         , "-- | V8: every name that 'listing' maps to a code is reached by that code."
         , "{-@ listingSound :: a:Aip194Name -> c:{Code | listing a == Present c} -> {listedAs c == a} @-}"
         , "listingSound :: Aip194Name -> Code -> Proof"
         ]
      ++ [ "listingSound " ++ padTo (con n) ++ " _ = ()" | n <- names ]
      ++ [ ""
         , "-- | V8: a name has no code exactly when it is " ++ intercalate " or " unlisted ++ ", so with"
         , "-- 'listedAsInjective' and 'listingSound', 'listedAs' reaches every other name"
         , "-- and never reaches " ++ intercalate " or " unlisted ++ "."
         , "{-@ unlistedNames :: a:Aip194Name -> {(listing a == Absent) <=> ("
             ++ (if null unlisted then "false" else intercalate " || " ["a == " ++ con n | n <- unlisted])
             ++ ")} @-}"
         , "unlistedNames :: Aip194Name -> Proof"
         ]
      ++ [ "unlistedNames " ++ padTo (con n) ++ " = ()" | n <- names ]
  where
    sectionId sc ns = case ns of
      _ | ("AIP194-" ++ sc ++ "-0") `elemKey` sts -> "AIP194-" ++ sc ++ "-0"
      n : _ -> "AIP194-" ++ sc ++ "-" ++ n
      [] -> "AIP194-" ++ sc ++ "-0"
    elemKey i s = either (const False) (const True) (statement s SS i)
