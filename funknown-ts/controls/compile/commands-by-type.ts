// Claims K2 and K5 by type: Seal names nothing (it can only seal the goal's
// chunks), Remove can't be built without a version, Discard without a staging
// area.
import { Cmd, StagingRef } from "../../src/Kernel/Types.js"

export const sealNamed = Cmd.DoSeal({ ref: StagingRef("other") }) // @expect TS2345
export const removeAll = Cmd.DoRemove({}) // @expect TS2741
export const discardAll = Cmd.DoDiscard({}) // @expect TS2741
