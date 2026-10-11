// The wire schemas in src/Wire.ts against the Haskell dump and the Haskell source.
//
// 1. Every Env, Asset, Observation and Decision in the dump parses, and every
//    asset splits into a PersistedState and an Observation that join back
//    into the same asset.
// 2. Every asset and env zod accepts is one the port's producers accept too:
//    building it through them and writing it back gives the same JSON.
// 3. Every tag schema accepts exactly the constructors its Haskell `data`
//    declaration names.
// 4. Every object the JSON Schema describes refuses an excess key, and every
//    integer it describes refuses a fraction, in every message.
// 5. For each refinement, a record mutated to break only that refinement is
//    refused, by PersistedState and by Asset, for that reason; where the port
//    has a producer that checks the same refinement, it refuses it as well.
// 6. What the shell keeps between runs (Stored, keep) holds the decision's
//    wait and its state, which the asset without seen can't give back.
// 7. A failed call is null, never a partial answer: null leaves the asset
//    alone (K11), and each partial answer changes it for good.
// 8. The JSON Schema files are exactly what the zod schemas generate.
import assert from "node:assert/strict"
import { existsSync, readFileSync } from "node:fs"
import { dirname } from "node:path"
import { test } from "node:test"
import { z } from "zod"
import { reconcile } from "../src/Kernel/Reconcile.js"
import { type State as PortState, stateOf as portStateOf } from "../src/Kernel/Types.js"
import {
  Asset,
  Cmd,
  Decision,
  Ending,
  Env,
  Fault,
  Observation,
  Observed,
  PersistedState,
  State,
  Stored,
  Vouching,
  checksumMax,
  decimalAtMost,
  jsonSchemaText,
  keep,
  kernelAsset,
  messages,
  persisted,
  rows,
  stateOf
} from "../src/Wire.js"
import { encAsset, encDecision, encEnv, encFault, type Json, toAsset, toEnv } from "./dumpCodec.js"

const fixture = readFileSync(`${import.meta.dirname}/../../test/fixtures/haskell-dump.jsonl`, "utf8")
  .split("\n")
  .filter((l) => l.length > 0)

// The dump's records, with the four messages where they occur. The store
// model and the adversary's moves are test-only, so their fields stay loose.
const ModelJ = z.strictObject({ obs: Observed, fresh: z.string(), version: z.string(), vouching: z.unknown() })
const RunOut = z.strictObject({ asset: Asset, model: ModelJ, row: z.enum(rows) })
const Record = z.discriminatedUnion("kind", [
  z.strictObject({ kind: z.literal("step"), src: z.string(), env: Env, asset: Asset, out: Decision }),
  z.strictObject({ kind: z.literal("round"), env: Env, asset: Asset, model: ModelJ, out: RunOut }),
  z.strictObject({
    kind: z.literal("converge"),
    env: Env,
    asset: Asset,
    model: ModelJ,
    allowance: z.int(),
    moves: z.array(z.unknown()),
    out: RunOut
  })
])
type Record = z.output<typeof Record>

// Parsed line by line, so a line zod refuses fails the first test below and
// not the whole file.
const parsed = fixture.map((l) => Record.safeParse(JSON.parse(l)))
const records: ReadonlyArray<Record> = parsed.flatMap((p) => (p.success ? [p.data] : []))
const assetsOf = (r: Record): ReadonlyArray<Asset> => (r.kind === "step" ? [r.asset, r.out.next] : [r.asset, r.out.asset])
const allAssets = records.flatMap(assetsOf)
const steps = records.flatMap((r) => (r.kind === "step" ? [r] : []))

test("wire: every record in the Haskell dump parses with the four schemas", () => {
  const refused = parsed.flatMap((p, i) => (p.success ? [] : [`line ${i + 1}: ${JSON.stringify(p.error.issues).slice(0, 300)}`]))
  assert.deepEqual({ refused: refused.length, first: refused.slice(0, 3) }, { refused: 0, first: [] })
  const counts = { step: 0, round: 0, converge: 0 }
  for (const r of records) counts[r.kind] += 1
  assert.ok(counts.step >= 2820 && counts.round > 5000 && counts.converge >= 1500, JSON.stringify(counts))
  assert.equal(allAssets.length, 2 * records.length)
})

test("wire: every asset splits into a PersistedState and an Observation that join back into it", () => {
  for (const a of allAssets) {
    const state = PersistedState.parse(persisted(a))
    const seen = Observation.parse(a.seen)
    assert.deepEqual(kernelAsset(state, seen), a)
  }
})

