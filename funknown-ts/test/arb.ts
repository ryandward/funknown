// Generators for the property tests. Every value of an opaque type is built
// through the module's own producers (limits, appendChunk, receiptReport,
// vouch, bind, makeAsset), so a property over these generators is a
// property over what callers can actually reach. Later modules (Reconcile,
// Model, Converge, Client) can import these.
import { Either, FastCheck as fc, Option } from "effect"
import { Fault } from "../src/Fault.js"
import { type Attempts, type Backoff, type MaxAttempts, makeBackoff } from "../src/Http/Retry.js"
import { type Bound, Version, bind, boundSize } from "../src/Kernel/Bound.js"
import {
  type Asset,
  type AssetInput,
  Assembly,
  Config,
  Ending,
  Env,
  Goal,
  ObjectObs,
  Outcome,
  Seen,
  type StagingRef,
  StagingRef as mkStagingRef,
  Vouch,
  Vouching,
  Write,
  makeAsset,
  assemblingGoal,
  assembledGoal,
  observed,
  staging,
  assembledTotal
} from "../src/Kernel/Types.js"
import { Int, Nat, PosInt } from "../src/Num.js"
import { ReceiptAlgorithm, type Checksum, checksumBound, checksumOf } from "../src/Store/Algorithm.js"
import { type ReceiptReport, receiptReport } from "../src/Store/Receipt.js"
import { Chunk, ChunkToken, type Chunks, type Limits, appendChunk, emptyChunks, limits, offsetOf } from "../src/Upload.js"

/** Unwraps a value the generator built to be valid. A None here is a bug in
 *  the generator, not a finding, so it throws. */
export const valid = <A>(o: Option.Option<A>): A => Option.getOrThrowWith(o, () => new Error("generator built an invalid value"))

export const natArb = (max: number): fc.Arbitrary<Nat> => fc.integer({ min: 0, max }).map((n) => Nat(n))
export const posArb = (max: number): fc.Arbitrary<PosInt> => fc.integer({ min: 1, max }).map((n) => PosInt(n))

export const limitsArb: fc.Arbitrary<Limits> = fc
  .record({
    minChunk: fc.integer({ min: 1, max: 5 }),
    spread: fc.integer({ min: 0, max: 5 }),
    maxChunks: fc.integer({ min: 1, max: 5 }),
    maxSize: fc.integer({ min: 0, max: 60 }),
    sealsEmpty: fc.boolean()
  })
  .map((r) =>
    valid(
      limits({
        minChunk: PosInt(r.minChunk),
        maxChunk: PosInt(r.minChunk + r.spread),
        maxChunks: PosInt(r.maxChunks),
        maxSize: Nat(r.maxSize),
        sealsEmpty: r.sealsEmpty
      })
    )
  )

let tokenCounter = 0
export const freshToken = (): ChunkToken => ChunkToken(`t${tokenCounter++}`)

/** Chunks reached by trying to append a random sequence of chunk sizes, some
 *  of them out of bounds; appendChunk refuses those. */
export const chunksArb: fc.Arbitrary<Chunks> = fc
  .tuple(limitsArb, fc.array(fc.integer({ min: 1, max: 12 }), { maxLength: 8 }))
  .map(([lim, sizes]) =>
    sizes.reduce<Chunks>(
      (acc, n) => Option.getOrElse(appendChunk(acc, new Chunk({ cbytes: PosInt(n), ctoken: freshToken() })), () => acc),
      emptyChunks(lim)
    )
  )

export const checksumArb: fc.Arbitrary<Checksum> = fc
  .oneof(
    fc.bigInt({ min: 0n, max: checksumBound - 1n }),
    fc.constantFrom(0n, 1n, 15n, 16n, checksumBound - 1n, checksumBound / 2n)
  )
  .map((v) => valid(checksumOf(v)))

export const reportArb = (sizeArb: fc.Arbitrary<number>): fc.Arbitrary<ReceiptReport> =>
  fc.tuple(checksumArb, sizeArb).map(([c, s]) => valid(receiptReport(ReceiptAlgorithm.Crc64Nvme(), c, s)))

export const versionArb: fc.Arbitrary<Version> = fc.constantFrom("v1", "v2", "v3").map((s) => Version(s))
export const stagingRefArb: fc.Arbitrary<StagingRef> = fc.constantFrom("s1", "s2", "s3").map((s) => mkStagingRef(s))

export const boundArb = (size: Nat): fc.Arbitrary<Bound> =>
  fc.tuple(versionArb, reportArb(fc.constant(size))).map(([v, rep]) =>
    Either.getOrThrowWith(bind(size, v, rep), () => new Error("generator: bind refused its own size"))
  )

export const faultArb: fc.Arbitrary<Fault> = fc.oneof(
  fc.constantFrom(Fault.StateLost(), Fault.SizeMismatch(), Fault.Unavailable(), Fault.Contradiction(), Fault.Expired()),
  fc.integer({ min: 100, max: 599 }).map((n) => Fault.SourceAnswered({ status: Int(n) }))
)

export const endingArb: fc.Arbitrary<Ending> = fc.oneof(
  fc.constant(Ending.Deleted()),
  fc.constant(Ending.Cancelled()),
  faultArb.map((fault) => Ending.Failed({ fault }))
)

