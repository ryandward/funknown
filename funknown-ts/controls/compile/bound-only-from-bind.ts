// Claim (K1, contract rule 4): a Bound is built only by bind, which only
// gets its Receipt from vouch.
import { Either, Option } from "effect"
import { type Bound, Version, bind } from "../../src/Kernel/Bound.js"
import { Nat } from "../../src/Num.js"
import { ReceiptAlgorithm, checksumOf } from "../../src/Store/Algorithm.js"
import { receiptReport } from "../../src/Store/Receipt.js"

const c = Option.getOrThrow(checksumOf(7n))
const rep = Option.getOrThrow(receiptReport(ReceiptAlgorithm.Crc64Nvme(), c, 3))
const real: Bound = Either.getOrThrow(bind(Nat(3), Version("v1"), rep))

export const literal: Bound = { version: Version("v2"), receipt: real.receipt } // @expect TS2741
export const rebound: Bound = { ...real, version: Version("v2") } // @expect TS2741
export const negative = bind(-1, Version("v1"), rep) // @expect TS2345