test("wire: every asset and env zod accepts goes through the port's producers and back unchanged", () => {
  let n = 0
  fixture.forEach((line, i) => {
    const raw: unknown = JSON.parse(line)
    const p = parsed[i]
    if (p === undefined || !p.success) throw new Error(`zod refused line ${i + 1}`)
    const r = p.data
    const rawOf = z.looseObject({ env: z.unknown(), asset: z.unknown(), out: z.unknown() }).parse(raw)
    assert.equal(JSON.stringify(encEnv(toEnv(r.env))), JSON.stringify(rawOf.env), `line ${i + 1}: env`)
    assert.equal(JSON.stringify(encAsset(toAsset(r.asset))), JSON.stringify(rawOf.asset), `line ${i + 1}: asset`)
    const outAsset = r.kind === "step" ? r.out.next : r.out.asset
    const rawOutAsset =
      r.kind === "step" ? z.looseObject({ next: z.unknown() }).parse(rawOf.out).next : z.looseObject({ asset: z.unknown() }).parse(rawOf.out).asset
    assert.equal(JSON.stringify(encAsset(toAsset(outAsset))), JSON.stringify(rawOutAsset), `line ${i + 1}: out asset`)
    n += 1
  })
  assert.equal(n, fixture.length)
})

test("wire: the JSON Schema files are what the zod schemas generate", () => {
  const names = ["PersistedState", "Observation", "Env", "Decision", "Stored"] as const
  assert.deepEqual(Object.keys(messages), [...names])
  for (const name of names) {
    const onDisk = readFileSync(`${import.meta.dirname}/../../src/wire/${name}.schema.json`, "utf8")
    assert.equal(onDisk, jsonSchemaText(name), `src/wire/${name}.schema.json is stale; run npm run schema`)
  }
})

test("wire: the checksum pattern accepts exactly the numerals 0 .. 2^64 - 1, without leading zeros", () => {
  const re = new RegExp(decimalAtMost(checksumMax))
  const max = BigInt(checksumMax)
  const probes: Array<bigint> = [0n, 1n, 9n, 10n, 99n, 2n ** 32n, 2n ** 53n, 2n ** 63n, max - 1n, max, max + 1n, 2n ** 65n, 10n ** 19n, 10n ** 20n]
  // Every value one digit change away from the bound, on both sides.
  for (let i = 0; i < checksumMax.length; i++)
    for (let d = 0; d <= 9; d++) probes.push(BigInt(checksumMax.slice(0, i) + String(d) + checksumMax.slice(i + 1)))
  for (const v of probes) assert.equal(re.test(v.toString()), v <= max, `pattern on ${v}`)
  for (const s of ["", "00", "07", "-1", "+1", "1e3", " 1", "1.0", "0x10"]) assert.equal(re.test(s), false, `pattern on "${s}"`)
})

// Tags against the Haskell ------------------------------------------------------------

/** The file at `rel` in the nearest directory above this test that has it. */
const findUp = (rel: string): string => {
  let dir = import.meta.dirname
  for (;;) {
    if (existsSync(`${dir}/${rel}`)) return `${dir}/${rel}`
    const up = dirname(dir)
    if (up === dir) throw new Error(`no ${rel} above ${import.meta.dirname}`)
    dir = up
  }
}

/** The constructor names of `data <type>` in a funknown-core module, in order. */
const constructorsOf = (module: string, type: string): ReadonlyArray<string> => {
  const lines = readFileSync(findUp(`funknown-core/src/Funknown/${module}`), "utf8").split("\n")
  const start = lines.findIndex((l) => new RegExp(`^data ${type}\\b`).test(l))
  if (start < 0) throw new Error(`no data ${type} in ${module}`)
  let text = ""
  for (let i = start; i < lines.length; i++) {
    const l = lines[i] ?? ""
    if ((i > start && !/^\s/.test(l)) || /^\s*deriving\b/.test(l)) break
    text += ` ${l.replace(/--.*$/, "")}`
  }
  return text
    .slice(text.indexOf("=") + 1)
    .replace(/\{[^}]*\}/g, " ")
    .split("|")
    .map((alt) => alt.trim().split(/\s+/)[0] ?? "")
}

