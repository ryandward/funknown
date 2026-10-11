{-# LANGUAGE Safe #-}
{-@ LIQUID "--reflection" @-}
{-@ LIQUID "--ple" @-}
-- | What the reconciler can be told, and what a failed call does to it.
--
-- We want the kernel to be a pure decision core whose shell makes every call
-- and absorbs every call failure. The one place a call's result meets the
-- kernel is the shell's next look at the store, so the theorem here is
-- stated at that look, with A1 written out as its premise: the shell's look
-- after a call is exactly what the store holds, or nothing. A look that
-- failed writes nothing into the asset.
--
-- * 'shellRound': whatever the call did (the store performed the command
--   before the shell looked again, or never did) and whether the look
--   answered, the asset stays exact with the store, and the state meets
--   the contract Converge's adversary moves are held to. A store command
--   the store performed costs nothing; a lost one, or a lost Observe, costs
--   one unit of the drop allowance, which is A2's fairness.
-- * 'keeps': under that premise no call failure can cost a receipted asset
--   anything: the goal, the receipt, and the object at the receipt's version
--   all survive the round, whatever the call did.
-- * 'justified': every fault the reconciler sets names what the store held,
--   not only what the asset last saw (K12 lifted to the store).
--
-- A store command that lands after the shell's next look is not covered:
-- the look would be stale but not lost, which the adversary doesn't model
-- yet (docs/design/kernel.md). The premise of 'shellRound' is that the store
-- performs a command before that look or never.
--
-- Two supporting statements pin what the inputs can hold at all:
--
-- * 'reach': every observation is what an empty store holds after some of
--   its own actions (open, land, seal, vouch or decline), and
--   'modelEvents' writes every command the store model performs as those
--   same actions (the tie is checked exhaustively in test/KernelGuards.hs).
-- * the '*Fields' functions and the '*Exact' lemmas: the environment, the
--   configuration, a write and an asset are exactly their named fields, of
--   the named types.
module Funknown.Kernel.Inputs
  ( StoreEvent (..)
  , apply
  , replay
  , replayOn
  , modelEvents
  , reach
  , lookAt
  , reachSeen
  , envFields
  , configFields
  , backoffFields
  , writeFields
  , assetFields
  , envExact
  , configExact
  , backoffExact
  , writeExact
  , assetExact
  , seenObs
  , Shell (..)
  , shellRound
  , keeps
  , justified
  ) where

import Funknown.Opt
import Funknown.Proof (Proof, (?))
import Funknown.Http.Retry (Backoff (..))
import Funknown.Kernel.Bound (Version (..))
import Funknown.Kernel.Converge ()
import Funknown.Kernel.Model (Model (..), Round (..), roundWith)
import Funknown.Kernel.Reconcile (failedOnStore)
import Funknown.Kernel.Types
import Funknown.Store.Receipt (ReceiptReport)
import Funknown.Upload (ChunkToken)

-- Observations are store states ---------------------------------------------------

-- | What the store itself does to what it holds for one file, under the
-- contract in docs/design/kernel.md: Opens is rule 1 (a staging area under
-- the file's id), Lands is a chunk becoming durable in the newest staging
-- area, Seals is rule 2 (the named staging area becomes the object at the
-- version the store names, create-only, and is consumed), Vouches and
-- Declines are rule 3 (the store vouches with a checksum and size, or will
-- never vouch in that algorithm), Discards removes every staging area of
-- that name, and Removes removes the object only at the version it names
-- (rule 2).
data StoreEvent
  = Opens StagingRef
  | Lands ChunkToken
  | Seals StagingRef Version
  | Vouches ReceiptReport
  | Declines
  | Discards StagingRef
  | Removes Version

{-@ measure ssOf @-}
ssOf :: Observed -> Stagings
ssOf (Observed ss _) = ss

{-@ measure objOf @-}
objOf :: Observed -> ObjectObs
objOf (Observed _ o) = o

{-@ reflect landIn @-}
landIn :: ChunkToken -> Staging -> Staging
landIn t (Staging r ts) = Staging r (t : ts)

{-@ reflect landTok @-}
landTok :: ChunkToken -> Stagings -> Stagings
landTok _ SNil          = SNil
landTok t (SCons st ss) = SCons (landIn t st) ss

-- | Every staging area named r goes, as the store model's dropRef does.
{-@ reflect consume @-}
consume :: StagingRef -> Stagings -> Stagings
consume _ SNil = SNil
consume r (SCons (Staging r' ts) ss) =
  if r == r' then consume r ss else SCons (Staging r' ts) (consume r ss)

-- | Seal is create-only (rule 2): where there is no object, staging area r
-- becomes one at version v, not yet vouched for, and r is consumed.
{-@ reflect sealIn @-}
sealIn :: StagingRef -> Version -> Observed -> Observed
sealIn r v (Observed ss NoObject)        = Observed (consume r ss) (HasObject v NotYetVouched)
sealIn _ _ (Observed ss (HasObject w c)) = Observed ss (HasObject w c)

{-@ reflect settle @-}
settle :: Vouching -> ObjectObs -> ObjectObs
settle _ NoObject        = NoObject
settle c (HasObject v _) = HasObject v c

{-@ reflect removeAt @-}
removeAt :: Version -> ObjectObs -> ObjectObs
removeAt _ NoObject        = NoObject
removeAt v (HasObject w c) = if w == v then NoObject else HasObject w c

-- | One store action, applied to what the store holds.
{-@ reflect apply @-}
apply :: StoreEvent -> Observed -> Observed
apply (Opens r)    ob = Observed (SCons (Staging r []) (ssOf ob)) (objOf ob)
apply (Lands t)    ob = Observed (landTok t (ssOf ob)) (objOf ob)
apply (Seals r v)  ob = sealIn r v ob
apply (Vouches p)  ob = Observed (ssOf ob) (settle (Vouched p) (objOf ob))
apply Declines     ob = Observed (ssOf ob) (settle Unvouchable (objOf ob))
apply (Discards r) ob = Observed (consume r (ssOf ob)) (objOf ob)
apply (Removes v)  ob = Observed (ssOf ob) (removeAt v (objOf ob))

-- | What an empty store holds after its actions, the newest first.
{-@ reflect replay @-}
replay :: [StoreEvent] -> Observed
replay []       = Observed SNil NoObject
replay (e : es) = apply e (replay es)

-- | What the store holds after its actions, the newest first, from ob.
replayOn :: [StoreEvent] -> Observed -> Observed
replayOn []       ob = ob
replayOn (e : es) ob = apply e (replayOn es ob)

-- | Each command the store model performs, as the store's own actions, the
-- newest first. test/KernelGuards.hs checks, for every small model, goal
-- and command, that replaying these from the model's observation gives
-- exactly what 'Funknown.Kernel.Model.perform' gives, so the actions above
-- are the store model the other proofs use, only finer.
modelEvents :: Goal -> Cmd -> Model -> [StoreEvent]
modelEvents _ NoCmd _ = []
modelEvents _ DoObserve _ = []
modelEvents _ DoOpen (Model _ fr _ _) = [Opens fr]
modelEvents g DoSeal (Model (Observed _ o) _ v vc) = case (g, o) of
  (Keep (Assembled r _), NoObject) -> settleEvents vc ++ [Seals r v]
  _                                -> []
modelEvents _ (DoDiscard r) _ = [Discards r]
modelEvents _ (DoRemove v) _ = [Removes v]

settleEvents :: Vouching -> [StoreEvent]
settleEvents (Vouched p)   = [Vouches p]
settleEvents Unvouchable   = [Declines]
settleEvents NotYetVouched = []

-- The witness: the actions, newest first, that lead an empty store to a given
-- observation. The object comes first: a staging area is opened, sealed into
-- the object (which consumes it) and settled, and only then are the
-- observation's own staging areas opened.

{-@ reflect sealRef @-}
sealRef :: StagingRef
sealRef = StagingRef []

{-@ reflect objEvents @-}
objEvents :: ObjectObs -> [StoreEvent]
objEvents NoObject                    = []
objEvents (HasObject v (Vouched p))   = [Vouches p, Seals sealRef v, Opens sealRef]
objEvents (HasObject v Unvouchable)   = [Declines, Seals sealRef v, Opens sealRef]
objEvents (HasObject v NotYetVouched) = [Seals sealRef v, Opens sealRef]

{-@ reflect landAll @-}
landAll :: [ChunkToken] -> [StoreEvent] -> [StoreEvent]
landAll []       k = k
landAll (t : ts) k = Lands t : landAll ts k

-- | Open r after the actions k.
{-@ reflect opening @-}
opening :: StagingRef -> [StoreEvent] -> [StoreEvent]
opening r k = Opens r : k

{-@ reflect areaEvents @-}
areaEvents :: Stagings -> [StoreEvent] -> [StoreEvent]
areaEvents SNil                      k = k
areaEvents (SCons (Staging r ts) ss) k = landAll ts (opening r (areaEvents ss k))

{-@ objLemma :: o:ObjectObs -> {replay (objEvents o) == Observed SNil o} @-}
objLemma :: ObjectObs -> Proof
objLemma NoObject                    = ()
objLemma (HasObject _ (Vouched _))   = ()
objLemma (HasObject _ Unvouchable)   = ()
objLemma (HasObject _ NotYetVouched) = ()

-- | Opening r and landing ts in it puts Staging r ts in front of whatever
-- the earlier actions left.
{-@ landLemma :: ts:[ChunkToken] -> r:StagingRef -> k:[StoreEvent]
              -> {ssOf (replay (landAll ts (opening r k))) == SCons (Staging r ts) (ssOf (replay k))
                  && objOf (replay (landAll ts (opening r k))) == objOf (replay k)} @-}
landLemma :: [ChunkToken] -> StagingRef -> [StoreEvent] -> Proof
landLemma []       _ _ = ()
landLemma (_ : ts) r k = landLemma ts r k

{-@ areaLemma :: ss:Stagings -> k:[StoreEvent]
              -> {ssOf (replay k) == SNil
                    => (ssOf (replay (areaEvents ss k)) == ss && objOf (replay (areaEvents ss k)) == objOf (replay k))} @-}
areaLemma :: Stagings -> [StoreEvent] -> Proof
areaLemma SNil                      _ = ()
areaLemma (SCons (Staging r ts) ss) k = landLemma ts r (areaEvents ss k) ? areaLemma ss k

{-@ observedIs :: o:Observed -> {o == Observed (ssOf o) (objOf o)} @-}
observedIs :: Observed -> Proof
observedIs (Observed _ _) = ()

-- | Every observation the kernel can be handed is what the store holds after
-- some sequence of its own actions.
{-@ reach :: o:Observed -> {es:[StoreEvent] | replay es == o} @-}
reach :: Observed -> [StoreEvent]
reach o@(Observed ss obj) =
  areaEvents ss (objEvents obj)
    ? objLemma obj
    ? areaLemma ss (objEvents obj)
    ? observedIs (replay (areaEvents ss (objEvents obj)))
    ? observedIs o

-- | The observation slot after a look at the store, or after none since the
-- last command.
{-@ reflect lookAt @-}
lookAt :: Opt [StoreEvent] -> Seen
lookAt Absent       = Unseen
lookAt (Present es) = Seen (replay es)

-- | Every value of the observation slot is a look at some store state, or
-- no look at all.
{-@ reachSeen :: s:Seen -> {l:Opt [StoreEvent] | lookAt l == s} @-}
reachSeen :: Seen -> Opt [StoreEvent]
reachSeen Unseen   = Absent
reachSeen (Seen o) = Present (reach o)

-- Everything else is the clock, the configuration or the asset's own fields --

-- | Every field of the kernel's inputs, with its type written out. A field
-- whose type changed, say to carry a call's result, stops these from
-- compiling, so the change has to show up here; the '*Exact' lemmas below
-- add that there are no other fields.
envFields :: Env -> (Int, Config)
envFields e = (now e, cfg e)

configFields :: Config -> (Int, Backoff, Int)
configFields c = (maxAttempts c, backoff c, writeDeadline c)

backoffFields :: Backoff -> (Int, Int, Int)
backoffFields b = (initialBackoff b, maxBackoff b, backoffMultiplier b)

writeFields :: Write -> (Int, Int)
writeFields w = (writeJobOf w, writeByOf w)

assetFields :: Asset -> (Goal, Outcome, Seen, Vouch, Int, Int, [Write])
assetFields a = (goal a, outcome a, seen a, vouch a, budget a, backoffAt a, authorised a)

-- | The environment is the clock and the configuration, and nothing else.
{-@ envExact :: e1:Env -> e2:{Env | now e2 == now e1 && cfg e2 == cfg e1} -> {e1 == e2} @-}
envExact :: Env -> Env -> Proof
envExact (Env _ _) (Env _ _) = ()

{-@ configExact :: c1:Config
                -> c2:{Config | maxAttempts c2 == maxAttempts c1 && backoff c2 == backoff c1
                                && writeDeadline c2 == writeDeadline c1}
                -> {c1 == c2} @-}
configExact :: Config -> Config -> Proof
configExact (Config _ _ _) (Config _ _ _) = ()

{-@ backoffExact :: b1:Backoff
                 -> b2:{Backoff | initialBackoff b2 == initialBackoff b1 && maxBackoff b2 == maxBackoff b1
                                  && backoffMultiplier b2 == backoffMultiplier b1}
                 -> {b1 == b2} @-}
backoffExact :: Backoff -> Backoff -> Proof
backoffExact (Backoff _ _ _) (Backoff _ _ _) = ()

{-@ measure writeJobOf @-}
writeJobOf :: Write -> Int
writeJobOf (Write e _) = e

{-@ measure writeByOf @-}
writeByOf :: Write -> Int
writeByOf (Write _ dl) = dl

-- | A write the core started is the job that writes it and its deadline: a
-- call in flight, never how it ended.
{-@ writeExact :: w1:Write -> w2:{Write | writeJobOf w2 == writeJobOf w1 && writeByOf w2 == writeByOf w1}
               -> {w1 == w2} @-}
writeExact :: Write -> Write -> Proof
writeExact (Write _ _) (Write _ _) = ()

{-@ assetExact :: a1:Asset
               -> a2:{Asset | goal a2 == goal a1 && outcome a2 == outcome a1 && seen a2 == seen a1
                              && vouch a2 == vouch a1 && budget a2 == budget a1
                              && backoffAt a2 == backoffAt a1 && authorised a2 == authorised a1}
               -> {a1 == a2} @-}
assetExact :: Asset -> Asset -> Proof
assetExact (Asset _ _ _ _ _ _ _) (Asset _ _ _ _ _ _ _) = ()

-- A call, and the shell's next look -----------------------------------------------

-- | What a look wrote into the observation slot, or an empty store for none.
{-@ measure seenObs @-}
seenObs :: Seen -> Observed
seenObs Unseen   = Observed SNil NoObject
seenObs (Seen o) = o

-- | A round as the shell runs it: the asset it keeps, what the store holds
-- afterwards, and how much of the drop allowance the round spent.
data Shell = Shell { shAsset :: Asset, shModel :: Model, shSpent :: Int }
{-@ data Shell = Shell { shAsset :: Asset, shModel :: Model, shSpent :: {n:Int | n == 0 || n == 1} } @-}

-- | The asset with its observation slot set to s.
{-@ withSeen :: a:Asset -> s:Seen
             -> {b:Asset | goal b == goal a && outcome b == outcome a && vouch b == vouch a
                          && budget b == budget a && authorised b == authorised a && seen b == s} @-}
withSeen :: Asset -> Seen -> Asset
withSeen (Asset g o _ v b st w) s = Asset g o s v b st w

-- | One round with the shell in it. The reconciler decides; the shell makes
-- the call; the store either performs the command before the shell looks
-- again (performed) or never does; then the shell looks. The look is A1 at
-- the one place a call's result meets the kernel: for whatever the store
-- holds, it gives exactly that, or Unseen when it failed or wasn't made, and
-- an Unseen look leaves the asset as the decision left it. Whatever the call
-- and the look did, the asset is exact with the store again, and the state
-- is smaller in Converge's metric: at the same allowance when the store
-- performed its command, or when there was no call, and by one unit of the
-- allowance when a store command or an Observe was lost. Outside a resting
-- row, that is the contract every adversary move in
-- "Funknown.Kernel.Converge" is held to; it isn't a move there of its own.
{-@ shellRound :: a:Asset -> m:{Model | Coherent a m} -> k:{Nat | k > 0} -> dec:Step a -> performed:Bool
               -> look:(n:Model -> {s:Seen | isSeen s => seenObs s == mObs n})
               -> {r:Shell | Coherent (shAsset r) (shModel r)
                            && (shSpent r == 1 => (cmdTag (command dec) >= 1
                                                   && Smaller a m k (shAsset r) (shModel r) (k - 1)))
                            && (shSpent r == 0 => (isFixedRow (row dec) || Smaller a m k (shAsset r) (shModel r) k))
                            && ((performed && cmdTag (command dec) >= 2) => shSpent r == 0)
                            && (cmdTag (command dec) == 0 => shSpent r == 0)
                            && goal (shAsset r) == goal (next dec) && vouch (shAsset r) == vouch (next dec)
                            && ((cmdTag (command dec) /= 3 && cmdTag (command dec) /= 5)
                                  => (obsObjTag (mObs (shModel r)) == obsObjTag (mObs m)
                                      && obsVersion (mObs (shModel r)) == obsVersion (mObs m)))} @-}
shellRound :: Asset -> Model -> Int -> Decision -> Bool -> (Model -> Seen) -> Shell
shellRound a m k dec performed look
  | cmdTag (command dec) >= 2 && not performed = lostCommand a m k dec (look m)
  | otherwise                                  = madeCall a m k dec (roundWith a m dec) look

-- | The store never performed the command: it holds what it held, and the
-- round is a Drop, whether or not the next look answered.
{-@ lostCommand :: a:Asset -> m:{Model | Coherent a m} -> k:{Nat | k > 0} -> dec:{Step a | cmdTag (command dec) >= 2}
                -> s:{Seen | isSeen s => seenObs s == mObs m}
                -> {r:Shell | Coherent (shAsset r) (shModel r) && shSpent r == 1
                             && Smaller a m k (shAsset r) (shModel r) (k - 1) && shModel r == m
                             && goal (shAsset r) == goal (next dec) && vouch (shAsset r) == vouch (next dec)} @-}
lostCommand :: Asset -> Model -> Int -> Decision -> Seen -> Shell
lostCommand _ m _ dec s = case s of
  Unseen -> Shell (next dec) m 1
  Seen o -> Shell (withSeen (next dec) (Seen o)) m 1

-- | The store performed the command (or there was none, or it was an
-- Observe): it holds what the honest round leaves, and the look either
-- shows that or nothing.
{-@ madeCall :: a:Asset -> m:{Model | Coherent a m} -> k:{Nat | k > 0} -> dec:Step a
             -> r:{Round | (isFixedRow (rRow r) || Lower a m (rAsset r) (rModel r))
                          && (cmdTag (command dec) >= 2 => Lower a m (rAsset r) (rModel r))
                          && ((cmdTag (command dec) /= 3 && cmdTag (command dec) /= 5)
                                => (obsObjTag (mObs (rModel r)) == obsObjTag (mObs m)
                                    && obsVersion (mObs (rModel r)) == obsVersion (mObs m)))
                          && goal (rAsset r) == goal (next dec) && vouch (rAsset r) == vouch (next dec)
                          && budget (rAsset r) == budget (next dec) && isSeen (seen (rAsset r))
                          && authorised (rAsset r) == authorised a && rRow r == row dec
                          && (cmdTag (command dec) <= 1 => mObs (rModel r) == mObs m)}
             -> look:(n:Model -> {s:Seen | isSeen s => seenObs s == mObs n})
             -> {v:Shell | Coherent (shAsset v) (shModel v)
                          && (shSpent v == 1 => (cmdTag (command dec) == 1
                                                 && Smaller a m k (shAsset v) (shModel v) (k - 1)))
                          && (shSpent v == 0 => (isFixedRow (row dec) || Smaller a m k (shAsset v) (shModel v) k))
                          && (cmdTag (command dec) /= 1 => shSpent v == 0)
                          && shModel v == rModel r
                          && goal (shAsset v) == goal (next dec) && vouch (shAsset v) == vouch (next dec)} @-}
madeCall :: Asset -> Model -> Int -> Decision -> Round -> (Model -> Seen) -> Shell
madeCall _ _ _ dec r look = case look (rModel r) of
  Seen o -> Shell (withSeen (next dec) (Seen o)) (rModel r) 0
  Unseen
    | cmdTag (command dec) == 1 -> Shell (next dec) (rModel r) 1
    | otherwise                 -> Shell (next dec) (rModel r) 0

-- | No call failure can cost a receipted asset anything. While a receipt is
-- held for an assembled goal and the store holds the object at the
-- receipt's version, a round keeps the goal, the receipt and the object,
-- whatever the call and the look did. The conclusion is the premise again,
-- so it holds round after round until a client or the producer moves the
-- goal.
{-@ keeps :: a:{Asset | goalTag (goal a) == 1 && hasReceipt (vouch a)}
          -> m:{Model | Coherent a m && obsObjTag (mObs m) /= 0 && obsVersion (mObs m) == vouchVersion (vouch a)}
          -> k:{Nat | k > 0} -> dec:Step a -> performed:Bool
          -> look:(n:Model -> {s:Seen | isSeen s => seenObs s == mObs n})
          -> {r:Shell | goal (shAsset r) == goal a && vouch (shAsset r) == vouch a
                       && Coherent (shAsset r) (shModel r)
                       && obsObjTag (mObs (shModel r)) /= 0
                       && obsVersion (mObs (shModel r)) == vouchVersion (vouch a)} @-}
keeps :: Asset -> Model -> Int -> Decision -> Bool -> (Model -> Seen) -> Shell
keeps a m k dec performed look = shellRound a m k dec performed look

-- | K12 lifted from the observation to the store: on an asset whose
-- observation is exact (which 'shellRound' keeps true), each fault the
-- reconciler sets names what the store holds. Unavailable in particular
-- needs the store's object to be not yet vouched, so a failed call can only
-- reach it if the shell reads the failure as that answer, which the premise
-- of 'shellRound' rules out.
{-@ justified :: a:Asset -> m:{Model | Coherent a m} -> dec:Step a
              -> {v:() | (not (isEnded (outcome a)) && isEnded (outcome (next dec)))
                          => ((failedOnStore (outcome (next dec)) == 1
                                 => (obsObjTag (mObs m) == 0 || obsVersion (mObs m) /= vouchVersion (vouch a)))
                              && (failedOnStore (outcome (next dec)) == 2 => obsObjTag (mObs m) /= 0)
                              && (failedOnStore (outcome (next dec)) == 3 => obsObjTag (mObs m) == 1)
                              && (failedOnStore (outcome (next dec)) == 4 => obsObjTag (mObs m) == 2)
                              && (failedOnStore (outcome (next dec)) == 5 => obsObjTag (mObs m) == 3))} @-}
justified :: Asset -> Model -> Decision -> Proof
justified _ _ _ = ()
