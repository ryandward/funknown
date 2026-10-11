# What the proved kernel became in TypeScript

We have a Haskell kernel whose claims LiquidHaskell proves: the reconciler's safety claims K0 to K13 on every step, a progress lemma for every round, and convergence against an adversary, all on top of a proved data model. Four agents ported the data model and the kernel moves to strict TypeScript with Effect, and we wanted an honest answer to two questions. Does the port compute what the Haskell computes? And what is each proved claim now: a type the compiler holds, a run-time check, a test, or nothing?

## The short answer

The port computes the same thing. I ran the Haskell kernel, with the LiquidHaskell plugin turned off, on 9499 inputs and fed the same inputs to the TypeScript, and every decision, round and converged run came back identical. The inputs were the whole guard domain, generated reconciler steps, rounds of the store model and full adversary runs, and every row R0 to R19 shows up in each of the three kinds.

What changed is the strength of the claims. Very little of what LiquidHaskell proves became a type. The parts that did are shapes: which fields go together, which commands carry which arguments, which preconditions a function accepts, and exhaustiveness. Every claim that relates a result to its input became a sampled property test. That covers all of K0 to K13, Prog, KMove's equalities, the progress lemma and convergence. Relations between fields became checks inside the one constructor that can build the value. The port was fast because TypeScript asks for so much less.

The LiquidHaskell negative controls still get caught. I translated 33 of them into the TypeScript, and every one is caught except R1, which turns out to behave exactly like the original code because a second check stops it. The catch is that most of them are caught by tests rather than by tsc. Two of the controls LiquidHaskell itself missed are caught in TypeScript, but only by the differential test, which is a comparison against the Haskell and not a claim of the port's own.

## Time

The port took 51 minutes of wall-clock time, from 18:00:36 to 18:51:39 on 2026-10-10. The data-model agent worked alone for about 20 minutes, and then three agents (reconciler, store model and convergence, client moves) worked in parallel for about 30. That adds up to about 97 agent-minutes:

- types: 18:00:36 to 18:20:28, about 20 minutes;
- reconciler: 18:22:03 to 18:40:53, about 19 minutes;
- store model and convergence: 18:22:03 to 18:51:39, about 30 minutes;
- client moves: 18:22:03 to 18:49:33, about 27 minutes.

This comparison (the dump, the differential test, the translated controls and this file) took me from 18:52:42 to 19:21, about 28 minutes, which is a bit over half the port's wall-clock time.

For the LiquidHaskell side, the transcript and the file times show the kernel's proved modules (Types, Reconcile, Model, Converge) being written in the main session between about 21:10 and 23:10 PDT on 2026-10-09, on top of Upload, Receipt and Retry, which had been proved before that. The client-side integration ran for most of the following day. One clean LiquidHaskell build of the kernel takes 2m13s on this machine, against about half a second for tsc 7 on the whole port, so the edit-check loop is a couple of hundred times faster in TypeScript. I couldn't recover a minute-for-minute figure for the LiquidHaskell effort, so the fairest summary I can give is hours of proof work against under an hour of porting.

## The differential test

I added an executable, `haskell-dump` (`funknown-core/dump/Dump.hs`), which runs the kernel as an ordinary program. It uses only `base` and writes its JSON by hand. It builds every input through the real Haskell producers (`appendChunk` only when `canAppend` holds, `receiptReport`, `bind`) and writes one JSON line per input with the Haskell result. Generation is splitmix64 over fixed seeds, so the dump is identical on every run. `test/Differential.test.ts` decodes each line with Effect Schema (no casts), builds the same input through the TypeScript producers, runs the TypeScript function, encodes the result in the same shape, and compares the two encodings.

| kind | points | what one point is | disagreements |
|---|---|---|---|
| step, guard domain | 1320 | `reconcile` at every point of test/Guards.hs | 0 |
| step, generated | 1500 | `reconcile` on a generated asset and environment | 0 |
| round | 5179 | `round` on a Coherent pair; 1500 generated pairs, each followed for up to 5 rounds | 0 |
| converge | 1500 | `converge` with a drop allowance of 0 to 4 and a script of up to 30 adversary moves | 0 |
| total | 9499 | | 0 |

