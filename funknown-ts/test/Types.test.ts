// Properties for Funknown.Kernel.Types: the measures, the Asset
// refinements, and K6.
import assert from "node:assert/strict"
import { test } from "node:test"
import { Either, Equal, FastCheck as fc, Option } from "effect"
import { Nat, PosInt } from "../src/Num.js"
import {
  Assembly,
  Goal,
  type GoalTag,
  type ObjTag,
  allRows,
  assembledGoal,
  assemblingGoal,
  assetInvariant,
  gapI,
  goalTag,
  hasReceipt,
  isActiveState,
  isFixedRow,
  makeAsset,
  rank,
  seenObjTag,
  seenVouchedSize,
  seenVersion,
  stateOf,
  withAuthorised,
  withBackoffAt,
  withBudget,
  withSeen
} from "../src/Kernel/Types.js"
import { room } from "../src/Upload.js"
import {
  assetArb,
  assetInputArb,
  attemptsArb,
  chunksArb,
  goalArb,
  posArb,
  receiptMatches,
  seenArb,
  stagingRefArb,
  writesArb
} from "./arb.js"

const runs = { numRuns: 1000 }

test("rank: 0 exactly for Clear, 1 for an assembled object, 2 + room for an assembly in progress", () => {
  fc.assert(
    fc.property(goalArb, (g) => {
      const r = rank(g)
      const t = goalTag(g)
      const byKind =
        g._tag === "Keep" && g.assembly._tag === "Assembling" ? r === 2 + room(g.assembly.chunks) : true
      return (t === 0) === (r === 0) && (t !== 1 || r === 1) && (t !== 2 || r >= 2) && byKind
    }),
    runs
  )
})

test("the narrow goal builders equal what Goal.Keep builds", () => {
  fc.assert(
    fc.property(stagingRefArb, chunksArb, (r, c) =>
      Equal.equals(assembledGoal(r, c), Goal.Keep({ assembly: Assembly.Assembled({ staging: r, chunks: c }) })) &&
      Equal.equals(
        assemblingGoal(Option.some(r), c),
        Goal.Keep({ assembly: Assembly.Assembling({ staging: Option.some(r), chunks: c }) })
      )
    )
  )
})

test("gapI matches the gap table in docs/design/kernel.md at every point", () => {
  // The table, transcribed apart from the code:
  //   Clear: staging areas, plus 1 for an object
  //   Assembling, nothing adopted: 3 when nothing is staged, otherwise staging areas + 1
  //   Assembling into r: staging areas
  //   Assembled, no receipt: staging areas, plus 2 with no object or 1 with one
  //   Assembled, receipt held: staging areas
  const table = (g: GoalTag, adopted: boolean, rc: boolean, n: number, obj: ObjTag): number => {
    if (g === 0) return n + (obj === 0 ? 0 : 1)
    if (g === 2) return adopted ? n : n === 0 ? 3 : n + 1
    if (rc) return n
    return n + (obj === 0 ? 2 : 1)
  }
  const goals: ReadonlyArray<GoalTag> = [0, 1, 2]
  const objs: ReadonlyArray<ObjTag> = [0, 1, 2, 3]
  let points = 0
  for (const g of goals)
    for (const adopted of [false, true])
      for (const rc of [false, true])
        for (let n = 0; n <= 5; n++)
          for (const obj of objs) {
            assert.equal(gapI(g, adopted, rc, Nat(n), obj), table(g, adopted, rc, n, obj))
            points++
          }
  assert.equal(points, 288)
})

test("observation measures agree: a vouched size exactly when the object tag is 1, a version exactly when there is an object", () => {
  fc.assert(
    fc.property(seenArb, (s) => {
      const t = seenObjTag(s)
      return Option.isSome(seenVouchedSize(s)) === (t === 1) && Option.isSome(seenVersion(s)) === (t !== 0)
    }),
    runs
  )
})

test("makeAsset accepts exactly the inputs whose receipt has the assembled length", () => {
  fc.assert(fc.property(assetInputArb, (i) => Either.isRight(makeAsset(i)) === receiptMatches(i)), runs)
})

test("every asset makeAsset builds meets the whole Asset refinement", () => {
  fc.assert(fc.property(assetArb, (a) => assetInvariant(a)), runs)
})

test("the with* functions change only their field and keep the refinement", () => {
  fc.assert(
    fc.property(assetArb, seenArb, attemptsArb, posArb(9), writesArb, (a, s, b, st, w) => {
      const all = [withSeen(a, s), withBudget(a, b), withBackoffAt(a, PosInt(st)), withAuthorised(a, w)]
      const [a1, a2, a3, a4] = all
      return (
        all.every((x) => assetInvariant(x) && x.goal === a.goal && x.outcome === a.outcome && x.vouch === a.vouch) &&
        a1 !== undefined && a1.seen === s && a1.budget === a.budget &&
        a2 !== undefined && a2.budget === b && a2.seen === a.seen &&
        a3 !== undefined && a3.backoffAt === st &&
        a4 !== undefined && a4.authorised === w
      )
    }),
    runs
  )
})

test("K6: stateOf is ACTIVE exactly when a receipt is held and the goal isn't Clear", () => {
  fc.assert(
    fc.property(assetArb, (a) => isActiveState(stateOf(a)) === (hasReceipt(a.vouch) && goalTag(a.goal) !== 0)),
    runs
  )
})

test("a deleted asset is DELETED only once the store was seen empty and no write is unreported", () => {
  fc.assert(
    fc.property(assetArb, (a) => {
      if (stateOf(a)._tag !== "DELETED") return true
      return (
        a.seen._tag === "Seen" &&
        a.seen.observed.stagings.length === 0 &&
        a.seen.observed.object._tag === "NoObject" &&
        a.authorised.length === 0 &&
        a.outcome._tag === "Ended" &&
        a.outcome.ending._tag === "Deleted"
      )
    }),
    runs
  )
})

test("the resting rows are exactly R3, R14, R18 and R19, and allRows lists twenty rows once each", () => {
  assert.equal(new Set(allRows).size, 20)
  assert.deepEqual(
    allRows.filter(isFixedRow),
    ["R3", "R14", "R18", "R19"]
  )
})

test("goalArb reaches every goal kind, so the properties above aren't vacuous", () => {
  const tags = new Set(fc.sample(goalArb, 300).map(goalTag))
  assert.equal(tags.size, 3)
  const fullRoom = fc.sample(goalArb, 2000).some((g) => g._tag === "Keep" && g.assembly._tag === "Assembling" && room(g.assembly.chunks) === 0)
  assert.ok(fullRoom, "no generated assembly reached its chunk cap")
})
