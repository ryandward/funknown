// Funknown.Kernel.Model: the store contract as a pure function, and the
// round the progress lemma is about (decide, perform the command, observe).
//
// LiquidHaskell proves the lemma on `round`: when the asset's last
// observation is absent or exactly what the store holds (Coherent), one
// round either rests or lowers the metric (rank, budget, gap, not yet
// observed) lexicographically, and leaves the observation exact again.
//
// Here Coherent is a type: `Synced` pairs an asset with a model, and every
// producer of one either checks Coherent (`synced`) or makes it true by
// construction (`observedNow`, `forgetting`, `keepingView`). So `round`
// can't be handed an incoherent pair, and what it returns is coherent by
// construction. That the round rests or lowers the metric is a property
// test (test/Model.test.ts), not a proof.
import { Data, HashSet, Match, Option } from "effect"
import type { Nat } from "../Num.js"
import { type Version } from "./Bound.js"
import { reconcile } from "./Reconcile.js"
import {
  type Asset,
  type Cmd,
  type Decision,
  type Env,
  type Goal,
  type Row,
  type StagingRef,
  type Stagings,
  type Vouching,
  ObjectObs,
  type Observed,
  Seen,
  assembledRef,
  gapI,
  goalAdopted,
  goalTag,
  hasReceipt,
  isSeen,
  obsObjTag,
  obsRefs,
  obsStagings,
  obsVersion,
  observed,
  seenObjTag,
  seenRefs,
  seenStagings,
  seenVersion,
  staging,
  withSeen
} from "./Types.js"

/** What the store holds for one file: the staging areas and the object, as
 *  an observation would show them (discovery, contract rule 1), plus the
 *  name the store gives the next staging area, the version it gives the
 *  next sealed object, and how it will vouch for that object. No
 *  refinement, so an open class, like the Haskell constructor. */
export class Model extends Data.Class<{
  readonly obs: Observed
  readonly fresh: StagingRef
  readonly version: Version
  readonly vouching: Vouching
}> {}

const withObs = (m: Model, obs: Observed): Model =>
  new Model({ obs, fresh: m.fresh, version: m.version, vouching: m.vouching })

/** Remove every staging area named r: a Discard, or a seal consuming it.
 *  The count never grows, and drops when r was listed (a property test). */
export const dropRef = (r: StagingRef, ss: Stagings): Stagings => ss.filter((s) => s.ref !== r)

/** The contract, command by command:
 *  - Open creates a staging area, discoverable under the file's id;
 *  - Seal makes the goal's staging area the object, create-only (rule 2),
 *    and a successful seal consumes the staging area;
 *  - Discard removes the staging area it names, idempotently;
 *  - Remove removes the object only at the version it names (rule 2);
 *  - Observe and no command change nothing. */
export const perform = (g: Goal, c: Cmd, m: Model): Model => {
  const ss = m.obs.stagings
  const o = m.obs.object
  return Match.valueTags(c, {
    NoCmd: () => m,
    DoObserve: () => m,
    DoOpen: () => withObs(m, observed([staging(m.fresh, []), ...ss], o)),
    DoSeal: () =>
      Option.match(assembledRef(g), {
        onNone: () => m,
        onSome: (r) =>
          Match.valueTags(o, {
            NoObject: () =>
              withObs(m, observed(dropRef(r, ss), ObjectObs.HasObject({ version: m.version, vouching: m.vouching }))),
            HasObject: () => m
          })
      }),
    DoDiscard: ({ ref }) => withObs(m, observed(dropRef(ref, ss), o)),
    DoRemove: ({ version }) =>
      Match.valueTags(o, {
        NoObject: () => m,
        HasObject: (h) => (h.version === version ? withObs(m, observed(ss, ObjectObs.NoObject())) : m)
      })
  })
}

/** The next observation: the asset sees exactly what the store holds. */
export const observeInto = (a: Asset, m: Model): Asset => withSeen(a, Seen.Seen({ observed: m.obs }))

// Coherent, as a type ----------------------------------------------------------

/** Coherent A M: the asset's last observation, if it has one, shows exactly
 *  what the model holds, on every measure the reconciler reads. */
export const coherent = (a: Asset, m: Model): boolean =>
  !isSeen(a.seen) ||
  (seenStagings(a.seen) === obsStagings(m.obs) &&
    seenObjTag(a.seen) === obsObjTag(m.obs) &&
    HashSet.size(HashSet.difference(seenRefs(a.seen), obsRefs(m.obs))) === 0 &&
    HashSet.size(HashSet.difference(obsRefs(m.obs), seenRefs(a.seen))) === 0 &&
    Option.getEquivalence((x: Version, y: Version) => x === y)(seenVersion(a.seen), obsVersion(m.obs)))

/** An asset and the store it observes, Coherent. Opaque: the four producers
 *  below are the only way to get one, and each either checks Coherent or
 *  makes it true by construction. */
class Synced extends Data.Class<{ readonly asset: Asset; readonly model: Model }> {
  private declare readonly nominal: "Synced"
}
export type { Synced }

/** The checked producer, for a starting state: present exactly when the
 *  pair is Coherent. */
export const synced = (a: Asset, m: Model): Option.Option<Synced> =>
  coherent(a, m) ? Option.some(new Synced({ asset: a, model: m })) : Option.none()

/** The asset after observing m: its observation is m's, so Coherent holds
 *  with no check. */
export const observedNow = (a: Asset, m: Model): Synced => new Synced({ asset: observeInto(a, m), model: m })

/** The asset with its observation marked stale: Coherent holds vacuously. */
export const forgetting = (a: Asset, m: Model): Synced =>
  new Synced({ asset: withSeen(a, Seen.Unseen()), model: m })

/** Another asset on the same store, carrying the old asset's observation:
 *  Coherent held for that observation on this model, so it still does. */
export const keepingView = (s: Synced, b: Asset): Synced =>
  new Synced({ asset: withSeen(b, s.asset.seen), model: s.model })

// The round ------------------------------------------------------------------------

/** The gap measured against the store, not against the asset's observation:
 *  GapM in Haskell, and the metric's fifth component. The lemma's order,
 *  Lower, is transcribed in test/Model.test.ts rather than here, so a
 *  mutant of the code can't change the property it is held to. */
export const gapM = (a: Asset, m: Model): Nat =>
  gapI(goalTag(a.goal), goalAdopted(a.goal), hasReceipt(a.vouch), obsStagings(m.obs), obsObjTag(m.obs))

/** One round's result. Its pair is Synced, so Coherent after the round is a
 *  type; the rest of the lemma is a property test. */
export class Round extends Data.Class<{ readonly synced: Synced; readonly row: Row }> {}

/** Observe the store after the command: the asset's new observation is
 *  exactly the store's state. */
const finish = (d: Decision, n: Model): Round => new Round({ synced: observedNow(d.next, n), row: d.row })

/** The round for a decision, whatever reached it. In Haskell the decision's
 *  type is `Step a`, which carries K0 to K13 and Prog; here it is any
 *  Decision, and the reconciler's claims are the reconciler's tests. */
export const roundWith = (s: Synced, d: Decision): Round => finish(d, perform(s.asset.goal, d.command, s.model))

/** Progress: one round of the real reconciler against the honest store. */
export const round = (env: Env, s: Synced): Round => roundWith(s, reconcile(env, s.asset))

