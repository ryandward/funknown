// Claim (C CH1, DC1): a Receipt is built only by vouch. Each line below
// tries another way to get one and has to be refused.
import { Either, Option } from "effect"
import { Nat } from "../../src/Num.js"
import { ReceiptAlgorithm, checksumOf } from "../../src/Store/Algorithm.js"
import { type Receipt, receiptReport, vouch } from "../../src/Store/Receipt.js"
import { Receipt as ReceiptClass } from "../../src/Store/Receipt.js" // @expect TS1485

const c = Option.getOrThrow(checksumOf(7n))
const real: Receipt = Either.getOrThrow(vouch(3, Option.getOrThrow(receiptReport(ReceiptAlgorithm.Crc64Nvme(), c, 3))))

export const literal: Receipt = { alg: ReceiptAlgorithm.Crc64Nvme(), checksum: c, size: Nat(99) } // @expect TS2741
export const spread: Receipt = { ...real, size: Nat(99) } // @expect TS2741
export const viaNew = new ReceiptClass({ alg: ReceiptAlgorithm.Crc64Nvme(), checksum: c, size: Nat(99) }) // @expect TS1362
real.size = Nat(99) // @expect TS2540
