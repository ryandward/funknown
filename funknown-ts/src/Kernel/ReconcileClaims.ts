// The claims LiquidHaskell's Step type holds every reconciler row to, as
// predicates over an asset and the decision taken on it. In Haskell they are
// proved for every row; here they are only checked, by the FastCheck
// properties in test/Reconcile.test.ts. They live in src/ so later modules
// (Model, Converge) can reuse Prog, and so a mutant of Reconcile.ts can't
// edit the spec it is checked against.
//
// LiquidHaskell's measures return sentinels (-1, Version []) where these
// return Option, so `==` on two measures becomes `sameOpt`. Every clause below
// that compares measures also requires the tags that make both sides Some, as
// the Haskell does, so the two readings agree.
import { Equal, HashSet, Option } from "effect"
import {
  type Asset,
  type Decision,
  assembledRef,
  assembledTotal,
  cmdTag,
  discardRef,
  gapI,
  goalAdopted,
  goalStaging,
  goalTag,
  hasReceipt,
  isEnded,
  isFixedRow,
  isSeen,
  rank,
  removeVersion,
  seenObjTag,
  seenRefs,
  seenStagings,
  seenVersion,
  seenVouchedSize,
  vouchSize,
  vouchVersion,
  type Write
} from "./Types.js"
import { isFailed } from "./Reconcile.js"

const implies = (p: boolean, q: boolean): boolean => !p || q

/** Equality of two Option measures: both None, or both Some of equal values. */
const sameOpt = <A>(x: Option.Option<A>, y: Option.Option<A>): boolean => Equal.equals(x, y)

const sameWrites = (x: ReadonlyArray<Write>, y: ReadonlyArray<Write>): boolean =>
  x.length === y.length && x.every((w, i) => Equal.equals(w, y[i]))

/** K8: the goal's rank never rises; an ending, once set, never changes; the
 *  reconciler moves the goal only by clearing it as Failed, and otherwise
 *  leaves its kind, rank and assembled length alone. */
export const k8 = (a: Asset, d: Decision): boolean => {
  const n = d.next
  return (
    rank(n.goal) <= rank(a.goal) &&
    implies(isEnded(a.outcome), Equal.equals(n.outcome, a.outcome)) &&
    implies(goalTag(a.goal) !== 0 && goalTag(n.goal) === 0, isFailed(n.outcome)) &&
    implies(
      goalTag(n.goal) !== 0,
      goalTag(n.goal) === goalTag(a.goal) && rank(n.goal) === rank(a.goal) && sameOpt(assembledTotal(n.goal), assembledTotal(a.goal))
    )
  )
}

/** K1: a receipt appears only for an assembled object the store vouched for,
 *  with the assembled length, bound to the version that was observed. */
export const k1 = (a: Asset, d: Decision): boolean =>
  implies(
    hasReceipt(d.next.vouch) && !hasReceipt(a.vouch),
    goalTag(a.goal) === 1 &&
      seenObjTag(a.seen) === 1 &&
      sameOpt(seenVouchedSize(a.seen), assembledTotal(a.goal)) &&
      sameOpt(vouchSize(d.next.vouch), assembledTotal(a.goal)) &&
      sameOpt(vouchVersion(d.next.vouch), seenVersion(a.seen))
  )

/** K1b: while the goal isn't Clear, a receipt once held is never replaced. */
export const k1b = (a: Asset, d: Decision): boolean =>
  implies(hasReceipt(a.vouch) && goalTag(d.next.goal) !== 0, Equal.equals(d.next.vouch, a.vouch))

/** K2: Seal only for an assembled goal with no receipt and no object seen. */
export const k2 = (a: Asset, d: Decision): boolean =>
  implies(
    cmdTag(d.command) === 3,
    goalTag(a.goal) === 1 && !hasReceipt(a.vouch) && isSeen(a.seen) && seenObjTag(a.seen) === 0
  )

/** K3: while a receipt is held and the goal isn't Clear, no Remove. */
export const k3 = (a: Asset, d: Decision): boolean =>
  implies(hasReceipt(a.vouch) && goalTag(a.goal) !== 0, cmdTag(d.command) !== 5)

/** K4: when the goal is Clear and anything was seen held, Discard or Remove. */
export const k4 = (a: Asset, d: Decision): boolean =>
  implies(
    goalTag(a.goal) === 0 && isSeen(a.seen) && (seenStagings(a.seen) > 0 || seenObjTag(a.seen) !== 0),
    cmdTag(d.command) === 4 || cmdTag(d.command) === 5
  )

