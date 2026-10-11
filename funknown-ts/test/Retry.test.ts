// Properties for the ported part of Funknown.Http.Retry.
import { test } from "node:test"
import { FastCheck as fc, Option } from "effect"
import { backoffDelay, makeBackoff, nextWait, spendAttempt } from "../src/Http/Retry.js"
import { PosInt } from "../src/Num.js"
import { attemptsArb, backoffArb, natArb, posArb } from "./arb.js"

const runs = { numRuns: 1000 }

// 2^31 written out, so the test doesn't agree with whatever bound the code picks.
const twoTo31 = 2147483648

test("makeBackoff is present exactly when initial <= max <= 2^31 and multiplier <= 2^31", () => {
  const big = fc.oneof(fc.integer({ min: 1, max: 100 }), fc.constantFrom(twoTo31 - 1, twoTo31, twoTo31 + 1))
  fc.assert(
    fc.property(big, big, big, (i, x, k) => {
      const b = makeBackoff({ initialBackoff: PosInt(i), maxBackoff: PosInt(x), backoffMultiplier: PosInt(k) })
      return Option.isSome(b) === (i <= x && x <= twoTo31 && k <= twoTo31)
    }),
    runs
  )
})

test("backoffDelay is in (0, maxBackoff] and is A6's min(initial * k^(s-1), max)", () => {
  fc.assert(
    fc.property(backoffArb, posArb(40), (c, s) => {
      const d = backoffDelay(c, s)
      const closed = BigInt(c.initialBackoff) * BigInt(c.backoffMultiplier) ** BigInt(s - 1)
      const expect = closed <= BigInt(c.maxBackoff) ? Number(closed) : c.maxBackoff
      return d > 0 && d <= c.maxBackoff && d === expect
    }),
    runs
  )
})

test("nextWait: a hint is the wait and resets the step; no hint backs off and steps up", () => {
  fc.assert(
    fc.property(backoffArb, fc.option(natArb(1000), { nil: undefined }), posArb(30), (c, h, s) => {
      const w = nextWait(c, Option.fromNullable(h), s)
      return h === undefined
        ? w.nextStep === s + 1 && w.waitFor === backoffDelay(c, s) && w.waitFor <= c.maxBackoff
        : w.nextStep === 1 && w.waitFor === h
    }),
    runs
  )
})

test("spendAttempt lowers the budget by one, and refuses at 0", () => {
  fc.assert(
    fc.property(attemptsArb, (b) =>
      Option.match(spendAttempt(b), { onNone: () => b === 0, onSome: (b2) => b > 0 && b2 === b - 1 })
    )
  )
})
