// Claim (Chunks refinement): Chunks are built only by emptyChunks and
// appendChunk, so an over-long or out-of-bounds list can't be wrapped as one.
import { Option } from "effect"
import { Nat, PosInt } from "../../src/Num.js"
import { Chunk, ChunkToken, type Chunks, emptyChunks, limits } from "../../src/Upload.js"

const lim = Option.getOrThrow(limits({ minChunk: PosInt(1), maxChunk: PosInt(2), maxChunks: PosInt(1), maxSize: Nat(2), sealsEmpty: false }))
const big = new Chunk({ cbytes: PosInt(100), ctoken: ChunkToken("t") })
const real = emptyChunks(lim)

export const literal: Chunks = { limits: lim, newestFirst: [big, big] } // @expect TS2741
export const spread: Chunks = { ...real, newestFirst: [big, big] } // @expect TS2741
export const zeroChunk = new Chunk({ cbytes: 0, ctoken: ChunkToken("t") }) // @expect TS2322