/** K5n: Discard names a staging area that was seen; Remove names the version
 *  seen. */
export const k5n = (a: Asset, d: Decision): boolean =>
  implies(cmdTag(d.command) === 4, Option.exists(discardRef(d.command), (r) => HashSet.has(seenRefs(a.seen), r))) &&
  implies(cmdTag(d.command) === 5, sameOpt(removeVersion(d.command), seenVersion(a.seen)) && seenObjTag(a.seen) !== 0)

/** K0: nothing but Observe before there is an observation, and every store
 *  command makes the observation stale. */
export const k0 = (a: Asset, d: Decision): boolean =>
  implies(!isSeen(a.seen), cmdTag(d.command) === 1) && implies(cmdTag(d.command) >= 1, !isSeen(d.next.seen))

/** K9: while a receipt is held for an assembled goal, an observation that
 *  shows no object, or an object at another version, clears the goal. */
export const k9 = (a: Asset, d: Decision): boolean =>
  implies(
    goalTag(a.goal) === 1 &&
      hasReceipt(a.vouch) &&
      isSeen(a.seen) &&
      (seenObjTag(a.seen) === 0 || !sameOpt(seenVersion(a.seen), vouchVersion(a.vouch))),
    goalTag(d.next.goal) === 0
  )

/** K10: while the goal keeps the asset and no receipt is held, no Discard
 *  names the staging area holding the goal's chunks. */
export const k10 = (a: Asset, d: Decision): boolean =>
  implies(
    goalTag(a.goal) !== 0 && goalAdopted(a.goal) && !hasReceipt(a.vouch) && cmdTag(d.command) === 4,
    !sameOpt(discardRef(d.command), goalStaging(a.goal))
  )

/** The gap of an asset's goal and receipt, measured on observation `on`. */
const gapOn = (x: Asset, on: Asset) =>
  gapI(goalTag(x.goal), goalAdopted(x.goal), hasReceipt(x.vouch), seenStagings(on.seen), seenObjTag(on.seen))

/** Prog, what the progress lemma needs from each step: a step that issues
 *  nothing leaves the observation and budget alone and, unless it rests,
 *  lowers the goal's rank or, at equal rank, the gap measured on the same
 *  observation; an Observe is the first look, a spent attempt, or the write
 *  wait; Open only with nothing staged for an unadopted assembly; Seal only of
 *  a staging area that was seen; and a store command leaves goal, receipt and
 *  budget alone. */
export const prog = (a: Asset, d: Decision): boolean => {
  const n = d.next
  const c = cmdTag(d.command)
  return (
    implies(
      c === 0,
      Equal.equals(n.seen, a.seen) &&
        n.budget === a.budget &&
        (isFixedRow(d.row) ||
          rank(n.goal) < rank(a.goal) ||
          (rank(n.goal) === rank(a.goal) && gapOn(n, a) < gapOn(a, a)))
    ) &&
    implies(
      c === 1,
      Equal.equals(n.goal, a.goal) &&
        Equal.equals(n.vouch, a.vouch) &&
        ((!isSeen(a.seen) && n.budget === a.budget) ||
          (isSeen(a.seen) && n.budget < a.budget) ||
          (isFixedRow(d.row) && n.budget === a.budget))
    ) &&
    implies(
      c === 2,
      goalTag(a.goal) === 2 && !goalAdopted(a.goal) && seenStagings(a.seen) === 0 && seenObjTag(a.seen) === 0
    ) &&
    implies(c === 3, Option.exists(assembledRef(a.goal), (r) => HashSet.has(seenRefs(a.seen), r))) &&
    implies(c === 4, goalTag(a.goal) !== 2 || goalAdopted(a.goal)) &&
    implies(c === 5, goalTag(a.goal) === 0) &&
    implies(c >= 2, Equal.equals(n.goal, a.goal) && Equal.equals(n.vouch, a.vouch) && n.budget === a.budget)
  )
}

/** authorised (next d) == authorised a */
export const keepsAuthorised = (a: Asset, d: Decision): boolean => sameWrites(d.next.authorised, a.authorised)

/** Every claim of LiquidHaskell's Step type, by name, so a failing property
 *  says which one broke. */
export const stepClaims = {
  K0: k0,
  K1: k1,
  K1b: k1b,
  K2: k2,
  K3: k3,
  K4: k4,
  K5n: k5n,
  K8: k8,
  K9: k9,
  K10: k10,
  Prog: prog,
  authorised: keepsAuthorised
} satisfies Record<string, (a: Asset, d: Decision) => boolean>
