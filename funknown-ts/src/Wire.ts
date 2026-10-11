// The wire format a shell speaks to the kernel, as zod schemas.
//
// The encoding is the one funknown-core/dump/Dump.hs already writes and the
// differential test already reads, so there is one encoding, not two.
//
//   kernel input   Env, and Asset = PersistedState + { seen: Observation }
//   kernel output  Decision
//   between runs   Stored = { asset: PersistedState, notBefore, state }
//
// One run of a shell, for one asset:
//
//   1. Load the Stored record. If env.now < notBefore, don't run yet.
//   2. Observe the store. An Observation is all or nothing: every call it
//      takes (listing the staging areas, reading the object, reading its
//      checksum) has to have answered. If any one of them failed, the
//      Observation is null. K11 (Reconcile.hs) proves that an asset with no
//      observation comes back unchanged, with an Observe and no alarm, so a
//      null costs nothing but the call. A failed call dressed as an answer is
//      not something the kernel can tell apart from the store's real answer:
//      `object: null` or `stagings: []` reads as the store having lost what
//      it held (R5, R8, R15, an ending that never changes, K8), `Unvouchable`
//      ends the asset (R11), and `NotYetVouched` spends an attempt (R12).
//   3. Decide: reconcile(env, kernelAsset(stored.asset, observation)).
//   4. Persist keep(env, decision) before performing decision.command, so a
//      crash after an R12 Observe can't hand the spent attempt back.
//   5. Perform the command no earlier than notBefore. Observe again on the
//      next run; never feed decision.next back without a fresh Observation.
//
// Why seen isn't kept. The progress lemma (Model.hs `round`) holds only when
// the asset's view is absent or exactly what the store holds (Coherent), and
// every round in the proof ends by observing again, after a NoCmd too. Two
// things the shell can't see change the store under a kept view: a late
// write landing, which Converge.hs's `landed` answers by making the view
// Unseen (LiquidHaskell refuses a `landed` that keeps it), and a producer
// staging a chunk, which leaves the kept view's token list short so R8 ends
// the asset as StateLost. Coherent doesn't compare token lists, so the proof
// doesn't see the second one; test/Wire.test.ts shows it on the port.
//
// Why state and notBefore are kept. stateOf reads seen: a deleted asset is
// DELETED only once the store was seen holding nothing, so the shell takes
// the state from decision.next before it drops seen. waitFor counts from
// this run's now, so the shell keeps now + waitFor; without it R12's backoff
// and R19's write wait would be lost across a restart.
//
// Every schema is strict (no excess keys), every tag is a literal, and every
// bound a Haskell refinement states is here: as a JSON Schema keyword where
// JSON Schema can say it, and as a zod refinement where it can't. The JSON
// Schema files in src/wire/ are generated from these schemas (`npm run
// schema`), and test/Wire.test.ts fails when they drift. Each refinement JSON
// Schema can't express is named in a `$comment` on the schema it belongs to.
//
// Integers are safe integers (|n| <= 2^53 - 1). Haskell's Int is 64 bits,
// but a JavaScript shell can't hold a larger value exactly, and JSON.parse
// would round it before zod saw it.
import { z } from "zod"

// Bounds the Haskell states -----------------------------------------------------

/** Funknown.Http.Retry.attemptCap. */
export const attemptCap = 5
/** Funknown.Http.Retry.backoffBound, 2^31. */
export const backoffBound = 2147483648
/** The largest checksum below 2^64 (Funknown.Store.Algorithm.Checksum). */
export const checksumMax = "18446744073709551615"

/**
 * A regular expression body that matches exactly the decimal numerals for
 * 0..bound, written as Haskell's `show` writes an Integer: no sign, no
 * leading zeros. JSON Schema can carry it as a `pattern`, so the checksum
 * bound is the one cross-digit bound both formats state the same way.
 */
