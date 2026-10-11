# The lifecycle kernel: intent, observed reality, receipt

Status: design only. Written 2026-10-09 and revised the same day after review (goal and ending separated, rows made mutually exclusive, the write deadline named, S3 gaps listed). It replaces the store-side half of `core.md`, and the client-facing half of `core.md` stays.

## What we're trying to do

File infrastructure for ETL tends to fail in the same few ways: files reported ready that were never verified, staging areas and multipart uploads leaked, rows left pending forever, and requests left unanswered. These are hard to see when the code looks functional but its types don't say what it does. We want a Haskell model that is honest in exactly those places: every fact the system relies on is in a type or a proved claim, and anything we can't prove is written down as a named assumption.

The model should also generalize. An upload, an import, a transform and a delete should each be an instance of one lifecycle, not separate machines.

The first design (`core.md`) was edge-triggered. Every store answer moved the file one step. That design needed the shell to deliver exactly one report per call, with epochs to reject stale ones, an `AwaitingOpen` stage for an Open that ended mid-flight, four "after" states for asking about a receipt, and a cleanup list. Each of those existed only because a dropped or duplicated message would otherwise leave a file stuck. That is the same failure we see in production, moved into a contract written in prose.

The kernel is level-triggered instead, after Kubernetes controllers. Nothing moves a file because a message arrived. The reconciler compares what the file should become with what the store actually holds, and issues the one command that closes the gap. A dropped command, a duplicated answer or a lost report changes nothing that matters, because the next observation still shows the gap.

## Two halves

Client requests are events that must each be answered once, in order. A PATCH can't be observed later, so the client side stays an edge-triggered per-file machine: the Requests and Receiving columns of `core.md`, with the step contract we already prove. Everything between the core and the store becomes the reconciler.

The two halves meet in one record:

```
data Asset = Asset
  { goal       :: Goal            -- what the store should end up holding
  , ending     :: Opt Ending      -- why the asset is going away; Present exactly when the goal is Clear
  , observed   :: Opt Observed    -- the latest snapshot of the store
  , receipt    :: Opt Receipt     -- set only by the reconciler, only from vouch
  , budget     :: Budget          -- store attempts left while the goal is Keep and no receipt is held
  , authorised :: [Write]         -- chunk writes started and not yet reported, each with its deadline
  }
```

The client side moves `goal` by requests (an append, a completion, a cancel, a DELETE), and it answers requests from a projection of the whole record. The reconciler reads `goal` and `observed`, emits store commands, and sets `receipt`. It also moves `goal` itself in exactly one way, to `Clear` with a `Failed` ending, when the store shows that the goal can't be reached. Both writers can only move the goal down the order below, so neither can undo the other.

## Intent, from AIP-216

AIP-216 already gives us a level-triggered vocabulary. Active states are "lifecycle states that typically resolve on their own into a single expected resting state" (`SS:AIP216-Active-1`): CREATING usually becomes ACTIVE, and DELETING usually becomes DELETED (`SS:AIP216-Active-3`). The goal is what the store should hold when the asset comes to rest, and the active state a client sees is derived from it, not stored.

The goal and the ending are separate on purpose. The reconciler converges toward exactly two physical goals, a sealed and vouched object or nothing at all, and it never reads why an asset is going away. DELETED, CANCELLED and FAILED are outcomes a client is told about, so they live in `ending`. Relabelling an ending could therefore never change what the reconciler does, or the measure its convergence proof decreases.

```
data Goal
  = Keep Assembly                  -- resolves to ACTIVE
  | Clear                          -- resolves to nothing held in the store

data Assembly
  = Assembling (Opt StagingRef) Chunks   -- the producer is still adding chunks to this staging area
  | Assembled StagingRef Chunks          -- the producer marked it complete; its length is the chunks' total

data Ending = Deleted | Cancelled | Failed Fault
```

`Assembling` versus `Assembled` is the upload draft's own distinction: "An upload is incomplete until it is explicitly marked as completed by the client or the server" (`UP:RESUMABLE-UPLOAD-13-4.1.2-1`), and length and offset don't decide it (`UP:RESUMABLE-UPLOAD-13-4.1.3-8`). A producer is whatever fills the chunks: a client upload, a URL import or a transform job. The kernel doesn't know which. `Assembling` holds the staging area the producer writes to once the reconciler has adopted one.

The goal only moves down this order, and its rank is the first component of the convergence metric:

```
rank (Keep (Assembling _ c)) = 2 + (maxChunks - count c)   -- every append lowers it by one
rank (Keep (Assembled _ _))  = 1
rank Clear                   = 0                            -- absorbing
```

Since every move lowers the rank, an asset's goal can change at most `maxChunks + 2` times. Adopting a staging area doesn't change the rank, and it isn't a goal move: it only records which staging area already holds the chunks.

