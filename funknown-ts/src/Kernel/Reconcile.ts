// Funknown.Kernel.Reconcile: the level-triggered reconciler. It compares what
// an asset should become with what the store was last seen to hold, and
// decides the one command that closes the gap. Rows R0 to R19 of
// docs/design/kernel.md.
//
// How the guards' exhaustiveness and exclusivity show up here. The Haskell
// reaches each row by one path through nested case analysis, and so does this
// module: `decide` is a tree of splits, and every split is Match.valueTags, a
// Match.value pipeline ending in Match.exhaustive, an Option.match, an
// Either.match, or a two-way if. tsc refuses a split with a case missing, so
// every input reaches a leaf (exhaustive), and a tree sends each input down
// one path, so it reaches exactly one leaf (exclusive). Every leaf carries its
// row as a literal type, so `RowsDecided` below is the union of the rows some
// leaf decides, and `everyRowDecided` fails to compile if a row of the table
// has no leaf. What the types can't show is that each leaf is the row the
// table's guard names; that is K7, the exhaustive guard test in
// test/Guards.test.ts.
//
// The Asset type is a union of three shapes (assembling, assembled, clear).
// TypeScript's own narrowing can't split it by a.goal._tag, because the
// discriminant is nested. Effect's Match.when with a nested pattern can, and
// Match.exhaustive checks that the three patterns cover the union, but the
// value it hands over is typed as a structural copy of the shape, without the
// Asset's nominal member. So each branch gets two names for the one value:
// `a`, the Asset, for the rows that keep it (rest, issue), and `v`, its shape,
// for the rows that build a new asset through asset() or makeAsset(), which
// take shapes. The shape is where the LiquidHaskell preconditions of failWith
// (goal not Clear), adopt (assembling, so no receipt) and clearing (Clear)
// went. failWith's other precondition, a store fault, is StoreFault.
//
// The safety claims K0 to K13 and Prog, which LiquidHaskell states once in
// the Step type, are predicates in Kernel/ReconcileClaims.ts and FastCheck
// properties in test/Reconcile.test.ts. They are tested, not enforced.
import { Either, Match, Option } from "effect"
import { Fault } from "../Fault.js"
import { nextWait, spendAttempt } from "../Http/Retry.js"
import { type Int, Nat, PosInt } from "../Num.js"
import type { ReceiptReport } from "../Store/Receipt.js"
import { type Chunks, chunkList, offsetOf } from "../Upload.js"
import { type Version, bind, boundVersion } from "./Bound.js"
import {
  type AssembledShape,
  type AssemblingShape,
  type Asset,
  type AssetCommon,
  type ClearShape,
  Cmd,
  Decision,
  Ending,
  type Env,
  Goal,
  type ObjectObs,
  Outcome,
  type Row,
  Seen,
  type StagingRef,
  type Stagings,
  Vouch,
  type Write,
  asset,
  assemblingGoal,
  makeAsset,
  withBackoffAt,
  withBudget,
  withSeen
} from "./Types.js"

// The asset's shape, by its goal ----------------------------------------------------

export type ClearView = AssetCommon & ClearShape
export type AssemblingView = AssetCommon & AssemblingShape
export type AssembledView = AssetCommon & AssembledShape
/** A goal that keeps the asset: LiquidHaskell's {a | goalTag (goal a) /= 0}. */
export type KeepView = AssemblingView | AssembledView

/** The five faults an observation of the store can justify, the ones
 *  LiquidHaskell's storeFault numbers 1 to 5: {f:Fault | storeFault f /= 0}.
 *  The rest name a call's result or a client-side check, and the reconciler
 *  never sets them. */
export type StoreFault = Fault & {
  readonly _tag: "StateLost" | "Contradiction" | "SizeMismatch" | "ObjectWithoutReceipt" | "Unavailable"
}

/** The commands that touch the store: LiquidHaskell's {c | cmdTag c >= 2}. */
export type StoreCmd = Cmd & { readonly _tag: "DoOpen" | "DoSeal" | "DoDiscard" | "DoRemove" }

/** Whether the outcome is a failure (Haskell's isFailed measure). */
export const isFailed = (o: Outcome): boolean =>
  Match.valueTags(o, {
    Ongoing: () => false,
    Ended: ({ ending }) => ending._tag === "Failed"
  })

// Looking things up in an observation --------------------------------------------
//
// Haskell's Found is Option here. Their postconditions (the ref found is
// listed, firstOther's isn't r, listed is membership, holds implies listed)
// are properties in test/Reconcile.test.ts.

/** The first staging area listed. */
export const firstRef = (ss: Stagings): Option.Option<StagingRef> =>
  Option.map(Option.fromNullable(ss[0]), (s) => s.ref)