No point disagrees, so there is no wrong side to report. The generated inputs vary the goal (all four kinds), chunk lists under five different limits, staging lists with full, partial, foreign and duplicated areas, objects at three versions with right and wrong sizes, receipts with checksums of 0, 7 and 2^64 - 1, budgets 0 to 5, backoff steps up to 64, backoff configurations up to 2^31 for both the cap and the multiplier, and up to three unreported writes. Every row R0 to R19 is reached by the generated steps and by the rounds, and the converge runs end in all four resting rows and play every kind of move (about 5000 Drops and Appends and about 2700 of each other kind).

The differential test doesn't cover these:

- the client moves in `Client/Core.ts`, since only the adversary's versions of append, complete and abandon (in `Converge.ts`) are exercised;
- `stateOf`, so the K6 control below is caught by its property alone;
- numbers past 2^53, where TypeScript's `Nat` throws and Haskell's `Int` doesn't.

I added the test to the suite, so `npm test` and every mutant in `npm run controls` now run it too. Its fixture, `test/fixtures/haskell-dump.jsonl`, is 9 MB, so `npm run fixture` writes it from `haskell-dump` before every test run rather than keeping it in git, and the test takes about 1.5 seconds. With it in place, `npm test` passes all 75 tests, and all 102 checks in `npm run controls` hold. One mutant, "receipts allowed while assembling", was written when only the data model existed and expected a compile control to catch it. Once the reconciler and client moves depended on the asset's shape, tsc caught it first in the main build, so its expected layer is tsc now. Adding the differential test flipped no verdict.

## Claim by claim

