// Properties for Funknown.Upload: what LiquidHaskell proved about Limits,
// Chunks, appendChunk and Upload, checked over generated inputs.
import assert from "node:assert/strict"
import { test } from "node:test"
import { FastCheck as fc, Option } from "effect"
import { Len } from "../src/Opt.js"
import { Nat, PosInt } from "../src/Num.js"
import {
  Chunk,
  canAppend,
  appendChunk,
  chunkList,
  chunksInvariant,
  emptyChunks,
  lastBytes,
  limits,
  limitsOf,
  makeUpload,
  nChunks,
  offsetOf,
  room,
  total,
  uploadInvariant
} from "../src/Upload.js"
import { chunksArb, freshToken, limitsArb, natArb } from "./arb.js"

const runs = { numRuns: 1000 }

test("limits is present exactly when maxChunk >= minChunk", () => {
  fc.assert(
    fc.property(fc.integer({ min: 1, max: 9 }), fc.integer({ min: 1, max: 9 }), (lo, hi) => {
      const l = limits({ minChunk: PosInt(lo), maxChunk: PosInt(hi), maxChunks: PosInt(1), maxSize: Nat(0), sealsEmpty: false })
      return Option.isSome(l) === hi >= lo
    }),
    runs
  )
})

test("every reachable Chunks meets the data refinement", () => {
  fc.assert(fc.property(chunksArb, (c) => chunksInvariant(c)), runs)
})

test("emptyChunks has offset 0, no chunks, and the limits it was given", () => {
  fc.assert(
    fc.property(limitsArb, (lim) => {
      const c = emptyChunks(lim)
      return offsetOf(c) === 0 && nChunks(c) === 0 && limitsOf(c) === lim
    })
  )
})

test("appendChunk is present exactly when canAppend holds", () => {
  fc.assert(
    fc.property(chunksArb, fc.integer({ min: 1, max: 15 }), (x, n) => {
      const c = new Chunk({ cbytes: PosInt(n), ctoken: freshToken() })
      return Option.isSome(appendChunk(x, c)) === canAppend(x, n)
    }),
    runs
  )
})

test("canAppend refuses a size below 1", () => {
  fc.assert(fc.property(chunksArb, fc.integer({ min: -5, max: 0 }), (x, n) => !canAppend(x, n)))
})

test("appendChunk keeps the refinement and its postcondition", () => {
  fc.assert(
    fc.property(chunksArb, fc.integer({ min: 1, max: 15 }), (x, n) => {
      const c = new Chunk({ cbytes: PosInt(n), ctoken: freshToken() })
      return Option.match(appendChunk(x, c), {
        onNone: () => true,
        onSome: (y) =>
          chunksInvariant(y) &&
          offsetOf(y) === offsetOf(x) + n &&
          nChunks(y) === nChunks(x) + 1 &&
          limitsOf(y) === limitsOf(x) &&
          lastBytes(y) === n &&
          room(y) === room(x) - 1 &&
          chunkList(y)[0] === c
      })
    }),
    runs
  )
})

test("offsetOf is the total of the chunk list, and room is the cap minus the count", () => {
  fc.assert(
    fc.property(chunksArb, (x) => offsetOf(x) === total(chunkList(x)) && room(x) === limitsOf(x).maxChunks - nChunks(x)),
    runs
  )
})

test("makeUpload is present exactly when the length and completion refinements hold", () => {
  const lenArb = fc.oneof(fc.constant(Len.Unknown()), natArb(70).map((n) => Len.Known({ n })))
  fc.assert(
    fc.property(chunksArb, lenArb, fc.boolean(), (chunks, uploadLen, complete) => {
      const f = { chunks, uploadLen, complete }
      const u = makeUpload(f)
      const off = offsetOf(chunks)
      const expect =
        (uploadLen._tag === "Unknown" || (off <= uploadLen.n && uploadLen.n <= chunks.limits.maxSize)) &&
        (!complete || (uploadLen._tag === "Known" && uploadLen.n === off))
      return Option.isSome(u) === expect && uploadInvariant(f) === expect
    }),
    runs
  )
})

test("an empty upload with known length 0 can be complete", () => {
  fc.assert(
    fc.property(limitsArb, (lim) => {
      const u = makeUpload({ chunks: emptyChunks(lim), uploadLen: Len.Known({ n: Nat(0) }), complete: true })
      assert.ok(Option.isSome(u))
    })
  )
})
