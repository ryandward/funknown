// The Model and Converge specs, transcribed from the LiquidHaskell
// predicates apart from the code, so a mutant of the code can't move the
// bar its tests hold it to.
import { Equal } from "effect"
import type { Model, Synced } from "../src/Kernel/Model.js"
import {
  type Asset,
  gapI,
  goalAdopted,
  goalTag,
  hasReceipt,
  isSeen,
  obsObjTag,
  obsRefs,
  obsStagings,
  obsVersion,
  rank,
  seenObjTag,
  seenRefs,
  seenStagings,
  seenVersion
} from "../src/Kernel/Types.js"

/** Coherent A M */
export const coherentSpec = (a: Asset, m: Model): boolean =>
  !isSeen(a.seen) ||
  (seenStagings(a.seen) === obsStagings(m.obs) &&
    seenObjTag(a.seen) === obsObjTag(m.obs) &&
    Equal.equals(seenRefs(a.seen), obsRefs(m.obs)) &&
    Equal.equals(seenVersion(a.seen), obsVersion(m.obs)))

/** GapM A M (GapA in Converge) */
export const gapSpec = (a: Asset, m: Model): number =>
  gapI(goalTag(a.goal), goalAdopted(a.goal), hasReceipt(a.vouch), obsStagings(m.obs), obsObjTag(m.obs))

/** Lower A M B N: the progress lemma's order. */
export const lowerSpec = (a: Asset, m: Model, b: Asset, n: Model): boolean =>
  rank(b.goal) < rank(a.goal) ||
  (rank(b.goal) === rank(a.goal) && b.budget < a.budget) ||
  (rank(b.goal) === rank(a.goal) && b.budget === a.budget && gapSpec(b, n) < gapSpec(a, m)) ||
  (rank(b.goal) === rank(a.goal) &&
    b.budget === a.budget &&
    gapSpec(b, n) === gapSpec(a, m) &&
    !isSeen(a.seen) &&
    isSeen(b.seen))

/** converge's termination metric:
 *  (rank of the goal, drop allowance, budget, unreported writes, gap, not yet observed) */
export const metricSpec = (s: Synced, d: number): ReadonlyArray<number> => [
  rank(s.asset.goal),
  d,
  s.asset.budget,
  s.asset.authorised.length,
  gapSpec(s.asset, s.model),
  isSeen(s.asset.seen) ? 0 : 1
]

/** Smaller: b is lexicographically below a. */
export const lexLess = (b: ReadonlyArray<number>, a: ReadonlyArray<number>): boolean => {
  for (let i = 0; i < a.length; i++) {
    const x = b[i] ?? 0
    const y = a[i] ?? 0
    if (x !== y) return x < y
  }
  return false
}
