# What TypeScript can't carry

The Haskell kernel states its claims as LiquidHaskell refinements, and the compiler proves them. This port moves each claim to the strongest place TypeScript and Effect allow: a type the compiler enforces, else a check inside the only constructor, else a FastCheck property over generated inputs. This file lists what fell short of a type, and the holes we found in the types we do rely on. `npm run controls` checks every entry that can be checked.

## Holes in what the compiler enforces

**Object.assign forges any opaque value.** `lib.es2015` types `Object.assign(target, source)` as `T & U`, so one genuine `Receipt` is enough to build another with a different size, and `Object.assign(-1, Nat(0))` is typed as a `Nat`. No cast appears and no constructor runs. `controls/gaps/object-assign-forges-opaque-values.ts` has to compile, and it does. This is the TypeScript form of the record-update forgery the Haskell module avoids by not exporting field names. Closing it would take a lint rule that bans `Object.assign` outside the module that owns a type, and no linter is installed. Only `Kernel/Types.ts` uses it, inside `mint`.

**Tagged-enum values can be written as literals.** `Data.TaggedEnum` types are structural, so `{ _tag: "Clear" }` is a valid `Goal`. It isn't built by `Data`, so `Equal.equals` compares it by reference and calls it different from `Goal.Clear()`. The safety claims don't depend on equality, but the Prog claim the reconciler port will check compares goals and observations, and a literal would read as a change there. `controls/gaps/tagged-enum-literals-skip-equal.ts` shows it compiling. Everything in `src/` and `test/arb.ts` builds sums with the generated constructors.

**Effect's own brands are forgeable on objects.** `Brand.Brand<K>` is keyed by `BrandTypeId`, which Effect exports, so an object literal can carry the brand without a cast. That is why record types here are classes with a `private declare` member instead of branded objects: TypeScript compares those by declaration, so a literal or a spread is refused (`controls/compile`). Brands are only used on primitives (`Nat`, `Checksum`, `Version`, ...), where a literal can't carry a symbol key and only the Object.assign hole above applies.

**`readonly` is a compile-time promise.** JavaScript code, or a value reached through reflection, can still write to a field. `Asset` is frozen at construction; the `Data.Class` records aren't, because Effect's `Data.Class` instances aren't frozen by default.

## Claims that became run-time checks in the only constructor