/** The first staging area listed that isn't r. */
export const firstOther = (r: StagingRef, ss: Stagings): Option.Option<StagingRef> =>
  Option.map(Option.fromNullable(ss.find((s) => s.ref !== r)), (s) => s.ref)

/** Whether staging area r is listed. */
export const listed = (r: StagingRef, ss: Stagings): boolean => ss.some((s) => s.ref === r)

/** Whether staging area r is listed and durably holds every chunk of c,
 *  matched by token, so a late duplicate write can't stand in for a chunk the
 *  core acknowledged. As in Haskell, the first listing of r decides. */
export const holds = (r: StagingRef, c: Chunks, ss: Stagings): boolean => {
  const s = ss.find((st) => st.ref === r)
  return s !== undefined && chunkList(c).every((ch) => s.tokens.includes(ch.ctoken))
}

/** Seconds until the last unreported write's deadline, or 0 when every write
 *  has reported or passed its deadline (A3). */
export const pending = (now: Int, ws: ReadonlyArray<Write>): Nat =>
  Nat(ws.reduce((m, w) => Math.max(m, w.deadline > now ? w.deadline - now : 0), 0))

// Leaves -----------------------------------------------------------------------------
//
// issue, rest, failWith and adopt are exported only so controls/compile can
// check their parameter types; `reconcile` is the module's interface.

/** A decision, with its row as a literal type so the rows decided can be
 *  counted at the type level. The row is written once and used for both. */
export interface Leaf<R extends Row> {
  readonly row: R
  readonly decision: Decision
}

const leaf = <R extends Row>(row: R, next: Asset, command: Cmd, waitFor: Nat, alarm: boolean): Leaf<R> => ({
  row,
  decision: new Decision({ next, command, waitFor, alarm, row })
})

const zero = Nat(0)

/** The asset with its observation marked stale. */
const stale = (a: Asset): Asset => withSeen(a, Seen.Unseen())

/** Issue a store command; the observation is stale after it. */
export const issue = <R extends Row>(row: R, a: Asset, c: StoreCmd): Leaf<R> => leaf(row, stale(a), c, zero, false)

/** Nothing to do: the asset is unchanged and nothing is issued. */
export const rest = <R extends Row>(row: R, a: Asset): Leaf<R> => leaf(row, a, Cmd.NoCmd(), zero, false)

/** The goal can't be reached: clear it, as Failed. No command yet; the next
 *  step, on the same observation, starts the cleanup (R16, R17). Only a goal
 *  that keeps the asset can fail, and only with a store fault, which the
 *  parameter types say. */
export const failWith = <R extends Row>(row: R, v: KeepView, fault: StoreFault): Leaf<R> =>
  leaf(
    row,
    asset({ ...v, goal: Goal.Clear(), outcome: Outcome.Ended({ ending: Ending.Failed({ fault }) }) }),
    Cmd.NoCmd(),
    zero,
    true
  )

// The rows ---------------------------------------------------------------------------

/** R0: nothing is decided before the store has been observed. */
const observeNow = (a: Asset): Leaf<"R0"> => leaf("R0", a, Cmd.DoObserve(), zero, false)

/** R2: record which staging area the producer's chunks go to. The goal's kind,
 *  rank and chunks don't change. Haskell needs a fallback equation for an
 *  asset of the wrong shape; the parameter type rules that out here. */
export const adopt = (v: AssemblingView, r: StagingRef): Leaf<"R2"> =>
  leaf("R2", asset({ ...v, goal: assemblingGoal(Option.some(r), v.goal.assembly.chunks) }), Cmd.NoCmd(), zero, false)

/** R9 and R10: the store vouched for the assembled object. bind checks the
 *  vouched size against the assembled length, and makeAsset checks it again.
 *  LiquidHaskell proves the second check can't fail once the first passed;
 *  TypeScript can't see that. Either Left means the vouched size isn't the
 *  assembled length, which is R10's guard, so both go to R10. */
const vouched = (v: AssembledView, ver: Version, rep: ReceiptReport): Leaf<"R9"> | Leaf<"R10"> =>
  Either.match(
    Either.flatMap(bind(offsetOf(v.goal.assembly.chunks), ver, rep), (bound) =>
      makeAsset({ ...v, vouch: Vouch.HasReceipt({ bound }) })
    ),
    {
      onRight: (next) => leaf("R9", next, Cmd.NoCmd(), zero, false),
      onLeft: () => failWith("R10", v, Fault.SizeMismatch())
    }
  )

/** R12: the store holds the object but can't vouch yet. Spend one attempt and
 *  observe again after backoff (R SS:GRFC-A6-Backoff), or fail when the
 *  budget is spent. */
