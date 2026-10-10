{-# LANGUAGE Safe #-}
-- | Funknown.Digest from the IANA Hash Algorithms for HTTP Digest Fields
-- registry. 'Forwarded' gets one constructor per registered key that names
-- the receipt algorithm, which the CRC catalogue identifies; today there are
-- none, and the module then carries the refinement that says so.
module Funknown.Tools.Gen.Digest (DigestRecord (..), digestRecords, receiptNames, forwardedKeys, genDigest) where

import Data.Char (isAlphaNum, isSpace, toLower)
import Data.List (intercalate, isInfixOf, isPrefixOf, nub)
import Funknown.Tools.Emit
import Funknown.Tools.Statements
import Funknown.Tools.Xml

data DigestRecord = DigestRecord {drKey :: String, drStatus :: String, drDescription :: String}
  deriving (Show)

digestRecords :: String -> Either String [DigestRecord]
digestRecords src = do
  doc <- either (Left . ("digest registry: " ++)) Right (parseXml src)
  case elements "record" doc of
    [] -> Left "digest registry: no records"
    rs -> mapM record rs
  where
    record r = case (children "key" r, children "status" r, children "description" r) of
      ([k], [s], [d]) -> Right (DigestRecord (textOf k) (textOf s) (textOf d))
      _ -> Left "digest registry: a record lacks exactly one key, status and description"

-- | The receipt algorithm's catalogue name and aliases, from the RevEng entry
-- the brief's algorithm is cited to (PD:REVENG-crc.cat.crc-64-nvme-1).
receiptNames :: String -> Either String [String]
receiptNames htm = case dropWhile (not . (anchor `isPrefixOf`)) (tails' htm) of
  [] -> Left "CRC catalogue: no entry crc.cat.crc-64-nvme"
  at : _ ->
    let name = takeWhile (/= '<') (drop (length anchor) at)
        entry = takeUntil "<H3>" (drop (length anchor) at)
        aliases = concat [strongs l | l <- lines entry, "<LI>Alias:" `isPrefixOf` dropWhile isSpace l]
     in if null name then Left "CRC catalogue: empty name" else Right (nub (name : aliases))
  where
    anchor = "<A NAME=\"crc.cat.crc-64-nvme\">"
    tails' s = case s of
      [] -> []
      _ : t -> s : tails' t
    takeUntil p s = case s of
      c : t | not (p `isPrefixOf` s) -> c : takeUntil p t
      _ -> []
    strongs l = case breakAfter "<STRONG>" l of
      Nothing -> []
      Just rest -> takeWhile (/= '<') rest : strongs rest
    breakAfter p s
      | null s = Nothing
      | p `isPrefixOf` s = Just (drop (length p) s)
      | otherwise = breakAfter p (drop 1 s)

-- | A key names the receipt algorithm when, ignoring case and punctuation,
-- the key is one of its names or its description mentions one.
forwardedKeys :: [String] -> [DigestRecord] -> [DigestRecord]
forwardedKeys names = filter names'
  where
    norm = map toLower . filter isAlphaNum
    ns = map norm names
    names' r = norm (drKey r) `elem` ns || any (`isInfixOf` norm (drDescription r)) ns

genDigest :: Statements -> [Source] -> String -> String -> Either String String
genDigest sts srcs xml htm = do
  recs <- digestRecords xml
  names <- receiptNames htm
  statusDef <- statement sts PD "RFC9530-5-3"
  let statuses = nub (map drStatus recs)
      fwd = forwardedKeys names recs
      con = pascal . drKey
      cons = map con recs
      w = maximum (map length cons)
      padTo s = s ++ replicate (w - length s) ' '
  mapM_
    (\s -> if ("\"" ++ s ++ "\"") `isInfixOf` stQuote statusDef then Right () else Left ("status " ++ s ++ " is not defined by PD:RFC9530-5-3"))
    statuses
  hsIds <- mapM (rfcRow sts) recs
  bases <- mapM (\(r, h) -> basis sts [R [(HS, h), (PD, "IANA-DIGEST-ALGS-" ++ drKey r ++ "-1")]]) (zip recs hsIds)
  statusBasis <- basis sts [R [(PD, "RFC9530-5-3")]]
  refuseBasis <- basis sts [P [(PD, "DIGEST-PROBLEMS-3.1-1"), (PD, "RFC9530-2-2")] "PM24", C "CH2"]
  algBasis <- basis sts [R [(PD, "REVENG-crc.cat.crc-64-nvme-1")], C "CH2"]
  tokens <- mapM (hsString . drKey) recs
  checkIdentifiers (cons ++ map pascal statuses ++ ["F_" ++ con r | r <- fwd])
  let nameList = intercalate ", " names
  pure . unlines $
    header "the IANA Hash Algorithms for HTTP Digest Fields registry and the CRC catalogue" srcs
      ++ [ "{-# LANGUAGE Safe #-}" ]
      ++ [ "{-# OPTIONS_GHC -Wno-unused-imports #-}" | null fwd ]
      ++ [ "-- | Digest keys a client can name in an integrity field, and what the core"
         , "-- can do with a client's digest. The store vouches only with the receipt"
         , "-- algorithm, " ++ nameList ++ " (" ++ algBasis ++ "), so a client digest"
         , "-- could only be checked if a registered key named it."
         , "module Funknown.Digest"
         , "  ( DigestKey (..)"
         , "  , KeyStatus (..)"
         , "  , keyToken"
         , "  , keyStatus"
         , "  , Octets (..)"
         , "  , ClientDigest (..)"
         , "  , Forwarded" ++ (if null fwd then "" else " (..)")
         , "  , forwardable"
         , "  ) where"
         , ""
         , "import Data.Word (Word8)"
         ]
      ++ ( if null fwd
             then
               [ "-- isPresent is named only by the NoForward refinement, and LiquidHaskell"
               , "-- resolves it through this import, which GHC therefore calls unused."
               , "import Funknown.Opt (Opt (..), isPresent)"
               ]
             else ["import Funknown.Opt (Opt (..))"]
         )
      ++ [ ""
         , "data DigestKey"
         ]
      ++ [ (if i == 0 then "  = " else "  | ") ++ padTo c ++ " -- " ++ b
         | (i, c, b) <- zip3 [0 :: Int ..] cons bases
         ]
      ++ [ "  deriving (Eq, Show, Enum, Bounded)"
         , ""
         , "-- | " ++ statusBasis ++ ". Only the statuses some key has today."
         , "data KeyStatus = " ++ intercalate " | " (map pascal statuses)
         , "  deriving (Eq, Show, Enum, Bounded)"
         , ""
         , "-- | The registry key, as it appears in an integrity field."
         , "keyToken :: DigestKey -> String"
         ]
      ++ [ "keyToken " ++ padTo c ++ " = " ++ t | (c, t) <- zip cons tokens ]
      ++ [ ""
         , "keyStatus :: DigestKey -> KeyStatus"
         ]
      ++ [ "keyStatus " ++ padTo (con r) ++ " = " ++ pascal (drStatus r) | r <- recs ]
      ++ [ ""
         , "-- | A digest value as the client sent it. The core never computes or parses"
         , "-- one (C CH3); it only carries it."
         , "newtype Octets = Octets [Word8]"
         , "  deriving (Eq, Show)"
         , ""
         , "-- | A parsed integrity field a client sent."
         , "data ClientDigest = ClientDigest DigestKey Octets"
         , "  deriving (Eq, Show)"
         , ""
         ]
      ++ (if null fwd then emptyForward refuseBasis nameList else someForward fwd)
  where
    -- HS's copy of RFC 9530's table: the row whose quote starts with the key.
    rfcRow s r =
      case [i | k <- [1 :: Int .. 99], let i = "RFC9530-7.2-" ++ show k, Right st <- [statement s HS i], ("| " ++ drKey r ++ " |") `isPrefixOf` stQuote st] of
        [i] -> Right i
        _ -> Left ("no unique HS:RFC9530-7.2 row for " ++ drKey r)

emptyForward :: String -> String -> [String]
emptyForward refuseBasis nameList =
  [ "-- | One constructor per registered key that names " ++ nameList ++ ". There are"
  , "-- none, so this type is empty, and every client integrity field is refused"
  , "-- with digest-unsupported-algorithms (" ++ refuseBasis ++ ")."
  , "data Forwarded"
  , ""
  , "-- Vacuous: 'Forwarded' has no values. They let types that hold an"
  , "-- @Opt Forwarded@ derive Eq and Show."
  , "instance Eq Forwarded where"
  , "  _ == _ = True"
  , ""
  , "instance Show Forwarded where"
  , "  show _ = \"Forwarded\""
  , ""
  , "-- | The type of Seal's forwarded argument. The logic can't see that"
  , "-- 'Forwarded' is empty, so \"never Present\" is stated here; the generator"
  , "-- drops this type when the first constructor appears, so every use site"
  , "-- has to be revisited then."
  , "{-@ type NoForward = {o:Opt Forwarded | not (isPresent o)} @-}"
  , ""
  , "-- | DC16: no client digest can be forwarded to the seal today."
  , "{-@ forwardable :: ClientDigest -> NoForward @-}"
  , "forwardable :: ClientDigest -> Opt Forwarded"
  , "forwardable _ = Absent"
  ]

someForward :: [DigestRecord] -> [String]
someForward fwd =
  [ "-- | One constructor per registered key that names the receipt algorithm."
  , "data Forwarded = " ++ intercalate " | " ["F_" ++ pascal (drKey r) | r <- fwd]
  , "  deriving (Eq, Show)"
  , ""
  , "forwardable :: ClientDigest -> Opt Forwarded"
  , "forwardable (ClientDigest k _) = case k of"
  ]
    ++ ["  " ++ pascal (drKey r) ++ " -> Present F_" ++ pascal (drKey r) | r <- fwd]
    ++ ["  _ -> Absent"]
