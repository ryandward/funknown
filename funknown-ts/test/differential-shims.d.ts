// The two Node facilities the differential test needs, typed by hand like
// node-shims.d.ts, because @types/node isn't installed and may not be added.
declare module "node:fs" {
  export function readFileSync(path: string, encoding: "utf8"): string
}

interface ImportMeta {
  /** The directory of the current module (Node 20.11 and later). */
  readonly dirname: string
}
