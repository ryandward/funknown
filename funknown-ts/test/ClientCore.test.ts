// Properties for Funknown.Client.Core and the KMove predicate of
// Funknown.Client.Contract. LiquidHaskell proves KMove in every move's
// result type; here each move is run on generated assets and held to KMove,
// to the move's own Haskell postcondition, and to the Asset refinement.
import assert from "node:assert/strict"
import { test } from "node:test"
import { Data, Equal, FastCheck as fc, Match, Option } from "effect"
import { Int, PosInt } from "../src/Num.js"
import { Chunk, emptyChunks, limitsOf, offsetOf } from "../src/Upload.js"
import {
  type Asset,
  type AssetCommon,
  type Ending,
  ObjectObs,
  Outcome,
  Seen,
  Vouch,
  Write,
  asset,
  assembledGoal,
  assemblingGoal,
  assetInvariant,
  goalAdopted,
  goalTag,
  observed,
  rank,
  withAuthorised,
  withBudget,
  withSeen
} from "../src/Kernel/Types.js"
import {
  appendTo,
  asAdopted,
  clearGoal,
  completeGoal,
  isAssemblingAsset,
  isKeepAsset,
  reportWrite,
  startWrite
} from "../src/Client/Core.js"
import { goalOffset, kMove, kMoveClauses } from "../src/Client/Contract.js"
import { assetArb, boundArb, endingArb, freshToken, stagingRefArb } from "./arb.js"

const runs = { numRuns: 1000 }

/** Fails with the names of the KMove clauses that broke. */
const assertKMove = (move: string, a: Asset, b: Asset): void => {
  const broken = Object.entries(kMoveClauses(a, b))
    .filter(([, ok]) => !ok)
    .map(([name]) => name)
  assert.deepEqual(broken, [], `${move} broke KMove: ${broken.join(", ")}`)
  assert.ok(kMove(a, b))
  assert.ok(assetInvariant(b), `${move} broke the Asset refinement`)
}

const offset = (a: Asset): number => Option.getOrElse(goalOffset(a.goal), () => -1)

// Every move, on every asset it accepts ------------------------------------------

test("clearGoal meets KMove, clears the goal and keeps the writes", () => {
  let tried = 0
  fc.assert(
    fc.property(assetArb, endingArb, (a, e) => {
      if (!isKeepAsset(a)) return
      tried++
      const b = clearGoal(a, e)
      assertKMove("clearGoal", a, b)
      assert.equal(goalTag(b.goal), 0)
      assert.equal(b.authorised, a.authorised)
    }),
    runs
  )
  assert.ok(tried > 100, `only ${tried} keep assets generated`)
})

test("appendTo meets KMove, grows the offset by the chunk and keeps the writes", () => {
  let appended = 0
  let refused = 0
  fc.assert(
    fc.property(assetArb, fc.integer({ min: 1, max: 12 }), fc.boolean(), (a0, n0, fit) => {
      if (!isAssemblingAsset(a0)) return
      Option.match(asAdopted(a0), {
        onNone: () => {},
        onSome: (a) => {
          // Half the sizes are drawn within the chunk bounds, so that enough
          // appends are accepted; the rest are anything, so some are refused.
          const lim = limitsOf(a.goal.assembly.chunks)
          const n = fit ? lim.minChunk + (n0 % (lim.maxChunk - lim.minChunk + 1)) : n0
          Option.match(appendTo(a, new Chunk({ cbytes: PosInt(n), ctoken: freshToken() })), {
            onNone: () => {
              refused++
            },
            onSome: (b) => {
              appended++
              assertKMove("appendTo", a, b)
              assert.equal(goalTag(b.goal), 2)
              assert.ok(goalAdopted(b.goal))
              assert.equal(offset(b), offset(a) + n)
              assert.ok(rank(b.goal) < rank(a.goal), "appendTo didn't lower the rank")
              assert.equal(b.authorised, a.authorised)
            }
          })
        }
      })
    }),
    runs
  )
  assert.ok(appended > 30 && refused > 30, `appended ${appended}, refused ${refused}`)
})

