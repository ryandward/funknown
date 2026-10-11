// Funknown.Kernel.Types: what an asset should become (its goal), why it is
// going away (its ending), what the store was last seen to hold, and the
// receipt. See docs/design/kernel.md.
//
// LiquidHaskell measures that return a sentinel to stay total (-1 for "no
// size", Version [] for "no version", StagingRef [] for "none") return an
// Option here instead, so a sentinel can never collide with a real value.
// Measures that return a tag in a range return a literal union, so the range
// is the compiler's to check.
import { Brand, Data, Either, HashSet, Match, Option } from "effect"
import type { Fault } from "../Fault.js"
import { type Attempts, type Backoff, type MaxAttempts } from "../Http/Retry.js"
import { type Int, Nat, type PosInt, addNat, lengthOf } from "../Num.js"
import { type Bound, type Version, boundSize, boundVersion } from "./Bound.js"
import { type ReceiptReport, reportSize } from "../Store/Receipt.js"
import { type ChunkToken, type Chunks, offsetOf, room } from "../Upload.js"

// Observed reality ------------------------------------------------------------

/** Opaque: whatever names a staging area in the store. */
export type StagingRef = string & Brand.Brand<"StagingRef">
export const StagingRef = Brand.nominal<StagingRef>()

/** A staging area and the tokens of the chunks it holds durably. */
export class Staging extends Data.Class<{ readonly ref: StagingRef; readonly tokens: ReadonlyArray<ChunkToken> }> {}
export const staging = (ref: StagingRef, tokens: ReadonlyArray<ChunkToken>): Staging =>
  new Staging({ ref, tokens: Data.array([...tokens]) })
export const stagingRef = (s: Staging): StagingRef => s.ref

/** Every staging area an observation found. Haskell needs its own list type
 *  for a measure; here it is an array. */
export type Stagings = ReadonlyArray<Staging>
export const refSet = (ss: Stagings): HashSet.HashSet<StagingRef> => HashSet.fromIterable(ss.map(stagingRef))
export const nStagings = (ss: Stagings): Nat => lengthOf(ss)

export type Vouching = Data.TaggedEnum<{
  /** a full-object CRC-64/NVME checksum of the whole object, and its size */
  Vouched: { readonly report: ReceiptReport }
  /** an object exists that the store will never vouch for in that algorithm */
  Unvouchable: {}
  /** an object exists, and the answer can still change without a call from us */
  NotYetVouched: {}
}>
export const Vouching = Data.taggedEnum<Vouching>()

export type ObjectObs = Data.TaggedEnum<{
  NoObject: {}
  HasObject: { readonly version: Version; readonly vouching: Vouching }
}>
export const ObjectObs = Data.taggedEnum<ObjectObs>()

export class Observed extends Data.Class<{ readonly stagings: Stagings; readonly object: ObjectObs }> {}
/** Builds an Observed whose staging list compares structurally under
 *  Equal.equals, which a plain array would not. */
export const observed = (stagings: Stagings, object: ObjectObs): Observed =>
  new Observed({ stagings: Data.array([...stagings]), object })

/** Whether the store has been observed since the last command. */
export type Seen = Data.TaggedEnum<{
  Unseen: {}
  Seen: { readonly observed: Observed }
}>
export const Seen = Data.taggedEnum<Seen>()

/** Type guards come from Effect's $is: a hand-written `x is T` predicate is
 *  a claim the compiler takes on trust, much like a cast. */
export const isSeen = Seen.$is("Seen")

// Measures of an observation --------------------------------------------------

/** 0 no object, 1 vouched, 2 unvouchable, 3 not yet vouched. */
export type ObjTag = 0 | 1 | 2 | 3

export const objTag = (o: ObjectObs): ObjTag =>
  Match.valueTags(o, {
    NoObject: (): ObjTag => 0,
    HasObject: ({ vouching }): ObjTag =>
      Match.valueTags(vouching, {
        Vouched: (): ObjTag => 1,
        Unvouchable: (): ObjTag => 2,
        NotYetVouched: (): ObjTag => 3
      })
  })

export const objVersion = (o: ObjectObs): Option.Option<Version> =>
  Match.valueTags(o, {
    NoObject: () => Option.none<Version>(),
    HasObject: ({ version }) => Option.some(version)
  })

