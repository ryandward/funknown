// Writes src/wire/<message>.schema.json from the zod schemas in src/Wire.ts.
// test/Wire.test.ts regenerates the same text and fails when a file differs,
// so run this (npm run schema) after changing a schema. Plain JavaScript
// tooling, like controls/run.mjs.
import fs from "node:fs"
import path from "node:path"
import { jsonSchemaText, messages } from "../dist/src/Wire.js"

const dir = path.resolve(import.meta.dirname, "..", "src", "wire")
fs.mkdirSync(dir, { recursive: true })
for (const name of Object.keys(messages)) {
  fs.writeFileSync(path.join(dir, `${name}.schema.json`), jsonSchemaText(name))
  console.log(`wrote src/wire/${name}.schema.json`)
}