test("completeGoal meets KMove and completes with exactly the chunks it had", () => {
  let tried = 0
  fc.assert(
    fc.property(assetArb, (a0) => {
      if (!isAssemblingAsset(a0)) return
      Option.match(asAdopted(a0), {
        onNone: () => {},
        onSome: (a) => {
          tried++
          const b = completeGoal(a)
          assertKMove("completeGoal", a, b)
          assert.equal(goalTag(b.goal), 1)
          assert.equal(offset(b), offset(a))
          assert.equal(b.authorised, a.authorised)
        }
      })
    }),
    runs
  )
  assert.ok(tried > 50, `only ${tried} adopted assets generated`)
})

test("startWrite meets KMove, keeps the goal and adds exactly one write", () => {
  let tried = 0
  fc.assert(
    fc.property(assetArb, fc.integer({ min: 0, max: 9 }), fc.integer({ min: 0, max: 100 }), (a, e, dl) => {
      if (!isAssemblingAsset(a)) return
      tried++
      const b = startWrite(a, Int(e), Int(dl))
      assertKMove("startWrite", a, b)
      assert.ok(Equal.equals(b.goal, a.goal))
      assert.equal(b.authorised.length, a.authorised.length + 1)
    }),
    runs
  )
  assert.ok(tried > 100, `only ${tried} assembling assets generated`)
})

test("reportWrite meets KMove on any asset, keeps the goal and never adds a write", () => {
  let removed = 0
  fc.assert(
    fc.property(assetArb, fc.integer({ min: 0, max: 9 }), (a, e) => {
      const b = reportWrite(a, Int(e))
      assertKMove("reportWrite", a, b)
      assert.ok(Equal.equals(b.goal, a.goal))
      const had = a.authorised.some((w) => w.epoch === e)
      assert.equal(b.authorised.length, had ? a.authorised.length - 1 : a.authorised.length)
      if (had) removed++
    }),
    runs
  )
  assert.ok(removed > 50, `only ${removed} reports matched a write`)
})

test("asAdopted rebuilds the same asset exactly when a staging area is adopted", () => {
  fc.assert(
    fc.property(assetArb, (a) => {
      if (!isAssemblingAsset(a)) return
      Option.match(asAdopted(a), {
        onNone: () => assert.ok(!goalAdopted(a.goal)),
        onSome: (b) => {
          assert.ok(goalAdopted(a.goal))
          assert.ok(Equal.equals(b.goal, a.goal), "the adopted goal doesn't compare equal to the original")
          assert.ok(kMove(a, b))
          assert.equal(b.backoffAt, a.backoffAt)
          assert.equal(b.outcome, a.outcome)
          assert.equal(b.authorised, a.authorised)
        }
      })
    }),
    runs
  )
})

// The convergence metric under a script of client moves ---------------------------

/** One client move, with its arguments. A step whose move doesn't apply to
 *  the asset changes nothing, like an honest round in Converge. */
type Step = Data.TaggedEnum<{
  Abandon: { readonly ending: Ending }
  Append: { readonly bytes: number }
  Complete: {}
  Start: { readonly epoch: number; readonly deadline: number }
  Report: { readonly epoch: number }
}>
const Step = Data.taggedEnum<Step>()

const stepArb: fc.Arbitrary<Step> = fc.oneof(
  endingArb.map((ending) => Step.Abandon({ ending })),
  fc.integer({ min: 1, max: 12 }).map((bytes) => Step.Append({ bytes })),
  fc.constant(Step.Complete()),
  fc.tuple(fc.integer({ min: 0, max: 9 }), fc.integer({ min: 0, max: 100 })).map(([epoch, deadline]) => Step.Start({ epoch, deadline })),
  fc.integer({ min: 0, max: 9 }).map((epoch) => Step.Report({ epoch }))
)

