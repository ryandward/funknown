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
import { Equal, HashSet, Match, Option } from "effect"
import type { Fault } from "../Fault.js"
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
  type Outcome,
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

/** K11: an asset with no observation comes back exactly as it went in, with
 *  no alarm, so a failed observe call turned into Unseen costs nothing but
 *  the call. */
export const k11 = (a: Asset, d: Decision): boolean =>
  implies(
    !isSeen(a.seen),
    Equal.equals(d.next.goal, a.goal) &&
      Equal.equals(d.next.outcome, a.outcome) &&
      Equal.equals(d.next.vouch, a.vouch) &&
      Equal.equals(d.next.seen, a.seen) &&
      d.next.budget === a.budget &&
      d.next.backoffAt === a.backoffAt &&
      sameWrites(d.next.authorised, a.authorised) &&
      !d.alarm
  )

/** Which of the faults an observation of the store can justify on its own
 *  (Haskell's storeFault): 1 StateLost, 2 Contradiction, 3 SizeMismatch,
 *  4 ObjectWithoutReceipt, 5 Unavailable, and 0 for the rest, which name a
 *  call's result or a client-side check. The table is keyed by every Fault
 *  tag, so a new fault doesn't compile until it is placed here. */
const storeFaultOf = {
  StateLost: 1,
  Contradiction: 2,
  SizeMismatch: 3,
  ObjectWithoutReceipt: 4,
  Unavailable: 5,
  Expired: 0,
  FinalizeTimedOut: 0,
  OutOfRange: 0,
  TooLarge: 0,
  QuotaAtFinalize: 0,
  Revoked: 0,
  Empty: 0,
  CreationRefused: 0,
  CreationInterrupted: 0,
  StoreRefusedUs: 0,
  SourceUnreachable: 0,
  SourceAnswered: 0,
  SourceChanged: 0
} as const satisfies Record<Fault["_tag"], 0 | 1 | 2 | 3 | 4 | 5>

/** The store fault an ending names, as storeFaultOf numbers it, or 0
 *  (Haskell's failedOnStore). */
const failedOnStore = (o: Outcome): 0 | 1 | 2 | 3 | 4 | 5 =>
  Match.valueTags(o, {
    Ongoing: () => 0 as const,
    Ended: ({ ending }) => (ending._tag === "Failed" ? storeFaultOf[ending.fault._tag] : 0)
  })

/** K12: a fault the reconciler sets is one of the five an observation can
 *  justify, and the observation it was decided on shows exactly that. */
export const k12 = (a: Asset, d: Decision): boolean => {
  const f = failedOnStore(d.next.outcome)
  const t = seenObjTag(a.seen)
  return implies(
    !isEnded(a.outcome) && isEnded(d.next.outcome),
    f !== 0 &&
      isSeen(a.seen) &&
      implies(f === 1, t === 0 || (hasReceipt(a.vouch) && !sameOpt(seenVersion(a.seen), vouchVersion(a.vouch)))) &&
      implies(f === 2, t !== 0) &&
      implies(f === 3, t === 1) &&
      implies(f === 4, t === 2) &&
      implies(f === 5, t === 3 && a.budget === 0)
  )
}

/** K13: the converse of K9. While a receipt is held for an assembled goal
 *  and the observation shows the object at the receipt's version, the goal
 *  and the receipt stay as they are. */
export const k13 = (a: Asset, d: Decision): boolean =>
  implies(
    goalTag(a.goal) === 1 &&
      hasReceipt(a.vouch) &&
      isSeen(a.seen) &&
      seenObjTag(a.seen) !== 0 &&
      sameOpt(seenVersion(a.seen), vouchVersion(a.vouch)),
    Equal.equals(d.next.goal, a.goal) && Equal.equals(d.next.vouch, a.vouch)
  )

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
  K11: k11,
  K12: k12,
  K13: k13,
  Prog: prog,
  authorised: keepsAuthorised
} satisfies Record<string, (a: Asset, d: Decision) => boolean>
