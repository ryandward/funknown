// Claims (Client/Core.ts, carried by the move types): each move takes only
// the shapes Haskell's precondition allows, and its result's shape says the
// goal's kind only moves down its order (Keep to Clear, an assembly in
// progress to an assembled object), so no move's result can be handed to a
// move that needs the goal back where it was.
import type { Ending } from "../../src/Kernel/Types.js"
import { Int } from "../../src/Num.js"
import type { Chunk } from "../../src/Upload.js"
import {
  type AdoptedAsset,
  type AssembledAsset,
  type AssemblingAsset,
  type ClearAsset,
  type KeepAsset,
  appendTo,
  clearGoal,
  completeGoal,
  startWrite
} from "../../src/Client/Core.js"

declare const cleared: ClearAsset
declare const assembled: AssembledAsset
declare const assembling: AssemblingAsset
declare const adopted: AdoptedAsset
declare const ending: Ending
declare const chunk: Chunk

// Preconditions.
clearGoal(cleared, ending) // @expect TS2345
startWrite(assembled, Int(0), Int(0)) // @expect TS2345
appendTo(assembling, chunk) // @expect TS2345
completeGoal(assembling) // @expect TS2345

// The goal's kind never moves back up.
startWrite(completeGoal(adopted), Int(0), Int(0)) // @expect TS2345
startWrite(clearGoal(adopted, ending), Int(0), Int(0)) // @expect TS2345
const back: KeepAsset = clearGoal(assembled, ending) // @expect TS2322
const reopened: AssemblingAsset = completeGoal(adopted) // @expect TS2322

export { back, reopened }
