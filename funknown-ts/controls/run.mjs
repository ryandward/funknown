// Runs every negative control and prints a verdict for each.
//
// 1. Compile-fail controls (controls/compile/*.ts). Each line marked
//    `// @expect TSnnnn` must draw exactly that error, and no other line may
//    error, so a control can't pass by failing for an unrelated reason.
// 2. Gap demonstrations (controls/gaps/*.ts). Each must COMPILE: it shows a
//    hole GAPS.md describes. If one stops compiling, the gap may have closed
//    and GAPS.md needs a look.
// 3. Mutants (controls/mutants*.json). Each edits one source file in a fresh
//    copy of the project, then runs tsc, the tests, and the compile controls,
//    in that order. The first layer that fails is the one that caught the
//    mutant, and it has to be the layer the mutant expects.
//
// Plain JavaScript on purpose: it is tooling, not part of the port, and
// typing node:child_process and node:fs by hand would add nothing.
import { spawnSync } from "node:child_process"
import fs from "node:fs"
import path from "node:path"

const root = path.resolve(import.meta.dirname, "..")
const tsc = path.join(root, "node_modules", ".bin", "tsc")
// One build directory per run: several agents run controls at once, and a
// shared directory let one run delete or collide with another's mutants.
const buildDir = path.join(root, "controls", `.build-${process.pid}`)
fs.rmSync(buildDir, { recursive: true, force: true })
fs.mkdirSync(buildDir, { recursive: true })

const errorLine = /^(.+?)\((\d+),(\d+)\): error (TS\d+): (.*)$/
const run = (cmd, args, cwd) => spawnSync(cmd, args, { cwd, encoding: "utf8" })

// Compiles one control file with the project's options; returns tsc's exit
// status and its errors.
const compileOne = (projectRoot, file) => {
  const cfgDir = path.join(projectRoot, "controls")
  const cfg = path.join(cfgDir, `tsconfig.${path.basename(file, ".ts")}.json`)
  fs.writeFileSync(
    cfg,
    JSON.stringify({
      extends: path.relative(cfgDir, path.join(projectRoot, "tsconfig.json")),
      compilerOptions: { noEmit: true },
      include: [],
      files: [path.relative(cfgDir, file)]
    })
  )
  const r = run(tsc, ["-p", cfg, "--pretty", "false"], projectRoot)
  fs.rmSync(cfg)
  const errors = (r.stdout + r.stderr)
    .split("\n")
    .map((l) => errorLine.exec(l))
    .filter((m) => m !== null)
    .map((m) => ({ file: path.resolve(projectRoot, m[1]), line: Number(m[2]), code: m[4], text: m[5] }))
  return { status: r.status, errors }
}

const checkCompileControl = (projectRoot, file) => {
  const lines = fs.readFileSync(file, "utf8").split("\n")
  const markers = lines
    .map((l, i) => ({ line: i + 1, m: /\/\/ @expect (TS\d+)/.exec(l) }))
    .filter((x) => x.m !== null)
    .map((x) => ({ line: x.line, code: x.m[1] }))
  const { status, errors } = compileOne(projectRoot, file)
  const problems = []
  if (status === 0) problems.push("compiled cleanly")
  for (const mk of markers) {
    if (!errors.some((e) => e.file === file && e.line === mk.line && e.code === mk.code))
      problems.push(`line ${mk.line}: expected ${mk.code}, got ${errors.filter((e) => e.line === mk.line).map((e) => e.code).join(",") || "nothing"}`)
  }
  for (const e of errors) {
    if (e.file !== file || !markers.some((mk) => mk.line === e.line))
      problems.push(`unexpected ${e.code} at ${path.relative(projectRoot, e.file)}:${e.line}: ${e.text.slice(0, 120)}`)
  }
  return { markers: markers.length, problems }
}

const listTs = (dir) =>
  fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.endsWith(".ts")).sort().map((f) => path.join(dir, f)) : []

let failures = 0
const verdict = (ok, label, detail) => {
  if (!ok) failures++
  console.log(`${ok ? "PASS" : "FAIL"}  ${label}${detail ? `\n      ${detail}` : ""}`)
}

console.log("== compile-fail controls (must fail tsc, for the marked reason only)")
for (const f of listTs(path.join(root, "controls", "compile"))) {
  const { markers, problems } = checkCompileControl(root, f)
  verdict(problems.length === 0, `${path.basename(f)} (${markers} refused constructions)`, problems.join("\n      "))
}

