// The LiquidHaskell negative controls, translated into the TypeScript port.
//
// Each entry is a mutation the Haskell work used as a negative control (from
// docs/design/kernel.md, README.md, and the mutate.sh / mutate2.sh runs on the
// kernel), written as the same bug in the TypeScript. For each one this script
// copies the project, applies the edit, and records every layer that notices:
//
//   tsc           the build fails;
//   constructor   a test fails because a smart constructor threw at run time
//                 (Nat, PosInt, ...), or the loop's own NoProgress check fired;
//   property      the FastCheck properties and exhaustive tests that fail
//                 (every test file except Differential.test.js);
//   differential  test/Differential.test.js, which compares against the
//                 Haskell kernel's outputs, fails.
//
// Unlike run.mjs it doesn't stop at the first layer: the point is to see what
// each layer would have caught on its own. Results go to stdout and to
// controls/lh-controls.out.json. Plain JavaScript tooling, like run.mjs.
//
//   node controls/lh-controls.mjs            all controls
//   ONLY=C1,R5 node controls/lh-controls.mjs some of them
import { spawnSync } from "node:child_process"
import fs from "node:fs"
import path from "node:path"

const root = path.resolve(import.meta.dirname, "..")
const tsc = path.join(root, "node_modules", ".bin", "tsc")
const buildDir = path.join(root, "controls", `.lh-build-${process.pid}`)

const R = "src/Kernel/Reconcile.ts"
const C = "src/Kernel/Converge.ts"
const T = "src/Kernel/Types.ts"
const CL = "src/Client/Core.ts"

