// Claims (Checksum below 2^64; ReceiptReport size a Nat; DrsType only from
// drsType; SizeDiffers only from vouch): none can be built by hand.
import { Option } from "effect"
import { Nat } from "../../src/Num.js"
import { type Checksum, type DrsType, ReceiptAlgorithm, checksumOf } from "../../src/Store/Algorithm.js"
import { type ReceiptReport, type SizeDiffers } from "../../src/Store/Receipt.js"

const c = Option.getOrThrow(checksumOf(7n))

export const tooBig: Checksum = 2n ** 64n // @expect TS2322
export const report: ReceiptReport = { alg: ReceiptAlgorithm.Crc64Nvme(), checksum: c, size: Nat(1) } // @expect TS2741
export const drs: DrsType = { name: "md5" } // @expect TS2741
export const same: SizeDiffers = { expectedSize: 3, reportedSize: Nat(3) } // @expect TS2741