console.log("\n== gap demonstrations (must compile: each shows a hole in GAPS.md)")
for (const f of listTs(path.join(root, "controls", "gaps"))) {
  const { status, errors } = compileOne(root, f)
  verdict(status === 0, `${path.basename(f)} compiles, so the gap is real`, status === 0 ? "" : `no longer compiles: ${errors.map((e) => e.code).join(",")}; re-check GAPS.md`)
}

console.log("\n== mutants (must be caught, by the expected layer)")
// Every controls/mutants.json and controls/mutants.<module>.json, so each
// module's port keeps its own list. MUTANTS=a.json,b.json runs only those.
const mutantFiles = fs
  .readdirSync(path.join(root, "controls"))
  .filter((f) => /^mutants(\..+)?\.json$/.test(f))
  .filter((f) => process.env.MUTANTS === undefined || process.env.MUTANTS.split(",").includes(f))
  .sort()
const mutants = mutantFiles.flatMap((f) => JSON.parse(fs.readFileSync(path.join(root, "controls", f), "utf8")))
mutants.forEach((mu, i) => {
  const dir = path.join(buildDir, `mutant-${i}`)
  for (const part of ["src", "test", path.join("controls", "compile")])
    fs.cpSync(path.join(root, part), path.join(dir, part), { recursive: true })
  for (const f of ["tsconfig.json", "package.json"]) fs.copyFileSync(path.join(root, f), path.join(dir, f))
  fs.symlinkSync(path.join(root, "node_modules"), path.join(dir, "node_modules"))

  const target = path.join(dir, mu.file)
  let src = fs.readFileSync(target, "utf8")
  const edits = mu.edits ?? [{ from: mu.from, to: mu.to }]
  for (const e of edits) {
    const count = src.split(e.from).length - 1
    if (count !== 1) {
      verdict(false, mu.name, `the edit's text occurs ${count} times in ${mu.file}; the mutant would be vacuous`)
      return
    }
    src = src.replace(e.from, e.to)
  }
  fs.writeFileSync(target, src)

  let caughtBy = "nothing (SURVIVED)"
  const build = run(tsc, ["-p", path.join(dir, "tsconfig.json"), "--pretty", "false"], dir)
  if (build.status !== 0) {
    const first = build.stdout.split("\n").find((l) => errorLine.test(l)) ?? ""
    caughtBy = `tsc: ${first.slice(0, 140)}`
  } else {
    const testFiles = fs.readdirSync(path.join(dir, "dist", "test")).filter((f) => f.endsWith(".test.js")).map((f) => path.join("dist", "test", f))
    const t = run(process.execPath, ["--test", ...testFiles], dir)
    if (t.status !== 0) {
      const failed = t.stdout.split("\n").filter((l) => l.startsWith("\u2716")).map((l) => l.replace(/\s*\([\d.]+ms\)$/, ""))
      caughtBy = `tests: ${failed.slice(0, 2).join("; ")}`
      // A mutant may name the test that has to catch it (`catches`), so a
      // claim's own property can't be stood in for by another test.
      if (mu.catches !== undefined && !failed.some((l) => l.includes(mu.catches)))
        caughtBy = `wrong test: "${mu.catches}" passed; ${failed.slice(0, 2).join("; ")}`
    } else {
      const broken = listTs(path.join(dir, "controls", "compile")).filter((f) => checkCompileControl(dir, f).problems.length > 0)
      if (broken.length > 0) caughtBy = `controls: ${broken.map((f) => path.basename(f)).join(", ")} stopped refusing`
    }
  }
  const layer = caughtBy.split(":")[0]
  verdict(layer === mu.expect, `${mu.name} [${mu.claim}]`, `expected ${mu.expect}; caught by ${caughtBy}`)
  // Each copy carries the fixture, so a hundred of them can fill a small
  // tmpfs; drop each one as soon as it has its verdict.
  fs.rmSync(dir, { recursive: true, force: true })
})

fs.rmSync(buildDir, { recursive: true, force: true })
console.log(`\n${failures === 0 ? "all controls hold" : `${failures} control(s) failed`}`)
process.exit(failures === 0 ? 0 : 1)