export const decimalAtMost = (bound: string): string => {
  const n = bound.length
  const alts: Array<string> = ["0"]
  if (n >= 2) alts.push(n === 2 ? "[1-9]" : `[1-9][0-9]{0,${n - 2}}`)
  for (let i = 0; i < n; i++) {
    const d = Number(bound[i])
    const lo = i === 0 ? 1 : 0
    if (d - 1 >= lo) {
      const cls = d - 1 === lo ? `${lo}` : `[${lo}-${d - 1}]`
      const rest = n - i - 1
      alts.push(`${bound.slice(0, i)}${cls}${rest === 0 ? "" : rest === 1 ? "[0-9]" : `[0-9]{${rest}}`}`)
    }
  }
  alts.push(bound)
  return `^(${alts.join("|")})$`
}

const Int = z.int()
const Nat = z.int().min(0)
const Pos = z.int().min(1)
const Str = z.string()

/** A checksum as Dump.hs writes it: `show` of an Integer in [0, 2^64). */
const Checksum = z.string().regex(new RegExp(decimalAtMost(checksumMax)))

// Constructor names ----------------------------------------------------------------
//
// test/Wire.test.ts reads each `data` declaration in funknown-core and checks
// every tag schema below against it, both ways, so a tag can't go missing or
// be made up here unnoticed.

/** Funknown.Fault.Fault, every constructor but SourceAnswered, which carries a status. */
export const plainFaultTags = [
  "Expired",
  "FinalizeTimedOut",
  "OutOfRange",
  "TooLarge",
  "QuotaAtFinalize",
  "Revoked",
  "Empty",
  "CreationRefused",
  "CreationInterrupted",
  "StateLost",
  "SizeMismatch",
  "ObjectWithoutReceipt",
  "StoreRefusedUs",
  "Contradiction",
  "Unavailable",
  "SourceUnreachable",
  "SourceChanged"
] as const
/** Funknown.Kernel.Types.Row. */
export const rows = [
  "R0", "R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8", "R9",
  "R10", "R11", "R12", "R13", "R14", "R15", "R16", "R17", "R18", "R19"
] as const

// Upload: Limits and Chunks ---------------------------------------------------------

/**
 * Limits, positionally: [minChunk, maxChunk, maxChunks, maxSize, sealsEmpty].
 * Funknown.Upload.Limits: minChunk >= 1, maxChunk >= minChunk,
 * maxChunks >= 1, maxSize Nat.
 */
const Limits = z
  .tuple([Pos, Pos, Pos, Nat, z.boolean()])
  .refine(([minChunk, maxChunk]) => maxChunk >= minChunk, { message: "maxChunk is below minChunk" })
  .meta({ $comment: "Not expressed here: maxChunk (item 1) >= minChunk (item 0)." })

/** A chunk: [cbytes >= 1, token]. */
const Chunk = z.tuple([Pos, Str])

/**
 * Chunks, newest first. Funknown.Upload.Chunks: the total is within maxSize,
 * the count within maxChunks, every chunk within maxChunk, and every chunk
 * but the newest at least minChunk.
 */
const Chunks = z
  .strictObject({ limits: Limits, list: z.array(Chunk) })
  .superRefine((c, ctx) => {
    const [minChunk, maxChunk, maxChunks, maxSize] = c.limits
    const total = c.list.reduce((s, [n]) => s + n, 0)
    if (total > maxSize) ctx.addIssue({ code: "custom", path: ["list"], message: `total ${total} is past maxSize ${maxSize}` })
    if (c.list.length > maxChunks)
      ctx.addIssue({ code: "custom", path: ["list"], message: `${c.list.length} chunks is past maxChunks ${maxChunks}` })
    c.list.forEach(([n], i) => {
      if (n > maxChunk) ctx.addIssue({ code: "custom", path: ["list", i, 0], message: `chunk of ${n} is past maxChunk ${maxChunk}` })
      if (i > 0 && n < minChunk)
        ctx.addIssue({ code: "custom", path: ["list", i, 0], message: `an older chunk of ${n} is below minChunk ${minChunk}` })
    })
  })
  .meta({
    $comment:
      "Not expressed here: the sum of the chunk sizes <= maxSize, the count <= maxChunks, every size <= maxChunk, and every size but the first (newest) >= minChunk."
  })