Once an ending is set it never changes. FAILED and CANCELLED absorb a later DELETE, which is answered 410, because a done operation's result shouldn't change (C CH10 in `core.md`).

The AIP-216 state a client sees is a projection, `stateOf :: Asset -> State`. That makes the state output-only, as AIP-216 asks (`SS:AIP216-OutputOnly-1`, a SHOULD we take), and it can't disagree with the facts:

| goal | ending | receipt | store holds nothing | State |
|---|---|---|---|---|
| Keep _ | Absent | Absent | any | CREATING |
| Keep _ | Absent | Present | any | ACTIVE |
| Clear | Deleted | any | no | DELETING |
| Clear | Deleted | any | yes | DELETED |
| Clear | Cancelled | any | any | CANCELLED |
| Clear | Failed f | any | any | FAILED |

FAILED and CANCELLED are resting the moment the ending is set. The store-side cleanup still runs, but it is internal, because the operation's outcome is already decided. A user DELETE shows DELETING until the store is empty, since that's the action the user asked to be told about.

## Observed reality

```
data Observed = Observed
  { stagings :: [Staging]          -- every staging area held for this file id
  , object   :: ObjectObs }
data Staging   = Staging StagingRef [Chunk]
data ObjectObs = NoObject | HasObject Version Vouching
data Vouching  = Vouched ReceiptReport | Unvouchable | NotYetVouched
```

`StagingRef`, `Version` and `ChunkToken` are opaque. The core carries them and never looks inside. No vendor term appears: an S3 multipart upload is one way to be a `Staging`, and an S3 ETag or version id is one way to be a `Version`.

## The store contract

The reconciler is only as honest as what it can observe, so the store contract is now mostly about observation:

1. **Discovery.** Every staging area and every object the store holds for a file is returned by `Observe` on that file's id. Staging areas are created under a name derived from the file id, so one an `Open` created without our learning its reference (a lost or ambiguous answer) is still found. The old design left those to the store's own expiry. Here they're found and discarded.
2. **Safety under staleness.** A command decided on any observation, however old, can't destroy anything it shouldn't. `Seal` is create-only, with the meaning of `If-None-Match: *`: the method isn't performed if a current representation exists (`HS:RFC9110-13.1.2-5`, `HS:RFC9110-13.1.2-6`). `Remove` names the version it was decided on, with the meaning of `If-Match` (`HS:RFC9110-13.1.1-5`). `Discard` is idempotent. `Open` isn't idempotent, but its extras are found by rule 1 and discarded.
3. **Vouching.** `Vouched` means the store vouches for a full-object CRC-64/NVME checksum of the whole object and reports the object's size. CRC-64/NVME detects accidental corruption, not tampering, so a receipt proves "the store holds bytes of this length with this checksum". It doesn't prove where the bytes came from.
4. **Version binding.** The `Version` in an observation identifies the object's bytes. A receipt carries it, and the shell must make every later read and every removal conditional on it. That closes the time-of-check to time-of-use gap: nothing can verify object A and then serve object B under the same name.
5. **Late writes.** A chunk write the core started may land after a `Discard` and make a discarded staging area reappear in a later observation. The vendored AbortMultipartUpload page says the same of S3: parts in progress "might or might not succeed", so an abort may have to be repeated (`PD:S3API-AbortMultipartUpload-API_AbortMultipartUpload-1`). A late write can do that at most once per write the core started and hasn't seen reported. `authorised` lists those writes, each with its deadline (A3).

## The reconciler

```
reconcile :: Env -> Asset -> Decision
data Decision = Decision { command :: Opt StoreCommand, nextGoal :: Goal, nextEnding :: Opt Ending
                         , receiptNow :: Opt Receipt, resyncAt :: Instant }
data StoreCommand = Observe | Open | Seal StagingRef Chunks | Discard StagingRef | Remove Version
```

The reconciler acts only on an observation. A command's answer, of any kind, is only a hint to observe again, and a resync Tick observes again whatever happened, which is how a dropped message heals. Each step issues at most one command.

The rows below are mutually exclusive: for any asset and observation, exactly one row's guard holds. Rows are therefore not evaluated in order, each row's claim stands on its own, and the exhaustive check over the guard tags verifies both that the guards cover every case and that no two overlap. In the guards, `others` means staging areas listed other than the current one, `held c` means the current staging area is listed and holds every chunk of c, and "spend" means using one unit of budget, or moving to `Clear (Failed Unavailable)` when none is left.

