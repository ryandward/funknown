// Generators for the reconciler's properties. assetArb's observations are
// independent of the asset, so they rarely list the goal's own staging area
// holding its chunks, or an object at the receipt's version with the
// assembled size. These build an observation from the asset, so every row of
// the table is reached often, and mix in the independent ones as well.
import { FastCheck as fc, Option } from "effect"
import { type Version } from "../src/Kernel/Bound.js"
import {
  type Asset,
  type Env,
  type Goal,
  ObjectObs,
  Seen,
  type Staging,
  Vouching,
  assembledTotal,
  goalStaging,
  observed,
  staging,
  vouchSize,
  vouchVersion,
  withSeen
} from "../src/Kernel/Types.js"
import { type ChunkToken, chunkList } from "../src/Upload.js"
import { assetArb, envArb, reportArb, seenArb, stagingRefArb, versionArb } from "./arb.js"

const goalTokens = (g: Goal): ReadonlyArray<ChunkToken> =>
  g._tag === "Keep" ? chunkList(g.assembly.chunks).map((c) => c.ctoken) : []

/** A staging listing for this asset: its own area holding every chunk, its
 *  own area missing one, or some other area (which may share a name). */
const stagingFor = (a: Asset): fc.Arbitrary<Staging> => {
  const toks = goalTokens(a.goal)
  const other = stagingRefArb.map((r) => staging(r, []))
  return Option.match(goalStaging(a.goal), {
    onNone: () => other,
    onSome: (own) =>
      fc.oneof(
        fc.constant(staging(own, toks)),
        fc.nat({ max: Math.max(0, toks.length - 1) }).map((i) => staging(own, toks.filter((_, j) => j !== i))),
        other
      )
  })
}

/** An object for this asset: none, or one at the receipt's version or another,
 *  vouched at the assembled size, the receipt's size or any size, or not
 *  vouchable, or not yet vouched. */
const objectFor = (a: Asset): fc.Arbitrary<ObjectObs> => {
  const versions: fc.Arbitrary<Version> = Option.match(vouchVersion(a.vouch), {
    onNone: () => versionArb,
    onSome: (v) => fc.oneof(fc.constant(v), versionArb)
  })
  const sizes = [assembledTotal(a.goal), vouchSize(a.vouch)].flatMap((o) => Option.toArray(o))
  const sizeArb = sizes.length > 0 ? fc.oneof(fc.constantFrom(...sizes), fc.nat({ max: 60 })) : fc.nat({ max: 60 })
  const vouching = fc.oneof(
    reportArb(sizeArb).map((report) => Vouching.Vouched({ report })),
    fc.constant(Vouching.Unvouchable()),
    fc.constant(Vouching.NotYetVouched())
  )
  return fc.oneof(
    fc.constant(ObjectObs.NoObject()),
    fc.tuple(versions, vouching).map(([version, v]) => ObjectObs.HasObject({ version, vouching: v }))
  )
}

const seenFor = (a: Asset): fc.Arbitrary<Seen> =>
  fc.oneof(
    { arbitrary: fc.constant(Seen.Unseen()), weight: 1 },
    {
      arbitrary: fc
        .tuple(fc.array(stagingFor(a), { maxLength: 3 }), objectFor(a))
        .map(([ss, obj]) => Seen.Seen({ observed: observed(ss, obj) })),
      weight: 6
    },
    { arbitrary: seenArb, weight: 1 }
  )

/** An asset, observed in a way that relates to it, and an environment. */
export const caseArb: fc.Arbitrary<readonly [Asset, Env]> = fc
  .tuple(assetArb, envArb)
  .chain(([a, env]) => seenFor(a).map((seen) => [withSeen(a, seen), env] satisfies readonly [Asset, Env]))