/** The tags a union schema's JSON Schema names on `t`, member by member. */
const TagsJS = z.looseObject({
  anyOf: z.array(z.looseObject({ properties: z.looseObject({ t: z.looseObject({ const: z.string().optional(), enum: z.array(z.string()).optional() }) }) }))
})
const tagsOf = (schema: z.ZodType): ReadonlyArray<string> =>
  TagsJS.parse(z.toJSONSchema(schema)).anyOf.flatMap((m) => (m.properties.t.const !== undefined ? [m.properties.t.const] : (m.properties.t.enum ?? [])))
const GoalTagsJS = z.looseObject({
  anyOf: z.array(z.looseObject({ properties: z.looseObject({ goal: z.looseObject({ properties: z.looseObject({ t: z.looseObject({ const: z.string() }) }) }) }) }))
})

test("wire: every tag schema accepts exactly the constructors its Haskell data declaration names", () => {
  const sorted = (xs: ReadonlyArray<string>) => [...xs].sort()
  // A payload for each constructor that carries one.
  const payload: { readonly [t: string]: object } = {
    SourceAnswered: { status: 500 },
    Failed: { fault: { t: "StateLost" } },
    FAILED: { fault: { t: "StateLost" } },
    Vouched: { checksum: "1", size: 1 },
    DoDiscard: { ref: "r" },
    DoRemove: { version: "v" }
  }
  const tagged: ReadonlyArray<{ readonly name: string; readonly schema: z.ZodType; readonly haskell: ReadonlyArray<string> }> = [
    { name: "Fault", schema: Fault, haskell: constructorsOf("Fault.hs", "Fault") },
    { name: "Ending", schema: Ending, haskell: constructorsOf("Kernel/Types.hs", "Ending") },
    { name: "Vouching", schema: Vouching, haskell: constructorsOf("Kernel/Types.hs", "Vouching") },
    { name: "Cmd", schema: Cmd, haskell: constructorsOf("Kernel/Types.hs", "Cmd") },
    { name: "State", schema: State, haskell: constructorsOf("Kernel/Types.hs", "State") }
  ]
  for (const { name, schema, haskell } of tagged) {
    assert.ok(haskell.length >= 3, `${name}: read ${JSON.stringify(haskell)}`)
    assert.deepEqual(sorted(tagsOf(schema)), sorted(haskell), `${name}: the zod tags are not the Haskell constructors`)
    for (const t of haskell) assert.equal(schema.safeParse({ t, ...payload[t] }).success, true, `${name}: ${t} is refused`)
    assert.equal(schema.safeParse({ t: "Bogus" }).success, false, `${name}: an unknown tag is accepted`)
  }
  assert.deepEqual([...rows], constructorsOf("Kernel/Types.hs", "Row"))
  // The wire flattens Keep's Assembly into the goal's tag.
  const goalTags = GoalTagsJS.parse(z.toJSONSchema(PersistedState)).anyOf.map((m) => m.properties.goal.properties.t.const)
  const haskellGoals = [...constructorsOf("Kernel/Types.hs", "Goal").filter((c) => c !== "Keep"), ...constructorsOf("Kernel/Types.hs", "Assembly")]
  assert.deepEqual(sorted(goalTags), sorted(haskellGoals))
  // Every fault, in a state the client side can persist.
  const failed = (fault: object) => ({ goal: { t: "Clear" }, outcome: { t: "Failed", fault }, vouch: null, budget: 0, backoffAt: 1, authorised: [] })
  for (const t of constructorsOf("Fault.hs", "Fault"))
    assert.equal(PersistedState.safeParse(failed({ t, ...payload[t] })).success, true, `PersistedState refuses Failed ${t}`)
})

// Every object and every integer ---------------------------------------------------------

type Seg = string | number
type Path = ReadonlyArray<Seg>

/** The objects and integers a JSON Schema describes, as paths; "*" is any array index. */
const schemaPaths = (js: unknown, path: Path = [], out = { objects: new Set<string>(), integers: new Set<string>() }) => {
  const S = z.looseObject({
    anyOf: z.array(z.unknown()).optional(),
    type: z.union([z.string(), z.array(z.string())]).optional(),
    properties: z.record(z.string(), z.unknown()).optional(),
    prefixItems: z.array(z.unknown()).optional(),
    items: z.unknown().optional()
  })
  // A boolean schema (zod writes `items: false` after a tuple's prefixItems) describes nothing.
  if (typeof js === "boolean") return out
  const s = S.parse(js)
  const types = s.type === undefined ? [] : typeof s.type === "string" ? [s.type] : s.type
  for (const m of s.anyOf ?? []) schemaPaths(m, path, out)
  if (types.includes("object")) {
    out.objects.add(JSON.stringify(path))
    for (const [k, v] of Object.entries(s.properties ?? {})) schemaPaths(v, [...path, k], out)
  }
  if (types.includes("array")) {
    ;(s.prefixItems ?? []).forEach((v, i) => schemaPaths(v, [...path, i], out))
    if (s.items !== undefined) schemaPaths(s.items, [...path, "*"], out)
  }
  if (types.includes("integer") || types.includes("number")) out.integers.add(JSON.stringify(path))
  return out
}