/** The asset after the step, and whether the step was a start. */
const apply = (a: Asset, s: Step): { readonly next: Asset; readonly started: boolean } => {
  const same = { next: a, started: false }
  const moved = (next: Asset) => ({ next, started: false })
  return Match.valueTags(s, {
    Abandon: ({ ending }) => (isKeepAsset(a) ? moved(clearGoal(a, ending)) : same),
    Append: ({ bytes }) =>
      isAssemblingAsset(a)
        ? Option.match(
            Option.flatMap(asAdopted(a), (d) => appendTo(d, new Chunk({ cbytes: PosInt(bytes), ctoken: freshToken() }))),
            { onNone: () => same, onSome: moved }
          )
        : same,
    Complete: () =>
      isAssemblingAsset(a) ? Option.match(asAdopted(a), { onNone: () => same, onSome: (d) => moved(completeGoal(d)) }) : same,
    Start: ({ epoch, deadline }) =>
      isAssemblingAsset(a) ? { next: startWrite(a, Int(epoch), Int(deadline)), started: true } : same,
    Report: ({ epoch }) => moved(reportWrite(a, Int(epoch)))
  })
}

/** The prefix of Converge's metric the client side can touch, in order:
 *  the goal's rank, the budget, the unreported writes. (The drop allowance,
 *  between rank and budget, belongs to the adversary's scheduler.) */
type Prefix = readonly [number, number, number]
const prefix = (a: Asset): Prefix => [rank(a.goal), a.budget, a.authorised.length]

/** Lexicographically at most. */
const atMost = (x: Prefix, y: Prefix): boolean =>
  x[0] < y[0] || (x[0] === y[0] && (x[1] < y[1] || (x[1] === y[1] && x[2] <= y[2])))

test("a script of client moves never raises the metric prefix, apart from each start's one write", () => {
  let starts = 0
  let goalMoves = 0
  fc.assert(
    fc.property(assetArb, fc.array(stepArb, { maxLength: 30 }), (a0, script) => {
      let a = a0
      let startsHere = 0
      for (const s of script) {
        const { next, started } = apply(a, s)
        const before = prefix(a)
        const after = prefix(next)
        if (started) {
          starts++
          startsHere++
          // The one permitted rise: one more write, rank and budget as they were.
          assert.deepEqual(after, [before[0], before[1], before[2] + 1], "a start moved more than its one write")
        } else {
          assert.ok(atMost(after, before), `${s._tag} raised the metric prefix from ${before} to ${after}`)
          if (!Equal.equals(next.goal, a.goal)) {
            goalMoves++
            assert.ok(after[0] < before[0], `${s._tag} moved the goal without lowering its rank`)
          }
        }
        assert.ok(kMove(a, next))
        a = next
      }
      // Over the whole script: the rank never rose, the budget never moved,
      // and the writes grew by at most the starts.
      assert.ok(rank(a.goal) <= rank(a0.goal))
      assert.equal(a.budget, a0.budget)
      assert.ok(a.authorised.length <= a0.authorised.length + startsHere)
    }),
    runs
  )
  assert.ok(starts > 100 && goalMoves > 100, `starts ${starts}, goal moves ${goalMoves}`)
})

test("goalOffset is None exactly for Clear, else the chunks' offset", () => {
  fc.assert(
    fc.property(assetArb, (a) => {
      const o = goalOffset(a.goal)
      assert.equal(Option.isNone(o), goalTag(a.goal) === 0)
      if (a.goal._tag === "Keep") assert.equal(Option.getOrElse(o, () => -1), offsetOf(a.goal.assembly.chunks))
    }),
    runs
  )
})

// The predicate's own negative control ------------------------------------------
// A KMove that accepted everything would pass every property above, so each
// clause is shown here refusing a move that breaks it and nothing it can
// see as legal: the named clause has to be the one that fails.

const commonOf = (a: Asset): AssetCommon => ({ seen: a.seen, budget: a.budget, backoffAt: a.backoffAt, authorised: a.authorised })
const aWrite = new Write({ epoch: Int(99), deadline: Int(0) })