"Type" means tsc refuses the violation. "Constructor" means a run-time check inside the only producer refuses it. "Property" means a FastCheck property or an exhaustive test samples it, and nothing stops a violation at run time. Every row has its own negative control in `controls/` (see GAPS.md and the four agents' reports).

| proved in LiquidHaskell | in TypeScript |
|---|---|
| `Opt` and `isPresent` in specs | type: Effect `Option`, with `isSome` as a real guard |
| `Len`: a known length is a Nat | type plus constructor: tagged enum with a `Nat` brand |
| Limits: per-field bounds | type: `PosInt` and `Nat` brands |
| Limits: `maxChunk >= minChunk` | constructor: `limits()` |
| Chunks list refinement (total, count, sizes, only the newest short) | constructor: `appendChunk` checks `canAppend`; that it keeps the refinement is a property |
| `appendChunk` precondition `canAppend` | constructor: an `Option` result, so callers handle a None that LiquidHaskell proves impossible |
| `appendChunk` postconditions (offset, count, room, lastBytes) | property |
| `offsetOf`, `nChunks`, `room`, `rank`, `gapI` are Nats | constructor: arithmetic leaves the brand, so each goes back through `Nat()`, which throws |
| Upload refinements | constructor: `makeUpload` |
| Checksum below 2^64 | constructor: `checksumOf` on a bigint |
| ReceiptReport size is a Nat; SizeDiffers sizes differ | constructor: `receiptReport`; only `vouch` builds SizeDiffers |
| Receipt only from `vouch`, Bound only from `bind` | type: opaque classes, except that `Object.assign` forges any opaque value (GAPS.md) |
| `vouch` and `bind` (K1) postconditions | property |
| `toHex`: 16 digits, round trip, injective | constructor (Hex16 brand) plus property |
| `width a == 64` | type: literal `64` |
| `widthIsSixteenDigits` | test by enumeration, a proof only because there is one algorithm |
| Backoff refinement | constructor: `makeBackoff` |
| `backoff` range and A6 closed form (proved by induction) | property |
| `nextWait` (RE3) | property |
| Asset: ending exactly when Clear; no receipt while assembling | type for builders (a union of three input shapes); readers can't narrow by it, so `stateOf` and the adversary keep branches the type rules out |
| Asset: a held receipt has the assembled length | constructor: `makeAsset` |
| Asset: budget at most 5, backoff step at least 1 | type: literal union `0..5` and `PosInt` |
| tag measures in range; Config, Env and Decision field bounds; Row in R0..R19 | type: literal unions and brands |
| K6 (`stateOf`) | property |
| `rank` relations, `gapI` against the table | property (gapI exhaustive at 288 points) |
| K0, K1, K1b, K3, K4, K5n, K8, K9, K10, K11, K12, K13, Prog, authorised unchanged (the `Step` type) | property: 2000 generated steps per claim plus all 1320 guard points; none enforced |
| K2 (Seal names nothing), K5 (Remove carries a Version, Discard a StagingRef) | type: the `Cmd` constructors' fields |
| preconditions of `issue`, `failWith`, `adopt` | type: `StoreCmd`, `KeepView` and `StoreFault`, `AssemblingView` |
| `failWith`'s postcondition `failedOnStore (outcome (next d)) == storeFault f` | property: K12 reads the fault back from the ending |
| precondition of `spend` (assembled, no receipt, the object seen and not yet vouched) | weaker: the parameter type says only assembled; `decide` reaches `spend` only from the NotYetVouched branch, and K12's Unavailable clause checks it on the step where `spend` ends the asset |
| K7: guards exhaustive and exclusive, and `reconcile` follows them | split: tsc holds the decision tree's shape and that every row has a leaf (`everyRowDecided`); that each leaf is the right row is the exhaustive guard test, as in Haskell |
| `received`'s precondition (the Bound has the assembled length) | constructor: `makeAsset` checks again, and its Left goes to R10 |
| `pending` is a Nat | constructor |
| `firstRef`, `firstOther`, `listed`, `holds` postconditions | property |
| Coherent, the precondition of `round` | type: the opaque `Synced` pair; three of its four producers are coherent by an argument the compiler doesn't check, which is a property |
| `perform`, `dropRef`, `observeInto` postconditions | property |
| progress lemma (`round` rests or is Lower, stays Coherent) | property: 5000 generated starts |
| `roundWith` takes `Step a` | weaker: it takes any Decision, so the lemma rests on the reconciler's tests |
| `Run`'s row is a resting row | type: `FixedRow` literal union |
| `metricNat`: the metric is natural | constructor: `Nat` brands |
| termination of `converge` (lexicographic metric) | constructor-like: the loop recomputes the metric and answers NoProgress if it didn't drop, so it can't loop forever; that NoProgress never happens is a property |
| adversary moves lower the metric and keep Coherent | property, with Coherent a type through `Synced` |
| a Drop relies on K0 | gap: the port forgets the view explicitly, so a K0 regression wouldn't show at a drop |
| client move preconditions; the goal kind only moves down | type: shape-typed parameters and results |
| KMove equalities (seen, vouch, budget, staging, chunks unchanged) | module structure (four lanes copy them by name) plus property |
| KMove: at most one write starts, offsets only grow | property |
| the client step contract (`ClientOut`) | not ported |

## The negative controls, translated

The controls come from three places. The design doc and the README name them, and I recovered the exact mutations and LiquidHaskell's verdicts from the session transcripts, because mutate.sh and mutate2.sh don't keep logs. I also re-ran four of them, plus one extra, against the current proved kernel in a scratch copy, and ran the Haskell guard test on three of them.

`controls/lh-controls.mjs` applies each translation to a fresh copy of the port and records every layer that notices, without stopping at the first: tsc, a constructor check that throws, the property tests (everything except the differential test), and the differential test. Its last output is in `controls/lh-controls.txt` and `controls/lh-controls.out.json`. The runner prints the layers it can detect mechanically. Two of the verdicts below are my reading of that output: R1 prints as NOT CAUGHT, and C2's constructor throw shows up inside the property and differential failures (`expected a natural number`) rather than in their own column.

| # | LiquidHaskell control | claim | LH verdict | TypeScript: caught by |
|---|---|---|---|---|
| R1 | trust the store's size for the receipt | K1 | UNSAFE | constructor, as an equivalent mutant: `makeAsset` refuses the receipt and the step goes to R10, exactly as before, so no later layer can see a difference |
| R2 | remove the vouched object while ACTIVE (R13) | K3 | UNSAFE | property (K3, Prog, progress, convergence), differential |
| R3 | remove a version nobody observed (R17) | K5n | UNSAFE | property (K5n, convergence), differential |
| R4 | leave a staging area behind on Clear (R16) | K4 | UNSAFE | property (K4, Prog, convergence), differential |
| R5 | stay ACTIVE after the store lost the object (R15) | K9 | SAFE at first, which is how K9 was found; UNSAFE now | property (K9, Prog, convergence), differential |
| R6 | decide before observing (R0) | K0 | UNSAFE | property (K0, Prog, convergence), differential |
| R7 | spend budget that isn't there | budget is a Nat | UNSAFE | tsc: `Option<-1>` isn't an `Option<Attempts>` |
| R8 | clear the goal as Cancelled, not Failed | K8 | UNSAFE | property (K8), differential |
| R9 | seal while an orphan staging area is listed (R4) | none | SAFE; the Haskell guard test misses it too | differential only |
| R10 | accept any version as the vouched one | K9 | UNSAFE | property (K9, K7), differential |
| R11 | call a file ACTIVE before its receipt | K6 | UNSAFE | property (K6) |
| R12 | stall on leftover staging after the receipt (R13) | Prog | UNSAFE | property (Prog, progress, convergence), differential |
| R13 | open while something is staged (R2), literally | Prog | UNSAFE | tsc: R2 loses its leaf, and `everyRowDecided` refuses |
| R13b | the same, keeping the row R2 | Prog | UNSAFE | property (Prog, progress, convergence), differential |
| R14 | retry forever without spending (R12) | Prog | UNSAFE | property (Prog, progress, convergence), differential |
| R15 | discard the producer's own staging area (R4, assembling) | K10 | SAFE at first, which is how K10 was found; UNSAFE now | property (K10), differential |
| R16 | the same, for an assembled goal | K10 | UNSAFE | property (K10), differential |
| R17 | R3 no longer a resting row | progress lemma | UNSAFE | property (Prog, progress, FixedRow agreement, convergence) |
| R18 | discard orphans before failing a missing chunk (R4 before R8) | K7 | SAFE; the Haskell guard test catches it (16 points) | property (K7 guard test), differential |
| C1 | drops that cost nothing | termination | UNSAFE | property (metric tests), NoProgress, differential |
| C2 | drops with no allowance left | termination | UNSAFE | constructor (`Nat(d - 1)` throws), property, differential |
| C3 | late writes that never run out | termination | UNSAFE | property, NoProgress, differential |
| C4 | an append that doesn't use up the cap | termination | UNSAFE | property, NoProgress, differential |
| C5 | keep going after a resting row, literally (`if False`) | termination | UNSAFE | tsc: the dead branch still has to hand `Rested` a `FixedRow` |
| C5b | the same, in a form that compiles | termination | UNSAFE | property, NoProgress, differential |
| C6 | a client can reopen a cleared goal | termination | UNSAFE | property, NoProgress, differential |
| K1 | clear without an ending | KMove, Asset | UNSAFE | tsc: a Clear goal with an Ongoing outcome fits no asset shape |
| K2 | append into a different staging area, literally | KMove | UNSAFE | tsc, by accident: `Option.some` is typed `Option`, not `Some` |
| K2b | the same, in a form that compiles | KMove | UNSAFE | property (KMove, client script) |
| K3 | append that drops the new chunk | KMove | UNSAFE | property (KMove) |
| K4 | complete that also starts a write | KMove | UNSAFE | property (KMove, client script) |
| K5 | report that starts another write instead | KMove | UNSAFE | property (KMove, client script) |
| K6 | the client throws away the receipt | KMove | UNSAFE | property (KMove, client script) |
| - | a stale report answers something; leave the mover running; drop the owed request | ClientOut | UNSAFE | no counterpart: the client step contract wasn't ported |
| - | skipping the cleanup's confirm (README) | old design | - | no counterpart: the kernel has no confirm step |
| X1 | `pending` reports the earliest deadline (not an LH control) | `pending :: Nat` | SAFE; the Haskell guard test catches it (4 points) | property (pending), differential |

Counting the 33 translated controls, with the literal and compiling forms of R13, C5 and K2 counted separately:

- tsc catches 5 (R7, R13, C5, K1 and K2). Only R7 and K1 are the claim itself showing up as a type. R13 and C5 are caught through the row and resting-row types, and K2 is caught by a typing accident.
- A constructor check catches 2. C2 is a `Nat` throwing. In R1 the bug can't take effect, because `makeAsset` checks the receipt a second time.
- The property tests catch 26, and the differential test catches 19 of those plus R9.
- R1 changes no behavior at all, so no test could catch it. It was a real bug in Haskell; in TypeScript the second check in `makeAsset`, which LiquidHaskell proved unnecessary, makes it harmless.

R9 matters most, because neither side catches it with a claim. Sealing while an orphan staging area is listed breaks no safety claim, the Haskell guard test only compares rows, and the row stays R4. Only the differential test notices, and the differential test is just "the TypeScript disagrees with the Haskell". It would catch any behavior change, so it isn't evidence that the port's claims are strong. If we want the table's commands, not just its rows, to hold, it looks to me like the guard test on both sides should also check that each row issues the command the table names.

## Where the TypeScript was easy, and where it can't say what LiquidHaskell says

**Easy.** Effect's `Data.TaggedEnum` with `Match.valueTags` gave us exhaustive sums for free, and adding a constructor breaks the build, just as `-Werror=incomplete-patterns` does. Literal unions and brands carried every bound on a single field, and they did it more directly than the LiquidHaskell measures did. The budget's bound, for example, is just the type `0 | 1 | 2 | 3 | 4 | 5`, and the R7 control fails to compile. Opaque classes whose value is never exported gave us "only `vouch` builds a Receipt" with no proof at all. Splitting the asset's input into three shapes made the goal/ending/receipt ties a type for anyone building an asset. And a whole build checks in half a second, so nobody needed the clean-build rituals the LiquidHaskell work did. Most of the port's speed came from the fact that nothing had to be proved, so all the work went into generators good enough to reach every row.

**Can't say it.** TypeScript has no way to say that a function's result relates to its argument. That one gap covers most of what LiquidHaskell proves here: every K-claim, Prog, KMove's equalities, the progress lemma and every postcondition. Each of those is now a property over generated inputs, and none of them is enforced. Relations between two fields of one value (maxChunk >= minChunk, a receipt's size against the assembled length) can only be checks inside the one constructor. There is no termination checker, so convergence became a run-time check of the metric inside the loop, plus tests that the check never fires. Arithmetic on a brand gives a plain number back, so every Nat that LiquidHaskell proved non-negative is checked again at run time.