const isRecord = (v: unknown): v is { readonly [k: string]: unknown } => typeof v === "object" && v !== null && !Array.isArray(v)

/** Every object and every number in a value, by path. */
const valuePaths = (v: unknown, path: Path = [], out: Array<{ kind: "object" | "integer"; path: Path }> = []) => {
  if (Array.isArray(v)) v.forEach((x: unknown, i) => valuePaths(x, [...path, i], out))
  else if (isRecord(v)) {
    out.push({ kind: "object", path })
    for (const [k, x] of Object.entries(v)) valuePaths(x, [...path, k], out)
  } else if (typeof v === "number") out.push({ kind: "integer", path })
  return out
}

const replaceAt = (v: unknown, path: Path, f: (x: unknown) => unknown): unknown => {
  const [h, ...rest] = path
  if (h === undefined) return f(v)
  if (Array.isArray(v)) return v.map((x: unknown, i) => (i === h ? replaceAt(x, rest, f) : x))
  if (isRecord(v)) return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, k === h ? replaceAt(x, rest, f) : x]))
  throw new Error(`no ${String(h)} in ${JSON.stringify(v)}`)
}

/** The schema path a value path stands for: array indices become "*" or stay a tuple position. */
const matches = (schemaPath: Path, valuePath: Path): boolean =>
  schemaPath.length === valuePath.length && schemaPath.every((s, i) => (s === "*" ? typeof valuePath[i] === "number" : s === valuePath[i]))

test("wire: every object refuses an excess key and every integer refuses a fraction, in every message", () => {
  const firstStep = steps[0]
  if (firstStep === undefined) throw new Error("no step in the dump")
  const samples: { readonly [K in keyof typeof messages]: ReadonlyArray<unknown> } = {
    PersistedState: allAssets.map(persisted),
    Observation: allAssets.flatMap((a) => (a.seen === null ? [] : [a.seen])),
    Env: records.map((r) => r.env),
    Decision: steps.map((r) => r.out),
    Stored: steps.map((r) => keep(r.env, r.out))
  }
  for (const name of Object.keys(messages) as Array<keyof typeof messages>) {
    const schema: z.ZodType = messages[name]
    const want = schemaPaths(z.toJSONSchema(schema))
    const wanted = [...[...want.objects].map((p) => ({ kind: "object", p })), ...[...want.integers].map((p) => ({ kind: "integer", p }))].map(
      ({ kind, p }) => ({ kind, path: z.array(z.union([z.string(), z.number()])).parse(JSON.parse(p)) })
    )
    // Keep a sample only when it reaches a schema path no kept sample has.
    const covered = new Set<number>()
    let mutants = 0
    for (const v of samples[name]) {
      const here = valuePaths(v)
      const adds = wanted.some((w, i) => !covered.has(i) && here.some((h) => h.kind === w.kind && matches(w.path, h.path)))
      if (!adds) continue
      wanted.forEach((w, i) => {
        if (here.some((h) => h.kind === w.kind && matches(w.path, h.path))) covered.add(i)
      })
      for (const h of here) {
        const m =
          h.kind === "object"
            ? replaceAt(v, h.path, (x) => (isRecord(x) ? { ...x, extra: 1 } : x))
            : replaceAt(v, h.path, (x) => (typeof x === "number" ? x + 0.5 : x))
        mutants += 1
        assert.equal(schema.safeParse(m).success, false, `${name}: accepts ${h.kind === "object" ? "an excess key" : "a fraction"} at ${JSON.stringify(h.path)}`)
      }
    }
    const missed = wanted.filter((_, i) => !covered.has(i)).map((w) => `${w.kind} ${JSON.stringify(w.path)}`)
    assert.deepEqual(missed, [], `${name}: no sample reaches these schema paths`)
    assert.ok(mutants > 0, name)
  }
})

