# funknown-core: the merged design

Status: design only, no Haskell source in the repo yet. Written 2026-10-09 against the five vendored reference groups under `references/`, revised the same day after the citation review, revised again after the verifiers checked that revision against the references and against a LiquidHaskell spike, and revised a third time after a second verification pass. The `experiments/` tree belongs to an abandoned premise and is ignored on purpose.

We had three independent designs for the pure core of a B2B drive that manages uploads, URL imports and downloads: `core-protocol.md` (protocol-first), `core-proof.md` (proof-first, with a LiquidHaskell spike) and `core-operations.md` (operations-first, built around timing failures). This document replaced all three with one design, and the brief's two rules still shape everything: every state, status, reason and recourse the core can express comes from a vendored standard, and a file becomes available only when the store vouches for it with a full-object checksum receipt. Both rules have to hold while movers die, reports arrive late and cancels race completions, so I kept them in the types and in one per-file transition function, where LiquidHaskell or an exhaustive check proves them.

The citation review showed us three structural problems, and the lead decided how to fix each one, so this design applies all three throughout rather than as an appendix:

1. **The core had been speaking S3.** Multipart uploads, part numbers, HeadObject and S3 error codes were all over the core, so the core could only ever talk to one vendor and its proofs were partly proofs about AWS documentation. I moved all of that into a second pure package, `funknown-store-s3`, described in its own section near the end. I gave the core abstract store commands and per-command answers instead, so it talks to "the store" only in the vocabulary the standards give it (RFC 9110 method semantics, RFC 9530 checksums, DRS objects, AIP-151 operations), plus the brief's receipt rule.
2. **Many citations claimed more than their statements said.** A SHOULD was being cited as if it were a MUST, and some of our own choices were being cited to statements that only permit them. I gave every decision, constructor, transition and theorem a basis that is exactly one of Required, Permitted or Chosen, and the Haskell design carries the same thing as a provenance type.
3. **The brief requires CRC-64/NVME.** The earlier draft had picked CRC32C because its DRS name was registered. The brief doesn't leave that open, so I made the receipt algorithm a closed type with exactly one constructor, and recorded naming it in DRS as a Permitted deviation from two DRS SHOULDs.

The verifiers then found that the first two fixes hadn't gone all the way down. The S3 shape was still in the store contract (one-part-minimum seals, per-chunk tokens as a requirement, no answer for "a file exists and will never carry a receipt"), and the provenance machinery would have pulled every adapter citation back into the core. Several rows still cited options as requirements, and the table had cells with no row, timers nobody scheduled, and a few states a file could never leave. Most of those had one root each: a store answer type that was shared by every command, a provenance type that only one package could own, and a timer that didn't name its file. I fixed those three things first, and most of the individual findings closed with them. Where I didn't take a finding's suggestion, the "Review notes" at the end say why.

