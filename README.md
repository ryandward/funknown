# Funknown

**We're modeling the internals of an ETL-style file infrastructure as a pure functional core in Haskell.**

Files get ingested, staged in an object store, verified, published, and eventually deleted. In *Funknown*, every decision about where a file is in that lifecycle, and what happens to it next, is a pure function over values. The core does no I/O. A thin imperative shell carries out whatever the core decides and reports back what happened.

### Where is the "Fun" in Funknown?
Distributed systems are usually an exercise in paranoia—waiting for a dropped webhook or a race condition to leak a staging area at 3 AM. *Funknown* flips that dynamic. 

The fun here is the absolute arrogance of writing a mathematically airtight contract and then actively playing the villain against it. We deliberately introduce microscopic, bug-shaped mutations into our own code (negative controls) just to watch LiquidHaskell's termination checker scream `UNSAFE` before the project even compiles. The joy of *Funknown* is trading the anxiety of "Did I miss an edge case?" for the absolute certainty of "The compiler proved I didn't."

## The Problem
File infrastructure typically fails in a handful of invisible ways:
- A file is reported ready, although nobody ever verified its bytes.
- Staging areas and multipart uploads leak.
- Rows sit pending forever.
- Requests never get an answer.
- Errors come back under the wrong status.

These failures are hard to track down because traditional imperative code looks functional, but its types don't say what it actually does. We wanted the opposite. Every fact this system relies on is either embedded in a type or proved by LiquidHaskell. Anything we cannot prove is explicitly written down as a named assumption.

We also don't invent vocabulary. Every state, status, and recourse a client can see comes from existing standards: RFC 9110, the IETF resumable upload draft, AIP-216 lifecycle states, `google.longrunning` operations, GA4GH DRS, and gRPC status codes. Each one is tied to a verbatim statement in `references/`, and a script checks every citation to prevent drift.

## Architecture: The Two Halves

### 1. The Edge-Triggered Client
A client's request is an ephemeral event that must be answered exactly once, in order. Because you cannot observe a `PATCH` later, the client-facing side is an **edge-triggered state machine**. We prove a step contract guaranteeing no request is ever dropped or answered twice.

### 2. The Level-Triggered Reconciler
Everything between the core and the object store is a **level-triggered reconciler**, modeled after Kubernetes controllers. Nothing moves a file just because a message arrived. The reconciler compares the asset's *goal* with the *observed reality* of the store, and issues the exact command needed to close that gap. 

A dropped command, a duplicated answer, or a lost report changes nothing. The next observation will still show the gap. This structural property completely eliminates the "pending forever" class of bugs.

## The Kernel: Intent, Observed Reality, Receipt

Following AIP-216, active states "typically resolve on their own into a single expected resting state." An asset's **goal** is the resting state it is resolving toward: either keep an assembled object, sealed and vouched for (`ACTIVE`), or hold nothing at all (`DELETED`). The state a client sees is strictly computed from the goal, the observation, and the receipt—it is never stored, meaning it cannot drift from reality.

```haskell
data Goal     = Keep Assembly | Clear
data Assembly = Assembling (Opt StagingRef) Chunks   -- the producer is still adding chunks
              | Assembled StagingRef Chunks          -- complete; its length is the chunks' total
```

A **receipt** is the store vouching for the whole object using a full-object CRC-64/NVME checksum. Only `vouch` can build one, and the receipt is permanently bound to the exact object version it vouched for (closing the TOCTOU gap). 

### The Convergence Proof
The goal only ever moves down an order, and its rank is the first thing the convergence proof counts down:

$$\mathrm{rank}(g) = \begin{cases} 0 & g = \mathsf{Clear} \\ 1 & g = \mathsf{Keep}(\mathsf{Assembled}\ r\ c) \\ 2 + \mathrm{room}(c) & g = \mathsf{Keep}(\mathsf{Assembling}\ r\ c) \end{cases}$$

$$\mathrm{room}(c) = \mathit{maxChunks} - \vert{}c\vert{}$$

Every append consumes room, completing an assembly drops its rank to 1, and clearing drops it to 0. An asset's goal can change at most $maxChunks + 2$ times.

## What is Proved

### 1. Safety (Per Reconciler Step)
Evaluated via LiquidHaskell refinements on `reconcile`. The decision table's 20 guards are exhaustive and mutually exclusive. A test transcribes them straight from the design document, checking all 1,320 combinations of goal, receipt, staging areas, object, budget, and pending writes. 

Core invariants proved:
- A receipt only ever comes from the store vouching for the right length, bound to the version it saw.
- Nothing removes the vouched object while the asset is meant to be kept.
- An asset cannot stay `ACTIVE` once the store loses what it vouched for.
- The reconciler never throws away the staging area the producer is actively writing into.

### 2. Progress (Per Round)
We defined the store contract as a pure function, `perform`, alongside a **gap** metric (the number of store commands needed to reach the goal's resting state). If the asset's view of the store is exact, every round either ends in a resting row or strictly lowers the metric in lexicographic order:

$$\mu(a, m, d) \;=\; \big(\mathrm{rank}(g_a),\ d,\ b_a,\ \vert{}w_a\vert{},\ \mathrm{gap}(a, m),\ [\,a \text{ not yet observed}\,]\big) \in \mathbb{N}^6$$

### 3. Convergence (Over Whole Runs)
A run alternates the reconciler with an adversary's script of moves. The adversary can lose commands, drop observations, land late writes, let deadlines pass, and move the goal. LiquidHaskell's termination checker formally verifies that against *any* valid adversarial script, the system reaches a resting row in finitely many rounds.

## Negative Controls (How we know the proofs have teeth)

A claim that cannot fail is vacuous. Every claim in *Funknown* gets a **negative control**: a deliberate, bug-shaped mutation introduced to the code that *must* force LiquidHaskell to report `UNSAFE`.

This practice exposed two critical holes in our initial design:
1. The store losing an `ACTIVE` object went unnoticed (now patched by Theorem K9).
2. The reconciler could discard the producer's own staging area, and the progress measure falsely counted it as progress (now patched by Theorem K10).

We ran 14 bug-shaped mutations (e.g., trusting the store's size, removing the good object, drops that cost the adversary nothing). Every single one now fails the compiler. 

## Named Assumptions

Because formal verification cannot prove physical reality, we explicitly box out our operational assumptions. If the system fails, it is because one of these boundaries was breached:
- **A1. Adapter Compliance.** The store meets its contract. Everything the core creates is discoverable by file ID, seals are create-only, and removes are conditional on the version.
- **A2. Fairness.** The shell keeps delivering Ticks, and the store eventually performs commands. (If this fails, an alarm on non-convergence makes it visible).
- **A3. Hard Deadlines.** Every write the shell starts has a hard wall-clock deadline, after which it is forcibly aborted.
- **A4. Honest Rendering.** The shell strictly executes what the core decides and nothing else.

## Building & Verifying

Built and checked with **GHC 9.14.1**, **cabal 3.16**, **LiquidHaskell 0.9.14.1.1**, and **z3 4.16**. The LiquidHaskell check runs as a GHC plugin, meaning building *is* checking.

```bash
cabal build all                            # Every module must come back LIQUID: SAFE
cabal test all                             # Exhaustive checks and port diffs
cabal run gen-vocab -- --repo . --check    # Generated registries match their sources
node references/check-quotes.mjs docs/design/kernel.md # Citations resolve verbatim
```
*(Note: LiquidHaskell caches imported specs in interface files. If only a spec changes, GHC may not trigger recompilation. Always build from a clean `dist-newstyle/build` when altering specs).*