// Negative controls -------------------------------------------------------------------

/** The text of every issue zod reports, nested union branches included. */
const refusal = (schema: z.ZodType, v: unknown): string => {
  const r = schema.safeParse(v)
  return r.success ? "" : JSON.stringify(r.error.issues)
}

/** zod refuses v, and one of its reasons mentions `why`. */
const refuses = (schema: z.ZodType, v: unknown, why: string, label: string): void => {
  const text = refusal(schema, v)
  assert.notEqual(text, "", `${label}: zod accepted it`)
  assert.ok(text.includes(why), `${label}: refused, but not for "${why}": ${text.slice(0, 400)}`)
}

/** The first asset in the dump that has the shape `pick` finds. */
const first = <T>(pick: (a: Asset) => T | undefined, what: string): T => {
  for (const a of allAssets) {
    const t = pick(a)
    if (t !== undefined) return t
  }
  throw new Error(`no ${what} in the dump`)
}

// Shapes the controls start from, found in the dump when a test first asks.
// Each one parses as it is, so a control that is refused was refused for its
// own mutation.
const findBases = () => {
  const assembledWithReceipt = first((a) => {
    if (a.goal.t !== "Assembled" || a.vouch === null || a.goal.chunks.list.length < 2) return undefined
    return { ...a, goal: a.goal, vouch: a.vouch }
  }, "assembled goal with a receipt and two chunks")
  const assembling = first((a) => (a.goal.t === "Assembling" && a.goal.chunks.list.length >= 2 ? { ...a, goal: a.goal } : undefined), "assembly with two chunks")
  const cleared = first((a) => (a.goal.t === "Clear" && a.outcome !== null ? { ...a, goal: a.goal, outcome: a.outcome } : undefined), "cleared goal")
  const seenWithObject = first((a) => {
    const s = a.seen
    if (s === null || s.object === null || s.object.vouching.t !== "Vouched" || s.stagings.length === 0) return undefined
    return { ...s, object: { ...s.object, vouching: s.object.vouching } }
  }, "observation with a vouched object and a staging area")
  const env = records[0]?.env
  const decision = steps[0]?.out
  if (env === undefined || decision === undefined) throw new Error("no env or decision in the dump")
  return { assembledWithReceipt, assembling, cleared, seenWithObject, env, decision }
}
type Bases = ReturnType<typeof findBases>
let cachedBases: Bases | undefined
const bases = (): Bases => (cachedBases ??= findBases())

test("wire controls: the starting shapes parse", () => {
  const { assembledWithReceipt, assembling, cleared, seenWithObject, env, decision } = bases()
  for (const a of [assembledWithReceipt, assembling, cleared]) assert.equal(refusal(Asset, a), "")
  assert.equal(refusal(Observation, seenWithObject), "")
  assert.equal(refusal(Env, env), "")
  assert.equal(refusal(Decision, decision), "")
})

const withChunks = (
  a: Bases["assembling"],
  limits: readonly [number, number, number, number, boolean],
  list: ReadonlyArray<readonly [number, string]>
) => ({ ...a, goal: { ...a.goal, chunks: { limits, list } } })