export const objVouchedSize = (o: ObjectObs): Option.Option<Nat> =>
  Match.valueTags(o, {
    NoObject: () => Option.none<Nat>(),
    HasObject: ({ vouching }) =>
      Match.valueTags(vouching, {
        Vouched: ({ report }) => Option.some(reportSize(report)),
        Unvouchable: () => Option.none<Nat>(),
        NotYetVouched: () => Option.none<Nat>()
      })
  })

export const obsObjTag = (o: Observed): ObjTag => objTag(o.object)
export const obsVersion = (o: Observed): Option.Option<Version> => objVersion(o.object)
export const obsVouchedSize = (o: Observed): Option.Option<Nat> => objVouchedSize(o.object)
export const obsRefs = (o: Observed): HashSet.HashSet<StagingRef> => refSet(o.stagings)
export const obsStagings = (o: Observed): Nat => nStagings(o.stagings)

export const seenObjTag = (s: Seen): ObjTag =>
  Match.valueTags(s, { Unseen: (): ObjTag => 0, Seen: ({ observed }) => obsObjTag(observed) })
export const seenVersion = (s: Seen): Option.Option<Version> =>
  Match.valueTags(s, { Unseen: () => Option.none<Version>(), Seen: ({ observed }) => obsVersion(observed) })
export const seenVouchedSize = (s: Seen): Option.Option<Nat> =>
  Match.valueTags(s, { Unseen: () => Option.none<Nat>(), Seen: ({ observed }) => obsVouchedSize(observed) })
export const seenRefs = (s: Seen): HashSet.HashSet<StagingRef> =>
  Match.valueTags(s, { Unseen: () => HashSet.empty<StagingRef>(), Seen: ({ observed }) => obsRefs(observed) })
export const seenStagings = (s: Seen): Nat =>
  Match.valueTags(s, { Unseen: () => Nat(0), Seen: ({ observed }) => obsStagings(observed) })

// Intent ------------------------------------------------------------------------

/** An upload is incomplete until it is explicitly marked complete. The
 *  staging area is the one the producer writes to, once one is adopted. */
export type Assembly = Data.TaggedEnum<{
  Assembling: { readonly staging: Option.Option<StagingRef>; readonly chunks: Chunks }
  Assembled: { readonly staging: StagingRef; readonly chunks: Chunks }
}>
export const Assembly = Data.taggedEnum<Assembly>()

/** What the store should hold when the asset comes to rest. */
export type Goal = Data.TaggedEnum<{
  Keep: { readonly assembly: Assembly }
  Clear: {}
}>
export const Goal = Data.taggedEnum<Goal>()

/** 0 Clear, 1 Keep an assembled object, 2 Keep an assembly in progress. */
export type GoalTag = 0 | 1 | 2

export const goalTag = (g: Goal): GoalTag =>
  Match.valueTags(g, {
    Clear: (): GoalTag => 0,
    Keep: ({ assembly }): GoalTag =>
      Match.valueTags(assembly, { Assembled: (): GoalTag => 1, Assembling: (): GoalTag => 2 })
  })

/** The goal's place in its order, the first component of the convergence
 *  metric. Clear is 0, an assembled object 1, an assembly in progress
 *  2 + room. The tag relations are a property test (test/Types.test.ts). */
export const rank = (g: Goal): Nat =>
  Match.valueTags(g, {
    Clear: () => Nat(0),
    Keep: ({ assembly }) =>
      Match.valueTags(assembly, {
        Assembled: () => Nat(1),
        Assembling: ({ chunks }) => addNat(Nat(2), room(chunks))
      })
  })

/** The assembled length, for an assembled goal. */
export const assembledTotal = (g: Goal): Option.Option<Nat> =>
  Match.valueTags(g, {
    Clear: () => Option.none<Nat>(),
    Keep: ({ assembly }) =>
      Match.valueTags(assembly, {
        Assembled: ({ chunks }) => Option.some(offsetOf(chunks)),
        Assembling: () => Option.none<Nat>()
      })
  })

/** Whether the goal has a staging area adopted. */
export const goalAdopted = (g: Goal): boolean => Option.isSome(goalStaging(g))

/** The staging area the goal's chunks are in, once one is adopted. */
export const goalStaging = (g: Goal): Option.Option<StagingRef> =>
  Match.valueTags(g, {
    Clear: () => Option.none<StagingRef>(),
    Keep: ({ assembly }) =>
      Match.valueTags(assembly, {
        Assembled: ({ staging }) => Option.some(staging),
        Assembling: ({ staging }) => staging
      })
  })