/** The sum of a chunk list's sizes: Funknown.Upload.offsetOf. */
const offsetOf = (c: z.output<typeof Chunks>): number => c.list.reduce((s, [n]) => s + n, 0)

// Intent: Goal, Ending, Vouch ------------------------------------------------------

const ClearGoal = z.strictObject({ t: z.literal("Clear") })
const AssemblingGoal = z.strictObject({ t: z.literal("Assembling"), staging: Str.nullable(), chunks: Chunks })
const AssembledGoal = z.strictObject({ t: z.literal("Assembled"), staging: Str, chunks: Chunks })

/** Funknown.Fault.Fault, by constructor name; SourceAnswered carries its status. */
export const Fault = z.union([z.strictObject({ t: z.literal("SourceAnswered"), status: Int }), z.strictObject({ t: z.literal(plainFaultTags) })])

/** Funknown.Kernel.Types.Ending; an Outcome is an Ending or null (Ongoing). */
export const Ending = z.union([
  z.strictObject({ t: z.literal("Deleted") }),
  z.strictObject({ t: z.literal("Cancelled") }),
  z.strictObject({ t: z.literal("Failed"), fault: Fault })
])

/** A held receipt (HasReceipt Bound): the version it is bound to, its size and checksum. */
const Receipt = z.strictObject({ version: Str, size: Nat, checksum: Checksum })

// Observation ------------------------------------------------------------------

export const Vouching = z.union([
  z.strictObject({ t: z.literal("Vouched"), checksum: Checksum, size: Nat }),
  z.strictObject({ t: z.literal("Unvouchable") }),
  z.strictObject({ t: z.literal("NotYetVouched") })
])

/** Funknown.Kernel.Types.Observed: every staging area found, and the object or null. */
export const Observed = z.strictObject({
  stagings: z.array(z.strictObject({ ref: Str, tokens: z.array(Str) })),
  object: z.strictObject({ version: Str, vouching: Vouching }).nullable()
})

/**
 * What the shell observed this round, or null (Seen / Unseen). All or
 * nothing: if any call the observation takes failed, it is null.
 */
export const Observation = Observed.nullable().meta({
  title: "Observation",
  description:
    "What the shell observed of the store this round (Seen), or null (Unseen). All or nothing: when any call the observation takes failed, it is null, never a partial answer."
})

// The asset ----------------------------------------------------------------------

/** Funknown.Kernel.Types.Asset: a receipt held for an assembled goal has the assembled length. */
const receiptHasAssembledLength = (a: {
  readonly goal: z.output<typeof AssembledGoal>
  readonly vouch: z.output<typeof Receipt> | null
}): boolean => a.vouch === null || a.vouch.size === offsetOf(a.goal.chunks)
const receiptLengthIssue = { message: "the receipt's size is not the assembled length", path: ["vouch", "size"] }
const receiptLengthComment = "Not expressed here: when vouch is not null, vouch.size equals the sum of goal.chunks.list sizes."

const common = {
  budget: z.literal([0, 1, 2, 3, 4, 5]),
  backoffAt: Pos,
  authorised: z.array(z.tuple([Int, Int]))
}

// The three shapes of the Asset refinement (an ending exactly when the goal is
// Clear, no receipt while assembling), each a strict union member so JSON
// Schema carries both ties, plus the receipt-length refinement on the
// assembled one. Asset's members are these with `seen` added by safeExtend,
// which keeps strictness and refinements, so a member can't be strict or
// refined in PersistedState and not in Asset, or the other way round.
const clearMember = z.strictObject({ goal: ClearGoal, outcome: Ending, vouch: Receipt.nullable(), ...common })
const assemblingMember = z.strictObject({ goal: AssemblingGoal, outcome: z.null(), vouch: z.null(), ...common })
const assembledMember = z
  .strictObject({ goal: AssembledGoal, outcome: z.null(), vouch: Receipt.nullable(), ...common })
  .refine(receiptHasAssembledLength, receiptLengthIssue)
