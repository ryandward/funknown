// K7: the guards of the decision table in docs/design/kernel.md are
// exhaustive and pairwise exclusive, and `reconcile` takes the row whose guard
// holds. A port of the Haskell test/Guards.hs. The guards below are
// transcribed from the table, apart from src/Kernel/Reconcile.ts, and checked
// over every shape an observation can take relative to the asset: which
// staging areas are listed (the current one holding every chunk, the current
// one missing a chunk, and others, in either order), what object is there
// (vouched with the right or wrong size, at the receipt's version or another,
// unvouchable, not yet vouched), budget, and writes still unreported. Nothing
// is sampled: each dimension is the full set of cases the table
// distinguishes, 1320 points in all.
import assert from "node:assert/strict"
import { test } from "node:test"
import { Either, Option } from "effect"
import { Fault } from "../src/Fault.js"
import { type Attempts, makeBackoff } from "../src/Http/Retry.js"
import { Version, bind } from "../src/Kernel/Bound.js"
import { reconcile } from "../src/Kernel/Reconcile.js"
import { stepClaims } from "../src/Kernel/ReconcileClaims.js"
import {
  type Asset,
  type AssetInput,
  Config,
  Ending,
  Env,
  Goal,
  ObjectObs,
  Outcome,
  type Row,
  Seen,
  StagingRef,
  Vouch,
  Vouching,
  Write,
  allRows,
  assembledGoal,
  assemblingGoal,
  makeAsset,
  observed,
  staging
} from "../src/Kernel/Types.js"
import { Int, Nat, PosInt } from "../src/Num.js"
import { ReceiptAlgorithm, checksumOf } from "../src/Store/Algorithm.js"
import { type ReceiptReport, receiptReport } from "../src/Store/Receipt.js"
import { Chunk, ChunkToken, appendChunk, emptyChunks, limits } from "../src/Upload.js"
import { valid } from "./arb.js"

const lim = valid(
  limits({ minChunk: PosInt(1), maxChunk: PosInt(10), maxChunks: PosInt(4), maxSize: Nat(100), sealsEmpty: false })
)
const theChunks = valid(
  Option.flatMap(appendChunk(emptyChunks(lim), new Chunk({ cbytes: PosInt(10), ctoken: ChunkToken("t1") })), (c) =>
    appendChunk(c, new Chunk({ cbytes: PosInt(3), ctoken: ChunkToken("t2") }))
  )
)
const total = 13

const cur = StagingRef("current")
const oth = StagingRef("orphan")
const oth2 = StagingRef("orphan2")
const v1 = Version("v1")
const v2 = Version("v2")

const report = (n: number): ReceiptReport =>
  valid(Option.flatMap(checksumOf(7n), (c) => receiptReport(ReceiptAlgorithm.Crc64Nvme(), c, n)))

const bound = Either.getOrThrowWith(bind(Nat(total), v1, report(total)), () => new Error("bind"))

// The dimensions ---------------------------------------------------------------

type G = "GClear" | "GAsmNone" | "GAsmCur" | "GDone"
type St = "SFull" | "SPart" | "SOther" | "SOther2"
type Ob = "ONone" | "OOk1" | "OOk2" | "OBad1" | "OUnv1" | "ONyv1"

const allG: ReadonlyArray<G> = ["GClear", "GAsmNone", "GAsmCur", "GDone"]
const budgets: ReadonlyArray<Attempts> = [0, 1]
const allOb: ReadonlyArray<Ob> = ["ONone", "OOk1", "OOk2", "OBad1", "OUnv1", "ONyv1"]
const stagingLists: ReadonlyArray<ReadonlyArray<St>> = [
  [], ["SFull"], ["SPart"], ["SOther"], ["SFull", "SOther"], ["SOther", "SFull"],
  ["SPart", "SOther"], ["SOther", "SPart"], ["SOther", "SOther2"]
]