/** The staging area an assembled goal's chunks are in. */
export const assembledRef = (g: Goal): Option.Option<StagingRef> =>
  Match.valueTags(g, {
    Clear: () => Option.none<StagingRef>(),
    Keep: ({ assembly }) =>
      Match.valueTags(assembly, {
        Assembled: ({ staging }) => Option.some(staging),
        Assembling: () => Option.none<StagingRef>()
      })
  })

/** The gap between a goal and what the store holds: how many store commands,
 *  at most, are still needed before the goal's resting state. */
export const gapI = (g: GoalTag, adopted: boolean, rc: boolean, n: Nat, obj: ObjTag): Nat => {
  const one = Nat(1)
  switch (g) {
    case 0:
      return obj !== 0 ? addNat(n, one) : n
    case 2:
      return adopted ? n : n === 0 ? Nat(3) : addNat(n, one)
    case 1:
      return rc ? n : addNat(n, obj !== 0 ? one : Nat(2))
    default: {
      const unreachable: never = g
      return unreachable
    }
  }
}

export type Ending = Data.TaggedEnum<{
  Deleted: {}
  Cancelled: {}
  Failed: { readonly fault: Fault }
}>
export const Ending = Data.taggedEnum<Ending>()

/** Why the asset is going away, once it is. The reconciler never reads it. */
export type Outcome = Data.TaggedEnum<{
  Ongoing: {}
  Ended: { readonly ending: Ending }
}>
export const Outcome = Data.taggedEnum<Outcome>()

export const isEnded = Outcome.$is("Ended")

export type Vouch = Data.TaggedEnum<{
  NoReceipt: {}
  HasReceipt: { readonly bound: Bound }
}>
export const Vouch = Data.taggedEnum<Vouch>()

export const hasReceipt = Vouch.$is("HasReceipt")
export const vouchVersion = (v: Vouch): Option.Option<Version> =>
  Match.valueTags(v, { NoReceipt: () => Option.none<Version>(), HasReceipt: ({ bound }) => Option.some(boundVersion(bound)) })
export const vouchSize = (v: Vouch): Option.Option<Nat> =>
  Match.valueTags(v, { NoReceipt: () => Option.none<Nat>(), HasReceipt: ({ bound }) => Option.some(boundSize(bound)) })

/** A chunk write the core started and hasn't seen reported, with the
 *  wall-clock instant by which the shell has aborted it (A3). */
export class Write extends Data.Class<{ readonly epoch: Int; readonly deadline: Int }> {}

// The asset -------------------------------------------------------------------

type KeepWith<A extends Assembly["_tag"]> = Data.TaggedEnum.Value<Goal, "Keep"> & {
  readonly assembly: Data.TaggedEnum.Value<Assembly, A>
}
export type AssemblingGoal = KeepWith<"Assembling">
export type AssembledGoal = KeepWith<"Assembled">
export type ClearGoal = Data.TaggedEnum.Value<Goal, "Clear">

// Goal.Keep(...) returns the broad Keep variant, whose assembly is any
// Assembly, so its result doesn't fit AssemblingShape or AssembledShape. These
// build the same structural value with the narrow type the shapes need.
export const assemblingGoal = (staging: Option.Option<StagingRef>, chunks: Chunks): AssemblingGoal =>
  Data.struct({ _tag: "Keep", assembly: Assembly.Assembling({ staging, chunks }) })
export const assembledGoal = (staging: StagingRef, chunks: Chunks): AssembledGoal =>
  Data.struct({ _tag: "Keep", assembly: Assembly.Assembled({ staging, chunks }) })

/** The fields no refinement ties to another. */
export interface AssetCommon {
  readonly seen: Seen
  /** {b:Nat | b <= attemptCap}, as a literal union */
  readonly budget: Attempts
  /** {s:Int | s >= 1} */
  readonly backoffAt: PosInt
  readonly authorised: ReadonlyArray<Write>
}

/** The shapes whose refinements the compiler checks on its own:
 *  - the ending is set exactly when the goal is Clear;
 *  - a receipt exists only when the goal isn't an assembly in progress. */
export type AssemblingShape = {
  readonly goal: AssemblingGoal
  readonly outcome: Data.TaggedEnum.Value<Outcome, "Ongoing">
  readonly vouch: Data.TaggedEnum.Value<Vouch, "NoReceipt">
}
export type AssembledShape = {
  readonly goal: AssembledGoal
  readonly outcome: Data.TaggedEnum.Value<Outcome, "Ongoing">
  readonly vouch: Vouch
}
export type ClearShape = {
  readonly goal: ClearGoal
  readonly outcome: Data.TaggedEnum.Value<Outcome, "Ended">
  readonly vouch: Vouch
}
export type AssetShape = AssemblingShape | AssembledShape | ClearShape
export type AssetInput = AssetCommon & AssetShape

