// Funknown.Kernel.Bound: a receipt bound to the exact object version it
// vouched for (store contract rule 4). Only bind builds one, so a bound
// receipt always came from vouch and always names the version it was
// observed at.
import { Brand, Data, Either } from "effect"
import type { Nat } from "../Num.js"
import { type Receipt, type ReceiptReport, type SizeDiffers, size, vouch } from "../Store/Receipt.js"

/** Opaque: whatever identifies an object's bytes in the store. The core
 *  compares versions and never looks inside. */
export type Version = string & Brand.Brand<"Version">
export const Version = Brand.nominal<Version>()

class Bound extends Data.Class<{ readonly version: Version; readonly receipt: Receipt }> {
  private declare readonly nominal: "Bound"
}
export type { Bound }

export const boundVersion = (b: Bound): Version => b.version
export const boundSize = (b: Bound): Nat => size(b.receipt)
export const boundReceipt = (b: Bound): Receipt => b.receipt

/** K1: a bound receipt's size is the expected length and the size the store
 *  reported, and its version is the version the store reported with the
 *  vouching. The only producer of Bound, and it can only get a Receipt from
 *  vouch. */
export const bind = (expected: Nat, v: Version, rep: ReceiptReport): Either.Either<Bound, SizeDiffers> =>
  Either.map(vouch(expected, rep), (r) => new Bound({ version: v, receipt: r }))
