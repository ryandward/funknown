{-# LANGUAGE Safe #-}
-- | Funknown.Http.Status from the IANA HTTP Status Code Registry CSV.
module Funknown.Tools.Gen.Status (Row (..), Reg (..), statusRows, conName, genStatus) where

import Data.Char (isDigit)
import Data.List (intercalate, isInfixOf, isSuffixOf, sort)
import Funknown.Tools.Csv (parseCsv)
import Funknown.Tools.Emit
import Funknown.Tools.Statements

data Reg = Permanent | Temporary | Obsoleted
  deriving (Eq, Show)

-- | One registry row. The CSV has three kinds: an assigned code, an
-- "(Unused)" code, and an unassigned range.
data Row
  = Assigned Int String Reg -- ^ code, description, registration
  | Unused Int
  | Unassigned Int Int
  deriving (Show)

statusRows :: String -> Either String [Row]
statusRows src = do
  rows <- parseCsv src
  body <- case rows of
    ["Value", "Description", "Reference"] : b -> Right b
    _ -> Left "status CSV: unexpected header"
  rs <- mapM row body
  partition 100 rs
  pure rs
  where
    row [v, d, _] = case break (== '-') v of
      (a, '-' : b) | d == "Unassigned" -> Unassigned <$> num a <*> num b
      (a, "")
        | d == "Unassigned" -> (\n -> Unassigned n n) <$> num a
        | d == "(Unused)" -> Unused <$> num a
        | otherwise -> (\n -> Assigned n d (reg d)) <$> num a
      _ -> Left ("status CSV: bad value " ++ v)
    row r = Left ("status CSV: expected three fields in " ++ show r)
    num s
      | not (null s) && all isDigit s = Right (read s)
      | otherwise = Left ("status CSV: bad number " ++ s)
    reg d
      | "(TEMPORARY" `isInfixOf` d = Temporary
      | "(OBSOLETED)" `isInfixOf` d = Obsoleted
      | otherwise = Permanent
    -- The rows must cover 100..599 once each, in order (HS:RFC9110-15-5).
    partition next [] = if next == 600 then Right () else Left "status CSV: rows stop before 599"
    partition next (r : rs) =
      let (lo, hi) = span' r
       in if lo == next && hi >= lo then partition (hi + 1) rs else Left ("status CSV: gap or overlap at " ++ show next)
    span' (Assigned n _ _) = (n, n)
    span' (Unused n) = (n, n)
    span' (Unassigned a b) = (a, b)

-- | The registry description without a trailing "(TEMPORARY ...)" or
-- "(OBSOLETED)" note, as a constructor name.
conName :: Int -> String -> String
conName n d = "H" ++ show n ++ "_" ++ pascal (stripNote d)
  where
    stripNote s
      | ")" `isSuffixOf` s, (pre, _ : _) <- breakLast s = trimEnd pre
      | otherwise = s
    breakLast s = let i = last [k | (k, c) <- zip [0 :: Int ..] s, c == '('] in (take i s, drop i s)
    trimEnd = reverse . dropWhile (== ' ') . reverse

-- | Class names from RFC 9110's own list: "* 1xx (Informational): ...".
classNames :: Statements -> Either String [String]
classNames sts = do
  s <- statement sts HS "RFC9110-15-3"
  let names = [pascal (takeWhile (/= ')') rest) | w <- tails' (stQuote s), Just rest <- [classAt w]]
  if length names == 5 then Right names else Left ("expected five classes in HS:RFC9110-15-3, got " ++ show names)
  where
    tails' xs = case xs of
      [] -> []
      _ : t -> xs : tails' t
    classAt w = case w of
      d : 'x' : 'x' : ' ' : '(' : rest | d `elem` "12345" -> Just rest
      _ -> Nothing

genStatus :: Statements -> Source -> String -> Either String String
genStatus sts src csv = do
  rows <- statusRows csv
  classes <- classNames sts
  let assigned = [(n, d, r) | Assigned n d r <- rows]
      con (n, d, _) = conName n d
      cons = map con assigned
      classOfN n = classes !! (n `div` 100 - 1)
      x00 k = case [c | a@(n, _, _) <- assigned, let c = con a, n == 100 * k] of
        [c] -> Right c
        _ -> Left ("no registered x00 code for class " ++ show k)
      temporaries = [n | (n, _, Temporary) <- assigned]
      obsoleted = [n | (n, _, Obsoleted) <- assigned]
      unused = [n | Unused n <- rows]
      rowCite n = (HS, "IANA-HTTP-Status-Codes-" ++ show n)
      width = maximum (map length cons)
      padTo s = s ++ replicate (width - length s) ' '
  bases <- mapM (\(n, _, _) -> basis sts [R [rowCite n]]) assigned
  classBasis <- basis sts [R [(HS, "RFC9110-15-3"), (HS, "RFC9110-15-2")]]
  unusedBasis <- basis sts [R (map rowCite unused ++ [(HS, "RFC9110-15.5.19")])]
  tempBasis <- basis sts [R (map rowCite temporaries)]
  obsBasis <- basis sts [R (map rowCite obsoleted)]
  wireBasis <- basis sts [R [(HS, "RFC9110-15-4"), (HS, "RFC9110-15-5")], P [(HS, "RFC9110-15-6")] "PM38"]
  (firstCode, lastCode, h500, informational) <- case (assigned, [a | a@(500, _, _) <- assigned], classes) of
    ((n0, _, _) : _, [a500], c1 : _) -> Right (n0, last [n | (n, _, _) <- assigned], conName 500 (snd3 a500), c1)
    _ -> Left "status CSV: no assigned rows, or no single 500"
  v1Basis <- basis sts [R [(HS, "RFC9110-15-1"), rowCite firstCode, rowCite lastCode]]
  v2Basis <- basis sts [R (map rowCite (temporaries ++ obsoleted)), P [(UP, "RESUMABLE-UPLOAD-13-4.4.2-8"), (UP, "RESUMABLE-UPLOAD-13-4.2.2-7")] "PM10"]
  bases0 <- mapM x00 [1 .. 5]
  descs <- mapM (\(_, d, _) -> hsString d) assigned
  checkIdentifiers (cons ++ classes)
  let cases f = [padTo c ++ " = " ++ f a | (a, c) <- zip assigned cons]
      proofCases name = [name ++ " " ++ c ++ " = ()" | c <- cons]
      -- 499 is code.proto's "Client Closed Request", which the registry lacks
      excluded = sort (temporaries ++ unused ++ obsoleted ++ [499])
      regName Permanent = "Permanent"
      regName Temporary = "Temporary"
      regName Obsoleted = "Obsoleted"
  pure . unlines $
    header "the IANA HTTP Status Code Registry" [src]
      ++ [ "{-# LANGUAGE Safe #-}"
         , "{-@ LIQUID \"--reflection\" @-}"
         , "{-@ LIQUID \"--ple\" @-}"
         , "-- | HTTP status codes: one constructor per assigned registry row, except the"
         , "-- \"(Unused)\" rows " ++ intercalate " and " (map show unused) ++ ", which define no semantics and so"
         , "-- can't be represented (" ++ unusedBasis ++ ")."
         , "module Funknown.Http.Status"
         , "  ( Status (..)"
         , "  , Registration (..)"
         , "  , Class (..)"
         , "  , statusCode"
         , "  , description"
         , "  , registration"
         , "  , classOf"
         , "  , valid"
         , "  , registered"
         , "  , classOfCode"
         , "  , classBase"
         , "  , fromWire"
         , "  , respondable"
         , "  , classAgrees"
         , "  , roundTrip"
         , "  , statusCodeInjective"
         , "  , respondableCode"
         , "  ) where"
         , ""
         , "import Funknown.Proof (Proof, (?))"
         , ""
         , "-- | How the registry lists a code. Temporary and Obsoleted exist so that"
         , "-- 'fromWire' can name what it receives; 'respondable' excludes them."
         , "data Registration"
         , "  = Permanent -- R its row: every row without a TEMPORARY or OBSOLETED note"
         , "  | Temporary -- " ++ tempBasis
         , "  | Obsoleted -- " ++ obsBasis
         , "  deriving (Eq, Show, Enum, Bounded)"
         , ""
         , "-- | " ++ classBasis ++ "."
         , "data Class = " ++ intercalate " | " classes
         , "  deriving (Eq, Show, Enum, Bounded)"
         , ""
         , "data Status"
         ]
      ++ [ (if i == 0 then "  = " else "  | ") ++ padTo c ++ " -- " ++ b
         | (i, c, b) <- zip3 [0 :: Int ..] cons bases
         ]
      ++ [ "  deriving (Eq, Show, Enum, Bounded)"
         , ""
         , "{-@ reflect statusCode @-}"
         , "{-@ statusCode :: Status -> {v:Int | 100 <= v && v <= 599 && registered v} @-}"
         , "statusCode :: Status -> Int"
         ]
      ++ map ("statusCode " ++) (cases (\(n, _, _) -> show n))
      ++ [ ""
         , "-- | The registry's Description column, verbatim."
         , "description :: Status -> String"
         ]
      ++ [ "description " ++ padTo c ++ " = " ++ d | (c, d) <- zip cons descs ]
      ++ [ ""
         , "{-@ reflect registration @-}"
         , "registration :: Status -> Registration"
         ]
      ++ map ("registration " ++) (cases (\(_, _, r) -> regName r))
      ++ [ ""
         , "-- | The class of each constructor, as a table: integer division breaks PLE"
         , "-- in reflected code, so the first digit is read off by the generator."
         , "{-@ reflect classOf @-}"
         , "classOf :: Status -> Class"
         ]
      ++ map ("classOf " ++) (cases (\(n, _, _) -> classOfN n))
      ++ [ ""
         , "-- | Values outside 100..599 are invalid (R HS:RFC9110-15-5)."
         , "{-@ inline valid @-}"
         , "valid :: Int -> Bool"
         , "valid n = 100 <= n && n <= 599"
         , ""
         , "-- | The codes the registry assigns, read from the same rows as 'statusCode'"
         , "-- but kept apart from it, so 'fromWire' is checked against both."
         , "{-@ inline registered @-}"
         , "registered :: Int -> Bool"
         , "registered n ="
         ]
      ++ wrapOr [ "n == " ++ show n | (n, _, _) <- assigned ]
      ++ [ ""
         , "-- | The class of a valid code, by its first digit (R HS:RFC9110-15-2)."
         , "{-@ reflect classOfCode @-}"
         , "classOfCode :: Int -> Class"
         , "classOfCode n"
         ]
      ++ [ "  | n < " ++ show (100 * (k + 1)) ++ " = " ++ c | (k, c) <- zip [1 :: Int .. 4] classes ]
      ++ [ "  | otherwise = " ++ classes !! 4
         , ""
         , "-- | Each class's x00 code, which an unrecognized code of that class is"
         , "-- treated as (R HS:RFC9110-15-4)."
         , "{-@ reflect classBase @-}"
         , "classBase :: Class -> Status"
         ]
      ++ [ "classBase " ++ c ++ " = " ++ b | (c, b) <- zip classes bases0 ]
      ++ [ ""
         , "-- | Decode a status received from an origin."
         , "-- " ++ wireBasis ++ "."
         , "-- SF9: a valid code keeps its class, a registered one maps to itself, an"
         , "-- unregistered or Unused one becomes its class's x00, and an invalid one"
         , "-- becomes 500."
         , "{-@ reflect fromWire @-}"
         , "{-@ fromWire :: n:Int -> {v:Status | (valid n => classOf v == classOfCode n)"
         , "                                  && (valid n && registered n => statusCode v == n)"
         , "                                  && (valid n && not (registered n) => v == classBase (classOfCode n))"
         , "                                  && (not (valid n) => v == " ++ h500 ++ ")} @-}"
         , "fromWire :: Int -> Status"
         , "fromWire n"
         ]
      ++ [ "  | n == " ++ show n ++ " = " ++ c | ((n, _, _), c) <- zip assigned cons ]
      ++ [ "  | n < 100 = " ++ h500 ++ " -- invalid" ]
      ++ [ "  | n < " ++ show (100 * (k + 1)) ++ " = " ++ b ++ " -- unregistered " ++ show k ++ "xx"
         | (k, b) <- zip [1 :: Int .. 5] bases0
         ]
      ++ [ "  | otherwise = " ++ h500 ++ " -- invalid"
         , ""
         , "-- | A status a response we send may carry: Permanent, and final rather than"
         , "-- interim. " ++ v2Basis ++ "."
         , "{-@ reflect respondable @-}"
         , "respondable :: Status -> Bool"
         , "respondable s = case registration s of"
         , "  Permanent -> case classOf s of"
         , "    " ++ informational ++ " -> False"
         , "    _ -> True"
         , "  Temporary -> False"
         , "  Obsoleted -> False"
         , ""
         , "-- | The class table agrees with the first digit of every code."
         , "{-@ classAgrees :: s:Status -> {classOf s == classOfCode (statusCode s)} @-}"
         , "classAgrees :: Status -> Proof"
         ]
      ++ proofCases "classAgrees"
      ++ [ ""
         , "-- | V1: decoding a code we can represent gives back the same constructor. " ++ v1Basis ++ "."
         , "{-@ roundTrip :: s:Status -> {fromWire (statusCode s) == s} @-}"
         , "roundTrip :: Status -> Proof"
         ]
      ++ proofCases "roundTrip"
      ++ [ ""
         , "-- | V1: so no two constructors share a code."
         , "{-@ statusCodeInjective :: a:Status -> b:{Status | statusCode a == statusCode b} -> {a == b} @-}"
         , "statusCodeInjective :: Status -> Status -> Proof"
         , "statusCodeInjective a b = () ? roundTrip a ? roundTrip b"
         , ""
         , "-- | V2, the Status half: a respondable status is final, and it is none of"
         , "-- the codes " ++ intercalate ", " (map show excluded) ++ "."
         , "{-@ respondableCode :: s:{Status | respondable s} -> {200 <= statusCode s"
         ]
      ++ [ "                                                    && statusCode s /= " ++ show n
         | n <- excluded
         ]
      ++ [ "                                                    } @-}"
         , "respondableCode :: Status -> Proof"
         ]
      ++ proofCases "respondableCode"
  where
    wrapOr xs = case chunks 6 xs of
      [] -> ["  False"]
      (c : cs) -> ("     " ++ intercalate " || " c) : map (\c' -> "  || " ++ intercalate " || " c') cs
    snd3 (_, d, _) = d
    chunks _ [] = []
    chunks k ys = take k ys : chunks k (drop k ys)
