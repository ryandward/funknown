// Claim: case analysis is exhaustive, so a missing case doesn't compile.
import { Match } from "effect"
import type { Fault } from "../../src/Fault.js"
import type { Cmd } from "../../src/Kernel/Types.js"

export const name = (c: Cmd): string =>
  Match.valueTags(c, { // @expect TS2741
    NoCmd: () => "none",
    DoObserve: () => "observe",
    DoOpen: () => "open",
    DoSeal: () => "seal",
    DoDiscard: () => "discard"
  })

export const retryable = (f: Fault): boolean => {
  switch (f._tag) {
    case "Unavailable":
      return true
    case "SourceUnreachable":
      return true
    default: {
      const rest: never = f // @expect TS2322
      return rest
    }
  }
}
