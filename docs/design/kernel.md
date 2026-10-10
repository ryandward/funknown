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

Every store failure (unavailable, ambiguous, refused) leads to the same next step: observe again after backoff. While the goal is Keep and no receipt is held, that spends budget. While the goal is Clear, it never gives up, because giving up on a cleanup is a leak. After a configured bound it raises an alarm and keeps retrying with capped backoff.

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

What the adversary doesn't model yet: an observation that is stale but not lost (it counts as a drop), and store answers that keep the object `NotYetVouched` (R12 already bounds that by the budget).

**Bounded exhaustion** (in `test/`, a pure fold): every adversary trace up to small bounds, run through the real `reconcile` and the real client-side step, checking K1 to K6 and that every run within the bounds converges.

## What stays assumed, by name

These can't be proved inside the core. We state them so nobody mistakes the proofs for more than they are.

- **A1.** The store meets the contract above, in particular discovery and conditional writes. The adapter for each store proves or tests it.
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
4. Re-attach the client side: the completing request is answered when `receipt` becomes present, or with 202 at `replyWait`; DELETE and cancel move the goal to `Clear` with their ending.
5. Bounded exhaustion over the composed system.

The S3 adapter, the projections and the World come after the kernel converges.