| # | goal | receipt | observed | decision |
|---|---|---|---|---|
| R0 | any | any | never observed | Observe |
| R1 | Keep (Assembling Absent c) | Absent | no staging, no object | Open |
| R2 | Keep (Assembling Absent c) | Absent | some staging, no object | adopt the first listed as current |
| R3 | Keep (Assembling (Present r) c) | Absent | r listed, no others, no object | nothing; the producer writes chunks |
| R4 | Keep (Assembling (Present r) c) with r listed, or Keep (Assembled r c) with held c | Absent | others, no object | Discard the first of the others |
| R5 | Keep (Assembling (Present r) c) | Absent | r not listed, no object | Clear, Failed StateLost |
| R6 | Keep (Assembling _ c) | Absent | an object | Clear, Failed Contradiction |
| R7 | Keep (Assembled r c) | Absent | held c, no others, no object | Seal r c |
| R8 | Keep (Assembled r c) | Absent | not held c, no object | Clear, Failed StateLost |
| R9 | Keep (Assembled r c) | Absent | object Vouched, size = total c | receipt := vouch |
| R10 | Keep (Assembled r c) | Absent | object Vouched, size differs | Clear, Failed SizeMismatch |
| R11 | Keep (Assembled r c) | Absent | object Unvouchable | Clear, Failed ObjectWithoutReceipt |
| R12 | Keep (Assembled r c) | Absent | object NotYetVouched | spend, then Observe after backoff |
| R13 | Keep (Assembled r c) | Present v | the object at version v, some staging | Discard the first staging listed |
| R14 | Keep (Assembled r c) | Present v | the object at version v, no staging | converged |
| R15 | Keep (Assembled r c) | Present v | no object, or an object at another version | Clear, Failed StateLost; alarm |
| R16 | Clear | any | some staging | Discard the first listed |
| R17 | Clear | any | no staging, an object at v | Remove v |
| R18 | Clear | any | nothing; no unreported write | converged |
| R19 | Clear | any | nothing; an unreported write | Observe at its deadline |

R4, R7 and R8 together cover an assembled goal with no object. If a chunk is missing from the current staging area, or the area is gone, R8 fails the asset at once, whatever else is listed: there is no point discarding orphans before reporting lost state. Otherwise the area holds every chunk, and R4 discards any other staging area before R7 seals. R4 comes first in effect, not by order but because its guard excludes R7's. Their scenario of an orphaned staging area from a retried Open resolves as: R4 discards the orphan, the next observation matches R7, and R7 seals.

A failed store call (unavailable, ambiguous, refused) never reaches the reconciler. The shell keeps the asset the decision left, whose observation is already stale, so the next step is R0's Observe. By K11 that step hands the asset back unchanged and asks to observe again with no wait, so how soon and how often a failing call is retried is up to the shell. Budget is spent only in R12, on an observation that shows the object not yet vouched, never on a call that failed. While the goal is Clear, the reconciler never gives up, because giving up on a cleanup is a leak; a cleanup that keeps failing shows up as A2's alarm, which the shell raises. (An earlier draft of this paragraph had failures spending budget and the reconciler raising that alarm. The code never did either; "What the kernel can be told" below states what it does.)

R15 is a choice for the product owner. If the store loses an object it vouched for, the asset can't honestly stay ACTIVE, so it ends FAILED with StateLost and an alarm. That does change a done operation's result, and it's the one place the kernel does. The alternative is to keep the operation's result and report the file as lost some other way, which would need vocabulary none of our standards give us.

The old design's 20 sealing and asking rows, its 7 cleanup rows, the "after" states, `AwaitingOpen` and the per-call epochs all go away. What a seal's answer said doesn't matter anymore, only what the next observation shows.

## What we prove

**Safety, per reconciler step** (LiquidHaskell refinements on `reconcile`, measures only):

