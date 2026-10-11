// Funknown.Fault: why a transfer ended in FAILED.
import { Data } from "effect"
import type { Int } from "./Num.js"

export type Fault = Data.TaggedEnum<{
  /** max-age passed while opening or receiving */
  Expired: {}
  /** the finalize budget ran out */
  FinalizeTimedOut: {}
  /** content past the upload length */
  OutOfRange: {}
  /** an import longer than max-size */
  TooLarge: {}
  /** over quota when the upload completed */
  QuotaAtFinalize: {}
  /** access was gone when an import finished */
  Revoked: {}
  /** a zero-length import the store can't seal */
  Empty: {}
  /** the creation request's own content was refused once the upload existed */
  CreationRefused: {}
  /** the creation request's content broke off before its 201 */
  CreationInterrupted: {}
  /** the store lost the staging area */
  StateLost: {}
  /** the store's size differs from the upload length */
  SizeMismatch: {}
  /** a file exists that the store will never vouch for */
  ObjectWithoutReceipt: {}
  /** a deterministic store refusal */
  StoreRefusedUs: {}
  /** the store contradicted itself or the shell broke its contract */
  Contradiction: {}
  /** store retries exhausted */
  Unavailable: {}
  /** the origin couldn't be reached */
  SourceUnreachable: {}
  /** the origin answered with a status we don't retry */
  SourceAnswered: { readonly status: Int }
  /** the origin's representation changed under a resume */
  SourceChanged: {}
}>
export const Fault = Data.taggedEnum<Fault>()
