// Claims (Asset refinements carried by the type): the ending is set exactly
// when the goal is Clear; no receipt while assembling; budget <= attemptCap;
// backoffAt >= 1; asset() won't take an assembled goal with a receipt, which
// needs the checked makeAsset; and an Asset can't be built or patched by hand.
import { Either, Option } from "effect"
import { Version, bind } from "../../src/Kernel/Bound.js"
import {
  type Asset,
  type AssetCommon,
  Ending,
  Goal,
  Outcome,
  Seen,
  StagingRef,
  Vouch,
  asset,
  assembledGoal,
  assemblingGoal
} from "../../src/Kernel/Types.js"
import { Nat, PosInt } from "../../src/Num.js"
import { ReceiptAlgorithm, checksumOf } from "../../src/Store/Algorithm.js"
import { receiptReport } from "../../src/Store/Receipt.js"
import { emptyChunks, limits } from "../../src/Upload.js"

const lim = Option.getOrThrow(limits({ minChunk: PosInt(1), maxChunk: PosInt(2), maxChunks: PosInt(1), maxSize: Nat(2), sealsEmpty: false }))
const chunks = emptyChunks(lim)
const rep = Option.getOrThrow(receiptReport(ReceiptAlgorithm.Crc64Nvme(), Option.getOrThrow(checksumOf(1n)), 0))
const bound = Either.getOrThrow(bind(Nat(0), Version("v1"), rep))
const base: AssetCommon = { seen: Seen.Unseen(), budget: 3, backoffAt: PosInt(1), authorised: [] }

export const clearOngoing = asset({ ...base, goal: Goal.Clear(), outcome: Outcome.Ongoing(), vouch: Vouch.NoReceipt() }) // @expect TS2345
export const keepEnded = asset({ ...base, goal: assemblingGoal(Option.none(), chunks), outcome: Outcome.Ended({ ending: Ending.Deleted() }), vouch: Vouch.NoReceipt() }) // @expect TS2345
export const assemblingWithReceipt = asset({ ...base, goal: assemblingGoal(Option.none(), chunks), outcome: Outcome.Ongoing(), vouch: Vouch.HasReceipt({ bound }) }) // @expect TS2345
export const uncheckedReceipt = asset({ ...base, goal: assembledGoal(StagingRef("s"), chunks), outcome: Outcome.Ongoing(), vouch: Vouch.HasReceipt({ bound }) }) // @expect TS2345
export const overBudget = asset({ ...base, budget: 6, goal: Goal.Clear(), outcome: Outcome.Ended({ ending: Ending.Deleted() }), vouch: Vouch.NoReceipt() }) // @expect TS2322
export const zeroStep = asset({ ...base, backoffAt: 0, goal: Goal.Clear(), outcome: Outcome.Ended({ ending: Ending.Deleted() }), vouch: Vouch.NoReceipt() }) // @expect TS2322

const real = asset({ ...base, goal: Goal.Clear(), outcome: Outcome.Ended({ ending: Ending.Deleted() }), vouch: Vouch.NoReceipt() })
export const literal: Asset = { ...base, goal: Goal.Clear(), outcome: Outcome.Ended({ ending: Ending.Deleted() }), vouch: Vouch.NoReceipt() } // @expect TS2322
export const patched: Asset = { ...real, vouch: Vouch.HasReceipt({ bound }) } // @expect TS2322
real.vouch = Vouch.HasReceipt({ bound }) // @expect TS2540
