// Claim (Limits and Upload refinements): only limits and makeUpload build
// these, so maxChunk < minChunk, or complete with a length that isn't the
// offset, can't be wrapped by hand.
import { Option } from "effect"
import { Len } from "../../src/Opt.js"
import { Nat, PosInt } from "../../src/Num.js"
import { type Limits, type Upload, emptyChunks, limits } from "../../src/Upload.js"

const ok = Option.getOrThrow(limits({ minChunk: PosInt(1), maxChunk: PosInt(2), maxChunks: PosInt(1), maxSize: Nat(2), sealsEmpty: false }))

export const backwards: Limits = { ...ok, minChunk: PosInt(9) } // @expect TS2741
export const liar: Upload = { chunks: emptyChunks(ok), uploadLen: Len.Known({ n: Nat(5) }), complete: true } // @expect TS2741
export const zeroMin = limits({ ...ok, minChunk: 0 }) // @expect TS2322
