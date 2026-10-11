// Funknown.Client.Contract, the KMove part: the only ways the client side
// may change the kernel's asset, which are the adversary's moves in
// Funknown.Kernel.Converge, so convergence carries over to the composed
// system.
//
// In LiquidHaskell, KMove is a predicate every client move's result type
// carries, so it is proved at every move. Here it is a boolean function.
// Client/Core.ts says which clauses its move types carry on their own, and
// test/ClientCore.test.ts checks the whole predicate on every move over
// generated assets. Nothing here is enforced by the compiler.
import { Equal, Match, Option } from "effect"
import type { Nat } from "../Num.js"
import { offsetOf } from "../Upload.js"
import { type Asset, type Goal, goalAdopted, goalStaging, goalTag, isEnded, rank } from "../Kernel/Types.js"

/** How many bytes the goal's chunks hold. Haskell's measure answers -1 for
 *  Clear to stay total; this one answers None. */
export const goalOffset = (g: Goal): Option.Option<Nat> =>
  Match.valueTags(g, {
    Clear: () => Option.none<Nat>(),
    Keep: ({ assembly }) => Option.some(offsetOf(assembly.chunks))
  })

/** Haskell's `goalOffset b >= goalOffset a`, read with -1 for None. Only
 *  used where b's goal isn't Clear, so b's side is always Some there. */
const offsetAtLeast = (b: Option.Option<Nat>, a: Option.Option<Nat>): boolean =>
  Option.getOrElse(b, () => -1) >= Option.getOrElse(a, () => -1)

/** Each clause of KMove A B, by name, so a failing property can say which
 *  one broke. */
export const kMoveClauses = (a: Asset, b: Asset) => {
  const ga = a.goal
  const gb = b.goal
  const tagA = goalTag(ga)
  const tagB = goalTag(gb)
  const goalSame = Equal.equals(gb, ga)
  const grew = b.authorised.length === a.authorised.length + 1
  return {
    seenKept: Equal.equals(b.seen, a.seen),
    vouchKept: Equal.equals(b.vouch, a.vouch),
    budgetKept: b.budget === a.budget,
    rankNotRaised: rank(gb) <= rank(ga),
    goalChangeLowersRank: goalSame || rank(gb) < rank(ga),
    stagingKept: !(tagB !== 0 && goalAdopted(ga)) || Equal.equals(goalStaging(gb), goalStaging(ga)),
    chunksOnlyGrow: tagB === 0 || offsetAtLeast(goalOffset(gb), goalOffset(ga)),
    completeKeepsChunks: !(tagA === 2 && tagB === 1) || Equal.equals(goalOffset(gb), goalOffset(ga)),
    endingKept: !isEnded(a.outcome) || Equal.equals(b.outcome, a.outcome),
    atMostOneStart: b.authorised.length <= a.authorised.length + 1,
    startOnlyAlone: !grew || (goalSame && tagA === 2)
  }
}

/** KMove A B: every clause holds. */
export const kMove = (a: Asset, b: Asset): boolean => Object.values(kMoveClauses(a, b)).every((ok) => ok)