const toStaging = (s: St) => {
  switch (s) {
    case "SFull":
      return staging(cur, [ChunkToken("t1"), ChunkToken("t2")])
    case "SPart":
      return staging(cur, [ChunkToken("t1")])
    case "SOther":
      return staging(oth, [])
    case "SOther2":
      return staging(oth2, [])
    default: {
      const unreachable: never = s
      return unreachable
    }
  }
}

const toObj = (o: Ob): ObjectObs => {
  switch (o) {
    case "ONone":
      return ObjectObs.NoObject()
    case "OOk1":
      return ObjectObs.HasObject({ version: v1, vouching: Vouching.Vouched({ report: report(total) }) })
    case "OOk2":
      return ObjectObs.HasObject({ version: v2, vouching: Vouching.Vouched({ report: report(total) }) })
    case "OBad1":
      return ObjectObs.HasObject({ version: v1, vouching: Vouching.Vouched({ report: report(12) }) })
    case "OUnv1":
      return ObjectObs.HasObject({ version: v1, vouching: Vouching.Unvouchable() })
    case "ONyv1":
      return ObjectObs.HasObject({ version: v1, vouching: Vouching.NotYetVouched() })
    default: {
      const unreachable: never = o
      return unreachable
    }
  }
}

/** One point of the domain. Receipts only exist for an assembled or cleared
 *  goal, as the Asset type requires. */
interface P {
  readonly g: G
  readonly rc: boolean
  readonly seen: Option.Option<readonly [ReadonlyArray<St>, Ob]>
  readonly budget: Attempts
  readonly pw: boolean
}

const domain: ReadonlyArray<P> = allG.flatMap((g) =>
  [false, true]
    .filter((rc) => !rc || g === "GDone" || g === "GClear")
    .flatMap((rc) =>
      [Option.none(), ...stagingLists.flatMap((ss) => allOb.map((o) => Option.some<readonly [ReadonlyArray<St>, Ob]>([ss, o])))].flatMap((seen) =>
        budgets.flatMap((budget) => [false, true].map((pw): P => ({ g, rc, seen, budget, pw })))
      )
    )
)

const toAsset = (p: P): Asset => {
  const common = {
    seen: Option.match(p.seen, {
      onNone: () => Seen.Unseen(),
      onSome: ([ss, o]) => Seen.Seen({ observed: observed(ss.map(toStaging), toObj(o)) })
    }),
    budget: p.budget,
    backoffAt: PosInt(1),
    authorised: p.pw ? [new Write({ epoch: Int(1), deadline: Int(200) })] : []
  }
  const vouch = p.rc ? Vouch.HasReceipt({ bound }) : Vouch.NoReceipt()
  const ongoing = Outcome.Ongoing()
  const input = ((): AssetInput => {
    switch (p.g) {
      case "GClear":
        return {
          ...common,
          goal: Goal.Clear(),
          outcome: Outcome.Ended({ ending: Ending.Failed({ fault: Fault.Unavailable() }) }),
          vouch
        }
      case "GAsmNone":
        return { ...common, goal: assemblingGoal(Option.none(), theChunks), outcome: ongoing, vouch: Vouch.NoReceipt() }
      case "GAsmCur":
        return { ...common, goal: assemblingGoal(Option.some(cur), theChunks), outcome: ongoing, vouch: Vouch.NoReceipt() }
      case "GDone":
        return { ...common, goal: assembledGoal(cur, theChunks), outcome: ongoing, vouch }
      default: {
        const unreachable: never = p.g
        return unreachable
      }
    }
  })()
  return Either.getOrThrowWith(makeAsset(input), () => new Error("the domain built an invalid asset"))
}

const env = new Env({
  now: Nat(100),
  cfg: new Config({
    maxAttempts: 3,
    backoff: valid(makeBackoff({ initialBackoff: PosInt(1), maxBackoff: PosInt(30), backoffMultiplier: PosInt(2) })),
    writeDeadline: Nat(60)
  })
})

// The table's guards, transcribed -------------------------------------------------

