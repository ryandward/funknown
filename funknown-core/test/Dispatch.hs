-- | The dispatcher sends every event where the slice tests say it belongs.
--
-- This suite has no oracle of its own. It runs each slice suite's own
-- cases and expectations (UploadReplies for slice 1, Requests for slice 2,
-- WatchCreate's KernelMoved and Tick part for slice 3), each transcribed
-- from CLIENT.md and core.md, but with 'stepClient' as the step in place of
-- the slice's entry point. An event routed to the wrong handler gets a
-- different reply or leaves a different file behind, so it fails there.
-- It also checks that the three suites together stepped every Event
-- constructor, so a constructor no suite reaches can't pass by absence.
module Main (main) where

import Control.Monad (unless)
import System.Exit (exitFailure)

import Funknown.Client.Step (stepClient)
import qualified Requests
import Tally
import qualified UploadReplies
import qualified WatchCreate

main :: IO ()
main = do
  t <- newTally
  results <- sequence
    [ (,) "slice 1 (UploadReplies)" <$> UploadReplies.suite t stepClient
    , (,) "slice 2 (Requests)" <$> Requests.suite t stepClient
    , (,) "slice 3 (WatchCreate, KernelMoved and Tick)" <$> WatchCreate.suite t stepClient ]
  mapM_ (\(name, (n, bad)) -> putStrLn ("dispatch, " ++ name ++ ": " ++ show n ++ " steps through stepClient, " ++ show bad ++ " differ"))
        results
  seen <- kindsSeen t
  let missing = [ k | k <- [0 .. eventKinds - 1], k `notElem` seen ]
  putStrLn ("dispatch: " ++ show (length seen) ++ " of " ++ show eventKinds ++ " Event constructors stepped"
            ++ (if null missing then "" else "; never stepped: " ++ unwords (map kindName missing)))
  unless (all ((== 0) . snd . snd) results && null missing) exitFailure
