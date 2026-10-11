// Properties for Funknown.Kernel.Converge. LiquidHaskell proves termination
// with the six-part lexicographic metric; here the same three facts are
// checked over generated starting states and long adversarial scripts:
//   - every component of the metric is a natural number;
//   - every iteration that doesn't rest makes the metric strictly smaller;
//   - every run reaches a resting row, finite script or infinite.
import assert from "node:assert/strict"
import { test } from "node:test"
import { Either, FastCheck as fc, Option } from "effect"
import { Nat } from "../src/Num.js"
import {
  type Advanced,
  type Move,
  adversary,
  advance,
  converge,
  isResting,
  metric,
  smaller
} from "../src/Kernel/Converge.js"
import type { Synced } from "../src/Kernel/Model.js"
import { type Env, type Row, allRows, isFixedRow } from "../src/Kernel/Types.js"
import { envArb, natArb } from "./arb.js"
import { forever, moveArb, scriptArb, syncedArb } from "./arbModel.js"
import { coherentSpec, lexLess, metricSpec } from "./specModel.js"

const isNatural = (x: number): boolean => Number.isSafeInteger(x) && x >= 0

test("the resting-row type agrees with isFixedRow on every row", () => {
  for (const r of allRows) assert.equal(isResting(r), isFixedRow(r), r)
})

type Seen = { moves: Set<Move["_tag"]>; rests: Set<Row>; longest: number }
type Driven = { readonly problem: string | undefined; readonly played: ReadonlyArray<Move>; readonly iterations: number }

/** Drives a run one iteration at a time, independently of converge's own
 *  check, and reports the first iteration that breaks a claim. `choose`
 *  supplies each iteration's move and may look at the state, so an adaptive
 *  adversary can be written as one. */
const drive = (
  env: Env,
  start: Synced,
  allowance: Nat,
  choose: (s: Synced, d: Nat, i: number) => Option.Option<Move>,
  seen: Seen
): Driven => {
  const played: Array<Move> = []
  let s = start
  let d = allowance
  // A generous bound, only so that a broken metric fails the test instead of
  // hanging it.
  for (let i = 0; i < 100000; i++) {
    const move = choose(s, d, i)
    if (Option.isSome(move)) played.push(move.value)
    const before = metricSpec(s, d)
    const fail = (problem: string): Driven => ({ problem, played, iterations: i + 1 })
    if (!before.every(isNatural)) return fail(`metric not natural: ${before.join(",")}`)
    const step: Advanced = advance(env, s, d, move)
    if (step._tag === "Rested") {
      seen.rests.add(step.row)
      seen.longest = Math.max(seen.longest, i + 1)
      return { problem: undefined, played, iterations: i + 1 }
    }
    if (step._tag === "Moved" && Option.isSome(move)) seen.moves.add(move.value._tag)
    const after = metricSpec(step.next.synced, step.next.allowance)
    if (!after.every(isNatural)) return fail(`metric not natural: ${after.join(",")}`)
    if (!coherentSpec(step.next.synced.asset, step.next.synced.model)) return fail(`${step._tag}: the pair is not Coherent`)
    if (!lexLess(after, before)) {
      const what = step._tag === "Rounded" ? `round ${step.row}` : `move ${Option.getOrThrow(move)._tag}`
      return fail(`${what} did not lower the metric: ${before.join(",")} -> ${after.join(",")}`)
    }
    s = step.next.synced
    d = step.next.allowance
  }
  return { problem: "no resting row within 100000 iterations", played, iterations: 100000 }
}

const fromScript = (moves: Iterable<Move, unknown, undefined>) => {
  const it = moves[Symbol.iterator]()
  return (): Option.Option<Move> => {
    const head = it.next()
    return head.done === true ? Option.none<Move>() : Option.some(head.value)
  }
}

/** A greedy adversary: each iteration it plays the first of its candidate
 *  moves (rotated by a generated pick) that applies, so the store is held
 *  away from rest for as long as the allowance, the writes and the goal
 *  allow. When none applies it plays the first candidate, which then is an
 *  honest round. */