const guards = (p: P): ReadonlyArray<Row> =>
  Option.match(p.seen, {
    onNone: (): ReadonlyArray<Row> => ["R0"],
    onSome: ([ss, o]) => {
      const { g, rc, pw } = p
      const listedCur = ss.some((s) => s === "SFull" || s === "SPart")
      const heldC = ss.includes("SFull")
      const others = ss.some((s) => s === "SOther" || s === "SOther2")
      const anyStg = ss.length > 0
      const noObj = o === "ONone"
      const objAtV1 = o === "OOk1" || o === "OBad1" || o === "OUnv1" || o === "ONyv1"
      const asm = g === "GAsmNone" || g === "GAsmCur"
      const table: ReadonlyArray<readonly [Row, boolean]> = [
        ["R1", g === "GAsmNone" && !rc && !anyStg && noObj],
        ["R2", g === "GAsmNone" && !rc && anyStg && noObj],
        ["R3", g === "GAsmCur" && !rc && listedCur && !others && noObj],
        ["R4", ((g === "GAsmCur" && listedCur) || (g === "GDone" && heldC)) && !rc && others && noObj],
        ["R5", g === "GAsmCur" && !rc && !listedCur && noObj],
        ["R6", asm && !rc && !noObj],
        ["R7", g === "GDone" && !rc && heldC && !others && noObj],
        ["R8", g === "GDone" && !rc && !heldC && noObj],
        ["R9", g === "GDone" && !rc && (o === "OOk1" || o === "OOk2")],
        ["R10", g === "GDone" && !rc && o === "OBad1"],
        ["R11", g === "GDone" && !rc && o === "OUnv1"],
        ["R12", g === "GDone" && !rc && o === "ONyv1"],
        ["R13", g === "GDone" && rc && objAtV1 && anyStg],
        ["R14", g === "GDone" && rc && objAtV1 && !anyStg],
        ["R15", g === "GDone" && rc && !objAtV1],
        ["R16", g === "GClear" && anyStg],
        ["R17", g === "GClear" && !anyStg && !noObj],
        ["R18", g === "GClear" && !anyStg && noObj && !pw],
        ["R19", g === "GClear" && !anyStg && noObj && pw]
      ]
      return table.filter(([, holds]) => holds).map(([r]) => r)
    }
  })

const show = (p: P): string =>
  `${p.g} rc=${p.rc} seen=${Option.match(p.seen, { onNone: () => "Unseen", onSome: ([ss, o]) => `[${ss.join(",")}] ${o}` })} budget=${p.budget} pw=${p.pw}`

test("K7: guards exhaustive, exclusive and followed at all 1320 points", () => {
  assert.equal(domain.length, 1320)
  const failures: Array<string> = []
  for (const p of domain) {
    const gs = guards(p)
    const d = reconcile(env, toAsset(p))
    const [only, ...rest] = gs
    if (only === undefined) failures.push(`no guard holds: ${show(p)}`)
    else if (rest.length > 0) failures.push(`guards overlap ${gs.join(",")}: ${show(p)}`)
    else if (d.row !== only) failures.push(`row ${d.row} taken where the table says ${only}: ${show(p)}`)
  }
  assert.deepEqual(failures.slice(0, 10), [])
})

test("K7: every row of the table is reached somewhere in the domain", () => {
  const reached = new Set(domain.map((p) => reconcile(env, toAsset(p)).row))
  assert.deepEqual(
    allRows.filter((r) => !reached.has(r)),
    []
  )
})

test("Step claims K0-K13 and Prog hold at all 1320 points of the guard domain", () => {
  const failures: Array<string> = []
  for (const p of domain) {
    const a = toAsset(p)
    const d = reconcile(env, a)
    for (const [name, claim] of Object.entries(stepClaims)) {
      if (!claim(a, d)) failures.push(`${name} fails at row ${d.row}: ${show(p)}`)
    }
  }
  assert.deepEqual(failures.slice(0, 10), [])
})