// lh: what LiquidHaskell said about the Haskell original. src: where the
// control comes from.
export const controls = [
  {
    id: "R1", name: "trust the store's size for the receipt", claim: "K1", lh: "UNSAFE", src: "transcript (a); README",
    file: R,
    edits: [
      ["bind(offsetOf(v.goal.assembly.chunks), ver, rep)", "bind(reportSize(rep), ver, rep)"],
      ['import type { ReceiptReport } from "../Store/Receipt.js"', 'import { type ReceiptReport, reportSize } from "../Store/Receipt.js"'],
      ['import { type Chunks, chunkList, offsetOf } from "../Upload.js"', 'import { type Chunks, chunkList } from "../Upload.js"']
    ]
  },
  {
    id: "R2", name: "remove the vouched object while ACTIVE (R13 removes)", claim: "K3", lh: "UNSAFE", src: "transcript (b); README 'removing the good object'",
    file: R,
    edits: [['onSome: (r2) => issue("R13", a, Cmd.DoDiscard({ ref: r2 })),', 'onSome: () => issue("R13", a, Cmd.DoRemove({ version: boundVersion(bound) })),']]
  },
  {
    id: "R3", name: "remove a version nobody observed (R17)", claim: "K5n", lh: "UNSAFE", src: "transcript (c)",
    file: R,
    edits: [
      ['HasObject: ({ version }) => issue("R17", a, Cmd.DoRemove({ version })),', 'HasObject: () => issue("R17", a, Cmd.DoRemove({ version: Version("") })),'],
      ['import { type Version, bind, boundVersion } from "./Bound.js"', 'import { Version, bind, boundVersion } from "./Bound.js"']
    ]
  },
  {
    id: "R4", name: "leave a staging area behind on Clear (R16 rests)", claim: "K4", lh: "UNSAFE", src: "transcript (d)",
    file: R,
    edits: [['onSome: (r) => issue("R16", a, Cmd.DoDiscard({ ref: r })),', 'onSome: () => rest("R16", a),']]
  },
  {
    id: "R5", name: "stay ACTIVE after the store lost the object (R15 rests)", claim: "K9", lh: "SAFE at first (hole), UNSAFE once K9 was added", src: "transcript (e); kernel.md K9; README",
    file: R,
    edits: [[': failWith("R15", v, Fault.StateLost())', ': rest("R15", a)']]
  },
  {
    id: "R6", name: "decide before observing (R0 opens)", claim: "K0", lh: "UNSAFE", src: "transcript (g); README 'issuing a command before observing'",
    file: R,
    edits: [['leaf("R0", a, Cmd.DoObserve(), zero, false)', 'leaf("R0", a, Cmd.DoOpen(), zero, false)']]
  },
  {
    id: "R7", name: "spend budget that isn't there (b >= 0)", claim: "Asset budget :: Nat", lh: "UNSAFE", src: "transcript (i)",
    file: "src/Http/Retry.ts",
    edits: [["case 0:\n      return Option.none()", "case 0:\n      return Option.some(-1)"]]
  },
  {
    id: "R8", name: "clear the goal as Cancelled, not Failed", claim: "K8", lh: "UNSAFE", src: "transcript (j)",
    file: R,
    edits: [
      ["(row: R, v: KeepView, fault: Fault): Leaf<R>", "(row: R, v: KeepView, _fault: Fault): Leaf<R>"],
      ["Ending.Failed({ fault })", "Ending.Cancelled()"]
    ]
  },
  {
    id: "R9", name: "seal while an orphan staging area exists (R4 seals)", claim: "none (no claim covers it)", lh: "SAFE (not caught)", src: "transcript (k)",
    file: R,
    edits: [[
      'onSome: (other) => issue("R4", a, Cmd.DoDiscard({ ref: other })),\n                onNone: () => issue("R7", a, Cmd.DoSeal())',
      'onSome: () => issue("R4", a, Cmd.DoSeal()),\n                onNone: () => issue("R7", a, Cmd.DoSeal())'
    ]]
  },
  {
    id: "R10", name: "accept any version as the vouched one", claim: "K9", lh: "UNSAFE", src: "transcript (l)",
    file: R,
    edits: [['obj._tag === "HasObject" && obj.version === boundVersion(bound)', 'obj._tag === "HasObject" && (obj.version === boundVersion(bound) || true)']]
  },
  {
    id: "R11", name: "call a file ACTIVE before its receipt", claim: "K6", lh: "UNSAFE", src: "transcript (K6)",
    file: T,
    edits: [["(hasReceipt(a.vouch) ? State.ACTIVE() : State.CREATING())", "(hasReceipt(a.vouch) ? State.ACTIVE() : State.ACTIVE())"]]
  },
  {
    id: "R12", name: "stall on leftover staging after the receipt (R13 rests)", claim: "Prog", lh: "UNSAFE", src: "transcript (p1)",
    file: R,
    edits: [['onSome: (r2) => issue("R13", a, Cmd.DoDiscard({ ref: r2 })),', 'onSome: () => rest("R13", a),']]
  },
  {
    id: "R13", name: "open while something is staged (R2 opens)", claim: "Prog", lh: "UNSAFE", src: "transcript (p2)",
    file: R,
    edits: [["onSome: (r) => adopt(v, r)", 'onSome: () => issue("R1", a, Cmd.DoOpen())']]
  },
  {
    id: "R13b", name: "open while something is staged (compiling form: the row stays R2)", claim: "Prog", lh: "UNSAFE", src: "transcript (p2)",
    file: R,
    edits: [["onSome: (r) => adopt(v, r)", 'onSome: () => issue("R2", a, Cmd.DoOpen())']]
  },
  {
    id: "R14", name: "retry forever without spending (R12)", claim: "Prog", lh: "UNSAFE", src: "transcript (p3)",
    file: R,
    edits: [
      ["onSome: (budget) => {", "onSome: () => {"],
      ["withBackoffAt(withBudget(stale(a), budget), w.nextStep)", "withBackoffAt(stale(a), w.nextStep)"],
      ["  withBudget,\n", ""]
    ]
  },
  {
    id: "R15", name: "discard the producer's own staging area (R4, assembling)", claim: "K10", lh: "SAFE at first (hole), UNSAFE once K10 was added", src: "transcript; kernel.md K10; README",
    file: R,
    edits: [[
      'onNone: () => rest("R3", a),\n                onSome: (other) => issue("R4", a, Cmd.DoDiscard({ ref: other }))',
      'onNone: () => rest("R3", a),\n                onSome: () => issue("R4", a, Cmd.DoDiscard({ ref: r }))'
    ]]
  },
  {
    id: "R16", name: "discard the producer's own staging area (R4, assembled)", claim: "K10", lh: "UNSAFE", src: "transcript",
    file: R,
    edits: [[
      'onSome: (other) => issue("R4", a, Cmd.DoDiscard({ ref: other })),\n                onNone: () => issue("R7"',
      'onSome: () => issue("R4", a, Cmd.DoDiscard({ ref: r })),\n                onNone: () => issue("R7"'
    ]]
  },
  {
    id: "R17", name: "R3 no longer a resting row", claim: "progress lemma (round)", lh: "UNSAFE", src: "transcript",
    file: T,
    edits: [["R3: true", "R3: false"]]
  },
  {
    id: "R18", name: "discard orphans before failing a missing chunk (R4 before R8)", claim: "K7", lh: "not LH: caught by the guard test", src: "README (the third problem)",
    file: R,
    edits: [[
      '          !holds(r, c, ss)\n            ? failWith("R8", v, Fault.StateLost())\n            : Option.match(firstOther(r, ss), {\n                onSome: (other) => issue("R4", a, Cmd.DoDiscard({ ref: other })),\n                onNone: () => issue("R7", a, Cmd.DoSeal())\n              }),',
      '          Option.match(firstOther(r, ss), {\n            onSome: (other) => issue("R4", a, Cmd.DoDiscard({ ref: other })),\n            onNone: () => (!holds(r, c, ss) ? failWith("R8", v, Fault.StateLost()) : issue("R7", a, Cmd.DoSeal()))\n          }),'
    ]]
  },
  {
    id: "C1", name: "drops that cost nothing", claim: "termination", lh: "UNSAFE", src: "transcript; kernel.md; README",
    file: C,
    edits: [["allowance: Nat(d - 1)", "allowance: d"]]
  },
  {
    id: "C2", name: "drops with no allowance left", claim: "termination", lh: "UNSAFE", src: "transcript; kernel.md",
    file: C,
    edits: [["return d > 0 && cmdTag(dec.command) >= 1", "return cmdTag(dec.command) >= 1"]]
  },
  {
    id: "C3", name: "late writes that never run out", claim: "termination", lh: "UNSAFE", src: "transcript; kernel.md",
    file: C,
    edits: [["forgetting(withAuthorised(a, tail), reappear(m))", "forgetting(a, reappear(m))"]]
  },
  {
    id: "C4", name: "an append that doesn't use up the cap", claim: "termination", lh: "UNSAFE", src: "transcript; kernel.md",
    file: C,
    edits: [["(c) =>\n      asset({\n        goal: assemblingGoal(r, c),", "(_c) =>\n      asset({\n        goal: assemblingGoal(r, chunks),"]]
  },
  {
    id: "C5", name: "keep going after a resting row (literal: if False)", claim: "termination", lh: "UNSAFE", src: "transcript; kernel.md",
    file: C,
    edits: [["return isResting(row)\n", "return false\n"]]
  },
  {
    id: "C5b", name: "keep going after a resting row (compiling form)", claim: "termination", lh: "UNSAFE", src: "transcript; kernel.md",
    file: C,
    edits: [["return isResting(row)\n", "return isResting(row) && d < 0\n"]]
  },
  {
    id: "C6", name: "a client can reopen a cleared goal", claim: "termination", lh: "UNSAFE", src: "transcript; kernel.md; README",
    file: C,
    edits: [["authorised: a.authorised\n        })\n      )\n    : Option.none()", "authorised: a.authorised\n        })\n      )\n    : Option.some(a)"]]
  },
  {
    id: "K1", name: "clear without an ending", claim: "KMove / Asset refinement", lh: "UNSAFE", src: "transcript (Client/Core)",
    file: CL,
    edits: [
      ["const toClear = (a: KeepAsset, ending: Ending) =>", "const toClear = (a: KeepAsset, _ending: Ending) =>"],
      ["outcome: Outcome.Ended({ ending })", "outcome: a.outcome"],
      ["  Outcome,\n", ""]
    ]
  },
  {
    id: "K2", name: "append into a different staging area (literal)", claim: "KMove", lh: "UNSAFE", src: "transcript (Client/Core)",
    file: CL,
    edits: [
      ["goal: adoptedGoal(a.goal.assembly.staging, chunks),", 'goal: adoptedGoal(Option.some(StagingRef("elsewhere")), chunks),'],
      ["  type StagingRef,\n", "  StagingRef,\n"]
    ]
  },
  {
    id: "K2b", name: "append into a different staging area (compiling form)", claim: "KMove", lh: "UNSAFE", src: "transcript (Client/Core)",
    file: CL,
    edits: [
      [
        "goal: adoptedGoal(a.goal.assembly.staging, chunks),",
        'goal: ((o: Option.Option<StagingRef>) => (Option.isSome(o) ? adoptedGoal(o, chunks) : adoptedGoal(a.goal.assembly.staging, chunks)))(Option.some(StagingRef("elsewhere"))),'
      ],
      ["  type StagingRef,\n", "  StagingRef,\n"]
    ]
  },
  {
    id: "K3", name: "append that drops the new chunk", claim: "KMove", lh: "UNSAFE", src: "transcript (Client/Core)",
    file: CL,
    edits: [["(chunks) => regrow(a, chunks))", "(_chunks) => regrow(a, a.goal.assembly.chunks))"]]
  },
  {
    id: "K4", name: "complete that also starts a write", claim: "KMove", lh: "UNSAFE", src: "transcript (Client/Core)",
    file: CL,
    edits: [
      ["    authorised: a.authorised,\n    goal: assembledGoal(", "    authorised: [new Write({ epoch: Int(0), deadline: Int(0) }), ...a.authorised],\n    goal: assembledGoal("],
      ['import type { Int } from "../Num.js"', 'import { Int } from "../Num.js"']
    ]
  },
  {
    id: "K5", name: "report that starts another write instead", claim: "KMove", lh: "UNSAFE", src: "transcript (Client/Core)",
    file: CL,
    edits: [
      ["withAuthorised(a, unlist(epoch, a.authorised))", "withAuthorised(a, [new Write({ epoch, deadline: Int(0) }), ...a.authorised])"],
      ['import type { Int } from "../Num.js"', 'import { Int } from "../Num.js"']
    ]
  },
  {
    id: "K6", name: "the client throws away the receipt", claim: "KMove", lh: "UNSAFE", src: "transcript (Client/Core)",
    file: CL,
    edits: [
      ["const toClear = (a: KeepAsset, ending: Ending) =>\n  shapedAsset({\n    seen: a.seen,\n    vouch: a.vouch,", "const toClear = (a: KeepAsset, ending: Ending) =>\n  shapedAsset({\n    seen: a.seen,\n    vouch: Vouch.NoReceipt(),"],
      ["  Write,\n", "  Vouch,\n  Write,\n"]
    ]
  },
  // Not an LH control: a bug in a function whose LH spec is only `Nat`. Run
  // against both, to see the comparison from the other side.
  {
    id: "X1", name: "pending reports the earliest deadline, not the latest", claim: "pending :: Nat (value unspecified)", lh: "see current-controls.log", src: "extra",
    file: R,
    edits: [["Nat(ws.reduce((m, w) => Math.max(m, w.deadline > now ? w.deadline - now : 0), 0))", "Nat(ws.reduce((m, w) => Math.min(m === 0 ? Infinity : m, w.deadline > now ? w.deadline - now : 0), 0))"]]
  }
]

