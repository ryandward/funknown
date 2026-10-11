// Funknown.Store.Receipt: the store's word that it holds a whole file, the
// only thing that can make a file available (C CH1). Receipt is opaque and
// vouch is the only way to build one.
//
// What comes in from outside the core, a ReceiptReport and the Checksum in
// it, is opaque with one checked producer each, and vouch has no
// precondition, so every claim here holds whoever calls it.
import { Brand, Data, Either, Option } from "effect"
import { Nat } from "../Num.js"
import { type Checksum, type ReceiptAlgorithm, checksumValue, width } from "./Algorithm.js"

// Reports --------------------------------------------------------------------

/** What a store reported for a sealed file, already decoded by its adapter. */
class ReceiptReport extends Data.Class<{
  readonly alg: ReceiptAlgorithm
  readonly checksum: Checksum
  readonly size: Nat
}> {
  private declare readonly nominal: "ReceiptReport"
}
export type { ReceiptReport }

/** The only producer of a ReceiptReport: present exactly when the size is a
 *  size, and then holding what it was given. */
export const receiptReport = (a: ReceiptAlgorithm, c: Checksum, s: number): Option.Option<ReceiptReport> =>
  Option.map(Nat.option(s), (size) => new ReceiptReport({ alg: a, checksum: c, size }))

export const reportAlg = (r: ReceiptReport): ReceiptAlgorithm => r.alg
export const reportChecksum = (r: ReceiptReport): Checksum => r.checksum
export const reportSize = (r: ReceiptReport): Nat => r.size

/** A report whose size isn't the expected length. The two can't be equal,
 *  which TypeScript can't state, so only vouch builds one, and only when they
 *  differ. Haskell leaves this constructor open because LiquidHaskell checks
 *  the inequality at every construction site; here the fields stay readable
 *  but the constructor doesn't leave this module. */
class SizeDiffers extends Data.Class<{ readonly expectedSize: number; readonly reportedSize: Nat }> {
  private declare readonly nominal: "SizeDiffers"
}
export type { SizeDiffers }

// Receipts -------------------------------------------------------------------

class Receipt extends Data.Class<{
  readonly alg: ReceiptAlgorithm
  readonly checksum: Checksum
  readonly size: Nat
}> {
  private declare readonly nominal: "Receipt"
}
export type { Receipt }

export const alg = (r: Receipt): ReceiptAlgorithm => r.alg
export const checksum = (r: Receipt): Checksum => r.checksum
export const size = (r: Receipt): Nat => r.size

/** The only producer of Receipt (DC1's construction half). The receipt keeps
 *  the report's algorithm, checksum and size, and exists only when that size
 *  is the length we expected; otherwise the answer says both sizes. */
export const vouch = (expected: number, rep: ReceiptReport): Either.Either<Receipt, SizeDiffers> =>
  rep.size === expected
    ? Either.right(new Receipt({ alg: rep.alg, checksum: rep.checksum, size: rep.size }))
    : Either.left(new SizeDiffers({ expectedSize: expected, reportedSize: rep.size }))

// Hex rendering --------------------------------------------------------------

const hexDigits = "0123456789abcdef"

/** A lowercase hex digit. */
export const isLowerHex = (c: string): boolean => c.length === 1 && hexDigits.includes(c)

/** Exactly sixteen lowercase hex digits: the DRS checksum string. */
export type Hex16 = string & Brand.Brand<"Hex16">
const Hex16 = Brand.refined<Hex16>(
  (s) => s.length === 16 && [...s].every(isLowerHex),
  (s) => Brand.error(`${s} is not sixteen lowercase hex digits`)
)

/** The value of a lowercase hex digit; anything else counts as 0. */
const digitValue = (c: string): bigint => {
  const i = hexDigits.indexOf(c)
  return i < 0 ? 0n : BigInt(i)
}

/** Horner's rule, most significant digit first. */
export const hexValue = (s: string): bigint => [...s].reduce((acc, c) => 16n * acc + digitValue(c), 0n)

export const pow16 = (k: number): bigint => (k <= 0 ? 1n : 16n ** BigInt(k))
export const pow2 = (k: number): bigint => (k <= 0 ? 1n : 2n ** BigInt(k))

/** Sixteen hex digits hold exactly the algorithm's width. */
export const widthIsSixteenDigits = (a: ReceiptAlgorithm): boolean => pow2(width(a)) === pow16(16)

/** The DRS checksum string: lowercase and zero-padded to the full width, so
 *  one checksum has one spelling. The Hex16 brand checks the shape at run
 *  time; that hexValue undoes it is a property test. */
export const toHex = (r: Receipt): Hex16 => Hex16(checksumValue(r.checksum).toString(16).padStart(16, "0"))

/** toHex is injective on the 2^64 checksums: equal strings mean equal values. */
export const sameHexSameChecksum = (r1: Receipt, r2: Receipt): boolean => toHex(r1) === toHex(r2)
