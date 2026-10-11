// Funknown.Client.Core, the moves on the asset: the client side's only ways
// to change the kernel's asset, one per move the adversary in
// Funknown.Kernel.Converge may make.
//
// In LiquidHaskell each move's result type carries KMove(a, b), so every
// clause is proved. TypeScript can't state that a field of the result
// equals a field of the argument, so this module splits the work in two:
//
// - Lanes. Four private functions are the only code here that builds an
//   asset. Each copies seen, vouch, budget and backoffAt from the old asset
//   by name, and none takes any of them as a parameter. A move hands a lane
//   only what the client side owns (an ending, new chunks, the writes), so
//   a move's own code has no way to pass in a different observation,
//   receipt or budget. The lanes also take no staging area, so appendTo and
//   completeGoal can't change it, and seal takes no chunks, so completeGoal
//   completes with exactly the chunks it had.
// - Shapes. Each move's parameter and result types name the asset's shape
//   (KeepAsset, AssemblingAsset, AdoptedAsset, AssembledAsset, ClearAsset),
//   so the goal's kind can only move down its order: Keep to Clear, an
//   assembly to an assembled object, or stay where it is.
//
// What neither carries, and test/ClientCore.test.ts checks as a property:
// the lanes' bodies copy faithfully, appendTo lowers the rank and only adds
// bytes, startWrite adds exactly one write, and reportWrite never adds one.
import { Data, Option, Predicate } from "effect"
import type { Int } from "../Num.js"
import { type Chunk, type Chunks, appendChunk } from "../Upload.js"
import {
  type AssembledGoal,
  type AssemblingGoal,
  type Asset,
  type ClearGoal,
  type Ending,
  type StagingRef,
  Assembly,
  Goal,
  Outcome,
  Write,
  assembledGoal,
  shapedAsset,
  withAuthorised
} from "../Kernel/Types.js"

// Shapes --------------------------------------------------------------------------

/** An asset whose goal keeps something. */
export type KeepAsset = Extract<Asset, { readonly goal: AssemblingGoal | AssembledGoal }>
/** An asset whose goal is an assembly in progress. */
export type AssemblingAsset = Extract<Asset, { readonly goal: AssemblingGoal }>
/** An asset whose goal is an assembled object. */
export type AssembledAsset = Extract<Asset, { readonly goal: AssembledGoal }>
/** An asset whose goal is Clear. */
export type ClearAsset = Extract<Asset, { readonly goal: ClearGoal }>

/** An assembly in progress with a staging area adopted. Option.Some in the
 *  type is what lets completeGoal read the staging area without a None
 *  branch, where Haskell matches `Assembling (Present r) c`. */
export type AdoptedGoal = AssemblingGoal & {
  readonly assembly: { readonly staging: Option.Some<StagingRef> }
}
export type AdoptedAsset = AssemblingAsset & { readonly goal: AdoptedGoal }

// The guards are composed from Effect's generated $is refinements, so the
// compiler derives what they narrow to; none is a hand-written `x is T`.
// Predicate.struct wants its input to have the fields already, so each
// nested field is reached through hasProperty first.
const keepGoal = Goal.$is("Keep")
const assemblingKeep = Predicate.and(
  keepGoal,
  Predicate.compose(Predicate.hasProperty("assembly"), Predicate.struct({ assembly: Assembly.$is("Assembling") }))
)
/** Narrows an asset to one whose goal keeps something. */
export const isKeepAsset = Predicate.struct({ goal: keepGoal })
/** Narrows an asset to one whose goal is an assembly in progress. */
export const isAssemblingAsset = Predicate.struct({ goal: assemblingKeep })

/** An assembly in progress with a staging area, as an AdoptedAsset, or
 *  None. TypeScript narrows an object by a discriminant on its own fields or
 *  one level down, but not by an Option two levels down: a guard on
 *  goal.assembly.staging leaves the asset's type as it was. So this rebuilds
 *  the asset, field for field, with the narrower goal type. It takes nothing
 *  but the asset, so it can't change it. */
export const asAdopted = (a: AssemblingAsset): Option.Option<AdoptedAsset> => {
  const staging = a.goal.assembly.staging
  return Option.isSome(staging)
    ? Option.some(
        shapedAsset({
          seen: a.seen,
          vouch: a.vouch,
          budget: a.budget,
          backoffAt: a.backoffAt,
          authorised: a.authorised,
          goal: adoptedGoal(staging, a.goal.assembly.chunks),
          outcome: a.outcome
        })
      )
    : Option.none()
}

