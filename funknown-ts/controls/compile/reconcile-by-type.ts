// The reconciler's LiquidHaskell preconditions that became parameter types:
// issue takes only a store command ({c | cmdTag c >= 2}), failWith only a
// goal that keeps the asset ({a | goalTag (goal a) /= 0}), adopt only an
// assembly in progress (so no receipt), and a leaf's row is one of the
// table's. Values are declared, not built: only the types are under test.
import { Fault } from "../../src/Fault.js"
import { type AssembledView, type ClearView, adopt, failWith, issue } from "../../src/Kernel/Reconcile.js"
import { type Asset, Cmd, type StagingRef } from "../../src/Kernel/Types.js"

declare const a: Asset
declare const cleared: ClearView
declare const done: AssembledView
declare const r: StagingRef

export const issueNothing = issue("R1", a, Cmd.NoCmd()) // @expect TS2345
export const issueObserve = issue("R0", a, Cmd.DoObserve()) // @expect TS2345
export const failCleared = failWith("R5", cleared, Fault.StateLost()) // @expect TS2345
export const adoptAssembled = adopt(done, r) // @expect TS2345
export const rowOffTable = issue("R20", a, Cmd.DoOpen()) // @expect TS2345
