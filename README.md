# Funknown

We're modeling the internals of an ETL-style file infrastructure as a functional core in Haskell. Files get ingested, staged in an object store, verified, published and eventually deleted. Every decision about where a file is in that life, and what happens to it next, is a pure function over values. The core does no I/O. A thin shell carries out whatever the core decides and reports back what happened.

File infrastructure like this tends to fail in a handful of ways:

- a file is reported ready although nobody ever verified its bytes;
- staging areas and multipart uploads leak;
- rows sit pending forever;
- requests never get an answer;
- errors come back under the wrong status.

These failures are hard to even see when the code looks functional but its types don't say what it actually does. We wanted the opposite, a model that's honest in exactly those places. Every fact the system relies on is either in a type or proved by LiquidHaskell, and anything we can't prove is written down as a named assumption.

We also didn't want to invent vocabulary. Every state, status and recourse a client can see comes from an existing standard: RFC 9110, the IETF resumable upload draft, AIP-216 lifecycle states, google.longrunning operations, GA4GH DRS and gRPC status codes. Each one is cited to a verbatim statement in `references/`, and a script checks every citation.

## Two halves

A client's request is an event that has to be answered exactly once, in order. You can't observe a PATCH later, so the client-facing side stays an edge-triggered state machine, with a step contract that proves no request is ever dropped or answered twice.

Everything between the core and the store is a **level-triggered reconciler**, in the style of a Kubernetes controller. Nothing moves a file just because a message arrived. The reconciler compares what an asset should become with what the store was actually seen to hold, and it issues the one command that closes that gap. A dropped command, a duplicated answer or a lost report changes nothing that matters, because the next observation still shows the gap. That property is what makes the "pending forever" class of bug go away structurally, rather than one bug report at a time.

## The kernel: intent, observed reality, receipt

AIP-216 already describes things this way. Active states are ones that "typically resolve on their own into a single expected resting state". So an asset's **goal** is the resting state it's resolving toward: keep an assembled object, sealed and vouched for (ACTIVE), or hold nothing at all. The state a client sees is computed from the goal, the observation and the receipt, never stored, so it can't drift away from the facts.

```haskell
data Goal     = Keep Assembly | Clear
data Assembly = Assembling (Opt StagingRef) Chunks   -- the producer is still adding chunks
              | Assembled StagingRef Chunks          -- complete; its length is the chunks' total
```

A **receipt** is the store vouching for the whole object with a full-object CRC-64/NVME checksum. Only `vouch` can build one, and the receipt is bound to the exact object version it vouched for, so the core can't verify one object and then serve another. CRC-64/NVME detects accidental corruption, not tampering, and the model claims no more than that.

The goal only ever moves down an order, and its rank is the first thing the convergence proof counts down:

```math
\operatorname{rank}(g) =
\begin{cases}
0 & g = \mathsf{Clear} \\
1 & g = \mathsf{Keep}(\mathsf{Assembled}\ r\ c) \\
2 + \operatorname{room}(c) & g = \mathsf{Keep}(\mathsf{Assembling}\ r\ c)
\end{cases}
\qquad
\operatorname{room}(c) = \mathit{maxChunks} - |c|
```

Every append uses up a chunk of room, completing an assembly drops its rank to 1, and clearing drops it to 0. So an asset's goal can change at most $\mathit{maxChunks} + 2$ times.

## What's proved

**Safety, for every step of the reconciler.** These are LiquidHaskell refinements on `reconcile`, and every row of its decision table is checked against them. A few of them, written out:

```math
\begin{aligned}
&\text{K1}\quad \mathit{receipt}' \neq \bot \land \mathit{receipt} = \bot \;\Rightarrow\; \operatorname{size}(\mathit{receipt}') = \operatorname{total}(c) \;\land\; \operatorname{ver}(\mathit{receipt}') = \operatorname{ver}(\mathit{observed}) \\
&\text{K3}\quad \mathit{receipt} \neq \bot \land g \neq \mathsf{Clear} \;\Rightarrow\; \mathit{cmd} \neq \mathsf{Remove} \\
&\text{K9}\quad \mathit{receipt} \neq \bot \land \big(\mathit{observed\ object} = \bot \lor \operatorname{ver}(\mathit{observed}) \neq \operatorname{ver}(\mathit{receipt})\big) \;\Rightarrow\; g' = \mathsf{Clear} \\
&\text{K10}\quad g \neq \mathsf{Clear} \land \mathit{receipt} = \bot \land \mathit{cmd} = \mathsf{Discard}\ r \;\Rightarrow\; r \neq \operatorname{staging}(g)
\end{aligned}
```

In words: a receipt only ever comes from the store vouching for the right length, bound to the version it saw. Nothing removes the vouched object while the asset is meant to be kept. An asset can't stay ACTIVE once the store has lost what it vouched for. And the reconciler never throws away the staging area the producer is writing into. The decision table's 20 guards are exhaustive and mutually exclusive. A test transcribes them straight from the design document, independently of the code, and checks every combination of goal, receipt, staging areas, object, budget and pending writes: 1,320 points.

