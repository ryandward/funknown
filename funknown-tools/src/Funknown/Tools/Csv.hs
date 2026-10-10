{-# LANGUAGE Safe #-}
-- | RFC 4180 CSV, as IANA publishes it: quoted fields may hold commas,
-- doubled quotes and line breaks. Anything else malformed is an error, so a
-- registry that changes shape stops the generator instead of being misread.
module Funknown.Tools.Csv (parseCsv) where

parseCsv :: String -> Either String [[String]]
parseCsv = go [] [] . filter (/= '\r')
  where
    -- row: fields of the current record, reversed; acc: records, reversed
    go acc row s = case field s of
      Left e -> Left e
      Right (f, rest) -> case rest of
        ',' : more -> go acc (f : row) more
        '\n' : more -> next (reverse (f : row) : acc) more
        [] -> Right (reverse (finish (reverse (f : row)) acc))
        c : _ -> Left ("unexpected " ++ show c ++ " after a field")
    next acc [] = Right (reverse acc)
    next acc s = go acc [] s
    finish [""] acc = acc
    finish r acc = r : acc

    field ('"' : s) = quoted "" s
    field s = Right (break (`elem` ",\n") s)

    quoted acc ('"' : '"' : s) = quoted ('"' : acc) s
    quoted acc ('"' : s) = Right (reverse acc, s)
    quoted acc (c : s) = quoted (c : acc) s
    quoted _ [] = Left "unterminated quoted field"