- K1. A receipt is built only by `vouch`, from a `Vouched` observation of the object whose size equals the assembled length, and it carries that observation's `Version`.
- K2. `Seal` is issued only for `Assembled` chunks, naming exactly those chunks.
- K3. While the goal is `Keep` and a receipt is held, no step emits `Remove`. The good file is never deleted by the reconciler; only R15 (the store lost it) or a client's DELETE moves the goal.
- K4. When the goal is `Clear` and the observation shows anything held, the step emits a command that removes some of it.
- K5. Every `StoreCommand` is create-only, conditional on a version, or idempotent, by its type: there is no unconditional seal or remove to construct.
- K6. `stateOf` is ACTIVE exactly when a receipt is held and the goal is `Keep`.
- K7. The guards of R0 to R19 are exhaustive and pairwise exclusive, and `reconcile` takes the row whose guard holds. `test/Guards.hs` transcribes the guards from this table, apart from the code, and checks every combination of goal, receipt, staging areas listed, object, budget and unreported writes (1320 points).
- K10. While the goal keeps the asset and no receipt is held, no Discard names the staging area holding the goal's chunks. Also missing from the first draft: a mutation that discarded the producer's own staging area passed every other claim, and the gap measure even counted it as progress.
- K9. While a receipt is held for an assembled goal, an observation that shows no object, or an object at another version, clears the goal (R15). This was missing from the first draft; a negative control that left such an asset ACTIVE came back SAFE.
- K8. Every decision's goal has a rank at most the old one's, and the ending is set exactly when the goal becomes `Clear`, never changed after.
- K11. An asset with no observation comes back exactly as it went in, with no alarm (and, by K0, an Observe). A shell that turns a failed observe call into `Unseen` therefore loses nothing but the call: no attempt is spent, no backoff step is taken and nothing ends.
- K12. Every fault the reconciler sets is one an observation justifies, and the observation it is set on shows exactly that: StateLost (no object, or an object at a version other than the receipt's), Contradiction (an object), SizeMismatch (a vouched object), ObjectWithoutReceipt (an object the store will never vouch for) or Unavailable (an object not yet vouched, with the budget spent). The other faults name a call's result or a client-side check, and only the client side sets them.
- K13. The converse of K9: while a receipt is held for an assembled goal and the observation shows the object at the receipt's version, the goal and the receipt stay as they are.

**Progress, per round** (LiquidHaskell, `Funknown.Kernel.Model`, proved). The store contract is a pure function, `perform :: Goal -> Cmd -> Model -> Model`, where the model holds exactly what an observation would show (contract rule 1). Open adds a staging area; Seal turns the goal's staging area into the object and consumes it; Discard removes the staging area it names; Remove removes the object only at the version it names; Observe changes nothing. The model doesn't check chunk contents: a seal of the wrong chunks would show up as a wrong size at the next observation (R10), which is still progress.

The gap counts the store commands still needed before the goal's resting state, from the goal's kind, whether a staging area is adopted, whether a receipt is held, how many staging areas the store holds and whether there is an object:

| goal | gap |
|---|---|
| Clear | staging areas, plus 1 for an object |
| Assembling, nothing adopted | 3 when nothing is staged, otherwise staging areas + 1 |
| Assembling into r | staging areas (r itself stays) |
| Assembled, no receipt | staging areas, plus 2 with no object (seal, then receipt) or 1 with one |
| Assembled, receipt held | staging areas |

A round is: decide, perform the command against the model, observe the result into the asset. The lemma (`round`, through `roundWith`, which uses only the reconciler's result type) says that when the asset's last observation is absent or exactly the model, the round either ends in a resting row (R3, R14, R18, R19) or lowers the metric (rank of the goal, budget, gap, not yet observed) lexicographically, and it leaves the asset's observation exact again. Making that provable needed one fact added to the reconciler's result type for every row (`Prog`): which command it may issue on which observation, and that a step issuing nothing lowers the metric on the same observation.

**Convergence, over whole runs** (LiquidHaskell's termination checker, `Funknown.Kernel.Converge`, proved). A run alternates the reconciler with an adversary's script of moves, which may be infinite. The adversary is anything the contract allows:

- `Drop` loses the round's command or observation, out of a drop allowance `d` that is finite but arbitrary (fairness, written as a number);
- `LateWrite` lands a write the core started and never saw reported, so a staging area reappears and the asset's observation is out of date;
- `Lapse` lets such a write pass its deadline (A3);
- `Append`, `Complete` and `Abandon` let the producer or a client move the goal: append a chunk, complete the assembly, or clear it by cancel, DELETE or expiry.

A move that doesn't apply is an honest round instead. `converge` stops when a round rests (R3, R14, R18, R19), and LiquidHaskell accepts its termination with the lexicographic metric `(rank goal, d, budget, unreported writes, gap, not yet observed)`, not the length of the script. So whatever the script, every run reaches a resting row in finitely many rounds: converged (R14, R18), or waiting on something only the environment can supply, the producer (R3) or a write deadline (R19).

Every move lowers the metric. A drop lowers `d`, a late write or lapse lowers the unreported writes (even though the gap may grow), and a goal move lowers the rank. An honest round lowers it by the progress lemma. The metric's components are proved to be natural numbers by pattern matching (`metricNat`), not assumed with an `invariant` declaration.

Negative controls, each of which makes the termination check fail: drops that cost nothing, drops with the allowance spent, late writes that never run out, an append that doesn't use up the chunk cap, carrying on past a resting row, and a client reopening a cleared goal.

What the adversary doesn't model yet: an observation that is stale but not lost (it counts as a drop), including the one a store command leaves when it lands after the shell's next look, and store answers that keep the object `NotYetVouched` (R12 already bounds that by the budget).

**Bounded exhaustion** (in `test/`, a pure fold): every adversary trace up to small bounds, run through the real `reconcile` and the real client-side step, checking K1 to K6 and that every run within the bounds converges.

## Reattaching the client side

The client side is the upload draft's request handling (the Requests and Receiving columns of `core.md`), rebuilt around the kernel's `Asset`. One file is now

```
data File   = File { meta :: Meta, asset :: Asset, client :: Client, epoch :: Int }
data Client = Client
  { clientLen  :: Len      -- Upload-Length, once a request declared it
  , uploadOpen :: Bool     -- whether the upload resource still accepts requests
  , phase      :: Phase    -- Opening, Idle, Reading, Writing, Sealing or Settled
  , opDeleted  :: Bool }
```

The asset keeps everything the store side needs, and the client keeps only what the upload protocol needs on top of it. The phase names the one request the file owes, if any (a held creation, an append in flight, a completing request waiting on its receipt), and the one mover job it waits for. The offset a client is told is the goal's chunk total, the one number `appendChunk` maintains, so the client side has no offset of its own to get wrong. The epoch is only for mover jobs (a body being read, a chunk being written), and store calls no longer use it.

Every client step is one function, `stepClient :: env:Env -> ev:Event -> f:File -> ClientOut env f ev`, which routes each of the 17 events to its slice: upload-resource requests and mover reports (`Client.Upload`), operation, object and content requests (`Client.Requests`), and the two watches, `KernelMoved` and `Tick` (`Client.Watch`). `create` (`Client.Create`) builds a new file or refuses with a reply.

**The client moves the kernel only the way the adversary does.** Every client step changes the asset by at most one of these moves, and leaves the asset's observation, receipt, budget and backoff step alone. The functions in `Client.Core` that make these moves (`clearGoal`, `appendTo`, `completeGoal`, `startWrite` and `reportWrite`) are the only code that builds an `Asset`, apart from `create`, which builds the first one.

| move | client step | effect on the asset |
|---|---|---|
| none | everything that only answers | the asset is unchanged |
| append | a chunk write reported durable (B10) | `Assembling r c` becomes `Assembling r (appendChunk c k)`; the rank drops by one |
| complete | a completing chunk (B11), a completing empty PATCH, or an empty creation the kernel just adopted | `Assembling (Present r) c` becomes `Assembled r c`; the rank drops to 1 |
| abandon | cancel, DELETE, expiry, a refused creation | the goal becomes `Clear` with that ending; the rank drops to 0 |
| start a write | a body read in full (B3) | one more unreported write, under the job's epoch |
| report a write | any report of that write | every entry under that write's epoch goes, and no other |

This is the `KMove` clause of the contract, stated with the same measures the kernel uses. The goal's rank never rises, the chunks only grow while the goal keeps the asset, a completed assembly keeps exactly the chunks it had (or one more, for B11), an ending once set stays, and the unreported writes grow by at most one, only while assembling and only on a step that leaves the goal alone.

**What the contract holds every step to.** The first version of `ClientOut` said what a step had to keep track of: the owed request is kept or settled, the event's request is settled or becomes owed, a mover job is reported, stopped or kept, a job the file waits for was started by this step or was already running, every new reply deadline has its Tick, and `KMove`. A cancel that didn't cancel, a DELETE that answered 412 and deleted anyway, and a write report that left its entry behind all proved SAFE against it, and only the exhaustive tests caught them, because the contract never said what a step was supposed to do. So in the second round we added the effects every slice shares to `ClientOut` itself, once:

- **A job is named by its epoch.** A job a step starts runs under an epoch greater than the file's (CJobFresh), and it sets the phase that names its kind, a read in Reading and a write in Writing (CJobKind). A report from the job the file is waiting for is its end: the file stops waiting for it, and a reader's report either stops the reader or hands its buffer to the write started under the next epoch (CJobEnded). A report from any other job stops its sender. A current report of the wrong kind runs the job's failure row (B9 while reading, B12 while writing, B16 for the creation request) with a `ShellContract` alert, as CH42 does for the store.
- **A write's report removes its own entry, and nothing else does.** `authorised` grows only on a step that starts a persist job, and its new entry carries that job's epoch and A3's deadline (CWriteJob, CWriteEntry). A report removes every entry under its own epoch (CWriteReported), and no other entry leaves (CWriteKept). That second half is what lets the composition below count a dropped entry as progress: `converge` only sees a late landing through its entry, and an entry now goes only once its own job has said its last word.
- **Every offset a client is told is the goal's** (CToldOffset). That covers `AppendAccepted`, `CreatedUpload`, an offset retrieval's `OffsetIs`, and A2's `OffsetMismatch`.
- **A read is capped** at what one chunk and max-size still allow (CReadCap), and a persist job writes the next chunk into the staging area the goal adopted (CPersistNames).
- **G3 stands before every request, the Tick, and the running job's own report** (CExpires). When the goal is still assembling past its deadline, X1 runs first: the file ends FAILED Expired and the owed request is abandoned. X1 is one function, `expireFile`, and `answer` and `stale` both require that G3 doesn't apply, so no row can answer or ignore a file past its deadline. `KernelMoved` isn't one of these events, because its rows are the watch's own and not `core.md`'s.
- **The watches move the goal only by their own rows** (CQuietGoal). `KernelMoved` never clears a goal (the kernel already did that) and completes only an empty creation the kernel has just adopted. A Tick never completes, and it clears only by X1.

The shared moves state their own effects in their specs too. `abandonFile` clears the goal with the given ending, leaves `authorised` alone and settles the owed request as asked; `answer` leaves the file unchanged; `stale` changes nothing but the report's own write entry; and `endingRefusal` is a measure, so a spec can name the reply a cleared goal owes.

**Held requests are watches on the asset.** A request that can't be answered yet stays in the phase, and `KernelMoved`, which runs after every kernel round, answers it as soon as the asset shows what it was waiting for. A Tick answers only by the clock.

| held request | answered when | with |
|---|---|---|
| the creation request | the reconciler adopts a staging area | 201, Location, Upload-Limit, Upload-Offset 0 |
| an empty creation with UC ?1 | the reconciler adopts a staging area, and the store can seal zero chunks | nothing yet: the goal completes, and the request waits for its receipt like a completing request |
| the completing request | a receipt appears | 201 with the file's ETag and UC ?1 |
| the completing request | `replyBy` passes first (T2, on a Tick at or after that instant, never before) | 202 with the operation as its body, UC ?1 |
| any held request | the goal is cleared first | the ending's refusal, with UC ?1 |

A cleared goal settles every phase that still owes something, `Opening` and `Sealing` with nothing held included, and a Tick over a cleared goal settles exactly as `KernelMoved` would, so a held request gets the ending's refusal and never a 202. Each watch's rows end with "anything else is stale". Once a receipt is held, the file is ACTIVE for every request, Sealing included, so the V rows answer it, and the request waiting on that receipt is never settled or dropped by another upload request. The `File` refinement also gained one fact: a goal still assembling under Idle, Reading or Writing has adopted its staging area.

**What's proved, and what only the tests cover.** LiquidHaskell proves every clause above for every row, and it also proves the row-level effects that fit over measures: the reply offset, the persisted-bytes check on a chunk report, the quota check at completion, a cancel that keeps a receipt, B16 ending the file, B9 abandoning the request and B12 answering `StoreUnavailable`, CancelOperation's refusal to a request still being created, F1's 201, and the cleared goal's refusal. What's left is which reply a client gets wherever a measure can't say it, and the exhaustive suites in `funknown-core/test/` cover it, each transcribed from `core.md` and the client rulings onto a test-side description of the file. One suite per slice runs every event over every phase it handles, with the max-age deadline on both sides of the clock; `dispatch` runs all three again through `stepClient`, and `scenarios` runs composed sequences no single slice reaches. Three things are left to them on purpose. T2's 202 body needs the file id, the outcome and the receipt at once. A set of epochs can't count two entries under one epoch, though CJobFresh already keeps a client step from making two. And the table from ending to refusal is only written in code.

Every claim has a negative control, a mutation that looks like a real bug: LiquidHaskell has to report it UNSAFE, or, for a claim only a test can see, its suite has to fail.

**Convergence carries over between producer actions** (`Client.Compose`, proved). We didn't state a client step as a list of the adversary's moves, because it isn't one. Starting a write has no adversary move, a report removes its entry wherever it sits while `Lapse` only drops the head, and `KMove` bounds the goal without naming the chunk that was appended. So Compose proves what `converge` actually consumes, using Converge's own `Smaller` and `GapA` and Model's `Coherent`, so a change to the kernel's metric reaches it:

- `kmoveMetric`: a step that keeps `KMove` leaves the asset coherent with the store model, and either lowers the kernel's metric or keeps every component of it, or it is the one step that starts a write on an otherwise unchanged assembly;
- `clientThenRound`: a `KMove` step that doesn't grow `authorised`, followed by a kernel round, either rests or ends `Smaller` than before the client step;
- `stepThenRound`: the same for `stepClient` itself, with "the step started a persist job" as the only exception, which CWriteJob makes the only way `authorised` grows.

Starting a write is the one client action that raises the metric, and a client can keep retrying a chunk for as long as it likes. So the honest statement for the composed system is that between producer actions the kernel converges, which is also what R3 means: an assembly in progress rests until its producer does something.

Some rows still wait on a ruling. F9's cancel while sealing answers 204, as A11 and B15 do, where `core.md` says 202. `KernelMoved` over an adopted creation past its deadline answers O1's 201 and leaves X1 to the next Tick. The table from ending to refusal (Gone for Deleted, Cancelled and Expired, Internal for the faults `core.md` doesn't name) is the code's choice. A held completing request answers 201 when a DELETE ends an ACTIVE file. Two readings also wait to be confirmed: that a wrong-kind report past the deadline is G2's and runs its failure row rather than X1, and that a held receipt makes the whole Sealing phase ACTIVE.

## What the kernel can be told

We want the kernel to be a pure decision core for an ETL system: the shell makes every call and absorbs every call failure, and the kernel decides only from what the store holds, the clock and the configuration. The one place a call's result meets the kernel is the shell's next look at the store, so `Funknown.Kernel.Inputs` states the theorem at that look, with A1 written out as its premise: after a call, the shell's look is exactly what the store holds, or nothing, and a look that failed writes nothing into the asset.

- **Every way a call can end is a round the convergence proof already accepts** (`shellRound`). The reconciler decides, the shell makes the call, the store either performs the command before the shell looks again or never does, and the look answers or fails. In every combination the asset stays exact with the store, and the state is smaller in Converge's metric: at the same drop allowance when the store performed its command or there was no call, and by one unit of the allowance when a store command or an Observe was lost, which is A2's fairness. That postcondition is the contract every adversary move in `Converge` is held to (smaller in the metric, allowance not negative, asset exact with the store), except in a resting row, where `converge` stops anyway. It isn't wired into `Converge` as a move of its own yet, so convergence of a run with the shell in it follows from matching that contract, not from a separate termination check. The shell keeps the decision's `next` asset whatever the call did; K0 has already made its observation stale, and K11 says the reconciler hands an asset with no observation back unchanged, so a failed look costs nothing but the call.
- **No call failure can cost a receipted asset anything** (`keeps`). While a receipt is held for an assembled goal and the store holds the object at the receipt's version, a round keeps the goal, the receipt and the object, whatever the call and the look did. The conclusion is the premise again, so it holds round after round until a client or the producer moves the goal. This needed K13, the converse of K9.
- **Every fault the reconciler sets names what the store held** (K12 and `justified`). K12 says which observation each of the five faults is set on: StateLost on no object or an object at a version other than the receipt's, Contradiction on an object, SizeMismatch on a vouched object, ObjectWithoutReceipt on an object the store will never vouch for, and Unavailable on an object not yet vouched with the budget spent. `justified` lifts that from the asset's observation to the store under the same premise. On an asset with no observation, K11 already says more: nothing changes at all, so no fault can be set there. The other faults name a call's result or a client-side check, and only the client side sets them.

The premise is doing real work, and it is exactly where the shell can go wrong. A failed HEAD read as "no object", a failed LIST read as "nothing staged", or a failed attributes call read as "not yet vouched" or "unvouchable" is each a legal store state, so nothing about the types can reject it, and the reconciler would act on it: a receipted asset would fail with StateLost and then have its object removed, or fail with Unavailable or ObjectWithoutReceipt, or a DELETE would end as DELETED while the object is still there. A1 is what rules those out. So the shell contract is that a call which didn't answer is never turned into an observation, and an Observe that answered is turned into exactly what it said. Two negative controls show the theorem depends on it: letting the look be any value, and reading a failed Observe as an empty store, each make LiquidHaskell report UNSAFE.

The theorem also assumes the store performs a command before the shell's next look, or never. A command that lands after that look (a timed-out request the store was still working on) would leave the asset holding an observation that is stale but not lost, which the adversary doesn't model yet. Safety still holds for it by contract rule 2, since every command is create-only, conditional on a version or idempotent, but convergence is unproved there. A third control, a look taken before the store performs the command, makes LiquidHaskell report UNSAFE. The shell can meet the premise the way A3 already does for chunk writes: give every store call a hard deadline and don't look again after an ambiguous failure until that deadline has passed.

Two supporting statements pin down what the inputs can hold at all. `reach` gives, for every `Observed` value, a sequence of the store's own actions that takes an empty store to it: open a staging area (rule 1), land a chunk in it, seal it into an object at a version the store names, consuming the staging area (rule 2), and vouch for the object or decline to (rule 3). `modelEvents` writes every command the store model performs as those same actions, and the K7 suite checks on every small model, goal and command that replaying them gives exactly what `perform` gives, so the actions are the store model the other proofs use, only finer. `reach` catches a call-failure case added to `Observed`, `Seen`, `ObjectObs`, `Vouching` or `Stagings` by itself, but not one added together with a matching store action, because the list of actions is our own transcription of rules 1 to 3; adding one is a visible change to the reference. In the same way, `envFields`, `configFields`, `backoffFields`, `writeFields` and `assetFields` list every input field with its type, so a field whose type is widened to carry a call's result stops them from compiling, and the `*Exact` lemmas say no other field exists. They pin shapes, not meanings, and they don't reach inside `Goal`, `Vouch` or `Outcome`, so the argument for each field's meaning is below.

Field by field, `goal` is what a producer or a client asked for, and it moves only by the client side's `KMove`. `vouch` is built only by `bind` from a vouched observation (K1). `budget` and `backoffAt` count R12's observations. `authorised` lists the writes the core started, each a job and a deadline: a call in flight, never how it ended, because a write's report removes its entry whatever the report said (CWriteReported). `outcome` is the one field whose vocabulary names call results (SourceUnreachable, SourceAnswered, StoreRefusedUs, CreationInterrupted, FinalizeTimedOut), and the reconciler never reads which ending it holds. LiquidHaskell can't state that about a single asset, so the K7 suite checks it: on each of the 440 cleared points, each of the 21 endings, each fault included, gets the same decision and passes through unchanged.

So the reading "a failed call just means no new observation" is right for the reconciler, under A1 and with two refinements; K11 is that reading stated for a single step. The shell has to keep `next`, not the asset it decided on: an asset that keeps its old observation after a command the store did perform is no longer exact with the store, and none of the proofs cover it. And the composed system isn't blind to failures. The client side reads `ChunkFailed` and `MoverDied`, and B16 clears a creation whose first write failed as `Failed Unavailable`. That reaches the kernel only as a goal move the adversary already makes (`Abandon`), so convergence covers it, but it is a call failure decided in the core, not in the shell.

Each statement has a negative control. LiquidHaskell reports UNSAFE for: a `CallFailed` case in `Vouching`, in `Seen` or in `Stagings`; a last-call field on `Env`, a status field on `Config` and a result field on `Write`; R12 failing with StoreRefusedUs, R5 failing with SourceUnreachable, R11 failing with Unavailable, and R14 failing a healthy ACTIVE asset; a reconciler not held to K13; a look that may be any value, a failed Observe read as an empty store, and a look taken before the store performs the command. Three more check the statements aren't vacuous: a witness that seals without settling, a lost store command that spends no allowance, and a lost Observe that spends none. Widening `writeDeadline` to carry a fault stops `configFields` from compiling, and the same widening passes every statement once `configFields` is taken out. The K7 suite fails on a reconciler that alarms on R18 only for a failed asset, and on store actions whose Discard drops only the first staging area of a name, both of which LiquidHaskell accepts.

## What stays assumed, by name

These can't be proved inside the core. We state them so nobody mistakes the proofs for more than they are.

- **A1.** The store meets the contract above, in particular discovery and conditional writes, and the shell turns a call into an observation only when an Observe answered, and then into exactly what it said. The adapter for each store proves or tests it. `shellRound` in `Funknown.Kernel.Inputs` states this as its premise.
- **A2.** Fairness: the shell keeps delivering resync Ticks and the store eventually performs a command it receives. The convergence theorem is conditional on this. When it fails, the alarm on non-convergence past the bound is what makes it visible, so a dead worker pool shows up as alarms rather than as rows quietly pending.
- **A3.** Every write the shell starts has a hard wall-clock deadline, `writeDeadline` seconds after it starts (a configured value), and the shell aborts the write when the deadline passes. A write that hasn't reported by then is treated as dead, and the asset's entry for it is released. The cost is that a cleared asset stays pending, visibly and with a deadline, until its last unreported write's deadline passes. We take that over an invisible leak.
- **A4.** The shell renders what the core decides, and nothing else. Every read and removal it performs is conditional on the version the receipt names.

## What carries over, and what goes

These carry over unchanged: `Upload` and `Chunks` (the list invariants and `canAppend`), `Receipt` and `vouch`, `Http.Retry` (backoff and the token bucket), `Http.Precondition`, `Http.Range`, `Http.Admission`, the registries, and the client-side step contract.

These go: the store-side columns (Opening, Finishing, Ended, Timers' store rows), `Stage`, `Cleanup`, `After`, the per-call epochs for store calls, and `endFile`'s cleanup selection. Epochs stay only for mover jobs on the client side, where a late body or chunk report still has to be told apart from a current one.

## Open items

- **ListMultipartUploads and DeleteObject aren't vendored.** Discovery (contract rule 1) depends on the first, and "Remove is conditional on the version" depends on the second's version-id or If-Match support. Until both pages are vendored and their statements checked, the S3 adapter's claim to meet rules 1 and 2 is unsupported.
- **Create-only seal on local stores.** The vendored CompleteMultipartUpload page documents `If-None-Match: *` (412 when the key exists, 409 ConditionalRequestConflict on a concurrent conflict) for AWS. Whether MinIO and VersityGW honour it is untested.
- **R15** changes a done operation's result. That is for the product owner to accept or replace.

## Order of work

1. The kernel types and `reconcile`, with K1 to K6 and negative controls.
2. The store model (`perform`, `observe`), the gap measure and the progress lemma.
3. The adversary and `converge` with its termination metric.
4. Re-attach the client side (see "Reattaching the client side"): every client step proved to move the kernel only as the adversary does, and held requests answered by `KernelMoved` once the asset shows what they wait for.
5. Bounded exhaustion over the composed system.

The S3 adapter, the projections and the World come after the kernel converges.
