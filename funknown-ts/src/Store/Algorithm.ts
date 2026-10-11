// Funknown.Store.Algorithm: the one checksum algorithm a store may vouch
// with, and the decoded value of a checksum in it. Nothing here, or anywhere
// in the core, computes a checksum (C CH3).
import { Brand, Data, Match, Option } from "effect"

/** C CH2: the only receipt algorithm, CRC-64/NVME. */
export type ReceiptAlgorithm = Data.TaggedEnum<{ Crc64Nvme: {} }>
export const ReceiptAlgorithm = Data.taggedEnum<ReceiptAlgorithm>()

/** Every algorithm, for exhaustive tests (Haskell's Enum, Bounded). */
export const allAlgorithms: ReadonlyArray<ReceiptAlgorithm> = [ReceiptAlgorithm.Crc64Nvme()]

/** R PD:NVME-NVMCS-1.1-5.3.1.3.4-2: "Width 64". The return type is the
 *  literal 64, so `{w:Nat | w == 64}` is the compiler's to check. */
export const width = (a: ReceiptAlgorithm): 64 =>
  Match.valueTags(a, { Crc64Nvme: (): 64 => 64 })

/** A DRS checksum type. Opaque, so drsType is the only source of one. */
class DrsType extends Data.Class<{ readonly name: string }> {
  private declare readonly nominal: "DrsType"
}
export type { DrsType }

export const drsType = (a: ReceiptAlgorithm): DrsType =>
  Match.valueTags(a, { Crc64Nvme: () => new DrsType({ name: "crc64nvme" }) })

export const drsTypeName = (t: DrsType): string => t.name

/** 2^64. */
export const checksumBound: bigint = 2n ** 64n

/** A decoded checksum value, 0 <= v < 2^64. */
export type Checksum = bigint & Brand.Brand<"Checksum">
const ChecksumC = Brand.refined<Checksum>(
  (v) => 0n <= v && v < checksumBound,
  (v) => Brand.error(`checksum ${v} is outside [0, 2^64)`)
)

/** The only producer of a Checksum: present exactly when 0 <= v < 2^64, and
 *  then holding v. */
export const checksumOf = (v: bigint): Option.Option<Checksum> => ChecksumC.option(v)

export const checksumValue = (c: Checksum): bigint => c