const spend = (env: Env, a: Asset, v: AssembledView): Leaf<"R12"> =>
  Option.match(spendAttempt(a.budget), {
    onNone: () => failWith("R12", v, Fault.Unavailable()),
    onSome: (budget) => {
      const w = nextWait(env.cfg.backoff, Option.none(), a.backoffAt)
      return leaf("R12", withBackoffAt(withBudget(stale(a), budget), w.nextStep), Cmd.DoObserve(), w.waitFor, false)
    }
  })

/** R1 to R6, for an assembly in progress. */
const assembling = (a: Asset, v: AssemblingView, ss: Stagings, obj: ObjectObs) =>
  Match.valueTags(obj, {
    HasObject: () => failWith("R6", v, Fault.Contradiction()),
    NoObject: () =>
      Option.match(v.goal.assembly.staging, {
        onNone: () =>
          Option.match(firstRef(ss), {
            onNone: () => issue("R1", a, Cmd.DoOpen()),
            onSome: (r) => adopt(v, r)
          }),
        onSome: (r) =>
          listed(r, ss)
            ? Option.match(firstOther(r, ss), {
                onNone: () => rest("R3", a),
                onSome: (other) => issue("R4", a, Cmd.DoDiscard({ ref: other }))
              })
            : failWith("R5", v, Fault.StateLost())
      })
  })

/** R4 and R7 to R15, for an assembled goal. R8 is checked before R4: a missing
 *  chunk fails the asset whatever else is listed, so R4 only ever sees an area
 *  that holds every chunk, and R4 in turn comes before R7. */
const assembled = (env: Env, a: Asset, v: AssembledView, ss: Stagings, obj: ObjectObs) => {
  const { staging: r, chunks: c } = v.goal.assembly
  return Match.valueTags(v.vouch, {
    NoReceipt: () =>
      Match.valueTags(obj, {
        NoObject: () =>
          !holds(r, c, ss)
            ? failWith("R8", v, Fault.StateLost())
            : Option.match(firstOther(r, ss), {
                onSome: (other) => issue("R4", a, Cmd.DoDiscard({ ref: other })),
                onNone: () => issue("R7", a, Cmd.DoSeal())
              }),
        HasObject: ({ version, vouching }) =>
          Match.valueTags(vouching, {
            Vouched: ({ report }) => vouched(v, version, report),
            Unvouchable: () => failWith("R11", v, Fault.ObjectWithoutReceipt()),
            NotYetVouched: () => spend(env, a, v)
          })
      }),
    HasReceipt: ({ bound }) =>
      obj._tag === "HasObject" && obj.version === boundVersion(bound)
        ? Option.match(firstRef(ss), {
            onSome: (r2) => issue("R13", a, Cmd.DoDiscard({ ref: r2 })),
            onNone: () => rest("R14", a)
          })
        : failWith("R15", v, Fault.StateLost())
  })
}

/** R16 to R19: the goal is Clear, so everything held goes, staging areas
 *  first, then the object; then the asset waits out the writes it started. */
const clearing = (env: Env, a: Asset, v: ClearView, ss: Stagings, obj: ObjectObs) =>
  Option.match(firstRef(ss), {
    onSome: (r) => issue("R16", a, Cmd.DoDiscard({ ref: r })),
    onNone: () =>
      Match.valueTags(obj, {
        HasObject: ({ version }) => issue("R17", a, Cmd.DoRemove({ version })),
        NoObject: () =>
          Option.match(PosInt.option(pending(env.now, v.authorised)), {
            onNone: () => rest("R18", a),
            onSome: (d) => leaf("R19", stale(a), Cmd.DoObserve(), d, false)
          })
      })
  })

/** The decision tree, returning the leaf it reached. */
export const decide = (env: Env, a: Asset) =>
  Match.valueTags(a.seen, {
    Unseen: () => observeNow(a),
    Seen: ({ observed: { stagings, object } }) =>
      Match.value(a).pipe(
        Match.when({ goal: { _tag: "Clear" } }, (v) => clearing(env, a, v, stagings, object)),
        Match.when({ goal: { assembly: { _tag: "Assembling" } } }, (v) => assembling(a, v, stagings, object)),
        Match.when({ goal: { assembly: { _tag: "Assembled" } } }, (v) => assembled(env, a, v, stagings, object)),
        Match.exhaustive
      )
  })

/** The rows some leaf of `decide` decides. */
export type RowsDecided = ReturnType<typeof decide>["row"]
type Undecided = Exclude<Row, RowsDecided>
/** Compiles only if every row of the table has a leaf. */
export const everyRowDecided: [Undecided] extends [never] ? true : Undecided = true

/** One step of the reconciler. */
export const reconcile = (env: Env, a: Asset): Decision => decide(env, a).decision
