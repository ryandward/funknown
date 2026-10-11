// Properties of Funknown.Kernel.Reconcile: every claim of LiquidHaskell's
// Step type (K0 to K13, Prog, authorised unchanged) over generated assets and
// observations, one test per claim so a failure names it; the asset each step
// leaves behind is still a valid Asset; and the lookups' postconditions.
// These are sampled, not proved.
import assert from "node:assert/strict"
import { test } from "node:test"
import { FastCheck as fc, HashSet, Option } from "effect"
import { decide, firstOther, firstRef, holds, listed, pending, reconcile } from "../src/Kernel/Reconcile.js"
import { stepClaims } from "../src/Kernel/ReconcileClaims.js"
import { type Asset, type Decision, type Env, type Row, allRows, assetInvariant, refSet, staging } from "../src/Kernel/Types.js"
import { Int } from "../src/Num.js"
import { chunksArb, stagingRefArb, writesArb } from "./arb.js"
import { caseArb } from "./reconcileArb.js"

const runs = { numRuns: 2000 }

const claimTest = (name: keyof typeof stepClaims) =>
  test(`Step claim ${name} holds for every generated asset and observation`, () => {
    const claim: (a: Asset, d: Decision) => boolean = stepClaims[name]
    fc.assert(
      fc.property(caseArb, ([a, env]) => claim(a, reconcile(env, a))),
      runs
    )
  })

claimTest("K0")
claimTest("K1")
claimTest("K1b")
claimTest("K2")
claimTest("K3")
claimTest("K4")
claimTest("K5n")
claimTest("K8")
claimTest("K9")
claimTest("K10")
claimTest("K11")
claimTest("K12")
claimTest("K13")
claimTest("Prog")
claimTest("authorised")

test("the generator reaches every row of the table", () => {
  const reached = new Set<Row>()
  for (const [a, env] of fc.sample(caseArb, { numRuns: 4000, seed: 7 })) reached.add(decide(env, a).row)
  assert.deepEqual(
    allRows.filter((r) => !reached.has(r)),
    []
  )
})

test("every step leaves a valid Asset, and the leaf's row is the decision's", () => {
  fc.assert(
    fc.property(caseArb, ([a, env]: readonly [Asset, Env]) => {
      const l = decide(env, a)
      return assetInvariant(l.decision.next) && l.row === l.decision.row
    }),
    runs
  )
})

const stagingsArb = fc.array(
  stagingRefArb.map((r) => staging(r, [])),
  { maxLength: 4 }
)

test("firstRef: a ref found is listed, and none is found only in an empty listing", () => {
  fc.assert(
    fc.property(stagingsArb, (ss) =>
      Option.match(firstRef(ss), { onNone: () => ss.length === 0, onSome: (r) => HashSet.has(refSet(ss), r) })
    ),
    runs
  )
})

test("firstOther: a ref found is listed and isn't r; none only when every listing is r", () => {
  fc.assert(
    fc.property(stagingRefArb, stagingsArb, (r, ss) =>
      Option.match(firstOther(r, ss), {
        onNone: () => ss.every((s) => s.ref === r),
        onSome: (o) => o !== r && HashSet.has(refSet(ss), o)
      })
    ),
    runs
  )
})

test("listed is membership, and holds implies listed", () => {
  fc.assert(
    fc.property(stagingRefArb, stagingsArb, chunksArb, (r, ss, c) =>
      listed(r, ss) === HashSet.has(refSet(ss), r) && (!holds(r, c, ss) || listed(r, ss))
    ),
    runs
  )
})

test("pending is 0 exactly when no write's deadline is after now, and otherwise the latest deadline less now", () => {
  fc.assert(
    fc.property(fc.integer({ min: 0, max: 200 }), writesArb, (now, ws) => {
      const p = pending(Int(now), ws)
      const late = ws.filter((w) => w.deadline > now).map((w) => w.deadline - now)
      return late.length === 0 ? p === 0 : p === Math.max(...late)
    }),
    runs
  )
})
