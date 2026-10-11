// Properties for Funknown.Store.Algorithm, Funknown.Store.Receipt and
// Funknown.Kernel.Bound.
import assert from "node:assert/strict"
import { test } from "node:test"
import { Either, FastCheck as fc, Option } from "effect"
import { bind, boundReceipt, boundSize, boundVersion } from "../src/Kernel/Bound.js"
import { Nat } from "../src/Num.js"
import {
  ReceiptAlgorithm,
  allAlgorithms,
  checksumBound,
  checksumOf,
  checksumValue,
  drsType,
  drsTypeName,
  width
} from "../src/Store/Algorithm.js"
import {
  alg,
  checksum,
  hexValue,
  isLowerHex,
  receiptReport,
  reportAlg,
  reportChecksum,
  reportSize,
  sameHexSameChecksum,
  size,
  toHex,
  vouch,
  widthIsSixteenDigits
} from "../src/Store/Receipt.js"
import { checksumArb, natArb, reportArb, versionArb } from "./arb.js"

const runs = { numRuns: 1000 }

// 2^64 written out, not imported: a test that read the bound from the code
// would agree with any bound the code chose.
const twoTo64 = 18446744073709551616n

const anyBig = fc.oneof(
  fc.bigInt({ min: -(2n ** 70n), max: 2n ** 70n }),
  fc.constantFrom(-1n, 0n, twoTo64 - 1n, twoTo64, twoTo64 + 1n, 2n ** 63n, 2n ** 63n - 1n)
)

test("checksumOf is present exactly when 0 <= v < 2^64, and keeps v", () => {
  fc.assert(
    fc.property(anyBig, (v) =>
      Option.match(checksumOf(v), {
        onNone: () => !(0n <= v && v < twoTo64),
        onSome: (c) => 0n <= v && v < twoTo64 && checksumValue(c) === v
      })
    ),
    runs
  )
})

test("width is 64 and sixteen hex digits hold exactly that width, for every algorithm", () => {
  for (const a of allAlgorithms) {
    assert.equal(width(a), 64)
    assert.ok(widthIsSixteenDigits(a))
  }
  assert.equal(checksumBound, twoTo64)
  assert.equal(drsTypeName(drsType(ReceiptAlgorithm.Crc64Nvme())), "crc64nvme")
})

test("receiptReport is present exactly when the size is a Nat, and keeps what it was given", () => {
  fc.assert(
    fc.property(checksumArb, fc.integer({ min: -50, max: 50 }), (c, s) => {
      const a = ReceiptAlgorithm.Crc64Nvme()
      return Option.match(receiptReport(a, c, s), {
        onNone: () => s < 0,
        onSome: (r) => s >= 0 && reportAlg(r) === a && reportChecksum(r) === c && reportSize(r) === s
      })
    }),
    runs
  )
})

test("vouch: a receipt exactly when the size is the expected one, keeping alg, checksum and size", () => {
  fc.assert(
    fc.property(fc.integer({ min: -3, max: 40 }), reportArb(fc.integer({ min: 0, max: 40 })), (expected, rep) =>
      Either.match(vouch(expected, rep), {
        onLeft: (d) => d.expectedSize === expected && d.reportedSize === reportSize(rep) && d.reportedSize !== d.expectedSize,
        onRight: (r) =>
          size(r) === expected &&
          size(r) === reportSize(rep) &&
          alg(r) === reportAlg(rep) &&
          checksum(r) === reportChecksum(rep)
      })
    ),
    runs
  )
})

test("vouch answers SizeDiffers exactly when the sizes differ", () => {
  fc.assert(
    fc.property(fc.integer({ min: -3, max: 40 }), reportArb(fc.integer({ min: 0, max: 40 })), (expected, rep) =>
      Either.isLeft(vouch(expected, rep)) === (expected !== reportSize(rep))
    ),
    runs
  )
})

const receiptOf = (c: bigint) =>
  Either.getOrThrow(
    vouch(0, Option.getOrThrow(receiptReport(ReceiptAlgorithm.Crc64Nvme(), Option.getOrThrow(checksumOf(c)), 0)))
  )

test("toHex is sixteen lowercase hex digits that hexValue reads back as the checksum", () => {
  fc.assert(
    fc.property(checksumArb, (c) => {
      const h = toHex(receiptOf(c))
      return h.length === 16 && [...h].every(isLowerHex) && hexValue(h) === checksumValue(c)
    }),
    runs
  )
})

test("toHex is injective: equal strings mean equal checksums", () => {
  fc.assert(
    fc.property(checksumArb, checksumArb, (c1, c2) => {
      const r1 = receiptOf(c1)
      const r2 = receiptOf(c2)
      return sameHexSameChecksum(r1, r2) === (checksumValue(checksum(r1)) === checksumValue(checksum(r2)))
    }),
    runs
  )
})

test("K1 for bind: the bound receipt has the expected and reported size and the given version", () => {
  fc.assert(
    fc.property(natArb(40), versionArb, reportArb(fc.integer({ min: 0, max: 40 })), (expected, v, rep) =>
      Either.match(bind(expected, v, rep), {
        onLeft: (d) => d.expectedSize === expected && d.reportedSize === reportSize(rep) && expected !== reportSize(rep),
        onRight: (b) =>
          boundSize(b) === expected &&
          boundSize(b) === reportSize(rep) &&
          boundVersion(b) === v &&
          size(boundReceipt(b)) === Nat(expected)
      })
    ),
    runs
  )
})
