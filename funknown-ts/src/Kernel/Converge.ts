// Funknown.Kernel.Converge: convergence against every environment the store
// contract allows.
//
// A run alternates the reconciler with an adversary's script of moves, which
// may be infinite (any Iterable). The adversary may lose a command or an
// observation out of a finite drop allowance, land a write the core started
// and never saw reported, let such a write's deadline pass (A3), or let the
// producer or a client move the goal. A move that doesn't apply is an honest
// round instead. `converge` stops when a round rests (R3, R14, R18, R19).
//
// LiquidHaskell accepts Haskell's `converge` by its termination checker,
// with the lexicographic metric
//
//   (rank of the goal, drop allowance, budget, unreported writes, gap, not yet observed)
//
// TypeScript has no termination checker, so the loop below checks that
// metric itself: every iteration that doesn't rest has to make it strictly
// smaller, or `converge` stops and answers NoProgress. Every component is a
// Nat, so the order is well-founded and the loop can't run forever. That the
// check never fires, so every run reaches a resting row, is a property test
// (test/Converge.test.ts), not a proof.
import { Array as Arr, Data, Either, Match, Option, Schema } from "effect"
import { type Attempts } from "../Http/Retry.js"
import { type Int, Nat, PosInt, lengthOf } from "../Num.js"
import { Chunk, type ChunkToken, appendChunk } from "../Upload.js"
import { Model, type Synced, forgetting, gapM, keepingView, round } from "./Model.js"
import { reconcile } from "./Reconcile.js"
import {
  type Asset,
  type Ending,
  type Env,
  type Row,
  Outcome,
  assembledGoal,
  assemblingGoal,
  asset,
  cmdTag,
  Goal,
  isSeen,
  observed,
  rank,
  staging,
  withAuthorised
} from "./Types.js"

/** What the adversary may do instead of an honest round. */
export type Move = Data.TaggedEnum<{
  /** the command or observation of this round is lost */
  Drop: {}
  /** an unreported write lands, and a staging area reappears */
  LateWrite: {}
  /** an unreported write passes its deadline; the shell aborted it */
  Lapse: {}
  /** the producer's next chunk is durable */
  Append: { readonly token: ChunkToken; readonly n: Int }
  /** the producer marks the assembly complete */
  Complete: {}
  /** a cancel, a DELETE, or expiry clears the goal */
  Abandon: { readonly ending: Ending }
}>
export const Move = Data.taggedEnum<Move>()

/** The resting rows, as a type. Haskell's `runRow :: {r:Row | isFixedRow r}`
 *  becomes this literal union, and Effect's Schema generates the guard, so
 *  no hand-written `x is T` predicate is involved. A test checks it agrees
 *  with isFixedRow on every row. */
export const FixedRow = Schema.Literal("R3", "R14", "R18", "R19")
export type FixedRow = typeof FixedRow.Type
export const isResting = Schema.is(FixedRow)

/** Where a run came to rest, and after how many iterations. */
export class Run extends Data.Class<{
  readonly asset: Asset
  readonly model: Model
  readonly row: FixedRow
  readonly rounds: Nat
}> {}

/** The termination metric. Every component is a Nat (or a literal union of
 *  Nats) by its type, so non-negativity is the brand's run-time check. */
export type Metric = readonly [
  rank: Nat,
  allowance: Nat,
  budget: Attempts,
  unreported: Nat,
  gap: Nat,
  unseen: 0 | 1
]

/** 1 until the store has been observed, as the metric's last component. */
const unseenBit = (seenYet: boolean): 0 | 1 => (seenYet ? 0 : 1)

export const metric = (s: Synced, d: Nat): Metric => [
  rank(s.asset.goal),
  d,
  s.asset.budget,
  lengthOf(s.asset.authorised),
  gapM(s.asset, s.model),
  unseenBit(isSeen(s.asset.seen))
]

/** Smaller A M D B N E: `after` is lexicographically below `before`. */
export const smaller = (after: Metric, before: Metric): boolean =>
  Option.match(
    Arr.findFirst(Arr.zip(after, before), ([x, y]) => x !== y),
    { onNone: () => false, onSome: ([x, y]) => x < y }
  )

// The adversary's moves on the asset and the model ----------------------------------

/** The state after the adversary's move. */
export class Next extends Data.Class<{ readonly synced: Synced; readonly allowance: Nat }> {}

/** A late write lands: a staging area with the store's next name shows up. */
const reappear = (m: Model): Model =>
  new Model({
    obs: observed([staging(m.fresh, []), ...m.obs.stagings], m.obs.object),
    fresh: m.fresh,
    version: m.version,
    vouching: m.vouching
  })

/** The producer's next chunk, when the assembly accepts it: the goal's rank
 *  drops by one, because the cap leaves room for one fewer chunk.
 *  appendChunk is present exactly when canAppend holds, so it is the check. */
const appended = (a: Asset, token: ChunkToken, n: Int): Option.Option<Asset> => {
  const g = a.goal
  if (g._tag !== "Keep" || g.assembly._tag !== "Assembling") return Option.none()
  const { staging: r, chunks } = g.assembly
  // An assembly in progress is Ongoing with no receipt, by the Asset type;
  // TypeScript doesn't narrow a.outcome and a.vouch by a.goal, so they are
  // narrowed here on their own, and the other branch is unreachable.
  if (a.outcome._tag !== "Ongoing" || a.vouch._tag !== "NoReceipt") return Option.none()
  const outcome = a.outcome
  const vouch = a.vouch
  return Option.map(
    Option.flatMap(PosInt.option(n), (cbytes) => appendChunk(chunks, new Chunk({ cbytes, ctoken: token }))),
    (c) =>
      asset({
        goal: assemblingGoal(r, c),
        outcome,
        vouch,
        seen: a.seen,
        budget: a.budget,
        backoffAt: a.backoffAt,
        authorised: a.authorised
      })
  )
}

