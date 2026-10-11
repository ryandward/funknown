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
import { Either, Match, Option, Schema } from "effect"
import { Fault } from "../src/Fault.js"
import { makeBackoff } from "../src/Http/Retry.js"
import { type Bound, Version, bind, boundReceipt, boundSize, boundVersion } from "../src/Kernel/Bound.js"
import { Move, converge } from "../src/Kernel/Converge.js"
import { Model, round, synced } from "../src/Kernel/Model.js"
import { reconcile } from "../src/Kernel/Reconcile.js"
import {
  type Asset,
  type AssetCommon,
  type AssetInput,
  type Cmd,
  Config,
  type Decision,
  Ending,
  Env,
  type Goal,
  Goal as GoalC,
  type ObjectObs,
  ObjectObs as ObjectObsC,
  type Observed,
  type Outcome,
  Outcome as OutcomeC,
  type Seen,
  Seen as SeenC,
  StagingRef,
  type Vouch,
  Vouch as VouchC,
  type Vouching,
  Vouching as VouchingC,
  Write,
  assembledGoal,
  assemblingGoal,
  makeAsset,
  observed,
  staging
} from "../src/Kernel/Types.js"
import { Int, Nat, PosInt } from "../src/Num.js"
import { ReceiptAlgorithm, checksumOf, checksumValue } from "../src/Store/Algorithm.js"
import { type ReceiptReport, checksum, receiptReport, reportChecksum, reportSize } from "../src/Store/Receipt.js"
import { Chunk, ChunkToken, type Chunks, type Limits, appendChunk, chunkList, emptyChunks, limits, limitsOf } from "../src/Upload.js"

// The JSON shapes Dump.hs writes ------------------------------------------------------

const LimitsJ = Schema.Tuple(Schema.Number, Schema.Number, Schema.Number, Schema.Number, Schema.Boolean)
const ChunksJ = Schema.Struct({ limits: LimitsJ, list: Schema.Array(Schema.Tuple(Schema.Number, Schema.String)) })
const GoalJ = Schema.Union(
  Schema.Struct({ t: Schema.Literal("Clear") }),
  Schema.Struct({ t: Schema.Literal("Assembling"), staging: Schema.NullOr(Schema.String), chunks: ChunksJ }),
  Schema.Struct({ t: Schema.Literal("Assembled"), staging: Schema.String, chunks: ChunksJ })
)

const plainFaults = {
  Expired: Fault.Expired(),
  FinalizeTimedOut: Fault.FinalizeTimedOut(),
  OutOfRange: Fault.OutOfRange(),
  TooLarge: Fault.TooLarge(),
  QuotaAtFinalize: Fault.QuotaAtFinalize(),
  Revoked: Fault.Revoked(),
  Empty: Fault.Empty(),
  CreationRefused: Fault.CreationRefused(),
  CreationInterrupted: Fault.CreationInterrupted(),
  StateLost: Fault.StateLost(),
  SizeMismatch: Fault.SizeMismatch(),
  ObjectWithoutReceipt: Fault.ObjectWithoutReceipt(),
  StoreRefusedUs: Fault.StoreRefusedUs(),
  Contradiction: Fault.Contradiction(),
  Unavailable: Fault.Unavailable(),
  SourceUnreachable: Fault.SourceUnreachable(),
  SourceChanged: Fault.SourceChanged()
} satisfies { readonly [K in Exclude<Fault["_tag"], "SourceAnswered">]: Fault }

