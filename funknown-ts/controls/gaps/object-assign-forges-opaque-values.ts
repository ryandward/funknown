// GAP: this file has to COMPILE. lib.es2015's Object.assign is typed
// (target: T, source: U) => T & U, so one genuine value of an opaque type is
// enough to forge another with any fields, and a negative number can be
// typed as a Nat. No cast appears. The run-time checks in the constructors
// are bypassed too, because no constructor runs. Only a lint rule banning
// Object.assign outside the modules that own a type could close this, and
// none is installed.
import { Either, Option } from "effect"
import { Version, bind } from "../../src/Kernel/Bound.js"
import { type Asset, Ending, Goal, Outcome, Seen, Vouch, asset } from "../../src/Kernel/Types.js"
import { Nat, PosInt } from "../../src/Num.js"
import { ReceiptAlgorithm, checksumOf } from "../../src/Store/Algorithm.js"
import { type Receipt, receiptReport, vouch } from "../../src/Store/Receipt.js"

const rep = Option.getOrThrow(receiptReport(ReceiptAlgorithm.Crc64Nvme(), Option.getOrThrow(checksumOf(1n)), 3))
const real: Receipt = Either.getOrThrow(vouch(3, rep))

export const forgedReceipt: Receipt = Object.assign({}, real, { size: Nat(999) })
export const forgedNat: Nat = Object.assign(-1, Nat(0))

const cleared: Asset = asset({
  seen: Seen.Unseen(),
  budget: 0,
  backoffAt: PosInt(1),
  authorised: [],
  goal: Goal.Clear(),
  outcome: Outcome.Ended({ ending: Ending.Deleted() }),
  vouch: Vouch.NoReceipt()
})
// A cleared asset re-labelled as Ongoing with a receipt of the wrong size.
export const forgedAsset: Asset = Object.assign({}, cleared, {
  outcome: Outcome.Ongoing(),
  vouch: Vouch.HasReceipt({ bound: Either.getOrThrow(bind(Nat(3), Version("v"), rep)) })
})