/** Asserts that kMove refuses a -> b and that `clause` is among the reasons. */
const refuses = (clause: keyof ReturnType<typeof kMoveClauses>, a: Asset, b: Asset): void => {
  assert.equal(kMoveClauses(a, b)[clause], false, `KMove's ${clause} clause accepted an illegal move`)
  assert.equal(kMove(a, b), false)
}

test("KMove refuses each kind of illegal move, by the clause that forbids it", () => {
  const seen = { seenKept: 0, budgetKept: 0, vouchKept: 0, endingKept: 0, atMostOneStart: 0, startOnlyAlone: 0, rankNotRaised: 0, goalChangeLowersRank: 0, stagingKept: 0, chunksOnlyGrow: 0, completeKeepsChunks: 0 }
  fc.assert(
    fc.property(assetArb, endingArb, endingArb, stagingRefArb, boundArb(PosInt(1)), (a, e1, e2, ref, bound) => {
      // Fields that belong to the reconciler.
      const otherSeen = a.seen._tag === "Unseen" ? Seen.Seen({ observed: observed([], ObjectObs.NoObject()) }) : Seen.Unseen()
      refuses("seenKept", a, withSeen(a, otherSeen)); seen.seenKept++
      refuses("budgetKept", a, withBudget(a, a.budget === 0 ? 1 : 0)); seen.budgetKept++
      // More than one start, or a start that isn't alone on an assembly.
      refuses("atMostOneStart", a, withAuthorised(a, [aWrite, aWrite, ...a.authorised])); seen.atMostOneStart++

      if (isKeepAsset(a)) {
        const c1 = clearGoal(a, e1)
        // A cleared goal can't be reopened, nor its ending rewritten.
        refuses("rankNotRaised", c1, a); seen.rankNotRaised++
        if (!Equal.equals(e1, e2)) {
          refuses("endingKept", c1, clearGoal(a, e2)); seen.endingKept++
        }
        refuses("startOnlyAlone", c1, withAuthorised(c1, [aWrite, ...c1.authorised])); seen.startOnlyAlone++
        const flipped = c1.vouch._tag === "NoReceipt" ? Vouch.HasReceipt({ bound }) : Vouch.NoReceipt()
        refuses("vouchKept", c1, asset({ ...commonOf(c1), goal: c1.goal, outcome: c1.outcome, vouch: flipped })); seen.vouchKept++
      }

      if (isAssemblingAsset(a)) {
        const chunks = a.goal.assembly.chunks
        const assembling = (staging: Option.Option<typeof ref>, cs: typeof chunks) =>
          asset({ ...commonOf(a), goal: assemblingGoal(staging, cs), outcome: Outcome.Ongoing(), vouch: Vouch.NoReceipt() })
        if (!goalAdopted(a.goal)) {
          // Adopting a staging area changes the goal but not its rank.
          refuses("goalChangeLowersRank", a, assembling(Option.some(ref), chunks)); seen.goalChangeLowersRank++
        } else if (!Equal.equals(a.goal.assembly.staging, Option.some(ref))) {
          refuses("stagingKept", a, assembling(Option.some(ref), chunks)); seen.stagingKept++
        }
        if (offsetOf(chunks) > 0) {
          const empty = emptyChunks(limitsOf(chunks))
          refuses("chunksOnlyGrow", a, assembling(a.goal.assembly.staging, empty)); seen.chunksOnlyGrow++
          refuses("completeKeepsChunks", a, asset({ ...commonOf(a), goal: assembledGoal(ref, empty), outcome: Outcome.Ongoing(), vouch: Vouch.NoReceipt() })); seen.completeKeepsChunks++
        }
      }
    }),
    runs
  )
  const missed = Object.entries(seen).filter(([, n]) => n < 20).map(([k, n]) => `${k} ${n}`)
  assert.deepEqual(missed, [], "some clauses were barely exercised")
})