The second verification pass, which ran its own LiquidHaskell spikes against the design's shapes, found 38 more problems, and once again most of them came from a handful of things we hadn't modelled. The first was that the types admitted states the table never reaches: a Sealing file with an incomplete upload, a phase holding another phase's slot, an import in a client upload's slot, an offset with no bound when the length is unknown. Since `stepFile`'s postconditions quantify over every value of the type, those states made several theorems unprovable, and they also hid real gaps, such as a file that expired while its Open was in flight and so threw away the staging area the Open created. I gave each phase its own slot type, put the reachability facts into data refinements, and added the missing max-size bound. The second was that `World` did work no proof could see: it set `doneAt`, asked for the retention Ticks, applied the throttle and forgot files. I moved all of that into `stepFile`'s output, so it falls under the same postconditions as everything else. The third was that some theorems were stated over ghost or partial state (an `advertised` field, `held` but not the slot, a backoff index that didn't exist), so I restated them as postconditions over the commands a step emits, the same shape that already went through for RE7. The rest were citations that attached a client's rule, a definition or an SDK's behaviour to a choice of ours, and a few places where the store contract still had S3's shape: the chunk write couldn't name its staging area, and the deny-list would have failed the core's own build.

## How a citation is written

Every grounded claim cites a statement id from one group's `statements.json`, prefixed with the group, because 68 ids appear in more than one group and 42 of those carry different quotes (`HS:RFC9110-15-5` and `PD:RFC9110-15-5` are different sentences). A citation only identifies a quote as a (group, id) pair.

- `HS:` references/http-semantics/statements.json
- `PD:` references/problems-and-digests/statements.json
- `UP:` references/uploads/statements.json
- `DO:` references/drive-and-objects/statements.json
- `SS:` references/status-and-supervision/statements.json

Each statement carries `doc`, `section`, `level` and the verbatim `quote`, so an id resolves to the document, section and normative text. Reference code without a statement id is cited by path and line under `references/`. Every citation in this file is checked by `node references/check-quotes.mjs docs/design/core.md`, which resolves each (group, id) in its group's `statements.json` and confirms every vendored quote appears verbatim, whitespace-normalised, in the file it names.

The earlier revision vendored RFC 5789 (`references/http-semantics/rfc5789.txt`, ids starting `RFC5789-`), because the upload draft appends with PATCH and RFC 9110 doesn't define it, and RFC 4648 (`references/problems-and-digests/rfc/rfc4648.txt`, ids starting `RFC4648-`), because the S3 adapter decodes base64 checksum values. For this revision I added four statements from the already-vendored HeadObject page (`PD:S3API-HeadObject-request-header-ChecksumMode-2`, `PD:S3API-HeadObject-response-header-ChecksumCRC64NVME-1`, `PD:S3API-HeadObject-response-header-ChecksumType-1`, `PD:S3API-HeadObject-response-header-ContentLength-1`), because the adapter's receipt query had been cited to a sentence about KMS permissions. The problems-and-digests `PROVENANCE.md` records them.

## How a basis is written

Every decision, constructor, transition and theorem carries a nonempty list of bases, and each basis is exactly one of these:

- **Required** cites a MUST, a MUST NOT, or a definition that leaves us no choice. Written `R` followed by the citations.
- **Permitted** cites a SHOULD, a MAY or an option the standard leaves open, and says which side we took and why. Written `P` followed by the citations and the number of the entry in the Permitted register (`PM1` and so on), which records the side and the reason.
- **Chosen** is a product or engineering choice that no vendored statement makes. It has no citation, only a one-line rationale in the Chosen register (`CH1` and so on). The brief's own rules are Chosen too, since the brief isn't a vendored standard, and they're marked "(brief)" there.

A cell like "R `UP:RESUMABLE-UPLOAD-13-4.1.1-7`; P `UP:RESUMABLE-UPLOAD-13-4.6-4` (PM8); C CH30" says the row exists because of one MUST, one SHOULD we followed, and one choice of ours. The registers sit near the end of this document; the core's Chosen register is the list the product owner should read. The S3 adapter keeps its own registers, numbered `SCH1` and so on, in its own section.

A Required citation has to be a statement whose `level` is MUST or definition, and the definition has to leave no choice: a definition phrased as an option ("might make ... inaccessible", "is preferred", "can use this problem type") is Permitted. Statements addressed to clients are never Required of us, because we can't make a client follow a SHOULD. When a theorem predicts what a client does, its claim says which client it assumes ("for a client that follows ..."), and the client statements it relies on are a Permitted basis (PM42 for AIP-194, PM43 for the upload draft): the side we took is to design for that client. A theorem whose basis includes a Chosen entry says "(our policy)" in its claim, because it proves what we decided, not what a standard requires.

In Haskell this becomes the provenance type. The type itself names no citation and no register, so each package can instantiate it with its own:

```
-- funknown-core, Funknown.Basis: vendor-free and register-free
data Basis c w r = Required c | Permitted c (Side w) | Chosen r
data Side w      = Took w | Declined w

-- funknown-core: generated from the core's citations and the core's two registers
type CoreBasis = Basis Cite Why Rationale
class Provenance t where provenance :: t -> NonEmpty CoreBasis

-- funknown-store-s3: generated from the adapter's citations and the adapter's registers
type S3Basis = Basis S3.Cite S3.Why S3.Rationale     -- S3.Rationale = CoreRationale Rationale | SCH1 | ...
class S3Provenance t where s3Provenance :: t -> NonEmpty S3Basis
```

Haskell2010 has neither associated types nor multi-parameter classes, so each package has its own class rather than one class with a type function. Every closed type in each package has to have an instance of its own package's class, and two different checks hold us to that. Within an instance, LiquidHaskell's totality check rejects a `provenance` that misses a constructor, which the review spike confirmed. Nothing in GHC or LiquidHaskell notices a type with no instance at all, though, so `check-cites` lists every `data` and `newtype` declaration under `funknown-core/src` and `funknown-store-s3/src` and fails when one has no instance of its package's class. The adapter can point at a core register entry through `CoreRationale` (its credential rows rest on CH24), but the core can't name anything the adapter generates. `check-cites` reads the levels from `statements.json` and fails the build when a `Required` cites a SHOULD, MAY or informative statement. It keeps no list of exceptions that would let a SHOULD through. The one list it keeps runs the other way: it names the definition-graded statements that are phrased as options (`UP:RESUMABLE-UPLOAD-13-4.1.4-7`, `HS:RFC9110-15.5.5-2` and every other statement this document cites only under P), and it refuses those as Required.

## The decisions

The "From" column says which earlier design a decision came from, "new" if it came from the citation review, and "verify" if it came from the verification pass.

| Decision | Basis | From | Why, in one line |
|---|---|---|---|
| Two pure packages: `funknown-core`, which names no store vendor, and `funknown-store-s3`, which depends on the core and maps S3 into the core's store answers | C CH25 | new | The core's proofs should be about the standards, and the core shouldn't change when the store does. |
| Both packages use `base`, `containers`, `liquidhaskell == 0.9.14.1.1`, `Haskell2010`, every module Safe | C CH26 | protocol, operations | The brief needs `step` over the whole state, which needs a map; GHC2021 drags in GeneralizedNewtypeDeriving, which Safe refuses. |
| The verified unit is `stepFile` on one file; `step` over the world is a lift | C CH27 | proof, operations | LiquidHaskell can't see inside `Data.Map`, so every machine-checked theorem is stated per file. |
| The provenance type is parameterised over citations and registers, and each package generates its own `Cite`, `Why` and `Rationale` | C CH4, CH25 | verify | A single generated `Cite` in the core would have had to carry every adapter citation, which is S3 vocabulary inside the core. |
| Every closed type has a provenance in its own package, and a citation that doesn't resolve fails to compile | C CH4 | operations, protocol, new, verify | A constructor without a basis fails LiquidHaskell's totality check, a type without an instance fails `check-cites`, and Required can't hide a SHOULD. |
| Generators and the citation checker are Haskell executables in a separate `funknown-tools` package | C CH26 | proof | One language for the repo, and the core still depends only on base, containers and liquidhaskell. |
| `Status` has 62 constructors: the assigned registry rows minus the two "(Unused)" rows | R `HS:IANA-HTTP-Status-Codes-306`, `HS:IANA-HTTP-Status-Codes-418`, `HS:RFC9110-15.5.19` | proof | Unused rows define no semantics, so 306 and 418 are unrepresentable rather than forbidden by a check. |
| Received statuses decode through one `fromWire :: Int -> Status` | R `HS:RFC9110-15-4`, `HS:RFC9110-15-5`; P `HS:RFC9110-15-6` (PM38) | proof | Its refinements verified symbolically for every Int in the spike. |
| Status classes are a reflected table with a case split, never `div`; optional values use `Opt`, `Len` and `Lookup`, never `Maybe` | C CH27 | protocol, proof | The `div` version failed under PLE, and `isJust` is not a logic name in this LiquidHaskell build. |
| A file's life is the six AIP-216 states CREATING, ACTIVE, FAILED, CANCELLED, DELETING, DELETED | R `SS:AIP216-EnumValues-4`, `SS:AIP216-Active-3`, `SS:AIP216-Resting` | proof, operations | AIP-216 is the only vendored state vocabulary, and each of the six has a use case here. |
| FAILED, CANCELLED and DELETED absorb every later client event; only their own cleanup moves inside them | C CH10 | proof | AIP-216 lets a user move a resting resource on; we don't offer any action that does. |
| Browser uploads and URL imports share one `Upload` record, one chunk acknowledgement event and one `appendChunk` | R `UP:RESUMABLE-UPLOAD-13-4.1.2-1`; C CH39 | protocol | The draft lets the server mark an upload complete itself; sharing the record is our engineering choice. |
| Every 2xx append is exactly one durable chunk: min-append-size = max-append-size = the store profile's chunk size, whatever store sits behind the core | P `UP:RESUMABLE-UPLOAD-13-4.1.4-5`, `UP:RESUMABLE-UPLOAD-13-4.1.4-6` (PM16); C CH28 | operations, verify | Chunk k then always covers the same byte range, so a late duplicate write can't corrupt anything however the store keys its writes; with S3 this makes every browser PATCH exactly the part size, open question 14. |
| The offset is the byte count of the chunks the store acknowledged durable, refined equal to them, and never above max-size | R `UP:RESUMABLE-UPLOAD-13-4.1.1-7`, `UP:RESUMABLE-UPLOAD-13-4.6-3`; P `UP:RESUMABLE-UPLOAD-13-4.1.4-3` (PM16); C CH1 | protocol, verify | An offset that is a measure of acknowledged chunks can't exceed what the store holds, so it can never have to go back down; the max-size bound is what keeps the chunk count under the cap when the length is unknown. |
| Each phase of CREATING carries its own slot type, and a data refinement ties the phase to the upload and the slot to the source | C CH27 | verify | `stepFile`'s postconditions quantify over every value of the type, so a state the table never reaches has to be unbuildable. |
| Length and completion invariants are data refinements on `Upload`; completion is set only by an explicit event | R `UP:RESUMABLE-UPLOAD-13-4.1.3-6`, `UP:RESUMABLE-UPLOAD-13-4.1.3-8`, `UP:RESUMABLE-UPLOAD-13-4.4.2-7` | proof | They verified in the spike. |
| `Chunks` carries its own chunk size and chunk cap, copied from the plan at creation | C CH27, CH28 | verify | A data refinement can only name its own fields, and the review spike verified this encoding. |
| An interrupted append keeps nothing of a partial chunk | P `UP:RESUMABLE-UPLOAD-13-4.4.2-2` (PM9); C CH28 | operations | A durable chunk is all-or-nothing, and the draft's keep-the-prefix rule is a SHOULD. |
| Every file has one async slot and one fencing epoch; a report from a superseded epoch changes nothing | R `UP:RESUMABLE-UPLOAD-13-4.6-3`; C CH29 | operations | Verified on a reduced `stepFile` in the operations probe. |
| A new request during Appending terminates the old one; during a chunk write it abandons the old reply and defers the new request, except a cancel, which ends the file at once | P `UP:RESUMABLE-UPLOAD-13-4.6-4` (PM8); C CH30 | operations and proof, merged | Terminating is what the draft recommends; deferring while a chunk write is in flight means two writes never race on one chunk. |
| The core speaks to the store only through `StoreCommand`, one answer type per command, and a written store contract | C CH6, CH25 | new, verify | With one answer type per command, GHC checks that every cell handles exactly the answers that command can get. |
| The store profile says what the core may ask of a store: chunk size, chunk cap, and whether it can seal an empty file | C CH6, CH15 | verify | Limits that differ between stores belong to the adapter, not to the core's contract. |
| `Receipt` is abstract, only `vouch` builds one, and its algorithm is the closed type `ReceiptAlgorithm = Crc64Nvme` | R `PD:NVME-NVMCS-1.1-5.3.1.3.4-2`; C CH1, CH2 | all three, new | A file can't be described as ready unless the store vouched for it with the one algorithm the brief allows. |
| A deterministic store answer at seal or ask ends the file at once in a named Fault; Ambiguous, Unavailable, NotYetVouched and StagingGone lead to asking for the receipt; the seal is re-sent only after the store says nothing is there | P `HS:RFC9110-9.2.2-4`, `SS:GRFC-A6-Retryable-1` (PM3); C CH7, CH8 | operations, new, verify | A write acknowledgement is never proof, an ambiguous seal is never blindly repeated, and an answer that would repeat identically isn't asked again. |
| The finalize budget has its own Fault, `FinalizeTimedOut`, whatever the last store answer was | R `SS:GRPC-STATUSCODES-DEADLINE_EXCEEDED`; C CH37 | verify | The same expiry used to end in three different statuses depending on which answer came last. |
| The reply to a completing request is held until the store answers, bounded by `replyWait`, after which it is a 202 | P `UP:RESUMABLE-UPLOAD-13-4.4.2-4` (PM11); C CH22 | protocol | The draft says the server SHOULD answer as the targeted resource would, and the bound keeps held requests finite. |
| A cancel during sealing waits for the store and accepts "completed despite cancellation" | R `SS:LRO-CancelOperation-1`, `SS:LRO-CancelOperation-2`; C CH9 | operations | Cancellation is best effort by definition, and a sealed file the store vouched for is the better outcome. |
| Permission is checked before routing, so a forbidden file is never disguised as 404 and an unknown id is never revealed as unknown | R `SS:AIP193-PermissionDenied-1`; P `HS:RFC9110-15.5.4-4` (PM1) | operations, verify | AIP-193 makes it a MUST on the Operations surface, and one rule is simpler than two. |
| Authorization at finalize uses the completing event's own access verdict | P `UP:RESUMABLE-UPLOAD-13-13-6`, `UP:RESUMABLE-UPLOAD-13-13-7` (PM12) | operations | No extra round trip; proof's `Reauthorize` command and its waiting state went away. |
| Errors come from two tables, `Refusal` (a request answered now) and `Fault` (a transfer that ended), and a `Refusal` carries no google.rpc.Code | C CH33 | operations, new | Every status, problem type and Operation error code is derived from one place. |
| Each Fault's google.rpc.Code is ours to pick; the code's definition is what the Fault has to fit | R each code's definition row; C CH36 | verify | The earlier draft cited gRPC library-generated transport rows for HTTP origin fetches. |
| `Response` is a sum type whose MUST-carry headers are constructor fields | R `HS:RFC9110-15.5.2-2`, `HS:RFC9110-15.5.6`, `HS:RFC9110-15.3.7.1`, `HS:RFC9110-15.4.5-2` | proof | Verified in the spike (a 401 can't be built without a challenge). |
| A `Problem` has no status field; every 4xx and 5xx except on HEAD carries one; the draft's two problem types sit behind a flag that is off by default | R `PD:RFC9457-3.1.2-2`, `PD:RFC9457-3-1`; P `UP:RESUMABLE-UPLOAD-13-7.1-1`, `UP:RESUMABLE-UPLOAD-13-7.2-1` (PM23); C CH40 | proof, protocol, operations | The status member is copied from the response, so the two can't disagree. |
| Unrecognised methods answer 501; a recognised method the resource doesn't support answers 405 with Allow | R `HS:RFC9110-15.6.2`, `HS:RFC9110-15.5.6` | new | 501 is RFC 9110's answer for a method the server doesn't recognise at all. |
| PATCH is neither safe nor idempotent | R `HS:RFC5789-2-1` | new | RFC 5789 says so. |
| An import that the origin refused fails with UNKNOWN, carrying the origin's status | R `SS:GRPC-STATUSCODES-UNKNOWN`; C CH16, CH36 | proof | UNKNOWN is described as a status from another error space; the gRPC HTTP-to-Code table is for gRPC clients. |
| An import whose source changed fails with ABORTED; we never restart from zero | R `SS:GRPC-STATUSCODES-ABORTED`; C CH17, CH36, CH39 | proof | The offset then never decreases for any transfer; for imports that is our rule carried over from uploads, since an import has no upload resource for the draft's MUST to bind. |
| An import resumes only with a strong ETag in If-Range | R `HS:RFC9110-15.3.7.3-1`, `HS:RFC9110-13.1.5-3` | all three | Ranges only combine under one strong validator. |
| A close-delimited import body counts as an interruption | C CH18 | operations | Implicit framing can't tell a truncated body from a whole one, and the store would vouch for the truncation; open question 6. |
| Retries are bounded by an attempt counter (gRFC A6, at most 5), the transfer's deadline, and one connection-failure retry, in every state that retries | R `SS:GRFC-A6-Validation-1`, `SS:GRFC-A6-MaxAttempts-2`; P `HS:RFC9110-9.2.2-8` (PM4); C CH31 | proof, operations, verify | One counter plus one deadline; OTP restart intensity was dropped so there is no second limiter on the same thing. |
| Backoff is gRFC A6 with exact pushback and a backoff step that resets after a delay hint, jitter is the shell's, and a gRFC A6 token bucket for the store lives in the world state, moved only by the delta `stepFile` reports | R `SS:GRFC-A6-Pushback-3`, `SS:GRFC-A6-Throttling-1`, `SS:GRFC-A6-Throttling-2`, `SS:GRFC-A6-Throttling-3`; C CH31 | operations, verify | One delay rule for the store and the origins, and a store outage doesn't become a retry storm across files. Only `stepFile` knows whether a report was current, so only it can say how the bucket moves. |
| `stepFile`'s output carries everything a step does: the next file, its commands (including `Retire`, which `step` lifts to forgetting the file) and the throttle delta; `stepFile` itself sets `doneAt` and asks for the retention Ticks | C CH5, CH27 | verify | `World` isn't machine-checked, so anything it decided on its own would sit outside every theorem. |
| Retry on a received status is urllib3's rule plus 421, 425, 408 and a no-repeat rule for 507 | P `HS:RFC9110-15.5.20-2`, `HS:RFC8470-5.2-2`, `HS:RFC9110-15.5.9-2` (PM5); R `HS:RFC4918-11.5-2`; C CH31 | proof | Each addition is an RFC sentence urllib3 doesn't model; the 507 rule applies to imports under our reading in CH31. |
| Every timer names its file, and every row that sets an instant the core will act on asks for a `Tick` at it | C CH5 | verify | Abandoned uploads, retention and tombstones used to depend on Ticks nobody requested. |
| A file's ETag is derived from its never-reused file id and sent strong | R `DO:DRS-DrsApiPrinciples.DRS-IDs-2`, `HS:RFC9110-8.8.1-2`; C CH32 | operations | Content is immutable per DRS id, and no store validator needs to leak through. |
| Content of a non-ACTIVE file is 404 while CREATING and 410 once ended or deleted; DRS GetObject is 202 while CREATING and 404 once ended | R `HS:RFC9110-15.5.11-1`, `DO:DRS-responses.404NotFoundDrsObject-1`; P `HS:RFC9110-15.5.5-2` (PM41), `DO:DRS-responses.202Accepted-1` (PM36) | protocol | Split by surface: DRS defines 202 for "delayed" and has no 410. |
| DELETE on a CREATING file is 409 | R `HS:RFC9110-15.5.10-1`; C CH11 | operations | Cancellation has its own verbs, and a delete racing a seal has no good answer. |
| DELETE on a DELETED file is 410, whatever its preconditions say | R `HS:RFC9110-15.5.11-1`, `HS:RFC9110-13.2.1-2`; P `HS:RFC9110-15.5.5-2` (PM41) | verify | Its unconditional answer is 410, so RFC 9110 requires the preconditions to be ignored. |
| Terminal records answer 410 until the tombstone is dropped, then 404 | R `HS:RFC9110-15.5.11-1`; P `HS:RFC9110-15.5.5-2` (PM41), `HS:RFC9110-15.5.11-3` (PM30); C CH12 | all three | Our resources are not WebDAV resources, so RFC 4918's 404-after-DELETE MUST doesn't bind them. |
| RFC 4918 reaches us only through the 507 status code it registers | C CH12 | new | We don't implement collections, properties or locks, so applying some WebDAV MUSTs and not others would be arbitrary. |
| A missing parent folder at creation is 409 | R `HS:RFC9110-15.5.10-1`; C CH13 | operations | Folders are our product model; 409 is the status RFC 9110 defines for a conflict the user can resolve. |
| A client digest could only be forwarded to the seal if a registered key named the receipt algorithm, and none does, so every client integrity field is refused with digest-unsupported-algorithms | P `PD:DIGEST-PROBLEMS-3.1-1`, `PD:RFC9530-2-2` (PM24); C CH2 | protocol, verify | Refusing is fail-closed; ignoring would let a client believe a check happened; open question 1. |
| Downloads never carry Repr-Digest | C CH19 | new | The digest registry has no key for CRC-64/NVME, and the brief forbids coining one. |
| The DRS checksum type is `crc64nvme` | P `DO:DRS-schemas.Checksum.type-1`, `DO:DRS-schemas.Checksum.type-2` (PM26); C CH2 | new | The brief requires CRC-64/NVME, and neither the Named Information registry nor DRS's suggested list names it. |
| A zero-length file is refused with 501 only when the store profile says the store can't seal an empty file | R `HS:RFC9110-15.6.2`; C CH15 | operations, verify | A store may be unable to seal zero chunks, and that is the store's limit, not a rule of the core. |
| No interim responses, so no 104 | P `UP:RESUMABLE-UPLOAD-13-4.4.2-8`, `UP:RESUMABLE-UPLOAD-13-4.2.2-7` (PM10) | proof, operations | 104 is a TEMPORARY registration expiring 2026-11-13, and empty-content creation makes it unnecessary. |
| Retry-After appears only on 202, 429 and 503, only as delay-seconds | R `DO:DRS-responses.202Accepted.Retry-After-1`; P `HS:RFC9110-10.2.3-4` (PM7), `HS:RFC9110-15.6.4-2`, `HS:RFC6585-4-2` (PM6); C CH20 | all three | DRS requires integral seconds, the core has no clock to format a date, and leaving it off 507 is our choice. |
| A ready file is described as a DRS object, with `available` always true | R `DO:DRS-schemas.DrsObject-1`, `DO:DRS-schemas.AccessMethod.available-1` | protocol | DRS is the only vendored file representation; this core never moves objects to archival storage. |
| Every file has a google.longrunning Operation whose `response` is the DRS object and which carries no `metadata` | P `SS:AIP151-Guidance-1`, `SS:LRO-Operation-response` (PM32); C CH21, CH44 | proof, operations, new, verify | DRS names every field of the response, and no vendored statement names progress fields, so metadata went out. The `@type` URL that `response` needs as a `google.protobuf.Any` is coined, which is a second exception to CH4; open question 13. |
| A 202 that has a status monitor embeds the operation in its body and never carries Location | P `HS:RFC9110-15.3.3-3` (PM45); R `HS:RFC9110-10.2.2-1` | verify | RFC 9110 defines Location only for 201 and 3xx, and says a 202's representation should point to or embed the status monitor. |
| An append without Upload-Offset is refused with 400 | R `HS:RFC9110-15.5.1`; C CH43 | verify | The draft puts the MUST on the client and names no server answer; 400 is RFC 9110's status for a perceived client error. |
| A creation request is refused in full before anything is created when its declared lengths already break a limit, and a creation request whose content fails once the upload exists ends the file with UC ?1 | P `UP:RESUMABLE-UPLOAD-13-4.2.3-2` (PM44); C CH45 | verify | The client never learned the upload resource, so nothing could resume it, and the draft's own example answers a refused creation with UC ?1. |
| An Operation error's ErrorInfo reason is the Fault's name, which is an exception to CH4 | R `SS:AIP193-Status.details-3`, `SS:AIP193-ErrorInfo-2`, `SS:AIP193-ErrorInfo-4`; C CH21 | verify | AIP-193 requires a distinct reason per logically different error and names none; open question 11. |
| Range: one range, ignored on a zero-length representation | P `HS:RFC9110-14.2-1`, `HS:RFC9110-14.2-5` (PM27) | proof | Keeps multipart/byteranges out of the core and avoids a zero-byte 206. |
| The precondition ladder is a port of Go's, with five fixes, and no "already applied" exception | R `HS:RFC9110-13.2.2-1`, `HS:RFC9110-13.2.1-2` | union of all three, verify | Each fix is a sentence of RFC 9110 13.1 or 13.2 that Go doesn't follow; the one row that used the exception contradicted 13.2.1. |
| `Recourse` is AIP-194's three sections exactly, over the 18 names AIP-194 lists, as a model of what clients do | P `SS:AIP194-NonRetryable-0`, `SS:AIP194-GenerallyNonRetryable-0` (PM42) | new, verify | AIP-194 tells clients what to do; we design for clients that follow it, which we can't require. |
| An append to a completed upload that no MUST covers gets 409 with UC ?0 and no Upload-Offset | P `UP:RESUMABLE-UPLOAD-13-4.1.2-6`, `HS:RFC5789-2.2-2` (PM21) | verify | A client following the draft then retrieves the offset, sees UC ?1 and stops, and nothing claims the targeted resource's semantics. |

What went out, because no vendored statement grounds it here or because a simpler grounded choice covered it: OTP supervision and restart intensity (shell runtime policy), the `Disclosure`/hide policy, code.proto's HTTP mapping, Recourse tokens on the wire, an AIP-151 file view with invented JSON names, Operation progress metadata, 104 interim responses, a single-part store path, the archival `available = false` flow, the `Reauthorize` round trip, restarting an import from byte 0, the AWS backoff formula, destination faults other than a missing parent, following 3xx in the core, REPAIRING, the CRC-64/NVME oracle, Funnel, WebDAV locks and the rest of WebDAV, tusd's 423 and 500-on-timeout, the CRC32C store default, every S3 name in the core, and in the previous revision the `AlreadyApplied` verdict, the `DigestMismatch` Fault and Refusal and the digest-mismatched-values problem type (they could only follow a forwarded digest, which can't exist today), and the modelled-client exception in `check-cites`. In this revision the shared `Slot` type, the `advertised` ghost field, Location on a 202, a cancel in Opening that waited in a flag, the negative-pushback stop rule (no input we receive can carry one), and the deny-list's case-insensitive fragments of S3 error codes and Smithy enum values went out too.

## What the prover allows

The design only promises proof shapes that went through in one of the five scratch spikes (the three earlier ones and the two the verification passes ran; GHC 9.14.1, LiquidHaskell 0.9.14.1.1, z3 4.16.0). Where the text below says "the review spike" it means either verification spike. The rules that came out of them:

1. `{-# LANGUAGE Safe #-}` works with `-fplugin=LiquidHaskell`, `--reflection` and `--ple`, including a Safe module importing `Data.Map.Strict`.
2. Specs can't mention `Maybe` (`isJust` and `fromJust` aren't logic names). Every optional thing is our own two-constructor type with a measure.
3. A field refinement enters the context only when the code pattern-matches the constructor. Code that relies on a record invariant matches `Upload cs l c`; it never uses selectors there.
4. `ProofCombinators` isn't exposed by this build, so the core carries a fifteen-line `Funknown.Proof` with `===`, `***`, `?` and `QED`. Exhaustive proofs over large enumerations need explicit equational steps.
5. z3 can tell `Char` literals apart but can't order them. Character classes are equality disjunctions, and anything needing ranges (ETag, HTTP-date and Structured Field scanning) stays in the shell. The adapter's base64 alphabet is a 64-way equality table for the same reason.
6. Integer division breaks PLE in reflected code, so classes are reflected tables with a case split, and the base64 decoder keeps its arithmetic out of reflection.
7. Reflecting `run`, which calls the non-reflected `stepFile`, prints "Assume Overwrites Specifications for StepFile.stepFile": LiquidHaskell names the non-reflected callee, not the reflected caller. The spikes showed it is harmless there, so CI allows that warning for `stepFile` and fails on it for any other name. Because `stepFile` is not reflected, every per-step claim about it is a postcondition on its `Out`, stated over measures such as `eventTag`, `phaseTag` and `lifeTag`; that is the shape the proof spike verified for `step`.
8. The generated status module takes about 45 seconds; nothing else measured came close.
9. A data refinement can only name fields of its own constructor and inline constants. A bound that lives in another record has to be copied into the refined one, which is why `Chunks` carries its own chunk size and cap. The review spike also needed the conjunct "an empty chunk list has total 0", which the measure can't infer from the count.
10. Record field names have to be unique per module: GHC rejects duplicates under Haskell2010, and with DuplicateRecordFields LiquidHaskell still rejects them ("Multiple specifications"). Under `--reflection` a field name can't even be shared by two constructors of the same type, although GHC allows that when the types agree: LiquidHaskell turns every field into an SMT accessor, and z3 refuses a datatype with a repeated accessor ("repeated accessor identifier"), so the whole module crashes instead of checking. A field named `len` clashes with LiquidHaskell's list measure in every module that imports it unqualified, so the upload's length field is `uploadLen`.
11. `^` doesn't parse in a spec. Bounds are written as literals (`18446744073709551616`) or inline constants.
12. `Text` has no measures, so anything a proof inducts over is `[Char]`; the shell unpacks header values before handing them over.
13. z3 handles the nonlinear step from `s <= m*c`, `o == (k-1)*c + l` and `o <= s` to `k <= m`, so the plan's max-size can be refined against the chunk cap. The step only has something to work with when a guard actually keeps `o <= s`: the review spike's `appendChunk` call failed its `nChunks < cmax` precondition until the caller checked `offset + n <= maxSize`, and then it went through.
14. LiquidHaskell's termination check rejects a function that calls itself on a changed argument with no decreasing measure. A row that "handles the new request as if the file were Idle" is therefore written as a direct call to the Idle column's handler, which calls nothing back, not as a second call to `stepFile`.
15. An empty data declaration is accepted, but the logic can't see that the type has no values, so `not (isPresent o)` doesn't follow for an arbitrary `o :: Opt Forwarded`. A "never Present" fact has to be a refinement on the field that holds it.

## Package and module layout

```
funknown-core/
  funknown-core.cabal          base, containers, liquidhaskell == 0.9.14.1.1; Haskell2010; -fplugin=LiquidHaskell
  src/Funknown/
    Proof.hs                   (===), (***), (?), QED
    Opt.hs                     Opt a = Absent | Present a; Len = Unknown | Known Nat; measures
    Basis.hs                   Basis c w r, Side w (vendor-free, register-free)
    Cite.hs                    GENERATED from basis-core.json: Cite (one constructor per (group,id) the core cites), doc, section, level, quote
    Register.hs                GENERATED from basis-core.json: Why, Rationale; CoreBasis; class Provenance
    Http/Status.hs             GENERATED from http-status-codes-1.csv: Status, Registration, Class, statusCode, classOf, fromWire
    Http/Method.hs             Method, Recognised, safe, idempotent
    Http/Validator.hs          EntityTag, strongMatch, weakMatch
    Http/Precondition.hs       Cond, Verdict, ladder (port of Go fs.go)
    Http/Range.hs              RangeSpec, Resolved, resolve
    Http/Admission.hs          Access, admit
    Http/Retry.hs              onStatus (port of urllib3), onConnection (port of Go transport), backoff, Throttle (gRFC A6)
    Digest.hs                  GENERATED keys: DigestKey, KeyStatus, ClientDigest, Forwarded, forwardable
    Problem.hs                 GENERATED registered rows the core uses plus the draft's two: ProblemType, Problem
    Rpc/Code.hs                GENERATED from code.proto: Code, codeNumber
    Rpc/Recourse.hs            GENERATED from AIP-194: Aip194Name, Recourse, recourse, listedAs
    Store/Algorithm.hs         ReceiptAlgorithm, width, drsType, Checksum
    Store/Receipt.hs           ReceiptReport, Receipt (abstract), vouch, toHex
    Store/Protocol.hs          StagingRef, ChunkToken, StoreProfile, StoreCommand, StoreReport and its per-command answers, Failure, StoreRefusal
    Upload.hs                  Chunk, Chunks, Upload, UploadLimit, Plan, appendChunk
    File.hs                    File, Life, Creation, Phase, Call, Recv, Req, Retry, Cleanup, Object, Fault
    Refusal.hs                 Refusal, refusalStatus, refusalProblem
    Event.hs, Command.hs       FileEvent, WorldEvent, Env, FileCommand, Command
    StepFile.hs                stepFile, run (every per-file theorem lives here)
    World.hs                   World, step :: World -> WorldEvent -> (World, [Command])
    Project/Response.hs        Response, status, fields
    Project/Drs.hs             drsObject, accessUrl
    Project/Operation.hs       Op, operationOf
    Theorems.hs                multi-step theorems over run
  test/Exhaustive.hs           proofs by exhaustion over finite domains, and port diffs against transcriptions
  test/Port/                   literal transcriptions of the originals: GoFs.hs, Urllib3.hs, GoTransport.hs, Tusd.hs
funknown-store-s3/             depends on funknown-core; the core may not import it (see "The S3 adapter")
funknown-tools/
  gen-vocab                    reads the vendored CSV, XML, proto, TypeScript arrays, statements, basis-core.json and basis-s3.json; writes the GENERATED modules of each package
  check-cites                  every Cite resolves in its group, its quote is unchanged since review, every Required cites a MUST or a definition that isn't on the option list, and every data or newtype declaration has a provenance instance
  check-vendor                 the vendor boundary lint described below
```

The generated modules are committed. CI regenerates them and fails on any diff, so the registries can't change under us silently. `funknown-tools` may depend on whatever it needs to parse JSON and XML, because it is not the core.

`basis-core.json` holds the bases of the core's decisions, constructors, rows and theorems, with the citations they make and the core's two registers; `basis-s3.json` holds the same for the adapter's section and the adapter's register. Citations that only appear in this document's prose, such as the list of newly vendored statements, belong to neither. Each is generated from this document, and `gen-vocab` writes each package's `Cite` and register module from its own file only. `check-vendor` fails the build in four cases:

- a module under `funknown-core/src` imports `funknown-store-s3`;
- a module under `funknown-core/src` other than `Store/Protocol.hs` uses the constructor of `StagingRef` or `ChunkToken`, so the core can carry what a store hands back but never look inside it;
- the core's `Cite` contains any problems-and-digests id from the adapter's citation families, which are the ids starting `S3API-`, `S3UG-`, `S3-SMITHY-`, `AWS-`, `AWSSDK-` or `SMITHY-TS-`;
- an identifier, string literal or comment in a module under `funknown-core/src` matches the deny-list. Tokens are split into segments at case changes, underscores and hyphens, and an entry matches when it equals a run of consecutive segments, case-sensitively, so `x-amz-meta` and `isS3Error` match while `draws` and `compute` don't. The deny-list has two parts. The first is a fixed list of spellings that only a vendor uses: `S3`, `AWS`, `Aws`, `amz`, `Smithy`, `Multipart`, `MpuObjectSize`, `PartNumber`, `FULL_OBJECT`, `COMPOSITE`, `ChecksumCRC64NVME`, `NoSuchUpload`, `NoSuchKey`, `SlowDown`, `Lifecycle`. The brief's own phrase "full-object checksum" stays legal, which is why `FULL_OBJECT` is matched in S3's upper-case spelling only. The second is generated from the constructors of the adapter's `S3Call` type, which are the S3 operations the adapter actually calls (CreateMultipartUpload, UploadPart, CompleteMultipartUpload, HeadObject, AbortMultipartUpload, ListParts, DeleteObject), matched case-sensitively as whole tokens. It is generated from that type rather than from citation ids, because the adapter's ids also name data-type and error pages (`S3API-Checksum-...`, `S3API-Error-...`), and a generator reading ids would have banned the core's own `Checksum`.

S3 error codes and Smithy enum values are deliberately not on the list. They coincide with names the core legitimately generates from IANA and RFC 9110 (`ServiceUnavailable`, `PreconditionFailed`, `RequestTimeout`, `NotImplemented`) and from the CRC catalogue and the digest registry (`Crc64Nvme`, `Crc32c`, `Sha256`), so a fragment match on them would fail the core's own build, and the only way out would be an exception list. Instead, `gen-vocab` checks the deny-list against every identifier the core's generators produce from non-vendor sources, and it fails when one matches, so the list can only hold spellings that really are vendor-only, and nobody gets to add a per-word exception. For the same reason `UploadId` isn't on the list: S3 has an upload ID, but the core's `UploadId` names the draft's upload resource.

## The types

Haskell identifiers are internal names. Whatever reaches a client is a token the cited statement defines: a registry code, a header field name, a problem type URI, an AIP-216 state name, a google.rpc.Code name or a DRS field. The one exception is the ErrorInfo reason, which CH21 records.

### Http.Status (generated)

```
data Registration = Permanent | Temporary | Obsoleted
data Class        = Informational | Successful | Redirection | ClientError | ServerError
data Status       = H100_Continue | ... | H511_NetworkAuthenticationRequired       -- 62 constructors
statusCode :: Status -> {v:Int | 100 <= v && v <= 599}
fromWire   :: n:Int -> {v:Status | (valid n => classOf v == classOfCode n) && (not (valid n) => v == H500_InternalServerError)}
```

- Basis of every constructor: R its registry row (`HS:IANA-HTTP-Status-Codes-100` through `HS:IANA-HTTP-Status-Codes-511`, one statement per row), named from the registry's description. The CSV has 75 rows: 11 unassigned ranges and 64 assigned codes, of which 306 and 418 are "(Unused)" (`HS:IANA-HTTP-Status-Codes-306`, `HS:IANA-HTTP-Status-Codes-418`, `HS:RFC9110-15.5.19`) and get no constructor.
- `Class`: R `HS:RFC9110-15-3`, decided by the first digit (`HS:RFC9110-15-2`).
- `Temporary` is only 104 (`HS:IANA-HTTP-Status-Codes-104`); `Obsoleted` is only 510 (`HS:IANA-HTTP-Status-Codes-510`). They exist so `fromWire` can name what it receives; no `Response` maps to them.
- `fromWire`: R `HS:RFC9110-15-4` (an unrecognized code is its class's x00) and `HS:RFC9110-15-5` (outside 100..599 is invalid); P `HS:RFC9110-15-6` (PM38), the client SHOULD that processes an invalid code as 5xx. It only runs on statuses we receive from an origin.
- There is no 499, because the registry has none (`HS:IANA-HTTP-Status-Codes-452-499`), so code.proto's "499 Client Closed Request" (`SS:RPC-CODE-CANCELLED-http`) can't be emitted.

### Http.Method

```
data Method     = GET | HEAD | POST | PUT | DELETE | CONNECT | OPTIONS | TRACE | PATCH
data Recognised = Known Method | Unrecognised
```

- GET, HEAD, OPTIONS, TRACE are safe: R `HS:RFC9110-9.2.1-2`. Those plus PUT and DELETE are idempotent: R `HS:RFC9110-9.2.2-1`. POST: R `HS:RFC9110-9.3.3-1`.
- PATCH exists because the draft appends with it (R `UP:RESUMABLE-UPLOAD-13-4.4.1-1`), and it is neither safe nor idempotent: R `HS:RFC5789-2-1`. A received patch document must suit the resource (R `HS:RFC5789-2-3`), which is why the media type is checked before anything is appended.
- A recognised method that the target resource doesn't support answers 405 with Allow (R `HS:RFC9110-15.5.6`). A method the server doesn't recognise answers 501 (R `HS:RFC9110-15.6.2`, "the appropriate response when the server does not recognize the request method"). CONNECT is recognised and never supported, so it gets 405.

### Http.Validator, Http.Precondition, Http.Range

```
data EntityTag  = EntityTag { weak :: Bool, opaque :: OpaqueTag }     -- R HS:RFC9110-8.8.3-2, HS:RFC9110-8.8.3-3
data Cond       = CAbsent | Holds | Fails                              -- an ignored header is CAbsent
data MethodKind = MGet | MHead | MUnsafe
data RangeReq   = NoRange | RangeOnly | RangeIfRange Cond
data Verdict    = V412 | V304 | Proceed Ranged
data RangeSpec  = IntRange Nat Nat | OpenRange Nat | Suffix Nat
data Resolved   = Satisfied { first :: Nat, lastPos :: {v:Nat | first <= v} } | Unsatisfiable | Ignore
resolve :: n:Nat -> RangeSpec -> {v:Resolved | (n == 0 => v == Ignore) && (isSatisfied v => lastPos v < n)}
```

- Strong and weak comparison: R `HS:RFC9110-8.8.3.2-1`, `HS:RFC9110-8.8.3.2-2`; the table in `HS:RFC9110-8.8.3.2-3` is a theorem. The core only emits strong tags, derived from the file id, which is never reused, for content that never changes (R `DO:DRS-DrsApiPrinciples.DRS-IDs-2`, `HS:RFC9110-8.8.1-2`; C CH32).
- `Cond` is the evaluation of each header: R `HS:RFC9110-13.1.1-4`, `HS:RFC9110-13.1.2-5`, `HS:RFC9110-13.1.3-4`, `HS:RFC9110-13.1.4-5`, `HS:RFC9110-13.1.5-5`. The MUST-ignore cases (`HS:RFC9110-13.1.3-1`, `HS:RFC9110-13.1.3-2`, `HS:RFC9110-13.1.4-1`, `HS:RFC9110-13.1.4-2`, `HS:RFC9110-13.1.5-2`) become `CAbsent` before the ladder runs.
- There is no "already applied" verdict. RFC 9110 lets an origin answer 2xx to a failed If-Match or If-Unmodified-Since when the change "appears to have already been applied to the selected representation" (`HS:RFC9110-13.1.1-6`, `HS:RFC9110-13.1.4-7`), but the only row that used it was a DELETE on a deleted file. That request's unconditional answer is 410, so RFC 9110 requires every precondition on it to be ignored (R `HS:RFC9110-13.2.1-2`), and a deleted file has no selected representation either. I removed the verdict rather than keep a MAY that could only override a MUST.
- A date validator is always weak until the rules of `HS:RFC9110-8.8.2.2` are vendored, so a date If-Range is false (R `HS:RFC9110-13.1.5-4`).
- The ladder runs only where the response would otherwise be 2xx (R `HS:RFC9110-13.2.1-2`). It takes an `origin` argument that is constant `True` at every call site, so the theorem that a non-origin ignores If-Match and If-Unmodified-Since is stated (`HS:RFC9110-13.2.2-2`, `HS:RFC9110-13.2.2-3`).
- Range forms: R `HS:RFC9110-14.1.1-1`, `HS:RFC9110-14.1.1-3`; an invalid range is defined by R `HS:RFC9110-14.1.1-2` and ignored under P `HS:RFC9110-14.2-4` (PM27); last-pos clamps (R `HS:RFC9110-14.1.2-3`); a long suffix selects everything (R `HS:RFC9110-14.1.2-4`); satisfiability is R `HS:RFC9110-14.1.2-5`; Range is honoured only for GET (R `HS:RFC9110-14.2-2`). Range is ignored on a zero-length representation and several ranges are served as if Range were absent (P `HS:RFC9110-14.2-5`, `HS:RFC9110-14.2-1`, PM27).

### Http.Admission

```
data Access = NoCredentials | InvalidCredentials | Insufficient | Allowed   -- the shell's verdict, per request
data Admit  = A401 | A403 | Clear
```

- 401 for missing or invalid credentials, with a challenge: P `HS:RFC9110-11.4-1` (PM2); R `HS:RFC9110-15.5.2-2`. 403 for valid but inadequate ones: P `HS:RFC9110-11.4-2` (PM2); R `HS:RFC9110-15.5.4-1`.
- Permission is checked before existence and answered 403 whether or not the file exists: R `SS:AIP193-PermissionDenied-1`; P `HS:RFC9110-15.5.4-4` (PM1, declined). Existence is only checked once admission is `Clear` (R `SS:AIP193-PermissionDenied-2`), which is why admission runs before the World routes a request by id (guard G0 below). RFC 4918's authorization-first rules aren't cited here, because our resources aren't WebDAV resources (CH12).

### Http.Retry

```
data RetryAfter = NoRetryAfter | DelaySeconds Nat | DateDelta Int
data Decision   = RetryIn Nat | RetryOnNewConnection | DoNotRetry
onStatus     :: Method -> {c:Int | 100 <= c && c <= 599} -> RetryAfter -> Decision
data ConnFault  = NothingWritten | ReadFailed | IdleClosed | FreshConnClosed
onConnection :: Method -> ConnFault -> Bool -> Decision
{-@ inline attemptCap @-}
attemptCap = 5                                                              -- R SS:GRFC-A6-Validation-1: values above 5 are treated as 5
type Attempts    = {n:Nat | n <= attemptCap}                                -- every attempt counter in the core
type MaxAttempts = {n:Int | 1 < n && n <= attemptCap}                       -- the configured value, a runtime field of Config
type BackoffStep = {n:Nat | n >= 1}                                         -- which backoff interval comes next; not an attempt count
backoff :: Config -> BackoffStep -> {d:Nat | d <= maxBackoff}               -- R SS:GRFC-A6-Backoff, without jitter
data Wait = Wait { waitFor :: Nat, nextStep :: BackoffStep }
nextWait :: cfg:Config -> hint:Opt Nat -> s:BackoffStep
         -> {w:Wait | (isPresent hint => nextStep w == 1) && (not (isPresent hint) => nextStep w == s + 1 && waitFor w == backoff cfg s)}
data Throttle = Throttle                                                    -- R SS:GRFC-A6-Throttling-1, SS:GRFC-A6-Throttling-2
  { maxTokens  :: {m:Int | m > 0}                                           -- milli-tokens, configured
  , tokenRatio :: {r:Int | r > 0}                                           -- milli-tokens per success, configured
  , tokens     :: {t:Int | 0 <= t && t <= maxTokens} }
data Delta = NoCall | CallFailed | CallSucceeded                           -- how one current store answer moves the bucket
```

`attemptCap` is an inline constant, so a data refinement can name it, while the configured `maxAttempts` (open question 5) is a runtime value that the guards compare against: "attempts left" means `attempts < maxAttempts cfg`, and the refinement guarantees `attempts <= 5` whatever the configuration says.

`onStatus` is only used on origins (the store's answers arrive already classified by the adapter). It tries these rules in order, each with its basis:

1. 507 is never repeated: R `HS:RFC4918-11.5-2`, under our reading that an import fetch is the result of the user's StartImport (C CH31).
2. 421 retries on a new connection for any method: P `HS:RFC9110-15.5.20-2` (PM5).
3. A non-idempotent method is not retried: P `HS:RFC9110-9.2.2-4` (PM3).
4. 425 retries: P `HS:RFC8470-5.2-2` (PM5).
5. 408 may be repeated: P `HS:RFC9110-15.5.9-2` (PM5).
6. 413, 429 and 503 with Retry-After retry after the delay, and everything else is `DoNotRetry`: C CH31 (urllib3's `status_forcelist` rule, ported).

Delay-seconds is `1*DIGIT` (R `HS:RFC9110-10.2.3-7`). A server's delay is used exactly once, then backoff restarts from its initial value (R `SS:GRFC-A6-Pushback-3`). That needs a counter of its own, because the attempt counter never resets, so every retry loop keeps a `BackoffStep` next to its attempt counter, and every retrying row computes its wait with `nextWait`: with a delay hint the wait is the hint and the step goes back to 1, and without one the wait is `backoff cfg s` and the step goes up by one. RE3 is stated over that step. gRFC A6 also says a negative or unparseable pushback means "don't retry" (`SS:GRFC-A6-Pushback-2`), but that rule is about its own `grpc-retry-pushback-ms` metadata, which nothing we talk to sends. Retry-After has no negative form, the store's hints are `Opt Nat`, and a Retry-After date already in the past asks the client to wait no time at all, so `DateDelta` clamps to 0, which means retry now. The rule has no input in our types, so the design doesn't model it, and it doesn't loosen anything we adopted.

A connection failure gets at most one automatic retry (P `HS:RFC9110-9.2.2-8`, PM4); the flag resets once a retried fetch has a chunk made durable, since that retry didn't fail. Only retryable failures move the throttle down (R `SS:GRFC-A6-Throttling-3`), and only `stepFile` knows whether a store answer was current and retryable, so it reports the move as the `Delta` in its output: `CallFailed` for a current `Unavailable` or `Ambiguous`, `CallSucceeded` for a current `Done`, and `NoCall` otherwise, including every stale report, which changes nothing. `step` applies that delta to `storeBucket` and does nothing else to it. The deadline applies across all attempts (R `SS:GRFC-A6-MaxAttempts-2`). Adopting gRFC A6 for calls that aren't gRPC is our choice (CH31); once adopted, its rules are Required of us, which is why every theorem about them says "(our policy)". When the throttle denies a retry (`retryAllowed` false), gRFC A6 doesn't retry, so every retrying row in the table treats "throttled" the same as "no attempts left".

### Digest and Problem

| `DigestKey` | Status | Basis |
|---|---|---|
| `Sha512` | Active | R `HS:RFC9530-7.2-1`, `PD:IANA-DIGEST-ALGS-sha-512-1` |
| `Sha256` | Active | R `HS:RFC9530-7.2-2`, `PD:IANA-DIGEST-ALGS-sha-256-1` |
| `Md5` | Deprecated | R `HS:RFC9530-7.2-3`, `PD:IANA-DIGEST-ALGS-md5-1` |
| `Sha` | Deprecated | R `HS:RFC9530-7.2-4`, `PD:IANA-DIGEST-ALGS-sha-1` |
| `Unixsum` | Deprecated | R `HS:RFC9530-7.2-5`, `PD:IANA-DIGEST-ALGS-unixsum-1` |
| `Unixcksum` | Deprecated | R `HS:RFC9530-7.2-6`, `PD:IANA-DIGEST-ALGS-unixcksum-1` |
| `Adler` | Deprecated | R `HS:RFC9530-7.2-7`, `PD:IANA-DIGEST-ALGS-adler-1` |
| `Crc32c` | Deprecated | R `HS:RFC9530-7.2-8`, `PD:IANA-DIGEST-ALGS-crc32c-1` |

```
data ClientDigest = ClientDigest DigestKey Octets     -- a parsed integrity field a client sent
data Forwarded                                        -- GENERATED: one constructor per registered key that names a ReceiptAlgorithm; none today
forwardable :: ClientDigest -> {v:Opt Forwarded | not (isPresent v)}   -- GENERATED with this refinement while Forwarded has no constructor
type NoForward = {o:Opt Forwarded | not (isPresent o)}                  -- GENERATED likewise; the type of Seal's forwarded argument
```

- `KeyStatus = Active | Deprecated`: R `PD:RFC9530-5-3`; no key is Provisional today.
- The registry has no key for CRC-64/NVME. That fact drives two decisions, and neither is Required. Downloads never carry Repr-Digest (C CH19): the only checksum the store vouches for has no registered key, and the brief forbids coining one. The earlier draft had argued this from the MUST NOT in `PD:RFC9530-5-2`, but that sentence only forbids Deprecated keys "in a potentially adversarial setting, for example, when signing", and whether serving files is such a setting is our judgment, not the RFC's, so it doesn't carry the decision.
- The second decision is what happens to a client's integrity field. A client digest can only be checked by the store if it is in the receipt algorithm, so `gen-vocab` generates `Forwarded` with one constructor per registered key that names one; today that is none, and Haskell2010's empty data declaration makes `Forwarded` uninhabited. LiquidHaskell's logic can't see that a type is empty, though, so the review spike could prove `not (isPresent v)` for `forwardable`'s result but not for an arbitrary `Opt Forwarded`. So while `Forwarded` has no constructor, `gen-vocab` also emits the refinement `not (isPresent o)` on `forwardable`'s result and on `Seal`'s forwarded argument (the `NoForward` type), and drops both refinements in the same commit that adds the first constructor. "The seal's forwarded argument is always `Absent`" therefore follows from that refinement, not from the empty declaration, and every client integrity field is refused with digest-unsupported-algorithms (P `PD:DIGEST-PROBLEMS-3.1-1`, `PD:RFC9530-2-2`, PM24). The forward path stays in the store command's type so that a future key needs no new command, but no row, Fault or theorem pretends to exercise it. Open question 1 asks whether to accept an unregistered `crc64nvme` key instead.
- The core never computes a digest. No event carries representation bytes, and no function takes bytes and returns a `Receipt` or DRS checksum. That rule is the brief's (C CH3), not RFC 9530's.

| `ProblemType` | Members | Status | Basis |
|---|---|---|---|
| `AboutBlank` | none | the response's | R `PD:IANA-PROBLEM-TYPES-about:blank-1`, `PD:RFC9457-4.2.1-1`, `PD:RFC9457-3.1.1-2`; P `PD:RFC9457-4.2.1-2` (PM35) |
| `DigestUnsupportedAlgorithms` | `unsupported_algorithms` | 400 | R `PD:IANA-PROBLEM-TYPES-digest-unsupported-algorithms-1`, `PD:DIGEST-PROBLEMS-3.1-2`; P `PD:DIGEST-PROBLEMS-3.1-1` (PM24) |
| `MismatchingUploadOffset` | `expected-offset`, `provided-offset` | 409 | R `UP:RESUMABLE-UPLOAD-13-14.4-1`; P `UP:RESUMABLE-UPLOAD-13-7.1-1`, `UP:RESUMABLE-UPLOAD-13-7.1-2` (PM23) |
| `InconsistentUploadLength` | none | 400 | R `UP:RESUMABLE-UPLOAD-13-14.4-2`; P `UP:RESUMABLE-UPLOAD-13-7.2-1` (PM23) |

- `Problem` has no status field. The renderer copies the response status in, so R `PD:RFC9457-3.1.2-2` holds by construction. The core never writes `detail` or `instance` (`PD:RFC9457-3.1.4-1`, `PD:RFC9457-3.1.5-1`).
- Every 4xx and 5xx response except one to HEAD carries a problem object as `application/problem+json`. The media type's name is R `PD:RFC9457-3-1`, HEAD's lack of content is R `HS:RFC9110-9.3.2-1`, and using problem details on every error is our choice (C CH40), since RFC 9457 doesn't require them.
- `digest-invalid-values` and `digest-mismatched-values` have no constructor. The core never parses a digest value, and a mismatch could only follow a forwarded digest, which can't exist today.
- The last two rows are IANA requests, not registry rows. With `draftProblemTypes = False` the same responses carry `AboutBlank` and keep the status the draft requires (open question 2).

### Rpc.Code and Rpc.Recourse (generated)

`Code` has the 17 values `SS:GRPC-STATUSCODES-OK` through `SS:GRPC-STATUSCODES-UNAUTHENTICATED`, each R its row, with `codeNumber :: Code -> {v:Int | 0 <= v && v <= 16}` taken from code.proto, where UNAUTHENTICATED = 16 is declared between 7 and 8. The core uses a Code only in `Operation.error` (R `SS:AIP151-Errors-2`). code.proto's HTTP mapping is not ported, because it needs 499.

```
data Recourse   = Retryable | NonRetryable | GenerallyNonRetryable      -- AIP-194's three sections, by their own headings
data Aip194Name = A_UNAVAILABLE | A_OK | A_CANCELLED | ... | A_UNAUTHORIZED | ... | A_UNIMPLEMENTED   -- 18 names
recourse :: Aip194Name -> Recourse
listedAs :: Code -> Aip194Name                                           -- total and injective; A_UNAUTHORIZED has no preimage
```

AIP-194 has exactly three sections, "Retryable codes", "Non-retryable codes" and "Generally non-retryable codes", and `Recourse` has one constructor per section, named after it. `Aip194Name` has one constructor per name AIP-194 lists, 18 in all, generated from the statements:

- Retryable: UNAVAILABLE (`SS:AIP194-Retryable-UNAVAILABLE`).
- Non-retryable: OK, CANCELLED, DEADLINE_EXCEEDED, INVALID_ARGUMENT, DATA_LOSS (`SS:AIP194-NonRetryable-0`, `SS:AIP194-NonRetryable-OK`, `SS:AIP194-NonRetryable-CANCELLED`, `SS:AIP194-NonRetryable-DEADLINE_EXCEEDED`, `SS:AIP194-NonRetryable-INVALID_ARGUMENT`, `SS:AIP194-NonRetryable-DATA_LOSS`).
- Generally non-retryable: RESOURCE_EXHAUSTED, INTERNAL, UNKNOWN, ABORTED, NOT_FOUND, ALREADY_EXISTS, PERMISSION_DENIED, UNAUTHORIZED, UNAUTHENTICATED, FAILED_PRECONDITION, OUT_OF_RANGE, UNIMPLEMENTED (`SS:AIP194-GenerallyNonRetryable-0`, `SS:AIP194-GenerallyNonRetryable-RESOURCE_EXHAUSTED`, `SS:AIP194-GenerallyNonRetryable-INTERNAL`, `SS:AIP194-GenerallyNonRetryable-UNKNOWN`, `SS:AIP194-GenerallyNonRetryable-ABORTED`, `SS:AIP194-GenerallyNonRetryable-NOT_FOUND`, `SS:AIP194-GenerallyNonRetryable-ALREADY_EXISTS`, `SS:AIP194-GenerallyNonRetryable-PERMISSION_DENIED`, `SS:AIP194-GenerallyNonRetryable-UNAUTHORIZED`, `SS:AIP194-GenerallyNonRetryable-UNAUTHENTICATED`, `SS:AIP194-GenerallyNonRetryable-FAILED_PRECONDITION`, `SS:AIP194-GenerallyNonRetryable-OUT_OF_RANGE`, `SS:AIP194-GenerallyNonRetryable-UNIMPLEMENTED`).

UNAUTHORIZED is kept as AIP-194 lists it, even though no google.rpc.Code carries that name, so `listedAs` never reaches it and the exhaustive check says so explicitly. The conditions inside each entry ("until it has permission", "must immediately be surfaced") stay in the quotes; the type doesn't pretend they are sections.

Every one of these sentences tells a client what to do, including the three graded MUST (CANCELLED, DEADLINE_EXCEEDED, DATA_LOSS), and none of them binds our server. So every `Recourse` and `Aip194Name` constructor has the basis P PM42: we take the side of designing for a client that follows AIP-194, and we pick each Fault's Code so that such a client does what we meant. A Recourse is never sent as a token. Theorem SF4 checks the choice for every Fault, under that assumption about the client.

### Store.Algorithm and Store.Receipt

```
data ReceiptAlgorithm = Crc64Nvme                           -- exactly the algorithm the brief allows
width    :: ReceiptAlgorithm -> {w:Nat | w == 64}
drsType  :: ReceiptAlgorithm -> DrsType                      -- Crc64Nvme |-> "crc64nvme"
newtype Checksum = Checksum {v:Integer | 0 <= v && v < 18446744073709551616}   -- 2^64; a decoded checksum value
data ReceiptReport = ReceiptReport { reportAlg :: ReceiptAlgorithm, reportChecksum :: Checksum, reportSize :: Nat }
data Receipt                                                 -- abstract; constructor not exported
  = Receipt { alg :: ReceiptAlgorithm, checksum :: Checksum, size :: Nat }
vouch :: expected:Nat -> ReceiptReport -> Either SizeDiffers {r:Receipt | size r == expected}
toHex :: Receipt -> {h:[Char] | len h == 16}
```

- `ReceiptAlgorithm` has one constructor. Its basis is C CH2 (brief) for being the only one, and R `PD:NVME-NVMCS-1.1-5.3.1.3.4-2` for what CRC-64/NVME is (width 64, the polynomial and the Rocksoft parameters), agreeing with `PD:REVENG-crc.cat.crc-64-nvme-1`. Nothing in the core names a vendor's spelling of it. That every `Receipt` has algorithm `Crc64Nvme` and a checksum below 2^64 is true as soon as these types compile, so it is a note here rather than a theorem.
- `drsType Crc64Nvme = "crc64nvme"`: P `DO:DRS-schemas.Checksum.type-1`, `DO:DRS-schemas.Checksum.type-2` (PM26). DRS says the type SHOULD be a hash name from the IANA Named Information registry and that "Other values MAY be used", and that an implementer using a provider's algorithm SHOULD use an existing standard value such as `crc32c`. The vendored Named Information registry has no CRC entry and the suggested list has no CRC-64, so we decline both SHOULDs and take the MAY, because the brief requires CRC-64/NVME (C CH2).
- In RFC 9530's vocabulary a receipt holds a "checksum", the output of an algorithm over a sequence of bytes (R `HS:RFC9530-1.4`), computed over the whole representation data of the file. `Checksum` holds the decoded value, so the core never sees the store's encoding of it.
- `vouch` is the only producer of `Receipt`. Because `ReceiptReport` already carries a `ReceiptAlgorithm` and a decoded 64-bit `Checksum`, the only thing left for the core to refuse is a size that differs from the upload length. A report reaches `vouch` only from a `Vouched` answer, and the store contract (C CH6) says what an adapter must have checked before it produces one: full object, the receipt algorithm, the whole width, and the size of what the store sealed.
- `toHex` re-encodes the checksum as 16 lowercase hex digits for DRS (R `DO:DRS-schemas.Checksum.checksum-1`). It renders a number; it computes nothing over file content.

### Store.Protocol

The core talks to "the store", which is anything that can keep durable chunks of a file and later vouch for the whole file. I wrote each command in terms of the RFC 9110 method semantics it has to honour, because those semantics are what the retry and fencing rules depend on, and I gave each command its own answer type, so a cell in the table can only receive the answers its command can actually get. The adapter decides how to realise the commands.

```
newtype StagingRef = StagingRef [Char]                       -- built only by an adapter, from whatever names the store's staging area
newtype ChunkToken = ChunkToken [Char]                       -- built only by an adapter, from whatever the store hands back per chunk
data StoreProfile = StoreProfile                             -- supplied by the adapter
  { chunkSize  :: {c:Nat | c >= 1}                           -- every chunk but the last has exactly this many bytes (CH28)
  , maxChunks  :: {k:Nat | k >= 1}                           -- the most chunks one seal can name
  , sealsEmpty :: Bool }                                     -- whether the store can seal zero chunks into an empty file
data StoreCommand
  = Open ReceiptAlgorithm                                    -- create a staging area for durable chunks; like POST creating a resource
  | Seal StagingRef c:Chunks {n:Nat | n == chunkBytes c} NoForward
                                                             -- make chunks 1..k the file, create-only, with the expected length
  | AskReceipt                                               -- does the store vouch for the file? safe, like HEAD
  | Discard StagingRef                                       -- discard the staging area; idempotent, like DELETE
  | ConfirmDiscarded StagingRef                              -- how many durable chunks remain staged? safe, like GET
  | Remove                                                   -- remove the sealed file; idempotent, like DELETE
-- a chunk write is a mover command, PersistChunk e ref k, idempotent per chunk number, like PUT;
-- its answer arrives as ChunkPersisted e k n tok or ChunkFailed e k Failure
data Failure  = Unavailable (Opt Nat)                        -- the store did not process the call; optional delay in seconds
              | Ambiguous (Opt Nat)                          -- the call may or may not have taken effect; optional delay hint
              | Refused StoreRefusal                         -- the same call in the same state would be refused the same way
data Answer a = Done a | Failed Failure
data Vouching = Vouched ReceiptReport                        -- the store vouches for the whole file with a full-object checksum
              | Unvouchable                                  -- a file exists, and the store will never vouch for it in the receipt algorithm
              | NotYetVouched                                -- a file exists, and the store's answer can still change without another call
data Presence = Exists Vouching | NothingThere               -- NothingThere: the store holds no file under this id
data StoreReport                                             -- one constructor per command
  = OpenR (Answer StagingRef) | SealR (Answer Vouching) | AskR (Answer Presence)
  | DiscardR (Answer ()) | ConfirmR (Answer Nat) | RemoveR (Answer ())
data StoreRefusal = StagingGone | LengthDiffers | NotPermitted | Inconsistent
```

`RemoveR (Done ())` means the file is gone, whether this call removed it or nothing was there, as an idempotent DELETE would. `ConfirmR (Done n)` says n chunks remain staged. A `StoreReport` whose constructor doesn't belong to the command the slot is waiting for is handled by guard G2.

`StagingRef` and `ChunkToken` export their constructors so that an adapter can build one from whatever its store hands back, and the core never uses either constructor; `check-vendor` fails a core module that does. The chunk write carries the staging reference the Open returned, because a store generally needs to know which staging area a chunk belongs to, and the core is the one that holds it. The `Seal` constructor's refinement makes clause 7's promise that the expected length equals the chunks' total a matter of construction: a `Seal` with any other number can't be built.

The store contract is the part of this module that no type can check, so every adapter has to prove or test it. Its basis is C CH6, and each clause is stated in RFC 9110 terms where one exists:

1. `Vouched` means the store vouches for a checksum of the entire representation data, in the receipt algorithm, decoded to its full width, and its size is the size of the file the store sealed. A chunk acknowledgement never implies a `Vouched` (C CH1).
2. `Seal` is create-only, with the meaning of `If-None-Match: *` (R `HS:RFC9110-13.1.2-5`): if a file already exists under the id, the store does not replace it. A repeated seal can therefore never overwrite a file the store already vouched for.
3. `Unavailable` means the store did not process the call, which is the only kind of failure gRFC A6 says should be retried (P `SS:GRFC-A6-Retryable-1`, PM3). Anything the adapter can't place with certainty is `Ambiguous`, which may carry the store's delay hint.
4. `NothingThere` is authoritative when it is given. `Refused` and `Unvouchable` are deterministic: the same call in the same state would get the same answer. `NotYetVouched` is reserved for an answer that can change without any further call from us; an adapter that can't name such a case never produces it.
5. A chunk write that is still in flight may land after `Discard`, which is why cleanup ends with `ConfirmDiscarded`.
6. The store eventually discards a staging area nobody sealed or discarded, and that expiry never touches a sealed file. This is the backstop for an `Open` whose outcome was `Ambiguous`, whose staging area the core never learns about. An `Open` that is still in flight when its file ends is not left to the backstop: the ended file waits for its answer and discards what it created (cleanup step `AwaitOpen`, row K0).
7. In return, the core promises every store the same shape of writes (C CH28): chunk k covers bytes `[(k-1)*chunkSize, k*chunkSize)` of the file, chunks are numbered 1..k with no gaps, at most one chunk write per file is in flight, every chunk write names the staging area it belongs to, k never exceeds `maxChunks`, a seal names the expected length, which equals the chunks' total by construction, and a seal over zero chunks is sent only when `sealsEmpty` is true. Fixed byte ranges are the core's own choice, not any store's requirement: they make a late duplicate write of chunk k carry exactly the bytes the first one did, whether the store keys writes by number, by offset or appends them, and they let the offset be a function of the chunk count. Whatever minimum or maximum chunk size, part cap or numbering rule a particular store has is the adapter's business: it picks `chunkSize` and `maxChunks` inside its own limits, and its own theorems show that this shape meets them.
8. A `ChunkToken` is opaque. A store may hand one back for each durable chunk and need it again at seal; the core carries it from `ChunkPersisted` into the `Seal` unchanged and never looks inside. A store that needs no token gets whatever its adapter put there.

`StagingGone` after a `Seal` is not a final answer, because a staging area disappears both when it is discarded and when it was already sealed; the core asks for the receipt. The other refusals at `Seal` are final.

### Upload

```
data Chunk  = Chunk { number :: {n:Nat | 1 <= n}, bytes :: {b:Nat | 1 <= b}, token :: ChunkToken }
data ChunkList = CNil | CSnoc { prev :: ChunkList, ch :: {c:Chunk | number c == cnt prev + 1} }
data Chunks = Chunks                                        -- csize, cmax and climit are copied from the plan at creation
  { csize  :: {c:Nat | c >= 1}
  , cmax   :: {m:Nat | m >= 1}
  , climit :: {s:Nat | s <= cmax * csize}                   -- the plan's max-size
  , cl     :: {l:ChunkList | cnt l <= cmax && total l <= climit && lastBytes l <= csize && (cnt l == 0 => total l == 0)
                          && (cnt l > 0 => total l == (cnt l - 1) * csize + lastBytes l)} }
data Len    = Unknown | Known Nat
data Upload = Upload
  { chunks    :: Chunks
  , uploadLen :: {l:Len  | isKnown l => chunkBytes chunks <= lenOr l}              -- R UP:RESUMABLE-UPLOAD-13-4.4.2-7
  , complete  :: {c:Bool | c => (isKnown uploadLen && lenOr uploadLen == chunkBytes chunks)}  -- R UP:RESUMABLE-UPLOAD-13-4.1.3-1
  }
offset :: Upload -> Nat     -- chunkBytes chunks; a measure, never a field
appendChunk :: x:{Chunks | nChunks x == 0 || lastFull x} -> n:{Nat | 1 <= n && n <= csize x && chunkBytes x + n <= climit x} -> ChunkToken
            -> {y:Chunks | chunkBytes y == chunkBytes x + n && nChunks y == nChunks x + 1
                        && csize y == csize x && cmax y == cmax x && climit y == climit x}
data Plan = Plan { profile :: StoreProfile, maxSize :: {m:Nat | m <= maxChunks profile * chunkSize profile}, maxAge :: Nat }
```

In the tables below, `len` is short for `uploadLen` and `chunkSize` for the chunks' `csize`, which equals the plan's.

- Offset, length and completion are the upload resource's state: R `UP:RESUMABLE-UPLOAD-13-4.1-1`, `UP:RESUMABLE-UPLOAD-13-4.1.1-1`, `UP:RESUMABLE-UPLOAD-13-4.1.2-1`, `UP:RESUMABLE-UPLOAD-13-4.1.3-1`. Because the offset is a measure of the chunks the store acknowledged durable, two rules hold by construction: the offset a client is told never exceeds what the store acknowledged (C CH1), and "the offset as seen by the client MUST NOT decrease" (R `UP:RESUMABLE-UPLOAD-13-4.1.1-7`) becomes a property of appending to a list.
- `Chunks` is the review spike's encoding: the chunk size, the cap and max-size live in the refined record, because a data refinement can't reach into the plan, and the empty-list conjunct is the one the spike needed (C CH27, CH28). A short chunk after a short chunk is rejected by `appendChunk`'s precondition, which the spike's negative control confirmed.
- The offset never exceeds max-size, whether or not the length is known, because `appendChunk` only accepts a chunk that keeps `chunkBytes <= climit` (P `UP:RESUMABLE-UPLOAD-13-4.1.4-3`, PM16: the draft says the server "might" deactivate an upload whose offset exceeds max-size, and we take the stricter side of never letting it get there). The earlier precondition asked for `nChunks < cmax` directly, and nothing in the table established it when the length was unknown, so a client upload with no Upload-Length or a chunked import could have reached chunk `cmax + 1`. With the max-size bound, the cap follows: when the last chunk is full, `offset == k * csize`, so `k * csize + n <= climit <= cmax * csize` with `n >= 1` gives `k < cmax` (rule 13). Every row that accepts a chunk checks `offset + n <= maxSize` first: A5 and A9 for a client upload, and I3 and I3a for an import.
- `complete` is set only by an explicit completing event, never from `offset == len`, because "the length and offset values do not determine whether an upload is complete" (R `UP:RESUMABLE-UPLOAD-13-4.1.3-8`). That is the one place tusd's `finishUploadIfComplete` is not followed (`UP:TUSD-2.10.1-finishUploadIfComplete-1`).
- `Len` replaces tusd's `Size` plus `SizeIsDeferred` (`UP:TUSD-2.10.1-FileInfo-1`), so a meaningless size can't exist.
- The plan announces `min-append-size = max-append-size = chunkSize` and `max-size` (P `UP:RESUMABLE-UPLOAD-13-4.1.4-3`, `UP:RESUMABLE-UPLOAD-13-4.1.4-5`, `UP:RESUMABLE-UPLOAD-13-4.1.4-6`, PM16; C CH28), plus `max-age`, the remaining lifetime after which the server might make the upload inaccessible, which we take up (P `UP:RESUMABLE-UPLOAD-13-4.1.4-7`, PM40). The completing request is exempt from the minimum (R `UP:RESUMABLE-UPLOAD-13-4.1.4-6`), which matches clause 7 of the store contract. Chunk k always covers bytes `[(k-1)*chunkSize, k*chunkSize)`. Announcing one exact append size is our choice for every store (CH28), and the adapter only picks the number; with the S3 adapter that number is at least S3's minimum part size, so every browser PATCH but the last has to be exactly that big, which open question 14 puts to the product owner.
- The plan is fixed at creation and has no update path, so the four monotonicity SHOULDs (P `UP:RESUMABLE-UPLOAD-13-4.1.4-8`, `UP:RESUMABLE-UPLOAD-13-4.1.4-9`, `UP:RESUMABLE-UPLOAD-13-4.1.4-10`, `UP:RESUMABLE-UPLOAD-13-4.1.4-11`, PM17) hold, and V12 proves it as a postcondition on `stepFile`.
- Imports use the same `Upload`, fed by the server rather than a client. The draft lets the server mark an upload complete (R `UP:RESUMABLE-UPLOAD-13-4.1.2-1`); sharing the record is our engineering choice (C CH39).

### File, Fault and the life of a file

```
data File = File { meta :: Meta, epoch :: Nat, life :: {l:Life | recvFits (source meta) l}, opDeleted :: Bool, doneAt :: Opt Instant }
data Meta = Meta { fileId, opName, owner, source :: Source, plan :: Plan, deadline :: Instant, createdWall :: HttpDate }
data Source = FromClient UploadId | FromUrl Url               -- only a client upload has an upload resource
data Life                                                     -- AIP-216 State values
  = CREATING Creation                                         -- R SS:AIP216-Active-3, SS:AIP216-EnumValues-3
  | ACTIVE Object                                             -- R SS:AIP216-EnumValues-1
  | FAILED Fault Cleanup                                      -- R SS:AIP216-Resting, SS:AIP216-EnumValues-2; C CH10
  | CANCELLED Cleanup                                         -- R SS:AIP216-Resting, SS:LRO-CancelOperation-3; C CH10
  | DELETING Object Retry                                     -- R SS:AIP216-Active-3
  | DELETED Tombstone                                         -- R SS:AIP216-Resting; C CH10
data Creation = Creation
  { upload :: Upload, held :: Opt ReqId, replyBy :: Opt Instant, finalizeBy :: Opt Instant
  , cancelRequested :: Bool, attempts :: Attempts, delayStep :: BackoffStep, connRetryUsed :: Bool, uploadOpen :: Bool
  , sourceTag :: Opt StrongETag, staging :: Opt StagingRef
  , phase :: {p:Phase | (finishing p => complete upload) && (not (isOpening p) => isPresent staging)} }
data Phase = Opening Call | Receiving Recv | Sealing Call | Asking After Call   -- the phase names the call: Open, Seal, AskReceipt
data Call  = Calling | Waiting Instant                        -- the phase's call is in flight, or waits out its backoff
data Recv                                                     -- the single slot while receiving
  = Idle | Appending Req ChunkNo Bool | Persisting (Opt Req) ChunkNo Nat Bool    -- client uploads
  | Fetching | Refetching Instant                                                 -- imports
data Req   = CreationReq ReqId | AppendReq ReqId              -- whether this append is the creation request's own content
data After = AfterAmbiguous | AfterStagingGone | AfterNotYetVouched
data Retry = Retry { call :: Opt Call, tries :: Attempts, retryStep :: BackoffStep }   -- Absent: DELETING after D3 gave up
data Cleanup = Cleanup { steps :: [CleanupStep], retry :: Retry, stagingRef :: Opt StagingRef }   -- empty steps means done
data CleanupStep = AwaitOpenStep | DiscardStep | ConfirmStep | RemoveStep    -- the head step names the call in flight
data Object = Object { receipt :: Receipt, etag :: EntityTag, uploadRes :: Opt UploadRes }   -- Absent exactly for FromUrl
data UploadRes = Retained Instant | Deactivated               -- P UP:RESUMABLE-UPLOAD-13-4-3, UP:RESUMABLE-UPLOAD-13-4.5.2-1 (PM14, PM15)
data Tombstone = Tombstone { lastEtag :: EntityTag, since :: Instant }
```

- Only six AIP-216 names appear, because "each state must come with a use case" (R `SS:AIP216-EnumValues-4`); there is no unspecified value and the state is output only (P `SS:AIP216-Default`, `SS:AIP216-OutputOnly-1`, `SS:AIP216-OutputOnly-2`, PM34). Phase, Call and Recv are not states anyone sees; they record which command's answer the file is waiting for.
- Each phase carries only the slot it can have, so the type can't express a state the table never reaches (C CH27). The earlier design had one `Slot` type shared by every phase, which made `Sealing Idle`, `Opening Persisting` and `Asking Fetching` typeable, and since `stepFile`'s postconditions quantify over every value of its input type, those values made DC1 and CC6 unprovable per step. Now Opening, Sealing and Asking hold a `Call`, and the call itself is implied by the phase (`Open Crc64Nvme`, `Seal ref chunks offset Absent`, `AskReceipt`), so a phase can't be waiting for another phase's command. The remaining reachability facts are data refinements, which rule 9 allows because each names only fields of its own constructor: Creation's `phase` says a Sealing or Asking file has a complete upload (and so, through `Upload`'s own refinement, a known length equal to the offset), and that every phase after Opening has its staging reference; File's `life` says, through the measure `recvFits`, that a client upload only ever uses `Idle`, `Appending` and `Persisting`, and an import only `Fetching` and `Refetching`. The review spike confirmed the shape: with the refinement `finishing p => complete upload` on Creation, the F1 and P1 branches verified without any runtime check, and without it they were UNSAFE.
- `Req` records whether an append in flight is the creation request's own content, because that request is answered with 201 and Location, and because a failure of it has to end the file: its client never learned the upload resource, so nobody could resume it (CH45).
- AIP-216 calls ACTIVE, CANCELLED, DELETED and FAILED resting states, which "the user can initiate an action to move" (`SS:AIP216-Resting`). We offer no such action, so FAILED, CANCELLED and DELETED absorb every client event in this core; only their own cleanup moves inside them. That is our policy (C CH10), and theorem DC13 says so.
- A file that has ended or is being deleted still has store work to do, so `FAILED`, `CANCELLED` and `DELETING` carry a `Retry` with its own call, attempt counter and backoff step, and a `Cleanup` carries the staging reference that `Discard` and `ConfirmDiscarded` need. The call in flight is the head cleanup step's command, or `Remove` in DELETING. `AwaitOpenStep` is the step for a file that ended while its `Open` was in flight: it waits for that Open's answer under the same epoch, and then discards what the Open created (K0). Every attempt counter in every life has the type `Attempts`, which is at most 5 (RE1).
- The file is the resource the creation request targeted, and `FromClient`'s `UploadId` names the upload resource (R `UP:RESUMABLE-UPLOAD-13-4.2.2-3`, `UP:RESUMABLE-UPLOAD-13-4-2`). The ids differ so the upload URI can be unguessable (P `UP:RESUMABLE-UPLOAD-13-13-1`, PM20). Ids arrive from the shell inside the creation event, since a pure core has no randomness. An import has no upload resource, so the World's upload map never names it and `uploadRes` is `Absent` for it.
- `uploadOpen` is true until an append tries to carry data past the length of a completed upload, or until a cancel is accepted while the file is sealing. After the first, the upload resource is invalid (R `UP:RESUMABLE-UPLOAD-13-4.4.2-7`); after the second, it is deactivated (P `UP:RESUMABLE-UPLOAD-13-4.5.2-1`, PM15, and our choice for a CancelOperation, CH9). Either way every later upload-resource request on the file gets `Gone`, and the file, if it becomes ACTIVE, gets `uploadRes = Deactivated`.
- `doneAt` is set once, by `stepFile` itself, on the step where the life first leaves CREATING, and that same step asks for the Ticks that the operation's retention and the tombstone need (C CH5). It used to be set by `World`, where no theorem could see it.
- `ACTIVE` can only hold a `Receipt`, and `size receipt` equals the upload length; the only rows that build it are F1 and P1 below.

| `Fault` | Code | Basis |
|---|---|---|
| `Expired` | DEADLINE_EXCEEDED | P `UP:RESUMABLE-UPLOAD-13-4.1.4-7` (PM40); R `SS:GRPC-STATUSCODES-DEADLINE_EXCEEDED`; C CH36 |
| `FinalizeTimedOut` | DEADLINE_EXCEEDED | R `SS:GRPC-STATUSCODES-DEADLINE_EXCEEDED`; C CH36, CH37 |
| `OutOfRange` | OUT_OF_RANGE | R `UP:RESUMABLE-UPLOAD-13-4.4.2-7`, `SS:GRPC-STATUSCODES-OUT_OF_RANGE`; C CH36 |
| `TooLarge` (an import longer than max-size) | RESOURCE_EXHAUSTED | R `SS:GRPC-STATUSCODES-RESOURCE_EXHAUSTED`; C CH36, CH39 |
| `QuotaAtFinalize` | RESOURCE_EXHAUSTED | P `UP:RESUMABLE-UPLOAD-13-13-7` (PM12); R `SS:GRPC-STATUSCODES-RESOURCE_EXHAUSTED`, `SS:GRPC-STATUSCODES-PERMISSION_DENIED-2`; C CH14, CH36 |
| `Revoked` | PERMISSION_DENIED | P `UP:RESUMABLE-UPLOAD-13-13-6` (PM12); R `SS:GRPC-STATUSCODES-PERMISSION_DENIED`; C CH36 |
| `Empty` (a zero-length import the store can't seal) | UNIMPLEMENTED | R `SS:GRPC-STATUSCODES-UNIMPLEMENTED`; C CH15, CH36 |
| `CreationRefused` (the creation request's own content was refused once the upload existed) | INVALID_ARGUMENT | R `SS:GRPC-STATUSCODES-INVALID_ARGUMENT`; P `UP:RESUMABLE-UPLOAD-13-4.2.3-2` (PM44); C CH36, CH45 |
| `CreationInterrupted` (the creation request's content broke off before its 201) | UNAVAILABLE | R `SS:GRPC-STATUSCODES-UNAVAILABLE`; C CH36, CH45 |
| `StateLost` | DATA_LOSS | R `UP:RESUMABLE-UPLOAD-13-4.1.1-9`, `SS:GRPC-STATUSCODES-DATA_LOSS`; C CH36 |
| `SizeMismatch` | DATA_LOSS | R `SS:GRPC-STATUSCODES-DATA_LOSS`; C CH1, CH7, CH36 |
| `ObjectWithoutReceipt` | INTERNAL | R `SS:GRPC-STATUSCODES-INTERNAL`; C CH1, CH8, CH36 |
| `StoreRefusedUs` | INTERNAL | R `SS:GRPC-STATUSCODES-INTERNAL`; C CH24, CH36 |
| `Contradiction` | INTERNAL | R `SS:GRPC-STATUSCODES-INTERNAL`; C CH36 |
| `Unavailable` | UNAVAILABLE | R `SS:GRPC-STATUSCODES-UNAVAILABLE`, `SS:GRFC-A6-Throttling-2`; C CH36 |
| `SourceUnreachable` | UNAVAILABLE | R `SS:GRPC-STATUSCODES-UNAVAILABLE`; P `HS:RFC9110-9.2.2-8` (PM4); C CH36 |
| `SourceAnswered Status` | UNKNOWN | R `SS:GRPC-STATUSCODES-UNKNOWN`, `HS:RFC9110-15-4`; C CH16, CH36 |
| `SourceChanged` | ABORTED | R `HS:RFC9110-13.1.5-6`, `SS:GRPC-STATUSCODES-ABORTED`; C CH17, CH36 |

Each row's R citation is the code's definition, which the Fault has to fit; that this Fault gets that code is our mapping (C CH36). The earlier draft grounded `TooLarge` and `SourceUnreachable` in gRPC's library-generated rows, which describe gRPC transport events, not an HTTP origin fetch, so they now rest on the RESOURCE_EXHAUSTED and UNAVAILABLE definitions instead.

`faultCode :: Fault -> {c:Code | c /= OK && c /= CANCELLED}`: a failure is never OK, because OK is defined as "Not an error; returned on success" (R `SS:GRPC-STATUSCODES-OK`), and a Fault never carries CANCELLED, because cancellation is its own life (C CH36).

### Refusal

A `Refusal` is a request answered with an error now. It decides the status, the extra headers and the problem type; nothing else in the core writes a 4xx or 5xx.

| `Refusal` | Status | Extra headers | Problem | Basis |
|---|---|---|---|---|
| `NoCredentials cs`, `BadCredentials cs` | 401 | WWW-Authenticate from `cs :: NonEmpty Challenge` | about:blank | R `HS:RFC9110-15.5.2-2`, `HS:RFC9110-11.6.1-1`; P `HS:RFC9110-11.4-1` (PM2) |
| `Forbidden` | 403 | | about:blank | R `HS:RFC9110-15.5.4-1`, `SS:AIP193-PermissionDenied-1`; P `HS:RFC9110-11.4-2` (PM2) |
| `NotFound` | 404 | | about:blank | R `HS:RFC9110-15.5.5-1`, `SS:AIP193-PermissionDenied-2`, `DO:DRS-responses.404NotFoundDrsObject-1` |
| `MethodNotAllowed ms` | 405 | Allow | about:blank | R `HS:RFC9110-15.5.6` |
| `OffsetMismatch e p` | 409 | Upload-Offset = e, UC ?0 | mismatching-upload-offset (gated) | R `UP:RESUMABLE-UPLOAD-13-4.4.2-3`; P `UP:RESUMABLE-UPLOAD-13-7.1-2` (PM23) |
| `AlreadyComplete` | 409 | UC ?0, no Upload-Offset | about:blank | P `UP:RESUMABLE-UPLOAD-13-4.1.2-6`, `HS:RFC5789-2.2-2` (PM21) |
| `OperationInProgress` | 409 | | about:blank | R `HS:RFC9110-15.5.10-1`; C CH11 |
| `ParentMissing` | 409 | | about:blank | R `HS:RFC9110-15.5.10-1`; C CH13 |
| `Gone` | 410 | | about:blank | R `HS:RFC9110-15.5.11-1`, `UP:RESUMABLE-UPLOAD-13-4.1.1-9`; P `HS:RFC9110-15.5.5-2` (PM41) |
| `PreconditionFailed` | 412 | | about:blank | R `HS:RFC9110-13.2.2-2`, `HS:RFC9110-13.2.2-4`, `HS:RFC9110-15.5.13` |
| `MissingOffset` | 400 | UC ?0 | about:blank | R `HS:RFC9110-15.5.1`; C CH43 |
| `InconsistentLength` | 400 | UC ?0 | inconsistent-upload-length (gated) | R `UP:RESUMABLE-UPLOAD-13-4.1.3-6`; P `UP:RESUMABLE-UPLOAD-13-7.2-1` (PM23) |
| `AppendTooSmall` | 400 | Upload-Limit, UC ?0 | about:blank | P `UP:RESUMABLE-UPLOAD-13-4.1.4-6` (PM16), `UP:RESUMABLE-UPLOAD-13-4.1.4-17` (PM18) |
| `DigestUnsupported algs` | 400 | | digest-unsupported-algorithms | P `PD:DIGEST-PROBLEMS-3.1-1`, `PD:RFC9530-2-2` (PM24) |
| `AppendTooLarge` | 413 | Upload-Limit, UC ?0 | about:blank | R `HS:RFC9110-15.5.14-1`; P `UP:RESUMABLE-UPLOAD-13-4.1.4-5` (PM16), `UP:RESUMABLE-UPLOAD-13-4.1.4-17` (PM18) |
| `ExceedsMaxSize` | 413 | Upload-Limit | about:blank | R `HS:RFC9110-15.5.14-1`; P `UP:RESUMABLE-UPLOAD-13-4.1.4-3` (PM16) |
| `OffsetPastLength` | 413 | UC ?0 | about:blank | R `UP:RESUMABLE-UPLOAD-13-4.4.2-7`, `HS:RFC9110-15.5.14-1` |
| `WrongMediaType` | 415 | Accept-Patch: application/partial-upload, UC ?0 | about:blank | R `HS:RFC9110-15.5.16`, `UP:RESUMABLE-UPLOAD-13-4.4.1-1`; P `HS:RFC5789-2.2-1` (PM22) |
| `RangeNotSatisfiable n` | 416 | Content-Range: bytes */n | about:blank | R `HS:RFC9110-15.5.17-1`; P `HS:RFC9110-14.4-6`, `HS:RFC9110-15.5.17-2` (PM31) |
| `RateLimited s` | 429 | Retry-After: s | about:blank | R `HS:RFC6585-4-1`; P `HS:RFC6585-4-2` (PM6), `UP:RESUMABLE-UPLOAD-13-13-8` (PM13) |
| `Internal` | 500 | | about:blank | R `HS:RFC9110-15.6.1` |
| `DataLoss` | 500 | | about:blank | R `HS:RFC9110-15.6.1`; C CH33 |
| `NotImplemented` | 501 | | about:blank | R `HS:RFC9110-15.6.2` |
| `StoreUnavailable (Opt s)` | 503 | Retry-After when the store gave a delay | about:blank | R `HS:RFC9110-15.6.4-1`; P `HS:RFC9110-15.6.4-2` (PM6) |
| `InsufficientStorage` | 507 | | about:blank | R `HS:RFC4918-11.5-1`; C CH14, CH20 |

- `WrongMediaType` is grounded in the draft's own media type, application/partial-upload (`UP:RESUMABLE-UPLOAD-13-4.4.1-1`), and in RFC 5789's error handling, which offers 415 for an unsupported patch document and asks for Accept-Patch with it. The earlier draft cited tus 1.0's `application/offset+octet-stream` rule here, which is a different protocol.
- `AlreadyComplete` answers an append to a completed upload that no MUST already covers: one with no content that doesn't complete (V2, F8). The appends a MUST does cover get that MUST's answer first: a missing offset, a wrong offset (409 with UC ?0 and Upload-Offset = length, R `UP:RESUMABLE-UPLOAD-13-4.4.2-3`), a wrong media type, inconsistent length indicators, and content past the length (R `UP:RESUMABLE-UPLOAD-13-4.4.2-7`, which also invalidates the upload resource). The draft notes that UC "can be false in response to an invalid operation performed on a completed upload" (`UP:RESUMABLE-UPLOAD-13-4.1.2-6`) and RFC 5789 offers 409 for a patch that conflicts with the resource's state (`HS:RFC5789-2.2-2`), so 409 with UC ?0 is the Permitted answer, and I left Upload-Offset out on purpose. The earlier draft sent Upload-Offset = length, and a client following the draft resumes straight from that (`UP:RESUMABLE-UPLOAD-13-4.7-2`), so it would keep appending. Without Upload-Offset, the same rule tells the client to retrieve the offset first; that answer carries UC ?1 (V3, F6), and a client that sees UC ?1 doesn't resume (`UP:RESUMABLE-UPLOAD-13-4.1.2-5`). The revision before this one had used UC ?1 on the 409 itself, which claimed the targeted resource's semantics for a refusal by the upload resource and so contradicted the definition of UC ?1 (`UP:RESUMABLE-UPLOAD-13-4.1.2-4`); this answer doesn't.
- `OperationInProgress` answers DELETE on a file that is still being created. It is a plain HTTP refusal on the content surface, not an AIP-151 operation, so it is grounded in the 409 definition and our choice (CH11), not in AIP-151's parallel-operations rule.
- `InsufficientStorage` never carries Retry-After. RFC 4918 doesn't forbid one; it only forbids repeating a user's request without a new user action (`HS:RFC4918-11.5-2`). Leaving the hint out is our choice (CH20).
- `MissingOffset` answers an append with no Upload-Offset. The draft's MUST to send one is addressed to the client (`UP:RESUMABLE-UPLOAD-13-4.4.1-2`), so it can't make any server answer Required; what is Required is only that 400 means a perceived client error (`HS:RFC9110-15.5.1`), and choosing it here is CH43.
- `Internal` and `DataLoss` carry an internal cause for the `Alert` command that never reaches the wire. `DataLoss` is a separate Refusal only so that the alert says which; both answer a plain 500, and neither carries a google.rpc.Code (CH33). `refuseEnded :: Life -> Refusal` answers every request on a finished upload resource, and it is always `Gone` (R `HS:RFC9110-15.5.11-1`; P PM41).

## State, events and commands

```
data World = World { files :: Map FileId File, uploads :: Map UploadId FileId, ops :: Map OpName FileId
                   , creatingByOwner :: Map Owner Nat, storeBucket :: Throttle }
type State = World
step     :: World -> WorldEvent -> (World, [Command])
stepFile :: Env -> File -> FileEvent -> Out
data Out = Out { next :: File, commands :: [FileCommand], throttle :: Delta }
data Env = Env { now :: Instant, wall :: HttpDate, access :: Access, quotaRemaining :: Nat, retryAllowed :: Bool, cfg :: Config }
data Command = ForFile FileId FileCommand | ToClient ReqId Response | Forget FileId
```

`step` checks admission, routes by id, computes `retryAllowed` from `storeBucket`, calls `stepFile`, writes the file back with one `Map.insert` at one key, applies `throttle` from the `Out` to `storeBucket`, and tags every command `stepFile` returned with the file's id. It lifts one command instead of tagging it: `Retire`, which T6 emits, becomes `Forget fid`, and `step` deletes the file and its upload and operation ids from the three maps. It also updates `creatingByOwner` by the difference of `isCreating` before and after, which is the only place that counter changes and the only decision `step` still makes on its own (RE8). Everything else a step does is in `stepFile`'s `Out`: `stepFile` sets `doneAt` on the step where the file first leaves CREATING and emits, on that same step, the `SetTimer`s for the operation's retention and the tombstone (T5, T6), so RE7's refinement on `stepFile` covers those Ticks too. The earlier design did both in `World`, which no theorem checks, and a missed Tick there would have kept the file and its operation forever. `Out` is a named record because the spike verified postconditions on named measures, not on tuple projections. `now` is a monotonic second count for deadlines and backoff; `wall` is an HTTP-date for Last-Modified and conditional requests. Basis of the whole shape: C CH5 (brief), CH27, CH29.

Every event is already-parsed protocol data, and none carries representation bytes (C CH3). An invalid header field has already become absent, because invalid values "MUST cause the entire header field to be ignored" (R `UP:RESUMABLE-UPLOAD-13-4.1.1-4`, `UP:RESUMABLE-UPLOAD-13-4.1.2-2`, `UP:RESUMABLE-UPLOAD-13-4.1.3-5`). Every report and every Tick names the file it is for, so `step` can route it like a client request.

| Event | From | Carries |
|---|---|---|
| `CreateUpload` | client POST | ids, owner, UC, `Opt UploadLength`, `Opt ContentLength`, has content, `Opt ClientDigest`, destination verdict |
| `StartImport` | client POST | ids, owner, url, destination verdict |
| `Append` | client PATCH | reqId, `Opt UploadOffset`, `Opt UC`, `Opt UploadLength`, `Opt ContentLength`, media type ok, `Opt ClientDigest` |
| `OffsetQuery`, `CancelUpload` | client HEAD, DELETE on the upload resource | reqId |
| `CancelOperation`, `GetOperation`, `DeleteOperation` | client | reqId |
| `GetObject`, `GetAccessUrl` | client, DRS paths | reqId |
| `GetContent`, `DeleteFile` | client | reqId, method, conditional header results, range |
| `Options`, `OtherMethod (Recognised)` | client | reqId |
| `StoreReplied fid e r` | shell, from the adapter | file, epoch, `StoreReport` |
| `BodyReceived fid e n`, `BodyBroken fid e why` | mover (client append) | file, epoch, bytes buffered, `ExceededLength`, `ExceededLimit` or `Interrupted` |
| `ChunkPersisted fid e k n tok`, `ChunkFailed fid e k f` | mover (append or import) | file, epoch, chunk number, size, chunk token, or the `Failure` |
| `OriginReplied fid e r` | mover (import) | file, epoch, status, strong ETag, length, Retry-After, Content-Range first-pos |
| `FetchEnded fid e how` | mover (import) | file, epoch, `Eof (LengthDelimited n \| ChunkedEnd \| CloseDelimited)` or `Interrupted` |
| `MoverDied fid e` | shell | file, epoch |
| `Tick fid` | shell timer | the file, nothing else but `Env` |

`ChunkFailed` carries a `Failure`, not a whole store answer, so a failed chunk write can only be `Unavailable`, `Ambiguous` or `Refused`; a chunk write can't be "vouched" or "nothing there". A successful write arrives only as `ChunkPersisted`, which is a mover event, so no store answer type has an acknowledgement constructor at all.

| `FileCommand` | Meaning | Basis |
|---|---|---|
| `Reply ReqId Response` | answer a waiting request | R `HS:RFC9110-15-1` |
| `Abandon ReqId` | close a request's connection without a response | P `UP:RESUMABLE-UPLOAD-13-4.6-5` (PM8) |
| `Defer ReqId` | re-deliver this request after the next report for this file | C CH30 |
| `StartAppend e ReqId ChunkNo MaxBytes` | read at most MaxBytes of the request body into a buffer for epoch e; a body longer than that is `BodyBroken ExceededLimit` (or `ExceededLength` past a known length) | C CH28 |
| `PersistChunk e StagingRef k` | make the buffer durable as chunk k of that staging area; the mover releases the buffer when it reports | C CH6, CH28 |
| `DropBuffer e` | release the buffer filled under epoch e without persisting it; a no-op if there is none | C CH28 |
| `StartFetch e Url (Opt (Offset, StrongETag))` | start an import mover, resuming with Range and If-Range when given | R `HS:RFC9110-13.1.5-3` |
| `StopMover e` | stop the mover running under that epoch; it releases no buffer, so a row that abandons a filled buffer also emits `DropBuffer` | C CH29 |
| `Store e StoreCommand` | make one store call and report its answer tagged with `e` | C CH6 |
| `SetTimer Instant` | ask for a `Tick` for this file at or after that time | C CH5 |
| `Alert Alarm` | surface something an operator has to see | C CH23, CH24 |
| `Retire` | the file's tombstone has expired; `step` lifts this to `Forget fid` | P `HS:RFC9110-15.5.11-3` (PM30); C CH5 |

The earlier draft grounded `Alert` in AIP-194's INTERNAL entry, which says such errors "should immediately be surfaced" (`SS:AIP194-GenerallyNonRetryable-INTERNAL`). That sentence is addressed to clients, so it can't make alerting Required of us; alerting is our operational choice.

A Tick carries no instruction; it only makes `stepFile` look at the clock. A file can have several timers pending, and the core doesn't record which: every Tick evaluates every timer row, and a Tick whose instants haven't arrived changes nothing. The obligation that matters is the other direction, and theorem RE7 states it: every row that sets an instant the core will act on (a creation deadline, `replyBy`, `finalizeBy`, a backoff wait, an upload retention, the operation's retention, a tombstone) emits a `SetTimer` for it. A Tick can still arrive for a file the World has already forgotten, for instance T5's retention Tick when `opRetention` is longer than `tombstoneHorizon`; G1 drops it.

## The transition table

### Guards, in order, before any cell

- **G0 access (World).** Every client request with `access` other than `Allowed` gets `NoCredentials`, `BadCredentials` or `Forbidden`, nothing changes, and nothing else is evaluated first, not even whether the id exists (R `SS:AIP193-PermissionDenied-1`; P PM1). The verifiers caught that this guard used to run after routing, which answered 404 for an unknown id and 403 for a known one and so leaked existence.
- **G1 routing (World).** `Options` answers 204 with Upload-Limit on a resource that supports creation (R `UP:RESUMABLE-UPLOAD-13-4.1.4-13`) and with Accept-Patch on an upload resource (P `HS:RFC5789-3.1-1`, PM22). `OtherMethod Unrecognised` answers `NotImplemented` (R `HS:RFC9110-15.6.2`); `OtherMethod (Known m)` for a method the resource doesn't support answers `MethodNotAllowed` (R `HS:RFC9110-15.5.6`). A request for an id the World doesn't know (never created, or forgotten after its tombstone) answers `NotFound`. An upload-resource request (`Append`, `OffsetQuery`, `CancelUpload`) is routed through `uploads`, which only ever names client uploads, so the same request for an import's file is `NotFound` in every state. A report for an unknown file emits `StopMover e` for mover reports, plus `DropBuffer e` for a `BodyReceived`, and nothing for store reports. A `Tick` for an unknown file changes nothing and emits nothing.
- **G2 stale report.** A report is current only when its epoch equals `epoch` and the file is waiting for that job: a `Calling` call for a store report (the call is the one the phase or the head cleanup step names), `Appending` or `Persisting` for an append mover's report, `Fetching` for an import mover's report. Any other report leaves the file unchanged and reports `NoCall` to the throttle; a mover report also emits `StopMover e`, and a stale `BodyReceived` also emits `DropBuffer e`, because nothing else would ever release the buffer the shell filled for it (R `UP:RESUMABLE-UPLOAD-13-4.6-3`; C CH29). A store report whose epoch is current but whose constructor belongs to a different command than the one in flight can only come from a shell that broke its delivery contract; the core emits an `Alert` and passes `Failed (Ambiguous Absent)` straight to the failure handler of the call in flight, so the file never waits for an answer that won't come (C CH42). That handler is called directly, not through `stepFile` again, so the step needs no termination measure (rule 14).
- **G3 deadline.** In phases Opening and Receiving, if `now >= deadline`, row X1 runs before anything else (P `UP:RESUMABLE-UPLOAD-13-4.1.4-7` (PM40), PM13).
- **G4 deleted operation.** `GetOperation`, `CancelOperation` and `DeleteOperation` on a file with `opDeleted` answer `NotFound`. DeleteOperation only says the client "is no longer interested in the operation result" (`SS:LRO-DeleteOperation`), so answering 404 afterwards is our choice (C CH38).

### Every State x Event cell

Columns are the reachable state classes, and since the types now admit exactly these classes, the columns are also every value of `Life`. `--` is no record; OPN is CREATING/Opening; IDL, APP and PER are CREATING/Receiving for a client upload with slot Idle, Appending and Persisting; FET and WAI are CREATING/Receiving for an import with slot Fetching and Refetching; SEA is CREATING/Sealing; ASK is CREATING/Asking; ACT is ACTIVE; END is FAILED or CANCELLED; DLG is DELETING; DEL is DELETED. A cell names a row below, or one of these codes: `S` (guard G2, nothing changes), `404`, `409` (`OperationInProgress`), `410` (`Gone`), `G1` (the request can't be routed to this file and is 404 at G1; a Tick for no record is dropped at G1), `T` (the timer rows). The three upload-resource rows apply only to client uploads; for an import's file every one of them is `G1` in every column, which is why FET and WAI show `G1` there.

| Event | -- | OPN | IDL | APP | PER | FET | WAI | SEA | ASK | ACT | END | DLG | DEL |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| CreateUpload | C1-C7 | C1 | C1 | C1 | C1 | C1 | C1 | C1 | C1 | C1 | C1 | C1 | C1 |
| StartImport | C1, C8 | C1 | C1 | C1 | C1 | C1 | C1 | C1 | C1 | C1 | C1 | C1 | C1 |
| Append | G1 | 404 | A1-A9 | B1 | B2 | G1 | G1 | F7, F8, F10 | F7, F8, F10 | V1, V2, V5 | 410 | 410 | 410 |
| OffsetQuery | G1 | 404 | A10 | B1 | B2 | G1 | G1 | F6, F10 | F6, F10 | V3, V5 | 410 | 410 | 410 |
| CancelUpload | G1 | 404 | A11 | B1 | B15 | G1 | G1 | F9, F10 | F9, F10 | V4, V5 | 410 | 410 | 410 |
| CancelOperation | 404 | O6 | A11 | B1 | B15 | I12 | I12 | F9 | F9 | Q1 | Q1 | Q1 | Q1 |
| GetOperation | 404 | Q2 | Q2 | Q2 | Q2 | Q2 | Q2 | Q2 | Q2 | Q2 | Q2 | Q2 | Q2 |
| DeleteOperation | 404 | Q3 | Q3 | Q3 | Q3 | Q3 | Q3 | Q3 | Q3 | Q3 | Q3 | Q3 | Q3 |
| GetObject | 404 | R1 | R1 | R1 | R1 | R1 | R1 | R1 | R1 | R2 | 404 | 404 | 404 |
| GetAccessUrl | 404 | R1 | R1 | R1 | R1 | R1 | R1 | R1 | R1 | R3 | 404 | 404 | 404 |
| GetContent | 404 | 404 | 404 | 404 | 404 | 404 | 404 | 404 | 404 | R4 | 410 | 404 | 410 |
| DeleteFile | 404 | 409 | 409 | 409 | 409 | 409 | 409 | 409 | 409 | R5 | 410 | R6 | R7 |
| StoreReplied | S | O1-O5 | S | S | S | S | S | F1-F5 | P1-P10 | S | K0-K6 | D1-D3 | S |
| BodyReceived | S | S | S | B3-B6, B16 | S | S | S | S | S | S | S | S | S |
| BodyBroken | S | S | S | B7-B9, B16 | S | S | S | S | S | S | S | S | S |
| ChunkPersisted | S | S | S | S | B10, B11 | I3, I3a, I4 | S | S | S | S | S | S | S |
| ChunkFailed | S | S | S | S | B12-B14, B16 | I5, I5a | S | S | S | S | S | S | S |
| OriginReplied | S | S | S | S | S | I1, I2, I6-I8 | S | S | S | S | S | S | S |
| FetchEnded | S | S | S | S | S | I9-I11, I13 | S | S | S | S | S | S | S |
| MoverDied | S | S | S | B9, B16 | B12, B16 | I11 | S | S | S | S | S | S | S |
| Tick | G1 | T | T | T | T | T | T | T | T | T | T | T | T |

The StoreReplied cells only ever see the answer type of the command in flight: OPN sees `OpenR`, SEA sees `SealR`, ASK sees `AskR`, DLG sees `RemoveR`, and END sees `OpenR`, `DiscardR`, `ConfirmR` or `RemoveR` according to its current cleanup step. Within each, the rows below partition the answer type, so GHC's exhaustiveness check covers every answer a command can get.

`stepFile` is written as one function per column plus `defaultFor :: Life -> FileEvent -> Out` for the `S`, `404`, `409` and `410` cells, so GHC's exhaustiveness checker and LiquidHaskell's totality check see every pair (C CH5).

### Creation (World)

| # | Guard | Result | Commands | Basis |
|---|---|---|---|---|
| C1 | any id already known, tombstones included | nothing created | Reply `Internal`; Alert | P `UP:RESUMABLE-UPLOAD-13-4-4` (PM20) |
| C2 | the owner already has `maxCreating` files in CREATING | nothing | Reply `RateLimited` | P `UP:RESUMABLE-UPLOAD-13-13-8` (PM13) |
| C3 | declared length > max-size, or Content-Length > max-size, or destination says `ParentMissing` | nothing | Reply `ExceedsMaxSize` or `ParentMissing` | P `UP:RESUMABLE-UPLOAD-13-4.1.4-3` (PM16); C CH13 |
| C4 | declared length > `quotaRemaining` | nothing | Reply `InsufficientStorage` | R `HS:RFC4918-11.5-1`; C CH14 |
| C5 | UC ?1 with total length 0, and the profile's `sealsEmpty` is false | nothing | Reply `NotImplemented` | R `HS:RFC9110-15.6.2`; C CH15 |
| C6 | any client digest (`forwardable` is `Absent` for every key) | nothing | Reply `DigestUnsupported` | P `PD:DIGEST-PROBLEMS-3.1-1`, `PD:RFC9530-2-2` (PM24) |
| C6a | CreateUpload with content: Upload-Length and Content-Length disagree under UC ?1, or Content-Length > chunkSize, or Content-Length < chunkSize without UC ?1 | nothing | Reply `InconsistentLength`, `AppendTooLarge` or `AppendTooSmall` | R `UP:RESUMABLE-UPLOAD-13-4.1.3-6`; P `UP:RESUMABLE-UPLOAD-13-4.1.4-5`, `UP:RESUMABLE-UPLOAD-13-4.1.4-6` (PM16); C CH28, CH45 |
| C7 | CreateUpload otherwise | CREATING FromClient, `Opening Calling`, `held = req`, deadline = now + maxAge, `uploadOpen` | `Store e+ (Open Crc64Nvme)`; `SetTimer deadline` | R `UP:RESUMABLE-UPLOAD-13-4.2.2-5`; C CH2, CH5, CH6 |
| C8 | StartImport after C1 to C3 | CREATING FromUrl, `Opening Calling`, deadline = now + importDeadline | `Store e+ (Open Crc64Nvme)`; `SetTimer deadline`; Reply 202 with the operation as its body | R `HS:RFC9110-15.3.3-1`; P `SS:AIP151-Guidance-1` (PM32), `HS:RFC9110-15.3.3-3` (PM45); C CH5 |

`e+` means bump the epoch and use the new value. "Attempts left" means `attempts < maxAttempts cfg` and `retryAllowed`; "otherwise" in a retrying row covers no attempts left, a throttled retry, and a refusal, all three (C CH31). "Backoff" in a row means `nextWait cfg h delayStep`, with h the store's or origin's delay hint when there is one, and the row stores the returned step back into `delayStep` (or `retryStep`).

C6a moves every check that A4 and A6 would make on the creation request's content up to creation, where a refusal still means nothing was created. The earlier O2 ran the creation request through A1 to A9 after the Open answered, but A1 refused it for having no Upload-Offset, A3 refused it because its Content-Type is the representation's own media type, as the draft says it should be (`UP:RESUMABLE-UPLOAD-13-4.2.1-9`), and any refusal there left a file in CREATING whose client never learned its URI. Checks that only the body can decide (a body without Content-Length that turns out too long, too short or interrupted) end the file instead, in B16.

Every row in this table and the ones below that takes a file out of CREATING also sets `doneAt := now` and emits `SetTimer (now + opRetention)` and `SetTimer (now + tombstoneHorizon)`, for T5 and T6; the rows don't repeat that (C CH5, RE7).

### Opening (OPN)

| # | Event and guard | Result | Commands | Basis |
|---|---|---|---|---|
| O1 | `OpenR (Done ref)`, client, no content | `staging := ref`; `Receiving Idle` | Reply held: 201, Location, Upload-Limit, Upload-Offset 0, UC ?0 | R `UP:RESUMABLE-UPLOAD-13-4.2.2-5`, `UP:RESUMABLE-UPLOAD-13-4.2.1-8` |
| O2 | `OpenR (Done ref)`, client, with content | `staging := ref`; `Receiving (Appending (CreationReq req) 1 uc)` under e+, `held := Absent` | `StartAppend e+ req 1 m`, with m as in A9 at offset 0 | R `UP:RESUMABLE-UPLOAD-13-4.2.2-3`; C CH28, CH45 |
| O3 | `OpenR (Done ref)`, import | `staging := ref`; `Receiving Fetching` under e+ | `StartFetch e+ url Absent` | C CH35 |
| O4 | `OpenR (Failed (Unavailable h))` or `(Failed (Ambiguous h))`, attempts left | `Opening (Waiting t)` with t = now + backoff, attempts + 1 | `SetTimer t` | R `SS:GRFC-A6-Backoff`, `SS:GRFC-A6-Pushback-3`; C CH6 (clause 6 collects a staging area an ambiguous Open created), CH31 |
| O5 | `OpenR (Failed _)` otherwise | FAILED `Unavailable`, or `StoreRefusedUs` on `Refused`, no cleanup | Reply held `StoreUnavailable` or `Internal`; Alert on `Refused` | R `SS:GRPC-STATUSCODES-UNAVAILABLE`; C CH24, CH31 |
| O6 | CancelOperation | `Opening Calling`: CANCELLED with cleanup [AwaitOpen, Discard, Confirm] and no new epoch, so the Open's answer stays current; `Opening (Waiting t)`: CANCELLED with cleanup [] | `Abandon held` if any; Reply 200 | R `SS:LRO-CancelOperation-3`; C CH6 (clause 6), CH9 |

The earlier design let a cancel in Opening only set `cancelRequested` and wait for the Open's answer, while X1's expiry in the same state bumped the epoch and so threw away the staging reference a late `OpenR (Done ref)` brought. Both now end the file at once and wait for the Open's answer inside the cleanup, under the epoch the Open was sent with (K0), so the two ways a file can end in Opening behave the same, and the O-rows need no "not cancelled" guard: a cancelled file is no longer in Opening.

The core never sends interim responses (PM10), so a client that creates with content can't resume before the final reply (`UP:RESUMABLE-UPLOAD-13-10.1-1`). Clients should create with empty content and UC ?0, which the draft offers for exactly this (`UP:RESUMABLE-UPLOAD-13-4.2.1-8`).

### Receiving, client upload (IDL, APP, PER)

| # | Slot | Event and guard | Result | Commands | Basis |
|---|---|---|---|---|---|
| A1 | Idle | Append, no Upload-Offset | unchanged | Reply `MissingOffset` | R `HS:RFC9110-15.5.1`; C CH43 |
| A2 | Idle | Append, offset differs from `offset` | unchanged | Reply `OffsetMismatch offset p` | R `UP:RESUMABLE-UPLOAD-13-4.4.2-3` |
| A3 | Idle | Append, media type is not application/partial-upload | unchanged | Reply `WrongMediaType` | R `UP:RESUMABLE-UPLOAD-13-4.4.1-1`, `HS:RFC5789-2-3`; P `HS:RFC5789-2.2-1` (PM22) |
| A4 | Idle | length indicators disagree with each other, with `len`, or with the offset | unchanged | Reply `InconsistentLength` | R `UP:RESUMABLE-UPLOAD-13-4.1.3-3`, `UP:RESUMABLE-UPLOAD-13-4.1.3-6` |
| A5 | Idle | new length > max-size, or > `quotaRemaining`; or the length stays unknown and offset + Content-Length > max-size, or offset == max-size without UC ?1 | unchanged | Reply `ExceedsMaxSize` or `InsufficientStorage` | P `UP:RESUMABLE-UPLOAD-13-4.1.4-3` (PM16); R `HS:RFC4918-11.5-1`; C CH14 |
| A6 | Idle | Content-Length > chunkSize, or < chunkSize without UC ?1 | unchanged | Reply `AppendTooLarge` or `AppendTooSmall` | P `UP:RESUMABLE-UPLOAD-13-4.1.4-5`, `UP:RESUMABLE-UPLOAD-13-4.1.4-6` (PM16); C CH28 |
| A7 | Idle | UC ?1, Content-Length 0, offset 0, and `sealsEmpty` is false | unchanged | Reply `NotImplemented` | R `HS:RFC9110-15.6.2`; C CH15 |
| A8 | Idle | any client digest (`forwardable` is `Absent` for every key) | unchanged | Reply `DigestUnsupported` | P `PD:DIGEST-PROBLEMS-3.1-1` (PM24) |
| A9 | Idle | otherwise | `len` set if newly known; `Appending (AppendReq req) (k+1) uc` under e+ | `StartAppend e+ req (k+1) m`, where m = min chunkSize (cap - offset), and cap is `len` when known and max-size otherwise | R `UP:RESUMABLE-UPLOAD-13-4.4.2-1`, `UP:RESUMABLE-UPLOAD-13-4.4.2-7`; P `UP:RESUMABLE-UPLOAD-13-4.1.4-3` (PM16) |
| A10 | Idle | OffsetQuery | unchanged | Reply 204, Upload-Offset, UC ?0, Upload-Limit, Upload-Length if known, Cache-Control: no-store | R `UP:RESUMABLE-UPLOAD-13-4.3.2-1`; P PM19 |
| A11 | Idle | CancelUpload or CancelOperation | CANCELLED, cleanup [Discard, Confirm] | `Store e+ (Discard ref)`; Reply 204 (DELETE) or 200 | P `UP:RESUMABLE-UPLOAD-13-4.5.2-1` (PM15), `HS:RFC9110-9.3.5-3` (PM29); R `SS:LRO-CancelOperation-3` |
| B1 | Appending | any upload-resource request or CancelOperation | the old append is terminated and the slot is Idle under e+; the Idle handler then answers the new request as A1 to A11 would | `StopMover e`, `DropBuffer e`, `Abandon old`, then that row's commands | P `UP:RESUMABLE-UPLOAD-13-4.6-4`, `UP:RESUMABLE-UPLOAD-13-4.6-5` (PM8) |
| B2 | Persisting | Append or OffsetQuery | the old request loses its reply (`Persisting Absent ...`); the chunk write continues | `Abandon old`, `Defer new` | P `UP:RESUMABLE-UPLOAD-13-4.6-4` (PM8); C CH30 |
| B3 | Appending | `BodyReceived n`, offset + n <= max-size, and n == chunkSize without UC ?1, or UC ?1 with 1 <= n <= chunkSize and offset + n consistent with `len` | `Persisting (Present r) (k+1) n uc` under e+, keeping the slot's request r | `PersistChunk e+ ref (k+1)` | R `UP:RESUMABLE-UPLOAD-13-4.4.1-3`; P `UP:RESUMABLE-UPLOAD-13-4.1.4-3` (PM16); C CH6 (clause 7), CH28, CH29 |
| B4 | Appending | `BodyReceived 0`, UC ?1, `len` unknown or offset == len | if offset > 0 or `sealsEmpty`: as B11 with no new chunk; else Idle | as B11, or `DropBuffer e`; Reply `NotImplemented` | R `UP:RESUMABLE-UPLOAD-13-4.4.1-3`, `HS:RFC9110-15.6.2`; C CH15 |
| B5 | Appending, an `AppendReq` | `BodyReceived n`, n < chunkSize without UC ?1 | Idle | `DropBuffer e`; Reply `AppendTooSmall` | P `UP:RESUMABLE-UPLOAD-13-4.1.4-6` (PM16) |
| B6 | Appending, an `AppendReq` | `BodyReceived n`, UC ?1, `len` known and offset + n differs from it | Idle | `DropBuffer e`; Reply `InconsistentLength` | R `UP:RESUMABLE-UPLOAD-13-4.1.3-6` |
| B7 | Appending | `BodyBroken ExceededLength` | FAILED `OutOfRange`, cleanup [Discard, Confirm] | `DropBuffer e`; Reply `OffsetPastLength` (with UC ?1 for the creation request); `Store e+ (Discard ref)` | R `UP:RESUMABLE-UPLOAD-13-4.4.2-7` |
| B8 | Appending, an `AppendReq` | `BodyBroken ExceededLimit` | Idle | `DropBuffer e`; Reply `AppendTooLarge` when the limit was chunkSize, `ExceedsMaxSize` when it was max-size - offset | P `UP:RESUMABLE-UPLOAD-13-4.1.4-5`, `UP:RESUMABLE-UPLOAD-13-4.1.4-3` (PM16) |
| B9 | Appending, an `AppendReq` | `BodyBroken Interrupted`, or `MoverDied` | Idle; nothing of the partial chunk is kept; never complete | `DropBuffer e`; `Abandon req` | R `UP:RESUMABLE-UPLOAD-13-4.4.2-2` (never complete); P PM9 (keep nothing) |
| B10 | Persisting | `ChunkPersisted`, not completing | `appendChunk`; Idle | for a held `AppendReq`: Reply 204 with UC ?0 and Upload-Offset; for a held `CreationReq`: Reply 201 with Location, Upload-Limit, Upload-Offset and UC ?0 | R `UP:RESUMABLE-UPLOAD-13-4.1.1-6`, `UP:RESUMABLE-UPLOAD-13-4.4.2-5`, `UP:RESUMABLE-UPLOAD-13-4.2.2-5`; C CH1 |
| B11 | Persisting | `ChunkPersisted`, completing | `appendChunk`; `len := offset`; complete; then: if offset > `quotaRemaining`, FAILED `QuotaAtFinalize` with cleanup [Discard, Confirm] and Reply 507 UC ?1; else `Sealing Calling`, `held` = the slot's request, `replyBy = now + replyWait`, `finalizeBy = now + finalizeBudget` | `Store e+ (Seal ref chunks offset Absent)`, `SetTimer replyBy`, `SetTimer finalizeBy`; or `Store e+ (Discard ref)` | R `UP:RESUMABLE-UPLOAD-13-4.1.2-3`; P `UP:RESUMABLE-UPLOAD-13-13-7` (PM12); C CH5, CH14, CH22 |
| B12 | Persisting, no `CreationReq` | `ChunkFailed` with `Unavailable` or `Ambiguous`, or `MoverDied` | Idle; offset unchanged | Reply (if held) `StoreUnavailable` with the store's delay if any | R `UP:RESUMABLE-UPLOAD-13-4.1.1-7`; C CH1 |
| B13 | Persisting | `ChunkFailed (Refused StagingGone)` | FAILED `StateLost`, cleanup [] | Reply (if held) `Gone`, with UC ?1 for the creation request; Alert | R `UP:RESUMABLE-UPLOAD-13-4.1.1-9` |
| B14 | Persisting, no `CreationReq` | `ChunkFailed (Refused r)`, any other r | Idle | Reply (if held) `Internal`; Alert | C CH23 |
| B15 | Persisting | CancelUpload or CancelOperation | CANCELLED, cleanup [Discard, Confirm]; the in-flight write's report becomes stale | `Abandon old` if any; `Store e+ (Discard ref)`; Reply 204 (DELETE) or 200 | P `UP:RESUMABLE-UPLOAD-13-4.5.2-1` (PM15), `HS:RFC9110-9.3.5-3` (PM29); R `SS:LRO-CancelOperation-3`; C CH6 (clause 5), CH30 |
| B16 | Appending or Persisting with a `CreationReq` | what B5, B6, B8, B9, B12 or B14 would otherwise handle | FAILED, cleanup [Discard, Confirm]: `CreationRefused` for B5, B6 and B8, `CreationInterrupted` for B9, `Unavailable` for B12, `StoreRefusedUs` for B14 | `DropBuffer e` from Appending; that row's reply with UC ?1, or `Abandon req` for B9; `Store e+ (Discard ref)`; Alert for B14 | P `UP:RESUMABLE-UPLOAD-13-4.2.3-2` (PM44); C CH24, CH45 |

The access verdict on the completing Append (guard G0) is the re-check before finalizing that `UP:RESUMABLE-UPLOAD-13-13-6` asks for, and `quotaRemaining` at B11 is the quota check of `UP:RESUMABLE-UPLOAD-13-13-7` (both PM12). B12 is where "the offset a client is told never exceeds what the store acknowledged durable" does its work: a chunk the store didn't acknowledge never moves the offset, so the client resends it at the same offset, into the same chunk number. B3 starts the chunk write under a new epoch, so a late `BodyBroken` from the append that preceded it is stale, and B15 can cancel during a chunk write without waiting for it, because store contract clause 5 and the closing `ConfirmDiscarded` cover a write that lands after the discard.

A5, A9 and B3 together keep the offset at or below max-size when the length is unknown, which is what `appendChunk`'s precondition needs (rule 13). The earlier table only checked a newly declared length against max-size, so an upload with no Upload-Length could keep sending full chunks until the chunk cap, and no row said what happened at the cap.

B16 exists because a creation request's own content is different from every later append. With no interim responses, its client learns the upload resource only from the 201, so if its content is refused, breaks off or meets a store failure before that, nobody can ever resume the upload, and leaving it Idle would only park it until X1 at max-age. The draft's own example of a refused creation answers with UC ?1, "since the server is uninterested in receiving the full representation" (`UP:RESUMABLE-UPLOAD-13-4.2.3-2`), and B16 does the same and ends the file. B7 and B13 already end the file and only add UC ?1 for the creation request. B1 and B2 don't need a creation case, because another request to the upload resource can only come from a client that already holds its URI.

### Receiving, URL import (FET, WAI)

| # | Event and guard | Result | Commands | Basis |
|---|---|---|---|---|
| I1 | `OriginReplied` 200 on a fresh fetch (offset 0) | record a strong ETag only if strong; Content-Length sets `len`; len > max-size gives FAILED `TooLarge`; len 0 without `sealsEmpty` gives FAILED `Empty` | none, or `StopMover e`, `Store e+ (Discard ref)` and cleanup [Discard, Confirm] on failure | R `HS:RFC9110-8.8.1-6`, `HS:RFC9110-15.3.1-1`; C CH15, CH39 |
| I2 | `OriginReplied` 206 on a resumed fetch, first-pos == offset, ETag strongly equal to `sourceTag` | continue | none | R `HS:RFC9110-15.3.7.3-1`, `HS:RFC9110-8.8.3.2-1` |
| I3 | `ChunkPersisted` with number k+1 and bytes chunkSize, or bytes < chunkSize as the first short chunk, within `len`, and offset + bytes <= max-size | `appendChunk`; `connRetryUsed := False` | none | C CH6 (clause 7), CH28, CH39 |
| I3a | `ChunkPersisted` with offset + bytes > max-size | FAILED `TooLarge`, cleanup [Discard, Confirm] | `StopMover e`; `Store e+ (Discard ref)` | C CH36, CH39 |
| I4 | `ChunkPersisted` outside the plan, or past `len` | FAILED `Contradiction` or `OutOfRange`, cleanup [Discard, Confirm] | `StopMover e`; `Store e+ (Discard ref)`; Alert | C CH6, CH39 |
| I5 | `ChunkFailed (Refused r)` | `StagingGone`: FAILED `StateLost`; any other r: FAILED `StoreRefusedUs`; cleanup [Discard, Confirm] | `StopMover e`; `Store e+ (Discard ref)`; Alert | C CH24, CH39 |
| I5a | `ChunkFailed (Unavailable h)` or `(Ambiguous h)` | if attempts left and (offset == 0 or a strong `sourceTag` exists): `Refetching t` with t = now + backoff, attempts + 1; else FAILED `Unavailable`, cleanup [Discard, Confirm] | `StopMover e`; `SetTimer t`, or `Store e+ (Discard ref)` | R `SS:GRFC-A6-Backoff`, `SS:GRFC-A6-Pushback-3`; C CH31, CH39 |
| I6 | `OriginReplied` 200 to a resumed fetch, or 206 with a different first-pos or validator | FAILED `SourceChanged`, cleanup [Discard, Confirm] | `StopMover e`; `Store e+ (Discard ref)` | R `HS:RFC9110-13.1.5-6`; C CH17 |
| I7 | `OriginReplied c`, `onStatus GET c ra` is `RetryIn d` or `RetryOnNewConnection`, `attempts < maxAttempts cfg` (origins have no token bucket) | `Refetching t` with t = now + backoff, using d as the hint when there is one, attempts + 1 | `StopMover e`, `SetTimer t` | R `SS:GRFC-A6-Pushback-3`; P PM5, PM6; C CH31 |
| I8 | `OriginReplied c`, `DoNotRetry`, or no attempts left | FAILED `SourceAnswered (fromWire c)`, cleanup [Discard, Confirm] | `StopMover e`; `Store e+ (Discard ref)` | R `HS:RFC9110-15-4`; C CH16 |
| I9 | `FetchEnded (Eof (LengthDelimited n))` with offset == n, or `Eof ChunkedEnd`; offset >= 1 or `sealsEmpty`; `access` Allowed; offset <= `quotaRemaining` | `len := offset`; complete; `Sealing Calling`; `finalizeBy = now + finalizeBudget` | `Store e+ (Seal ref chunks offset Absent)`; `SetTimer finalizeBy` | R `HS:RFC9110-6.1-2`; C CH5, CH15, CH39 |
| I10 | the same Eof with offset >= 1 or `sealsEmpty`, but `access` not Allowed, or quota exceeded | FAILED `Revoked` or `QuotaAtFinalize`, cleanup [Discard, Confirm] | `Store e+ (Discard ref)` | C CH14, CH39 |
| I11 | `FetchEnded` CloseDelimited, a length mismatch or Interrupted; `MoverDied` | if not `connRetryUsed` and (offset == 0 or a strong `sourceTag` exists): `connRetryUsed := True`, `Fetching` under e+; else FAILED `SourceUnreachable`, cleanup [Discard, Confirm] | `StartFetch e+ url (offset, tag)`, or `Store e+ (Discard ref)` | R `HS:RFC9110-13.1.5-3`; P `HS:RFC9110-9.2.2-8` (PM4); C CH18 |
| I12 | CancelOperation | CANCELLED, cleanup [Discard, Confirm] | `StopMover e` if fetching; `Store e+ (Discard ref)`; Reply 200 | R `SS:LRO-CancelOperation-3` |
| I13 | the Eof of I9 at offset 0 when `sealsEmpty` is false | FAILED `Empty`, cleanup [Discard, Confirm] | `Store e+ (Discard ref)` | C CH15 |

The mover follows redirects within its own bound; a 3xx that reaches the core is `DoNotRetry` and lands in I8. I6 is where the draft's monotonic offset meets a changed source: starting over would decrease the offset, so the outcome we chose is ABORTED, which AIP-194 says clients retry "at a level higher" (`SS:AIP194-GenerallyNonRetryable-ABORTED`), here a new import. I13 exists because a chunked or Content-Length-less empty body reaches the end of the fetch without I1 ever seeing a length of 0, and I3a exists for the same reason at the other end: a chunked or close-delimited body larger than max-size never shows I1 a length either, so the first chunk that would cross max-size fails the file as `TooLarge` instead of reaching `appendChunk`.

None of these rows cites the upload draft as Required. An import has no upload resource, so the draft's MUSTs about upload resources don't bind it; the offset that never decreases, the state that can't be lost and the completion rule are ours for imports, carried over through the shared `Upload` record (C CH39) and CH17. I5a is a store failure, so it is held to the store's retry budget, including `retryAllowed`, and ends as the store Fault `Unavailable`; the earlier I5 had sent it down the origin's connection-retry path, which spent `connRetryUsed`, ignored the store's delay and blamed the origin as `SourceUnreachable`.

### Sealing and asking (SEA, ASK)

These rows carry the brief's rule and the hard-won ones. A seal's answer is a receipt or it isn't; a write acknowledgement never counts. A deterministic answer ends the file at once, in the Fault that names it. Anything that leaves the outcome unknown leads to asking for the receipt, and the seal is re-sent only after the store has said there is nothing there. Every wait in these two phases is clamped to `finalizeBy`, so a Tick always arrives by then, and T3 ends the file if no call is outstanding.

| # | Event and guard | Result | Commands | Basis |
|---|---|---|---|---|
| F1 | `SealR (Done (Vouched rep))` and `vouch offset rep` gives a receipt | ACTIVE, even if `cancelRequested`; for a client upload, `uploadRes = Retained (now + uploadRetention)` if `uploadOpen`, else `Deactivated`; for an import, `uploadRes = Absent` | Reply held: 201, Location = the file, ETag, UC ?1; `SetTimer` for the retention instant | C CH1, CH5, CH9; R `HS:RFC9110-15.3.2-1`, `SS:LRO-CancelOperation-2`; P `UP:RESUMABLE-UPLOAD-13-4.4.2-4` (PM11) |
| F2 | `SealR (Done (Vouched rep))` whose size differs from the offset | FAILED `SizeMismatch`, cleanup [Remove] | `Store e+ Remove`; Reply held `DataLoss` UC ?1; Alert | C CH1, CH7 |
| F3 | `SealR (Failed (Refused LengthDiffers))` | FAILED `SizeMismatch`, cleanup [Discard, Confirm] | `Store e+ (Discard ref)`; Reply held `DataLoss` UC ?1; Alert | C CH7 |
| F4 | `SealR (Done Unvouchable)` | FAILED `ObjectWithoutReceipt`, cleanup [Remove] | `Store e+ Remove`; Reply held `Internal` UC ?1; Alert | C CH1, CH8 |
| F5 | `SealR (Failed (Refused NotPermitted))` or `(Refused Inconsistent)`; or `SealR (Done NotYetVouched)`, `(Failed (Ambiguous h))`, `(Failed (Unavailable h))` or `(Failed (Refused StagingGone))` | the first two: FAILED `StoreRefusedUs` or `Contradiction`, cleanup [Discard, Confirm], Reply held `Internal` UC ?1, Alert; the rest: `Asking after Calling`, or `Asking after (Waiting t)` with t = min (now + h) `finalizeBy` when the store gave a delay h, and the backoff step reset to 1 | `Store e+ (Discard ref)`, or `Store e+ AskReceipt`, or `SetTimer t` | C CH7; P `HS:RFC9110-9.2.2-4`, `SS:GRFC-A6-Retryable-1` (PM3) |
| F6 | OffsetQuery, `uploadOpen` | `held` abandoned | `Abandon held` if any; Reply 204, UC ?1, Upload-Offset = len, Upload-Limit, Cache-Control: no-store | P `UP:RESUMABLE-UPLOAD-13-4.6-4` (PM8), PM19; R `UP:RESUMABLE-UPLOAD-13-4.3.2-1` |
| F7 | Append, `uploadOpen`, Upload-Offset == len, no content, UC ?1 | `held := req`, `replyBy := now + replyWait` | `Abandon old held` if any; `SetTimer replyBy` | P `UP:RESUMABLE-UPLOAD-13-4.4.2-6` (PM14); C CH22 |
| F8 | any other Append, `uploadOpen` | the checks of A1 to A4, in their order; then content at offset len: `uploadOpen := False`; otherwise unchanged | that row's reply; or Reply `OffsetPastLength`; or Reply `AlreadyComplete` | R `UP:RESUMABLE-UPLOAD-13-4.4.2-3`, `UP:RESUMABLE-UPLOAD-13-4.1.3-6`, `UP:RESUMABLE-UPLOAD-13-4.4.2-7`; P `UP:RESUMABLE-UPLOAD-13-4.1.2-6` (PM21) |
| F9 | CancelUpload with `uploadOpen`, or CancelOperation | `cancelRequested := True`, `uploadOpen := False` | `Abandon held` if any; Reply 202 (DELETE) or 200 | P `HS:RFC9110-9.3.5-3` (PM29), `UP:RESUMABLE-UPLOAD-13-4.5.2-1` (PM15); R `SS:LRO-CancelOperation-1`, `SS:LRO-CancelOperation-2`; C CH9 |
| F10 | Append, OffsetQuery or CancelUpload, `uploadOpen` false | unchanged | Reply `Gone` | R `UP:RESUMABLE-UPLOAD-13-4.4.2-7`, `HS:RFC9110-15.5.11-1`; P PM15 |
| P1 | `AskR (Done (Exists (Vouched rep)))` and `vouch offset rep` gives a receipt | as F1 | as F1 | C CH1, CH9 |
| P2 | `AskR (Done (Exists (Vouched rep)))` whose size differs from the offset | as F2 | as F2 | C CH1, CH7 |
| P3 | `AskR (Done (Exists NotYetVouched))`, now < `finalizeBy`, attempts left | `Asking AfterNotYetVouched (Waiting t)` with t = min (now + backoff) `finalizeBy`, attempts + 1 | `SetTimer t` | R `SS:GRFC-A6-Backoff`; C CH8, CH31 |
| P4 | `AskR (Done (Exists NotYetVouched))` otherwise | FAILED `FinalizeTimedOut` if now >= `finalizeBy`, else `ObjectWithoutReceipt`; cleanup [Remove] | `Store e+ Remove`; Reply held `Internal` UC ?1; Alert | C CH1, CH8, CH37 |
| P5 | `AskR (Done NothingThere)` after `AfterStagingGone` | CANCELLED with cleanup [] if `cancelRequested`, else FAILED `StateLost` | Reply held `DataLoss` UC ?1; Alert | R `UP:RESUMABLE-UPLOAD-13-4.1.1-9`; C CH6 (clause 4) |
| P6 | `AskR (Done NothingThere)` after `AfterNotYetVouched` | FAILED `Contradiction`, cleanup [Discard, Confirm] | `Store e+ (Discard ref)`; Reply held `Internal` UC ?1; Alert | C CH6 (clause 4) |
| P7 | `AskR (Done NothingThere)` after `AfterAmbiguous`: if `cancelRequested`, CANCELLED with cleanup [Discard, Remove, Confirm]; else if now < `finalizeBy` and attempts left, `Sealing (Waiting t)` with t = min (now + backoff) `finalizeBy`, attempts + 1; else FAILED `FinalizeTimedOut` if now >= `finalizeBy`, else `Unavailable`, cleanup [Discard, Remove, Confirm] | as stated | `Store e+ (Discard ref)` and `Abandon held` if any; or `SetTimer t`; or `Store e+ (Discard ref)`, Reply held `StoreUnavailable` UC ?1, Alert | P `HS:RFC9110-9.2.2-4` (PM3); R `SS:LRO-CancelOperation-3`, `SS:GRFC-A6-MaxAttempts-2`; C CH6 (clause 2), CH7, CH31, CH37 |
| P8 | `AskR (Failed (Unavailable h))` or `(Failed (Ambiguous h))` | if now < `finalizeBy` and attempts left: `Asking a (Waiting t)` with t = min (now + backoff, using h as the hint) `finalizeBy`, attempts + 1; else FAILED `FinalizeTimedOut` if now >= `finalizeBy`, else `Unavailable`, cleanup [Discard, Remove, Confirm], because the outcome is unknown | `SetTimer t`; or `Store e+ (Discard ref)`, Reply held `StoreUnavailable` UC ?1, Alert | R `SS:GRFC-A6-MaxAttempts-2`, `SS:GRFC-A6-Pushback-3`; C CH7, CH31, CH37 |
| P9 | `AskR (Failed (Refused r))` | FAILED `StoreRefusedUs`, cleanup [Discard, Remove, Confirm] | `Store e+ (Discard ref)`; Reply held `Internal` UC ?1; Alert | C CH24 |
| P10 | `AskR (Done (Exists Unvouchable))` | FAILED `ObjectWithoutReceipt`, cleanup [Remove] | `Store e+ Remove`; Reply held `Internal` UC ?1; Alert | C CH1, CH8 |

P7 is the only row that re-sends a seal, and it can only follow a `NothingThere` given to an ask that itself followed an `Ambiguous` or `Unavailable` seal. Because the seal is create-only (store contract clause 2), a seal that did land in the meantime can't be overwritten by the re-sent one, and the re-sent one comes back as something other than a receipt, which leads to another ask. The attempt counter and `finalizeBy` bound that loop.

The rows that the earlier drafts got wrong were the deterministic ones. A size mismatch used to go to the probe and then back to Complete until attempts ran out, and after the first fix an answer that showed a file the store would never vouch for in the receipt algorithm still went round `NotYetVouched` until attempts ran out, because the answer types had no word for it. I added `Unvouchable` to the store's vocabulary and made F2, F3, F4, P10 and the first half of F5 end the file in one step, in `SizeMismatch`, `ObjectWithoutReceipt`, `StoreRefusedUs` or `Contradiction`. `NotYetVouched` is left for an answer that can actually change.

Every row that leaves CREATING in these two phases answers or abandons `held` (SF10). The verifiers caught that P8's failure branch had left a held completing request with nobody to answer it, and in the second pass that F7 could take a new held request after F9 had accepted a cancel, which P7's cancel branch then dropped. F9 now closes the upload resource as well, so F7 and F8 can't run after a cancel and F10 answers `Gone` instead, which is also what the draft recommends after a DELETE on the upload resource (PM15); a CancelUpload on a closed upload resource gets `Gone` too, so that cell has one answer.

In F1 and P1 the Creation refinement says the upload is complete, so `offset` is the length, and `vouch` gets a `Nat` without a runtime check. On F1 the comparison is weaker than it looks: the seal's expected length is the offset by construction, and an adapter may well report back the size it sent, so F2 is mostly reachable through an ask (P2). DC1 says so.

### ACTIVE, DELETING, DELETED and ended files

| # | State | Event and guard | Result | Commands | Basis |
|---|---|---|---|---|---|
| V1 | ACT, upload retained | Append with offset == len, no content, UC ?1 | unchanged | Reply the F1 201 again | P `UP:RESUMABLE-UPLOAD-13-4.4.2-6` (PM14) |
| V2 | ACT, upload retained | any other Append | the checks of A1 to A4, in their order; then content at offset len: `uploadRes := Deactivated`; otherwise unchanged | that row's reply; or Reply `OffsetPastLength`; or Reply `AlreadyComplete` | R `UP:RESUMABLE-UPLOAD-13-4.4.2-3`, `UP:RESUMABLE-UPLOAD-13-4.1.3-6`, `UP:RESUMABLE-UPLOAD-13-4.4.2-7`; P `UP:RESUMABLE-UPLOAD-13-4.1.2-6` (PM21) |
| V3 | ACT, upload retained | OffsetQuery | unchanged | Reply 204, UC ?1, Upload-Offset = len, Upload-Limit, Cache-Control: no-store | R `UP:RESUMABLE-UPLOAD-13-4.3.2-1`; P `UP:RESUMABLE-UPLOAD-13-4-3` (PM14), PM19 |
| V4 | ACT, upload retained | CancelUpload | `uploadRes := Deactivated`; the file stays ACTIVE | Reply 204 | P `UP:RESUMABLE-UPLOAD-13-4.5.2-1` (PM15) |
| V5 | ACT, upload deactivated | any upload-resource request | unchanged | Reply `Gone` | R `UP:RESUMABLE-UPLOAD-13-4.1.1-9`, `HS:RFC9110-15.5.11-1`; P PM41 |
| R1 | CREATING | GetObject or GetAccessUrl | unchanged | Reply 202, Retry-After: pendingDelay | P `DO:DRS-responses.202Accepted-1` (PM36); R `DO:DRS-responses.202Accepted.Retry-After-1` |
| R2 | ACT | GetObject | unchanged | Reply 200 with `drsObject` | R `DO:DRS-schemas.DrsObject-1`, `DO:DRS-paths.objects.{object_id}.get-1` |
| R3 | ACT | GetAccessUrl | unchanged | Reply 200 with the access URL fact | R `DO:DRS-paths.objects.{object_id}.access.{access_id}.get-2` |
| R4 | ACT | GetContent | unchanged | `ladder`, then `resolve`: 200, 206, 304, 412 or 416, with ETag, Last-Modified, Content-Length, Accept-Ranges | R `HS:RFC9110-13.2.2-1`, `HS:RFC9110-15.3.7.1`, `HS:RFC9110-15.4.5-2` |
| R5 | ACT | DeleteFile; `ladder` gives Proceed, or V412 | DELETING with `Retry (Present Calling) 0 1` under e+, or unchanged | `Store e+ Remove`, Reply 202; or Reply `PreconditionFailed` | P `HS:RFC9110-9.3.5-3` (PM29); R `HS:RFC9110-13.1.1-5` |
| R6 | DLG | DeleteFile | if the retry's call is `Absent` (D3 gave up): `Retry (Present Calling) 0 1` under e+; otherwise unchanged | `Store e+ Remove` if it was `Absent`; Reply 202 | P `HS:RFC9110-9.3.5-3` (PM29); C CH41 |
| R7 | DEL | DeleteFile, whatever its preconditions | unchanged | Reply `Gone` | R `HS:RFC9110-15.5.11-1`, `HS:RFC9110-13.2.1-2`; P PM41 |
| D1 | DLG | `RemoveR (Done ())` | DELETED with tombstone (`lastEtag`, now) | `SetTimer (now + tombstoneHorizon)` | R `SS:AIP216-Active-3`, `HS:RFC9110-9.2.2-1`; C CH5 |
| D2 | DLG | `RemoveR (Failed (Unavailable h))` or `(Failed (Ambiguous h))`, tries left | `Retry (Present (Waiting t)) (tries + 1) s'` with t = now + backoff | `SetTimer t` | R `SS:GRFC-A6-Backoff`, `SS:GRFC-A6-Pushback-3`, `HS:RFC9110-9.2.2-1`; C CH31 |
| D3 | DLG | `RemoveR (Failed _)` otherwise | DELETING, the retry's call `Absent` | Alert | C CH24, CH41 |
| K0 | END, head step `AwaitOpen` | `OpenR (Done ref)`; or `OpenR (Failed _)` | `stagingRef := ref` and the next step, Discard, under e+; or the cleanup is done, since an `Ambiguous` Open is clause 6's and any other failure created nothing | `Store e+ (Discard ref)`; or as K2 when done | C CH6 (clause 6) |
| K1 | END | `DiscardR (Done ())`, or `DiscardR (Failed (Refused StagingGone))` | next cleanup step | `Store e+ next` | C CH6 (clause 5) |
| K2 | END | `ConfirmR (Done 0)`, or `ConfirmR (Failed (Refused StagingGone))` | next step, or done | `Store e+ next`, or `SetTimer (doneAt + tombstoneHorizon)` when done | C CH5, CH6 (clause 5) |
| K3 | END | `ConfirmR (Done n)`, n > 0, tries left | steps := Discard : Confirm : rest; tries + 1 | `Store e+ (Discard ref)` | C CH6 (clause 5) |
| K4 | END | `RemoveR (Done ())` | next step, or done | as K2 | R `HS:RFC9110-9.2.2-1` |
| K5 | END, head step other than `AwaitOpen` | any `Failed (Unavailable h)` or `Failed (Ambiguous h)`, tries left | the retry's call `Waiting t` with t = now + backoff, tries + 1 | `SetTimer t` | R `SS:GRFC-A6-Backoff`, `SS:GRFC-A6-Pushback-3`; C CH31 |
| K6 | END | otherwise, including K3's answer with no tries left | drop the step; store contract clause 6 is the backstop | `Alert Leak`; then as K2 | C CH6 (clause 6) |
| Q1 | ACT, END, DLG, DEL | CancelOperation on a done operation | unchanged | Reply 200 | R `SS:LRO-CancelOperation-1` |
| Q2 | any record | GetOperation | unchanged | Reply 200 with `operationOf` | R `SS:LRO-GetOperation`, `SS:LRO-Operation-done` |
| Q3 | any record | DeleteOperation | `opDeleted := True`; life unchanged | Reply 204 | R `SS:LRO-DeleteOperation`; P `HS:RFC9110-9.3.5-3` (PM29) |

In DELETING and the ended states, "tries left" means `tries < maxAttempts cfg` and `retryAllowed`, and `tries` counts every retry and every K3 loop over the whole cleanup or delete. It never resets inside one cleanup, so the K3 loop is bounded by the same counter. R6 starts a fresh counter, because a repeated DELETE is a new user action; that is also the exit from the state D3 leaves behind, where a refused Remove used to sit in DELETING forever while every DELETE was told the delete was pending. The file still only reaches DELETED through D1, after the store has answered.

Q3's 204 isn't in the DeleteOperation definition, which names no status at all. The vendored google.longrunning service maps DeleteOperation to an HTTP DELETE (`references/status-and-supervision/googleapis/operations.proto:82-83`), and for a DELETE that has been enacted RFC 9110 recommends 204 (PM29), so that is the side we took.

DELETED and the terminal states answer 410, not 404. RFC 4918 requires 404 after a successful DELETE (`DO:RFC4918-9.6-3`), but that MUST binds WebDAV resources, and ours aren't WebDAV resources (C CH12): we serve no collections, properties or locks, so I didn't want to take one WebDAV rule and leave the rest. RFC 9110 prefers 410 when the server knows the condition is permanent (P `HS:RFC9110-15.5.5-2`, PM41), and once the World drops a tombstone, routing answers 404 (P `HS:RFC9110-15.5.11-3`, PM30). The same scoping decision means a missing parent folder is our own rule (C CH13), answered with the 409 RFC 9110 defines, rather than RFC 4918's PUT rule. A DELETE on a DELETED file is 410 whatever its If-Match says, because 410 is its unconditional answer and RFC 9110 requires preconditions to be ignored then (R `HS:RFC9110-13.2.1-2`).

### Timers (T)

A Tick evaluates these rows in the order listed, each against the state the previous one left. X1 and T3 end the file, and once a file has ended only T5 and T6 can still apply.

| # | Guard | Result | Commands | Basis |
|---|---|---|---|---|
| X1 | OPN, IDL, APP, PER, FET or WAI with now >= deadline | FAILED `Expired`. In OPN with `Calling`: cleanup [AwaitOpen, Discard, Confirm] and no new epoch, as in O6; in OPN with `Waiting`: cleanup []; otherwise cleanup [Discard, Confirm] | `Abandon` the held request or the slot's request, if any; `StopMover e` in APP, PER and FET; `DropBuffer e` in APP; `Store e+ (Discard ref)` outside OPN | P `UP:RESUMABLE-UPLOAD-13-4.1.4-7` (PM40), PM13; C CH6 (clause 6) |
| T3 | SEA or ASK, call `Waiting _`, now >= `finalizeBy` | FAILED `FinalizeTimedOut`, cleanup [Discard, Remove, Confirm] | `Store e+ (Discard ref)`; Reply held `StoreUnavailable` UC ?1 if any; Alert | C CH7, CH37 |
| T2 | SEA or ASK with a held request and now >= replyBy | `held := Absent` | Reply 202, UC ?1, with the operation as its body | R `HS:RFC9110-15.3.3-1`; P `HS:RFC9110-15.3.3-3` (PM45); C CH22 |
| T1 | a call `Waiting t` (in Opening, Sealing, Asking or a `Retry`) or `Refetching t`, with now >= t | `Calling`, or `Fetching`, under e+ | `Store e+ c`, where c is the command the phase or the head cleanup step names (`Remove` in DELETING); or `StartFetch e+ url resume` | R `SS:GRFC-A6-Backoff`; C CH31 |
| T4 | ACT with `Retained t`, now >= t | `uploadRes := Deactivated` | none | P `UP:RESUMABLE-UPLOAD-13-4-3` (PM14) |
| T5 | `doneAt` is `Present d`, now >= d + opRetention, not `opDeleted` | `opDeleted := True` | none | P `SS:AIP151-Expiration-1` (PM33) |
| T6 | END with empty cleanup and now >= `doneAt` + tombstoneHorizon, or DEL with now >= since + tombstoneHorizon | unchanged; `step` then forgets the file and its upload and operation ids | `Retire` | P `HS:RFC9110-15.5.11-3` (PM30) |

T3 runs before T1, so a seal or ask whose wait ends at or after `finalizeBy` is never issued; the file fails instead. Since every wait in SEA and ASK is clamped to `finalizeBy`, the Tick that T3 needs is always requested. A call that is outstanding at `finalizeBy` is left to answer, and P4, P7 and P8 then end the file in `FinalizeTimedOut`. Expiry by max-age only ends transfers that are still receiving.

T6 used to emit the World-level `Forget` from inside `stepFile`, which can only return `FileCommand`s, so the row couldn't produce what it said. It emits the `FileCommand` `Retire` now, and `step` lifts it. X1 used to bump the epoch in Opening even while the Open was in flight, so a late `OpenR (Done ref)` arrived stale and the staging area it named was left to the store's expiry; it now leaves the epoch alone and waits for that answer in K0, exactly as a cancel does in O6. X1 also drops the buffer of an append it interrupts, since every other exit from Appending does.

## What a client is told

### The response type

```
data Response
  = Created201 { createdAt :: Uri, created :: Created }
  | Ok200 { okBody :: Body }
  | Accepted202 { monitor :: Opt Op, acceptedRetryAfter :: Opt Nat, acceptedUc :: Opt UC }   -- monitor: the operation, in the body
  | NoContent204 { uploadFields :: Opt UploadFields, acceptPatch :: Bool }
  | PartialContent206 { range :: {r:Resolved | isSatisfied r}, repSize :: Nat, partialEtag :: EntityTag, partialLastModified :: HttpDate }
  | NotModified304 { notModifiedEtag :: EntityTag }
  | Rejected { refusal :: Refusal, rejectedUc :: Opt UC }
data Created = UploadResourceCreated UploadLimit Nat     -- UC ?0; R UP:RESUMABLE-UPLOAD-13-4.2.2-5
             | FileCreated EntityTag                     -- UC ?1; R UP:RESUMABLE-UPLOAD-13-4.4.2-4, HS:RFC9110-15.3.2-1
data Body = Content EntityTag HttpDate Nat | DrsBody DrsObject | AccessBody AccessUrl | OperationBody Op | EmptyBody
status :: Response -> Status                               -- reflected, one equation per constructor
fields :: Response -> [Field]
```

Every field name belongs to one constructor. GHC would allow `etag` and `uc` to be shared between constructors whose types agree, and the earlier draft shared them, but `status` is reflected, so this module runs under `--reflection`, where z3 refuses a datatype with a repeated accessor, and the whole module crashed in the review spike instead of checking (rule 10). With unique names, the same spike checked and only its negative control failed.

A 202 never carries Location, because RFC 9110 defines Location only for 201 and 3xx responses (R `HS:RFC9110-10.2.2-1`). When a 202 has a status monitor, which is the operation for StartImport (C8) and for a completing request that waited past `replyWait` (T2), the operation is the 202's body, as RFC 9110 suggests a 202's representation should "point to (or embed) a status monitor" (P `HS:RFC9110-15.3.3-3`, PM45). The 202s for a pending DELETE and for DRS's delayed GetObject have no monitor.

These obligations hold by construction, each Required unless marked: 401 carries a challenge (`HS:RFC9110-15.5.2-2`); 405 carries Allow (`HS:RFC9110-15.5.6`); a 201 for an upload resource carries Location and Upload-Limit (`UP:RESUMABLE-UPLOAD-13-4.2.2-5`); a 201 for a file carries an ETag (C CH32, our choice: no vendored MUST puts one there); a 206 carries a Content-Range for a satisfied range (`HS:RFC9110-15.3.7.1`); the offset 409 carries the current offset with UC ?0 (`UP:RESUMABLE-UPLOAD-13-4.4.2-3`); 304 carries ETag (`HS:RFC9110-15.4.5-2`); a 204 can't carry Content-Length (`HS:RFC9110-8.6-4`); a problem's status agrees with the response (`PD:RFC9457-3.1.2-2`); a successful answer to an offset retrieval carries Upload-Offset and Upload-Limit (`UP:RESUMABLE-UPLOAD-13-4.3.2-1`), because the 204 that answers one is built from a constructor of `UploadFields` that requires both; a 415 carries Accept-Patch (P PM22). Retry-After exists only on 202, 429 and 503 (P PM6, PM36; C CH20) and only as delay-seconds (R `HS:RFC9110-10.2.3-6`; P PM7). Every 4xx and 5xx except on HEAD carries `application/problem+json` (R `PD:RFC9457-3-1`, `HS:RFC9110-9.3.2-1`; C CH40). Upload-Offset, Upload-Length and Upload-Complete render as Structured Field Integers and Booleans, Upload-Limit as a Dictionary with only the draft's keys, and `min-size=0` when nothing is limited (R `UP:RESUMABLE-UPLOAD-13-4.1.4-15`). No 301, 302 or 303 is ever produced on the upload surface (P `UP:RESUMABLE-UPLOAD-13-4.2.2-10`, PM39).

The reply to a completing request goes through one function, `replyToCompleting`, whose refinement says a 2xx carries UC ?1, which is the draft's "MUST NOT emit a 2xx ... with the Upload-Complete header field set to false or missing" (R `UP:RESUMABLE-UPLOAD-13-4.2.2-4`, `UP:RESUMABLE-UPLOAD-13-4.4.2-4`). The proof spike verified this shape.

### The DRS object and the operation

`drsObject :: FileId -> Object -> DrsObject` is total on ACTIVE files and fills the five required fields (R `DO:DRS-schemas.DrsObject-1`): `id` (`DO:DRS-schemas.DrsObject.id-1`), `self_uri` rendered by the shell from the id (`DO:DRS-schemas.DrsObject.self_uri-1`), `size` from the receipt (`DO:DRS-schemas.DrsObject.size-1`), `created_time` (`DO:DRS-schemas.DrsObject.created_time-1`), and `checksums` as exactly one entry, `{type: "crc64nvme", checksum: toHex receipt}` (R `DO:DRS-schemas.DrsObject.checksums-1`, `DO:DRS-schemas.Checksum-1`; P PM26). It has one `https` access method with an `access_id` (R `DO:DRS-schemas.AccessMethod-1`, `DO:DRS-schemas.AccessMethod.access_id-1`), and `available` is always true, because this core never moves an object to archival storage (R `DO:DRS-schemas.AccessMethod.available-1`).

```
data Op     = InProgress | Done Result                      -- R SS:LRO-Operation-done, SS:LRO-Operation-result
data Result = Failed {c:Code | c /= OK} Reason | Succeeded DrsObject
operationOf :: File -> Op
```

- CREATING maps to `InProgress`; ACTIVE, DELETING and DELETED to `Done (Succeeded (drsObject ...))`; FAILED f to `Done (Failed (faultCode f) (reasonOf f))`; CANCELLED to `Done (Failed CANCELLED Cancelled)` (R `SS:LRO-CancelOperation-3`). An operation with done and no result, or with both, can't be built.
- `response` is the DRS object. The google.longrunning comment says the response "should be the resource" for a standard Create (P `SS:LRO-Operation-response`, PM32), and the DRS object is the only vendored representation of our resource, so every field name inside it comes from DRS. The field itself is a `google.protobuf.Any` (`references/status-and-supervision/googleapis/operations.proto:154`), and in JSON an `Any` needs an `@type` URL naming a message type. DRS 1.5 is vendored only as OpenAPI and has no message type, and no vendored statement names a type URL for a DRS object, so the shell writes `"@type": "type.googleapis.com/ga4gh.drs.v1.DrsObject"`, in the `type.googleapis.com/packagename.messagename` form that abseil documents (`references/status-and-supervision/abseil/status.h:624`). That URL is coined vocabulary on the wire, which is a second explicit exception to the brief's rule (CH4), recorded as CH44 and put to the product owner as open question 13. The alternative is to leave `response` unset, which the definition allows ("Some services might not provide the result", `SS:LRO-Operation-result`), but then an import's client has no way to learn which file it made.
- There is no `metadata`. The Operation comment only says metadata "typically contains progress information" (`SS:LRO-Operation-metadata`) and names no fields, so any progress object would be coined vocabulary (C CH21). A client uploading through the draft still sees progress through HEAD on the upload resource; an import shows none until it is done, which is open question 10.
- `error` is a google.rpc.Status (R `SS:AIP151-Errors-2`) whose `code` is the Fault's Code (R `SS:AIP193-Status.code`). AIP-193 also requires every error to carry an ErrorInfo (R `SS:AIP193-Status.details-3`) whose reason matches `[A-Z][A-Z0-9_]+[A-Z0-9]` (R `SS:AIP193-ErrorInfo-2`) and whose (reason, domain) pair differs for logically different errors (R `SS:AIP193-ErrorInfo-4`), but it names no reasons. I couldn't derive the reason from the Code alone, because two Faults with one Code can call for different client actions (`TooLarge` and `QuotaAtFinalize` are both RESOURCE_EXHAUSTED), and AIP-193 judges sameness by the action a client might take (`SS:AIP193-ErrorInfo-5`). So `Reason` is the Fault's name in AIP-193's upper-case form (`SIZE_MISMATCH`, `STATE_LOST`, ..., plus `CANCELLED`), and the domain is the service name the shell supplies. Those reason strings are vocabulary we coin, which is an explicit exception to the brief's rule (CH4), recorded as CH21 and put to the product owner as open question 11.
- The shell renders an Operation only as google.longrunning JSON, never through AIP-193's HTTP JSON, which would need 499 for CANCELLED (`SS:AIP193-HTTP-1`).

### The eight circumstances

| Circumstance | Request | What the core answers | Basis |
|---|---|---|---|
| in flight up | HEAD on the upload resource; DRS GetObject; GetOperation | 204 with UC ?0, Upload-Offset, Upload-Length if known, Upload-Limit, no-store; 202 with Retry-After; `InProgress` | R `UP:RESUMABLE-UPLOAD-13-4.3.2-1`, `SS:LRO-Operation-done`; P PM36 |
| ready | DRS GetObject | 200 with the DRS object and its one checksum | R `DO:DRS-schemas.DrsObject-1`, `DO:DRS-schemas.DrsObject.checksums-1`; C CH1 |
| accessible | the object's access method | `available: true` | R `DO:DRS-schemas.AccessMethod.available-1` |
| downloadable | GetAccessUrl, then GET content | 200 with the access URL; then 200 or 206 with ETag, Last-Modified, Accept-Ranges | R `DO:DRS-paths.objects.{object_id}.access.{access_id}.get-1`, `HS:RFC9110-15.3.7-1` |
| in flight down | GET with Range | 206 with one Content-Range per request; no server state | R `HS:RFC9110-15.3.7-1`; P PM27 |
| inaccessible | anything on an ended upload; DRS on a FAILED file; content of a DELETED file | 410 while the tombstone is kept, then 404; DRS answers 404 because its tables have no 410 | R `HS:RFC9110-15.5.11-1`, `DO:DRS-responses.404NotFoundDrsObject-1`; P PM30, PM41 |
| wrong permissions | any | 401 with WWW-Authenticate for missing or bad credentials; 403 for insufficient ones, whether or not the file exists | R `SS:AIP193-PermissionDenied-1`, `HS:RFC9110-15.5.2-2`; P PM1, PM2 |
| wrong destination, upload | CreateUpload | 409 for a missing parent, 413 above max-size, 507 over quota | R `HS:RFC9110-15.5.10-1`, `HS:RFC4918-11.5-1`; P PM16; C CH13, CH14 |
| wrong destination, import | StartImport | 409 for a missing parent at creation; an import above max-size or over quota is only found out while it runs, so its operation fails later with RESOURCE_EXHAUSTED (`TooLarge` or `QuotaAtFinalize`) | R `HS:RFC9110-15.5.10-1`, `SS:GRPC-STATUSCODES-RESOURCE_EXHAUSTED`; C CH13, CH14, CH39 |

We designed the upload refusals for a client that follows the draft's client rules, which we can't require of anyone (PM43). Such a client resumes at the given offset after a 409 with UC ?0 and an Upload-Offset (`UP:RESUMABLE-UPLOAD-13-4.7-2`), retrieves the offset first after a 409 with UC ?0 and none (`UP:RESUMABLE-UPLOAD-13-4.7-2`), stops after any answer with UC ?1 (`UP:RESUMABLE-UPLOAD-13-4.1.2-5`), resumes within limits after 413 (`UP:RESUMABLE-UPLOAD-13-4.7-3`), and retries after 5xx (`UP:RESUMABLE-UPLOAD-13-4.7-5`). For operations, we designed each Fault's Code for a client that follows AIP-194 (PM42). SF4 and SF5 check both designs, and both state their assumption about the client in the claim. What happens after that next request depends on the server's state in between, which no client model can see, so that half is a separate claim about `stepFile` (SF11): after `AlreadyComplete`, the offset retrieval a following client sends is answered with UC ?1 (V3, F6) or with `Gone` (V5, F10, or 410 once the file ended), and none of those answers invites the client to resume.

## Porting plan

The rule for every port is the same. Where the original is data (a CSV, XML registry, proto enum, TypeScript constant array, or a table quoted in a statement), `gen-vocab` generates the Haskell from the vendored file and an exhaustive check compares the generated module against the file row by row. Where the original is code, `test/Port/` holds a literal transcription of the original function, bugs included, and `test/Exhaustive.hs` enumerates the whole finite input domain and asserts that our function and the transcription agree everywhere except on exactly the documented divergence set. A divergence that isn't in the list, or a listed one that no longer differs, fails the build. The S3 ports moved to the adapter and are listed in its section.

| Original | Haskell module | How the port is checked | What changes on the way |
|---|---|---|---|
| `references/http-semantics/http-status-codes-1.csv` | `Http.Status` | generated; all 75 rows compared: 62 round trips `fromWire (statusCode s) == s`, every unassigned and Unused code folds to its class's x00 | constructor names from the registry, not the stale phrases in Go `status.go`, CPython `http__init__.py` or http-types `Status.hs` |
| `http-types/Status.hs:783-816` | `Http.Status.classOf` | transcription `Port.HttpTypesStatus`; exhaustive diff of its five class predicates against `classOf . fromWire` over codes 0..999 (1000 inputs); `classOf` proved against `fromWire` | class predicates become a reflected table; a code outside 100..599 gets class 5xx through `fromWire` (P `HS:RFC9110-15-6`, PM38), where http-types gives it no class, so the divergence set is exactly 0..99 and 600..999 |
| `problems-and-digests/iana/http-digest-hash-alg.xml` | `Digest` | generated; 8 rows compared, and `Forwarded` generated from the keys that name a receipt algorithm, which today is none | none |
| `problems-and-digests/iana/http-problem-type-uris.csv` | `Problem` | generated; the registered rows the core uses compared; the draft's two types added by hand behind the flag | `digest-invalid-values` and `digest-mismatched-values` not emitted |
| `status-and-supervision/googleapis/code.proto` | `Rpc.Code` | generated; 17 names and numbers compared | the HTTP mapping is not ported |
| `status-and-supervision/aip/0194.md` (statements) | `Rpc.Recourse` | generated from the 18 AIP-194 entries and their three section headings; `listedAs` checked total and injective over the 17 Codes, with UNAUTHORIZED its only unreached name | nothing dropped |
| `http-semantics/code/go/fs.go:470-671` | `Http.Precondition.ladder` | transcription `Port.GoFs.checkPreconditions`; exhaustive diff over 3^5 header results x 3 method kinds x Range present x representation exists (2916 inputs) | (a) a date If-Range is false; (b) the If-Match and If-Unmodified-Since steps are guarded by `origin`; (c) If-Range only for GET, not HEAD; (d) `If-Match: *` holds only when a representation exists; (e) `If-None-Match: *` fails only when one exists |
| `go/fs.go:431-468` | `Http.Validator` | the four rows of `HS:RFC9110-8.8.3.2-3` by exhaustion | ETag scanning stays in the shell |
| `http-semantics/code/urllib3/retry.py:184-189, 308-333, 379-407` | `Http.Retry.onStatus` | transcription `Port.Urllib3.is_retry`; exhaustive diff over 9 methods x 100..599 x Retry-After absent, delay, past date | adds 507, 421, 425 and 408; delay-seconds is `1*DIGIT` |
| `go/request.go:1543-1557`, `go/transport.go:756-800` | `Http.Retry.onConnection` | transcriptions; exhaustive diff over methods x faults x body rewindable | Idempotency-Key dropped; PUT and DELETE count as idempotent |
| `grpc/A6-client-retries.md` | `Http.Retry.backoff`, `Throttle` | LiquidHaskell refinements on the bounds | jitter is the shell's; tokens in integer milli-tokens |
| `uploads/tusd/unrouted_handler.go:1562-1600`, `:734-876`, `datastore.go:12-31` | `Upload`, rows A1 to A9 | transcription of `getIETFDraftUploadLength`; exhaustive diff over (Opt length, Opt UC, Opt Content-Length, offset) on 0..3 | `Size` plus `SizeIsDeferred` becomes `Len`; no completion from `Offset == Size`; no 423; no 500 on timeouts |
| `drive-and-objects/ga4gh-drs-1.5.0` (statements) | `Project.Drs` | required fields by construction | none |
| `problems-and-digests/crc/nvm-command-set-1.1-excerpt-5.3.1.3.txt` | `Store.Algorithm` | the width and parameters in `PD:NVME-NVMCS-1.1-5.3.1.3.4-2` compared with `PD:REVENG-crc.cat.crc-64-nvme-1` | only the width is used; no CRC is computed |

Deliberately not ported: the CRC-64/NVME code (`aws-checksums`, `Crc64NvmeJs.ts`), because the core never computes a checksum (CH3); OTP's `supervisor.erl`, because restart policy is the shell's runtime and the core's bound is one counter plus a deadline; Funnel's two TES transition functions, which disagree with each other and whose lesson is that there must be exactly one; the WebDAV handlers and locks (CH12); tus-js-client's retry rule; abseil's errno mapping; grpc-gateway's `HTTPStatusFromCode`.

## Theorem catalog

Methods: **refinement** (a LiquidHaskell type discharged by z3; for `stepFile` this is always a postcondition on its `Out`, stated over measures such as `eventTag`, `phaseTag`, `lifeTag` and `outcomeTag`, because `stepFile` is not reflected), **reflection** (a reflected definition and a lemma under `--reflection --ple`), **construction** (the bad value has no constructor, or the only builder enforces the rule, backed by GHC's exhaustiveness check and LiquidHaskell's totality check), **exhaustion** (every point of a genuinely finite domain checked, either as equational cases inside LiquidHaskell or by `test/Exhaustive.hs`; nothing is sampled, so it is only used where no payload is unbounded). The Spike column says whether this shape already went through: verified (the same claim was SAFE in a spike), pattern (a structurally identical proof was SAFE), or not yet. A theorem whose basis includes a Chosen entry says "(our policy)" in its claim, because it proves what we decided, not what a standard requires. A theorem that predicts what a client does says which client it assumes.

The earlier DC2 ("every `Receipt` has algorithm `Crc64Nvme` and a checksum below 2^64") is gone: the one-constructor type and the refined `Checksum` make it true as soon as the module compiles, so it is a note under Store.Receipt. The earlier DC15 is now the lint L1 below, because neither GHC nor LiquidHaskell can quantify over a module's exports.

### Data corruption

| # | Claim | Basis | Method | Spike |
|---|---|---|---|---|
| DC1 | (our policy) ACTIVE is reached only by F1 or P1, from a complete upload, with a receipt from `vouch` whose size equals the length. On F1 the size clause holds largely by echo, because the seal's expected length is the offset by construction and an adapter may report back the size it sent (S12), so it only has content on P1 | C CH1 | construction plus refinement on `stepFile`, using Creation's data refinement `finishing p => complete upload` | pattern (the review spike's StepInv, SAFE with that refinement and no runtime check; UNSAFE without it) |
| DC3 | (our policy) `ChunkPersisted` never moves a file to ACTIVE: it changes the life only to Sealing (still CREATING) or to FAILED `QuotaAtFinalize`, `OutOfRange`, `TooLarge` or `Contradiction`; and no row reaches ACTIVE from anything but a `Vouched` answer to a seal or an ask | C CH1, CH6 | refinement on `stepFile` | pattern |
| DC4 | (our policy) from Sealing, `Refused LengthDiffers`, `Refused NotPermitted`, `Refused Inconsistent` and `Unvouchable` end the file in one step, and from Asking, `Unvouchable` and any `Refused` do too; `NotYetVouched`, `Ambiguous`, `Unavailable` and `StagingGone` at seal lead to Asking | C CH7, CH8 | refinement on `stepFile` | pattern |
| DC5 | (our policy) `Seal` is issued again only by T1 after P7, so never after a deterministic answer, `NotYetVouched` or `StagingGone` | C CH7; P `HS:RFC9110-9.2.2-4` (PM3) | refinement on the phase relation | not yet |
| DC6 | (our policy) `offset == chunkBytes chunks`, the offset never decreases across any step, and the offset in any reply is at most the bytes of chunks the store acknowledged durable | R `UP:RESUMABLE-UPLOAD-13-4.1.1-1`, `UP:RESUMABLE-UPLOAD-13-4.1.1-7`; C CH1 | refinement (offset is a measure) | verified (monotonicity) |
| DC7 | a known length never changes, offset <= length, and complete implies length == offset | R `UP:RESUMABLE-UPLOAD-13-4.1.3-6`, `UP:RESUMABLE-UPLOAD-13-4.4.2-7`, `UP:RESUMABLE-UPLOAD-13-4.1.3-3` | data refinement on `Upload` | verified |
| DC8 | `complete` turns true only on a fully processed UC ?1 append or a well-framed end of an import, and never on an interruption | R `UP:RESUMABLE-UPLOAD-13-4.1.2-1`, `UP:RESUMABLE-UPLOAD-13-4.1.3-8`, `UP:RESUMABLE-UPLOAD-13-4.4.2-2` | refinement on `stepFile` | pattern |
| DC9 | (our policy) chunks are numbered 1..k with no gaps, k <= `cmax`, every chunk but the last has exactly `csize` bytes, the total is (k-1) x `csize` plus the last chunk's bytes and at most `climit`, `appendChunk` keeps `csize`, `cmax` and `climit`, and `Seal` receives that list with its total as the expected length | C CH6, CH28 | data refinement on `Chunks` carrying `csize`, `cmax` and `climit`, and on `Seal` | verified for the list (review spike, with its negative control); pattern for the `climit` bound (the second review spike's CapGuard, SAFE once the caller checks `offset + n <= maxSize`) |
| DC10 | (our policy) an import resumes only with a strong ETag from the same transfer, and a 200 or a mismatched 206 to a resumed fetch fails the file with ABORTED | R `HS:RFC9110-13.1.5-3`, `HS:RFC9110-13.1.5-6`, `HS:RFC9110-15.3.7.3-1`; C CH17 | construction (the resume argument is `(Offset, StrongETag)`) plus refinement | not yet |
| DC11 | (our policy) an import completes only after a length-delimited end with offset == length, or a chunked end, and never seals zero chunks unless the profile's `sealsEmpty` is true | R `HS:RFC9110-6.1-2`; C CH15, CH18 | refinement on I9 and I13 | not yet |
| DC12 | (our policy) in ACTIVE, the receipt and ETag never change | R `DO:DRS-DrsApiPrinciples.DRS-IDs-2`, `HS:RFC9110-8.8.1-2`; C CH32 | refinement on `stepFile` | pattern |
| DC13 | (our policy) FAILED, CANCELLED and DELETED absorb every event sequence: `run s es` keeps the life tag. AIP-216 would allow a user action to move them; we offer none | C CH10 | reflection with induction over the event list | verified |
| DC14 | (our policy) the life relation is CREATING to {CREATING, ACTIVE, FAILED, CANCELLED}, ACTIVE to {ACTIVE, DELETING}, DELETING to {DELETING, DELETED}, terminal to itself | R `SS:AIP216-Active-3`; C CH10 | refinement on `stepFile`, with the 6 x 6 relation checked by exhaustion | pattern |
| DC16 | (our policy) while no registered key names the receipt algorithm, `forwardable` is `Absent` for every key, every `Seal` carries `Absent`, and every client integrity field is refused at C6 or A8; none is silently dropped | P `PD:DIGEST-PROBLEMS-3.1-1`, `PD:RFC9530-2-2` (PM24); C CH2 | refinement: the generated `not (isPresent o)` on `forwardable`'s result and on `Seal`'s argument (not the empty declaration, which the logic can't see), plus refinement on C6 and A8 | pattern (the review spike's Empty, SAFE for `forwardable`) |
| DC17 | (our policy) no `Response` carries Repr-Digest | C CH19 | exhaustion over the Response constructors | pattern |
| DC18 | (our policy) a seal over zero chunks is issued only when the profile's `sealsEmpty` is true, and otherwise a zero-length file is refused with 501 or fails `Empty` | C CH15 | refinement on `stepFile` | not yet |
| DC19 | (our policy) in every CREATING state the offset is at most max-size, whether or not the length is known, so k <= `cmax` follows by rule 13; a client append that would cross it is refused with `ExceedsMaxSize` (A5, B8) and an import chunk that would cross it fails the file as `TooLarge` (I3a) | P `UP:RESUMABLE-UPLOAD-13-4.1.4-3` (PM16); C CH39 | data refinement on `Chunks` (`total <= climit`) plus the guards of A5, A9, B3, I3 and I3a | pattern (CapGuard) |

### Resource exhaustion

| # | Claim | Basis | Method | Spike |
|---|---|---|---|---|
| RE1 | (our policy) every attempt counter in every life (`Creation.attempts`, the `Retry` of DELETING and of every `Cleanup`) is at most `attemptCap` = 5, every retrying row compares it with the configured `maxAttempts`, and K3's loop counts against it, so origin and store retries stop | R `SS:GRFC-A6-Validation-1`; C CH31 | data refinement against the inline constant | not yet |
| RE2 | a connection failure is retried at most once until a chunk is persisted | P `HS:RFC9110-9.2.2-8` (PM4) | refinement on I11 | not yet |
| RE3 | (our policy) `backoff` never exceeds its cap; on every retrying step the wait is the delay hint when there is one, and then the backoff step is reset to 1, and otherwise the wait is `backoff cfg s` and the step becomes s + 1 | R `SS:GRFC-A6-Backoff`, `SS:GRFC-A6-Pushback-3`; C CH31 | refinement on `nextWait`, and a postcondition on `stepFile` over `delayStep` and `retryStep` | not yet |
| RE4 | (our policy) the token count stays in [0, `maxTokens`]; `stepFile`'s `throttle` is `CallFailed` exactly for a current `Unavailable` or `Ambiguous` store answer or chunk failure, `CallSucceeded` exactly for a current `Done` answer or `ChunkPersisted`, and `NoCall` otherwise, stale reports included; and `retryAllowed` holds exactly above `maxTokens`/2 | R `SS:GRFC-A6-Throttling-1`, `SS:GRFC-A6-Throttling-2`, `SS:GRFC-A6-Throttling-3`; C CH31 | data refinement on `Throttle` (with `maxTokens` as its own field, rule 9), a postcondition on `stepFile`, and a refinement on the function `step` uses to compute `retryAllowed` | pattern (the first review spike's Throttle, for the bucket) |
| RE5 | (our policy) every FAILED or CANCELLED file with a staging area starts with cleanup [Discard, Confirm], and one that ended while its Open was in flight starts with [AwaitOpen, Discard, Confirm]; cleanup ends only when a confirm finds no chunks staged, on `StagingGone`, on an Open that failed, or with an alert | C CH6 | refinement on `stepFile` | not yet |
| RE6 | (our policy) every file the store holds without a usable receipt, or whose outcome is unknown, gets a Remove step | C CH1, CH8 | refinement on `stepFile` over F2, F4, P4, P7, P8, P9, P10 and T3 | not yet |
| RE7 | (our policy) at a Tick with now >= deadline in OPN, IDL, APP, PER, FET or WAI the file is FAILED `Expired`; at a Tick with now >= `replyBy` in SEA or ASK, `held` becomes `Absent`; every row that sets a deadline, `replyBy`, `finalizeBy`, a `Waiting` or `Refetching` instant, an upload retention or a tombstone emits a `SetTimer` for it; and the step that first takes a file out of CREATING sets `doneAt` to now and emits `SetTimer`s for `doneAt + opRetention` and `doneAt + tombstoneHorizon` | P `UP:RESUMABLE-UPLOAD-13-4.1.4-7` (PM40); R `SS:GRFC-A6-MaxAttempts-2`; C CH5, CH22 | refinement on `stepFile`, with a reflected `hasTimer t cmds` | pattern (the review spike's StepF verified a `hasTimer` postcondition) |
| RE8 | `creatingByOwner o` equals the number of CREATING files of owner `o`; it is the only thing `step` decides on its own | P `UP:RESUMABLE-UPLOAD-13-13-8` (PM13) | construction at the single update site in `World` | not machine-checked |

### Concurrency

| # | Claim | Basis | Method | Spike |
|---|---|---|---|---|
| CC1 | (our policy) a report with a stale epoch, or one the slot isn't waiting for, returns the file unchanged, with `StopMover` for mover reports; a current store report of the wrong command is handled as `Ambiguous` with an alert | R `UP:RESUMABLE-UPLOAD-13-4.6-3`; C CH29, CH42 | refinement on `stepFile` | verified (operations probe, first half) |
| CC2 | (our policy) a file has one slot, and the epoch strictly increases whenever the slot starts a new job (a store call, a StartAppend, a PersistChunk or a StartFetch), except that an ending in Opening keeps the epoch of the Open in flight so its answer stays current | R `UP:RESUMABLE-UPLOAD-13-4.6-3`; C CH29 | construction plus refinement | pattern |
| CC3 | (our policy) a new upload request while Appending terminates the old one first; while Persisting an Append or OffsetQuery is deferred, so two chunk writes never target one chunk number | P `UP:RESUMABLE-UPLOAD-13-4.6-4`, `UP:RESUMABLE-UPLOAD-13-4.6-5` (PM8); C CH30 | refinement on `stepFile` over B1, B2 | not yet |
| CC4 | (our policy) a cancel while opening or receiving (OPN, IDL, APP, PER, FET, WAI) ends the file CANCELLED at once; while sealing or asking it sets `cancelRequested` and closes the upload resource, and a receipt still gives ACTIVE; in ACTIVE, CancelOperation changes nothing and CancelUpload changes only `uploadRes`, so the life stays ACTIVE | R `SS:LRO-CancelOperation-2`, `SS:LRO-CancelOperation-3`; P PM15; C CH9, CH30 | refinement on `stepFile` | not yet |
| CC5 | every Upload-Offset in a Reply equals the offset of the state the step returns (the receipt's size in ACTIVE), and the offset changes only on B10, B11 and I3, so the offset a client was last told is the one A2 compares against until one of those rows runs | R `UP:RESUMABLE-UPLOAD-13-4.6-3`, `UP:RESUMABLE-UPLOAD-13-4.1.1-6` | a postcondition on `stepFile` over a reflected predicate on the command list, the same shape as RE7 | not yet |
| CC6 | (our policy) in SEA and ASK every `Waiting` instant is at most `finalizeBy`, and at a Tick with now >= `finalizeBy` a file with no call outstanding leaves CREATING; expiry by deadline moves a file to FAILED only from Opening or Receiving | P `UP:RESUMABLE-UPLOAD-13-4.1.4-7` (PM40); C CH7, CH37 | refinement on `stepFile`; per step only because Sealing and Asking can't hold an Idle slot any more | not yet |
| CC7 | (our policy) `step` on the World changes only the file named by the event | C CH27; follows from routing by the event's file id and one `Map.insert` at one key | construction | not machine-checked |

### Silent failures

| # | Claim | Basis | Method | Spike |
|---|---|---|---|---|
| SF1 | with access other than Allowed, the answer is 401 or 403, the World is unchanged, and nothing about existence, state or preconditions affects it | R `SS:AIP193-PermissionDenied-1`, `HS:RFC9110-15.5.2-2`; P PM1, PM2 | refinement on `admit` and `step` | verified |
| SF2 | (our policy) no store answer and no origin status leads to a 401 or 403, or to a Fault with UNAUTHENTICATED or PERMISSION_DENIED; `Revoked` comes only from an event's own access | R `SS:GRPC-STATUSCODES-PERMISSION_DENIED-2`; C CH24 | refinement on `stepFile` for store answers; exhaustion over 100..599 for origin statuses | not yet |
| SF3 | a request with UC ?1 never gets a 2xx without UC ?1 | R `UP:RESUMABLE-UPLOAD-13-4.2.2-4`, `UP:RESUMABLE-UPLOAD-13-4.4.2-4` | refinement on `replyToCompleting` | verified |
| SF4 | (our policy) `faultCode` is never OK or CANCELLED, and for a client that follows AIP-194, `recourse (listedAs (faultCode f))` is the section we intended for every Fault f | R `SS:GRPC-STATUSCODES-OK`; P `SS:AIP194-NonRetryable-0`, `SS:AIP194-GenerallyNonRetryable-0` (PM42); C CH36 | refinement plus exhaustion over 18 Faults | not yet |
| SF5 | for a client that follows the draft's client rules, each upload Refusal leads to the next request we intended: `AlreadyComplete` to an offset retrieval, `OffsetMismatch` to an append at the offset it carries, `AppendTooLarge`, `AppendTooSmall` and `ExceedsMaxSize` to an append within the announced limits, a 5xx to a retry, and any answer with UC ?1 to no further request | P `UP:RESUMABLE-UPLOAD-13-4.7-2`, `UP:RESUMABLE-UPLOAD-13-4.1.2-5`, `UP:RESUMABLE-UPLOAD-13-4.7-3`, `UP:RESUMABLE-UPLOAD-13-4.7-5` (PM43), `UP:RESUMABLE-UPLOAD-13-4.1.2-6` (PM21) | exhaustion over Refusal tags against a transcription of the client rules | not yet |
| SF6 | `operationOf` gives InProgress exactly for CREATING, a Done result otherwise, never done-without-result, and every Failed result carries a Reason | R `SS:LRO-Operation-done`, `SS:LRO-Operation-result`, `SS:LRO-CancelOperation-3`, `SS:AIP193-Status.details-3` | construction plus a total function | not yet |
| SF7 | (our policy) DELETED is reached only through D1, after the store answered the Remove | R `SS:AIP216-Active-3`; P PM29; C CH41 | refinement on `stepFile` | not yet |
| SF8 | a problem's `status` equals the response status, and a non-about:blank type appears only with its recommended status | R `PD:RFC9457-3.1.2-2`, `UP:RESUMABLE-UPLOAD-13-14.4-1`, `UP:RESUMABLE-UPLOAD-13-14.4-2` | construction plus exhaustion over 4 types | pattern |
| SF9 | for every valid received code, `fromWire` keeps its class; an unregistered code becomes its class's x00; an invalid one becomes 500 | R `HS:RFC9110-15-4`, `HS:RFC9110-15-5`; P `HS:RFC9110-15-6` (PM38) | refinement, symbolic over every Int | verified |
| SF10 | (our policy) on every step, every request id held in the old state (in `held` or in the slot as an `Appending` or `Persisting` request) that is not held in the new state appears in a `Reply`, an `Abandon` or a `Defer` among the step's commands | C CH22, CH30 | a postcondition on `stepFile` over a reflected predicate on the command list, the same shape as RE7 | not yet |
| SF11 | (our policy) in every state where a row can answer `AlreadyComplete` (ACT with the upload retained, SEA and ASK with `uploadOpen`), and in every state reachable from those, an OffsetQuery is answered either with a 204 carrying UC ?1 (V3, F6) or with `Gone` (V5, F10, or 410 once the file ended); none of these answers invites a resumption. A seal that fails, a T4 deactivation and a cancel are all allowed in between, and they lead to the `Gone` cases | P PM21, PM43; C CH22 | a postcondition on `stepFile` over the life and phase tags, plus exhaustion over those tags | not yet |

### Conformance and vocabulary

| # | Claim | Basis | Method | Spike |
|---|---|---|---|---|
| V1 | `statusCode` is in 100..599, `fromWire (statusCode s) == s` for all 62 constructors, so `statusCode` is injective | R `HS:RFC9110-15-1`, `HS:IANA-HTTP-Status-Codes-100`, `HS:IANA-HTTP-Status-Codes-511` | exhaustion (62 equational cases) then reflection | verified |
| V2 | every `Response` has a Permanent status: no 1xx, 104, 306, 418, 499 or 510 | R `HS:IANA-HTTP-Status-Codes-104`, `HS:IANA-HTTP-Status-Codes-510`; P PM10 | exhaustion over Response and Refusal constructors | pattern |
| V3 | `ladder` restates RFC 9110 13.2.2 steps 1 to 6, has no already-applied verdict, and agrees with the Go transcription except on divergences (a) to (e) | R `HS:RFC9110-13.2.2-2`, `HS:RFC9110-13.2.2-3`, `HS:RFC9110-13.2.2-4`, `HS:RFC9110-13.2.2-5`, `HS:RFC9110-13.2.2-6` | refinement plus exhaustion (2916 inputs) | verified (refinements) |
| V4 | preconditions never change a response that would be other than 2xx or 412 without them; in particular a DELETE on a DELETED file is 410 whatever its preconditions | R `HS:RFC9110-13.2.1-2` | refinement | not yet |
| V5 | a satisfied range has `0 <= first <= last < n`; n == 0 means Ignore; 416 carries `*/n` | R `HS:RFC9110-14.1.2-3`, `HS:RFC9110-14.1.2-5`; P PM27, PM31 | refinement | verified |
| V6 | (our policy) `onStatus` never repeats after 507, allows 421 for any method, never repeats a non-idempotent method otherwise, and agrees with urllib3 except on its documented additions | R `HS:RFC4918-11.5-2`; P PM3, PM5; C CH31 | refinement plus exhaustion | verified (refinements) |
| V7 | (our policy) `onConnection` never retries on a fresh connection and agrees with Go's `shouldRetryRequest` except on PUT and DELETE | R `HS:RFC9110-9.2.2-1`; C CH31 | exhaustion | not yet |
| V8 | `codeNumber` is injective with image 0..16, and `listedAs` is total and injective with only UNAUTHORIZED unreached | R `SS:GRPC-STATUSCODES-OK`, `SS:GRPC-STATUSCODES-UNAUTHENTICATED`; P `SS:AIP194-GenerallyNonRetryable-UNAUTHORIZED` (PM42) | exhaustion (17 and 18 cases) | pattern |
| V9 | `safe` implies `idempotent`, the idempotent set equals urllib3's DEFAULT_ALLOWED_METHODS, and PATCH is neither | R `HS:RFC9110-9.2.1-2`, `HS:RFC9110-9.2.2-1`, `HS:RFC5789-2-1` | exhaustion | pattern |
| V10 | an unrecognised method gets 501 and a recognised one the resource doesn't support gets 405 with Allow | R `HS:RFC9110-15.6.2`, `HS:RFC9110-15.5.6` | exhaustion over `Recognised` x resource kinds | not yet |
| V11 | strong match implies weak match, and the four comparison rows hold | R `HS:RFC9110-8.8.3.2-1`, `HS:RFC9110-8.8.3.2-3` | refinement plus exhaustion | not yet |
| V12 | the plan never changes after creation, so every Upload-Limit for one upload is identical | P `UP:RESUMABLE-UPLOAD-13-4.1.4-8`, `UP:RESUMABLE-UPLOAD-13-4.1.4-11` (PM17) | refinement on `stepFile`: `plan (meta (next o)) == plan (meta f)` | not yet |
| V13 | (our policy) 401 has a challenge, 405 Allow, 201 Location, 206 Content-Range, 304 ETag, 415 Accept-Patch, the offset 409 Upload-Offset, and every 2xx answer to an offset retrieval Upload-Offset and Upload-Limit; Retry-After appears only on 202, 429 and 503; no 202 carries Location | R `HS:RFC9110-15.5.2-2`, `HS:RFC9110-15.5.6`, `HS:RFC9110-15.3.7.1`, `UP:RESUMABLE-UPLOAD-13-4.3.2-1`, `HS:RFC9110-10.2.2-1`; P PM6, PM22, PM36, PM45; C CH20 | construction, with every field name unique to its constructor (rule 10) | verified (401); pattern (the review spike's Resp5, with unique field names under `--reflection`) |
| V14 | (our policy) every closed type's constructors have a nonempty provenance in their own package, every `Cite` resolves in its group with an unchanged quote, and every `Required` cites a MUST or a definition that isn't on the option list | C CH4 (brief) | the per-constructor half by LiquidHaskell's totality check on each instance; the per-type half by `check-cites`, which fails on a declaration with no instance; the rest by `check-cites` | pattern (the review spike's Prov, for the per-constructor half) |
| V15 | (our policy) `stepFile` and `step` are total and terminating | C CH5 (brief) | LiquidHaskell totality and termination; B1 and G2 call the Idle and failure handlers directly, and O2 emits its `StartAppend` itself, so nothing calls `stepFile` again (rule 14) | pattern (the review spike's RedispatchM was SAFE even with re-entrant rows and a rank on the phase; the direct-call form needs no rank at all) |

### Lints, not theorems

- **L1** (our policy, C CH3): no event carries representation bytes, and no exported function from bytes yields a `Receipt` or a DRS checksum. `check-vendor` checks it over the module interfaces; it isn't a theorem, because nothing in GHC or LiquidHaskell can quantify over a module's exports.
- **L2** (C CH25): the vendor boundary, as `check-vendor` enforces it under "Package and module layout".
- **L3** (C CH27): the "Assume Overwrites Specifications" warning names `stepFile`, the non-reflected function that the reflected `run` calls; CI allows it for that name and fails on it for any other.

The whole catalog should check in a few minutes; the generated status module is the slowest piece measured, at about 45 seconds.

## What the shell owes the core

These are not decisions; they are the contract that makes the theorems mean something outside the core.

- Tag every report with the file it is for and the epoch of the job it answers (this used to be the second half of CC2, but no core proof can establish what the shell delivers), and deliver reports per job like this: exactly one `StoreReplied`, of that command's constructor, per `Store` call, with a call whose outcome the shell lost reported as `Failed (Ambiguous Absent)`; exactly one `ChunkPersisted` or `ChunkFailed` per `PersistChunk`, made against the staging area it names; exactly one `BodyReceived` or `BodyBroken` per `StartAppend`; and for each `StartFetch` an ordered, duplicate-free stream of one `OriginReplied`, then `ChunkPersisted` in chunk order, then exactly one of `ChunkFailed`, `FetchEnded` or `MoverDied`.
- Deliver `Tick fid` at or after every instant a `SetTimer` for that file asked for.
- Re-deliver a `Defer`red request after the next report for that file.
- Release a filled buffer when a `DropBuffer` names its epoch, or when the chunk write it fed reports; treat a `DropBuffer` for an epoch with no buffer as a no-op.
- Run one store adapter whose answers meet the store contract, and apply jitter to the core's delays.
- Generate unguessable ids, and never reuse one (`UP:RESUMABLE-UPLOAD-13-13-1`, `UP:RESUMABLE-UPLOAD-13-4-4`).
- Parse headers (ETag lists, HTTP-dates, Structured Fields) and hand the core typed values, with invalid fields already dropped.
- Supply the WWW-Authenticate challenges, the access verdict for every request, the owner's re-evaluated access on `FetchEnded`, `quotaRemaining`, and the AIP-193 domain.

## The S3 adapter: funknown-store-s3

Everything S3-specific lives here. `funknown-store-s3` is a second pure package with the same toolchain and rules as the core (Haskell2010, Safe, LiquidHaskell). It depends on `funknown-core` and implements the store contract for Amazon S3, and the core may not import it (C CH25). It does three jobs: it plans each `StoreCommand` and each chunk write as one S3 call, it maps each S3 reply to exactly one answer of that command's type, and it fixes the `StoreProfile`. It carries its own proofs, its own citations, mostly to the AWS documents under `references/problems-and-digests/aws/`, which the vendoring graded as definitions, and its own Permitted and Chosen registers (`SPM1` and `SCH1` and on, below). The same level rule applies here as in the core: a statement graded definition that gives advice ("you should call") or describes what an SDK does is not a Required basis for what the adapter maps. Its provenance is `S3Basis`, so none of this reaches the core's generated modules.

```
funknown-store-s3/
  src/Funknown/S3/
    Cite.hs         GENERATED from basis-s3.json: S3.Cite, one constructor per (group,id) the adapter cites
    Register.hs     GENERATED from basis-s3.json: S3.Why (CoreWhy or SPMn), S3.Rationale (CoreRationale or SCHn), S3Basis, class S3Provenance
    Checksum.hs     GENERATED from the Smithy model: ChecksumAlgorithm, ChecksumType; supports (from the quoted table)
    Base64.hs       the RFC 4648 alphabet as a reflected 64-way equality table; decode64 :: [Char] -> Opt [Octet]
    Receipt.hs      shape (port of isChecksumWithPartNumber), toVouching :: ReplyChecksums -> Nat -> Vouching
    Code.hs         GENERATED: S3Code from the S3 error-table statements; classify (port of smithy-typescript)
    Call.hs         S3Call (one constructor per S3 operation the adapter calls); plan :: StoreCommand -> S3Call; planChunk :: StagingRef -> ChunkNo -> S3Call
    Outcome.hs      S3Reply; one function per command, e.g. sealAnswer :: Nat -> S3Reply -> Answer Vouching,
                    and chunkAnswer :: S3Reply -> Answer ChunkToken, from which the mover reports ChunkPersisted or ChunkFailed
    Profile.hs      s3Profile :: StoreProfile
  test/Port/        AwsSdkPartNumber.hs, SmithyClassification.hs
```

### Commands become S3 calls

| Core command | S3 call | Basis |
|---|---|---|
| `Open Crc64Nvme` | CreateMultipartUpload with ChecksumAlgorithm CRC64NVME and ChecksumType FULL_OBJECT | R `PD:S3API-CreateMultipartUpload-API_CreateMultipartUpload-1`, `PD:S3API-CreateMultipartUpload-request-header-ChecksumAlgorithm-1`, `PD:S3API-CreateMultipartUpload-request-header-ChecksumType-1`, `PD:S3UG-INTEGRITY-UPLOAD-Full-object-checksums-6` |
| `PersistChunk e ref k` | UploadPart on upload ID `ref` with part number k; the part's ETag becomes the opaque `ChunkToken` | R `PD:S3UG-MPU-mpu-process-2`, `PD:S3UG-MPU-mpu-process-3` |
| `Seal ref chunks n d` | CompleteMultipartUpload on upload ID `ref` with the part list 1..k and each part's ETag, MpuObjectSize n and `If-None-Match: *`; no ChecksumCRC64NVME request header, because `d`'s type `NoForward` only admits `Absent` while `Forwarded` has no constructor | R `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-1`, `PD:S3API-CompleteMultipartUpload-request-header-MpuObjectSize-1`, `PD:S3API-CompleteMultipartUpload-request-header-IfNoneMatch-1`, `PD:S3UG-MPU-mpuchecksums-2` |
| `AskReceipt` | HeadObject with ChecksumMode ENABLED | R `PD:S3API-HeadObject-request-header-ChecksumMode-2`, `PD:S3API-HeadObject-response-header-ChecksumCRC64NVME-1`, `PD:S3API-HeadObject-response-header-ContentLength-1` |
| `Discard ref` | AbortMultipartUpload | R `PD:S3API-AbortMultipartUpload-API_AbortMultipartUpload-1` |
| `ConfirmDiscarded ref` | ListParts on upload ID `ref` | P `PD:S3API-AbortMultipartUpload-API_AbortMultipartUpload-2` (SPM1) |
| `Remove` | DeleteObject | C SCH5 |

Declaring the algorithm and FULL_OBJECT at CreateMultipartUpload keeps us out of the case S3 describes for its older algorithms, where a checksum offered only at Complete is accepted without being stored (`PD:S3UG-INTEGRITY-UPLOAD-Full-object-checksums-6`), and S3 calculates the CRC-64/NVME of the full object once the upload completes (`PD:S3UG-MPU-mpuchecksums-1`). `If-None-Match: *` is how this adapter meets store contract clause 2, which is what makes the core's one re-seal (P7) safe, so S10 proves `plan` always sends it.

`s3Profile` sets `maxChunks = 10000` (R `PD:S3UG-MPU-mpu-process-2`), a `chunkSize` P with `P >= 5242880` (R `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-4`; 5242880 satisfies "5 MB" under either reading), and `sealsEmpty = False` (C SCH7), because zero-part completion isn't vendored. With checksums, S3 needs part numbers that start at 1 and are consecutive, and answers 500 otherwise (R `PD:S3UG-MPU-mpuchecksums-2`); the core's clause 7 promises exactly that numbering, and S10 checks that `plan` passes it through. The largest file is therefore 10000 x P, and S3's maximum part size isn't vendored yet. Because the core announces min-append-size = max-append-size = `chunkSize` to every client (CH28), P is also the exact size of every browser PATCH but the last; that is the one place S3's part minimum reaches a client, and open question 14 asks the product owner about it.

### S3 replies become store answers

| S3 reply | Core answer | Basis |
|---|---|---|
| CreateMultipartUpload 200 | `OpenR (Done (StagingRef uploadId))` | R `PD:S3API-CreateMultipartUpload-API_CreateMultipartUpload-1` |
| UploadPart 200 | `chunkAnswer` gives `Done (ChunkToken etag)`, and the mover reports `ChunkPersisted e k n` with it | R `PD:S3UG-MPU-mpu-process-3` |
| CompleteMultipartUpload 200 with ChecksumType FULL_OBJECT or absent and a ChecksumCRC64NVME value that decodes | `SealR (Done (Vouched rep))`, with the size taken from the MpuObjectSize the call sent | R `PD:S3API-CompleteMultipartUpload-response-ChecksumType-1`, `PD:S3API-Checksum-API_Checksum_Contents-1`, `PD:S3API-CompleteMultipartUpload-request-header-MpuObjectSize-1` |
| CompleteMultipartUpload 200 without a checksum, with ChecksumType COMPOSITE, or with a value that doesn't decode | `SealR (Done Unvouchable)` | R `PD:S3UG-MPU-mpuAndPermissions-1`, `PD:S3UG-MPU-mpuAndPermissions-2`, `PD:S3UG-INTEGRITY-UPLOAD-ChecksumTypes-Uploads-3`, `PD:RFC4648-3.3-1` |
| CompleteMultipartUpload 200 with an embedded error | `SealR (Failed (Ambiguous Absent))` | R `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-2` |
| CompleteMultipartUpload 412 | `SealR (Failed (Ambiguous Absent))` | R `PD:S3API-CompleteMultipartUpload-request-header-IfNoneMatch-1`; C SCH1 |
| CompleteMultipartUpload 409 (ConditionalRequestConflict, OperationAborted) | `SealR (Failed (Ambiguous Absent))` | R `PD:S3API-CompleteMultipartUpload-request-header-IfNoneMatch-1`, `PD:S3API-Error-OperationAborted-1` |
| HeadObject 200 with ChecksumType FULL_OBJECT or absent and a ChecksumCRC64NVME value that decodes | `AskR (Done (Exists (Vouched rep)))`, with the size taken from Content-Length | R `PD:S3API-HeadObject-response-header-ChecksumCRC64NVME-1`, `PD:S3API-HeadObject-response-header-ChecksumType-1`, `PD:S3API-HeadObject-response-header-ContentLength-1`, `HS:RFC9110-8.6-3` |
| HeadObject 200 without a checksum, with ChecksumType COMPOSITE, or with a value that doesn't decode | `AskR (Done (Exists Unvouchable))` | R `PD:S3UG-MPU-mpuAndPermissions-1`, `PD:RFC4648-3.3-1`; C SCH9 |
| HeadObject 404 | `AskR (Done NothingThere)` | R `PD:S3API-Error-NoSuchKey-1`, `HS:RFC9110-15.5.5-1` |
| NoSuchUpload, from any call that names an upload ID | `Failed (Refused StagingGone)` | R `PD:S3API-Error-NoSuchUpload-1`, `PD:S3API-UploadPart-API_UploadPart-1` |
| CompleteMultipartUpload InvalidRequest | `SealR (Failed (Refused LengthDiffers))` | R `PD:S3API-CompleteMultipartUpload-request-header-MpuObjectSize-1`; C SCH2 |
| CompleteMultipartUpload InvalidPart, InvalidPartOrder or EntityTooSmall | `SealR (Failed (Refused Inconsistent))` | R `PD:S3API-Error-InvalidPart-1`, `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-6`, `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-4` |
| AccessDenied, InvalidAccessKeyId or ExpiredToken, from any call | `Failed (Refused NotPermitted)` | R `PD:S3API-Error-AccessDenied-1`, `PD:S3API-Error-InvalidAccessKeyId-1`, `PD:S3API-Error-ExpiredToken-1` |
| UploadPart BadDigest | `ChunkFailed k (Ambiguous Absent)` | C SCH6 |
| 503 ServiceUnavailable, from any call | `Failed (Unavailable h)`, with Retry-After seconds if present | R `PD:S3API-Error-ServiceUnavailable-1`; C SCH8 |
| 503 SlowDown, from any call | `Failed (Ambiguous h)`, with Retry-After seconds if present | R `PD:S3API-Error-SlowDown-1`; C SCH4 |
| any other code `classify` calls Transient or Throttling, a timeout, or a lost connection | `Failed (Ambiguous Absent)` | C SCH10 |
| any other 4xx | `Failed (Refused Inconsistent)` | C SCH11 |
| AbortMultipartUpload 204 | `DiscardR (Done ())` | R `PD:S3API-AbortMultipartUpload-API_AbortMultipartUpload-1` |
| ListParts 200 with n parts | `ConfirmR (Done n)` | P `PD:S3API-AbortMultipartUpload-API_AbortMultipartUpload-2` (SPM1) |
| DeleteObject 204 | `RemoveR (Done ())` | C SCH5 |

The adapter never produces `NotYetVouched`. Every S3 reply that shows an object without a usable checksum describes something that won't change by asking again: the permissions text says the object "is created without a checksum value" (`PD:S3UG-MPU-mpuAndPermissions-1`), a composite checksum is a different calculation, not a late one (`PD:S3UG-INTEGRITY-UPLOAD-ChecksumTypes-Uploads-3`), and a value outside the base64 alphabet will never decode. So all three are `Unvouchable`, which store contract clause 4 makes deterministic, and the core ends the file at once in `ObjectWithoutReceipt` with a Remove step instead of probing until its attempts run out.

The size in a `Vouched` from CompleteMultipartUpload is the MpuObjectSize the call sent, because S3 answers InvalidRequest when that size and the object's differ (`PD:S3API-CompleteMultipartUpload-request-header-MpuObjectSize-1`), so a success means they agree. That makes the core's F2 reachable only through an ask, where HeadObject's Content-Length is the object's length by RFC 9110's rule for HEAD (`HS:RFC9110-8.6-3`). The echo is at least stated rather than hidden: S12 says a `Vouched` from `sealAnswer n` always has size n. The check that matters, that the object S3 built is as long as the chunks the core sent, is S3's own MpuObjectSize comparison, which reaches the core as `LengthDiffers` (SCH2).

`S3Code` has one constructor per S3 error-table row (the PD statements whose ids start `S3API-Error-`) that a call above can return, plus `ConditionalRequestConflict` and `OtherCode`; unknown codes fold into `OtherCode`, as gRPC folds unknown codes into UNKNOWN (`SS:GRPC-STATUSCODES-status-3`). `classify` matches the code before the status (R `PD:AWSSDK-RETRY-error-classification-4`): throttling codes and 429 are throttling (`PD:SMITHY-TS-service-error-classification-isThrottlingError-1`), transient codes and a bare 500, 502, 503 or 504 are transient (`PD:SMITHY-TS-error-classification-constants-TRANSIENT_ERROR_CODES-1`), everything else is non-retryable. The adapter uses that classification only to separate "maybe try again" from "refused", and how it maps each side is its own choice, not the SDK's. The SDK documentation only describes what the SDK does with each class: transient errors (`PD:AWSSDK-RETRY-error-classification-1`) and throttling errors (`PD:AWSSDK-RETRY-error-classification-2`) are retried, and non-retryable errors "are returned to your code immediately" (`PD:AWSSDK-RETRY-error-classification-3`). We read the first two as "the call may or may not have happened" and map them to `Ambiguous` (SCH10), and we read the third as a deterministic refusal, which is what store contract clause 4 promises the core about `Refused`, and map it to `Refused Inconsistent` (SCH11). Those statements are the evidence for both readings, not a basis that leaves us no choice. It hands the core `Unavailable` only for ServiceUnavailable, whose description says S3 "is unable to handle request" (`PD:S3API-Error-ServiceUnavailable-1`), because store contract clause 3 promises the core that `Unavailable` means "not processed", and reading "unable to handle" that way is still our reading (SCH8). SlowDown only says "Reduce your request rate" (`PD:S3API-Error-SlowDown-1`), which says nothing about whether the call was processed, so it is `Ambiguous` and keeps its delay (SCH4). Every other retryable failure is `Ambiguous` too, which costs the core at most one extra ask. The credential codes mean the store refuses us, and they never reach a person as 401 or 403 (C CH24, through `CoreRationale`).

Two more rows rest on readings, and SCH1 and SCH2 record them. The first is the 412. Object keys come from file ids that are never reused, so a 412 from `If-None-Match: *` on CompleteMultipartUpload most likely means our own earlier Complete already succeeded. RFC 9110 doesn't say that: its "already succeeded" exception exists only for If-Match and If-Unmodified-Since, in steps 1 and 2 of the evaluation order (`HS:RFC9110-13.2.2-2`, `HS:RFC9110-13.2.2-3`), and If-None-Match in step 3 has none (`HS:RFC9110-13.2.2-4`). So reading success into the 412 would be an inference, and I mapped it to `Ambiguous` instead, after which the core asks for the receipt, so nothing depends on the inference. The second is InvalidRequest at Complete: the only vendored cause is the MpuObjectSize mismatch, so the adapter reports `LengthDiffers`, and a different InvalidRequest cause would end the file as `SizeMismatch` instead of `Contradiction`. Both are final, so neither reading can make a file available.

### The receipt check

`toVouching` turns the checksum fields of a CompleteMultipartUpload or HeadObject reply, together with the size the row above names, into a `Vouching`, and it is the only producer of `Vouched`:

1. The ChecksumType, when present, is FULL_OBJECT (R `PD:S3API-CompleteMultipartUpload-response-ChecksumType-1`, `PD:S3API-HeadObject-response-header-ChecksumType-1`, `PD:S3-SMITHY-com.amazonaws.s3#ChecksumType-1`). For CRC64NVME, S3 says the checksum is always full-object (`PD:S3API-CompleteMultipartUpload-request-header-ChecksumCRC64NVME-1`, `PD:S3UG-INTEGRITY-UPLOAD-MultipartUploads-Checksums-1`), and the adapter checks anyway.
2. The ChecksumCRC64NVME value decodes as base64 with the RFC 4648 section 4 alphabet (R `PD:RFC4648-4-2`), rejecting any character outside it (R `PD:RFC4648-3.3-1`), to exactly 8 octets, the "64-bit" value S3 describes (R `PD:S3API-Checksum-API_Checksum_Contents-1`). The 8-octet check is a runtime comparison, not a proof, because the decoder's output length depends on `div`.
3. The 8 octets are read big-endian. S3 only states the byte order for trailer chunks (`PD:S3UG-INTEGRITY-UPLOAD-trailing-checksums-1`), so applying it to response headers is our reading (C SCH3). S11 pins the decoder to that order with the CRC-64/NVME check value, so the only thing left unproven is S3's own byte order in response headers.
4. The decoder accepts the value with its one `=` of padding or without it. RFC 4648 requires encoders to pad unless the referring specification says otherwise (`PD:RFC4648-3.2-1`) and the S3 text only says "Base64 encoded", so S3 presumably pads, but no proof depends on that.

Anything that fails steps 1 or 2 is `Unvouchable`, not `NotYetVouched`.

`decode64` is typed over `[Char]`, because `Text` has no measures for a proof to induct over, and the shell unpacks the header value. It is built the way the review spike built it: a reflected 64-way alphabet predicate `allB64` gates a decoder whose arithmetic is not reflected, so rule 6 on `div` is respected, and the refinement `decode64 :: s:[Char] -> {v:Opt [Octet] | isPresent v => not (hasDash s)}` follows from a lemma that `allB64 t` implies `not (hasDash t)`, proved by induction on `t`. The earlier draft grounded padding in RFC 9651 (`PD:RFC9651-4.1.8-1`), which governs Structured Field byte sequences and not S3's headers, and its composite-value proof depended on that padding. The proof that replaced it depends only on the alphabet: a composite value ends in `-N` (`PD:AWS-SDK-JS-isChecksumWithPartNumber-isChecksumWithPartNumber-1`), `-` is not in the base64 alphabet (`PD:RFC4648-4-2`), and a decoder must reject non-alphabet characters (`PD:RFC4648-3.3-1`), so no composite value can ever decode, padded or not.

### The adapter's theorems

| # | Claim | Basis | Method | Spike |
|---|---|---|---|---|
| S1 | no string containing `-` decodes, so no composite value ever becomes `Vouched` | R `PD:RFC4648-4-2`, `PD:RFC4648-3.3-1`, `PD:AWS-SDK-JS-isChecksumWithPartNumber-isChecksumWithPartNumber-1` | reflection with induction on the `[Char]` | verified (review spike, with its negative control) |
| S2 | (our policy) `Vouched` is produced only by `toVouching`, only for ChecksumType FULL_OBJECT or absent, and only for a value that decodes to exactly 8 octets; a 200 without a usable checksum is `Unvouchable`, and no reply maps to `NotYetVouched` | R `PD:S3API-CompleteMultipartUpload-response-ChecksumType-1`, `PD:S3API-Checksum-API_Checksum_Contents-1`, `PD:S3UG-MPU-mpuAndPermissions-1`; C CH6, SCH9 | construction plus exhaustion over reply shapes | not yet |
| S3 | `supports` equals the S3 table on all 10 x 2 x 2 points, and CRC64NVME is never COMPOSITE | R `PD:S3UG-INTEGRITY-UPLOAD-MultipartUploads-Checksums-1`, `PD:S3API-PutObject-request-header-ChecksumCRC64NVME-1` | exhaustion | verified |
| S4 | (our policy) a 200 with an embedded error, a 412, a 409, a SlowDown, a timeout and a lost connection map only to `Ambiguous`, never to `Vouched` or `NothingThere` | R `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-2`; C SCH1, SCH4 | exhaustion over reply tags x calls | not yet |
| S5 | (our policy) `Unavailable` comes only from ServiceUnavailable | R `PD:S3API-Error-ServiceUnavailable-1`; C CH6, SCH8 | exhaustion over `S3Code` x status | not yet |
| S6 | `classify` matches the code before the status and equals the smithy-typescript tables | R `PD:AWSSDK-RETRY-error-classification-4`, `PD:SMITHY-TS-error-classification-constants-TRANSIENT_ERROR_STATUS_CODES-1` | exhaustion | not yet |
| S7 | (our policy) every per-command answer function is total over every reply, and maps the credential codes only to `Refused NotPermitted` | R `PD:S3API-Error-AccessDenied-1`; C CH24 | GHC exhaustiveness plus exhaustion | not yet |
| S8 | every string the `isChecksumWithPartNumber` transcription calls part-suffixed fails `decode64`, over every string up to length 8 on the alphabet `A`, `9`, `=`, `-`, `0`, `1` | R `PD:AWS-SDK-JS-isChecksumWithPartNumber-isChecksumWithPartNumber-1`, `PD:RFC4648-3.3-1` | exhaustion against the transcription | not yet |
| S9 | (our policy) `s3Profile` has `chunkSize >= 5242880`, `maxChunks == 10000` and `sealsEmpty == False` | R `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-4`, `PD:S3UG-MPU-mpu-process-2`; C SCH7 | refinement | pattern |
| S10 | for every `Seal ref chunks n d`, `plan` returns a CompleteMultipartUpload on `ref` that carries `If-None-Match: *`, MpuObjectSize n, and the part list 1..k with each chunk's token, and carries a ChecksumCRC64NVME header exactly when `d` is `Present`, which `NoForward`'s refinement rules out while `Forwarded` has no constructor; this is the adapter's discharge of store contract clause 2 | R `PD:S3API-CompleteMultipartUpload-request-header-IfNoneMatch-1`, `PD:S3API-CompleteMultipartUpload-request-header-MpuObjectSize-1`, `PD:S3UG-MPU-mpuchecksums-2` | refinement on `plan` | not yet |
| S11 | (our policy) `toVouching` on the value `rosUhgp5mIg=`, the base64 of the CRC-64/NVME check value 0xae8b14860a799888 written big-endian, yields exactly that Integer, and on the same octets reversed does not | R `PD:REVENG-crc.cat.crc-64-nvme-1`, `PD:RFC4648-4-2`; C SCH3 | exhaustion over the fixed vector in both byte orders | not yet |
| S12 | (our policy) a `Vouched` from `sealAnswer n` has size n, so on the seal path the core's size comparison is with the length it sent | R `PD:S3API-CompleteMultipartUpload-request-header-MpuObjectSize-1`; C SCH2 | refinement on `sealAnswer` | not yet |
| S13 | (our policy) `planChunk ref k` is an UploadPart on upload ID `ref` with part number k, and `chunkAnswer` maps an UploadPart 200 to `Done` with that part's ETag as the token and nothing else to `Done` | R `PD:S3UG-MPU-mpu-process-2`, `PD:S3UG-MPU-mpu-process-3`; C CH6 | refinement plus exhaustion over reply tags | not yet |

S11 is a pure check inside the adapter, and it pins our decoder's byte order. It can't show that S3 writes response headers in that order; that stays SCH3 until a vendored statement or a test against a real bucket in the shell settles it.

### Ports into the adapter

| Original | Haskell module | How the port is checked | What changes on the way |
|---|---|---|---|
| `smithy-typescript/.../service-error-classification/constants.ts`, `service-error-classification.ts` | `S3.Code.classify` | constant arrays generated from `constants.ts`; exhaustive diff over `S3Code` x the statuses that appear in the tables | AbortError has no counterpart; cancellation is an event |
| `api-models-aws/.../s3-2006-03-01.json`; `PD:S3UG-INTEGRITY-UPLOAD-MultipartUploads-Checksums-1` | `S3.Checksum` | enums generated from the Smithy model; `supports` generated from the quoted table and compared on all 10 x 2 x 2 points | none |
| `aws-sdk-js-v3/.../isChecksumWithPartNumber.ts` | `S3.Receipt.shape` | transcription with JavaScript `parseInt` semantics; used only as the oracle for S8 | strict suffix: `parseInt` accepts `-12abc` as part 12, we call it malformed; a composite never becomes "skip validation" |

### What the shell owes the S3 adapter

- Run the AWS SDK with max attempts 1, so the core is the only retry authority (`PD:AWSSDK-RETRY-retry-settings-1`).
- Configure an abort-incomplete-multipart lifecycle rule with a horizon longer than maxAge plus finalizeBudget. That rule is how S3 meets store contract clause 6: an orphaned CreateMultipartUpload is invisible to the core (`PD:S3UG-MPU-LIFECYCLE-mpu-abort-incomplete-mpu-lifecycle-config-1`), the multipart overview says uploads otherwise have "no expiry" (`PD:S3UG-MPU-mpuoverview-1`), and the abort action "has no effect on completed multipart uploads" (`PD:S3UG-MPU-LIFECYCLE-mpu-abort-incomplete-mpu-lifecycle-config-2`).
- Grant the permissions CompleteMultipartUpload needs to store a checksum, since without them the object is created without one (`PD:S3UG-MPU-mpuAndPermissions-1`); the core would then fail every file at once as `ObjectWithoutReceipt`.
- Grant `kms:Decrypt` on the bucket's KMS key when objects are KMS-encrypted, since HeadObject needs it to return the checksum (`PD:S3API-HeadObject-request-header-ChecksumMode-1`); without it an ask could look `Unvouchable` and the core would remove a good object.

The AWS documents contradict each other in places. The at-rest page and the multipart table disagree about which algorithms support composite checksums (`PD:S3UG-INTEGRITY-AT-REST-using-additional-checksums-rest-1`), but both say CRC64NVME is full-object only, so with CRC-64/NVME as the only algorithm the disagreement no longer reaches us. `OperationAborted` says "Try again" but sits in neither retry list; at Complete it maps to `Ambiguous`, which asks for the receipt and is safe either way.

### The adapter's registers

The Permitted register has one entry, and each entry is one constructor of `S3.Why` next to `CoreWhy`, which wraps the core's `Why`.

| # | Statements | Side | Why |
|---|---|---|---|
| SPM1 | `PD:S3API-AbortMultipartUpload-API_AbortMultipartUpload-2` | took: after AbortMultipartUpload we call ListParts and treat a non-empty list as parts still staged | The statement is graded definition but is advice ("you should call"), and following it is how this adapter meets store contract clause 5, a part upload that lands after the abort. |

The Chosen register holds readings of S3 that no vendored statement settles. Each is one constructor of `S3.Rationale`.

| # | Choice | Rationale |
|---|---|---|
| SCH1 | A 412 on CompleteMultipartUpload is `Ambiguous`, not success. | RFC 9110 gives If-None-Match no "already succeeded" exception, and asking for the receipt costs one call. |
| SCH2 | InvalidRequest at Complete is `Refused LengthDiffers`. | The only vendored cause is the MpuObjectSize mismatch, and the answer is final either way. |
| SCH3 | ChecksumCRC64NVME values in response headers are big-endian, as S3 states for trailer chunks. | It is the only order S3 states anywhere; S11 pins the decoder to it. |
| SCH4 | SlowDown is `Ambiguous` and keeps its delay. | Its description doesn't say whether the call was processed. |
| SCH5 | `Remove` is DeleteObject, and its 204 is `RemoveR (Done ())`. | No DeleteObject text is vendored yet; item 5 under "Before we write code". |
| SCH6 | An UploadPart BadDigest is `Ambiguous`, so the chunk is resent at the same offset. | S3's BadDigest is not the HTTP digest-mismatched-values problem type, and a part damaged in transit is the likely cause. |
| SCH7 | `sealsEmpty` is false, so a zero-length file is refused with 501. | Zero-part completion isn't vendored; item 5 under "Before we write code". |
| SCH8 | ServiceUnavailable means S3 didn't process the call, so it is `Unavailable`. | "Unable to handle request" is the closest S3 comes to saying so. |
| SCH9 | A HeadObject 200 without a usable CRC64NVME checksum is `Unvouchable`. | An object's checksum is fixed when the object is created, so asking again can't add one. |
| SCH10 | Every failure the SDK would class as transient or throttling, and every timeout or lost connection, is `Ambiguous`, except ServiceUnavailable (SCH8). | The SDK only says it retries these; whether S3 processed the call is unknown, and `Ambiguous` costs the core at most one ask. |
| SCH11 | Every other 4xx is `Refused Inconsistent`, which the store contract makes deterministic. | The SDK returns these to the caller at once; the same call in the same state would be refused the same way, and a file can't become available through a refusal. |

## Before we write code

These are gaps in the vendored sources that we can close ourselves before the first module. None needs the product owner.

1. Generate `basis-core.json` and `basis-s3.json` from this document's citations and registers, split by package, and teach `check-cites` the level rule and the list of definition-graded statements that are phrased as options.
2. Vendor RFC 9651's Integer, Boolean and Dictionary serialisation for the Upload-* fields.
3. Extract the RFC 9110 8.8.2.2 strong-date rules; until then a date If-Range is always false.
4. Regenerate the 42 statement ids that carry different quotes in different groups, or keep keying every tool on (group, id).
5. For the adapter: vendor the S3 text on DeleteObject (SCH5), on zero-part completion (SCH7), on the maximum part size and on the "5 MB" unit.
6. For the adapter: settle S3's byte order for ChecksumCRC64NVME in response headers (SCH3), with a vendored statement or a test against a real bucket in the shell. S11 already pins our decoder to big-endian.
7. Write `check-vendor`'s deny-list generator from the adapter's `S3Call` constructors, and the `gen-vocab` check that fails when a deny-list entry matches an identifier the core generates from a non-vendor source.
8. Teach `check-cites` to list every `data` and `newtype` declaration in both packages and fail on one with no provenance instance (V14).

## The Permitted register

Each entry names the SHOULD, MAY or open option, the side we took, and why. `gen-vocab` turns each entry into one constructor of the core's `Why`, so a `Permitted` basis can only point at a side recorded here. PM25 and PM28 were retired in this revision with the rows that used them (the digest-mismatched-values answer and the "already applied" DELETE), and PM37 moved to the adapter as SCH6.

| # | Statements | Side | Why |
|---|---|---|---|
| PM1 | `HS:RFC9110-15.5.4-4` | declined: a forbidden resource is never hidden behind 404 | AIP-193 requires 403 before any existence check on the Operations surface (`SS:AIP193-PermissionDenied-1`), and one rule for every surface is simpler and leaks nothing extra. |
| PM2 | `HS:RFC9110-11.4-1`, `HS:RFC9110-11.4-2` | took: 401 for missing or invalid credentials, 403 for inadequate ones | These are the answers RFC 9110 expects, and DRS lists both (`DO:DRS-responses.401Unauthorized-1`, `DO:DRS-responses.403Forbidden-1`). |
| PM3 | `HS:RFC9110-9.2.2-4`, `SS:GRFC-A6-Retryable-1` | took: a non-idempotent request is re-sent only after detecting it was never applied, and only "did not process" failures are retried directly | The seal is the one non-idempotent store call, and asking for the receipt is our means of detecting that it never applied. |
| PM4 | `HS:RFC9110-9.2.2-8` | took: at most one automatic retry after a connection failure | A retry that fails again goes to the attempt counter, not to another automatic retry. |
| PM5 | `HS:RFC9110-15.5.20-2`, `HS:RFC8470-5.2-2`, `HS:RFC9110-15.5.9-2` | took: retry 421 on a new connection for any method, retry 425, repeat after 408 | Each is safe by its own definition and urllib3 doesn't model them. |
| PM6 | `HS:RFC9110-15.6.4-2`, `HS:RFC6585-4-2` | took: Retry-After on 503 when the store gave a delay, and on 429 | A client that waits the right time costs us less than one that guesses. |
| PM7 | `HS:RFC9110-10.2.3-4` | took the delay-seconds form only | DRS requires integral seconds on its 202 (`DO:DRS-responses.202Accepted.Retry-After-1`), and the core has no clock to format an HTTP-date. |
| PM8 | `UP:RESUMABLE-UPLOAD-13-4.6-4`, `UP:RESUMABLE-UPLOAD-13-4.6-5` | took: a new request terminates the previous one by closing its connection | The draft recommends it; during a chunk write we still terminate the old request's reply but defer the new request until the write reports (CH30). |
| PM9 | `UP:RESUMABLE-UPLOAD-13-4.4.2-2`, `UP:RESUMABLE-UPLOAD-13-4.2.2-11` | declined: nothing of an interrupted append is kept | A durable chunk is all-or-nothing (CH28), and RFC 5789's atomicity (`HS:RFC5789-2-2`) agrees with keeping nothing. |
| PM10 | `UP:RESUMABLE-UPLOAD-13-4.4.2-8`, `UP:RESUMABLE-UPLOAD-13-4.2.2-7` | declined: no 104 interim responses | 104 is a TEMPORARY registration (`HS:IANA-HTTP-Status-Codes-104`), and creating with empty content gives the client the upload URI without it. |
| PM11 | `UP:RESUMABLE-UPLOAD-13-4.4.2-4` | took: the completing request gets the targeted resource's response | Bounded by `replyWait`, after which it gets 202 and the operation (CH22). |
| PM12 | `UP:RESUMABLE-UPLOAD-13-13-6`, `UP:RESUMABLE-UPLOAD-13-13-7` | took: access and quota are re-checked before sealing | The completing event already carries the access verdict and `quotaRemaining`, so it costs nothing. |
| PM13 | `UP:RESUMABLE-UPLOAD-13-13-8` | took: a per-owner cap on files in CREATING, max-age and deadlines | These are the Slowloris mitigations the draft lists that a pure core can enforce. |
| PM14 | `UP:RESUMABLE-UPLOAD-13-4-3`, `UP:RESUMABLE-UPLOAD-13-4.4.2-6` | took: completed upload resources are kept for `uploadRetention`, and the final response is replayed to a valid re-completion | A client that lost the final reply can find out what happened. |
| PM15 | `UP:RESUMABLE-UPLOAD-13-4.5.2-1` | took: DELETE deactivates the upload resource | The draft recommends it, and on an ACTIVE file it leaves the file alone. |
| PM16 | `UP:RESUMABLE-UPLOAD-13-4.1.4-3`, `UP:RESUMABLE-UPLOAD-13-4.1.4-5`, `UP:RESUMABLE-UPLOAD-13-4.1.4-6` | took: requests above max-size or outside the append sizes are rejected, and the offset is never allowed past max-size even when the length is unknown | min-append-size = max-append-size = chunkSize (CH28), and max-size is bounded by the store profile; keeping the offset under max-size is what bounds the chunk count. |
| PM17 | `UP:RESUMABLE-UPLOAD-13-4.1.4-8`, `UP:RESUMABLE-UPLOAD-13-4.1.4-9`, `UP:RESUMABLE-UPLOAD-13-4.1.4-10`, `UP:RESUMABLE-UPLOAD-13-4.1.4-11` | took: limits never change | The plan is fixed at creation, and V12 proves it. |
| PM18 | `UP:RESUMABLE-UPLOAD-13-4.1.4-17` | took: limit refusals carry Upload-Limit | The client needs the limits to resume (`UP:RESUMABLE-UPLOAD-13-4.7-3`). |
| PM19 | `UP:RESUMABLE-UPLOAD-13-4.3.2-1` | took: offset responses carry Cache-Control: no-store | A cached offset would be outdated information. |
| PM20 | `UP:RESUMABLE-UPLOAD-13-4-4`, `UP:RESUMABLE-UPLOAD-13-13-1` | took: upload URIs are unique and unguessable | The shell supplies ids that are never reused. |
| PM21 | `UP:RESUMABLE-UPLOAD-13-4.1.2-6`, `HS:RFC5789-2.2-2` | took: an append to a completed upload that no MUST covers gets 409 with UC ?0 and no Upload-Offset | A client following the draft retrieves the offset first, sees UC ?1 and stops (PM43), and UC ?0 doesn't claim the targeted resource's semantics. |
| PM22 | `HS:RFC5789-2.2-1`, `HS:RFC5789-3.1-1` | took: 415 with Accept-Patch for a wrong media type, and Accept-Patch in OPTIONS on the upload resource | It tells the client the one media type that works. |
| PM23 | `UP:RESUMABLE-UPLOAD-13-7.1-1`, `UP:RESUMABLE-UPLOAD-13-7.1-2`, `UP:RESUMABLE-UPLOAD-13-7.2-1` | declined by default: the draft's two problem types sit behind `draftProblemTypes = False` | They are IANA requests, not registrations, and the brief forbids unregistered vocabulary (CH4); open question 2. |
| PM24 | `PD:DIGEST-PROBLEMS-3.1-1`, `PD:RFC9530-2-2` | took the problem type and declined the MAY to ignore: a client digest we can't forward is refused with digest-unsupported-algorithms | Ignoring it would let a client believe a check happened; open question 1. |
| PM26 | `DO:DRS-schemas.Checksum.type-1`, `DO:DRS-schemas.Checksum.type-2` | took the "Other values MAY be used" side, and declined both SHOULDs: the type is `crc64nvme` | The brief requires CRC-64/NVME (CH2); the Named Information registry has no CRC entry and DRS's suggested list stops at `crc32c`. |
| PM27 | `HS:RFC9110-14.2-1`, `HS:RFC9110-14.2-4`, `HS:RFC9110-14.2-5` | took: several ranges are served as if Range were absent, an invalid range is ignored, and Range is ignored on a zero-length file | Keeps multipart/byteranges out of the core and avoids a zero-byte 206. |
| PM29 | `HS:RFC9110-9.3.5-3` | took: 202 while a delete or cancel is pending, 204 once enacted | These are the codes RFC 9110 recommends for each case. |
| PM30 | `HS:RFC9110-15.5.11-3` | took: the 410 mark is kept for `tombstoneHorizon`, then the id answers 404 | Tombstones can't grow forever. |
| PM31 | `HS:RFC9110-14.4-6`, `HS:RFC9110-15.5.17-2` | took: 416 carries `Content-Range: bytes */n` | The client learns the length in one round trip. |
| PM32 | `SS:AIP151-Guidance-1`, `SS:LRO-Operation-response` | took: imports return an Operation, and its response is the resource, as a DRS object | Imports take long; the DRS object is the only vendored representation of the resource. |
| PM33 | `SS:AIP151-Expiration-1` | took: finished operations expire after `opRetention` | Operations can't grow forever. |
| PM34 | `SS:AIP216-Default`, `SS:AIP216-OutputOnly-1`, `SS:AIP216-OutputOnly-2` | took: no unspecified state, and the state is output only | Nothing in this drive lets a client set a state. |
| PM35 | `PD:RFC9457-4.2.1-2` | took: an about:blank problem's title is the status phrase | It needs no vocabulary of ours. |
| PM36 | `DO:DRS-responses.202Accepted-1` | took: DRS GetObject on a CREATING file answers 202 with Retry-After | DRS defines 202 for exactly "delayed". |
| PM38 | `HS:RFC9110-15-6` | took: a received invalid status is processed as 5xx | It is the client SHOULD, and `fromWire` gives it one place. |
| PM39 | `UP:RESUMABLE-UPLOAD-13-4.2.2-10` | took: no 301, 302 or 303 on the upload surface | The core produces no redirects at all. |
| PM40 | `UP:RESUMABLE-UPLOAD-13-4.1.4-7` | took: a transfer still receiving when its max-age runs out fails `Expired` | The definition lets the server make the resource inaccessible then, and an abandoned upload has to end somewhere. |
| PM41 | `HS:RFC9110-15.5.5-2` | took: 410 rather than 404 while a terminal or deleted record is kept | We know the condition is permanent, which is when RFC 9110 prefers 410. |
| PM42 | `SS:AIP194-Retryable-UNAVAILABLE`, `SS:AIP194-NonRetryable-0`, `SS:AIP194-GenerallyNonRetryable-0` and every AIP-194 listing statement | took: we design for a client that follows AIP-194, generate `Recourse` from its three sections, and pick each Fault's Code so that such a client does what we mean | It is the only vendored retry guidance for google.rpc codes, and it binds clients, not us. |
| PM43 | `UP:RESUMABLE-UPLOAD-13-4.1.2-5`, `UP:RESUMABLE-UPLOAD-13-4.7-2`, `UP:RESUMABLE-UPLOAD-13-4.7-3`, `UP:RESUMABLE-UPLOAD-13-4.7-5`, `UP:RESUMABLE-UPLOAD-13-4.4.1-6` | took: we design the upload refusals for a client that follows the draft's client rules and heuristics | Those rules are SHOULDs and informative options for clients, so they can only be an assumption of ours. |
| PM44 | `UP:RESUMABLE-UPLOAD-13-4.2.3-2` | took: a creation request whose own content is refused, or fails, after the upload resource exists is answered with UC ?1, and the file ends | The draft's own example answers a refused creation this way, and the client never learned the upload resource, so nothing could resume it (CH45). |
| PM45 | `HS:RFC9110-15.3.3-3` | took: a 202 with a status monitor embeds the operation in its body | Location is defined only for 201 and 3xx (`HS:RFC9110-10.2.2-1`), so the body is the only place RFC 9110 suggests for the monitor. |

## The Chosen register

These are the choices no vendored statement makes. Each is one constructor of the core's `Rationale`. The product owner should read the first group; the second group is engineering and needs no decision. CH34 was retired in the previous revision: its S3 readings moved to the adapter's register as SCH1 to SCH3.

### Product choices, for the product owner

| # | Choice | Rationale |
|---|---|---|
| CH1 | (brief) A file is available only when the store vouches for it with a full-object checksum receipt; a write acknowledgement is never proof. | It is the brief's definition of available. |
| CH2 | (brief) The receipt algorithm is CRC-64/NVME, and `ReceiptAlgorithm` has no other constructor. | The brief requires it; the cost is that neither DRS nor the digest registry names it (PM26, CH19). |
| CH3 | (brief) The core never computes a digest: no event carries representation bytes, and no function turns bytes into a receipt or DRS checksum. | The store is the only party whose checksum counts. |
| CH4 | (brief) Every state, status, reason and recourse a client can see comes from a vendored standard, and every closed type carries its basis. The two exceptions are the ErrorInfo reason (CH21) and the `@type` URL of an Operation's response (CH44). | The brief's no-invented-vocabulary rule. |
| CH5 | (brief) The whole state steps through one total `step`, with every per-file rule in one `stepFile`, and every instant the core acts on is backed by a requested Tick for that file. | The brief asks for one transition function, and a deadline nobody wakes up for isn't one. |
| CH35 | (brief) The drive handles browser uploads, URL imports and downloads. | The brief's scope. |
| CH6 | The store contract: (1) `Vouched` only for a full-object checksum in the receipt algorithm at full width, with the sealed file's size; (2) seal is create-only; (3) `Unavailable` means not processed; (4) `NothingThere` is authoritative, `Refused` and `Unvouchable` are deterministic, and `NotYetVouched` is only for an answer that can still change; (5) a chunk write can land after `Discard`; (6) the store expires staging areas nobody seals or discards and never touches a sealed file; (7) the core writes fixed-size chunks numbered 1..k, one at a time, each naming its staging area, at most `maxChunks`, seals with the chunks' total as the expected length, and seals zero chunks only when the profile allows it; (8) staging references and chunk tokens are opaque. | It is the least a store must promise for the brief's rule and our retries to hold, stated without any one store's limits. |
| CH7 | At seal and at ask, a deterministic answer ends the file at once in its named Fault; `Ambiguous`, `Unavailable`, `NotYetVouched` and `StagingGone` at seal lead to asking for the receipt; the seal is re-sent only after the store says nothing is there. | An answer that would repeat identically shouldn't burn attempts, and an ambiguous seal must never be repeated blindly. |
| CH8 | `NotYetVouched` is asked again with backoff while attempts and `finalizeBudget` last; `Unvouchable` fails the file at once; either way the file ends `ObjectWithoutReceipt` (or `FinalizeTimedOut`) and the object is removed. | "Not yet" deserves a bounded wait, and "never" deserves none. |
| CH9 | A cancel while sealing waits for the store, and a receipt still makes the file ACTIVE. | A file the store vouched for is the better outcome than a cancel that can't be guaranteed anyway. |
| CH10 | FAILED, CANCELLED and DELETED absorb every client event; we offer no action that moves a file out of them, and only their own cleanup and timers act inside them. | AIP-216 allows such actions but doesn't require them, and offering none keeps every terminal file final. |
| CH11 | DELETE on a file still being created is refused with 409. | Cancellation has its own verbs, and a delete racing a seal has no good answer. |
| CH12 | Our resources are not WebDAV resources; RFC 4918 reaches us only through the 507 status code it registers. | We serve no collections, properties or locks, so applying some WebDAV MUSTs and not others would be arbitrary. |
| CH13 | Files live in folders, and creating a file whose parent folder is missing is refused with 409. | Folders are our product model, and 409 is RFC 9110's status for a conflict the user can resolve. |
| CH14 | Quota is checked at creation and again at finalize, and exceeding it answers 507. | 507 is the registered status for "unable to store the representation"; open question 7. |
| CH15 | A zero-length file is refused with 501, or an empty import fails `Empty`, exactly when the store profile says the store can't seal an empty file. | Whether an empty file can exist is the store's limit, so the core reads it from the profile; open question 12. |
| CH16 | An import whose origin refused it fails with UNKNOWN, carrying the origin's status. | The origin's status comes from another error space, and the gRPC HTTP mapping is for gRPC clients. |
| CH17 | An import whose source changed fails with ABORTED; it never restarts from zero. | Restarting would decrease the offset, which the draft forbids for uploads and we keep for imports too. |
| CH18 | An import body ended by connection close counts as an interruption. | The store would otherwise vouch for a truncated file; open question 6. |
| CH19 | Downloads never carry Repr-Digest. | The digest registry has no key for CRC-64/NVME, and the brief forbids coining one. |
| CH20 | Retry-After appears only on 202, 429 and 503; in particular 507 never carries it. | RFC 4918 forbids repeating a user's request after 507 without a new user action, and a delay hint would read as an invitation to do that. |
| CH21 | An Operation carries no `metadata`. Its error's ErrorInfo reason is the Fault's name in upper case and its domain is the service name, which is an exception to CH4. | No vendored statement names progress fields, and AIP-193 requires a distinct reason per logically different error without naming any; open question 11. |
| CH22 | The reply to a completing request is held up to `replyWait`, then answered 202 with the operation, and every row that ends the file answers or abandons it. | Held requests must stay finite. |
| CH23 | A chunk write the store refuses for any reason but `StagingGone` leaves the upload Idle with an alert. | An operator can fix the store, and the client can then resume. |
| CH24 | When the store refuses us, operators get an alert and clients see 500 or INTERNAL, never 401 or 403. | The client's credentials were fine; ours weren't. |
| CH36 | Each Fault's google.rpc.Code is our mapping onto the code whose definition fits it, and no Fault carries CANCELLED. | code.proto defines the codes but doesn't say which of our failures gets which. |
| CH37 | When `finalizeBudget` runs out, the file fails `FinalizeTimedOut` (DEADLINE_EXCEEDED), whatever the last store answer was. | One cause should end in one named status. |
| CH38 | After DeleteOperation, the operation's methods answer 404. | DeleteOperation only says the client is no longer interested; 404 is the simplest way to honour that. |
| CH40 | Every 4xx and 5xx response except one to HEAD carries a problem details object. | One error shape for every client, at no cost in vocabulary. |
| CH41 | A Remove the store refused, or that ran out of attempts, leaves the file DELETING with an alert, and a repeated DELETE starts a fresh Remove; DELETED is reached only after the store answered the Remove. | The file can't be DELETED until the store has answered, and the 202 a repeated DELETE gets is then true. |
| CH44 | An Operation's `response` carries the DRS object under the coined `@type` URL `type.googleapis.com/ga4gh.drs.v1.DrsObject`, which is an exception to CH4. | `response` is a `google.protobuf.Any`, DRS has no message type and no vendored statement names one, and without a response an import's client couldn't learn which file it made; open question 13. |
| CH45 | A creation request's length checks run before anything is created, and a creation request whose content fails once the upload exists ends the file with UC ?1 (`CreationRefused` or `CreationInterrupted`). | Its client learns the upload resource only from the 201, so a file left behind would be unreachable until max-age. |

### Engineering choices

| # | Choice | Rationale |
|---|---|---|
| CH25 | Two pure packages, `funknown-core` naming no vendor and `funknown-store-s3` depending on it; the core may not import the adapter, and each has its own generated citations and registers. | The core's proofs stay about standards, and a second store means a second adapter, not a new core. |
| CH26 | Haskell2010, every module Safe, dependencies limited to base, containers and liquidhaskell, with generators in `funknown-tools`. | GHC2021 drags in GeneralizedNewtypeDeriving, which Safe refuses, and the tools may need JSON and XML parsers. |
| CH27 | The verified unit is `stepFile`; optional values use `Opt`, `Len` and `Lookup`; status classes are reflected tables; refined records carry the bounds their refinements name. | These are the shapes the spikes proved. |
| CH28 | Every 2xx append is one durable chunk, so chunk k always covers the same byte range, and chunks are numbered 1..k with one write in flight; the core announces min-append-size = max-append-size = the profile's chunk size. This is the core's choice for every store, and only the number comes from the adapter. | A late duplicate write then carries the same bytes whether a store keys writes by number, by offset or appends them, the offset is a function of the chunk count, and the mover never buffers more than one chunk. The cost is that clients must send appends of exactly that size, which with S3 is at least 5 MiB (open question 14). |
| CH29 | Every file has one async slot and one fencing epoch, bumped for every new job, and a report from a superseded epoch changes nothing. | It is how the core meets the draft's MUST to prevent races. |
| CH30 | While a chunk write is in flight, a new Append or OffsetQuery is deferred until the write reports, and a cancel ends the file at once. | Two writes then never race on one chunk number, and a cancel doesn't have to wait for one. |
| CH31 | Retries follow gRFC A6 (attempt counter, deadline, token bucket for the store, backoff with exact pushback) though neither the store nor the origins speak gRPC; a throttled retry counts as no attempts left; origin statuses go through a port of urllib3's rule; and an import fetch counts as the result of the user's StartImport, so RFC 4918's no-repeat rule for 507 applies to it. A server delay is used once and resets the backoff step; gRFC A6's negative-pushback rule isn't modelled, because nothing we talk to sends its `grpc-retry-pushback-ms` metadata, and a past Retry-After date means retry now. | One retry model for everything, from the most precise vendored source. |
| CH32 | A file's ETag is derived from its never-reused file id. | Content never changes per id, and no store validator needs to leak through. |
| CH33 | Errors come from two tables, `Refusal` and `Fault`; a `Refusal` carries no google.rpc.Code, and a `Problem` has no status field. | Every status, problem type and Operation code is then derived from one place. |
| CH39 | Browser uploads and URL imports share one `Upload` record and one `appendChunk`. | An import is an upload the server feeds, so one set of invariants covers both. |
| CH42 | A store report under the current epoch whose command isn't the one the slot is calling is handled as `Ambiguous` for that call, with an alert. | Only a shell that broke its contract can send one, and treating it as unknown never makes a file available and never strands a slot. |
| CH43 | An append without Upload-Offset is refused with 400. | The draft's MUST is on the client and names no server answer; 400 is RFC 9110's status for a perceived client error. |

## Open questions for the product owner

1. **Client digests.** No registered Repr-Digest key names CRC-64/NVME, so today no client digest can be forwarded to the store, and every client that sends an integrity field gets digest-unsupported-algorithms (PM24). The alternatives are to accept an unregistered `crc64nvme` key from clients, which coins input vocabulary, or to ignore client digests, which RFC 9530 allows but which lets a client believe a check happened.
2. **Draft vocabulary.** Upload-Offset, Upload-Complete, Upload-Length and Upload-Limit exist only in draft-ietf-httpbis-resumable-upload-13, and there is no registered alternative. Its two problem types are IANA requests, not registrations, so they are off by default and those responses carry about:blank. Do we accept the draft's fields, and do we turn the problem types on?
3. **Largest file.** max-size is at most maxChunks x chunkSize. With the S3 adapter that is 10000 x P, so P = 5 MiB gives about 50 GB; a larger P raises that, once S3's maximum part size is vendored.
4. **Retention.** How long we keep completed upload resources (so a client that lost the final reply can recover), tombstones, finished operations, the upload max-age, and the import deadline.
5. **Retry budget and patience.** maxAttempts in 2..5, `replyWait` before a completing request gets 202, and `finalizeBudget`.
6. **Close-delimited imports.** We treat a body ended by connection close as an interruption (CH18), because the store would otherwise vouch for a truncated file. RFC 9110 calls such a body complete (`HS:RFC9110-6.1-3`), so some origins become impossible to import. Is that acceptable?
7. **Quota exceeded at finalize.** 507 is tentative (CH14). The 5xx class says the server erred or can't perform the method (`HS:RFC9110-15.6-1`), which reads oddly for a user's quota; 403 and 429 are the alternatives.
8. **A 500 from an import source** is not retried (urllib3's rule in the core), while with the S3 adapter a store 500 is classified transient and handed to the core as `Ambiguous` (SCH10), which is followed by an ask and possibly a re-seal. The second half is the adapter's choice, not the core's. Is that double standard what we want?
9. **Per-owner concurrency cap** for uploads in CREATING, which the draft recommends against Slowloris (PM13).
10. **Import progress.** With Operation metadata gone (CH21), an import shows no progress until it is done, and DRS only says 202. Is that acceptable, or do we want a progress field badly enough to coin one?
11. **ErrorInfo reasons.** AIP-193 makes every error carry a reason that differs for logically different errors, and names none, so the reasons (`SIZE_MISMATCH`, `FINALIZE_TIMED_OUT` and the rest) are one of the two places a client sees vocabulary we coined (CH21; the other is question 13). Do we accept that exception to the brief, or would we rather collapse Faults that share a Code and accept that some clients can't tell, say, a file that is too large from a quota that is full?
12. **Empty files.** With the S3 adapter, `sealsEmpty` is false until S3's zero-part completion is vendored, so a zero-length upload gets 501 and a zero-length import fails `Empty` (CH15, SCH7). Is that acceptable for now?
13. **The Operation's `@type`.** An Operation's `response` is a `google.protobuf.Any`, which needs a type URL, and DRS has no message type to name, so the shell writes `type.googleapis.com/ga4gh.drs.v1.DrsObject`, which we coined (CH44). The alternative is to leave `response` unset, which google.longrunning allows, and an import's client then can't learn from the operation which file it made. Do we accept the coined URL?
14. **Exact append size.** The core asks every client for appends of exactly the chunk size (CH28), and with the S3 adapter that is at least 5 MiB, so a browser client has to send 5 MiB PATCHes, except the last one. The alternative is to let clients append any size and have the mover gather appends into store chunks, but then a 2xx append could no longer mean the bytes are durable, or the offset a client is told would have to lag behind what it sent. Is the fixed size acceptable?
15. **The Chosen register.** CH1 to CH24, CH35 to CH38, CH40, CH41, CH44 and CH45 are product choices no standard made for us; each is worth a yes or a no.

## Review notes

### Second verification pass

I checked all 38 findings against the document and the vendored statements, and every one of them was right, so none of the text was left standing. These are the places where the fix differs from what the finding suggested:

- Fixed part size (finding 3). The lead's decision moved "fixed part size" to the adapter. The adapter now picks the number, and S3's minimum, maximum and part cap live only there, but the rule that every append is exactly one chunk stays in the core as CH28, because its benefit doesn't depend on S3: a late duplicate write always carries the same bytes, and the offset stays a function of the chunk count. Decoupling client appends from store chunks would have meant a 2xx for bytes that aren't durable yet, which breaks the brief's rule that the offset never exceeds what the store acknowledged. The client-visible cost with S3 is open question 14.
- The deny-list (finding 1). Instead of subtracting core identifiers from a generated list, `gen-vocab` fails when a deny-list entry matches anything the core generates from a non-vendor source. A subtraction rule would have let a vendor word into the core whenever a registry happened to spell it the same way; a failing check makes us pick a spelling that really is vendor-only.
- The Operation's `@type` (finding 6). I kept `response` and recorded the coined type URL as CH44, rather than dropping `response`, because without it an import's client has no way to learn which file the import created.
- Reachability (finding 16). I did both things the finding offered: each phase carries its own slot type, and the facts that a type can't carry (a finishing phase has a complete upload, a slot fits the source) are data refinements.
- The backoff step (finding 20). I kept "a past date means retry now" and stopped modelling gRFC A6's negative-pushback rule. That rule is about a gRPC metadata key nothing we talk to sends, so no input in our types can trigger it, and dropping it loosens nothing we adopted.
- Re-entrant rows (finding 22). B1 and G2 call the Idle and failure handlers directly, and O2 issues its own `StartAppend`, so no termination measure is needed; V15 is marked pattern on the strength of RedispatchM, which went through even with the re-entrant form.
- The creation request (finding 29). Instead of listing which A-rows apply after the Open, I moved the length checks to creation (C6a), where a refusal still creates nothing, and made B16 end the file when the content fails later, following the draft's own example of a refused creation (PM44).
- Late Open answers (findings 30 and 37). I took the finding's second option, keeping the Open's epoch current, and applied it to cancels as well, so X1 and O6 both end the file at once and wait for the Open in K0. The `cancelRequested` flag is no longer used in Opening at all, which is what removed the old cancel row's unenforced "only an import can reach it" guard.
- Cancel while sealing (finding 33). F9 closes the upload resource for a CancelOperation too, not only for a CancelUpload. That part is our choice (CH9): once a cancel is accepted, no later append should be able to reopen the held-request path.
- SDK classification (finding 11). The SDK statements stay in the adapter's prose as evidence for SCH10 and SCH11; they are no longer anyone's Required basis.

### First verification pass

Most findings from the first verification pass were right and are fixed in place above. These are the places where I didn't take a finding's suggestion as written, or where the suggestion would have broken a rule we hold:

- The provenance fix (finding 1) uses one `Basis c w r` type with a class per package, not one class with associated types, because neither associated types nor multi-parameter classes are in Haskell2010.
- For the AIP-194 sections (finding 9), I didn't keep R on "which section lists a name". Every listing statement is graded SHOULD, or MUST addressed to clients, so a Required basis would fail the level rule; the whole of `Recourse` is P PM42 instead, and the section list is still generated from the vendored file.
- For `AlreadyComplete` (finding 10), I didn't record a Chosen deviation from the definition of UC ?1, because that would loosen a Required rule, and I didn't replay the F1 201 for every append, because the draft only allows a replay for a valid request (`UP:RESUMABLE-UPLOAD-13-4.4.2-6`). The 409 with UC ?0 and no Upload-Offset gets a following client to stop without either. Applying the MUSTs in order before it also meant honouring `UP:RESUMABLE-UPLOAD-13-4.4.2-7` on a completed upload, which is where `uploadOpen` came from.
- For ErrorInfo reasons (finding 12), I didn't derive the reason from the Code, because `TooLarge` and `QuotaAtFinalize` share RESOURCE_EXHAUSTED but call for different client actions, and AIP-193 then requires different reasons. The exception is recorded instead (CH21, open question 11).
- "A failure is never OK" (finding 13 (e)) turned out to have a Required ground after all: code.proto defines OK as "Not an error; returned on success" (`SS:GRPC-STATUSCODES-OK`). Only "never CANCELLED" is ours.
- The byte-order check (finding 18) went in as S11, but a fixed vector can only pin our decoder. S3's own byte order in response headers is still SCH3 until a vendored statement or a real-bucket test settles it.
- The HeadObject citations (finding 15 (3)) are grounded rather than reclassified: the vendored HeadObject page does say it returns the CRC64NVME checksum, its type and the length, so I added those four statements to the problems-and-digests group.
