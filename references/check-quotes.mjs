// Checks the vendored statements and the citations that point at them.
//
// 1. For every references/*/statements.json: every id is unique within its group,
//    every statement names a file that exists under references/, and its quote
//    appears verbatim in that file after whitespace normalisation only
//    (every run of whitespace becomes one space). No other leniency.
// 2. For every design document passed as an argument: every citation of the form
//    GROUP:ID (HS, PD, UP, DO, SS) resolves to a statement in that group.
//
// Usage: node references/check-quotes.mjs [docs/design/core.md ...]
// Exits 1 if anything fails.

import { readFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const REFS = dirname(fileURLToPath(import.meta.url));

const GROUPS = {
  HS: "http-semantics",
  PD: "problems-and-digests",
  UP: "uploads",
  DO: "drive-and-objects",
  SS: "status-and-supervision",
};

const norm = (s) => s.replace(/\s+/g, " ").trim();

let failures = 0;
const fail = (msg) => {
  failures += 1;
  console.log(msg);
};

// group dir -> Map(id -> statement)
const byGroup = new Map();
const texts = new Map();
let statementCount = 0;

const groupDirs = readdirSync(REFS)
  .filter((d) => statSync(join(REFS, d)).isDirectory())
  .filter((d) => existsSync(join(REFS, d, "statements.json")))
  .sort();

for (const dir of groupDirs) {
  const statements = JSON.parse(readFileSync(join(REFS, dir, "statements.json"), "utf8"));
  const ids = new Map();
  for (const st of statements) {
    statementCount += 1;
    for (const key of ["id", "doc", "section", "file", "quote"]) {
      if (typeof st[key] !== "string" || st[key].length === 0) {
        fail(`MISSING FIELD ${dir}:${st.id ?? "?"} ${key}`);
      }
    }
    if (ids.has(st.id)) fail(`DUPLICATE ID ${dir}:${st.id}`);
    ids.set(st.id, st);
    const path = join(REFS, st.file);
    if (!existsSync(path)) {
      fail(`NO SUCH FILE ${dir}:${st.id} -> ${st.file}`);
      continue;
    }
    if (!texts.has(path)) texts.set(path, norm(readFileSync(path, "utf8")));
    if (!texts.get(path).includes(norm(st.quote))) {
      fail(`QUOTE NOT FOUND ${dir}:${st.id} in ${st.file}`);
    }
  }
  byGroup.set(dir, ids);
}

console.log(`${groupDirs.length} groups, ${statementCount} statements, ${texts.size} vendored files read`);

// Citations in design documents.
const CITE = /\b(HS|PD|UP|DO|SS):([A-Za-z0-9][^\s`,;|]*)/g;
for (const docArg of process.argv.slice(2)) {
  const docPath = resolve(docArg);
  const text = readFileSync(docPath, "utf8");
  const seen = new Set();
  let resolved = 0;
  for (const m of text.matchAll(CITE)) {
    const group = m[1];
    // A citation can be followed by sentence punctuation; ids never end in it.
    const id = m[2].replace(/[.:)\]]+$/, "");
    const key = `${group}:${id}`;
    if (seen.has(key)) continue;
    seen.add(key);
    const st = byGroup.get(GROUPS[group])?.get(id);
    if (!st) {
      const elsewhere = [...byGroup.entries()]
        .filter(([, ids]) => ids.has(id))
        .map(([d]) => Object.keys(GROUPS).find((g) => GROUPS[g] === d));
      const line = text.slice(0, m.index).split("\n").length;
      fail(`UNRESOLVED CITATION ${key} at ${docArg}:${line}` + (elsewhere.length ? ` (exists as ${elsewhere.map((g) => `${g}:${id}`).join(", ")})` : ""));
    } else {
      resolved += 1;
    }
  }
  console.log(`${docArg}: ${seen.size} distinct citations, ${resolved} resolved`);
}

console.log(`${failures} failures`);
process.exit(failures ? 1 : 0);