/** The inputs for which the type alone carries every refinement: anything
 *  but an assembled goal holding a receipt. */
export type UncheckedInput = AssetCommon &
  (
    | AssemblingShape
    | (AssembledShape & { readonly vouch: Data.TaggedEnum.Value<Vouch, "NoReceipt"> })
    | ClearShape
  )

/** Gives Asset its nominal identity; it holds no data of its own. */
class AssetTag {
  private declare readonly nominal: "Asset"
}

/** One asset. Opaque: only asset, makeAsset and the with* functions below
 *  build one, and they all go through mint. */
export type Asset = AssetTag & AssetInput

/** The one refinement the type can't carry: a receipt held for an assembled
 *  goal has the assembled length. */
export class ReceiptLengthMismatch extends Data.TaggedClass("ReceiptLengthMismatch")<{
  readonly assembled: Nat
  readonly receipt: Nat
}> {}

const mint = <I extends AssetInput>(i: I): AssetTag & I => {
  const a = Object.assign(new AssetTag(), i)
  // Object.freeze's return type is Readonly<T>, which drops the private
  // member and with it the nominal identity, so its result is not used.
  Object.freeze(a)
  return a
}

/** An asset whose refinements the input type already proves. */
export const asset = (i: UncheckedInput): Asset => mint(i)

/** asset(), with the input's shape kept in the result type, so a move from
 *  one shape to another can say in its type which shape it lands in (used by
 *  Client/Core.ts). The same unchecked inputs as asset(). */
export const shapedAsset = <I extends UncheckedInput>(i: I): AssetTag & I => mint(i)

/** The checked constructor, for any shape. Left exactly when a receipt held
 *  for an assembled goal doesn't have the assembled length. */
export const makeAsset = (i: AssetInput): Either.Either<Asset, ReceiptLengthMismatch> => {
  const assembled = assembledTotal(i.goal)
  const receipt = vouchSize(i.vouch)
  if (Option.isSome(assembled) && Option.isSome(receipt) && assembled.value !== receipt.value) {
    return Either.left(new ReceiptLengthMismatch({ assembled: assembled.value, receipt: receipt.value }))
  }
  return Either.right(mint(i))
}

/** The Asset data refinement, as a predicate over what a reader can see.
 *  Tests hold every Asset to it. */
export const assetInvariant = (a: Asset): boolean => {
  const tag = goalTag(a.goal)
  const endedOk = isEnded(a.outcome) === (tag === 0)
  const receiptOk = !hasReceipt(a.vouch) || tag !== 2
  const sizeOk =
    !(hasReceipt(a.vouch) && tag === 1) ||
    Option.getEquivalence((x: Nat, y: Nat) => x === y)(vouchSize(a.vouch), assembledTotal(a.goal))
  const budgetOk = a.budget >= 0 && a.budget <= 5
  return endedOk && receiptOk && sizeOk && budgetOk && a.backoffAt >= 1
}

// The fields below aren't part of any refinement, so replacing one keeps the
// asset valid without a check. The spread keeps the asset's own shape.
export const withSeen = (a: Asset, seen: Seen): Asset => mint({ ...a, seen })
export const withBudget = (a: Asset, budget: Attempts): Asset => mint({ ...a, budget })
export const withBackoffAt = (a: Asset, backoffAt: PosInt): Asset => mint({ ...a, backoffAt })
export const withAuthorised = (a: Asset, authorised: ReadonlyArray<Write>): Asset => mint({ ...a, authorised })

// Decisions ---------------------------------------------------------------------

/** The one command a step may issue. Seal names nothing: the chunks it seals
 *  are always the goal's (K2). Discard and Remove name what was observed, and
 *  Remove can't be built without a version (K5). */
export type Cmd = Data.TaggedEnum<{
  NoCmd: {}
  DoObserve: {}
  DoOpen: {}
  DoSeal: {}
  DoDiscard: { readonly ref: StagingRef }
  DoRemove: { readonly version: Version }
}>
export const Cmd = Data.taggedEnum<Cmd>()

/** 0 none, 1 observe, 2 open, 3 seal, 4 discard, 5 remove. */
export type CmdTag = 0 | 1 | 2 | 3 | 4 | 5

