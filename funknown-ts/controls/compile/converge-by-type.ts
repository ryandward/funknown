// Claims carried by types in Converge: a run rests in a resting row
// (Haskell's runRow :: {r:Row | isFixedRow r}); every metric component is a
// natural number or a literal union of them; an adversary's move carries
// what it needs; and case analysis over moves is exhaustive.
import { Match } from "effect"
import { type Metric, type Move, Move as M, Run } from "../../src/Kernel/Converge.js"
import type { Model } from "../../src/Kernel/Model.js"
import type { Asset } from "../../src/Kernel/Types.js"
import { Nat } from "../../src/Num.js"
import { ChunkToken } from "../../src/Upload.js"

declare const a: Asset
declare const m: Model

export const runAtR0 = new Run({ asset: a, model: m, row: "R0", rounds: Nat(1) }) // @expect TS2322
export const runAtR12 = new Run({ asset: a, model: m, row: "R12", rounds: Nat(1) }) // @expect TS2322
export const negativeRank: Metric = [-1, Nat(0), 0, Nat(0), Nat(0), 0] // @expect TS2322
export const plainAllowance: Metric = [Nat(0), 3, 0, Nat(0), Nat(0), 0] // @expect TS2322
export const budgetSix: Metric = [Nat(0), Nat(0), 6, Nat(0), Nat(0), 0] // @expect TS2322
export const unseenTwo: Metric = [Nat(0), Nat(0), 0, Nat(0), Nat(0), 2] // @expect TS2322
export const appendNoSize = M.Append({ token: ChunkToken("a1") }) // @expect TS2741
export const abandonNoEnding = M.Abandon({}) // @expect TS2741

export const name = (mv: Move): string =>
  Match.valueTags(mv, { // @expect TS2345
    Drop: () => "drop",
    LateWrite: () => "late write",
    Lapse: () => "lapse",
    Append: () => "append",
    Complete: () => "complete"
  })
