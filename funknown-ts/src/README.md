# The data model, for the modules that come next

These modules port the Haskell kernel's data model: `Funknown.Opt`, `Upload`, `Fault`, `Store.Algorithm`, `Store.Receipt`, `Kernel.Bound`, `Kernel.Types`, and the backoff part of `Http.Retry` that `Kernel.Types` and the reconciler need. Reconcile, Model, Converge and Client/Core are still to come, and they should only need what is listed here. `GAPS.md` at the project root says which Haskell claims became types, which became constructor checks, and which are only tested.

## Conventions

- **Opaque types** are classes this code never exports as values, each with a `private declare readonly nominal` member, so TypeScript compares them by declaration. You can read their fields, but the only way to get one is the producer named below. Don't reach for `Object.assign` to build or patch one: it type-checks, and it bypasses every check (see GAPS.md).
- **Sums** are `Data.TaggedEnum`. Build them with the generated constructors (`Goal.Clear()`, `Cmd.DoDiscard({ ref })`), never as object literals, or `Equal.equals` won't compare them structurally. Take them apart with `Match.valueTags(x, { ... })`, which won't compile with a case missing.
- **Opt is Effect's Option.** Every Haskell `Opt` is `Option.Option`, and `isPresent` is `Option.isSome`.
- **Sentinel measures return Option.** Where a LiquidHaskell measure returned -1, `Version []` or `StagingRef []` to stay total, the TypeScript one returns `Option`: `objVersion`, `objVouchedSize`, `seenVersion`, `seenVouchedSize`, `assembledTotal`, `goalStaging`, `assembledRef`, `vouchVersion`, `vouchSize`, `discardRef`, `removeVersion`, `knownLen`.
- **Tag measures return literal unions** (`ObjTag = 0|1|2|3`, `GoalTag`, `CmdTag`), so `gapI` and later predicates can't be handed an out-of-range tag.
- **Numbers** are `Int`, `Nat` and `PosInt` from `Num.ts`, made by their constructors (`Nat(3)` throws on a bad value, `Nat.option(n)` doesn't). Arithmetic gives a plain number back, so use `addNat`, `subNat` and `lengthOf`, or go back through a constructor.
- **Type guards** come from Effect's `$is` (`isSeen`, `isEnded`, `hasReceipt`, `isKnown`). Please don't hand-write `x is T` predicates: the compiler takes their bodies on trust.
- **Haskell names** are kept, with two exceptions: Haskell's `backoff` function is `backoffDelay` (Config has a field named `backoff`), and `Write`'s two Ints are named `epoch` and `deadline`.

## Surface

### `Num.ts`
`Int`, `Nat`, `PosInt` (brands and constructors), `addNat`, `subNat`, `lengthOf`.

### `Opt.ts`
`Len` (`Len.Unknown()`, `Len.Known({ n })`), `isKnown`, `knownLen`.

### `Fault.ts`
`Fault`, the eighteen ways a transfer fails. `SourceAnswered` carries `status: Int`.

### `Upload.ts`
- `Limits` (opaque) and `limits(fields): Option<Limits>`, plus `LimitsFields`.
- `ChunkToken` (brand), `Chunk` (open class, `cbytes: PosInt`, `ctoken`).
- `Chunks` (opaque, newest first), `emptyChunks(lim)`, `appendChunk(x, c): Option<Chunks>` (present exactly when `canAppend(x, c.cbytes)`), `canAppend`.
- Measures: `limitsOf`, `chunkList`, `offsetOf`, `nChunks`, `room`, `lastBytes`, `total`, `headBytes`, `older`, `allAtMost`, `allAtLeast`, `olderAtLeast`, and `chunksInvariant` (the data refinement as a predicate, for tests).
- `Upload` (opaque), `makeUpload(fields): Option<Upload>`, `uploadInvariant`, `upOffset`, `upLen`, `upComplete`, `upChunks`.

### `Store/Algorithm.ts`
`ReceiptAlgorithm` (`Crc64Nvme`), `allAlgorithms`, `width` (returns the literal `64`), `DrsType` (opaque), `drsType`, `drsTypeName`, `Checksum` (brand), `checksumOf(v: bigint): Option<Checksum>`, `checksumValue`, `checksumBound`.

### `Store/Receipt.ts`
- `ReceiptReport` (opaque), `receiptReport(alg, checksum, size): Option<ReceiptReport>`, `reportAlg`, `reportChecksum`, `reportSize`.
- `SizeDiffers` (opaque, readable `expectedSize`, `reportedSize`).
- `Receipt` (opaque), `vouch(expected, report): Either<Receipt, SizeDiffers>`, the only producer. Readers `alg`, `checksum`, `size`.
- `toHex(r): Hex16`, `hexValue`, `isLowerHex`, `sameHexSameChecksum`, `pow16`, `pow2`, `widthIsSixteenDigits`.

### `Kernel/Bound.ts`
`Version` (brand), `Bound` (opaque), `bind(expected: Nat, v, report): Either<Bound, SizeDiffers>`, the only producer, `boundVersion`, `boundSize`, `boundReceipt`.

### `Http/Retry.ts`
`attemptCap` (the literal 5), `Attempts` (`0..5`), `MaxAttempts` (`1..5`), `spendAttempt(b): Option<Attempts>`, `backoffBound`, `Backoff` (opaque) and `makeBackoff(fields): Option<Backoff>`, `backoffDelay(c, s)`, `Wait`, `nextWait(c, hint, s)`.

### `Kernel/Types.ts`
- Observations: `StagingRef` (brand), `Staging` and `staging(ref, tokens)`, `Stagings` (a readonly array), `refSet` (a `HashSet`), `nStagings`, `Vouching`, `ObjectObs`, `Observed` and `observed(stagings, object)` (use this one, so the list compares structurally), `Seen`, `isSeen`.
- Observation measures: `objTag`, `objVersion`, `objVouchedSize`, `obsObjTag`, `obsVersion`, `obsVouchedSize`, `obsRefs`, `obsStagings`, `seenObjTag`, `seenVersion`, `seenVouchedSize`, `seenRefs`, `seenStagings`, and the `ObjTag` type.
- Intent: `Assembly`, `Goal`, `assemblingGoal(staging, chunks)` and `assembledGoal(staging, chunks)` (use these to build an asset's goal, see below), `GoalTag`, `goalTag`, `rank`, `assembledTotal`, `goalAdopted`, `goalStaging`, `assembledRef`, `gapI`.
- `Ending`, `Outcome`, `isEnded`, `Vouch`, `hasReceipt`, `vouchVersion`, `vouchSize`, `Write`.
- The asset:
  - `Asset` is opaque. Its fields are `goal`, `outcome`, `seen`, `vouch`, `budget: Attempts`, `backoffAt: PosInt` and `authorised`.
  - `AssetInput` is the union of `AssemblingShape`, `AssembledShape` and `ClearShape`, combined with `AssetCommon`. The union makes the ending/goal tie and the no-receipt-while-assembling rule into types.
  - `asset(input: UncheckedInput): Asset` builds an asset with no check. It takes every shape except an assembled goal holding a receipt. `shapedAsset` is the same, with the input's shape kept in the result type, for code that has to say which shape a move lands in.
  - `makeAsset(input: AssetInput): Either<Asset, ReceiptLengthMismatch>` takes any shape, and checks that a receipt has the assembled length.
  - `withSeen`, `withBudget`, `withBackoffAt` and `withAuthorised` replace one field that no refinement involves, so they need no check.
  - `assetInvariant` is the whole refinement as a predicate, for tests.
- Decisions: `Cmd`, `CmdTag`, `cmdTag`, `discardRef`, `removeVersion`, `Config` (`maxAttempts: MaxAttempts`, `backoff`, `writeDeadline: Nat`), `Env` (`now: Nat`, `cfg`), `Row` (`"R0"`..`"R19"`), `allRows`, `isFixedRow`, `Decision` (`next`, `command`, `waitFor: Nat`, `alarm`, `row`).
- AIP-216: `State`, `isActiveState`, `stateOf`.

### `Kernel/Reconcile.ts`
- `reconcile(env, a): Decision`, one step of rows R0 to R19. `decide(env, a)` returns the same decision as a `Leaf` whose row is a literal type; `RowsDecided` is the union of rows some leaf decides, and `everyRowDecided` compiles only when that is every row.
- Lookups: `firstRef`, `firstOther` (both `Option<StagingRef>`, Haskell's `Found`), `listed`, `holds`, `pending`, and the measure `isFailed`.
- Shapes: `ClearView`, `AssemblingView`, `AssembledView`, `KeepView` (an asset's fields, narrowed by goal), `StoreFault` (the five faults `failWith` takes) and `StoreCmd`. `issue`, `rest`, `failWith` and `adopt` are exported only for `controls/compile/reconcile-by-type.ts`.

### `Kernel/ReconcileClaims.ts`
`k0`, `k1`, `k1b`, `k2`, `k3`, `k4`, `k5n`, `k8`, `k9`, `k10`, `k11`, `k12`, `k13`, `prog`, `keepsAuthorised`, and `stepClaims` (all of them by name): LiquidHaskell's Step type as predicates over `(asset, decision)`, for the properties in `test/Reconcile.test.ts` and for Model and Converge to reuse.

### `Client/Core.ts`
- Shapes: `KeepAsset`, `AssemblingAsset`, `AssembledAsset`, `ClearAsset` (each an `Extract` of `Asset`), `AdoptedGoal` and `AdoptedAsset` (an assembly whose staging area is `Option.Some`).
- Guards: `isKeepAsset`, `isAssemblingAsset` (composed from `$is`, so they narrow an `Asset`), and `asAdopted(a: AssemblingAsset): Option<AdoptedAsset>`, which rebuilds the asset because TypeScript won't narrow by a nested Option.
- Moves: `clearGoal(a: KeepAsset, e): ClearAsset`, `appendTo(a: AdoptedAsset, k): Option<AdoptedAsset>`, `completeGoal(a: AdoptedAsset): AssembledAsset`, `startWrite(a: AssemblingAsset, epoch, deadline): AssemblingAsset`, `reportWrite(a: Asset, epoch): Asset`, and `unlist`.

### `Client/Contract.ts`
`goalOffset` (Option where Haskell answers -1), `kMoveClauses(a, b)` (each KMove clause by name) and `kMove(a, b)`.

### `Wire.ts` (and `src/wire/*.schema.json`)
The messages a shell exchanges with the kernel, as zod schemas over the JSON that `funknown-core/dump/Dump.hs` already writes, so the shell, the differential test and the Haskell share one encoding. The header of `Wire.ts` walks through one run of a shell.
- `PersistedState`: the asset between runs, every field but `seen` (goal, outcome, vouch, budget, backoffAt, authorised).
- `Observation`: this round's `Observed`, or `null` (Unseen). All or nothing: when any call the observation takes failed, it is `null`, never a partial answer. K11 proves `null` costs nothing but the call.
- `Env`: `now` is the shell's clock for this run; `maxAttempts`, `backoff` and `writeDeadline` are deployment config.
- `Decision`: the kernel's answer; `next` is a full `Asset`.
- `Stored`: what the shell keeps between runs, made by `keep(env, decision)`: the asset without `seen`, `notBefore` (`now + waitFor`), and the AIP-216 `state`, taken from `decision.next` before `seen` is dropped.
- `Asset` (the kernel's input: a PersistedState plus `seen`), `Observed`, `Fault`, `Ending`, `Vouching`, `Cmd`, `State`, `rows`, `stateOf`, `statesOf`, `kernelAsset(state, seen)` and `persisted(asset)`; the joins are parsed so their results are checked.
- `jsonSchemaText(name)` is the text of `src/wire/<name>.schema.json` (draft 2020-12), generated from the zod schema. `npm run schema` rewrites the files, and `test/Wire.test.ts` fails when they drift.

## Building assets in the reconciler and the client side

`Goal.Keep(...)` returns a Keep of any Assembly, which won't fit an asset's shape, so build goals with `assemblingGoal` and `assembledGoal`. To move an asset, spread it and pass the result back through a constructor: `asset({ ...a, goal: Goal.Clear(), outcome: Outcome.Ended({ ending }) })` compiles because every Clear shape is unchecked. Attaching a receipt to an assembled goal has to go through `makeAsset`, which answers `Left` if the receipt's size isn't the assembled length. R9 binds against `offsetOf` of the goal's chunks, so that `Left` can't happen there, but TypeScript can't see that, and the reconciler will have to say what it does with it.

## Tests and controls

`test/arb.ts` has FastCheck generators for every type here, each built through the real producers, so a property over them covers exactly what callers can reach: `limitsArb`, `chunksArb`, `checksumArb`, `reportArb`, `boundArb`, `goalArb`, `seenArb`, `objectObsArb`, `assetInputArb`, `assetArb`, `envArb` and more. `npm test` builds and runs the properties. `npm run controls` runs the compile-fail controls, the gap demonstrations and the mutants, and prints a verdict for each.

## The store model and convergence

### `Kernel/Model.ts`
- `Model` (an open class: `obs`, `fresh`, `version`, `vouching`), `perform(goal, cmd, model)`, `dropRef`, `observeInto`, `gapM`, `coherent`.
- `Synced` (opaque) is an asset paired with the model it observes, with Coherent as a type. Its producers are `synced(a, m): Option<Synced>`, which checks, and `observedNow(a, m)`, `forgetting(a, m)` and `keepingView(s, b)`, which make it true by construction.
- `Round` (`synced`, `row`), `roundWith(s, decision)` and `round(env, s)`.

### `Kernel/Converge.ts`
- `Move` (`Drop`, `LateWrite`, `Lapse`, `Append({ token, n })`, `Complete`, `Abandon({ ending })`), `FixedRow` and `isResting`, `Run` (`asset`, `model`, `row: FixedRow`, `rounds`).
- `Metric`, `metric(s, d)`, `smaller(after, before)`, `adversary`, `advance` (one iteration), `NoProgress`.
- `converge(env, s, allowance, moves: Iterable<Move>): Either<Run, NoProgress>`. The script may be infinite.

`test/arbModel.ts` has `modelFor(asset)`, `pairArb`, `syncedArb`, `cmdArb`, `moveArb`, `scriptArb` and `forever(script)`. `test/specModel.ts` has the transcribed specs.