**Progress, for every round.** We wrote the store contract as a pure function, `perform`, and defined a **gap**: the number of store commands still needed to reach the goal's resting state. A round decides a command, performs it against the model, and observes the result. The lemma says that if the asset's view of the store is exact (or empty), every round either ends in a resting row or strictly lowers the metric

```math
\mu(a, m, d) \;=\; \big(\operatorname{rank}(g_a),\ d,\ b_a,\ |w_a|,\ \operatorname{gap}(a, m),\ [\,a \text{ not yet observed}\,]\big) \in \mathbb{N}^6
```

in the lexicographic order. Here $d$ is the adversary's drop allowance, $b_a$ the retry budget and $w_a$ the writes started but not yet reported.

**Convergence, over whole runs.** A run alternates the reconciler with an adversary's script of moves. The adversary can lose commands and observations (out of a finite allowance $d$, which is fairness written as a number), land late writes, let write deadlines pass, and move the goal on the producer's or a client's behalf. The script can be infinite. LiquidHaskell's termination checker accepts `converge` with $\mu$ as its metric, not the script's length, so:

```math
\forall\, \sigma \in \mathit{Move}^{\omega}.\;\; \mathrm{converge}(a, m, d, \sigma) \text{ reaches a resting row in finitely many rounds.}
```

A resting row is either converged, or waiting on something only the environment can provide: the producer's next chunk, or a write deadline.

## How we know the proofs have teeth

A claim that can't fail is vacuous, so every claim gets a negative control: a small mutation that looks like a real bug and has to make LiquidHaskell report UNSAFE. Examples are trusting the store's size, removing the good object, skipping the cleanup's confirm, issuing a command before observing, drops that cost the adversary nothing, and reopening a cleared goal.

This is how we found two holes in our own design. Each time, a mutation came back SAFE when it should have failed:

- the store losing an ACTIVE object went unnoticed (now K9);
- the reconciler could discard the producer's own staging area, and the progress measure even counted it as progress (now K10).

Each one became a claim, and the same mutation now fails. The guard test caught a third problem the same way. The design table and the code disagreed about whether a completed asset with a missing chunk should fail at once or first discard an orphaned staging area. The table was right, so we fixed the code.

## Named assumptions

These can't be proved inside the core, so we name them, so nobody mistakes the proofs for more than they are:

- **A1.** The store meets its contract. Everything the core may have created is discoverable by file id, a seal is create-only, and a remove is conditional on the version it names.
- **A2.** Fairness. The shell keeps delivering Ticks, and the store eventually performs commands. When this fails, an alarm on non-convergence makes it visible, so it doesn't show up as rows quietly pending.
- **A3.** Every write the shell starts has a hard wall-clock deadline, after which it's aborted.
- **A4.** The shell does what the core decides and nothing else.

## Layout

| Path | What's there |
|---|---|
| `funknown-core/src/Funknown/Kernel/` | the reconciler (`Reconcile`), the store model and progress lemma (`Model`), convergence (`Converge`), the version-bound receipt (`Bound`) |
| `funknown-core/src/Funknown/Upload.hs` | chunks with their invariants, proved: every chunk within bounds, only the newest may be short, total within max-size |
| `funknown-core/src/Funknown/Http/` | method semantics, the RFC 9110 precondition ladder (a port of Go's `net/http`, with its divergences documented), ranges, admission, and retry and backoff (ports of urllib3 and Go's transport, plus gRFC A6's token bucket) |
| `funknown-core/src/Funknown/Http/Status.hs`, `Rpc/`, `Digest.hs`, `Problem.hs` | generated from the vendored IANA registries and `code.proto` by `funknown-tools`; `gen-vocab --check` fails on any drift |
| `funknown-core/test/` | exhaustive checks over finite domains, and diffs against literal transcriptions of the original code |
| `docs/design/kernel.md` | the kernel's design: decision table, contract, theorems and assumptions |
| `docs/design/core.md` | the earlier edge-triggered design, whose client-facing half we're keeping |
| `references/` | the vendored primary sources, with provenance and a `statements.json` of verbatim quotes per group |

## Building

We built and checked everything with GHC 9.14.1, cabal 3.16, LiquidHaskell 0.9.14.1.1 and z3 4.16. The LiquidHaskell check runs as a GHC plugin, so building is checking:

```sh
cabal build all                            # every module must come back LIQUID: SAFE
cabal test all                             # exhaustive checks and port diffs
cabal run gen-vocab -- --repo . --check    # generated registries match their sources
node references/check-quotes.mjs docs/design/kernel.md   # every citation resolves verbatim
```

One practical warning: LiquidHaskell keeps a copy of imported specs in each module's interface, and GHC's recompilation check doesn't notice when only a spec changed. After a spec changes, build from a clean `dist-newstyle/build`.

## Status

The kernel's safety, progress and convergence are proved. Next, we're reattaching the client-facing half to the kernel: a completing upload is answered when the receipt appears, and cancel and DELETE move the goal. After that comes bounded exhaustive exploration of the composed system, then the store adapters, which have to prove or test the contract they claim to meet.