const FaultJ = Schema.Union(
  Schema.Struct({ t: Schema.Literal("SourceAnswered"), status: Schema.Number }),
  Schema.Struct({
    t: Schema.Literal(
      "Expired", "FinalizeTimedOut", "OutOfRange", "TooLarge", "QuotaAtFinalize", "Revoked", "Empty",
      "CreationRefused", "CreationInterrupted", "StateLost", "SizeMismatch", "ObjectWithoutReceipt",
      "StoreRefusedUs", "Contradiction", "Unavailable", "SourceUnreachable", "SourceChanged"
    )
  })
)
const EndingJ = Schema.Union(
  Schema.Struct({ t: Schema.Literal("Deleted") }),
  Schema.Struct({ t: Schema.Literal("Cancelled") }),
  Schema.Struct({ t: Schema.Literal("Failed"), fault: FaultJ })
)
const VouchingJ = Schema.Union(
  Schema.Struct({ t: Schema.Literal("Vouched"), checksum: Schema.String, size: Schema.Number }),
  Schema.Struct({ t: Schema.Literal("Unvouchable") }),
  Schema.Struct({ t: Schema.Literal("NotYetVouched") })
)
const ObservedJ = Schema.Struct({
  stagings: Schema.Array(Schema.Struct({ ref: Schema.String, tokens: Schema.Array(Schema.String) })),
  object: Schema.NullOr(Schema.Struct({ version: Schema.String, vouching: VouchingJ }))
})
const AssetJ = Schema.Struct({
  goal: GoalJ,
  outcome: Schema.NullOr(EndingJ),
  seen: Schema.NullOr(ObservedJ),
  vouch: Schema.NullOr(Schema.Struct({ version: Schema.String, size: Schema.Number, checksum: Schema.String })),
  budget: Schema.Literal(0, 1, 2, 3, 4, 5),
  backoffAt: Schema.Number,
  authorised: Schema.Array(Schema.Tuple(Schema.Number, Schema.Number))
})
const EnvJ = Schema.Struct({
  now: Schema.Number,
  maxAttempts: Schema.Literal(1, 2, 3, 4, 5),
  backoff: Schema.Tuple(Schema.Number, Schema.Number, Schema.Number),
  writeDeadline: Schema.Number
})
const ModelJ = Schema.Struct({ obs: ObservedJ, fresh: Schema.String, version: Schema.String, vouching: VouchingJ })
const MoveJ = Schema.Union(
  Schema.Struct({ t: Schema.Literal("Drop", "LateWrite", "Lapse", "Complete") }),
  Schema.Struct({ t: Schema.Literal("Append"), token: Schema.String, n: Schema.Number }),
  Schema.Struct({ t: Schema.Literal("Abandon"), ending: EndingJ })
)
const RecordJ = Schema.Union(
  Schema.Struct({ kind: Schema.Literal("step"), src: Schema.String, env: EnvJ, asset: AssetJ, out: Schema.Unknown }),
  Schema.Struct({ kind: Schema.Literal("round"), env: EnvJ, asset: AssetJ, model: ModelJ, out: Schema.Unknown }),
  Schema.Struct({
    kind: Schema.Literal("converge"),
    env: EnvJ,
    asset: AssetJ,
    model: ModelJ,
    allowance: Schema.Number,
    moves: Schema.Array(MoveJ),
    out: Schema.Unknown
  })
)
type RecordJ = typeof RecordJ.Type
const decodeRecord = Schema.decodeUnknownSync(Schema.parseJson(RecordJ))

// Building the inputs through the TypeScript producers ----------------------------------

/** A value the input describes validly; None means the dump and the port
 *  disagree about what is a valid input, which the test reports. */
const must = <A>(o: Option.Option<A>, what: string): A =>
  Option.getOrThrowWith(o, () => new Error(`the port refuses an input the Haskell accepted: ${what}`))

const toLimits = ([a, b, c, d, e]: typeof LimitsJ.Type): Limits =>
  must(limits({ minChunk: PosInt(a), maxChunk: PosInt(b), maxChunks: PosInt(c), maxSize: Nat(d), sealsEmpty: e }), "limits")

/** The list is newest first, so it is appended oldest first. */
const toChunks = (j: typeof ChunksJ.Type): Chunks =>
  [...j.list]
    .reverse()
    .reduce(
      (c, [n, t]) => must(appendChunk(c, new Chunk({ cbytes: PosInt(n), ctoken: ChunkToken(t) })), "appendChunk"),
      emptyChunks(toLimits(j.limits))
    )

const toFault = (j: typeof FaultJ.Type): Fault =>
  j.t === "SourceAnswered" ? Fault.SourceAnswered({ status: Int(j.status) }) : plainFaults[j.t]

const toEnding = (j: typeof EndingJ.Type): Ending => {
  switch (j.t) {
    case "Deleted":
      return Ending.Deleted()
    case "Cancelled":
      return Ending.Cancelled()
    case "Failed":
      return Ending.Failed({ fault: toFault(j.fault) })
    default: {
      const unreachable: never = j
      return unreachable
    }
  }
}