const receiptLengthMeta = { $comment: receiptLengthComment }

/** The asset as it lives between runs: every Asset field but `seen`. */
export const PersistedState = z
  .union([clearMember, assemblingMember, assembledMember.meta(receiptLengthMeta)])
  .meta({
    title: "PersistedState",
    description: "The asset between runs: goal, outcome, vouch, budget, backoffAt and authorised. seen is not kept; it lasts one round."
  })

const withSeen = { seen: Observation }

/** The kernel's Asset: the persisted state plus this round's observation. */
export const Asset = z
  .union([clearMember.safeExtend(withSeen), assemblingMember.safeExtend(withSeen), assembledMember.safeExtend(withSeen).meta(receiptLengthMeta)])
  .meta({ title: "Asset", description: "The kernel's input asset: a PersistedState with this round's Observation as seen." })

// Env --------------------------------------------------------------------------

/** Backoff, positionally: [initialBackoff, maxBackoff, backoffMultiplier]. */
const Backoff = z
  .tuple([Pos.max(backoffBound), Pos.max(backoffBound), Pos.max(backoffBound)])
  .refine(([initial, max]) => initial <= max, { message: "initialBackoff is past maxBackoff" })
  .meta({ $comment: "Not expressed here: initialBackoff (item 0) <= maxBackoff (item 1)." })

/**
 * Funknown.Kernel.Types.Env, with Config's fields inline as Dump.hs writes
 * them. The client side stores now + writeDeadline as a write's deadline
 * (Client/Upload.hs startWrite), and a shell stores now + waitFor, which is
 * at most now + maxBackoff (R12) or a stored deadline (R19); both sums have
 * to stay safe integers, or a run would write a state the next run refuses.
 */
export const Env = z
  .strictObject({
    now: Nat,
    maxAttempts: z.literal([1, 2, 3, 4, 5]),
    backoff: Backoff,
    writeDeadline: Nat
  })
  .refine((e) => e.now + Math.max(e.writeDeadline, e.backoff[1]) <= Number.MAX_SAFE_INTEGER, {
    message: "now plus writeDeadline or maxBackoff is past 2^53 - 1",
    path: ["now"]
  })
  .meta({
    title: "Env",
    description: "now is the shell's clock for this run; maxAttempts, backoff and writeDeadline are deployment config.",
    $comment: "Not expressed here: now + max(writeDeadline, maxBackoff (backoff item 1)) <= 2^53 - 1."
  })

// Decision -------------------------------------------------------------------------

export const Cmd = z.union([
  z.strictObject({ t: z.literal(["NoCmd", "DoObserve", "DoOpen", "DoSeal"]) }),
  z.strictObject({ t: z.literal("DoDiscard"), ref: Str }),
  z.strictObject({ t: z.literal("DoRemove"), version: Str })
])

export const Decision = z
  .strictObject({ next: Asset, command: Cmd, waitFor: Nat, alarm: z.boolean(), row: z.enum(rows) })
  .meta({
    title: "Decision",
    description: "The asset after the step, the one command to issue, the seconds to wait before issuing it, whether to tell an operator, and the row."
  })

export type PersistedState = z.output<typeof PersistedState>
export type Observation = z.output<typeof Observation>
export type Asset = z.output<typeof Asset>
export type Env = z.output<typeof Env>
export type Decision = z.output<typeof Decision>

// AIP-216 State ------------------------------------------------------------------

/** Funknown.Kernel.Types.State: what a client sees (R SS:AIP216-EnumValues-1 .. -3). */
export const State = z.union([
  z.strictObject({ t: z.literal(["CREATING", "ACTIVE", "CANCELLED", "DELETING", "DELETED"]) }),
  z.strictObject({ t: z.literal("FAILED"), fault: Fault })
])
export type State = z.output<typeof State>

