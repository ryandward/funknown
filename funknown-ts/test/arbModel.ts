// Generators for the store model and the adversary. Each starting state is
// an asset from assetArb paired with a model built around its goal, so the
// rows that need a particular store (the goal's staging area holding every
// chunk for R7, a vouched object of the assembled length for R9, the
// receipt's version for R14) come up often, not by luck.
import { FastCheck as fc, Option } from "effect"
import { Int } from "../src/Num.js"
import { Move } from "../src/Kernel/Converge.js"
import { Model, type Synced, forgetting, observedNow } from "../src/Kernel/Model.js"
import {
  type Asset,
  Cmd,
  ObjectObs,
  type Staging,
  StagingRef,
  Vouching,
  assembledTotal,
  goalStaging,
  observed,
  staging,
  vouchVersion
} from "../src/Kernel/Types.js"
import { type Version } from "../src/Kernel/Bound.js"
import { ChunkToken, chunkList } from "../src/Upload.js"
import { assetArb, endingArb, reportArb, stagingRefArb, versionArb, vouchingArb } from "./arb.js"

const goalTokens = (a: Asset): ReadonlyArray<ChunkToken> =>
  a.goal._tag === "Keep" ? chunkList(a.goal.assembly.chunks).map((c) => c.ctoken) : []

const stagingArb = (a: Asset): fc.Arbitrary<Staging> => {
  const toks = goalTokens(a)
  const own = goalStaging(a.goal)
  const choices: Array<fc.Arbitrary<Staging>> = [stagingRefArb.map((r) => staging(r, []))]
  if (Option.isSome(own)) {
    const r = own.value
    choices.push(fc.constant(staging(r, toks)), fc.constant(staging(r, toks.slice(1))))
  }
  return fc.oneof(...choices)
}

/** A version, biased towards the one the asset's receipt names. */
const versionFor = (a: Asset): fc.Arbitrary<Version> =>
  Option.match(vouchVersion(a.vouch), {
    onNone: () => versionArb,
    onSome: (v) => fc.oneof(fc.constant(v), versionArb)
  })

/** How the store vouches, biased towards the assembled length. */
const vouchingFor = (a: Asset): fc.Arbitrary<Vouching> =>
  Option.match(assembledTotal(a.goal), {
    onNone: () => vouchingArb,
    onSome: (n) =>
      fc.oneof(reportArb(fc.constant(n)).map((report) => Vouching.Vouched({ report })), vouchingArb)
  })

const objectFor = (a: Asset): fc.Arbitrary<ObjectObs> =>
  fc.oneof(
    fc.constant(ObjectObs.NoObject()),
    fc.tuple(versionFor(a), vouchingFor(a)).map(([version, vouching]) => ObjectObs.HasObject({ version, vouching }))
  )

export const modelFor = (a: Asset): fc.Arbitrary<Model> =>
  fc
    .tuple(
      fc.array(stagingArb(a), { maxLength: 3 }),
      objectFor(a),
      fc.oneof(stagingRefArb, fc.constant(StagingRef("fresh"))),
      versionFor(a),
      vouchingFor(a)
    )
    .map(([ss, obj, fresh, version, vouching]) => new Model({ obs: observed(ss, obj), fresh, version, vouching }))

/** Any asset and model, with the asset's observation as generated (so the
 *  pair may or may not be Coherent). */
export const pairArb: fc.Arbitrary<readonly [Asset, Model]> = assetArb.chain((a) =>
  modelFor(a).map((m): readonly [Asset, Model] => [a, m])
)

/** Coherent starting states: the asset has either just observed the model,
 *  or holds no observation. */
export const syncedArb: fc.Arbitrary<Synced> = fc
  .tuple(pairArb, fc.integer({ min: 0, max: 3 }))
  .map(([[a, m], k]) => (k === 0 ? forgetting(a, m) : observedNow(a, m)))

export const cmdArb: fc.Arbitrary<Cmd> = fc.oneof(
  fc.constantFrom(Cmd.NoCmd(), Cmd.DoObserve(), Cmd.DoOpen(), Cmd.DoSeal()),
  fc.oneof(stagingRefArb, fc.constant(StagingRef("fresh"))).map((ref) => Cmd.DoDiscard({ ref })),
  versionArb.map((version) => Cmd.DoRemove({ version }))
)

export const moveArb: fc.Arbitrary<Move> = fc.oneof(
  fc.constantFrom(Move.Drop(), Move.LateWrite(), Move.Lapse(), Move.Complete()),
  fc
    .tuple(fc.constantFrom("a1", "a2", "a3"), fc.integer({ min: -1, max: 12 }))
    .map(([t, n]) => Move.Append({ token: ChunkToken(t), n: Int(n) })),
  endingArb.map((ending) => Move.Abandon({ ending }))
)

/** Long adversarial scripts. */
export const scriptArb: fc.Arbitrary<ReadonlyArray<Move>> = fc.array(moveArb, { maxLength: 300 })

/** The script, forever: an infinite Iterable when the script isn't empty. */
export function* forever(script: ReadonlyArray<Move>): Generator<Move, void, undefined> {
  if (script.length === 0) return
  for (;;) yield* script
}