const report = (cs: string, size: number): ReceiptReport =>
  must(Option.flatMap(checksumOf(BigInt(cs)), (c) => receiptReport(ReceiptAlgorithm.Crc64Nvme(), c, size)), "report")

const toVouching = (j: typeof VouchingJ.Type): Vouching => {
  switch (j.t) {
    case "Vouched":
      return VouchingC.Vouched({ report: report(j.checksum, j.size) })
    case "Unvouchable":
      return VouchingC.Unvouchable()
    case "NotYetVouched":
      return VouchingC.NotYetVouched()
    default: {
      const unreachable: never = j
      return unreachable
    }
  }
}

const toObserved = (j: typeof ObservedJ.Type): Observed =>
  observed(
    j.stagings.map((s) => staging(StagingRef(s.ref), s.tokens.map(ChunkToken))),
    j.object === null
      ? ObjectObsC.NoObject()
      : ObjectObsC.HasObject({ version: Version(j.object.version), vouching: toVouching(j.object.vouching) })
  )

const toVouch = (j: (typeof AssetJ.Type)["vouch"]): Vouch => {
  if (j === null) return VouchC.NoReceipt()
  const b = bind(Nat(j.size), Version(j.version), report(j.checksum, j.size))
  return VouchC.HasReceipt({ bound: Either.getOrThrowWith(b, () => new Error("bind refused the receipt")) })
}

const toAsset = (j: typeof AssetJ.Type): Asset => {
  const common: AssetCommon = {
    seen: j.seen === null ? SeenC.Unseen() : SeenC.Seen({ observed: toObserved(j.seen) }),
    budget: j.budget,
    backoffAt: PosInt(j.backoffAt),
    authorised: j.authorised.map(([e, dl]) => new Write({ epoch: Int(e), deadline: Int(dl) }))
  }
  const vouch = toVouch(j.vouch)
  const input = ((): AssetInput => {
    const g = j.goal
    switch (g.t) {
      case "Clear":
        if (j.outcome === null) throw new Error("a Clear goal with no ending")
        return { ...common, goal: GoalC.Clear(), outcome: OutcomeC.Ended({ ending: toEnding(j.outcome) }), vouch }
      case "Assembling":
        if (j.outcome !== null || vouch._tag !== "NoReceipt") throw new Error("an assembly with an ending or a receipt")
        return {
          ...common,
          goal: assemblingGoal(g.staging === null ? Option.none() : Option.some(StagingRef(g.staging)), toChunks(g.chunks)),
          outcome: OutcomeC.Ongoing(),
          vouch
        }
      case "Assembled":
        if (j.outcome !== null) throw new Error("an assembled goal with an ending")
        return { ...common, goal: assembledGoal(StagingRef(g.staging), toChunks(g.chunks)), outcome: OutcomeC.Ongoing(), vouch }
      default: {
        const unreachable: never = g
        return unreachable
      }
    }
  })()
  return Either.getOrThrowWith(makeAsset(input), () => new Error("makeAsset refused the asset"))
}

const toEnv = (j: typeof EnvJ.Type): Env =>
  new Env({
    now: Nat(j.now),
    cfg: new Config({
      maxAttempts: j.maxAttempts,
      backoff: must(
        makeBackoff({ initialBackoff: PosInt(j.backoff[0]), maxBackoff: PosInt(j.backoff[1]), backoffMultiplier: PosInt(j.backoff[2]) }),
        "backoff"
      ),
      writeDeadline: Nat(j.writeDeadline)
    })
  })

const toModel = (j: typeof ModelJ.Type): Model =>
  new Model({ obs: toObserved(j.obs), fresh: StagingRef(j.fresh), version: Version(j.version), vouching: toVouching(j.vouching) })

const toMove = (j: typeof MoveJ.Type): Move => {
  switch (j.t) {
    case "Drop":
      return Move.Drop()
    case "LateWrite":
      return Move.LateWrite()
    case "Lapse":
      return Move.Lapse()
    case "Complete":
      return Move.Complete()
    case "Append":
      return Move.Append({ token: ChunkToken(j.token), n: Int(j.n) })
    case "Abandon":
      return Move.Abandon({ ending: toEnding(j.ending) })
    default: {
      const unreachable: never = j
      return unreachable
    }
  }
}