const run = (cmd, args, cwd) => spawnSync(cmd, args, { cwd, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 })
const brandError = /expected a (natural number|positive integer|safe integer)/
const failedTests = (out) => [...new Set(out.split("\n").filter((l) => l.startsWith("\u2716")).map((l) => l.replace(/^\u2716 /, "").replace(/\s*\([\d.]+m?s\)$/, "")))].filter((l) => l !== "failing tests:")

const only = process.env.ONLY?.split(",")
const results = []
fs.rmSync(buildDir, { recursive: true, force: true })
fs.mkdirSync(buildDir, { recursive: true })
for (const c of controls.filter((x) => only === undefined || only.includes(x.id))) {
  const dir = path.join(buildDir, c.id)
  for (const part of ["src", "test"]) fs.cpSync(path.join(root, part), path.join(dir, part), { recursive: true })
  for (const f of ["tsconfig.json", "package.json"]) fs.copyFileSync(path.join(root, f), path.join(dir, f))
  fs.symlinkSync(path.join(root, "node_modules"), path.join(dir, "node_modules"))
  const target = path.join(dir, c.file)
  let src = fs.readFileSync(target, "utf8")
  let applied = true
  for (const [from, to] of c.edits) {
    const n = src.split(from).length - 1
    if (n !== 1) { applied = false; console.log(`!! ${c.id}: edit text occurs ${n} times: ${from.slice(0, 60)}`) }
    src = src.replace(from, to)
  }
  const r = { id: c.id, name: c.name, claim: c.claim, lh: c.lh, src: c.src, applied }
  if (applied) {
    fs.writeFileSync(target, src)
    const build = run(tsc, ["-p", path.join(dir, "tsconfig.json"), "--pretty", "false"], dir)
    if (build.status !== 0) {
      r.tsc = (build.stdout.split("\n").find((l) => / error TS/.test(l)) ?? "").replace(dir + "/", "").slice(0, 200)
    } else {
      const tests = fs.readdirSync(path.join(dir, "dist", "test")).filter((f) => f.endsWith(".test.js") && f !== "Differential.test.js")
      const t = run(process.execPath, ["--test", ...tests.map((f) => path.join("dist", "test", f))], dir)
      r.property = failedTests(t.stdout)
      const all = t.stdout + t.stderr
      r.ctor = brandError.test(all) ? (all.match(brandError) ?? [""])[0] : /NoProgress|did not strictly decrease|not strictly smaller/.test(all) ? "NoProgress (converge's metric check)" : null
      const d = run(process.execPath, ["--test", path.join("dist", "test", "Differential.test.js")], dir)
      r.differential = d.status !== 0
      const m = /disagreements: (\d+)/.exec(d.stdout)
      r.differentialDetail = d.status === 0 ? null : m ? `${m[1]} points disagree` : (d.stdout.match(/(the port refuses[^\n]*|expected a [a-z ]+|Error: [^\n]*)/) ?? ["failed"])[0]
      if (d.stdout.includes("NoProgress")) r.differentialDetail += "; NoProgress"
    }
  }
  results.push(r)
  const caught = [r.tsc ? "tsc" : null, r.ctor ? "constructor" : null, r.property?.length ? "property" : null, r.differential ? "differential" : null].filter((x) => x !== null)
  console.log(`${c.id.padEnd(4)} ${c.name}\n     LH: ${c.lh} | TS: ${caught.length ? caught.join(", ") : "NOT CAUGHT"}`)
  if (r.tsc) console.log(`     tsc: ${r.tsc}`)
  if (r.ctor) console.log(`     constructor: ${r.ctor}`)
  if (r.property?.length) console.log(`     properties: ${r.property.slice(0, 4).join(" | ")}`)
  if (r.differential) console.log(`     differential: ${r.differentialDetail}`)
}
fs.rmSync(buildDir, { recursive: true, force: true })
if (only === undefined) fs.writeFileSync(path.join(root, "controls", "lh-controls.out.json"), JSON.stringify(results, null, 2))