**Can say it, but readers can't use it.** The asset's shape union holds at construction, but TypeScript won't narrow `a.outcome` by `a.goal._tag`, so `stateOf`, `appended` and `completed` all keep branches the type rules out. Effect's nested `Match.when` does narrow, but it drops the asset's nominal identity, so the reconciler carries each asset under two names.

**What the types promise and don't deliver.** `Object.assign` is typed `T & U`, so one genuine value forges any opaque value or brand with no cast, and `Effect`'s object brands can be forged by a literal. Both are written up in GAPS.md, and a lint rule would close the first. LiquidHaskell has no hole of that kind in this code.

**What I'd take from this.** The Haskell proofs and the TypeScript tests agree on all 9499 points, and on this kernel the proofs mostly bought certainty rather than different behavior. The port's claims are only as good as its generators. Two LiquidHaskell controls (R9 and R18) and one extra (X1) show that an unproved function, or a spec that is silent about something, slips past LiquidHaskell just as easily, and that an exhaustive test is what closes those gaps on either side.

## Files

- `funknown-core/dump/Dump.hs` is the dump executable, `haskell-dump`
- `funknown-ts/test/Differential.test.ts` is the differential test
- `funknown-ts/test/differential-shims.d.ts` hand-types `node:fs` and `import.meta.dirname`
- `funknown-ts/test/fixtures/haskell-dump.jsonl` is the dump's output, written by `npm run fixture` and not committed
- `funknown-ts/controls/lh-controls.mjs` holds the translated controls and their runner; `lh-controls.txt` and `lh-controls.out.json` are its last run
