// Properties for Funknown.Kernel.Model: the store contract (perform), the
// observation (observeInto), and the progress lemma (round).
import assert from "node:assert/strict"
import { test } from "node:test"
import { Equal, FastCheck as fc, HashSet, Option } from "effect"
import {
  dropRef,
  observeInto,
  perform,
  round,
  synced
} from "../src/Kernel/Model.js"
import {
  Cmd,
  type Row,
  type Write,
  allRows,
  assembledRef,
  cmdTag,
  discardRef,
  goalTag,
  isFixedRow,
  isSeen,
  nStagings,
  obsObjTag,
  obsRefs,
  obsStagings,
  obsVersion,
  refSet,
  removeVersion,
  seenObjTag,
  seenRefs,
  seenStagings,
  seenVersion,
  staging
} from "../src/Kernel/Types.js"
import { envArb, stagingRefArb, versionArb } from "./arb.js"
import { cmdArb, modelFor, pairArb, syncedArb } from "./arbModel.js"
import { coherentSpec, lowerSpec } from "./specModel.js"

const runs = { numRuns: 1000 }

const sameOpt = <A>(x: Option.Option<A>, y: Option.Option<A>): boolean => Equal.equals(x, y)
const sameWrites = (x: ReadonlyArray<Write>, y: ReadonlyArray<Write>): boolean =>
  x.length === y.length && x.every((w, i) => Equal.equals(w, y[i]))

test("dropRef: the count never grows, and drops when the ref was listed", () => {
  fc.assert(
    fc.property(stagingRefArb, fc.array(stagingRefArb, { maxLength: 5 }), (r, refs) => {
      const ss = refs.map((x) => staging(x, []))
      const t = dropRef(r, ss)
      const shrinks = !HashSet.has(refSet(ss), r) || nStagings(t) < nStagings(ss)
      return nStagings(t) <= nStagings(ss) && shrinks && !HashSet.has(refSet(t), r)
    }),
    runs
  )
})

test("perform meets the store contract, command by command", () => {
  fc.assert(
    fc.property(pairArb, cmdArb, ([a, m], c) => {
      const g = a.goal
      const n = perform(g, c, m)
      const before = m.obs
      const after = n.obs
      const t = cmdTag(c)
      const s0 = obsStagings(before)
      const s1 = obsStagings(after)
      const o0 = obsObjTag(before)
      const o1 = obsObjTag(after)
      const noChange = t > 1 || Equal.equals(after, before)
      const open = t !== 2 || (s1 === s0 + 1 && o1 === o0)
      const sealGuard =
        t === 3 &&
        goalTag(g) === 1 &&
        o0 === 0 &&
        Option.match(assembledRef(g), { onNone: () => false, onSome: (r) => HashSet.has(obsRefs(before), r) })
      const seal = !sealGuard || (s1 < s0 && o1 !== 0)
      const discardGuard =
        t === 4 && Option.match(discardRef(c), { onNone: () => false, onSome: (r) => HashSet.has(obsRefs(before), r) })
      const discard = !discardGuard || (s1 < s0 && o1 === o0)
      const removeGuard = t === 5 && o0 !== 0 && sameOpt(removeVersion(c), obsVersion(before))
      const remove = !removeGuard || (s1 === s0 && o1 === 0)
      return noChange && open && seal && discard && remove
    }),
    runs
  )
})

test("observeInto: the asset sees exactly what the store holds, and nothing else changes", () => {
  fc.assert(
    fc.property(pairArb, ([a, m]) => {
      const b = observeInto(a, m)
      return (
        Equal.equals(b.goal, a.goal) &&
        Equal.equals(b.vouch, a.vouch) &&
        b.budget === a.budget &&
        Equal.equals(b.outcome, a.outcome) &&
        sameWrites(b.authorised, a.authorised) &&
        isSeen(b.seen) &&
        seenStagings(b.seen) === obsStagings(m.obs) &&
        seenObjTag(b.seen) === obsObjTag(m.obs) &&
        Equal.equals(seenRefs(b.seen), obsRefs(m.obs)) &&
        sameOpt(seenVersion(b.seen), obsVersion(m.obs)) &&
        coherentSpec(b, m)
      )
    }),
    runs
  )
})

test("synced is present exactly when the pair is Coherent", () => {
  let accepted = 0
  let refused = 0
  fc.assert(
    // The asset observes one model and is paired with another, which is
    // sometimes the same store and sometimes one that moved on.
    fc.property(pairArb.chain(([a, m]) => fc.tuple(fc.constant(a), fc.constant(m), modelFor(a), fc.boolean())), ([a, m, other, same]) => {
      const b = observeInto(a, m)
      const n = same ? m : other
      const s = synced(b, n)
      if (Option.isSome(s)) accepted++
      else refused++
      return Option.isSome(s) === coherentSpec(b, n)
    }),
    runs
  )
  assert.ok(accepted > 0 && refused > 0, "the generator reached both answers")
})

// Store contract rule 2, which the LiquidHaskell spec of perform leaves out:
// Remove is conditional on the version it names.
test("perform: Remove leaves an object at another version alone", () => {
  fc.assert(
    fc.property(pairArb, versionArb, ([a, m], v) => {
      const n = perform(a.goal, Cmd.DoRemove({ version: v }), m)
      const at = obsVersion(m.obs)
      return Option.isNone(at) || at.value === v || Equal.equals(n.obs, m.obs)
    }),
    runs
  )
})

// The progress lemma: from a Coherent pair, one round of the real reconciler
// against the honest store either rests or lowers (rank, budget, gap, not yet
// observed) lexicographically, observes, stays Coherent, and leaves the
// unreported writes alone.
test("progress: every round rests or lowers the metric, and leaves the asset's observation exact", () => {
  const rows = new Set<Row>()
  fc.assert(
    fc.property(envArb, syncedArb, (env, s) => {
      const r = round(env, s)
      const b = r.synced.asset
      const n = r.synced.model
      rows.add(r.row)
      return (
        (isFixedRow(r.row) || lowerSpec(s.asset, s.model, b, n)) &&
        isSeen(b.seen) &&
        coherentSpec(b, n) &&
        sameWrites(b.authorised, s.asset.authorised)
      )
    }),
    { numRuns: 5000 }
  )
  // The lemma is vacuous for any row the generator never reaches.
  const missing = allRows.filter((row) => !rows.has(row))
  assert.deepEqual(missing, [], `rows never reached: ${missing.join(", ")}`)
})
