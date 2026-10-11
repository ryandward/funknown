// @types/node isn't installed and we may not add it, so these are the few
// Node built-ins the tests use, typed by hand from the Node 26 docs. They
// type only what the tests call.
declare module "node:test" {
  export function test(name: string, fn: () => void | Promise<void>): Promise<void>
  export function describe(name: string, fn: () => void): void
}

declare module "node:assert/strict" {
  interface Assert {
    ok(value: unknown, message?: string): asserts value
    equal<T>(actual: unknown, expected: T, message?: string): asserts actual is T
    notEqual(actual: unknown, expected: unknown, message?: string): void
    deepEqual(actual: unknown, expected: unknown, message?: string): void
    throws(fn: () => unknown, message?: string): void
  }
  const assert: Assert
  export default assert
}