// Encoding the TypeScript results in Dump.hs's shape (same keys, same order) ----------

type Json = null | boolean | number | string | ReadonlyArray<Json> | { readonly [k: string]: Json }

const encLimits = (l: Limits): Json => [l.minChunk, l.maxChunk, l.maxChunks, l.maxSize, l.sealsEmpty]
const encChunks = (c: Chunks): Json => ({
  limits: encLimits(limitsOf(c)),
  list: chunkList(c).map((ch) => [ch.cbytes, ch.ctoken])
})
const encGoal = (g: Goal): Json =>
  Match.valueTags(g, {
    Clear: (): Json => ({ t: "Clear" }),
    Keep: ({ assembly }): Json =>
      Match.valueTags(assembly, {
        Assembling: ({ staging: s, chunks }): Json => ({
          t: "Assembling",
          staging: Option.getOrNull(s),
          chunks: encChunks(chunks)
        }),
        Assembled: ({ staging: s, chunks }): Json => ({ t: "Assembled", staging: s, chunks: encChunks(chunks) })
      })
  })
const encFault = (f: Fault): Json => (f._tag === "SourceAnswered" ? { t: f._tag, status: f.status } : { t: f._tag })
const encEnding = (e: Ending): Json =>
  Match.valueTags(e, {
    Deleted: (): Json => ({ t: "Deleted" }),
    Cancelled: (): Json => ({ t: "Cancelled" }),
    Failed: ({ fault }): Json => ({ t: "Failed", fault: encFault(fault) })
  })
const encOutcome = (o: Outcome): Json =>
  Match.valueTags(o, { Ongoing: (): Json => null, Ended: ({ ending }) => encEnding(ending) })
const encVouching = (v: Vouching): Json =>
  Match.valueTags(v, {
    Vouched: ({ report: r }): Json => ({ t: "Vouched", checksum: String(checksumValue(reportChecksum(r))), size: reportSize(r) }),
    Unvouchable: (): Json => ({ t: "Unvouchable" }),
    NotYetVouched: (): Json => ({ t: "NotYetVouched" })
  })
const encObj = (o: ObjectObs): Json =>
  Match.valueTags(o, {
    NoObject: (): Json => null,
    HasObject: ({ version, vouching }): Json => ({ version, vouching: encVouching(vouching) })
  })
const encObserved = (o: Observed): Json => ({
  stagings: o.stagings.map((s): Json => ({ ref: s.ref, tokens: [...s.tokens] })),
  object: encObj(o.object)
})
const encSeen = (s: Seen): Json => Match.valueTags(s, { Unseen: (): Json => null, Seen: ({ observed: o }) => encObserved(o) })
const encBound = (b: Bound): Json => ({
  version: boundVersion(b),
  size: boundSize(b),
  checksum: String(checksumValue(checksum(boundReceipt(b))))
})
const encVouch = (v: Vouch): Json => Match.valueTags(v, { NoReceipt: (): Json => null, HasReceipt: ({ bound }) => encBound(bound) })
const encAsset = (a: Asset): Json => ({
  goal: encGoal(a.goal),
  outcome: encOutcome(a.outcome),
  seen: encSeen(a.seen),
  vouch: encVouch(a.vouch),
  budget: a.budget,
  backoffAt: a.backoffAt,
  authorised: a.authorised.map((w): Json => [w.epoch, w.deadline])
})
const encCmd = (c: Cmd): Json =>
  Match.valueTags(c, {
    NoCmd: (): Json => ({ t: "NoCmd" }),
    DoObserve: (): Json => ({ t: "DoObserve" }),
    DoOpen: (): Json => ({ t: "DoOpen" }),
    DoSeal: (): Json => ({ t: "DoSeal" }),
    DoDiscard: ({ ref }): Json => ({ t: "DoDiscard", ref }),
    DoRemove: ({ version }): Json => ({ t: "DoRemove", version })
  })
const encDecision = (d: Decision): Json => ({
  next: encAsset(d.next),
  command: encCmd(d.command),
  waitFor: d.waitFor,
  alarm: d.alarm,
  row: d.row
})
const encModel = (m: Model): Json => ({ obs: encObserved(m.obs), fresh: m.fresh, version: m.version, vouching: encVouching(m.vouching) })

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
