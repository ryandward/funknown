// Differential test against the proved Haskell kernel. The haskell-dump
// executable (funknown-core/dump/Dump.hs) runs the Haskell `reconcile`, `round`
// and `converge` on a fixed set of inputs and writes each input with the
// Haskell result as a JSON line; `npm run fixture` writes its output to
// test/fixtures/haskell-dump.jsonl. This test builds the same inputs through the TypeScript
// producers, runs the TypeScript functions, encodes their results in the same
// JSON shape, and compares the two encodings point by point.
//
// The inputs are:
// - "step": the 1320 points of test/Guards.hs, plus one step per generated
//   asset (random goals, chunk lists, observations, receipts, budgets,
//   backoff steps, writes and environments);
// - "round": rounds of the store model from generated Coherent pairs, each
//   pair followed for up to five rounds;
// - "converge": whole runs against generated adversary scripts.
//
// The JSON is decoded with Effect Schema, so no value is cast on the way in.
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"
import { Either, Option } from "effect"
import { converge } from "../src/Kernel/Converge.js"
import { round, synced } from "../src/Kernel/Model.js"
import { reconcile } from "../src/Kernel/Reconcile.js"
import { Nat } from "../src/Num.js"
import { type Json, type RecordJ, decodeRecord, encAsset, encDecision, encModel, toAsset, toEnv, toModel, toMove } from "./dumpCodec.js"

// Running one record on the TypeScript side ----------------------------------------------

/** The TypeScript result for a record, encoded, or why it has none. */
const runTs = (r: RecordJ): Either.Either<Json, string> => {
  const env = toEnv(r.env)
  const a = toAsset(r.asset)
  switch (r.kind) {
    case "step":
      return Either.right(encDecision(reconcile(env, a)))
    case "round":
      return Option.match(synced(a, toModel(r.model)), {
        onNone: () => Either.left("synced refused a pair the Haskell treats as Coherent"),
        onSome: (s) => {
          const out = round(env, s)
          return Either.right({ asset: encAsset(out.synced.asset), model: encModel(out.synced.model), row: out.row })
        }
      })
    case "converge":
      return Option.match(synced(a, toModel(r.model)), {
        onNone: () => Either.left("synced refused a pair the Haskell treats as Coherent"),
        onSome: (s) =>
          Either.match(converge(env, s, Nat(r.allowance), r.moves.map(toMove)), {
            onLeft: (np) => Either.left(`converge answered NoProgress after ${np.rounds} iterations`),
            onRight: (run) => Either.right({ asset: encAsset(run.asset), model: encModel(run.model), row: run.row })
          })
      })
    default: {
      const unreachable: never = r
      return unreachable
    }
  }
}

/** Where two encodings first differ, with a little context. */
const firstDifference = (x: string, y: string): string => {
  let i = 0
  while (i < x.length && i < y.length && x[i] === y[i]) i++
  return `at ${i}: haskell ...${x.slice(Math.max(0, i - 60), i + 60)}... / typescript ...${y.slice(Math.max(0, i - 60), i + 60)}...`
}

const lines = readFileSync(`${import.meta.dirname}/../../test/fixtures/haskell-dump.jsonl`, "utf8")
  .split("\n")
  .filter((l) => l.length > 0)

test("differential: the TypeScript reconcile, round and converge agree with the Haskell at every dumped point", () => {
  const counts = { step: 0, round: 0, converge: 0 }
  const disagreements: Array<string> = []
  lines.forEach((line, i) => {
    const r = decodeRecord(line)
    counts[r.kind] += 1
    const hs = JSON.stringify(r.out)
    const ts = Either.match(runTs(r), { onLeft: (why) => `NO RESULT: ${why}`, onRight: (j) => JSON.stringify(j) })
    if (hs !== ts) disagreements.push(`line ${i + 1} (${r.kind}): ${firstDifference(hs, ts)}`)
  })
  assert.equal(lines.length > 9000, true, `only ${lines.length} dumped points`)
  assert.deepEqual({ disagreements: disagreements.length, first: disagreements.slice(0, 5) }, { disagreements: 0, first: [] })
  assert.ok(counts.step >= 2820 && counts.round > 5000 && counts.converge >= 1500, JSON.stringify(counts))
})