export const vouchingArb: fc.Arbitrary<Vouching> = fc.oneof(
  reportArb(fc.integer({ min: 0, max: 60 })).map((report) => Vouching.Vouched({ report })),
  fc.constant(Vouching.Unvouchable()),
  fc.constant(Vouching.NotYetVouched())
)

export const objectObsArb: fc.Arbitrary<ObjectObs> = fc.oneof(
  fc.constant(ObjectObs.NoObject()),
  fc.tuple(versionArb, vouchingArb).map(([version, vouching]) => ObjectObs.HasObject({ version, vouching }))
)

export const seenArb: fc.Arbitrary<Seen> = fc.oneof(
  fc.constant(Seen.Unseen()),
  fc
    .tuple(fc.array(stagingRefArb, { maxLength: 3 }), objectObsArb)
    .map(([refs, obj]) => Seen.Seen({ observed: observed(refs.map((r) => staging(r, [])), obj) }))
)

export const attemptsArb: fc.Arbitrary<Attempts> = fc.constantFrom<Attempts>(0, 1, 2, 3, 4, 5)
export const maxAttemptsArb: fc.Arbitrary<MaxAttempts> = fc.constantFrom<MaxAttempts>(1, 2, 3, 4, 5)

export const writesArb: fc.Arbitrary<ReadonlyArray<Write>> = fc.array(
  fc.tuple(fc.integer({ min: 0, max: 9 }), fc.integer({ min: 0, max: 100 })).map(
    ([e, d]) => new Write({ epoch: Int(e), deadline: Int(d) })
  ),
  { maxLength: 3 }
)

export const goalArb: fc.Arbitrary<Goal> = fc.oneof(
  fc.constant(Goal.Clear()),
  fc
    .tuple(fc.option(stagingRefArb, { nil: undefined }), chunksArb)
    .map(([r, chunks]) => Goal.Keep({ assembly: Assembly.Assembling({ staging: Option.fromNullable(r), chunks }) })),
  fc.tuple(stagingRefArb, chunksArb).map(([r, chunks]) => Goal.Keep({ assembly: Assembly.Assembled({ staging: r, chunks }) }))
)

const common = fc.record({ seen: seenArb, budget: attemptsArb, backoffAt: posArb(6), authorised: writesArb })

/** Any input of the right shape. For an assembled goal the receipt, when
 *  there is one, may or may not have the assembled length. */
export const assetInputArb: fc.Arbitrary<AssetInput> = fc.oneof(
  fc.tuple(common, fc.option(stagingRefArb, { nil: undefined }), chunksArb).map(
    ([c, r, chunks]): AssetInput => ({
      ...c,
      goal: assemblingGoal(Option.fromNullable(r), chunks),
      outcome: Outcome.Ongoing(),
      vouch: Vouch.NoReceipt()
    })
  ),
  fc
    .tuple(common, stagingRefArb, chunksArb, fc.boolean(), fc.boolean())
    .chain(([c, r, chunks, withReceipt, sameSize]) => {
      const goal = assembledGoal(r, chunks)
      const len = offsetOf(chunks)
      const vouchArb: fc.Arbitrary<Vouch> = withReceipt
        ? boundArb(sameSize ? len : Nat(len + 1)).map((bound) => Vouch.HasReceipt({ bound }))
        : fc.constant(Vouch.NoReceipt())
      return vouchArb.map((vouch): AssetInput => ({ ...c, goal, outcome: Outcome.Ongoing(), vouch }))
    }),
  fc.tuple(common, endingArb, fc.boolean(), natArb(60)).chain(([c, ending, withReceipt, n]) =>
    (withReceipt ? boundArb(n).map((bound) => Vouch.HasReceipt({ bound })) : fc.constant(Vouch.NoReceipt())).map(
      (vouch): AssetInput => ({ ...c, goal: Goal.Clear(), outcome: Outcome.Ended({ ending }), vouch })
    )
  )
)

/** Assets the checked constructor accepts. */
export const assetArb: fc.Arbitrary<Asset> = assetInputArb
  .map((i) => makeAsset(i))
  .filter(Either.isRight)
  .map((e) => e.right)

/** Whether the input's receipt, if any, matches its assembled length. */
export const receiptMatches = (i: AssetInput): boolean => {
  if (i.vouch._tag === "NoReceipt") return true
  const bound = i.vouch.bound
  return Option.match(assembledTotal(i.goal), {
    onNone: () => true,
    onSome: (n) => n === boundSize(bound)
  })
}

export const backoffArb: fc.Arbitrary<Backoff> = fc
  .record({ i: fc.integer({ min: 1, max: 1000 }), extra: fc.integer({ min: 0, max: 100000 }), k: fc.integer({ min: 1, max: 10 }) })
  .map(({ i, extra, k }) =>
    valid(makeBackoff({ initialBackoff: PosInt(i), maxBackoff: PosInt(i + extra), backoffMultiplier: PosInt(k) }))
  )

export const envArb: fc.Arbitrary<Env> = fc
  .tuple(natArb(200), maxAttemptsArb, backoffArb, natArb(100))
  .map(([now, maxAttempts, backoff, writeDeadline]) => new Env({ now, cfg: new Config({ maxAttempts, backoff, writeDeadline }) }))