test("wire controls: each Asset refinement refuses its mutant, in PersistedState and Asset, and the port's producers refuse it too", () => {
  const { assembledWithReceipt, assembling, cleared, seenWithObject } = bases()
  const [, , maxChunks, maxSize, sealsEmpty] = assembling.goal.chunks.limits
  const controls: ReadonlyArray<{ label: string; v: Parameters<typeof toAsset>[0]; why: string; onSeen?: true }> = [
    {
      label: "an ending while the goal keeps the asset",
      v: { ...assembledWithReceipt, outcome: { t: "Deleted" } },
      why: "outcome"
    },
    { label: "a Clear goal with no ending", v: { ...cleared, outcome: null }, why: "outcome" },
    {
      label: "a receipt while assembling",
      v: { ...assembling, vouch: assembledWithReceipt.vouch },
      why: "vouch"
    },
    {
      label: "a receipt whose size is not the assembled length",
      v: { ...assembledWithReceipt, vouch: { ...assembledWithReceipt.vouch, size: assembledWithReceipt.vouch.size + 1 } },
      why: "the receipt's size is not the assembled length"
    },
    {
      label: "chunks past maxSize",
      v: withChunks(assembling, [1, 10, 4, 5, sealsEmpty], [[3, "b"], [3, "a"]]),
      why: "past maxSize"
    },
    {
      label: "more chunks than maxChunks",
      v: withChunks(assembling, [1, 10, 1, 100, sealsEmpty], [[3, "b"], [3, "a"]]),
      why: "past maxChunks"
    },
    {
      label: "a chunk past maxChunk",
      v: withChunks(assembling, [1, 10, 4, 100, sealsEmpty], [[11, "b"], [3, "a"]]),
      why: "past maxChunk"
    },
    {
      label: "a short chunk that is not the newest",
      v: withChunks(assembling, [4, 10, 4, 100, sealsEmpty], [[5, "b"], [3, "a"]]),
      why: "below minChunk"
    },
    {
      label: "maxChunk below minChunk",
      v: withChunks(assembling, [5, 4, maxChunks, maxSize, sealsEmpty], []),
      why: "maxChunk is below minChunk"
    },
    { label: "backoffAt 0", v: { ...assembling, backoffAt: 0 }, why: "backoffAt" },
    {
      label: "a receipt checksum of 2^64",
      v: { ...assembledWithReceipt, vouch: { ...assembledWithReceipt.vouch, checksum: "18446744073709551616" } },
      why: "checksum"
    },
    {
      label: "a negative receipt size",
      v: { ...cleared, vouch: { version: "v1", size: -1, checksum: "7" } },
      why: "size"
    },
    {
      label: "an observed object vouched with a negative size",
      v: { ...assembledWithReceipt, seen: { ...seenWithObject, object: { ...seenWithObject.object, vouching: { ...seenWithObject.object.vouching, size: -1 } } } },
      why: "size",
      onSeen: true
    }
  ]
  for (const c of controls) {
    refuses(Asset, c.v, c.why, c.label)
    if (c.onSeen === undefined) {
      const { seen: _seen, ...state } = c.v
      refuses(PersistedState, state, c.why, `${c.label} (persisted)`)
    }
    assert.throws(() => toAsset(c.v), `${c.label}: the port's producers accepted it`)
  }
})

test("wire controls: each bound zod states alone refuses its mutant", () => {
  const { assembledWithReceipt, assembling, seenWithObject, env, decision } = bases()
  const { seen: _seen, ...noSeen } = assembling
  const cases: ReadonlyArray<{ label: string; schema: z.ZodType; v: unknown; why: string }> = [
    { label: "budget 6", schema: Asset, v: { ...assembling, budget: 6 }, why: "budget" },
    { label: "a persisted state that carries seen", schema: PersistedState, v: { ...noSeen, seen: null }, why: "seen" },
    { label: "an asset with no seen", schema: Asset, v: noSeen, why: "seen" },
    { label: "an excess key on the asset", schema: Asset, v: { ...assembling, extra: 1 }, why: "extra" },
    { label: "an unknown goal tag", schema: Asset, v: { ...assembling, goal: { ...assembling.goal, t: "Sealed" } }, why: "goal" },
    { label: "a checksum with a leading zero", schema: Asset, v: { ...assembledWithReceipt, vouch: { ...assembledWithReceipt.vouch, checksum: "07" } }, why: "checksum" },
    { label: "a write epoch past 2^53", schema: Asset, v: { ...assembling, authorised: [[2 ** 53, 1]] }, why: "authorised" },
    { label: "a staging area with an excess key", schema: Observation, v: { ...seenWithObject, stagings: [{ ref: "r", tokens: [], extra: true }] }, why: "extra" },
    { label: "an unknown vouching tag", schema: Observation, v: { ...seenWithObject, object: { ...seenWithObject.object, vouching: { t: "Maybe" } } }, why: "vouching" },
    { label: "maxAttempts 0", schema: Env, v: { ...env, maxAttempts: 0 }, why: "maxAttempts" },
    { label: "maxAttempts 6", schema: Env, v: { ...env, maxAttempts: 6 }, why: "maxAttempts" },
    { label: "a negative now", schema: Env, v: { ...env, now: -1 }, why: "now" },
    { label: "initialBackoff past maxBackoff", schema: Env, v: { ...env, backoff: [5, 4, 2] }, why: "initialBackoff is past maxBackoff" },
    { label: "maxBackoff past 2^31", schema: Env, v: { ...env, backoff: [1, 2 ** 31 + 1, 2] }, why: "backoff" },
    { label: "a backoff multiplier of 0", schema: Env, v: { ...env, backoff: [1, 30, 0] }, why: "backoff" },
    { label: "a negative writeDeadline", schema: Env, v: { ...env, writeDeadline: -1 }, why: "writeDeadline" },
    { label: "a negative waitFor", schema: Decision, v: { ...decision, waitFor: -1 }, why: "waitFor" },
    { label: "an unknown command", schema: Decision, v: { ...decision, command: { t: "DoRetry" } }, why: "command" },
    { label: "a Discard naming nothing", schema: Decision, v: { ...decision, command: { t: "DoDiscard" } }, why: "ref" },
    { label: "row R20", schema: Decision, v: { ...decision, row: "R20" }, why: "row" }
  ]
  for (const c of cases) refuses(c.schema, c.v, c.why, c.label)
})