const greedy =
  (env: Env, candidates: ReadonlyArray<Move>, picks: ReadonlyArray<number>) =>
  (s: Synced, d: Nat, i: number): Option.Option<Move> => {
    const k = picks.length === 0 ? 0 : (picks[i % picks.length] ?? 0)
    const rotated = [...candidates.slice(k % candidates.length), ...candidates.slice(0, k % candidates.length)]
    const applies = rotated.find((mv) => Option.isSome(adversary(env, s, d, mv)))
    return Option.fromNullable(applies ?? candidates[0])
  }

const runStats = (): Seen => ({ moves: new Set(), rests: new Set(), longest: 0 })
const allMoves: ReadonlyArray<Move["_tag"]> = ["Drop", "LateWrite", "Lapse", "Append", "Complete", "Abandon"]

test("the metric is natural and strictly decreases on every iteration that doesn't rest (fixed scripts)", () => {
  const seen = runStats()
  fc.assert(
    fc.property(envArb, syncedArb, natArb(20), scriptArb, fc.boolean(), (env, s, d, script, cyclic) => {
      assert.equal(drive(env, s, d, fromScript(cyclic ? forever(script) : script), seen).problem, undefined)
      return true
    }),
    { numRuns: 1000 }
  )
  assert.deepEqual(allRows.filter((r) => isResting(r) && !seen.rests.has(r)), [], "every resting row reached")
})

test("the metric strictly decreases against a greedy adversary, and converge agrees with the replayed script", () => {
  const seen = runStats()
  fc.assert(
    fc.property(
      envArb,
      syncedArb,
      natArb(30),
      fc.array(moveArb, { minLength: 1, maxLength: 12 }),
      fc.array(fc.nat(11), { maxLength: 40 }),
      (env, s, d, candidates, picks) => {
        const driven = drive(env, s, d, greedy(env, candidates, picks), seen)
        assert.equal(driven.problem, undefined)
        // The same moves, as a plain script, through converge itself.
        const run = converge(env, s, d, driven.played)
        return Either.isRight(run) && run.right.rounds === driven.iterations
      }
    ),
    { numRuns: 1000 }
  )
  // Vacuity checks: every kind of move applied, and some runs were long.
  assert.deepEqual(allMoves.filter((m) => !seen.moves.has(m)), [], "every move applied at least once")
  assert.ok(seen.longest >= 30, `the longest greedy run took ${seen.longest} iterations`)
})

test("converge reaches a resting row for every start and every script, finite or infinite", () => {
  fc.assert(
    fc.property(envArb, syncedArb, natArb(20), scriptArb, fc.boolean(), (env, s, d, script, cyclic) => {
      const result = converge(env, s, d, cyclic ? forever(script) : script)
      const stuck = Either.match(result, {
        onLeft: (e) => `no progress after ${e.rounds} rounds: ${e.before.join(",")} -> ${e.after.join(",")}`,
        onRight: () => undefined
      })
      assert.equal(stuck, undefined)
      return Either.isRight(result) && isFixedRow(result.right.row) && result.right.rounds >= 1
    }),
    { numRuns: 1500 }
  )
})

test("the code's metric and order agree with the transcribed ones", () => {
  fc.assert(
    fc.property(syncedArb, natArb(20), syncedArb, natArb(20), (s, d, t, e) => {
      const m = metric(s, d)
      return (
        m.length === 6 &&
        m.every((x, i) => x === metricSpec(s, d)[i]) &&
        smaller(metric(t, e), m) === lexLess(metricSpec(t, e), metricSpec(s, d))
      )
    }),
    { numRuns: 1000 }
  )
})

test("an empty script is the honest store alone, and still converges", () => {
  fc.assert(
    fc.property(envArb, syncedArb, (env, s) => Either.isRight(converge(env, s, Nat(0), []))),
    { numRuns: 1000 }
  )
})
