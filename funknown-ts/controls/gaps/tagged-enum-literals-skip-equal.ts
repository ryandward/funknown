// GAP: this file has to COMPILE. Data.TaggedEnum types are structural, so a
// plain object literal is a valid Goal. It isn't built by Data, though, so
// Equal.equals compares it by reference: a literal Clear is not equal to
// Goal.Clear(). Nothing in src builds sums this way, but a later module
// comparing goals or observations with Equal.equals (the Prog claim does)
// would get a false "changed" from such a value. The tests stay with the
// generated constructors.
import { Equal } from "effect"
import { Goal } from "../../src/Kernel/Types.js"

export const literalClear: Goal = { _tag: "Clear" }
export const notEqual: boolean = Equal.equals(literalClear, Goal.Clear())