test("wire controls: an Env the port's producers refuse is one zod refuses", () => {
  const { env } = bases()
  const bad = [{ ...env, now: -1 }, { ...env, backoff: [5, 4, 2] as const }, { ...env, writeDeadline: -1 }]
  for (const e of bad) {
    assert.notEqual(refusal(Env, e), "", JSON.stringify(e))
    assert.throws(() => toEnv(e), `the port's producers accepted ${JSON.stringify(e)}`)
  }
})

test("wire controls: an Env whose now plus writeDeadline or maxBackoff passes 2^53 - 1 is refused, and the bound itself is accepted", () => {
  const { env } = bases()
  const max = Number.MAX_SAFE_INTEGER
  const why = "now plus writeDeadline or maxBackoff is past 2^53 - 1"
  refuses(Env, { ...env, now: max, writeDeadline: 1 }, why, "now + writeDeadline")
  refuses(Env, { ...env, now: max - 10, writeDeadline: 0, backoff: [1, 11, 2] }, why, "now + maxBackoff")
  assert.equal(refusal(Env, { ...env, now: max - 11, writeDeadline: 11, backoff: [1, 11, 2] }), "")
})

// Between runs: Stored and keep ---------------------------------------------------------

const encState = (s: PortState): Json => (s._tag === "FAILED" ? { t: s._tag, fault: encFault(s.fault) } : { t: s._tag })

test("wire: stateOf on the wire agrees with the port's stateOf on every asset in the dump", () => {
  for (const a of allAssets) assert.equal(JSON.stringify(stateOf(a)), JSON.stringify(encState(portStateOf(toAsset(a)))))
})

test("wire: keep holds every step's wait and state, which the asset without seen can't give back", () => {
  let deletedAtRest = 0
  for (const r of steps) {
    const s = keep(r.env, r.out)
    assert.equal(s.notBefore, r.env.now + r.out.waitFor)
    assert.deepEqual(s.asset, persisted(r.out.next))
    assert.deepEqual(s.state, stateOf(r.out.next))
    // R18 is a resting row: a scheduler may never run this asset again, so
    // the state it shows is the one kept here.
    if (r.out.row === "R18" && s.state.t === "DELETED") {
      deletedAtRest += 1
      assert.equal(stateOf(kernelAsset(s.asset, null)).t, "DELETING")
    }
  }
  assert.ok(deletedAtRest > 0, "no R18 step comes to rest DELETED")
  // R12 and R19 wait; a run that dropped notBefore would observe again at once.
  assert.ok(steps.some((r) => r.out.row === "R12" && r.out.waitFor > 0))
  assert.ok(steps.some((r) => r.out.row === "R19" && r.out.waitFor > 0))
})

test("wire controls: a Stored state that is not the asset's is refused", () => {
  const { assembledWithReceipt, cleared } = bases()
  const active = persisted(Asset.parse(assembledWithReceipt))
  const why = "the state is not one stateOf gives for the asset"
  refuses(Stored, { asset: active, notBefore: 0, state: { t: "CREATING" } }, why, "CREATING with a receipt")
  const failed = { ...persisted(Asset.parse(cleared)), outcome: { t: "Failed", fault: { t: "StateLost" } }, authorised: [] }
  refuses(Stored, { asset: failed, notBefore: 0, state: { t: "FAILED", fault: { t: "Expired" } } }, why, "FAILED with another fault")
  const deleted = { ...failed, outcome: { t: "Deleted" } }
  for (const t of ["DELETING", "DELETED"]) assert.equal(refusal(Stored, { asset: deleted, notBefore: 0, state: { t } }), "", t)
  refuses(Stored, { asset: { ...deleted, authorised: [[1, 2]] }, notBefore: 0, state: { t: "DELETED" } }, why, "DELETED with a write unreported")
})

