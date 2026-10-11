// Claim: Coherent A M, the progress lemma's precondition, is a type. Only
// synced (which checks it), observedNow, forgetting and keepingView (which
// make it true by construction) produce a Synced, so round can't be handed
// a pair nobody checked, and the round's own pair is Synced again.
import { Option } from "effect"
import type { Asset, Env } from "../../src/Kernel/Types.js"
import { type Model, type Synced, round, synced } from "../../src/Kernel/Model.js"
import { Synced as SyncedValue } from "../../src/Kernel/Model.js" // @expect TS1485

declare const env: Env
declare const a: Asset
declare const m: Model
declare const s: Synced

export const rawPair = round(env, a, m) // @expect TS2554
export const literal = round(env, { asset: a, model: m }) // @expect TS2741
export const spread = round(env, { ...s, model: m }) // @expect TS2741
export const constructed = new SyncedValue({ asset: a, model: m }) // @expect TS1362
export const unchecked = round(env, synced(a, m)) // @expect TS2345
export const retargeted: Synced = Option.getOrThrow(synced(a, m)).model // @expect TS2322
export const fine = round(env, s)
