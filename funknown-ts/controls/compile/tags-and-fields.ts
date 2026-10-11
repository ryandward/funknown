// Claims carried by literal types and branded field types: tag measures stay
// in range, width is 64, Config's maxAttempts is in 1..attemptCap, Env's now
// and a Decision's waitFor are Nats; opaque names aren't plain strings.
import { Option } from "effect"
import { makeBackoff } from "../../src/Http/Retry.js"
import type { Version } from "../../src/Kernel/Bound.js"
import {
  Cmd,
  type CmdTag,
  Config,
  Decision,
  Ending,
  Env,
  Goal,
  type GoalTag,
  type ObjTag,
  Outcome,
  Seen,
  type StagingRef,
  Vouch,
  asset
} from "../../src/Kernel/Types.js"
import type { ChunkToken } from "../../src/Upload.js"
import { Nat, PosInt } from "../../src/Num.js"
import { ReceiptAlgorithm, width } from "../../src/Store/Algorithm.js"

const backoff = Option.getOrThrow(makeBackoff({ initialBackoff: PosInt(1), maxBackoff: PosInt(2), backoffMultiplier: PosInt(2) }))

export const obj: ObjTag = 4 // @expect TS2322
export const goal: GoalTag = 3 // @expect TS2322
export const cmd: CmdTag = 6 // @expect TS2322
export const w: 65 = width(ReceiptAlgorithm.Crc64Nvme()) // @expect TS2322
export const noAttempts = new Config({ maxAttempts: 0, backoff, writeDeadline: Nat(1) }) // @expect TS2322
export const tooMany = new Config({ maxAttempts: 6, backoff, writeDeadline: Nat(1) }) // @expect TS2322
export const negativeDeadline = new Config({ maxAttempts: 1, backoff, writeDeadline: -1 }) // @expect TS2322
export const negativeNow = new Env({ now: -1, cfg: new Config({ maxAttempts: 1, backoff, writeDeadline: Nat(1) }) }) // @expect TS2322
export const version: Version = "v1" // @expect TS2322
export const ref: StagingRef = "s1" // @expect TS2322
export const token: ChunkToken = "t1" // @expect TS2322

const next = asset({
  seen: Seen.Unseen(), budget: 0, backoffAt: PosInt(1), authorised: [],
  goal: Goal.Clear(), outcome: Outcome.Ended({ ending: Ending.Deleted() }), vouch: Vouch.NoReceipt()
})
export const plainWait = new Decision({ next, command: Cmd.NoCmd(), waitFor: 5, alarm: false, row: "R0" }) // @expect TS2322
export const noSuchRow = new Decision({ next, command: Cmd.NoCmd(), waitFor: Nat(0), alarm: false, row: "R20" }) // @expect TS2322
