// Funknown.Upload: the chunks the store acknowledged durable, the length, and
// completion. The offset is a measure of the chunks, never a field, so it
// can't disagree with what the store acknowledged.
//
// Opaque types here are classes that this module never exports as values.
// Each carries a `private declare` field, which makes TypeScript compare it
// by declaration rather than by shape, so an object literal or a spread of a
// real one is not assignable to it (see controls/compile). The only way to
// get one is a function below.
import { Data, Option, Brand } from "effect"
import { Nat, type PosInt, addNat, lengthOf, subNat } from "./Num.js"
import { type Len, knownLen } from "./Opt.js"

// Limits ---------------------------------------------------------------------

export interface LimitsFields {
  /** every chunk but the last has at least this many bytes */
  readonly minChunk: PosInt
  /** no chunk has more; at least minChunk */
  readonly maxChunk: PosInt
  /** the most chunks one seal can name */
  readonly maxChunks: PosInt
  /** the plan's max-size */
  readonly maxSize: Nat
  /** whether the store can seal zero chunks */
  readonly sealsEmpty: boolean
}

class Limits extends Data.Class<LimitsFields> {
  private declare readonly nominal: "Limits"
}
export type { Limits }

/** The only producer of Limits. The per-field bounds are in the field types;
 *  the one bound between fields, maxChunk >= minChunk, is checked here. */
export const limits = (f: LimitsFields): Option.Option<Limits> =>
  f.maxChunk >= f.minChunk ? Option.some(new Limits(f)) : Option.none()

// Chunks ---------------------------------------------------------------------

/** Opaque: built only by an adapter from what the store hands back for a
 *  durable chunk. No invariant, so a nominal brand with no check. */
export type ChunkToken = string & Brand.Brand<"ChunkToken">
export const ChunkToken = Brand.nominal<ChunkToken>()

/** cbytes >= 1 is the field's type. Open, like the Haskell constructor. */
export class Chunk extends Data.Class<{ readonly cbytes: PosInt; readonly ctoken: ChunkToken }> {}

/** Newest chunk first. Every chunk is within the chunk-size bounds, except
 *  that only the newest may be short, the count is within the cap, and the
 *  total is within max-size. Only emptyChunks and appendChunk build one. */
class Chunks extends Data.Class<{ readonly limits: Limits; readonly newestFirst: ReadonlyArray<Chunk> }> {
  private declare readonly nominal: "Chunks"
}
export type { Chunks }

export const total = (l: ReadonlyArray<Chunk>): Nat =>
  l.reduce<Nat>((acc, c) => addNat(acc, c.cbytes), Nat(0))

export const headBytes = (l: ReadonlyArray<Chunk>): Nat => {
  const h = l[0]
  return h === undefined ? Nat(0) : h.cbytes
}

export const older = (l: ReadonlyArray<Chunk>): ReadonlyArray<Chunk> => l.slice(1)

export const allAtMost = (m: number, l: ReadonlyArray<Chunk>): boolean => l.every((c) => c.cbytes <= m)

export const allAtLeast = (m: number, l: ReadonlyArray<Chunk>): boolean => l.every((c) => c.cbytes >= m)

/** Every chunk but the newest has at least m bytes. */
export const olderAtLeast = (m: number, l: ReadonlyArray<Chunk>): boolean => allAtLeast(m, older(l))

export const limitsOf = (x: Chunks): Limits => x.limits
export const chunkList = (x: Chunks): ReadonlyArray<Chunk> => x.newestFirst
export const offsetOf = (x: Chunks): Nat => total(x.newestFirst)
export const nChunks = (x: Chunks): Nat => lengthOf(x.newestFirst)
export const lastBytes = (x: Chunks): Nat => headBytes(x.newestFirst)

/** How many more chunks the cap allows. A Nat because of the count
 *  invariant; TypeScript can't see that, so the brand checks it at run time
 *  and throws if the invariant were ever broken. */
export const room = (x: Chunks): Nat =>
  Option.getOrThrowWith(subNat(x.limits.maxChunks, nChunks(x)), () => new Error("room: chunk count above the cap"))

/** The Chunks data refinement, as a predicate. Tests hold every reachable
 *  Chunks to it; the code never needs to call it. */
export const chunksInvariant = (x: Chunks): boolean => {
  const lim = x.limits
  const l = x.newestFirst
  return (
    total(l) <= lim.maxSize &&
    l.length <= lim.maxChunks &&
    allAtMost(lim.maxChunk, l) &&
    olderAtLeast(lim.minChunk, l)
  )
}

export const emptyChunks = (lim: Limits): Chunks => new Chunks({ limits: lim, newestFirst: Data.array([]) })

/** Whether a chunk of n bytes may be appended: within the chunk size, within
 *  max-size and the cap, and the newest chunk so far is not a short one. */
export const canAppend = (x: Chunks, n: number): boolean => {
  const lim = x.limits
  const l = x.newestFirst
  return (
    1 <= n &&
    n <= lim.maxChunk &&
    total(l) + n <= lim.maxSize &&
    l.length < lim.maxChunks &&
    (l.length === 0 || headBytes(l) >= lim.minChunk)
  )
}

/** The Haskell precondition `canAppend x (cbytes c)` can't be a parameter
 *  type here, so it is checked: the result is present exactly when
 *  canAppend holds. */
export const appendChunk = (x: Chunks, c: Chunk): Option.Option<Chunks> =>
  canAppend(x, c.cbytes)
    ? Option.some(new Chunks({ limits: x.limits, newestFirst: Data.array([c, ...x.newestFirst]) }))
    : Option.none()

// Upload ---------------------------------------------------------------------

export interface UploadFields {
  readonly chunks: Chunks
  /** when known: offset <= length <= maxSize */
  readonly uploadLen: Len
  /** set only by an explicit event; true only when the length is known and
   *  equals the offset */
  readonly complete: boolean
}

class Upload extends Data.Class<UploadFields> {
  private declare readonly nominal: "Upload"
}
export type { Upload }

/** The Upload data refinement, as a predicate. */
export const uploadInvariant = (f: UploadFields): boolean => {
  const off = offsetOf(f.chunks)
  const len = knownLen(f.uploadLen)
  const lenOk = Option.match(len, {
    onNone: () => true,
    onSome: (n) => off <= n && n <= f.chunks.limits.maxSize
  })
  const completeOk = !f.complete || Option.match(len, { onNone: () => false, onSome: (n) => n === off })
  return lenOk && completeOk
}

/** The only producer of Upload. */
export const makeUpload = (f: UploadFields): Option.Option<Upload> =>
  uploadInvariant(f) ? Option.some(new Upload(f)) : Option.none()

export const upOffset = (u: Upload): Nat => offsetOf(u.chunks)
export const upLen = (u: Upload): Len => u.uploadLen
export const upComplete = (u: Upload): boolean => u.complete
export const upChunks = (u: Upload): Chunks => u.chunks
