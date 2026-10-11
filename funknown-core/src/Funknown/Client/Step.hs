{-# LANGUAGE Safe #-}
-- | The client side's one entry point. Every event goes to the one slice
-- handler that owns it, one route per constructor and no wildcard, so GHC's
-- exhaustiveness check (-Werror=incomplete-patterns) refuses a constructor
-- that has no route.
--
-- Each slice's entry point names its own events in its precondition
-- ('uploadEventKind' in "Funknown.Client.Upload", 'requestKind' in
-- "Funknown.Client.Requests"), so a request or a report sent to another
-- handler is a LiquidHaskell error here, not a wrong reply later. The two
-- watch handlers can't do that: 'kernelMoved' and 'tick' both take any
-- event that carries no request and reports no job. So 'stepClient' states,
-- on top of ClientOut, each one's own row spec for its own constructor
-- (WatchRows for KernelMoved, TickRows for Tick), and a swap of the two is
-- refused here as well.
module Funknown.Client.Step
  ( stepClient
  , stepKind
  ) where

import Funknown.Opt
import Funknown.Client.Contract ()
import Funknown.Client.Types
import Funknown.Client.Upload
  ( onAppend, onOffsetQuery, onCancelUpload
  , onBodyReceived, onBodyBroken, onChunkPersisted, onChunkFailed, onMoverDied )
import Funknown.Client.Requests
  ( cancelOperation, getOperation, deleteOperation, getObject, getAccessUrl, getContent, deleteFile )
import Funknown.Client.Watch (kernelMoved, tick)

-- | Which constructor an event is, in declaration order, so the dispatcher's
-- spec can name KernelMoved (15) and Tick (16).
{-@ measure stepKind @-}
{-@ stepKind :: Event -> {k:Int | 0 <= k && k <= 16} @-}
stepKind :: Event -> Int
stepKind (Append _)           = 0
stepKind (OffsetQuery _)      = 1
stepKind (CancelUpload _)     = 2
stepKind (CancelOperation _)  = 3
stepKind (GetOperation _)     = 4
stepKind (DeleteOperation _)  = 5
stepKind (GetObject _)        = 6
stepKind (GetAccessUrl _)     = 7
stepKind (GetContent _ _)     = 8
stepKind (DeleteFile _ _)     = 9
stepKind (BodyReceived _ _)   = 10
stepKind (BodyBroken _ _)     = 11
stepKind (ChunkPersisted _ _) = 12
stepKind (ChunkFailed _)      = 13
stepKind (MoverDied _)        = 14
stepKind KernelMoved          = 15
stepKind Tick                 = 16

-- | The request a Requests event carries is present, and KernelMoved and a
-- Tick carry none. z3 only learns 'isPresent' of a value built in code, so
-- the route builds the event's own request and hands it over.
{-@ carried :: ev:Event -> o:{Opt ReqId | o == evReq ev && isPresent o} -> {v:() | isPresent (evReq ev)} @-}
carried :: Event -> Opt ReqId -> ()
carried _ _ = ()

{-@ carriesNone :: ev:Event -> o:{Opt ReqId | o == evReq ev && not (isPresent o)} -> {v:() | not (isPresent (evReq ev))} @-}
carriesNone :: Event -> Opt ReqId -> ()
carriesNone _ _ = ()

-- | Route the event to its slice. Upload owns the three upload-resource
-- requests and the mover's reports; Requests owns the operation, object and
-- content requests and DeleteFile; Watch owns KernelMoved and Tick.
{-@ stepClient :: env:Env -> ev:Event -> f:File
               -> {o:ClientOut env f ev | (stepKind ev == 15 => WatchRows f o)
                                         && (stepKind ev == 16 => TickRows env f o)} @-}
stepClient :: Env -> Event -> File -> Out
stepClient env ev f = case ev of
  Append _           -> onAppend env ev f
  OffsetQuery _      -> onOffsetQuery env ev f
  CancelUpload _     -> onCancelUpload env ev f
  CancelOperation r  -> case carried ev (Present r) of () -> cancelOperation env ev f
  GetOperation r     -> case carried ev (Present r) of () -> getOperation env ev f
  DeleteOperation r  -> case carried ev (Present r) of () -> deleteOperation env ev f
  GetObject r        -> case carried ev (Present r) of () -> getObject env ev f
  GetAccessUrl r     -> case carried ev (Present r) of () -> getAccessUrl env ev f
  GetContent r _     -> case carried ev (Present r) of () -> getContent env ev f
  DeleteFile r _     -> case carried ev (Present r) of () -> deleteFile env ev f
  BodyReceived _ _   -> onBodyReceived env ev f
  BodyBroken _ _     -> onBodyBroken env ev f
  ChunkPersisted _ _ -> onChunkPersisted env ev f
  ChunkFailed _      -> onChunkFailed env ev f
  MoverDied _        -> onMoverDied env ev f
  KernelMoved        -> case carriesNone ev Absent of () -> kernelMoved env ev f
  Tick               -> case carriesNone ev Absent of () -> tick env ev f
