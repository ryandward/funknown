// Funknown.Opt. The Haskell module has two types.
//
// Opt a is gone: Effect's Option replaces it. Opt existed only because this
// LiquidHaskell build can't name isJust in a spec. TypeScript has no such
// restriction, and Option.isSome is a type guard that narrows, so every
// `Opt` in the Haskell becomes `Option.Option` here and `isPresent` becomes
// `Option.isSome`.
//
// Len stays its own type. It is isomorphic to Option<Nat>, but it names a
// different fact (an upload length that was never declared, rather than a
// value that is missing), and the client side reads it by those names.
import { Data, Match, Option } from "effect"
import type { Nat } from "./Num.js"

export type Len = Data.TaggedEnum<{
  Unknown: {}
  Known: { readonly n: Nat }
}>
export const Len = Data.taggedEnum<Len>()

/** Effect generates this guard; a hand-written `l is ...` predicate would be
 *  a claim the compiler takes on trust. */
export const isKnown = Len.$is("Known")

/** The known length, if there is one. Replaces lenOr's -1 sentinel. */
export const knownLen = (l: Len): Option.Option<Nat> =>
  Match.valueTags(l, {
    Unknown: () => Option.none(),
    Known: ({ n }) => Option.some(n)
  })