// Lanes ---------------------------------------------------------------------------
// The only code in this module that builds an asset. None of them takes
// seen, vouch, budget or backoffAt; each copies them from `a` by name.

/** Keep to Clear, with the ending. The writes stay. */
const toClear = (a: KeepAsset, ending: Ending) =>
  shapedAsset({
    seen: a.seen,
    vouch: a.vouch,
    budget: a.budget,
    backoffAt: a.backoffAt,
    authorised: a.authorised,
    goal: Goal.Clear(),
    outcome: Outcome.Ended({ ending })
  })

/** New chunks for an adopted assembly. The staging area, the outcome and the
 *  writes stay. */
const regrow = (a: AdoptedAsset, chunks: Chunks): AdoptedAsset =>
  shapedAsset({
    seen: a.seen,
    vouch: a.vouch,
    budget: a.budget,
    backoffAt: a.backoffAt,
    authorised: a.authorised,
    goal: adoptedGoal(a.goal.assembly.staging, chunks),
    outcome: a.outcome
  })

/** An adopted assembly becomes assembled, in its staging area, with its
 *  chunks. Nothing is handed in, so nothing else can change. The vouch is
 *  NoReceipt by the AssemblingAsset type, which is why the unchecked
 *  constructor accepts an assembled goal here. */
const seal = (a: AdoptedAsset) =>
  shapedAsset({
    seen: a.seen,
    vouch: a.vouch,
    budget: a.budget,
    backoffAt: a.backoffAt,
    authorised: a.authorised,
    goal: assembledGoal(a.goal.assembly.staging.value, a.goal.assembly.chunks),
    outcome: a.outcome
  })

/** New writes for an assembly in progress. The goal and outcome stay. */
const withWrites = (a: AssemblingAsset, authorised: ReadonlyArray<Write>) =>
  shapedAsset({
    seen: a.seen,
    vouch: a.vouch,
    budget: a.budget,
    backoffAt: a.backoffAt,
    authorised,
    goal: a.goal,
    outcome: a.outcome
  })

/** The goal regrow builds: the same structural value assemblingGoal builds,
 *  typed with the staging area still known present. */
const adoptedGoal = (staging: Option.Some<StagingRef>, chunks: Chunks): AdoptedGoal =>
  Data.struct({ _tag: "Keep", assembly: Data.struct({ _tag: "Assembling", staging, chunks }) })

// Moves ---------------------------------------------------------------------------

/** Abandon: a cancel, a DELETE, expiry or a refused creation clears a goal
 *  that still keeps the asset, with that ending. */
export const clearGoal = (a: KeepAsset, ending: Ending): ClearAsset => toClear(a, ending)

/** Append: a chunk the store acknowledged durable joins the assembly, if the
 *  assembly accepts it (None otherwise, where Haskell answers Absent). The
 *  rank drops by one, because the cap leaves room for one fewer chunk. */
export const appendTo = (a: AdoptedAsset, k: Chunk): Option.Option<AdoptedAsset> =>
  Option.map(appendChunk(a.goal.assembly.chunks, k), (chunks) => regrow(a, chunks))

/** Complete: the assembly is marked complete with exactly the chunks it has. */
export const completeGoal = (a: AdoptedAsset): AssembledAsset => seal(a)

/** Start a write: one more write the core started and hasn't seen reported,
 *  with the deadline by which the shell aborts it (A3). Only while
 *  assembling. */
export const startWrite = (a: AssemblingAsset, epoch: Int, deadline: Int): AssemblingAsset =>
  withWrites(a, [new Write({ epoch, deadline }), ...a.authorised])

/** Report a write: its entry goes, whatever the report said. Any shape; the
 *  shared setter withAuthorised is the lane here. */
export const reportWrite = (a: Asset, epoch: Int): Asset => withAuthorised(a, unlist(epoch, a.authorised))

/** Drops the first write with this epoch, if there is one. */
export const unlist = (epoch: Int, ws: ReadonlyArray<Write>): ReadonlyArray<Write> => {
  const i = ws.findIndex((w) => w.epoch === epoch)
  return i < 0 ? ws : [...ws.slice(0, i), ...ws.slice(i + 1)]
}