/** The producer completes an assembly that has a staging area. */
const completed = (a: Asset): Option.Option<Asset> => {
  const g = a.goal
  if (g._tag !== "Keep" || g.assembly._tag !== "Assembling") return Option.none()
  if (a.outcome._tag !== "Ongoing" || a.vouch._tag !== "NoReceipt") return Option.none()
  const outcome = a.outcome
  const vouch = a.vouch
  const { chunks } = g.assembly
  return Option.map(g.assembly.staging, (r) =>
    asset({
      goal: assembledGoal(r, chunks),
      outcome,
      vouch,
      seen: a.seen,
      budget: a.budget,
      backoffAt: a.backoffAt,
      authorised: a.authorised
    })
  )
}

/** A cancel, a DELETE or expiry clears a goal that still keeps the asset. */
const abandoned = (a: Asset, ending: Ending): Option.Option<Asset> =>
  a.goal._tag === "Keep"
    ? Option.some(
        asset({
          goal: Goal.Clear(),
          outcome: Outcome.Ended({ ending }),
          vouch: a.vouch,
          seen: a.seen,
          budget: a.budget,
          backoffAt: a.backoffAt,
          authorised: a.authorised
        })
      )
    : Option.none()

/** The adversary's move, if it applies; each one lowers the metric (a
 *  property test) and leaves the pair Synced (a type). */
export const adversary = (env: Env, s: Synced, d: Nat, move: Move): Option.Option<Next> => {
  const a = s.asset
  const m = s.model
  const tail = a.authorised.slice(1)
  const hasUnreported = a.authorised.length > 0
  return Match.valueTags(move, {
    // Only a round that issues something can lose it, and only while the
    // allowance lasts. K0 says the decided asset's observation is already
    // stale after a command; the drop makes that explicit.
    Drop: () => {
      const dec = reconcile(env, a)
      return d > 0 && cmdTag(dec.command) >= 1
        ? Option.some(new Next({ synced: forgetting(dec.next, m), allowance: Nat(d - 1) }))
        : Option.none()
    },
    LateWrite: () =>
      hasUnreported
        ? Option.some(new Next({ synced: forgetting(withAuthorised(a, tail), reappear(m)), allowance: d }))
        : Option.none(),
    Lapse: () =>
      hasUnreported
        ? Option.some(new Next({ synced: keepingView(s, withAuthorised(a, tail)), allowance: d }))
        : Option.none(),
    Append: ({ token, n }) =>
      Option.map(appended(a, token, n), (b) => new Next({ synced: keepingView(s, b), allowance: d })),
    Complete: () => Option.map(completed(a), (b) => new Next({ synced: keepingView(s, b), allowance: d })),
    Abandon: ({ ending }) =>
      Option.map(abandoned(a, ending), (b) => new Next({ synced: keepingView(s, b), allowance: d }))
  })
}

// One iteration, and the run --------------------------------------------------------

/** What one iteration of `converge` did. */
export type Advanced = Data.TaggedEnum<{
  /** the adversary's move applied */
  Moved: { readonly next: Next }
  /** an honest round that didn't rest */
  Rounded: { readonly next: Next; readonly row: Row }
  /** an honest round that rested */
  Rested: { readonly synced: Synced; readonly row: FixedRow }
}>
export const Advanced = Data.taggedEnum<Advanced>()

/** One iteration: the move at the head of the script if it applies,
 *  otherwise an honest round (which consumes the move all the same). */
export const advance = (env: Env, s: Synced, d: Nat, move: Option.Option<Move>): Advanced =>
  Option.match(
    Option.flatMap(move, (mv) => adversary(env, s, d, mv)),
    {
      onSome: (next) => Advanced.Moved({ next }),
      onNone: () => {
        const r = round(env, s)
        const row = r.row
        return isResting(row)
          ? Advanced.Rested({ synced: r.synced, row })
          : Advanced.Rounded({ next: new Next({ synced: r.synced, allowance: d }), row })
      }
    }
  )

/** The loop's own termination check failed: an iteration that didn't rest
 *  left the metric where it was, or raised it. */
export class NoProgress extends Data.TaggedClass("NoProgress")<{
  readonly before: Metric
  readonly after: Metric
  readonly move: Option.Option<Move>
  readonly rounds: Nat
}> {}

/** Run the reconciler against the store and the adversary's script until a
 *  round rests. The script may be infinite. */
export const converge = (
  env: Env,
  start: Synced,
  allowance: Nat,
  moves: Iterable<Move, unknown, undefined>
): Either.Either<Run, NoProgress> => {
  const script = moves[Symbol.iterator]()
  let s = start
  let d = allowance
  let rounds = 0
  for (;;) {
    const head = script.next()
    const move = head.done === true ? Option.none<Move>() : Option.some(head.value)
    const step = advance(env, s, d, move)
    rounds += 1
    if (step._tag === "Rested") {
      return Either.right(
        new Run({ asset: step.synced.asset, model: step.synced.model, row: step.row, rounds: Nat(rounds) })
      )
    }
    const before = metric(s, d)
    const after = metric(step.next.synced, step.next.allowance)
    if (!smaller(after, before)) {
      return Either.left(new NoProgress({ before, after, move, rounds: Nat(rounds) }))
    }
    s = step.next.synced
    d = step.next.allowance
  }
}