export const cmdTag = (c: Cmd): CmdTag =>
  Match.valueTags(c, {
    NoCmd: (): CmdTag => 0,
    DoObserve: (): CmdTag => 1,
    DoOpen: (): CmdTag => 2,
    DoSeal: (): CmdTag => 3,
    DoDiscard: (): CmdTag => 4,
    DoRemove: (): CmdTag => 5
  })

export const discardRef = (c: Cmd): Option.Option<StagingRef> =>
  c._tag === "DoDiscard" ? Option.some(c.ref) : Option.none()
export const removeVersion = (c: Cmd): Option.Option<Version> =>
  c._tag === "DoRemove" ? Option.some(c.version) : Option.none()

/** maxAttempts in 1..attemptCap and writeDeadline a Nat are field types. */
export class Config extends Data.Class<{
  readonly maxAttempts: MaxAttempts
  readonly backoff: Backoff
  readonly writeDeadline: Nat
}> {}

export class Env extends Data.Class<{ readonly now: Nat; readonly cfg: Config }> {}

/** Which row of the decision table decided. */
export type Row =
  | "R0" | "R1" | "R2" | "R3" | "R4" | "R5" | "R6" | "R7" | "R8" | "R9"
  | "R10" | "R11" | "R12" | "R13" | "R14" | "R15" | "R16" | "R17" | "R18" | "R19"

/** Every row, in order (Haskell's Enum, Bounded). The type below fails to
 *  compile if a row is missing from the list. */
export const allRows = [
  "R0", "R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8", "R9",
  "R10", "R11", "R12", "R13", "R14", "R15", "R16", "R17", "R18", "R19"
] satisfies ReadonlyArray<Row>
type MissingRows = Exclude<Row, (typeof allRows)[number]>
export const allRowsComplete: [MissingRows] extends [never] ? true : MissingRows = true

/** The resting rows: waiting for the producer (R3), converged (R14, R18), or
 *  waiting out a write deadline (R19). A table keyed by Row, so a new row
 *  doesn't compile until it says whether it rests. */
const fixedRows: { readonly [R in Row]: boolean } = {
  R0: false, R1: false, R2: false, R3: true, R4: false, R5: false, R6: false,
  R7: false, R8: false, R9: false, R10: false, R11: false, R12: false, R13: false,
  R14: true, R15: false, R16: false, R17: false, R18: true, R19: true
}
export const isFixedRow = (r: Row): boolean => fixedRows[r]

/** The asset after the step, the command to issue, how many seconds to wait
 *  before issuing it, whether an operator has to be told, and the row. */
export class Decision extends Data.Class<{
  readonly next: Asset
  readonly command: Cmd
  readonly waitFor: Nat
  readonly alarm: boolean
  readonly row: Row
}> {}

// AIP-216 -------------------------------------------------------------------------

/** The State a client sees. Never stored, only computed by stateOf. */
export type State = Data.TaggedEnum<{
  CREATING: {}
  ACTIVE: {}
  FAILED: { readonly fault: Fault }
  CANCELLED: {}
  DELETING: {}
  DELETED: {}
}>
export const State = Data.taggedEnum<State>()

export const isActiveState = (s: State): boolean => s._tag === "ACTIVE"

const heldNothing = (s: Seen): boolean =>
  Match.valueTags(s, {
    Unseen: () => false,
    Seen: ({ observed }) => observed.stagings.length === 0 && observed.object._tag === "NoObject"
  })

/** K6: ACTIVE exactly when a receipt is held and the goal isn't Clear (a
 *  property test). A deleted asset is DELETED only once the store was seen
 *  holding nothing and no write it started is still unreported. */
export const stateOf = (a: Asset): State =>
  Match.valueTags(a.goal, {
    Keep: () => (hasReceipt(a.vouch) ? State.ACTIVE() : State.CREATING()),
    Clear: () =>
      Match.valueTags(a.outcome, {
        Ended: ({ ending }) =>
          Match.valueTags(ending, {
            Failed: ({ fault }) => State.FAILED({ fault }),
            Cancelled: () => State.CANCELLED(),
            Deleted: () => (heldNothing(a.seen) && a.authorised.length === 0 ? State.DELETED() : State.DELETING())
          }),
        // The Asset type rules this out (Clear goes with Ended), but reading
        // a.goal and a.outcome separately doesn't narrow one by the other.
        Ongoing: () => State.DELETING()
      })
  })