// A failed call is null ---------------------------------------------------------------

/** The port's decision on a wire asset, written back on the wire. */
const decide = (env: Env, a: Asset): Decision => Decision.parse(encDecision(reconcile(toEnv(env), toAsset(a))))

test("wire: K11 on the Haskell dump, every step with no observation returns the asset unchanged, with an Observe and no alarm", () => {
  let n = 0
  for (const r of steps) {
    if (r.asset.seen !== null) continue
    n += 1
    assert.deepEqual(r.out.next, r.asset)
    assert.equal(r.out.command.t, "DoObserve")
    assert.equal(r.out.alarm, false)
  }
  assert.ok(n > 0)
})

const chunks = (list: ReadonlyArray<readonly [number, string]>) => ({ limits: [1, 100, 10, 1000, false] as const, list })
const asset = (fields: object) => Asset.parse({ outcome: null, vouch: null, budget: 3, backoffAt: 1, authorised: [], seen: null, ...fields })

test("wire: a failed call is null, never a partial answer; null leaves the asset alone and each partial answer changes it for good", () => {
  const { env } = bases()
  const object = { version: "v1", vouching: { t: "Vouched", checksum: "7", size: 3 } }
  const held = asset({ goal: { t: "Assembled", staging: "s1", chunks: chunks([[3, "a"]]) }, vouch: { version: "v1", size: 3, checksum: "7" } })
  const adopted = asset({ goal: { t: "Assembling", staging: "s1", chunks: chunks([[3, "a"]]) } })
  const sealed = asset({ goal: { t: "Assembled", staging: "s1", chunks: chunks([[3, "a"]]) } })
  const cases: ReadonlyArray<{ label: string; base: Asset; dressed: Observation; row: string }> = [
    { label: "the object read failed, dressed as no object", base: held, dressed: { stagings: [], object: null }, row: "R15" },
    { label: "the staging list failed, dressed as none", base: adopted, dressed: { stagings: [], object: null }, row: "R5" },
    { label: "the checksum read failed, dressed as Unvouchable", base: sealed, dressed: { stagings: [], object: { ...object, vouching: { t: "Unvouchable" } } }, row: "R11" },
    { label: "the checksum read failed, dressed as NotYetVouched", base: sealed, dressed: { stagings: [], object: { ...object, vouching: { t: "NotYetVouched" } } }, row: "R12" },
    { label: "the same, on the last attempt", base: { ...sealed, budget: 0 }, dressed: { stagings: [], object: { ...object, vouching: { t: "NotYetVouched" } } }, row: "R12" }
  ]
  for (const c of cases) {
    const blind = decide(env, { ...c.base, seen: null })
    assert.deepEqual(blind.next, { ...c.base, seen: null }, `${c.label}: null changed the asset`)
    assert.deepEqual([blind.command.t, blind.alarm, blind.row], ["DoObserve", false, "R0"], c.label)
    const d = decide(env, { ...c.base, seen: c.dressed })
    assert.equal(d.row, c.row, c.label)
    assert.notEqual(JSON.stringify(persisted(d.next)), JSON.stringify(persisted(c.base)), `${c.label}: the partial answer left the persisted state alone`)
    // An ending never changes (K8), and a spent attempt is never given back.
    assert.ok(d.next.outcome !== null || d.next.budget < c.base.budget, `${c.label}: neither ended nor spent`)
  }
})

test("wire: a producer's chunk makes a kept view wrong, and the kernel ends the asset on it", () => {
  const { env } = bases()
  const before = asset({ goal: { t: "Assembling", staging: "s1", chunks: chunks([[3, "a"]]) }, seen: { stagings: [{ ref: "s1", tokens: ["a"] }], object: null } })
  assert.equal(decide(env, before).row, "R3")
  // The producer stages chunk b and completes, between two runs.
  const after = { ...before, goal: { t: "Assembled" as const, staging: "s1", chunks: chunks([[2, "b"], [3, "a"]]) } }
  const kept = decide(env, Asset.parse(after))
  assert.deepEqual([kept.row, kept.next.outcome], ["R8", { t: "Failed", fault: { t: "StateLost" } }])
  const fresh = decide(env, Asset.parse({ ...after, seen: { stagings: [{ ref: "s1", tokens: ["b", "a"] }], object: null } }))
  assert.deepEqual([fresh.row, fresh.command.t, fresh.next.outcome], ["R7", "DoSeal", null])
})