const heldNothing = (s: Observation): boolean => s !== null && s.stagings.length === 0 && s.object === null

/**
 * Funknown.Kernel.Types.stateOf. The Asset schema ties an ending to a Clear
 * goal, so `outcome === null` is the Keep case.
 */
export const stateOf = (a: Asset): State => {
  if (a.outcome === null) return { t: a.vouch === null ? "CREATING" : "ACTIVE" }
  switch (a.outcome.t) {
    case "Failed":
      return { t: "FAILED", fault: a.outcome.fault }
    case "Cancelled":
      return { t: "CANCELLED" }
    case "Deleted":
      return { t: heldNothing(a.seen) && a.authorised.length === 0 ? "DELETED" : "DELETING" }
  }
}

const sameState = (x: State, y: State): boolean => JSON.stringify(x) === JSON.stringify(y)

/**
 * The states a persisted asset can show: stateOf under every observation.
 * Only DELETED versus DELETING depends on it, so this is the persisted
 * state's stateOf with that one choice left open.
 */
export const statesOf = (p: PersistedState): ReadonlyArray<State> => [
  stateOf({ ...p, seen: null }),
  stateOf({ ...p, seen: { stagings: [], object: null } })
]

// Between runs -------------------------------------------------------------------

/**
 * What the shell keeps of a run, until the next: the asset without seen,
 * the earliest time the decision's command may be performed and the next run
 * may observe (the Env clock's now + waitFor; R SS:RFC9110-10.2.3-1 is the
 * same "wait before a follow-up request"), and the AIP-216 state stateOf gave
 * on the decision's asset, before seen was dropped. The state is output only
 * (P SS:AIP216-OutputOnly-1); zod holds it to the asset, so the one thing it
 * carries that the asset doesn't is DELETED versus DELETING.
 */
export const Stored = z
  .strictObject({ asset: PersistedState, notBefore: Nat, state: State })
  .refine((s) => statesOf(s.asset).some((x) => sameState(x, s.state)), {
    message: "the state is not one stateOf gives for the asset",
    path: ["state"]
  })
  .meta({
    title: "Stored",
    description:
      "What the shell keeps between runs: the asset without seen, the earliest time the next command or observation may happen, and the AIP-216 state computed before seen was dropped.",
    $comment:
      "Not expressed here: state is stateOf the asset under some observation, so only DELETED versus DELETING is free, and DELETED needs an empty authorised list."
  })
export type Stored = z.output<typeof Stored>

// Joining and splitting ------------------------------------------------------------

/** The kernel's input asset for this round. Parsed, so the result is checked. */
export const kernelAsset = (state: PersistedState, seen: Observation): Asset => Asset.parse({ ...state, seen })

/** The asset part of what the shell keeps: everything but `seen`. */
export const persisted = (a: Asset): PersistedState =>
  PersistedState.parse({
    goal: a.goal,
    outcome: a.outcome,
    vouch: a.vouch,
    budget: a.budget,
    backoffAt: a.backoffAt,
    authorised: a.authorised
  })

/** What the shell keeps of a decision taken at env.now. Parsed, so the result is checked. */
export const keep = (env: Env, d: Decision): Stored =>
  Stored.parse({ asset: persisted(d.next), notBefore: env.now + d.waitFor, state: stateOf(d.next) })

/** The five messages, by the name of their JSON Schema file in src/wire/. */
export const messages = { PersistedState, Observation, Env, Decision, Stored } as const

/**
 * The text of src/wire/<name>.schema.json: draft 2020-12, generated from the
 * zod schema, so the two can't say different things where both can speak.
 * zod drops refinements here; each one left out is named in a `$comment`.
 */
export const jsonSchemaText = (name: keyof typeof messages): string =>
  `${JSON.stringify(z.toJSONSchema(messages[name], { target: "draft-2020-12" }), null, 2)}\n`
