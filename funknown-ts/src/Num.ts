// Whole numbers. Haskell's Int and LiquidHaskell's Nat become branded
// numbers here, each with one smart constructor that checks before it brands
// (Effect's Brand.refined does the branding, so no cast appears in this code).
//
// What a brand can't do: arithmetic on two Nats gives a plain number, so every
// sum or difference goes back through a constructor, which checks at run time
// what LiquidHaskell proved at compile time. The helpers below are those
// re-entries, kept in one place so it is clear where the run-time checks are.
import { Brand, Option } from "effect"

/** A safe integer: what Haskell's Int means here. */
export type Int = number & Brand.Brand<"Int">
export const Int = Brand.refined<Int>(
  (n) => Number.isSafeInteger(n),
  (n) => Brand.error(`expected a safe integer, got ${n}`)
)

/** LiquidHaskell's Nat. */
export type Nat = Int & Brand.Brand<"Nat">
export const Nat = Brand.refined<Nat>(
  (n) => Number.isSafeInteger(n) && n >= 0,
  (n) => Brand.error(`expected a natural number, got ${n}`)
)

/** {v:Int | v >= 1} */
export type PosInt = Nat & Brand.Brand<"PosInt">
export const PosInt = Brand.refined<PosInt>(
  (n) => Number.isSafeInteger(n) && n >= 1,
  (n) => Brand.error(`expected a positive integer, got ${n}`)
)

/** The sum of two Nats. Throws only past 2^53, which LiquidHaskell's
 *  unbounded integers would not notice either. */
export const addNat = (a: Nat, b: Nat): Nat => Nat(a + b)

/** a - b when that is still a Nat. */
export const subNat = (a: Nat, b: Nat): Option.Option<Nat> => Nat.option(a - b)

/** The length of an array, which is a Nat by construction. */
export const lengthOf = (xs: ReadonlyArray<unknown>): Nat => Nat(xs.length)
