// The part of Funknown.Http.Retry the kernel's types need: the attempt cap,
// gRFC A6's backoff parameters, and the wait before a retry. The rest of the
// Haskell module (Retry-After, status decisions, the token bucket) belongs to
// the shell side and isn't ported here.
import { Data, Option } from "effect"
import { type Nat, PosInt } from "../Num.js"

/** R SS:GRFC-A6-Validation-1: values above 5 are treated as 5. */
export const attemptCap: 5 = 5

/** {n:Nat | n <= attemptCap}, as a literal union, so the bound is a type. */
export type Attempts = 0 | 1 | 2 | 3 | 4 | 5

/** {n:Int | 1 <= n && n <= attemptCap}: a configured maxAttempts. */
export type MaxAttempts = 1 | 2 | 3 | 4 | 5

/** One attempt fewer, when there is one to spend. A table rather than
 *  subtraction, so the result stays an Attempts without a run-time check. */
export const spendAttempt = (b: Attempts): Option.Option<Attempts> => {
  switch (b) {
    case 0:
      return Option.none()
    case 1:
      return Option.some(0)
    case 2:
      return Option.some(1)
    case 3:
      return Option.some(2)
    case 4:
      return Option.some(3)
    case 5:
      return Option.some(4)
    default: {
      const unreachable: never = b
      return unreachable
    }
  }
}

/** 2^31. Both the cap and the multiplier stay under it. */
export const backoffBound = 2147483648

export interface BackoffFields {
  /** 0 < initialBackoff */
  readonly initialBackoff: PosInt
  /** initialBackoff <= maxBackoff <= backoffBound */
  readonly maxBackoff: PosInt
  /** 1 <= backoffMultiplier <= backoffBound */
  readonly backoffMultiplier: PosInt
}

/** gRFC A6's backoff parameters. Opaque, because two of its bounds relate
 *  fields to each other or to backoffBound, which a field type can't say. */
class Backoff extends Data.Class<BackoffFields> {
  private declare readonly nominal: "Backoff"
}
export type { Backoff }

/** The only producer of Backoff. */
export const makeBackoff = (f: BackoffFields): Option.Option<Backoff> =>
  f.initialBackoff <= f.maxBackoff && f.maxBackoff <= backoffBound && f.backoffMultiplier <= backoffBound
    ? Option.some(new Backoff(f))
    : Option.none()

/** One backoff interval after the one before, capped. Both factors are at
 *  most 2^31, so a product past 2^53 loses precision, but it is then far
 *  above the cap and the comparison still picks the cap. */
const grow = (c: Backoff, b: PosInt): PosInt => {
  const p = b * c.backoffMultiplier
  return p >= c.maxBackoff ? c.maxBackoff : PosInt(p)
}

/** The wait before retry step s (s >= 1) when the server named no delay,
 *  without jitter (R SS:GRFC-A6-Backoff). Haskell's `backoff`, renamed
 *  because Config has a field of that name. */
export const backoffDelay = (c: Backoff, s: PosInt): PosInt => {
  let d = c.initialBackoff
  for (let i = 1; i < s && d < c.maxBackoff; i++) {
    d = grow(c, d)
  }
  return d
}

/** The wait before a retry and the backoff step after it. */
export class Wait extends Data.Class<{ readonly waitFor: Nat; readonly nextStep: PosInt }> {}

/** RE3: with a delay hint the wait is exactly the hint and the step goes back
 *  to 1; without one the wait is backoffDelay c s and the step goes up by one. */
export const nextWait = (c: Backoff, h: Option.Option<Nat>, s: PosInt): Wait =>
  Option.match(h, {
    onNone: () => new Wait({ waitFor: backoffDelay(c, s), nextStep: PosInt(s + 1) }),
    onSome: (hint) => new Wait({ waitFor: hint, nextStep: PosInt(1) })
  })
