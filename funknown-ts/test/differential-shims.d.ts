// The Node facilities the differential and wire tests need, typed by hand
// like node-shims.d.ts, because @types/node isn't installed and may not be
// added.
declare module "node:fs" {
  export function readFileSync(path: string, encoding: "utf8"): string
  export function existsSync(path: string): boolean
}

declare module "node:path" {
  export function dirname(path: string): string
}

interface ImportMeta {
  /** The directory of the current module (Node 20.11 and later). */
  readonly dirname: string
}