Each of these is a relation between fields, or between a field and a constant, that no TypeScript type can state. The constructor is the only producer (the class value isn't exported), it checks before it builds, and a property test checks that it accepts exactly the right inputs. A mutant that removes each check is caught by the tests.

- `Limits`: `maxChunk >= minChunk` (`limits`).
- `Chunks`: total within `maxSize`, count within `maxChunks`, every chunk within `maxChunk`, only the newest short. `appendChunk` is the only way to grow one and checks `canAppend` first; that `canAppend` keeps the whole refinement is a property test, not a proof.
- `Upload`: offset <= known length <= `maxSize`, and complete only when the known length is the offset (`makeUpload`).
- `Checksum`: `0 <= v < 2^64` (`checksumOf`).
- `ReceiptReport`: size is a Nat (`receiptReport`).
- `SizeDiffers`: reported size differs from the expected size. Haskell leaves this constructor open because LiquidHaskell checks the inequality at every construction site. Here only `vouch` can build one.
- `Backoff`: `initial <= max <= 2^31`, multiplier `<= 2^31` (`makeBackoff`).
- `Asset`: a receipt held for an assembled goal has the assembled length (`makeAsset`). The other Asset refinements are types; see below.
- `Hex16`: `toHex`'s result is sixteen lowercase hex digits, checked by the brand.

**Arithmetic leaves the brand.** `Nat + Nat` is a plain `number` in TypeScript, so every measure that LiquidHaskell typed as `Nat` (`offsetOf`, `room`, `rank`, `gapI`, `total`) goes back through the `Nat` constructor, which throws if the value is negative. For `room` and `rank`, which are Nats only because of the Chunks count invariant, a broken invariant would show up as a throw at run time rather than a compile error. The mutant "canAppend ignores the chunk cap" is caught exactly that way.

**Preconditions became Option results.** `appendChunk`'s LiquidHaskell precondition `canAppend x (cbytes c)` can't be a parameter type, so `appendChunk` returns `Option<Chunks>`, present exactly when `canAppend` holds. A caller that has already checked `canAppend` still has to handle `None`.

## Claims that are tested, not enforced

These are postconditions relating a result to its inputs. TypeScript has no dependent types, so each is a FastCheck property in `test/`, with a mutant in `controls/mutants.json` that the property has to catch. None of them is enforced.

- `appendChunk`: offset grows by the chunk, count by one, limits unchanged, `lastBytes` is the chunk, `room` drops by one.
- `checksumOf` and `receiptReport` keep the value they were given.
- `vouch` keeps the report's algorithm, checksum and size, and answers `SizeDiffers` exactly when the sizes differ.
- `bind` (K1): the bound receipt's size is the expected size and the reported one, and its version is the one observed.
- `toHex` round-trips through `hexValue`, which makes it injective (`sameHexSameChecksum`). Haskell proves this with `hexFromSnoc` and `hexDigits`'s refinement; here it is 1000 generated checksums plus the edge values 0, 1, 15, 16, 2^63 and 2^64 - 1.
- `widthIsSixteenDigits`: checked for every algorithm by enumeration, which is a proof only because there is one algorithm.
- `rank`: 0 exactly for Clear, 1 for an assembled object, at least 2 for an assembly in progress.
- `gapI` against the gap table in `docs/design/kernel.md`, at all 288 points of its small domain. This one is exhaustive, so it is a proof for that domain.
- K6, `stateOf`: ACTIVE exactly when a receipt is held and the goal isn't Clear; DELETED only once the store was seen empty and no write is unreported.
- `backoffDelay` is in `(0, maxBackoff]` and equals A6's closed form `min(initial * k^(s-1), max)` (Haskell's `backoffClosedForm`, proved by induction there).
- `nextWait` (RE3): a hint is the wait and resets the step; no hint backs off and steps up.

## What the types did carry

For contrast, these LiquidHaskell refinements became plain types, each with a compile-fail control:

- The Asset ties: the ending is set exactly when the goal is Clear, and no receipt is held for an assembly in progress. The input to `asset` and `makeAsset` is a union of three shapes, so the wrong combinations don't compile. `asset` (no check) also refuses an assembled goal holding a receipt, which has to go through `makeAsset`.
- `budget <= attemptCap` and `1 <= maxAttempts <= attemptCap` are literal unions. `spendAttempt` lowers a budget by a table, not by subtraction, so it stays a type.
- Tag measures (`objTag`, `goalTag`, `cmdTag`) return literal unions, and `width` returns the literal type `64`.
- `Nat`, `PosInt` and the opaque names (`Version`, `StagingRef`, `ChunkToken`) are brands.
- K2 and K5 by construction: `DoSeal` takes no argument, and `DoRemove` can't be built without a `Version`.
- Opaque types (`Receipt`, `Bound`, `Chunks`, `Limits`, `Upload`, `ReceiptReport`, `SizeDiffers`, `DrsType`, `Backoff`, `Asset`) can't be built by literal, spread or `new` outside their module.
- Exhaustiveness: every case analysis is `Match.valueTags` or a `switch` ending in a `never` check, so a new constructor breaks the build (mutants "a new store command appears", "a new kind of vouching appears", "a new decision row appears").

## What the type can't use once it holds

TypeScript narrows a union by a discriminant on the value itself, not by one nested in a field. The Asset type ties `goal` and `outcome` together at construction, but a reader who checks `a.goal._tag === "Clear"` still sees `a.outcome` as either variant. `stateOf` therefore has a branch for a Clear goal with an Ongoing outcome, which the type rules out. Haskell has the same unreachable line, and LiquidHaskell proves it unreachable; here it is only commented.

