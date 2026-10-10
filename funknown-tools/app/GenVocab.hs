-- | gen-vocab: write funknown-core's generated vocabulary modules from the
-- vendored registries under references/.
--
--   gen-vocab [--repo DIR] [--references DIR] [--out DIR] [--check] [--draft-problem-types]
--
-- --repo is the repository root (default "."); --references and --out
-- default to DIR/references and DIR/funknown-core/src. --check writes nothing
-- and exits 1 if any committed module differs from what would be generated.
-- Not Safe: System.Directory isn't, and GHC refuses a Safe module that imports it.
module Main (main) where

import Control.Monad (forM, unless, when)
import qualified Data.ByteString as B
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Funknown.Tools.Emit (Source (..))
import Funknown.Tools.Gen.Digest (genDigest)
import Funknown.Tools.Gen.Problem (genProblem)
import Funknown.Tools.Gen.Rpc (genCode, genRecourse)
import Funknown.Tools.Gen.Status (genStatus)
import Funknown.Tools.Sha256 (sha256Hex)
import Funknown.Tools.Statements
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.FilePath (takeDirectory, (</>))
import System.IO (hPutStrLn, stderr)

data Opts = Opts
  { optRepo :: FilePath
  , optRefs :: Maybe FilePath
  , optOut :: Maybe FilePath
  , optCheck :: Bool
  , optDraft :: Bool
  }

parseArgs :: [String] -> Either String Opts
parseArgs = go (Opts "." Nothing Nothing False False)
  where
    go o [] = Right o
    go o ("--repo" : d : r) = go o {optRepo = d} r
    go o ("--references" : d : r) = go o {optRefs = Just d} r
    go o ("--out" : d : r) = go o {optOut = Just d} r
    go o ("--check" : r) = go o {optCheck = True} r
    go o ("--draft-problem-types" : r) = go o {optDraft = True} r
    go _ (a : _) = Left ("unknown argument " ++ a)

main :: IO ()
main = do
  opts <- either die' pure . parseArgs =<< getArgs
  let refs = maybe (optRepo opts </> "references") id (optRefs opts)
      out = maybe (optRepo opts </> "funknown-core" </> "src") id (optOut opts)
      -- read a vendored file: its text and its Source line for the header
      vendored rel = do
        bytes <- B.readFile (refs </> rel)
        text <- either (\e -> die' (rel ++ ": " ++ show e)) (pure . T.unpack) (TE.decodeUtf8' bytes)
        pure (Source ("references/" ++ rel) (sha256Hex bytes), text)
  stmts <- fmap Map.unions . forM [minBound .. maxBound] $ \g -> do
    (_, txt) <- vendored (groupDir g </> "statements.json")
    either die' pure (readStatements g txt)
  (statusSrc, statusCsv) <- vendored "http-semantics/http-status-codes-1.csv"
  (protoSrc, proto) <- vendored "status-and-supervision/googleapis/code.proto"
  (aipSrc, aip) <- vendored "status-and-supervision/aip/0194.md"
  (xmlSrc, xml) <- vendored "problems-and-digests/iana/http-digest-hash-alg.xml"
  (crcSrc, crc) <- vendored "problems-and-digests/crc/reveng-crc-catalogue-17plus.htm"
  (probSrc, prob) <- vendored "problems-and-digests/iana/http-problem-type-uris.csv"
  (draftSrc, draft) <- vendored "uploads/draft-ietf-httpbis-resumable-upload-13.txt"
  modules <-
    either die' pure $
      sequence
        [ (,) "Funknown/Http/Status.hs" <$> genStatus stmts statusSrc statusCsv
        , (,) "Funknown/Rpc/Code.hs" <$> genCode stmts protoSrc proto
        , (,) "Funknown/Rpc/Recourse.hs" <$> genRecourse stmts [aipSrc, protoSrc] proto aip
        , (,) "Funknown/Digest.hs" <$> genDigest stmts [xmlSrc, crcSrc] xml crc
        , (,) "Funknown/Problem.hs" <$> genProblem stmts [probSrc, draftSrc, statusSrc] (optDraft opts) statusCsv prob draft
        ]
  stale <- fmap concat . forM modules $ \(rel, txt) -> do
    let path = out </> rel
        bytes = TE.encodeUtf8 (T.pack txt)
    if optCheck opts
      then do
        exists <- doesFileExist path
        same <- if exists then (== bytes) <$> B.readFile path else pure False
        pure [path | not same]
      else do
        createDirectoryIfMissing True (takeDirectory path)
        B.writeFile path bytes
        putStrLn ("wrote " ++ path)
        pure []
  unless (null stale) $ do
    mapM_ (hPutStrLn stderr . ("differs from what gen-vocab would write: " ++)) stale
    exitFailure
  when (optCheck opts) (putStrLn "generated modules are up to date")

die' :: String -> IO a
die' e = hPutStrLn stderr ("gen-vocab: " ++ e) >> exitFailure