The tagged-enum constructors widen the same way: `Goal.Keep({ assembly: Assembly.Assembled(...) })` is typed as a Keep of any Assembly, which doesn't fit the shape an assembled asset needs. `assemblingGoal` and `assembledGoal` build the same value (a test checks they are `Equal`) with the narrow type.

## Proof-only functions

`hexFromSnoc`, `pow16Is2To64`, `growPower`, `monotone`, `backoffClosedForm` and `maxAttemptsSpecDetermines` exist in Haskell only to carry a proof. They have no run-time counterpart here; what they proved is a property test above, or (for `maxAttemptsOf`, which the kernel doesn't use) not ported.

## Numbers

Haskell's `Int` is 64 bits and LiquidHaskell reasons about unbounded integers. `Nat` here is a safe integer, below 2^53, so a sum past that throws instead of wrapping. Checksums are `bigint`, so the 2^64 bound is exact. The backoff product `b * k` can pass 2^53 and lose precision, but only when it is already far above the cap, so the comparison that picks the cap still comes out right.

## The reconciler (Kernel/Reconcile.ts)

LiquidHaskell states K0 to K13 and Prog once, in the `Step` type every row returns, and proves each row against them. TypeScript has no way to say "this function's result relates to its argument like so", so here they are predicates in `src/Kernel/ReconcileClaims.ts` and FastCheck properties in `test/Reconcile.test.ts`, one test per claim over 2000 generated assets with observations built to match them. They are also checked at all 1320 points of the guard domain in `test/Guards.test.ts`. Each claim has a mutant in `controls/mutants.reconcile.json` that its own test has to catch (the mutant's `catches` field). None of them is enforced.

**What did become types.** `issue` takes only a store command (LH's `{c | cmdTag c >= 2}`), `failWith` only a goal that keeps the asset (`goalTag /= 0`) and only one of the five faults an observation of the store can justify (`StoreFault`, LH's `{f:Fault | storeFault f /= 0}`), `adopt` only an assembly in progress, and a leaf's row is one of the table's (`controls/compile/reconcile-by-type.ts`). Every split in `decide` is exhaustive (two tsc mutants), and `everyRowDecided` fails to compile when a row of the table has no leaf (a tsc mutant). Haskell's `adopt` has a fallback equation for an asset of the wrong shape; the parameter type removed it.

**What exclusivity and exhaustiveness mean here.** The types show that every input reaches exactly one leaf and that every row has a leaf. That each leaf is the row the table's guard names is K7, the exhaustive guard test, the same as in Haskell.

**Nested narrowing, and the cost.** TypeScript can't narrow the Asset union by `a.goal._tag`. Effect's `Match.when({ goal: { assembly: { _tag: "Assembled" } } })` can, and `Match.exhaustive` checks the three shapes are covered, but the value it hands over is a structural copy of the shape without Asset's nominal member. So each branch of `decide` holds the value under two names: the Asset, for rows that keep it, and its shape, for rows that rebuild it through `asset()` or `makeAsset()`. Narrowing on a field the union doesn't split on (`vouch`) gets no exhaustiveness at all from Match, so that split is `Match.valueTags(v.vouch, ...)`.

**R9's second check.** `bind` checks the vouched size against the assembled length, and then `makeAsset` checks the receipt against the assembled length again. LiquidHaskell proves the second can't fail; TypeScript can't see it. Both Lefts go to R10, whose guard is exactly "the vouched size isn't the assembled length", so the unreachable branch still does what the table says. One consequence: a mutant that binds against the reported size instead of the assembled length is equivalent (makeAsset still sends it to R10), so it isn't in the mutant list.

**Equality in the claims.** K1b, K8 and Prog compare goals, receipts and observations with `Equal.equals`, which is structural only for values built by Effect's `Data` constructors. A tagged-enum literal written by hand (see the gap above) would read as a change.

## The store model and convergence (Kernel/Model.ts, Kernel/Converge.ts)

In Haskell, the progress lemma is a refinement on `round` and convergence is a termination proof. TypeScript can check neither, so here is where each piece landed. The mutants are in `controls/mutants.model.json`.

**Became a type.**
- Coherent A M, the precondition of `round`, is the opaque `Synced` pair. Four functions produce one. `synced` checks Coherent. `observedNow`, `forgetting` and `keepingView` make it true by construction, because each one either copies the model into the asset's view, marks the view stale, or keeps a view that was already coherent with the same model. `round` takes a `Synced` and returns one, so Coherent after the round is a type as well. The construction argument itself is only tested: every pair a run passes through is checked against a transcribed Coherent, and the mutants "observedNow keeps the asset's old observation" and "forgetting keeps a stale observation" are caught that way. The Object.assign hole above applies to `Synced` like any other opaque type. Compile control: `synced-only-from-producers.ts`.
- `runRow :: {r:Row | isFixedRow r}` is the literal union `FixedRow`. Its guard comes from `Schema.is`, and a test checks it against `isFixedRow` on every row.
- The metric's components are `Nat`, `Attempts` and `0 | 1`. Non-negativity is the Nat brand's run-time check, which stands in for Haskell's `metricNat` and `countNat` (proof-only, not ported).
- Exhaustive case analysis over `Move`.

**Termination became a run-time check in the loop.** `converge` recomputes the six-part metric after every iteration that doesn't rest, and it answers `NoProgress` instead of continuing if the metric didn't go strictly down. Every component is a natural number, so the loop can't run forever, whatever the script, including an infinite one. That this check never fires is a property test, not a proof, so "every run reaches a resting row" is tested. Five mutants that break the metric's decrease make `converge` answer `NoProgress`, and the tests catch it: a free drop, late writes that never run out, an append that doesn't use up the cap, an abandon of a cleared goal, and carrying on past a resting row.

**Tested, not enforced.**
- `perform`'s postconditions, command by command, and contract rule 2 for Remove at another version, which the LiquidHaskell spec doesn't state.
- `dropRef`: the count never grows, and drops when the ref was listed.
- `observeInto`: the asset sees exactly the model, and nothing else changes.
- The progress lemma: from a coherent pair, a round rests or is Lower, observes, stays coherent, and keeps the unreported writes. This was checked on 5000 generated pairs, and the test fails if any of R0 to R19 goes unreached.
- Convergence: the transcribed metric is natural and strictly decreases on every iteration that doesn't rest. This was checked against fixed scripts of up to 300 moves (sometimes repeated forever) and against a greedy adversary that plays whichever move applies. The test fails unless every move kind applied, every resting row was reached, and some run took 30 or more iterations.
- The specs are transcribed in `test/specModel.ts` (Coherent, GapM, Lower, the metric, the lexicographic order). The tests don't read them from the code, so a mutant of the code can't move the bar it's held to.

**Weaker than Haskell.**
- `roundWith` takes any `Decision`. In Haskell it takes `Step a`, which carries K0 to K13 and Prog, so the lemma rests on the reconciler's type there and on the reconciler's tests here.
- Haskell's `roundWith` also says that a store command always lowers the metric, that Open and Discard leave the object alone, and that the round keeps the decision's goal, receipt and budget; `Funknown.Kernel.Inputs` (`shellRound`, `keeps`, `justified`, `reach`) builds on those. None of that is ported, so the port's progress test checks only the original postcondition.
- `spend` (R12) takes an `AssembledView`, which says the goal is assembled and nothing more. Haskell's `spend` also requires no receipt and an observation that shows the object not yet vouched for (`seenObjTag == 3`), and K12's Unavailable clause leans on that. TypeScript can't tie the observation `decide` destructured to the asset's own `seen`, so here it rests on `decide` calling `spend` only from the NotYetVouched branch, and the K12 property only catches a `spend` reached from anywhere else on the step where it ends the asset, with the budget spent (the mutant "R11 spends an attempt instead when the budget is already spent", which ends the asset Unavailable on an object the store will never vouch for).
- A `Drop` marks the decided asset's view stale with `forgetting`. Haskell relies on K0 instead, which proves that view is already stale after any command. If a reconciler bug broke K0, this port wouldn't show it at a drop.
- `appended` and `completed` have to re-narrow `outcome` and `vouch` after matching on the goal, because TypeScript doesn't narrow by a nested discriminant. Their other branch says the move doesn't apply. The Asset type rules that branch out, but TypeScript can't see that.

## The client side's moves (Client/Core.ts, Client/Contract.ts)

In LiquidHaskell every client move's result type carries `KMove a b`, so all eleven clauses are proved at every move. TypeScript can't say that a field of the result equals a field of the argument, so I split KMove three ways.

**Carried by the move types.** Each move's parameter and result types name the asset's shape (`KeepAsset`, `AssemblingAsset`, `AdoptedAsset`, `AssembledAsset`, `ClearAsset`), so Haskell's preconditions are parameter types, and the goal's kind can only move down its order: `clearGoal` goes from Keep to Clear, `completeGoal` from an adopted assembly to an assembled object, and the others stay where they are. A Clear result can't be handed back to `startWrite`, and an assembled one can't go back to `appendTo`. `controls/compile/client-moves-by-shape.ts` holds eight such refusals.

**Carried by how the module is built, and checked by tests.** Four private lanes (`toClear`, `regrow`, `seal`, `withWrites`), plus the shared `withAuthorised` for `reportWrite`, are the only code that builds a moved asset. Each copies seen, vouch, budget and backoffAt from the old asset by name, and none takes them as a parameter, so a move's own code has no way to pass in a new observation, receipt or budget. `regrow` and `seal` take no staging area, and `seal` takes no chunks, so `appendTo` and `completeGoal` keep the staging area and `completeGoal` keeps exactly the chunks. That's a fact about this module's structure and not a type: a new move written in this module could call `shapedAsset` directly. Whether the lane bodies copy faithfully is a property, and three mutants that make a lane change the budget or the staging area are caught by the tests.

**Tested only.** `appendTo` lowers the rank and adds exactly the chunk's bytes (from `appendChunk`'s postcondition, itself tested), `startWrite` adds exactly one write, and `reportWrite` never adds one. `test/ClientCore.test.ts` holds every move to all of KMove, to its own Haskell postcondition and to the Asset refinement on generated assets. A further property runs random scripts of up to 30 client moves and checks that the prefix of Converge's metric the client can touch (rank, then budget, then unreported writes) never rises, apart from each start's one write, and that every goal move lowers the rank.

**The predicate itself.** A KMove that accepted everything would pass every property above, so one test builds, for each of the eleven clauses, a move that breaks it, and requires that clause to be the one that refuses. Three mutants that weaken a clause are caught there.

**Nested Option narrowing.** TypeScript narrows an asset by a discriminant on its goal (Effect's `$is` guards composed with `Predicate.struct` and `hasProperty` do this without a hand-written `x is T`), but not by an `Option` two levels down: a guard on `goal.assembly.staging` leaves the asset's type as it was, because the narrowing keeps any union member that is merely comparable. So `asAdopted` rebuilds the asset with the narrower `AdoptedGoal` type, and a test checks that the rebuilt goal compares equal to the original. The payoff is that `completeGoal` reads the staging area with no None branch, where Haskell matches `Assembling (Present r) c`.

**Shared-module change.** `Kernel/Types.ts` gained `shapedAsset`, which is `asset()` with the input's shape kept in the result type. `mint` became generic to support it. Nothing else in Types changed.

## The wire format (src/Wire.ts)

The wire schemas are the shell's way in, so they have to refuse whatever the kernel's types refuse. I wrote them in zod and generate the JSON Schema files from them, which means the two can only disagree where JSON Schema has no words. The mutants are in `controls/mutants.wire.json`.

**One definition per member.** PersistedState and Asset are unions of the same three members, and Asset's are PersistedState's with `seen` added by zod's `safeExtend`, which keeps strictness and refinements. I'd first written the two unions side by side, and a reviewer showed that a member could then be strict or refined in one and not the other with every test still green. A generic helper would have been the obvious fix, but the compiler refused it, and rightly: a generic `extra` shape could override `goal` or `vouch` underneath the refinement that reads them.

**Both formats carry it.** Strict objects, every tag as a literal, Nat and positive bounds, `budget` in 0..5 and `maxAttempts` in 1..5, every backoff field at most 2^31, and the checksum bound: the checksum is Dump.hs's decimal string, and `decimalAtMost` writes a pattern that matches exactly the numerals 0 to 2^64 - 1. The two Asset ties (an ending exactly when the goal is Clear, no receipt while assembling) are the three union shapes the port's `AssetInput` already uses, so JSON Schema carries them too. The tests hold this structurally rather than by example: every object the JSON Schema describes refuses an excess key and every integer refuses a fraction, in all five messages, and a coverage check fails if no sample reaches one of those schema paths. Every tag schema is read against its Haskell `data` declaration, both ways.

**Only zod carries it.** JSON Schema 2020-12 can't compare one value in a document with another, or add values up, so six refinements are zod checks and only a `$comment` in the JSON Schema: `maxChunk >= minChunk`, the Chunks invariant (total within `maxSize`, count within `maxChunks`, every chunk within `maxChunk`, only the newest short), a receipt's size equal to the assembled length, `initialBackoff <= maxBackoff`, `now + max(writeDeadline, maxBackoff)` within 2^53 - 1, and a Stored state that is one stateOf gives for its asset. A shell that validates with JSON Schema alone would accept those mutants.

**Neither carries it.** On the wire a receipt is three fields, so a stored state holding a receipt the kernel never bound parses fine. In Haskell only `bind` makes a `Bound` and only R9 calls it (K1); here the shell has to store exactly what the kernel answered. The same goes for `authorised`, which only the client side's `startWrite` should grow. Closing that would mean signing the persisted state, which is a shell concern. The other thing no schema can carry is whether an Observation is honest: a failed call dressed up as `object: null`, `stagings: []`, `Unvouchable` or `NotYetVouched` is a well-formed observation, and the kernel acts on it. The tests show each one ending the asset or spending an attempt, so the rule that a failed call makes the whole Observation null is the shell's to keep.

**Narrower than Haskell.** Integers are safe integers. Haskell's Int is 64 bits, but a JavaScript shell can't hold more than 2^53 exactly and `JSON.parse` would round it before zod looked. Env therefore also bounds `now + max(writeDeadline, maxBackoff)`, because the client side stores `now + writeDeadline` as a write's deadline and the shell stores `now + waitFor`; without that bound an Env zod accepts could produce a state zod refuses on the next run.

**Checked against the port, not the Haskell kernel.** Nothing in funknown-core parses JSON, so "a shell that parses with zod lands on the kernel's input" holds through the port: every fixture record zod accepts is built through the port's own producers (`makeAsset`, `bind`, `appendChunk`, `limits`, `makeBackoff`) and written back unchanged, each refinement's mutant record is refused by zod and by the producer that checks the same thing, and the port is held to the Haskell by the differential test. zod's output type also has to fit the port's input type, so widening `budget` past 5, or adding a fault tag the port lacks, fails `tsc` before any test runs. The wire's `stateOf` is checked against the port's on every fixture asset; State isn't in the dump, so that agreement reaches the Haskell only through the port's own K6 property.
