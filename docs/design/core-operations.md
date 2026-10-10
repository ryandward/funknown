# funknown-core: an operations-first design

Status: design only, no Haskell source yet. Written 2026-10-09 against the five vendored reference groups under `references/`. The `experiments/` tree belongs to an abandoned premise and is ignored on purpose.

We have five folders of vendored standards and reference code, and no core yet. We want a pure Haskell core for a B2B drive that moves files in (browser uploads and URL imports) and out (downloads), and this document designs it from the point of view of what goes wrong over time: movers that die halfway through a transfer, reports that arrive from an attempt we already replaced, retries that nobody bounded, a cancel that races a completion, uploads that expire, a store that refuses us while the person is perfectly entitled, and a store that answers 200 without actually vouching for anything. What forces the shape is the pair of rules in the brief. Every state, status, reason and recourse has to be one a standard already defines, and a file only becomes available when the store vouches for it with a full-object digest. If those two rules are going to hold while all of the above is happening at once, it looks to me like they have to live in the types and in one transition function whose every row is checked by LiquidHaskell or by exhaustion, because a test can only sample a race.

The document goes in this order: how citations are written, the risks the design is built around, the package and its modules, the vocabulary types with the statements each constructor comes from, the two reason tables (why a request is refused, why a transfer ended), the per-file state machine and its transition table, what a client is told, which reference code we port and what we fix on the way, the theorem catalog, and the questions the sources leave open.

## How a citation is written here

Every claim cites a statement id from a `statements.json`, prefixed with its group, because the ids are not unique across groups. Sixty-eight ids appear in more than one group and forty-two of those carry different quotes (for example `RFC9110-15-5` is the "Values outside the range 100..599 are invalid" definition in http-semantics but the 5xx SHOULD in problems-and-digests). A citation only means something as a (group, id) pair. This is the same convention as `docs/design/core-protocol.md`, so the two designs can be merged without re-resolving anything.

- `HS:` references/http-semantics/statements.json
- `PD:` references/problems-and-digests/statements.json
- `UP:` references/uploads/statements.json
- `DO:` references/drive-and-objects/statements.json
- `SS:` references/status-and-supervision/statements.json

Reference code that has no statement id (Funnel, the Go net/http sources, urllib3, OTP function bodies beyond the quoted ones) is cited by path and line range under `references/`.

## The risks, in the order we check them

We check blind spots in a fixed order: data corruption, resource exhaustion, concurrency failures, silent failures, and finally developer experience. Each paragraph below says what could go wrong, which mechanism in the design stops it, and which theorem in the catalog proves that the mechanism holds.

**Data corruption.** The worst outcome would be a file that is reported ACTIVE while its bytes differ from what the person sent, or an upload offset that tells a client to skip bytes we never stored. I'd like the offset we report to be exactly the sum of the parts the store has acknowledged, and nothing else ("Representation data processed by the upload resource cannot be removed again and, therefore, the offset as seen by the client MUST NOT decrease", `UP:RESUMABLE-UPLOAD-13-4.1.1-7`; "the server MUST NOT send outdated information in responses", `UP:RESUMABLE-UPLOAD-13-4.6-3`). To get there, I pinned every upload to one fixed part size `P`, and I announce it through Upload-Limit as both `min-append-size` and `max-append-size`. Every non-final append is then exactly one store part, so a 2xx append response always means the whole append is durable, which is what `UP:RESUMABLE-UPLOAD-13-4.1.1-6` requires. A second consequence is that a stale mover which overwrites part `n` late writes the same byte range of the same representation, because part numbers and byte ranges never move. An import resumes at a nonzero offset only when the origin gave us a strong validator and we send it back in If-Range ("These ranges can only be safely combined if they all have in common the same strong validator", `HS:RFC9110-15.3.7.3-1`). Finally, ACTIVE is a constructor that cannot be built without a parsed full-object receipt whose size equals the recorded length (T12, T13, T18, T20, T37).

**Resource exhaustion.** Every abandoned multipart upload costs storage until someone aborts it ("Amazon S3 frees up the space used to store the parts and stops charging you for storing them only after you either complete or abort a multipart upload", `PD:S3API-CreateMultipartUpload-API_CreateMultipartUpload-2`), and an abort can leave parts behind when a part upload was still in flight ("it might be necessary to abort a given multipart upload multiple times", `PD:S3API-AbortMultipartUpload-API_AbortMultipartUpload-1`). So failed and cancelled files carry a cleanup obligation that ends only when ListParts comes back empty (`PD:S3API-AbortMultipartUpload-API_AbortMultipartUpload-2`). Retries are bounded three ways: per file by the OTP restart intensity (`SS:OTP-SUPERVISOR-Intensity`), per store by the gRFC A6 token bucket (`SS:GRFC-A6-Throttling-1`, `SS:GRFC-A6-Throttling-2`), and in total by a deadline that every transfer carries. The number of concurrent uploads per owner is capped, as the draft recommends against Slowloris (`UP:RESUMABLE-UPLOAD-13-13-8`). Tombstones and finished operations expire (`SS:AIP151-Expiration-1`) (T20, T33, T35, T36).

**Concurrency failures.** A client can believe a request failed while the server still considers it alive ("network interruptions can occur in such a way that the client considers a request as failed while the server is unaware of the problem", `UP:RESUMABLE-UPLOAD-13-4.6-2`), and an import mover can be presumed dead while it is still writing. Every file has exactly one slot for outstanding asynchronous work and one fencing epoch. Every report from a mover or the store carries the epoch it was started under, and a report whose epoch is not current changes nothing. This is the "sequencer check failure" that `SS:GRPC-STATUSCODES-ABORTED` names. A new append, an offset query or a cancel terminates the previous append before it is processed, as the draft recommends (`UP:RESUMABLE-UPLOAD-13-4.6-4`). A cancel that arrives while the store is completing the upload doesn't race it. The core waits for the store's answer and lets the store decide, which is what "the operation completed despite cancellation" allows (`SS:LRO-CancelOperation-2`) (T16, T17, T19, T23, T24).

**Silent failures.** The S3 references are full of success-shaped failures. A 200 from CompleteMultipartUpload "can contain either a success or an error" (`PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-2`). An object can be "created without a checksum value" (`PD:S3UG-MPU-mpuAndPermissions-1`). A checksum supplied at Complete can be "accepted but not validated or stored" (`PD:S3UG-INTEGRITY-UPLOAD-Full-object-checksums-6`). NoSuchUpload means "invalid, or ... aborted or completed" (`PD:S3API-Error-NoSuchUpload-1`). And a deadline "may be returned even if the operation has completed successfully" (`SS:RPC-CODE-DEADLINE_EXCEEDED-1`). The design takes no outcome of a state-changing store call as final unless it carries a parsed receipt. Every other outcome goes to a probe (HeadObject with checksum mode), and only the probe decides. The store refusing our credentials is never shown to the person as 401 or 403, because that would tell them to fix credentials they don't control (`HS:RFC9110-15.5.4-3`). DELETED is only reached after the store confirms the delete (T9, T12, T21, T22, T41).

**Developer experience.** Every refusal comes from one table and every transfer failure from another, and the HTTP response, the problem type and the `Operation.error` code are all derived from those two tables. That way there's no second place where a 409 could be written by hand. The citations themselves are a generated closed type, so citing a statement that doesn't exist fails to compile (T6, T30).

## The package

One cabal package, `funknown-core`, with `build-depends: base, containers, liquidhaskell`, `ghc-options: -fplugin=LiquidHaskell`, and `default-language: Haskell2010` plus explicit extensions (the sibling design found that GHC2021 turns on `GeneralizedNewtypeDeriving`, which Safe Haskell refuses). It does no IO and reads no clock. Each event brings two times from the shell: `mono`, a monotonic second count used for deadlines, backoff and restart intensity (OTP measures intensity in `erlang:monotonic_time(second)`, `references/status-and-supervision/otp/supervisor.erl:2279`), and `wall`, an HTTP-date as seconds since the epoch, used for Last-Modified and conditional requests.

I checked the toolchain in a throwaway scratch package (GHC 9.14.1, LiquidHaskell 0.9.14.1.1, z3 4.16.0), and four things came out of it that this layout depends on:

- `{-# LANGUAGE Safe #-}` modules verify under the plugin, including a Safe module that imports `Data.Map.Strict`. So every module below can be Safe.
- The RFC 9110 15-4 rule (an unknown code is treated as the x00 of its class) and the 15-6 rule (an invalid code is processed as 5xx) verified as plain refinements on `fromWire` and `fromAny` over the whole 100..599 range, with no enumeration and no PLE. I broke one branch on purpose and it came back UNSAFE, so the proof isn't vacuous.
- A per-file `stepFile` whose refinement says "a report with a stale epoch returns the file unchanged, and the offset never decreases" verified as stated. When I let a stale report through, it came back UNSAFE at that branch.
- LiquidHaskell can't see inside `Data.Map`, so every theorem about the machine is stated on `stepFile :: Env -> File -> FileEvent -> Step`. The `Map` routing layer only looks a file up, calls `stepFile`, and writes the result back.

Module layout:

```
funknown-core/
  funknown-core.cabal
  src/Funknown/
    Cite.hs                  generated: data Group, data Cite (one constructor per cited (group,id)), quote, doc, section
    Vocab/HttpStatus.hs      generated from HS http-status-codes-1.csv; Wire, fromWire, fromAny, Emittable
    Vocab/Method.hs          Method, safe, idempotent, replayable
    Vocab/RpcCode.hs         google.rpc.Code (17), codeNumber, codeName, codeHttp
    Vocab/ResourceState.hs   the AIP-216 states this core uses
    Vocab/DigestKey.hs       IANA Hash Algorithms for HTTP Digest Fields, with status
    Vocab/ProblemType.hs     RFC 9457 problem types we may emit
    Vocab/UploadField.hs     typed values of Upload-Offset, Upload-Complete, Upload-Length, Upload-Limit
    Vocab/EntityTag.hs       EntityTag, strong and weak comparison
    Store/Checksum.hs        S3 ChecksumAlgorithm, ChecksumType, the support relation, bit widths
    Store/Receipt.hs         Receipt and parseReceipt (composite detection, base64 shape)
    Store/Error.hs           S3 error codes we expect, their status, and the AWS retry classification
    Store/Call.hs            StoreCall and StoreOutcome
    Retry/Recourse.hs        Recourse and codeRecourse (AIP-194)
    Retry/OnStatus.hs        retry decision on an HTTP status (port of urllib3 Retry.is_retry)
    Retry/OnConnection.hs    retry decision on a connection failure (port of Go shouldRetryRequest)
    Retry/Backoff.hs         gRFC A6 backoff and pushback
    Retry/Throttle.hs        gRFC A6 retry token bucket
    Supervise/Intensity.hs   OTP add_restart and can_restart
    Supervise/Restart.hs     OTP do_restart decision table
    Http/Conditional.hs      RFC 9110 13.2.2 precondition ladder (port of Go net/http fs.go)
    Http/Range.hs            single-range satisfiability, 206 and 416
    Upload/Plan.hs           part size, part numbering, Upload-Limit values
    Upload/Length.hs         length indicators on append (port of tusd getIETFDraftUploadLength)
    Import/Origin.hs         decision on an origin's response to an import fetch
    Core/Refusal.hs          Refusal: every reason a request is refused, with status, problem, code, recourse
    Core/Fault.hs            Fault: every reason a transfer ends badly, with code and recourse
    Core/File.hs             File, Life, Transfer, Phase, Outstanding, Cleanup
    Core/Event.hs            FileEvent, WorldEvent
    Core/Command.hs          Command
    Core/StepFile.hs         stepFile: the per-file transition function (all theorems live here)
    Core/World.hs            routing by id, token bucket, per-owner counters, tombstones (uses containers)
    Project/Response.hs      Response with refined headers, render of Refusal
    Project/Upload.hs        responses on the upload resource
    Project/Content.hs       responses on file content (download)
    Project/File.hs          FileView: the facts a file representation is rendered from
    Project/Operation.hs     the google.longrunning.Operation projection
  test/Exhaustive.hs         properties checked over their entire finite domain
tools/
  gen-vocab.py             regenerates Cite.hs and Vocab/HttpStatus.hs from references/; fails on unknown ids
  check-cites.py           re-checks every quote in Cite.hs against its group's statements.json
```

The two tools sit outside the package because the core may only depend on base and containers. They run with `python3 -I`, take the reference paths as arguments, and their output is committed. If CI regenerates the files and gets a diff, the build fails.

Proof methods used in the catalog:

- **Refinement**: a LiquidHaskell type on a function or data constructor, discharged by z3 at compile time.
- **Reflection**: a reflected function plus a lemma proved with `--reflection --ple`, for properties that need to unfold a definition.
- **Construction**: the illegal value has no constructor, or the only function that builds a value enforces the rule. GHC's exhaustiveness checking (`-Werror=incomplete-patterns`) and LiquidHaskell's totality check back it.
- **Exhaustion**: a test-suite executable that enumerates the whole finite domain and checks every point. It's only acceptable where the domain really is finite and fully enumerated, and nowhere do we sample.

## The vocabulary, type by type

Each table lists a type's constructors and the statements each one comes from. A constructor I couldn't tie to a statement is left out, and if we need it anyway, it goes to the open questions.

### HTTP status (`Vocab.HttpStatus`, generated)

The sum type has one constructor for each of the 64 assigned rows of `references/http-semantics/http-status-codes-1.csv`, each citing `HS:IANA-HTTP-Status-Codes-<value>`. Reason phrases come from the registry, not from Go `status.go`, CPython `http/__init__.py` or http-types `Status.hs`, because all three still carry pre-RFC 9110 phrases ("Request Entity Too Large", "Unprocessable Entity", "I'm a teapot"). The eleven unassigned ranges (`HS:IANA-HTTP-Status-Codes-105-199`, `-209-225`, `-227-299`, `-309-399`, `-419-420`, `-427`, `-430`, `-432-450`, `-452-499`, `-509`, `-512-599`) have no constructors. A received code in one of them is folded to the x00 of its class.

| Name | Meaning | Statements |
|---|---|---|
| `Wire` | `{s:Int \| 100 <= s && s <= 599}` | `HS:RFC9110-15-1`, `HS:RFC9110-15-5` |
| `statusClass` | first digit, 1..5 | `HS:RFC9110-15-2`, `HS:RFC9110-15-3` |
| `fromWire :: Wire -> Status` | assigned code as itself, anything else as x00 of its class | `HS:RFC9110-15-4` |
| `fromAny :: Int -> Status` | outside 100..599 is processed as 500 | `HS:RFC9110-15-5`, `HS:RFC9110-15-6` |
| `Emittable` | `{s:Status \| final s && not (s in {104, 306, 418, 510})}` | `HS:RFC9110-15-7`, `HS:IANA-HTTP-Status-Codes-104`, `HS:IANA-HTTP-Status-Codes-306`, `HS:IANA-HTTP-Status-Codes-418`, `HS:IANA-HTTP-Status-Codes-510`, `HS:RFC9110-15.5.19` |

The core only ever emits final responses, so 1xx is excluded from `Emittable`. 104 in particular is a TEMPORARY registration that expires 2026-11-13. We don't need it, because every upload is created by a request whose final 201 carries the Location (`UP:RESUMABLE-UPLOAD-13-4.2.1-8`, `UP:RESUMABLE-UPLOAD-13-4.2.2-5`). There is no constructor for 499, so the nginx "Client Closed Request" that `SS:RPC-CODE-CANCELLED-http` uses can't be emitted.

### Method (`Vocab.Method`)

| Constructor | safe | idempotent | replayable | Statements |
|---|---|---|---|---|
| `GET`, `HEAD`, `OPTIONS`, `TRACE` | yes | yes | yes | `HS:RFC9110-9.2.1-2`, `HS:RFC9110-9.2.2-1` |
| `PUT`, `DELETE` | no | yes | no | `HS:RFC9110-9.2.2-1` |
| `POST` | no | no | no | `HS:RFC9110-9.3.3-1` |
| `PATCH` | no | no | no | `UP:RESUMABLE-UPLOAD-13-4.4.1-1` |
| `OtherMethod` | no | no | no | `HS:RFC9110-9.2.2-4`, `HS:RFC8470-4-1` |

`replayable` is the Go `isReplayable` set (`references/http-semantics/code/go/request.go:1543-1557`) without the Idempotency-Key escape, because Idempotency-Key is not a standard. PATCH is marked non-idempotent because RFC 5789 isn't vendored and RFC 9110 doesn't list it as idempotent.

### google.rpc.Code (`Vocab.RpcCode`)

There are 17 constructors, each citing `SS:GRPC-STATUSCODES-<NAME>` for its meaning and `SS:RPC-CODE-<NAME>-http` for its HTTP mapping. `codeNumber` follows code.proto, where UNAUTHENTICATED = 16 is declared between PERMISSION_DENIED = 7 and RESOURCE_EXHAUSTED = 8. `codeHttp` is the "HTTP Mapping" column: OK 200, CANCELLED 499, UNKNOWN 500, INVALID_ARGUMENT 400, DEADLINE_EXCEEDED 504, NOT_FOUND 404, ALREADY_EXISTS 409, PERMISSION_DENIED 403, UNAUTHENTICATED 401, RESOURCE_EXHAUSTED 429, FAILED_PRECONDITION 400, ABORTED 409, OUT_OF_RANGE 400, UNIMPLEMENTED 501, INTERNAL 500, UNAVAILABLE 503, DATA_LOSS 500. `codeHttp` returns a plain `Int`, not `Emittable`, because of the 499.

We use the Code only in `Operation.error`, which AIP-151 requires to be a `google.rpc.Status` (`SS:AIP151-Errors-2`). Our HTTP responses never take their status from `codeHttp`. They take it from the Refusal table, and the theorem catalog lists every place where the two disagree (T6). That follows the gRPC rule that the HTTP-to-Code table is not for servers ("Servers _must not_ use this table to determine an HTTP status code to use", `SS:GRPC-HTTPMAP-scope-2`).

### Resource state (`Vocab.ResourceState`)

Two candidate vocabularies were vendored for a file's lifecycle: GA4GH TES/WES task states and AIP-216 resource states. I went with AIP-216, because it is the only one that defines what a refused transition answers ("If the state transition is not allowed, the service **must** error with `FAILED_PRECONDITION` (HTTP 400)", `SS:AIP216-Transition-2`). TES and WES define no transitions at all, and Funnel encodes two that disagree with each other (`references/drive-and-objects/code/funnel-v0.11.14/tes/states.go:30-80` against `database/boltdb/events.go:188-230`). AIP-216 also requires that "Each state must come with a use case" (`SS:AIP216-EnumValues-4`), so the type only has the six states below.

| Constructor | Use case in this core | Statements |
|---|---|---|
| `CREATING` | bytes are arriving or the store is completing; the file is listed but not usable | `SS:AIP216-Active-3`, `SS:AIP151-StandardMethods-1` |
| `ACTIVE` | the store vouched with a full-object receipt; downloads are served | `SS:AIP216-EnumValues-1`, `SS:AIP216-Resting` |
| `FAILED` | the transfer ended with a Fault other than cancellation | `SS:AIP216-EnumValues-2`, `SS:AIP216-Resting` |
| `CANCELLED` | the transfer ended because someone cancelled it | `SS:AIP216-Resting`, `SS:LRO-CancelOperation-3` |
| `DELETING` | the store's delete is in flight | `SS:AIP216-Active-3` |
| `DELETED` | the store confirmed the delete; kept as a tombstone | `SS:AIP216-Resting`, `SS:AIP216-EnumValues-2` |

`ACCEPTED`, `SUCCEEDED`, `SUSPENDED`, `VERIFIED`, `PENDING`, `RUNNING`, `REPAIRING` and `SUSPENDING` are left out because nothing in this core needs them. The state is output only (`SS:AIP216-OutputOnly-1`, `SS:AIP216-OutputOnly-2`), and there is no unspecified value (`SS:AIP216-Default`).

### Digest keys (`Vocab.DigestKey`)

There are eight constructors, one per row of the IANA "Hash Algorithms for HTTP Digest Fields" registry, each with its status. The registry status set is Active, Provisional and Deprecated (`HS:RFC9530-5-3`), and no Provisional entry exists today.

| Constructor | Status | Statements |
|---|---|---|
| `Sha512` | Active | `HS:RFC9530-7.2-1`, `PD:IANA-DIGEST-ALGS-sha-512-1` |
| `Sha256` | Active | `HS:RFC9530-7.2-2`, `PD:IANA-DIGEST-ALGS-sha-256-1` |
| `Md5` | Deprecated | `HS:RFC9530-7.2-3`, `PD:IANA-DIGEST-ALGS-md5-1` |
| `Sha` | Deprecated | `HS:RFC9530-7.2-4`, `PD:IANA-DIGEST-ALGS-sha-1` |
| `Unixsum` | Deprecated | `HS:RFC9530-7.2-5`, `PD:IANA-DIGEST-ALGS-unixsum-1` |
| `Unixcksum` | Deprecated | `HS:RFC9530-7.2-6`, `PD:IANA-DIGEST-ALGS-unixcksum-1` |
| `Adler` | Deprecated | `HS:RFC9530-7.2-7`, `PD:IANA-DIGEST-ALGS-adler-1` |
| `Crc32c` | Deprecated | `HS:RFC9530-7.2-8`, `PD:IANA-DIGEST-ALGS-crc32c-1` |

The core only emits through `EmitKey = {k:DigestKey | status k == Active}`. A download served to a third party is a potentially adversarial setting, and Deprecated keys "MUST NOT be used in a potentially adversarial setting" (`HS:RFC9530-5-2`).

### Problem types (`Vocab.ProblemType`)

| Constructor | Title | Recommended status | Statements |
|---|---|---|---|
| `AboutBlank` | the status's registry phrase | the response status | `PD:IANA-PROBLEM-TYPES-about:blank-1`, `PD:RFC9457-4.2.1-1`, `PD:RFC9457-4.2.1-2`, `PD:RFC9457-3.1.1-2` |
| `MismatchingUploadOffset` | Mismatching Upload Offset | 409 | `UP:RESUMABLE-UPLOAD-13-7.1-1`, `UP:RESUMABLE-UPLOAD-13-7.1-2`, `UP:RESUMABLE-UPLOAD-13-14.4-1` |
| `InconsistentUploadLength` | Inconsistent Upload Length Values | 400 | `UP:RESUMABLE-UPLOAD-13-7.2-1`, `UP:RESUMABLE-UPLOAD-13-14.4-2` |

The three registered digest problem types (`PD:IANA-PROBLEM-TYPES-digest-unsupported-algorithms-1`, `-digest-invalid-values-1`, `-digest-mismatched-values-1`) don't get constructors, because nothing in this core validates a client's digest yet (see open question 4). The `title` member always comes from a registry or from a draft's registration request, and the core never generates a `detail` member, because any detail text would be prose we made up (`PD:RFC9457-3.1.4-1`). A problem body has no `status` field of its own. The renderer copies the response status in, so "Generators MUST use the same status code in the actual HTTP response" (`PD:RFC9457-3.1.2-2`) holds by construction.

The two upload problem types come from an Internet-Draft. IANA has not registered them yet, so they stay an open question (open question 1).

### Upload fields and the part plan (`Vocab.UploadField`, `Upload.Plan`)

| Type | Shape | Statements |
|---|---|---|
| `UploadOffset` | `Nat` | `UP:RESUMABLE-UPLOAD-13-4.1.1-4`, `UP:TUS-1.0.0-Core.Headers.Upload-Offset-1` |
| `UploadComplete` | `Bool` | `UP:RESUMABLE-UPLOAD-13-4.1.2-2` |
| `UploadLength` | `Nat` | `UP:RESUMABLE-UPLOAD-13-4.1.3-5` |
| `UploadLimit` | record of `maxSize`, `maxAppendSize`, `minAppendSize`, `maxAge` | `UP:RESUMABLE-UPLOAD-13-4.1.4-2`..`-7` |
| `PartSize` | `{p:Nat \| p >= 5242880}` | `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-4` |
| `PartNo` | `{n:Int \| 1 <= n && n <= 10000}` | `PD:S3UG-MPU-mpu-process-2` |

The plan for every upload is fixed at creation as `minAppendSize = maxAppendSize = P` and `maxSize <= 10000 * P`. A client that respects the announced limits therefore sends exactly `P` bytes per non-final append (`UP:RESUMABLE-UPLOAD-13-4.1.4-5`, `UP:RESUMABLE-UPLOAD-13-4.1.4-6`), and the completing append is exempt from the minimum and may be shorter (`UP:RESUMABLE-UPLOAD-13-4.1.4-6`). Part `n` always covers bytes `[(n-1)P, nP)`. I chose 5242880 (5 MiB) as the floor because it satisfies "at least 5 MB" under either reading of MB. The limits never change after creation, so the monotonicity SHOULDs (`UP:RESUMABLE-UPLOAD-13-4.1.4-8`..`-11`) hold trivially.

### Entity tags (`Vocab.EntityTag`)

`EntityTag = Strong Opaque | Weak Opaque`, where `Opaque` is refined to the `etagc` alphabet (`HS:RFC9110-8.8.3-3`). The two comparison functions follow `HS:RFC9110-8.8.3.2-1` and `HS:RFC9110-8.8.3.2-2`. The core only emits `Strong` tags, and the tag for a file is derived from its file id. A file's content never changes once it is ACTIVE ("One DRS ID MUST always return the same object data", `DO:DRS-DrsApiPrinciples.DRS-IDs-2`), and file ids are never reused, so that constant tag is a strong validator: it changes whenever the data changes because the data never changes, and it is unique across all versions because there is one (`HS:RFC9110-8.8.1-1`, `HS:RFC9110-8.8.1-2`, `DO:RFC4918-8.8-2`). I didn't want to use the store's ETag, because RFC 4918 itself says the meaning of an ETag on PUT isn't clearly defined (`DO:RFC4918-8.6-3`) and S3's multipart ETag isn't a digest (`PD:S3UG-INTEGRITY-UPLOAD-ChecksumTypes-Uploads-4`).

## Store vocabulary and the receipt

The core talks about the store in S3's own vocabulary, because S3's API docs are the only store API we vendored. It never calls S3 itself. It emits a `StoreCall` command, and the shell reports a `StoreOutcome` event.

### Checksum algorithm, type and support (`Store.Checksum`)

`ChecksumAlgorithm` has the ten values `CRC32 | CRC32C | SHA1 | SHA256 | CRC64NVME | SHA512 | MD5 | XXHASH64 | XXHASH3 | XXHASH128` (`PD:S3API-CreateMultipartUpload-request-header-ChecksumAlgorithm-1`). `ChecksumType` is `COMPOSITE | FULL_OBJECT` (`PD:S3-SMITHY-com.amazonaws.s3#ChecksumType-1`, `PD:S3API-CreateMultipartUpload-request-header-ChecksumType-1`). The support relation `supports :: Shape -> ChecksumAlgorithm -> ChecksumType -> Bool` comes from the multipart table (`PD:S3UG-INTEGRITY-UPLOAD-MultipartUploads-Checksums-1`), and for a single request it is FULL_OBJECT only (`PD:S3UG-INTEGRITY-UPLOAD-SinglePartUploads-Checksums-1`, `PD:S3API-PutObject-response-header-ChecksumType-1`). The at-rest page contradicts the table (`PD:S3UG-INTEGRITY-AT-REST-using-additional-checksums-rest-1` says every algorithm supports both types except CRC64NVME). I followed the table, because it is the more specific statement and the full-object text agrees with it (`PD:S3UG-INTEGRITY-UPLOAD-Full-object-checksums-3`).

`bitWidth` is only defined for algorithms whose width a vendored statement quotes: CRC64NVME 64 (`PD:S3API-PutObject-request-header-ChecksumCRC64NVME-1`), CRC32 32 (`PD:S3API-CompleteMultipartUpload-response-ChecksumCRC32-1`) and SHA256 256 (`PD:S3API-Checksum-API_Checksum_Contents-3`). The other widths are open question 14.

`toDigestKey :: ChecksumAlgorithm -> Maybe DigestKey` maps SHA256 to sha-256, SHA512 to sha-512, SHA1 to sha, MD5 to md5 and CRC32C to crc32c. Everything else maps to `Nothing`, because the IANA registry has no key for CRC32, CRC64NVME or any XXHASH.

The core always uses one configuration: multipart, CRC64NVME, FULL_OBJECT, declared at CreateMultipartUpload. Multipart covers both a single small upload and a large one, so there is one store path instead of two. CRC64NVME is full-object-only and is S3's default ("If you don't specify a checksum algorithm ... S3 automatically chooses the CRC-64/NVME", `PD:S3UG-INTEGRITY-UPLOAD-using-additional-checksums-2`). Declaring it at creation avoids the trap where a checksum supplied only at Complete is "accepted but not validated or stored" (`PD:S3UG-INTEGRITY-UPLOAD-Full-object-checksums-6`). The cost of that choice is that the receipt never has a registered digest key, so the core can't emit Repr-Digest under this configuration (open question 3).

### Receipt (`Store.Receipt`)

```
data Receipt = Receipt { alg :: ChecksumAlgorithm, value :: Digest alg, size :: Nat }
parseReceipt :: ChecksumType -> ChecksumAlgorithm -> Text -> Nat -> Either NotAReceipt Receipt
```

There is no `ChecksumType` field, because a `Receipt` can only be FULL_OBJECT. `parseReceipt` is the only function that builds one, and it returns `Right` only when all of these hold:

- the declared type is FULL_OBJECT (`PD:S3-SMITHY-com.amazonaws.s3#ChecksumType-1`);
- the value doesn't end in `-N` with `N` from 1 to 10000 and no leading zero, the composite marker detected by the AWS SDK (`PD:AWS-SDK-JS-isChecksumWithPartNumber-isChecksumWithPartNumber-1`; port of `references/problems-and-digests/code/aws-sdk-js-v3/.../isChecksumWithPartNumber.ts`);
- the value is padded base64 (`PD:RFC9651-4.1.8-1`) of exactly `bitWidth alg / 8` big-endian bytes (`PD:S3UG-INTEGRITY-UPLOAD-trailing-checksums-1`). For CRC64NVME that is 12 characters ending in a single `=`.

`NotAReceipt` is a closed sum (`Composite`, `NotFullObject`, `BadEncoding`, `UnknownWidth`) so a caller can't silently drop the reason.

The core never computes a digest. The CRC-64/NVME reference fold in `aws-checksums/tests/crc64_test.c` and the combine lemma in `crc64_sw.c` aren't ported into the core, because the core never needs a checksum value, only the store's report of one. They are good test oracles for the shell (open question 18).

### Store calls, outcomes and errors (`Store.Call`, `Store.Error`)

| StoreCall | Purpose | Statements |
|---|---|---|
| `CreateMultipartUpload` (CRC64NVME, FULL_OBJECT) | open the store-side upload | `PD:S3API-CreateMultipartUpload-API_CreateMultipartUpload-1`, `PD:S3API-CreateMultipartUpload-request-header-ChecksumAlgorithm-1`, `PD:S3API-CreateMultipartUpload-request-header-ChecksumType-1` |
| `UploadPart n` | store one planned part (issued through the mover) | `PD:S3UG-MPU-mpu-process-2`, `PD:S3UG-MPU-mpu-process-3` |
| `CompleteMultipartUpload parts size` with `If-None-Match: *` and the object size | finalize | `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-1`, `PD:S3API-CompleteMultipartUpload-request-header-IfNoneMatch-1`, `PD:S3API-CompleteMultipartUpload-request-header-MpuObjectSize-1` |
| `HeadObject` with checksum mode | the probe | `PD:S3API-GetObject-request-header-ChecksumMode-1`, `PD:S3API-HeadObject-request-header-ChecksumMode-1` |
| `AbortMultipartUpload` | cleanup | `PD:S3API-AbortMultipartUpload-API_AbortMultipartUpload-1` |
| `ListParts` | prove cleanup finished | `PD:S3API-AbortMultipartUpload-API_AbortMultipartUpload-2` |
| `DeleteObject` | delete content | `HS:RFC9110-9.3.5-1` (no vendored S3 statement; open question 13) |

Object keys are derived from file ids, which are never reused, so `If-None-Match: *` on Complete can only fail when our own earlier Complete already succeeded. That is the RFC 9110 "unless it can be determined that the state-changing request has already succeeded" case (`HS:RFC9110-13.2.2-2`, `HS:RFC9110-13.1.1-6`), and the core treats it as "go probe".

```
data StoreOutcome
  = Opened UploadRef                 -- CreateMultipartUpload succeeded
  | Completed (Maybe ReceiptReport)  -- Complete's body parsed as success; the checksum may be missing
  | Found (Maybe ReceiptReport) Nat  -- HeadObject: object exists, with or without a checksum, and its size
  | Absent                           -- HeadObject: no such key
  | Aborted | PartsListed Nat | Removed
  | NoSuchUpload                     -- PD:S3API-Error-NoSuchUpload-1, ambiguous by definition
  | KeyExists                        -- 412 on Complete with If-None-Match: *
  | StoreFailed StoreError
data StoreError = StoreError { code :: S3Code, status :: Status, cls :: RetryClass } | Timeout | ConnectionLost
data RetryClass = Transient | Throttling | NonRetryable
```

`S3Code` has one constructor per `PD:S3API-Error-<Code>-1` row that a call above can return, plus `ConditionalRequestConflict` (`PD:S3API-PutObject-request-header-IfMatch-1`) and `OtherCode`. Unknown codes are folded into `OtherCode` rather than given new names, which is the "convert them to UNKNOWN" rule (`SS:GRPC-STATUSCODES-status-3`). `RetryClass` is a port of the AWS SDK classification: the error code is matched first and the status second (`PD:AWSSDK-RETRY-error-classification-4`). The transient codes come from `PD:AWSSDK-RETRY-error-classification-1` and `PD:SMITHY-TS-error-classification-constants-TRANSIENT_ERROR_CODES-1`, the throttling codes (including `SlowDown`) from `PD:AWSSDK-RETRY-error-classification-2`, and a bare 500, 502, 503 or 504 is transient (`PD:SMITHY-TS-error-classification-constants-TRANSIENT_ERROR_STATUS_CODES-1`). The credential and identity codes (`AccessDenied`, `InvalidAccessKeyId`, `ExpiredToken`, `InvalidToken`, `TokenRefreshRequired`, `RequestTimeTooSkewed`; `PD:S3API-Error-AccessDenied-1`, `PD:S3API-Error-InvalidAccessKeyId-1`, `PD:S3API-Error-ExpiredToken-1`, `PD:S3API-Error-InvalidToken-1`, `PD:S3API-Error-TokenRefreshRequired-1`, `PD:S3API-Error-RequestTimeTooSkewed-1`) are NonRetryable. They mean the store is refusing *us*, so they become `Internal StoreRefusedUs`, never 401 or 403 to the person.

## Why a request is refused, and why a transfer ends

These are the only two places in the core where an error is named. A `Refusal` is a request we answer with an error right now, and every Refusal has an HTTP status. A `Fault` is the reason a transfer ended without a usable file, and every Fault has a google.rpc.Code for `Operation.error`. I kept them as separate types because a single type would force us to invent an HTTP status for transfer failures that no request is waiting on, and to invent a Code for refusals no operation records.

### Refusal (`Core.Refusal`)

| Constructor | HTTP | Extra headers | Problem type | Code (T6 lists the mismatches) | Recourse | Statements |
|---|---|---|---|---|---|---|
| `NoCredentials` | 401 | WWW-Authenticate | about:blank | UNAUTHENTICATED | `NoRetryUntil Authenticated` | `HS:RFC9110-11.4-1`, `HS:RFC9110-15.5.2-1`, `HS:RFC9110-15.5.2-2`, `HS:RFC9110-11.6.1-1`, `SS:AIP194-GenerallyNonRetryable-UNAUTHENTICATED` |
| `BadCredentials` | 401 | WWW-Authenticate | about:blank | UNAUTHENTICATED | `RetryWithNewCredentials` | `HS:RFC9110-11.4-1`, `HS:RFC9110-15.5.2-3`, `HS:RFC9110-15.5.2-4` |
| `Forbidden` | 403 | | about:blank | PERMISSION_DENIED | `NoRetryUntil HasPermission` | `HS:RFC9110-11.4-2`, `HS:RFC9110-15.5.4-1`, `HS:RFC9110-15.5.4-3`, `SS:AIP193-PermissionDenied-1`, `SS:AIP194-GenerallyNonRetryable-PERMISSION_DENIED`, `PD:RFC9457-4-2` |
| `NotFound` | 404 | | about:blank | NOT_FOUND | `NoRetryUntil ResourceCreated` | `HS:RFC9110-15.5.5-1`, `SS:AIP193-PermissionDenied-2`, `SS:AIP194-GenerallyNonRetryable-NOT_FOUND` |
| `Gone` | 410 | | about:blank | NOT_FOUND | `StartNewUpload` | `HS:RFC9110-15.5.11-1`, `HS:RFC9110-15.5.5-2`, `UP:TUS-1.0.0-Expiration.Headers.Upload-Expires-3`, `UP:TUS-1.0.0-Termination.Requests.DELETE-1`, `UP:RESUMABLE-UPLOAD-13-4.1.1-9`, `UP:RESUMABLE-UPLOAD-13-4.5.2-1` |
| `OffsetMismatch expected provided` | 409 | Upload-Offset = expected, Upload-Complete: ?0 | MismatchingUploadOffset with expected-offset, provided-offset | ABORTED | `ResumeAtOffset expected` | `UP:RESUMABLE-UPLOAD-13-4.4.2-3`, `UP:RESUMABLE-UPLOAD-13-7.1-2`, `UP:RESUMABLE-UPLOAD-13-4.7-2`, `UP:TUS-1.0.0-Core.Requests.PATCH-2`, `SS:GRPC-STATUSCODES-FAILED_PRECONDITION-2` |
| `InconsistentLength` | 400 | Upload-Complete: ?0 | InconsistentUploadLength | INVALID_ARGUMENT | `NeverRetry` | `UP:RESUMABLE-UPLOAD-13-4.1.3-6`, `UP:RESUMABLE-UPLOAD-13-4.1.3-7`, `SS:AIP194-NonRetryable-INVALID_ARGUMENT` |
| `AppendTooLarge` | 413 | Upload-Limit, Upload-Complete: ?0 | about:blank | RESOURCE_EXHAUSTED | `ResumeWithinLimits` | `UP:RESUMABLE-UPLOAD-13-4.1.4-5`, `UP:RESUMABLE-UPLOAD-13-4.1.4-17`, `UP:RESUMABLE-UPLOAD-13-4.1.4-18`, `UP:RESUMABLE-UPLOAD-13-4.1.4-20`, `HS:RFC9110-15.5.14-1`, `SS:GRPC-STATUSCODES-libgen-toolarge` |
| `AppendTooSmall` | 400 | Upload-Limit, Upload-Complete: ?0 | about:blank | INVALID_ARGUMENT | `ResumeWithinLimits` | `UP:RESUMABLE-UPLOAD-13-4.1.4-6`, `UP:RESUMABLE-UPLOAD-13-4.1.4-17`, `UP:RESUMABLE-UPLOAD-13-4.1.4-20`, `HS:RFC9110-15.5.1` |
| `ExceedsMaxSize` | 413 | Upload-Limit, Upload-Complete: ?0 | about:blank | RESOURCE_EXHAUSTED | `NeverRetry` | `UP:RESUMABLE-UPLOAD-13-4.1.4-3`, `UP:RESUMABLE-UPLOAD-13-4.2.1-6`, `UP:TUS-1.0.0-Creation.Requests.POST-7`, `HS:RFC9110-15.5.14-1` |
| `OffsetPastLength` | 413 | Upload-Complete (open question 6) | about:blank | OUT_OF_RANGE | `NeverRetry` | `UP:RESUMABLE-UPLOAD-13-4.4.2-7`, `UP:TUSD-2.10.1-writeChunk-1`, `SS:GRPC-STATUSCODES-OUT_OF_RANGE` |
| `PreconditionFailed` | 412 | | about:blank | ABORTED | `RetryHigherLevel` | `HS:RFC9110-13.2.2-2`, `HS:RFC9110-13.2.2-3`, `HS:RFC9110-13.2.2-4`, `HS:RFC9110-15.5.13`, `SS:AIP154-Guidance-3`, `SS:GRPCGW-HTTPStatusFromCode-412` |
| `RangeNotSatisfiable len` | 416 | Content-Range: bytes */len | about:blank | OUT_OF_RANGE | `NoRetryUntil RangeExtended` | `HS:RFC9110-14.2-9`, `HS:RFC9110-14.4-6`, `HS:RFC9110-14.4-7`, `HS:RFC9110-15.5.17-1`, `HS:RFC9110-15.5.17-2` |
| `OperationInProgress` | 409 | | about:blank | ABORTED | `RetryHigherLevel` | `SS:AIP151-Parallel-2`, `HS:RFC9110-15.5.10-1`, `SS:AIP194-GenerallyNonRetryable-ABORTED` |
| `RateLimited secs` | 429 | Retry-After: secs | about:blank | RESOURCE_EXHAUSTED | `RetryAfterDelay secs` | `HS:RFC6585-4-1`, `HS:RFC6585-4-2`, `UP:RESUMABLE-UPLOAD-13-13-8`, `UP:RESUMABLE-UPLOAD-13-4.7-4` |
| `InsufficientStorage` | 507 | never Retry-After | about:blank | RESOURCE_EXHAUSTED | `SeparateUserAction` | `HS:RFC4918-11.5-1`, `HS:RFC4918-11.5-2`, `SS:AIP194-GenerallyNonRetryable-RESOURCE_EXHAUSTED` |
| `StoreUnavailable (Maybe secs)` | 503 | Retry-After when the store gave a hint | about:blank | UNAVAILABLE | `RetryCall` | `HS:RFC9110-15.6.4-1`, `HS:RFC9110-15.6.4-2`, `HS:RFC9110-10.2.3-2`, `SS:AIP194-Retryable-UNAVAILABLE`, `UP:RESUMABLE-UPLOAD-13-4.7-5` |
| `NotImplemented` | 501 | | about:blank | UNIMPLEMENTED | `NoRetryUntil Implemented` | `HS:RFC9110-15.6.2`, `SS:AIP194-GenerallyNonRetryable-UNIMPLEMENTED` |
| `Internal cause` | 500 | | about:blank | INTERNAL | `SurfaceImmediately` | `HS:RFC9110-15.6.1`, `SS:GRPC-STATUSCODES-INTERNAL`, `SS:AIP194-GenerallyNonRetryable-INTERNAL` |
| `DataLoss` | 500 | | about:blank | DATA_LOSS | `SurfaceImmediately` | `SS:GRPC-STATUSCODES-DATA_LOSS`, `SS:AIP194-NonRetryable-DATA_LOSS`, `SS:ABSL-STATUS-kDataLoss` |

`Internal`'s `cause` is `StoreRefusedUs | DuplicateId | PlanViolated | ObjectWithoutChecksum | Contradiction`. The cause is for the alert command and never reaches the wire. A store timeout on a request-scoped call becomes `StoreUnavailable`, not 504, because every request-scoped store call the core makes (UploadPart, CreateMultipartUpload) is safe to repeat: a part re-upload overwrites the same part (`PD:S3UG-MPU-mpu-process-2`), and an orphaned CreateMultipartUpload is caught by the lifecycle backstop (open question 13).

### Fault (`Core.Fault`)

`faultCode :: Fault -> {c:Code | c /= OK}`. A Fault can never be OK, the same way a StatusOr can never hold OK (`SS:ABSL-STATUSOR-2`).

| Constructor | Code | Recourse shown through the operation | Statements |
|---|---|---|---|
| `Cancelled` | CANCELLED | `NeverRetry` | `SS:LRO-CancelOperation-3`, `SS:GRPC-STATUSCODES-CANCELLED`, `SS:AIP194-NonRetryable-CANCELLED` |
| `Expired` | DEADLINE_EXCEEDED | `StartNewUpload` | `SS:GRPC-STATUSCODES-DEADLINE_EXCEEDED`, `UP:RESUMABLE-UPLOAD-13-4.1.4-7`, `UP:TUS-1.0.0-Expiration.Example-1`, `SS:AIP194-NonRetryable-DEADLINE_EXCEEDED` |
| `OutOfRange` | OUT_OF_RANGE | `NeverRetry` | `UP:RESUMABLE-UPLOAD-13-4.4.2-7`, `SS:GRPC-STATUSCODES-OUT_OF_RANGE` |
| `Unavailable` | UNAVAILABLE | `RetryHigherLevel` (start a new transfer) | `SS:GRPC-STATUSCODES-UNAVAILABLE`, `SS:OTP-SUPPRINC-MaxIntensity-1`, `SS:GRFC-A6-Throttling-2` |
| `UpstreamRefused Status` | FAILED_PRECONDITION | `NoRetryUntil StateChanges` | `SS:GRPC-STATUSCODES-FAILED_PRECONDITION`, `SS:GRPC-STATUSCODES-FAILED_PRECONDITION-2`, `SS:AIP194-GenerallyNonRetryable-FAILED_PRECONDITION` |
| `Revoked` | PERMISSION_DENIED | `NoRetryUntil HasPermission` | `UP:RESUMABLE-UPLOAD-13-13-6`, `UP:RESUMABLE-UPLOAD-13-13-7` |
| `FInternal cause` | INTERNAL | `SurfaceImmediately` | `SS:GRPC-STATUSCODES-INTERNAL`, `SS:AIP194-GenerallyNonRetryable-INTERNAL` |
| `FDataLoss` | DATA_LOSS | `SurfaceImmediately` | `SS:GRPC-STATUSCODES-DATA_LOSS`, `SS:AIP194-NonRetryable-DATA_LOSS`, `SS:ABSL-STATUS-kDataLoss` |

`UpstreamRefused` is how an import origin's own 401 or 403 is recorded. The person's permission in our system is not what failed, so it is not PERMISSION_DENIED (T9). `Revoked` comes only from the person's own access being re-checked before an import finalizes (`UP:RESUMABLE-UPLOAD-13-13-6`).

`refuseNow :: Fault -> Refusal` answers the request that was waiting when a transfer failed (Unavailable to `StoreUnavailable`, FInternal to `Internal`, FDataLoss to `DataLoss`, OutOfRange to `OffsetPastLength`, Revoked to `Forbidden`, Expired and Cancelled to `Gone`, UpstreamRefused to `Internal Contradiction` because imports never hold a request open). `refuseEnded :: Fault -> Refusal` answers every later request to the dead upload resource, and it is always `Gone`, because we track ended uploads and "The latter one SHOULD be used if the Server is keeping track of expired uploads" (`UP:TUS-1.0.0-Expiration.Headers.Upload-Expires-3`).

### Recourse (`Retry.Recourse`)

A Recourse is never sent as a token. It is the core's name for a behavior a standard prescribes, and the status code and problem type are how the client learns it. Each constructor cites the text that defines the behavior.

| Constructor | Statements |
|---|---|
| `RetryCall` | `SS:AIP194-Retryable-UNAVAILABLE`, `SS:GRPC-STATUSCODES-FAILED_PRECONDITION-2` |
| `RetryAfterDelay secs` | `HS:RFC9110-10.2.3-1`, `HS:RFC6585-4-2` |
| `RetryHigherLevel` | `SS:AIP194-GenerallyNonRetryable-ABORTED`, `SS:GRPC-STATUSCODES-FAILED_PRECONDITION-2` |
| `ResumeAtOffset n` | `UP:RESUMABLE-UPLOAD-13-4.7-2` |
| `ResumeWithinLimits` | `UP:RESUMABLE-UPLOAD-13-4.1.4-20`, `UP:RESUMABLE-UPLOAD-13-4.7-3` |
| `RetryWithNewCredentials` | `HS:RFC9110-15.5.2-3`, `HS:RFC9110-15.5.4-3` |
| `NoRetryUntil cond`, cond in `ResourceCreated, ResourceDeleted, HasPermission, Authenticated, StateChanges, RangeExtended, Implemented` | `SS:AIP194-GenerallyNonRetryable-NOT_FOUND`, `-ALREADY_EXISTS`, `-PERMISSION_DENIED`, `-UNAUTHENTICATED`, `-FAILED_PRECONDITION`, `-OUT_OF_RANGE`, `-UNIMPLEMENTED` |
| `NeverRetry` | `SS:AIP194-NonRetryable-0`, `SS:AIP194-NonRetryable-INVALID_ARGUMENT`, `SS:AIP194-NonRetryable-CANCELLED`, `SS:AIP194-NonRetryable-DEADLINE_EXCEEDED` |
| `SurfaceImmediately` | `SS:AIP194-NonRetryable-DATA_LOSS`, `SS:AIP194-GenerallyNonRetryable-INTERNAL`, `SS:AIP194-GenerallyNonRetryable-UNKNOWN` |
| `SeparateUserAction` | `HS:RFC4918-11.5-2` |
| `StartNewUpload` | `UP:TUS-1.0.0-Expiration.Headers.Upload-Expires-3` |

`codeRecourse :: Code -> Recourse` is the AIP-194 partition over all 17 codes. RESOURCE_EXHAUSTED maps to `NoRetryUntil StateChanges` by default, because AIP-194 calls it generally non-retryable unless the cause is not quota (`SS:AIP194-GenerallyNonRetryable-RESOURCE_EXHAUSTED`). The Refusal table then refines it to `RetryAfterDelay` for rate limiting and `SeparateUserAction` for storage. AIP-194 also lists `UNAUTHORIZED` (`SS:AIP194-GenerallyNonRetryable-UNAUTHORIZED`), which is not a google.rpc.Code value, so it gets no constructor.

## The per-file state machine

### State

```
data File = File
  { meta        :: Meta            -- fileId, uploadId, opName, owner, createdMono, limits
  , life        :: Life
  , epoch       :: Nat             -- fencing token; bumped every time new async work starts
  , outstanding :: Outstanding     -- the single slot for async work
  , restarts    :: Window          -- OTP restart timestamps for this file's server-driven work
  , opOutcome   :: Maybe (Either Fault ())  -- set once when CREATING ends, never changed again
  , opDeleted   :: Bool
  }

data Life
  = Creating Transfer
  | Active   Receipt Length WallTime                 -- refinement: size receipt == length
  | Failed   Fault Cleanup
  | Cancelled Cleanup
  | Deleting Receipt Length
  | Deleted  MonoTime                                -- tombstone since

data Transfer = Transfer
  { source          :: Source        -- FromClient | FromUrl Url (Maybe StrongETag)
  , phase           :: Phase         -- Opening | Receiving | Finalizing | Probing After
  , storeUpload     :: Maybe UploadRef
  , parts           :: Parts         -- refinement: numbered 1..k, every part has size P
  , offset          :: Nat           -- refinement: offset == P * length parts (until the final part)
  , declared        :: Maybe Nat     -- refinement: offset <= declared; set once, never changed
  , cancelRequested :: Bool
  , deadline        :: MonoTime      -- upload max-age end, or import deadline
  , finalizeBy      :: Maybe MonoTime
  , advertised      :: Maybe Nat     -- ghost: the last Upload-Offset we sent
  }

data After = AfterCompletedNoReceipt | AfterKeyExists | AfterNoSuchUpload | AfterAmbiguous

data Outstanding
  = Idle
  | Appending Epoch ReqId PartNo Bool          -- client body being received into the mover buffer
  | Storing   Epoch ReqId PartNo Nat Bool      -- that buffer is being stored as part PartNo
  | Fetching  Epoch                            -- import mover alive
  | Calling   Epoch StoreCall
  | Waiting   Epoch MonoTime Next              -- backoff before reissuing Next

data Cleanup = Cleanup [CleanupStep]            -- empty means done
data CleanupStep = AbortUpload UploadRef | ListUploadParts UploadRef | DeleteContent
```

The draft separates "the resource targeted by this initial request" from the upload resource (`UP:RESUMABLE-UPLOAD-13-4.2.2-3`). Here the File is the targeted resource and `uploadId` names the upload resource. They are 1:1 (`UP:RESUMABLE-UPLOAD-13-4-2`), but the ids differ so that the upload URI can be unguessable without making file ids unguessable too (`UP:RESUMABLE-UPLOAD-13-13-1`). Ids come from the shell inside the creation event, since a pure core has no randomness.

The operation is not stored separately. `operationOf :: File -> Operation` is a projection: `InProgress meta` while `opOutcome` is Nothing, `Done meta (Left fault)` or `Done meta (Right file)` once it is set. That is the shape `SS:LRO-Operation-result` describes ("If `done` == `false`, neither `error` nor `response` is set. If `done` == `true`, exactly one of `error` or `response` can be set.").

### Events

Every event carries `Env { mono, wall, access, retryAllowed, quotaRemaining }`. `access` is the shell's evaluation of the requester's credentials and policy for the target: `NoCredentials | InvalidCredentials | Insufficient | Allowed`. `retryAllowed` comes from the World's token bucket.

| Event | From | Fields |
|---|---|---|
| `CreateUpload` | client POST | ids, owner, `Maybe UploadLength`, `UploadComplete`, `Maybe ContentLength`, has content |
| `CreateImport` | client POST | ids, owner, url |
| `Append` | client PATCH | reqId, `UploadOffset`, `UploadComplete`, `Maybe UploadLength`, `Maybe ContentLength` |
| `OffsetQuery` | client HEAD | reqId |
| `RequestCancel` | client DELETE on the upload, or CancelOperation | reqId, which entry point |
| `GetFile`, `GetContent`, `DeleteFile` | client | reqId, method, conditionals, range |
| `GetOperation`, `DeleteOperation` | client | reqId |
| `Options` | client OPTIONS | reqId |
| `BodyReceived e n` / `BodyBroken e why` | mover (append) | epoch, bytes buffered, `Exceeded \| Interrupted` |
| `PartResult e r` | mover | epoch, `PartStored ETag \| PartFailed StoreError` |
| `OriginReplied e o` | mover (import) | epoch, `OriginReply { status, strongETag, length, retryAfter, contentRangeStart }` |
| `ImportPart e n bytes etag` | mover (import) | epoch, part number, size, etag |
| `FetchEnded e how` | mover (import) | epoch, `Eof Framing \| Interrupted`, plus the owner's re-evaluated access |
| `MoverExited e why` | shell | epoch, `Normal \| Shutdown \| Abnormal` (OTP exit reasons) |
| `StoreReplied e o` | shell | epoch, `StoreOutcome` |
| `Tick` | shell timer | nothing but Env |

`Framing` is `LengthDelimited Nat | ChunkedEnd | CloseDelimited`.

### Commands

| Command | Meaning |
|---|---|
| `Reply ReqId Response` | answer a waiting request |
| `Abandon ReqId` | close a request's connection without a response (`UP:RESUMABLE-UPLOAD-13-4.6-5`) |
| `StartAppend Epoch ReqId PartNo MaxBytes` | let the shell read the request body into a buffer of at most MaxBytes |
| `StorePart Epoch PartNo` / `DiscardPart Epoch` | store the buffered body as part PartNo, or drop it |
| `StartFetch Epoch Url (Maybe (Offset, StrongETag))` | start an import mover, resuming with Range and If-Range when given |
| `StopMover Epoch` | terminate the mover running under that epoch |
| `Store Epoch StoreCall` | make one store call and report its outcome tagged with the epoch |
| `SetTimer MonoTime` | ask for a `Tick` at or after that time |
| `Alert Fault` or `Alert Leak` | surface something an operator has to see (`SS:ABSL-STATUS-kDataLoss`, `SS:AIP194-GenerallyNonRetryable-INTERNAL`) |

### Guards that run before every row

These run in order, and the first that applies wins.

1. **Stale report.** If an event from a mover or the store carries an epoch different from `epoch`, or the outstanding slot is not waiting for that kind of report, the file is unchanged. A stale mover report emits `StopMover e` and a stale store report emits nothing. (`UP:RESUMABLE-UPLOAD-13-4.6-3`, `UP:RESUMABLE-UPLOAD-13-4.6-4`, `SS:GRPC-STATUSCODES-ABORTED`, `SS:AIP151-Parallel-3`, and the tusd lock handover in `UP:TUSD-2.10.1-lockUpload-1`.)
2. **Access.** On a client request, `NoCredentials` and `InvalidCredentials` reply `NoCredentials` or `BadCredentials` (401), and `Insufficient` replies `Forbidden` (403). Nothing else is evaluated first, not existence, not state, not preconditions (`SS:AIP193-PermissionDenied-1`: "Permission **must** be checked prior to checking if the resource or parent exists"; `DO:RFC4918-8.1-1`; `DO:RFC4918-8.5-1`; `SS:AIP154-Guidance-3`). This guard settles the 401-versus-403-versus-hidden-404 choice that RFC 9110 leaves open (`HS:RFC9110-15.5.4-4`): AIP-193 makes it a MUST that permission comes first, so we never use the 404 disguise.
3. **Deadline.** If the file is `Creating` in phase `Opening` or `Receiving` and `mono >= deadline`, row X1 runs before anything else.
4. **Deleted operation.** `GetOperation` on a file with `opDeleted` replies 404.

### Transition table

`e+` means "bump `epoch` and use the new value". "retry N" means: call `addRestart` on `restarts`. If that returns `ok` and `retryAllowed` holds, the slot becomes `Waiting e+ (mono + delay) N` and the core emits `SetTimer`, where `delay` is the gRFC A6 backoff or the server's pushback. Otherwise the transfer fails with the fault named in the row. "Clean[A,D,L]" sets `Cleanup` to abort the store upload, delete the content key, then list parts (and similarly for subsets).

**Creation** (no file yet; these run in `Core.World` and then hand over to `stepFile`)

| # | Event and guard | Result | Commands | Statements |
|---|---|---|---|---|
| C1 | CreateUpload, id already known (including tombstones) | no file | Reply `Internal DuplicateId` | `UP:RESUMABLE-UPLOAD-13-4-4` |
| C2 | CreateUpload, owner already has `maxCreating` files in CREATING | no file | Reply `RateLimited` | `UP:RESUMABLE-UPLOAD-13-13-8`, `HS:RFC6585-4-1` |
| C3 | CreateUpload, declared length > maxSize | no file | Reply `ExceedsMaxSize` | `UP:RESUMABLE-UPLOAD-13-4.1.4-3`, `UP:TUS-1.0.0-Creation.Requests.POST-7` |
| C4 | CreateUpload, declared length > quotaRemaining | no file | Reply `InsufficientStorage` | `HS:RFC4918-11.5-1` |
| C5 | CreateUpload, complete with total length 0 | no file | Reply `NotImplemented` | `HS:RFC9110-15.6.2` (open question 5) |
| C6 | CreateUpload, otherwise | Creating, Opening, deadline = mono + maxAge; creation reply held | `Store e+ CreateMultipartUpload` | `UP:RESUMABLE-UPLOAD-13-4.2.2-5`, `PD:S3API-CreateMultipartUpload-API_CreateMultipartUpload-1` |
| C7 | CreateImport, guards C1, C2, C4 | as C1..C4 | as C1..C4 | as above |
| C8 | CreateImport, otherwise | Creating, Opening, deadline = mono + importDeadline | `Store e+ CreateMultipartUpload`; Reply 202 with the operation | `SS:AIP151-Guidance-1`, `HS:RFC9110-15.3.3-1`, `HS:RFC9110-15.3.3-3` |

**Opening** (slot `Calling e CreateMultipartUpload`)

| # | Event and guard | Result | Commands | Statements |
|---|---|---|---|---|
| O1 | StoreReplied `Opened ref`, client source, creation had no content | Receiving, Idle | Reply 201 with Location, Upload-Offset 0, Upload-Limit, Upload-Complete: ?0 | `UP:RESUMABLE-UPLOAD-13-4.2.2-5`, `UP:RESUMABLE-UPLOAD-13-4.2.1-8` |
| O2 | StoreReplied `Opened ref`, client source, creation had content | Receiving, then U1..U5 applied to the creation request as its first append | as U5 | `UP:RESUMABLE-UPLOAD-13-4.2.2-11` |
| O3 | StoreReplied `Opened ref`, URL source, not cancelRequested | Receiving, `Fetching e+` | `StartFetch e+ url Nothing` | `DO:TES-tesInput.url-1` |
| O4 | StoreReplied `Opened ref`, cancelRequested | Cancelled, Clean[A,L]; outcome Left Cancelled | `Store e+ AbortMultipartUpload` | `SS:LRO-CancelOperation-3` |
| O5 | StoreReplied `StoreFailed` with Transient, Throttling or Timeout | retry CreateMultipartUpload, else Failed Unavailable | as retry; on failure Reply `refuseNow` | `PD:AWSSDK-RETRY-error-classification-1`, `SS:OTP-SUPERVISOR-Intensity` |
| O6 | StoreReplied `StoreFailed` with NonRetryable | Failed (FInternal StoreRefusedUs), no cleanup | Reply `Internal`; Alert | `SS:AIP194-GenerallyNonRetryable-INTERNAL` |
| O7 | RequestCancel (only reachable for imports) | cancelRequested := True | Reply 200 | `SS:LRO-CancelOperation-1` |

**Receiving, client upload**

| # | Slot | Event and guard | Result | Commands | Statements |
|---|---|---|---|---|---|
| U1 | Idle | Append, provided offset /= offset | unchanged | Reply `OffsetMismatch offset provided` | `UP:RESUMABLE-UPLOAD-13-4.4.2-3`, `UP:TUS-1.0.0-Core.Requests.PATCH-2` |
| U2 | Idle | Append, length indicators disagree with each other, with `declared`, or with `offset` | unchanged | Reply `InconsistentLength` | `UP:RESUMABLE-UPLOAD-13-4.1.3-3`, `UP:RESUMABLE-UPLOAD-13-4.1.3-6`, `UP:TUSD-2.10.1-getIETFDraftUploadLength-1`, `UP:TUSD-2.10.1-PatchFile-5` |
| U3 | Idle | Append, new declared length > maxSize | unchanged | Reply `ExceedsMaxSize` | `UP:RESUMABLE-UPLOAD-13-4.1.4-3` |
| U4 | Idle | Append with Content-Length > P, or < P without completion | unchanged | Reply `AppendTooLarge` or `AppendTooSmall` | `UP:RESUMABLE-UPLOAD-13-4.1.4-5`, `UP:RESUMABLE-UPLOAD-13-4.1.4-6` |
| U5 | Idle | Append, otherwise | `declared` set if newly known; `Appending e+ req (offset/P + 1) c` | `StartAppend e+ req part (min P (declared - offset))` | `UP:RESUMABLE-UPLOAD-13-4.4.2-7`, `UP:RESUMABLE-UPLOAD-13-4.2.2-6` |
| U6 | Appending or Storing e | Append | previous append terminated; then U1..U5 | `StopMover e`, `Abandon oldReq`, then as U1..U5 | `UP:RESUMABLE-UPLOAD-13-4.6-4`, `UP:RESUMABLE-UPLOAD-13-4.6-5` |
| U7 | Idle | OffsetQuery | `advertised := offset` | Reply 204 with Upload-Offset, Upload-Complete: ?0, Upload-Limit, Upload-Length if declared, Cache-Control: no-store | `UP:RESUMABLE-UPLOAD-13-4.3.2-1`, `UP:RESUMABLE-UPLOAD-13-4.3.3-1` |
| U8 | Appending or Storing e | OffsetQuery | Idle, then U7 | `StopMover e`, `Abandon oldReq`, then U7 | `UP:RESUMABLE-UPLOAD-13-4.6-4` |
| U9 | Appending e | BodyReceived e n, valid: n == P and not completing, or completing with n <= P and offset + n consistent with `declared`, and n == 0 only when completing and offset > 0 | `Storing e req part n c` | `StorePart e part` | `UP:RESUMABLE-UPLOAD-13-4.4.1-3`, `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-4` |
| U9z | Appending e | BodyReceived e 0, completing, offset > 0 | goes straight to U14 with no new part | as U14 | `UP:RESUMABLE-UPLOAD-13-4.4.1-3` |
| U10 | Appending e | BodyReceived e n, n < P and not completing | Idle | `DiscardPart e`; Reply `AppendTooSmall` | `UP:RESUMABLE-UPLOAD-13-4.1.4-6` |
| U11 | Appending e | BodyBroken e Exceeded, where the limit that tripped was `declared - offset` | Failed OutOfRange, Clean[A,L]; the upload resource is invalid | `DiscardPart e`; Reply `OffsetPastLength`; `Store e+ AbortMultipartUpload` | `UP:RESUMABLE-UPLOAD-13-4.4.2-7`, `UP:TUSD-2.10.1-writeChunk-1` |
| U12 | Appending e | BodyBroken e Exceeded, where the limit that tripped was P | Idle | `DiscardPart e`; Reply `AppendTooLarge` | `UP:RESUMABLE-UPLOAD-13-4.1.4-18`, `UP:TUSD-2.10.1-bodyReader.Read-2` |
| U13 | Appending e | BodyBroken e Interrupted | Idle | `DiscardPart e`; `Abandon req` | `UP:RESUMABLE-UPLOAD-13-4.4.2-2` (we keep nothing of a partial part; see below) |
| U14 | Storing e, completing | PartResult e PartStored etag | parts ++ [(part, n, etag)]; offset += n; declared := offset; Finalizing; finalizeBy := mono + finalizeBudget; outcome stays Nothing | `Store e+ CompleteMultipartUpload parts offset`; Reply 202 with Upload-Complete: ?1 and the operation; throttle success | `UP:RESUMABLE-UPLOAD-13-4.4.2-4`, `UP:RESUMABLE-UPLOAD-13-13-6`, `HS:RFC9110-15.3.3-1` |
| U15 | Storing e, not completing | PartResult e PartStored etag | parts ++ [(part, P, etag)]; offset += P; Idle; advertised := offset | Reply 204 (201 if the request was the creation request) with Upload-Complete: ?0, Upload-Offset; throttle success | `UP:RESUMABLE-UPLOAD-13-4.1.1-6`, `UP:RESUMABLE-UPLOAD-13-4.4.2-5`, `UP:RESUMABLE-UPLOAD-13-4.4.3-1` |
| U16 | Storing e | PartResult e PartFailed (Transient, Throttling, Timeout or ConnectionLost) | Idle; offset unchanged | Reply `StoreUnavailable hint`; throttle failure | `UP:RESUMABLE-UPLOAD-13-4.7-5`, `PD:S3UG-MPU-mpu-process-2` |
| U17 | Storing e | PartResult e PartFailed NoSuchUpload | Failed FDataLoss, Clean[] | Reply `DataLoss`; Alert | `PD:S3API-UploadPart-API_UploadPart-1` |
| U18 | Storing e | PartResult e PartFailed NonRetryable | Idle; offset unchanged | Reply `Internal StoreRefusedUs`; Alert | `SS:AIP194-GenerallyNonRetryable-INTERNAL` |
| U19 | Idle | RequestCancel | Cancelled, Clean[A,L]; outcome Left Cancelled | `Store e+ AbortMultipartUpload`; Reply 204 (DELETE) or 200 (CancelOperation) | `UP:RESUMABLE-UPLOAD-13-4.5.2-1`, `HS:RFC9110-9.3.5-3`, `SS:LRO-CancelOperation-3` |
| U20 | Appending or Storing e | RequestCancel | as U19 | `StopMover e`, `Abandon req`, then as U19 | `UP:RESUMABLE-UPLOAD-13-4.5.2-2` |

The draft says that when an append is interrupted, the server SHOULD keep the longest prefix it can (`UP:RESUMABLE-UPLOAD-13-4.4.2-2`). U13 deliberately doesn't. A store part is all-or-nothing (`PD:S3API-Error-IncompleteBody-1`), and keeping a short non-final part would break the plan that T20 proves. The MUST in that same statement, that the upload is not complete, still holds.

**Receiving, URL import**

| # | Slot | Event and guard | Result | Commands | Statements |
|---|---|---|---|---|---|
| I1 | Fetching e | OriginReplied, `originDecision` = Proceed | record strong ETag (only when strong) and complete length | none | `HS:RFC9110-8.8.1-6`, `HS:RFC9110-14.4-1` |
| I2 | Fetching e | OriginReplied 200 to a resumed fetch, or 206 whose start /= offset | parts := [], offset := 0; keep fetching the new full body | none | `HS:RFC9110-13.1.5-6`, `HS:RFC9110-14.2-1` |
| I3 | Fetching e | OriginReplied, `originDecision` = RetryAfter d | retry Fetch with pushback d, else Failed Unavailable, Clean[A,L] | `StopMover e`; as retry | `HS:RFC9110-15.6.4-2`, `HS:RFC6585-4-2`, `SS:GRFC-A6-Pushback-3` |
| I4 | Fetching e | OriginReplied, `originDecision` = Fail status | Failed (UpstreamRefused status), Clean[A,L] | `StopMover e`; `Store e+ AbortMultipartUpload` | `HS:RFC4918-11.5-2`, `SS:AIP194-NonRetryable-0` |
| I5 | Fetching e | ImportPart e n bytes etag, n == length parts + 1 and bytes == P | parts ++, offset += P; throttle success | none | `PD:S3UG-MPU-mpu-process-2` |
| I6 | Fetching e | ImportPart outside the plan | Failed (FInternal PlanViolated), Clean[A,L] | `StopMover e`; Alert | `PD:S3API-Error-InvalidPartOrder-1` |
| I7 | Fetching e | FetchEnded (Eof (LengthDelimited len)) with offset (after the final short part) == len, or Eof ChunkedEnd; re-checked access Allowed | declared := offset; Finalizing | `Store e+ CompleteMultipartUpload parts offset` | `HS:RFC9110-6.1-2`, `HS:RFC9110-8.6-7` |
| I8 | Fetching e | FetchEnded Eof, re-checked access not Allowed | Failed Revoked, Clean[A,L] | `Store e+ AbortMultipartUpload` | `UP:RESUMABLE-UPLOAD-13-13-6`, `UP:RESUMABLE-UPLOAD-13-13-7` |
| I9 | Fetching e | FetchEnded (Eof CloseDelimited), FetchEnded Eof with a length mismatch, FetchEnded Interrupted, or MoverExited Abnormal | retry Fetch, resuming from (offset, strong ETag) only when both exist and offset > 0, otherwise from 0 with parts := []; on failure Failed Unavailable, Clean[A,L] | as retry | `HS:RFC9110-6.1-1`, `HS:RFC9110-6.1-3`, `SS:OTP-SUPERVISOR-ChildSpec-restart` |
| I10 | Fetching e | MoverExited Normal without FetchEnded | Failed (FInternal Contradiction), Clean[A,L] | Alert | `SS:OTP-SUPERVISOR-code-do_restart` |
| I11 | Waiting e t (Fetch) | Tick with mono >= t | `Fetching e+` | `StartFetch e+ url resume` | `SS:GRFC-A6-Backoff` |
| I12 | any | RequestCancel | Cancelled, Clean[A,L] | `StopMover e` if fetching; `Store e+ AbortMultipartUpload`; Reply 200 | `SS:LRO-CancelOperation-3` |

**Finalizing** (slot `Calling e CompleteMultipartUpload`, or `Waiting` before a re-issue)

| # | Event and guard | Result | Commands | Statements |
|---|---|---|---|---|
| F1 | StoreReplied `Completed (Just rep)`, `parseReceipt` is Right r, `size r == declared` | Active r; outcome Right; throttle success | none | `PD:S3UG-INTEGRITY-UPLOAD-checking-object-integrity-upload-1`, `PD:S3UG-MPU-mpuchecksums-1` |
| F2 | StoreReplied `Completed (Just rep)`, not a receipt or wrong size | Failed (FInternal ObjectWithoutChecksum) or FDataLoss, Clean[D] | `Store e+ DeleteObject`; Alert | `PD:S3UG-MPU-mpuAndPermissions-1`, `PD:S3UG-MPU-mpuAndPermissions-2` |
| F3 | StoreReplied anything else: `Completed Nothing`, `KeyExists`, `NoSuchUpload`, `StoreFailed _` | Probing (After from the outcome) | `Store e+ HeadObject` | `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-2`, `PD:S3API-Error-NoSuchUpload-1`, `SS:RPC-CODE-DEADLINE_EXCEEDED-1`, `HS:RFC9110-9.2.2-4` |
| F4 | RequestCancel | cancelRequested := True | Reply 202 (DELETE) or 200 (CancelOperation) | `HS:RFC9110-9.3.5-3`, `SS:LRO-CancelOperation-1`, `SS:LRO-CancelOperation-2` |
| F5 | OffsetQuery | unchanged | Reply 204 with Upload-Complete: ?1, Upload-Offset = declared | `UP:TUS-1.0.0-Core.Requests.HEAD-1` |
| F6 | Append with offset == declared, completing, no content | unchanged | Reply 202 with Upload-Complete: ?1 and the operation (replaying the final response) | `UP:RESUMABLE-UPLOAD-13-4.4.2-6` |
| F7 | Append otherwise | unchanged | Reply `OffsetMismatch declared provided` | `UP:RESUMABLE-UPLOAD-13-4.1.2-6`, `UP:RESUMABLE-UPLOAD-13-4.1.2-1` |
| F8 | Waiting e t (Complete), Tick with mono >= t | `Calling e+ Complete` | `Store e+ CompleteMultipartUpload` | `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-3` |

**Probing** (slot `Calling e HeadObject`)

| # | Event and guard | Result | Commands | Statements |
|---|---|---|---|---|
| P1 | `Found (Just rep) sz`, receipt parses, sz == declared | Active; outcome Right, whether or not a cancel was requested | none | `SS:LRO-CancelOperation-2` |
| P2 | `Found` with no checksum, or with one that doesn't parse | Failed (FInternal ObjectWithoutChecksum), Clean[D] | `Store e+ DeleteObject`; Alert | `PD:S3UG-MPU-mpuAndPermissions-1`, `PD:S3UG-MPU-mpuAndPermissions-2` |
| P3 | `Found _ sz`, sz /= declared | Failed FDataLoss, Clean[D] | `Store e+ DeleteObject`; Alert | `PD:S3API-CompleteMultipartUpload-request-header-MpuObjectSize-1` |
| P4 | `Absent`, After = NoSuchUpload | Cancelled with Clean[] if cancelRequested, else Failed FDataLoss with Alert | as stated | `PD:S3API-Error-NoSuchUpload-1`, `PD:S3UG-MPU-LIFECYCLE-mpu-abort-incomplete-mpu-lifecycle-config-1` |
| P5 | `Absent`, After = CompletedNoReceipt or KeyExists | Failed (FInternal Contradiction), Clean[A,L] | Alert | `PD:S3UG-MPU-distributedmpupload-2` |
| P6 | `Absent`, After = Ambiguous, cancelRequested | Cancelled, Clean[A,D,L] | `Store e+ AbortMultipartUpload` | `SS:LRO-CancelOperation-3` |
| P7 | `Absent`, After = Ambiguous, mono < finalizeBy | retry Complete | as retry | `HS:RFC9110-9.2.2-4` ("some means to detect that the original request was never applied") |
| P8 | `Absent`, After = Ambiguous, mono >= finalizeBy or retry refused | Failed Expired or Unavailable, Clean[A,D,L] | `Store e+ AbortMultipartUpload` | `SS:GRFC-A6-MaxAttempts-2` |
| P9 | `StoreFailed _` from the probe | retry HeadObject, else Failed Unavailable, Clean[A,D,L] with Alert, because the outcome is unknown | as retry | `SS:OTP-SUPERVISOR-code-restart-escalate` |
| P10 | RequestCancel | cancelRequested := True | Reply 202 or 200 | `HS:RFC9110-9.3.5-3` |

**Cleanup** (Life is Failed or Cancelled and the step list is not empty)

| # | Event and guard | Result | Commands | Statements |
|---|---|---|---|---|
| K1 | Abort replied `Aborted` or `NoSuchUpload` | next step | `Store e+ next` | `PD:S3API-AbortMultipartUpload-API_AbortMultipartUpload-1` |
| K2 | ListParts replied `PartsListed 0` or `NoSuchUpload` | next step | `Store e+ next` or done | `PD:S3API-AbortMultipartUpload-API_AbortMultipartUpload-2` |
| K3 | ListParts replied `PartsListed n`, n > 0 | steps := Abort : ListParts : rest | `Store e+ AbortMultipartUpload` | `PD:S3API-AbortMultipartUpload-API_AbortMultipartUpload-1`, `PD:S3UG-MPU-mpu-process-4` |
| K4 | DeleteObject replied `Removed` | next step | as K1 | `HS:RFC9110-9.2.2-1` |
| K5 | any step `StoreFailed` that is retryable, with retry allowed | `Waiting e+ t step` | `SetTimer` | `SS:GRFC-A6-Backoff` |
| K6 | any step `StoreFailed` that is NonRetryable, or retry refused | drop the step; the store-side lifecycle rule is the backstop | `Alert Leak` | `PD:S3UG-MPU-LIFECYCLE-mpu-abort-incomplete-mpu-lifecycle-config-1` |
| K7 | upload-resource request (Append, OffsetQuery, RequestCancel) | unchanged | Reply `refuseEnded` (410) | `UP:RESUMABLE-UPLOAD-13-4.1.1-9`, `UP:TUS-1.0.0-Termination.Requests.DELETE-1` |
| K8 | GetContent | unchanged | Reply `NotFound` | `HS:RFC9110-15.5.5-1` |
| K9 | DeleteFile | Deleted mono; any remaining cleanup steps continue | Reply 204 | `HS:RFC9110-9.3.5-3` |

**Active, Deleting, Deleted**

| # | Life | Event and guard | Result | Commands | Statements |
|---|---|---|---|---|---|
| A1 | Active | GetContent | unchanged | Reply from `Http.Conditional` then `Http.Range`: 200, 206, 304, 412 or 416, with ETag, Last-Modified, Content-Length, Accept-Ranges: bytes, and the object stream | `HS:RFC9110-13.2.2-1`..`-7`, `HS:RFC9110-14.2-7`, `HS:RFC9110-15.3.1-2`, `HS:RFC9110-14.3-1` |
| A2 | Active | GetFile | unchanged | Reply 200 with the FileView | `SS:AIP151-StandardMethods-1` |
| A3 | Active | DeleteFile, preconditions pass | Deleting; outstanding `Calling e+ DeleteObject` | `Store e+ DeleteObject`; Reply 202 | `HS:RFC9110-9.3.5-3` |
| A4 | Active | DeleteFile, preconditions fail | unchanged | Reply `PreconditionFailed` | `HS:RFC9110-13.1.1-5`, `HS:RFC9110-13.2.2-2` |
| A5 | Active | RequestCancel | unchanged | Reply 204 (DELETE deactivates an already complete upload resource) or 200 (CancelOperation on a done operation) | `UP:RESUMABLE-UPLOAD-13-4-3`, `SS:LRO-CancelOperation-1`; Funnel `server/tes.go:225-245` |
| A6 | Active | OffsetQuery, Append | as F5, F6, F7 | as F5, F6, F7 | as F5, F6, F7 |
| D1 | Deleting | StoreReplied `Removed` | Deleted mono; throttle success | none | `DO:RFC4918-9.6-3` |
| D2 | Deleting | StoreReplied `StoreFailed` retryable | retry DeleteObject; if refused, stay Deleting, Idle, with Alert | as retry | `SS:AIP216-Active-3` |
| D3 | Deleting | StoreReplied `StoreFailed` NonRetryable | stay Deleting, Idle | Alert | `SS:AIP194-GenerallyNonRetryable-INTERNAL` |
| D4 | Deleting | GetContent, GetFile, DeleteFile | unchanged | Reply `NotFound`, 200 with state DELETING, or 202 again | `HS:RFC9110-15.5.5-1`, `HS:RFC9110-9.3.5-3` |
| Z1 | Deleted | any file or upload request except DeleteFile | unchanged | Reply `Gone` | `HS:RFC9110-15.5.11-1`, `DO:RFC4918-9.6-3` |
| Z2 | Deleted | DeleteFile | unchanged | Reply 204 | `HS:RFC9110-9.2.2-3` |
| Z3 | Deleted | Tick with mono >= since + tombstoneHorizon | the World forgets the file and its upload and operation ids; later requests get 404 | none | `HS:RFC9110-15.5.11-3` |

**Deadline and operation rows**

| # | Event and guard | Result | Commands | Statements |
|---|---|---|---|---|
| X1 | any event or Tick, Creating in Opening or Receiving, mono >= deadline | Failed Expired; Clean[A,L] when a store upload ref exists; outcome Left Expired | `StopMover e` if a mover is running; `Abandon` a held request; Alert none | `UP:RESUMABLE-UPLOAD-13-4.1.4-7`, `UP:TUS-1.0.0-Expiration-1`, `UP:TUS-1.0.0-Expiration.Example-1` |
| X2 | Tick in Finalizing or Probing with mono >= finalizeBy | no new Complete is issued (P7 becomes P8); an outstanding call is left to answer | none | `PD:S3UG-MPU-LIFECYCLE-mpu-abort-incomplete-mpu-lifecycle-config-2` |
| OP1 | GetOperation | unchanged | Reply 200 with `operationOf f` | `SS:LRO-GetOperation`, `SS:LRO-Operation-done` |
| OP2 | DeleteOperation | opDeleted := True; life unchanged | Reply 204 | `SS:LRO-DeleteOperation` |
| OP3 | Tick, opOutcome set and mono >= doneAt + opRetention | opDeleted := True | none | `SS:AIP151-Expiration-1`, `SS:AIP151-Expiration-2` |
| OPT | Options | unchanged | Reply 204 with Upload-Limit | `UP:RESUMABLE-UPLOAD-13-4.1.4-13` |

Every `(Life, Outstanding, Event)` combination that no row names has a default. A client request gets the Refusal that the life implies (`NotFound` for content of a non-ACTIVE file, `OperationInProgress` for DeleteFile while CREATING per `SS:AIP151-Parallel-2`, `Gone` once deleted), and a report from a mover or the store is handled by guard 1. The default is written as one function, `defaultFor :: Life -> FileEvent -> Step`, so GHC's exhaustiveness checker sees every pair.

### Supervision, backoff and throttling

We only supervise server-driven work: import fetches and the store calls the core makes (Create, Complete, HeadObject, Abort, ListParts, DeleteObject). Client appends are driven by the client, which retries with the draft's own heuristics (`UP:RESUMABLE-UPLOAD-13-4.7-1`..`-7`). The core's job there is to stay truthful about the offset, not to retry on the client's behalf.

- **Restart decision** (`Supervise.Restart`) ports OTP `do_restart` (`SS:OTP-SUPERVISOR-code-do_restart`) as a total function over `RestartType = Permanent | Transient | Temporary` and `ExitReason = Normal | Shutdown | ShutdownWith | Abnormal`. Every mover and every store call is `Transient`, which means it is restarted only on an abnormal exit (`SS:OTP-SUPERVISOR-ChildSpec-restart`). Each file has a single job at a time, so the strategy is always `one_for_one` (`SS:OTP-SUPERVISOR-Strategy-one_for_one`) and the other strategies aren't ported.
- **Restart intensity** (`Supervise.Intensity`) ports `add_restart` and `can_restart` (`references/status-and-supervision/otp/supervisor.erl:2265-2295`, `SS:OTP-SUPERVISOR-code-add_restart-1`, `SS:OTP-SUPERVISOR-code-add_restart-2`). Intensity 0 terminates at once. Otherwise a restart is allowed only if fewer than MaxR restarts fall inside the last MaxT seconds. When intensity is exceeded, the transfer ends with the Fault of the last failure, which is OTP's `{shutdown, _}` escalation (`SS:OTP-SUPERVISOR-code-restart-escalate`, `SS:OTP-SUPPRINC-MaxIntensity-2`). The `Window` type keeps at most MaxR timestamps, sorted descending, so it can't grow without bound.
- **Backoff and pushback** (`Retry.Backoff`) port gRFC A6: attempt `n` waits `min(initialBackoff * multiplier^(n-1), maxBackoff)`, and jitter is the shell's job (`SS:GRFC-A6-Backoff`). A server delay (a Retry-After from an origin, or the store's hint) replaces the computed delay once, and the next computed delay starts again from `initialBackoff` (`SS:GRFC-A6-Pushback-3`). A negative or unparseable pushback means do not retry (`SS:GRFC-A6-Pushback-2`). The AWS SDK clamps `x-amz-retry-after` differently (`PD:AWSSDK-RETRY-server-directed-retry-timing-1`). I picked A6 so there is one delay rule, and the divergence is open question 11.
- **Throttling** (`Retry.Throttle`, applied in `Core.World`) ports the A6 token bucket, with one bucket for the store. The token count stays in `[0, maxTokens]`. A retryable failure subtracts 1 and a success adds `tokenRatio`, scaled to an integer number of milli-tokens. While the count is at or below `maxTokens/2`, `retryAllowed` is False (`SS:GRFC-A6-Throttling-1`, `SS:GRFC-A6-Throttling-2`). Only retryable failures count, so a malformed request can't drain the bucket (`SS:GRFC-A6-Throttling-3`). First attempts are never throttled, only retries, so new successes can still refill the bucket after an outage. Import origins get no bucket, because one bucket per origin host would itself be an unbounded map. They are bounded by per-file intensity and the import deadline instead.
- **The total bound** is the transfer's deadline, as in gRPC, where the call deadline applies across all attempts (`SS:GRFC-A6-MaxAttempts-2`). Intensity alone isn't enough, because once backoff reaches its cap, MaxR restarts may never fall inside MaxT and retries would go on forever. A6's `maxAttempts` (`SS:GRFC-A6-Validation-1`) isn't ported as a second limiter, because the window plus the deadline already does its job, and two limiters on the same counter would be the kind of accidental difference we try to remove.

### Routing across files (`Core.World`)

```
data World = World
  { files :: Map FileId File, uploads :: Map UploadId FileId, ops :: Map OpName FileId
  , creatingByOwner :: Map Owner Nat, storeBucket :: Throttle }
step :: World -> WorldEvent -> (World, [Command])
```

`step` resolves the target id (rows C1..C8 for creation), computes `Env.retryAllowed` from `storeBucket`, calls `stepFile`, writes the file back, applies the returned throttle delta, and updates `creatingByOwner` by `fromEnum (isCreating after) - fromEnum (isCreating before)`. That subtraction is the only place the counter changes, so the counter equals the number of CREATING files per owner by construction. LiquidHaskell doesn't see into `Data.Map`, so the claim that "a step touches only its own file" is argued by construction (one `Map.insert` at one key) rather than machine-checked. I'd rather say that plainly than dress it up.

## What a client is told

Every response is a value of `Response { status :: Emittable, headers :: Headers, body :: Body }`, and the header rules are refinements on that record, so a response that breaks one doesn't compile.

| Endpoint | Outcomes | Headers carried | Statements |
|---|---|---|---|
| POST create upload | 201; 202 when the request completes the upload; Refusals C1..C5 | Location, Upload-Offset, Upload-Limit, Upload-Complete | `UP:RESUMABLE-UPLOAD-13-4.2.2-4`, `UP:RESUMABLE-UPLOAD-13-4.2.2-5`, `UP:RESUMABLE-UPLOAD-13-4.2.2-9` |
| PATCH append | 204 with ?0; 202 with ?1; 409, 400, 413, 410, 503, 500 | Upload-Offset, Upload-Complete, Upload-Limit on limit refusals | `UP:RESUMABLE-UPLOAD-13-4.4.2-3`, `UP:RESUMABLE-UPLOAD-13-4.4.2-4`, `UP:RESUMABLE-UPLOAD-13-4.4.2-5` |
| HEAD upload | 204 | Upload-Offset, Upload-Complete, Upload-Limit, Upload-Length if known, Cache-Control: no-store | `UP:RESUMABLE-UPLOAD-13-4.3.2-1` |
| DELETE upload | 204 when enacted, 202 while finalizing, 410 when already ended | none | `HS:RFC9110-9.3.5-3`, `UP:RESUMABLE-UPLOAD-13-4.5.2-1` |
| OPTIONS | 204 | Upload-Limit | `UP:RESUMABLE-UPLOAD-13-4.1.4-13` |
| POST import | 202 with the operation | Retry-After poll hint | `SS:AIP151-Guidance-1`, `DO:DRS-responses.202Accepted-1` |
| GET/HEAD file | 200 FileView; 404; 410 | ETag when ACTIVE | `SS:AIP151-StandardMethods-1` |
| GET/HEAD content | 200, 206, 304, 412, 416; 404 unless ACTIVE; 410 when DELETED | ETag, Last-Modified, Content-Length, Content-Range, Accept-Ranges, Repr-Digest only when allowed | `HS:RFC9110-13.2.2-1`, `HS:RFC9110-15.3.7.1`, `HS:RFC9110-15.4.5-2` |
| DELETE file | 202, 204, 409, 412, 410 | none | `HS:RFC9110-9.3.5-3`, `SS:AIP151-Parallel-2` |
| GET operation | 200; 404 once deleted or expired | none | `SS:LRO-GetOperation`, `SS:AIP151-Expiration-1` |
| CancelOperation | 200 | none | `SS:LRO-CancelOperation-1` |
| DELETE operation | 204 | none | `SS:LRO-DeleteOperation` |

For content of a CREATING file I chose 404 rather than DRS's 202 with Retry-After (`DO:DRS-responses.202Accepted-1`). The 404 is literally true, since there is "no current representation" (`HS:RFC9110-15.5.5-1`). A Retry-After would promise a time that depends on someone else's upload, which the core can't know. The file representation still shows CREATING, so nobody is misled.

Header rules, each a refinement on `Response`:

- **Retry-After** only appears on 202 (a poll hint, as in `DO:DRS-responses.202Accepted-1`), 413 when temporary, 429 or 503 (`HS:RFC9110-10.2.3-1`, `HS:RFC9110-15.5.14-3`, `HS:RFC6585-4-2`, `HS:RFC9110-15.6.4-2`). It is never on 507 (`HS:RFC4918-11.5-2`). We always write it as delay-seconds, a `Nat` (`HS:RFC9110-10.2.3-6`, `HS:RFC9110-10.2.3-7`), and never as an HTTP-date, which keeps clock skew out of it.
- **Upload-Offset** always equals the file's `offset` (or `declared` once complete). It is required on HEAD and on 409 (`UP:RESUMABLE-UPLOAD-13-4.3.2-1`, `UP:RESUMABLE-UPLOAD-13-4.4.2-3`), and on a 2xx with ?0 it matches the inferred offset (`UP:RESUMABLE-UPLOAD-13-4.1.1-6`).
- **Upload-Complete**: a request that sent ?1 never gets a 2xx with ?0 or with the header missing (`UP:RESUMABLE-UPLOAD-13-4.2.2-4`, `UP:RESUMABLE-UPLOAD-13-4.4.2-4`). A 409 for offset mismatch carries ?0 (`UP:RESUMABLE-UPLOAD-13-4.4.2-3`).
- **WWW-Authenticate** is present exactly on 401 (`HS:RFC9110-15.5.2-2`, `HS:RFC9110-11.6.1-1`). The challenge text is the shell's (open question 16).
- **Content-Length** is never on 204 (`HS:RFC9110-8.6-4`), and on 200 it equals the receipt's size (`HS:RFC9110-8.6-7`).
- **Content-Range** appears only on 206 and 416 (`HS:RFC9110-14.4-8`). It is required on a single-part 206 (`HS:RFC9110-15.3.7.1`), and it is never a multipart 206 for one range (`HS:RFC9110-15.3.7.2`).
- **Repr-Digest** appears only when the receipt's algorithm maps to an Active IANA key (`HS:RFC9530-3-1`, `HS:RFC9530-5-2`). Under the default store configuration that never happens (open question 3).
- **Problem bodies** are only sent for Refusals, never on HEAD (`HS:RFC9110-9.3.2-1`), with media type application/problem+json (`PD:RFC9457-3-1`) and the status copied from the response (`PD:RFC9457-3.1.2-2`).

`FileView` is a record of facts (`fileId`, `state :: ResourceState`, `length`, `etag`, `lastModified`, `operation`, `faultCode`), not a JSON layout. JSON field names would be vocabulary, and no vendored standard defines a file representation that carries both a state and a receipt (open question 7).

## Reference code we port, and what we fix on the way

| Source | Target | What we keep | What we fix or leave behind |
|---|---|---|---|
| Go net/http `references/http-semantics/code/go/fs.go:431-671` (`scanETag`, `etagStrongMatch`, `etagWeakMatch`, `checkIfMatch`, `checkIfUnmodifiedSince`, `checkIfNoneMatch`, `checkIfModifiedSince`, `checkIfRange`, `checkPreconditions`) | `Http.Conditional`, `Vocab.EntityTag` | the three-valued `condResult` and the order of the ladder | (a) we add an `AlreadySucceeded` outcome for the 13.1.1 and 13.1.4 MAY (`HS:RFC9110-13.1.1-6`, `HS:RFC9110-13.1.4-7`), used by DELETE on a deleted file; (b) an If-Range HTTP-date is never treated as strong, so a date If-Range is false and the full 200 is served (`HS:RFC9110-13.1.5-4`), where Go compares seconds; (c) the recipient is a one-constructor type `Origin`, which makes the "when recipient is the origin server" condition explicit (`HS:RFC9110-13.2.2-2`); (d) Range and If-Range are evaluated for GET only, where Go also does it for HEAD (`HS:RFC9110-14.2-2`, `HS:RFC9110-13.2.2-6`); (e) `If-Match: *` is true only when a current representation exists, where Go returns true unconditionally (`HS:RFC9110-13.1.1-4`); (f) `If-None-Match: *` is false only when a current representation exists (`HS:RFC9110-13.1.2-5`) |
| urllib3 `references/http-semantics/code/urllib3/retry.py:184-189, 308-333, 379-407` | `Retry.OnStatus`, used by `Import.Origin` | `DEFAULT_ALLOWED_METHODS` as `idempotent`; `RETRY_AFTER_STATUS_CODES = {413, 429, 503}`; the negative Retry-After clamp to 0 | we add 507 as never automatically repeated (`HS:RFC4918-11.5-2`), 421 as retryable on a new connection for any method (`HS:RFC9110-15.5.20-2`), 408 as repeatable (`HS:RFC9110-15.5.9-2`), and 500, 502 and 504 as transient for imports (`PD:SMITHY-TS-error-classification-constants-TRANSIENT_ERROR_STATUS_CODES-1`) |
| Go `references/http-semantics/code/go/request.go:1543-1557` (`isReplayable`) and `transport.go:756-800` (`shouldRetryRequest`) | `Vocab.Method.replayable`, `Retry.OnConnection` | nothing written means retry when the body can be rewound; replayable method plus a read error or idle close on a reused connection means retry; a fresh connection is never retried | the Idempotency-Key escape is dropped because it is not a standard (`HS:RFC9110-9.2.2-4`) |
| IANA `references/http-semantics/http-status-codes-1.csv`; http-types `Status.hs:783-830` for shape only | `Vocab.HttpStatus` (generated) | the 64 assigned rows and their registry phrases; class predicates | we don't take the pre-RFC 9110 phrases from http-types, Go or CPython |
| googleapis code.proto, grpc-gateway `HTTPStatusFromCode` (`SS:RPC-CODE-*-http`, `SS:GRPCGW-HTTPStatusFromCode-1`) | `Vocab.RpcCode` | numbers, names, HTTP mapping | the gateway's default branch (unknown code to 500) has nothing to port, because Code is closed |
| AIP-194 (`SS:AIP194-*`) with the guidelines in `SS:GRPC-STATUSCODES-FAILED_PRECONDITION-2` | `Retry.Recourse` | the partition of all 17 codes | `UNAUTHORIZED` is dropped because it isn't a Code |
| OTP `references/status-and-supervision/otp/supervisor.erl:2265-2295` (`add_restart`, `can_restart`) and `do_restart` (`SS:OTP-SUPERVISOR-code-do_restart`) | `Supervise.Intensity`, `Supervise.Restart` | the window logic and the restart table | we don't port the `?DIRTY_RESTART_LIMIT` shortcut, because it is a performance path with the same result; we don't port the strategies other than `one_for_one` |
| gRFC A6 (`SS:GRFC-A6-Backoff`, `SS:GRFC-A6-Throttling-1`..`-3`, `SS:GRFC-A6-Pushback-2`, `-3`) | `Retry.Backoff`, `Retry.Throttle` | formulas and bounds | jitter is the shell's; the core works in integer milli-tokens |
| aws-sdk-js-v3 `isChecksumWithPartNumber.ts` | `Store.Receipt` | the `-N`, 1..10000, no-leading-zero test | the middleware's silent skip of validation on GetObject (`PD:AWS-SDK-JS-flexibleChecksumsResponseMiddleware-flexibleChecksumsResponseMiddleware-1`) is the opposite of what we want: a composite value becomes `Left Composite`, never "skip" |
| S3 user guide table and Smithy enums (`PD:S3UG-INTEGRITY-UPLOAD-MultipartUploads-Checksums-1`, `PD:S3-SMITHY-com.amazonaws.s3#ChecksumType-1`) | `Store.Checksum` | the support relation | the at-rest page's contradiction is recorded, not followed |
| AWS SDK retry tables and smithy constants (`PD:AWSSDK-RETRY-error-classification-1`..`-4`, `PD:SMITHY-TS-*`) | `Store.Error` | code first, then status; transient, throttling, non-retryable | Smithy's acceptance of decimal Retry-After isn't ported, because delay-seconds is `1*DIGIT` (`HS:RFC9110-10.2.3-7`) |
| tusd `references/uploads/tusd/unrouted_handler.go:1562-1600` (`getIETFDraftUploadLength`), `:734-876` check order in `PatchFile` | `Upload.Length`; the order of rows U1..U5 | the two length indicators must match; a declared length below the offset is refused | we don't port tusd's 500 for timeouts and resets (`UP:TUSD-2.10.1-errors.ErrReadTimeout-2`), because it would misreport a client-side fault as a server error; we don't port 423 for a locked upload, because the draft's terminate-previous rule replaces locking |
| Funnel `server/tes.go:225-245` (`CancelTask` on a terminal task succeeds and does nothing) | rows A5, K7 | cancelling something already finished is not an error | Funnel's two transition functions aren't ported; the lesson we take from them is that there must be exactly one |

We don't port the CRC-64/NVME reference, the combine lemma, the WebDAV handlers or Funnel's HTTP-to-gRPC table. The first two compute digests, which the core must never do. WebDAV locking has no use case here. Funnel's table maps HTTP to Code in a server, which `SS:GRPC-HTTPMAP-scope-2` forbids.

## Theorem catalog

Each entry gives the claim, the statements it encodes, and how it is proved. "stepFile" always means the per-file function, and claims about it hold for every `Env`, `File` and `FileEvent`.

**T1. An unknown status keeps its class.** For every `s` in 100..599, `statusClass (fromWire s) == s / 100`, and `code (fromWire s)` is either `s` (when assigned) or `100 * (s / 100)`. Statements: `HS:RFC9110-15-1`, `HS:RFC9110-15-2`, `HS:RFC9110-15-4`. Method: refinement (already verified in the probe).

**T2. An invalid status is processed as 5xx.** For every Int `s` outside 100..599, `statusClass (fromAny s) == 5`. Statements: `HS:RFC9110-15-5`, `HS:RFC9110-15-6`. Method: refinement.

**T3. The status type is the registry.** The constructors of `Status` are exactly the 64 assigned rows of http-status-codes-1.csv, `code` is injective, and every phrase equals the registry's. Statements: `HS:IANA-HTTP-Status-Codes-*`. Method: construction (generated) plus exhaustion (64 x 64 injectivity, rows compared with the CSV by `tools/gen-vocab.py`).

**T4. Every emitted status is registered and final.** Every `Response` the core builds has a status in `Emittable`; in particular 1xx, 104, 306, 418, 510 and 499 are never emitted. Statements: `HS:RFC9110-15-7`, `HS:IANA-HTTP-Status-Codes-104`, `HS:IANA-HTTP-Status-Codes-452-499`, `SS:RPC-CODE-CANCELLED-http`. Method: refinement on the `status` field.

**T5. The Code table is the canonical one.** `codeNumber` is injective with image exactly {0..16}; `codeHttp` equals the code.proto mapping row by row; and `codeHttp` is not injective, with INVALID_ARGUMENT, FAILED_PRECONDITION and OUT_OF_RANGE all mapping to 400 as the witness. Statements: `SS:RPC-CODE-*-http`, `SS:GRPC-STATUSCODES-*`, `SS:ABSL-STATUS-sync`. Method: exhaustion (17 x 17).

**T6. One source for every error rendering.** For every Refusal `r`, the problem body's status equals the response status, and `codeHttp (refusalCode r) == refusalStatus r` except exactly for this listed set: Gone (410 vs 404), PreconditionFailed (412 vs 409), RangeNotSatisfiable (416 vs 400), AppendTooLarge and ExceedsMaxSize (413 vs 429), OffsetPastLength (413 vs 400), InsufficientStorage (507 vs 429). Statements: `PD:RFC9457-3.1.2-2`, `SS:GRPC-HTTPMAP-scope-2`, `SS:GRPCGW-HTTPStatusFromCode-412`, `SS:AIP154-Changelog-1`. Method: construction for the problem status; exhaustion over the Refusal constructor tags for the listed set.

**T7. Retry-After goes only where a standard puts it.** If a Response carries Retry-After, its status is 202, 413, 429 or 503; no 507 ever carries it; and its value is delay-seconds. Statements: `HS:RFC9110-10.2.3-1`, `HS:RFC9110-10.2.3-6`, `HS:RFC9110-10.2.3-7`, `HS:RFC9110-15.5.14-3`, `HS:RFC6585-4-2`, `HS:RFC9110-15.6.4-2`, `HS:RFC4918-11.5-2`, `DO:DRS-responses.202Accepted-1`. Method: refinement on `Response`.

**T8. Access is decided first.** For every client request event with access `NoCredentials` or `InvalidCredentials`, stepFile leaves the file unchanged and replies 401 with WWW-Authenticate; with `Insufficient`, it replies 403. Nothing about the file, the preconditions or the body affects the result. Statements: `HS:RFC9110-11.4-1`, `HS:RFC9110-11.4-2`, `HS:RFC9110-15.5.2-2`, `SS:AIP193-PermissionDenied-1`, `DO:RFC4918-8.1-1`, `DO:RFC4918-8.5-1`, `SS:AIP154-Guidance-3`. Method: refinement on stepFile.

**T9. The store and the origin never blame the person.** No `StoreOutcome` and no origin status (all of 100..599) leads to a 401 or 403 response or to a Fault with code UNAUTHENTICATED or PERMISSION_DENIED. The only Fault with PERMISSION_DENIED is `Revoked`, and it comes only from an event's own `access`. Statements: `HS:RFC9110-15.5.4-3`, `SS:GRPC-STATUSCODES-PERMISSION_DENIED-2`, `PD:S3API-Error-AccessDenied-1`, `PD:S3API-Error-InvalidAccessKeyId-1`. Method: exhaustion over `S3Code x RetryClass x StoreCall` and over `originDecision` on 100..599, plus a refinement on `Revoked`'s only construction site.

**T10. The precondition ladder is RFC 9110 13.2.2.** Over every combination of five headers (absent, true, false), method (GET, HEAD, other), Range present, a current representation existing, and already-applied: (a) If-Match false gives 412 unless already applied; (b) If-Unmodified-Since is ignored when If-Match is present; (c) If-None-Match false gives 304 for GET and HEAD and 412 otherwise; (d) If-Modified-Since is ignored when If-None-Match is present or the method is not GET or HEAD; (e) If-Range is ignored without Range and for HEAD; (f) a weak or date If-Range is false; (g) Range applies only when the result would otherwise be 200. Statements: `HS:RFC9110-13.2.2-1`..`-7`, `HS:RFC9110-13.1.1-4`, `HS:RFC9110-13.1.2-5`, `HS:RFC9110-13.1.2-6`, `HS:RFC9110-13.1.3-1`, `HS:RFC9110-13.1.3-2`, `HS:RFC9110-13.1.4-1`, `HS:RFC9110-13.1.5-2`, `HS:RFC9110-13.1.5-4`, `HS:RFC9110-13.1.5-5`, `HS:RFC9110-14.2-6`. Method: exhaustion (3^5 x 3 x 2 x 2 x 2 = 5832 cases), each case checked against (a) to (g).

**T11. Preconditions never override an earlier failure.** If a GetContent or DeleteFile would get a status other than 2xx or 412 without its conditional headers, the conditional headers don't change the response. Statements: `HS:RFC9110-13.2.1-2`, `HS:RFC9110-13.2.1-1`. Method: refinement on the composition order in `Project.Content`.

**T12. No availability without a receipt.** Whenever `life f` is `Active r len _`, `r` came from `parseReceipt` with FULL_OBJECT and `size r == len`. No row reaches Active from any outcome other than a parsed receipt (F1, P1). Statements: `PD:S3UG-INTEGRITY-UPLOAD-ChecksumTypes-Uploads-1`, `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-2`, `PD:S3UG-MPU-mpuAndPermissions-1`, `PD:S3UG-MPU-mpuAndPermissions-2`, `PD:RFC9530-6.5-1`. Method: construction (Receipt has no other builder) plus refinement on the Active constructor.

**T13. A composite checksum is never a receipt.** `parseReceipt` returns Right only when the declared type is FULL_OBJECT, the value has no `-N` part suffix with N in 1..10000 and no leading zero, and the value decodes to exactly `bitWidth alg / 8` bytes. For CRC64NVME that means 12 base64 characters ending in exactly one `=`. Statements: `PD:AWS-SDK-JS-isChecksumWithPartNumber-isChecksumWithPartNumber-1`, `PD:S3-SMITHY-com.amazonaws.s3#ChecksumType-1`, `PD:S3UG-INTEGRITY-UPLOAD-trailing-checksums-1`, `PD:RFC9651-4.1.8-1`, `PD:S3API-PutObject-request-header-ChecksumCRC64NVME-1`. Method: refinement on `parseReceipt`.

**T14. The checksum configuration is one S3 supports.** The support relation equals the multipart table on all 10 x 2 x 2 points, so CRC64NVME implies FULL_OBJECT only, and SHA1, SHA256, SHA512, MD5 and the XXHASH family in a multipart upload imply COMPOSITE only. The core's fixed configuration (multipart, CRC64NVME, FULL_OBJECT) is in the relation. Statements: `PD:S3UG-INTEGRITY-UPLOAD-MultipartUploads-Checksums-1`, `PD:S3UG-INTEGRITY-UPLOAD-Full-object-checksums-3`, `PD:S3API-CompleteMultipartUpload-request-header-ChecksumCRC64NVME-1`. Method: exhaustion.

**T15. Repr-Digest only with a registered Active key.** If a Response carries Repr-Digest, its key is sha-256 or sha-512 and it came from a FULL_OBJECT receipt. Statements: `HS:RFC9530-3-1`, `HS:RFC9530-5-1`, `HS:RFC9530-5-2`, `HS:RFC9530-7.2-1`, `HS:RFC9530-7.2-2`. Method: construction (`EmitKey` has two inhabitants, and the header is built only from a `Receipt`).

**T16. Stale reports change nothing.** For every event `ev` from a mover or the store with `epochOf ev /= epoch f`, `fst (stepFile env f ev) == f`, and the commands are `[StopMover (epochOf ev)]` for a mover report and `[]` for a store report. Statements: `UP:RESUMABLE-UPLOAD-13-4.6-3`, `UP:RESUMABLE-UPLOAD-13-4.6-4`, `UP:RESUMABLE-UPLOAD-13-4.6-5`, `UP:TUSD-2.10.1-lockUpload-1`, `SS:GRPC-STATUSCODES-ABORTED`, `SS:AIP151-Parallel-3`. Method: refinement on stepFile (already verified on a reduced model in the probe).

**T17. One writer at a time.** A file has at most one outstanding asynchronous job, and an upload has at most one append in flight. Every row that starts new work either finds the slot Idle or first emits `StopMover` for the occupant and bumps the epoch. Statements: `UP:RESUMABLE-UPLOAD-13-4.6-1`, `UP:RESUMABLE-UPLOAD-13-4.6-4`, `SS:AIP151-Parallel-2`. Method: construction (one slot), plus refinement that `epoch` strictly increases whenever the slot's epoch changes.

**T18. The offset is honest.** For a client upload: `offset == sum of sizes of parts`; `offset` never decreases across any stepFile; `offset <= declared` whenever `declared` is set; `declared` never changes once set; and every Upload-Offset the core emits equals `offset` at the moment of emission (or `declared` once complete). Statements: `UP:RESUMABLE-UPLOAD-13-4.1.1-1`, `UP:RESUMABLE-UPLOAD-13-4.1.1-6`, `UP:RESUMABLE-UPLOAD-13-4.1.1-7`, `UP:RESUMABLE-UPLOAD-13-4.1.3-6`, `UP:RESUMABLE-UPLOAD-13-4.4.2-7`, `UP:TUS-1.0.0-Creation.Requests.POST-4`, `UP:TUS-1.0.0-Core.Requests.PATCH-4`. Method: refinement on `Transfer` and on stepFile. For imports, monotonicity is deliberately not claimed, because rows I2 and I9 restart from zero when the origin's representation changed, and no import-facing standard promises a monotone offset.

**T19. A client can use the offset it was given.** If `advertised t == Just o` and the next event for the file is an Append with offset `o`, then that Append is not refused with `OffsetMismatch` (unless the deadline guard fires first). `advertised` is cleared by every row that accepts an append or cancel. Statements: `UP:RESUMABLE-UPLOAD-13-4.6-3`. Method: refinement on stepFile with `advertised` as a ghost field.

**T20. The part plan is the one S3 accepts.** The parts of every Transfer are numbered `1..k` with `k <= 10000`, every part except the final part of a completed transfer has size exactly `P >= 5242880`, and the list passed to CompleteMultipartUpload is that list in ascending order with the ETags the store returned. So the S3 errors EntityTooSmall and InvalidPartOrder, and the 500 for non-consecutive part numbers, can't be provoked by the core. Statements: `PD:S3UG-MPU-mpu-process-2`, `PD:S3UG-MPU-mpu-process-3`, `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-4`, `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-6`, `PD:S3UG-MPU-mpuchecksums-2`, `UP:RESUMABLE-UPLOAD-13-4.1.4-5`, `UP:RESUMABLE-UPLOAD-13-4.1.4-6`. Method: refinement on `Parts`.

**T21. Complete is never re-sent blind.** CompleteMultipartUpload is a POST. Within one Transfer it is issued again only through row P7, which requires a probe that found no object after an ambiguous outcome. It is never re-issued after NoSuchUpload, after KeyExists, or after a missing receipt. Statements: `HS:RFC9110-9.2.2-4`, `HS:RFC9110-13.2.2-2`, `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-3`, `SS:RPC-CODE-DEADLINE_EXCEEDED-1`. Method: refinement on the phase transition relation.

**T22. Ambiguous outcomes are always probed.** For every Finalizing file and every StoreOutcome other than a parsed receipt, the next life is still Creating in phase Probing. No such outcome moves a file directly to Active, Failed or Cancelled. Statements: `PD:S3API-Error-NoSuchUpload-1`, `PD:S3API-AbortMultipartUpload-Errors-1`, `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-2`, `SS:RPC-CODE-DEADLINE_EXCEEDED-1`. Method: exhaustion over `StoreOutcome` constructor tags x `After`.

**T23. Cancel against completion has one answer.** In Receiving, a cancel ends the file as Cancelled at once and stops the running append or fetch. In Finalizing or Probing, a cancel only sets `cancelRequested`; a receipt then yields Active (completed despite cancellation), and a confirmed absence yields Cancelled. In Active a cancel changes nothing. The cancel response is 204 when enacted and 202 when pending. Statements: `SS:LRO-CancelOperation-1`, `SS:LRO-CancelOperation-2`, `SS:LRO-CancelOperation-3`, `UP:RESUMABLE-UPLOAD-13-4.5.2-1`, `UP:RESUMABLE-UPLOAD-13-4.5.2-2`, `HS:RFC9110-9.3.5-3`. Method: exhaustion over Phase x cancelRequested x StoreOutcome tags, against rows U19, U20, F4, P1, P4, P6, P10, A5.

**T24. Expiry only ends incomplete transfers.** Row X1 moves a file to Failed Expired only from phase Opening or Receiving. In Finalizing or Probing, passing `finalizeBy` only prevents new Complete calls, and the file still ends by a probe result. Statements: `UP:RESUMABLE-UPLOAD-13-4.1.4-7`, `UP:TUS-1.0.0-Expiration-1`, `PD:S3UG-MPU-LIFECYCLE-mpu-abort-incomplete-mpu-lifecycle-config-2`, `SS:RPC-CODE-DEADLINE_EXCEEDED-1`. Method: refinement on stepFile.

**T25. Limits never move.** For one upload, every Upload-Limit the core emits has the same max-size, min-append-size and max-append-size, and `mono + max-age` is the same `deadline` in every response. Statements: `UP:RESUMABLE-UPLOAD-13-4.1.4-8`, `UP:RESUMABLE-UPLOAD-13-4.1.4-9`, `UP:RESUMABLE-UPLOAD-13-4.1.4-10`, `UP:RESUMABLE-UPLOAD-13-4.1.4-11`. Method: construction (`limits` lives in `Meta` and has no update path).

**T26. Completion headers are coherent.** No response to a request that carried Upload-Complete: ?1 is a 2xx with Upload-Complete ?0 or missing, and every 409 OffsetMismatch carries Upload-Offset and Upload-Complete: ?0. Statements: `UP:RESUMABLE-UPLOAD-13-4.2.2-4`, `UP:RESUMABLE-UPLOAD-13-4.4.2-3`, `UP:RESUMABLE-UPLOAD-13-4.4.2-4`. Method: refinement on `Project.Upload`.

**T27. Finalizing is entered only by an authorized request or a re-check.** A client upload enters Finalizing only through row U14, whose triggering Append passed guard 2 with access Allowed. An import enters it only through row I7, whose `FetchEnded` carries a re-evaluated access of Allowed. Statements: `UP:RESUMABLE-UPLOAD-13-13-6`, `UP:RESUMABLE-UPLOAD-13-13-7`. Method: refinement on stepFile.

**T28. Operations are monotone.** Once `opOutcome` is set it never changes and is never cleared. `DeleteOperation` never changes `life`. A cancelled operation's error code is CANCELLED, and the operation still exists afterwards. Statements: `SS:LRO-Operation-done`, `SS:LRO-Operation-result`, `SS:LRO-DeleteOperation`, `SS:LRO-CancelOperation-3`, `SS:AIP151-Guidance-4`. Method: refinement on stepFile.

**T29. A Fault is never OK.** `faultCode` has type `Fault -> {c:Code | c /= OK}`. Statements: `SS:ABSL-STATUSOR-2`, `SS:LRO-Operation-error`, `SS:AIP151-Errors-2`. Method: refinement.

**T30. Recourse is total and follows AIP-194.** `codeRecourse` covers all 17 codes: UNAVAILABLE is `RetryCall`; ABORTED is `RetryHigherLevel`; NOT_FOUND, ALREADY_EXISTS, PERMISSION_DENIED, UNAUTHENTICATED, FAILED_PRECONDITION, OUT_OF_RANGE and UNIMPLEMENTED are `NoRetryUntil` with the matching condition; OK, CANCELLED, DEADLINE_EXCEEDED and INVALID_ARGUMENT are `NeverRetry`; DATA_LOSS, INTERNAL and UNKNOWN are `SurfaceImmediately`; RESOURCE_EXHAUSTED is `NoRetryUntil StateChanges`. Every Refusal's recourse is either `codeRecourse` of its code or one of the refinements listed in the Refusal table. Statements: `SS:AIP194-*`, `SS:GRPC-STATUSCODES-FAILED_PRECONDITION-2`. Method: exhaustion (17 codes, plus the Refusal tags).

**T31. Retrying on a status is total and safe.** `retryOnStatus :: Method -> Status -> Bool -> Decision` is total over all methods and all of 100..599; it never repeats after a 507; it allows 421 for any method; and it never repeats a non-idempotent method on any other status. Statements: `HS:RFC9110-9.2.1-2`, `HS:RFC9110-9.2.2-1`, `HS:RFC9110-9.2.2-4`, `HS:RFC9110-9.2.2-7`, `HS:RFC9110-15.5.20-2`, `HS:RFC4918-11.5-2`, `HS:RFC6585-4-2`, `HS:RFC9110-15.5.14-3`, `HS:RFC9110-15.6.4-2`, `HS:RFC9110-15.5.9-2`. Method: exhaustion (8 methods x 500 statuses x Retry-After present or absent).

**T32. Retrying on a connection failure follows the replay rules.** `retryOnConnection` never retries on a fresh connection, retries a non-replayable request only when nothing was written and the body can be rewound, and otherwise retries only after a read error or an idle close. Statements: `HS:RFC9110-9.2.2-2`, `HS:RFC9110-9.2.2-4`, `HS:RFC9110-9.2.2-6`, `HS:RFC9110-9.2.2-8`. Method: exhaustion over its finite input product.

**T33. Restart intensity is bounded.** With intensity 0, `addRestart` always returns Terminate. After any `Ok`, the window holds at most MaxR timestamps, all greater than `now - MaxT`, sorted descending. So no sequence of calls allows more than MaxR restarts within any MaxT window. Statements: `SS:OTP-SUPERVISOR-Intensity`, `SS:OTP-SUPERVISOR-code-add_restart-1`, `SS:OTP-SUPERVISOR-code-add_restart-2`, `SS:OTP-SUPPRINC-MaxIntensity-1`. Method: refinement with list measures (length, sortedness, lower bound).

**T34. The restart table is OTP's.** `doRestart` over 3 restart types x 4 exit reasons gives Restart for permanent; for transient it gives Restart only on an abnormal exit; for temporary it never restarts. Statements: `SS:OTP-SUPERVISOR-code-do_restart`, `SS:OTP-SUPERVISOR-ChildSpec-restart`, `SS:OTP-SUPPRINC-ChildSpec-restart`. Method: exhaustion (12 cases).

**T35. The token bucket stays in bounds.** After every update, `0 <= tokens <= maxTokens`; `retryAllowed` holds exactly when `tokens > maxTokens/2`; and only retryable failures decrement. Statements: `SS:GRFC-A6-Throttling-1`, `SS:GRFC-A6-Throttling-2`, `SS:GRFC-A6-Throttling-3`. Method: refinement.

**T36. Backoff stays under its cap.** `delay n <= maxBackoff` for every n >= 1; a pushback delay is used once, and the next computed delay is `initialBackoff`; a negative pushback means no retry. Statements: `SS:GRFC-A6-Backoff`, `SS:GRFC-A6-Pushback-2`, `SS:GRFC-A6-Pushback-3`. Method: refinement.

**T37. An import resumes only with a strong validator.** Every `StartFetch` with a resume point carries a strong ETag captured from an earlier response of the same Transfer. Without one, the fetch starts at 0 with `parts = []`. A 200 to a resumed fetch resets `offset` to 0. Statements: `HS:RFC9110-13.1.5-3`, `HS:RFC9110-13.1.5-5`, `HS:RFC9110-13.1.5-6`, `HS:RFC9110-15.3.7.3-1`, `HS:RFC9110-8.8.1-6`. Method: construction (the resume argument's type is `(Offset, StrongETag)`), plus refinement on rows I2 and I9.

**T38. An import completes only with trustworthy framing.** An import enters Finalizing only after `Eof (LengthDelimited len)` with `offset == len`, or after `Eof ChunkedEnd`. A close-delimited end is treated as an interruption. Statements: `HS:RFC9110-6.1-1`, `HS:RFC9110-6.1-2`, `HS:RFC9110-6.1-3`, `HS:RFC9110-8.6-7`. Method: refinement on row I7.

**T39. Ranges are sound.** A 206 serves a single range `[a, b]` with `0 <= a <= b < len`, Content-Range `bytes a-b/len` and Content-Length `b - a + 1`. A 416 carries `bytes */len`. A zero-length representation never gets a 206. Statements: `HS:RFC9110-14.1.2-3`, `HS:RFC9110-14.1.2-4`, `HS:RFC9110-14.1.2-5`, `HS:RFC9110-14.1.2-6`, `HS:RFC9110-14.4-5`, `HS:RFC9110-14.4-6`, `HS:RFC9110-15.3.7.1`, `HS:RFC9110-15.3.7.2`, `HS:RFC9110-14.2-5`. Method: refinement on `Http.Range`.

**T40. Header pairings hold.** WWW-Authenticate is present exactly when the status is 401; Content-Length is never present with 204; Content-Range only appears with 206 or 416; a HEAD response never has a body. Statements: `HS:RFC9110-15.5.2-2`, `HS:RFC9110-11.6.1-1`, `HS:RFC9110-8.6-4`, `HS:RFC9110-14.4-8`, `HS:RFC9110-9.3.2-1`. Method: refinement on `Response`.

**T41. DELETED is reached only after the store confirmed the delete.** The only transitions into Deleted are D1 (after `Removed`) and K9 (from a Failed or Cancelled file, which never had stored content beyond what its cleanup removes). A failed delete leaves the file in DELETING. Statements: `HS:RFC9110-9.3.5-3`, `DO:RFC4918-9.6-3`, `SS:AIP216-Active-3`. Method: refinement on stepFile.

**T42. Ids are never reused within the tombstone horizon.** A creation event whose file, upload or operation id is present in the World, tombstones included, is refused and creates nothing. Statements: `UP:RESUMABLE-UPLOAD-13-4-4`, `DO:RFC4918-8.8-3`, `DO:RFC4918-6.5-2`. Method: construction at the single creation site in `Core.World` (not machine-checked, see Routing).

**T43. The exposed state is always one of six.** `stateOf :: Life -> ResourceState` is total and its image is {CREATING, ACTIVE, FAILED, CANCELLED, DELETING, DELETED}. No unspecified value exists. Statements: `SS:AIP216-Default`, `SS:AIP216-EnumValues-4`, `SS:AIP216-Resting`, `SS:AIP216-Active-3`. Method: construction.

**T44. A conforming draft client does what we meant.** Let `draftClient :: Status -> Maybe Bool -> Maybe Nat -> DraftAction` be a transcription of the draft's client heuristics: a target result on ?1, continue on 2xx with ?0, resume at the offset on 409 (or fetch it first when absent), resume within limits on 413, retry after a delay on 429, retry on 5xx, and fail otherwise. Then for every Refusal an upload endpoint can return, `draftClient` applied to the projected response yields an action in the allowed set the Refusal table names for it. For example, OffsetMismatch gives a resume at `expected`, OffsetPastLength gives a resume-within-limits that the next request answers with 410, and StoreUnavailable gives a retry. Statements: `UP:RESUMABLE-UPLOAD-13-4.7-1`..`-7`, `UP:RESUMABLE-UPLOAD-13-4.2.1-11`, `UP:RESUMABLE-UPLOAD-13-4.2.1-12`, `UP:RESUMABLE-UPLOAD-13-4.2.1-13`, `UP:RESUMABLE-UPLOAD-13-4.4.1-6`. Method: exhaustion over the Refusal constructor tags.

**T45. Per-owner upload count is exact.** `creatingByOwner o` equals the number of files of owner `o` whose life is Creating. Statements: `UP:RESUMABLE-UPLOAD-13-13-8`. Method: construction (a single update site computing the delta from `isCreating` before and after).

## What the sources leave open

1. **The wire protocol is an Internet-Draft.** Upload-Offset, Upload-Complete, Upload-Length, Upload-Limit and the two upload problem types come from draft-ietf-httpbis-resumable-upload-13 (`UP:RESUMABLE-UPLOAD-13-*`). The problem types are IANA requests, not registry entries (`UP:RESUMABLE-UPLOAD-13-14.4-1`, `UP:RESUMABLE-UPLOAD-13-14.4-2`), and 104 is a TEMPORARY registration (`HS:IANA-HTTP-Status-Codes-104`). Upload-Offset also exists in tus 1.0 with the same meaning (`UP:TUS-1.0.0-Core.Headers.Upload-Offset-1`), but tus defines completion differently. We need a decision on whether draft vocabulary counts as "a standard already defines it".
2. **Statement ids collide across groups.** Forty-two ids carry different quotes in different groups. `tools/gen-vocab.py` will namespace `Cite` constructors by group, but the references themselves should probably be fixed upstream so an id names one quote.
3. **The store's receipt has no registered digest key.** CRC64NVME has no key in the IANA digest registry, so under the single multipart path no Repr-Digest is ever emitted. Emitting sha-256 would need single-request PutObject with SHA256 (FULL_OBJECT per `PD:S3API-PutObject-response-header-ChecksumType-1`), which only works when the whole file fits in one request. That would split the store path in two. DRS checksum types (`DO:DRS-schemas.Checksum.type-1`, `DO:DRS-schemas.Checksum.type-2`) would need a type string like "crc64nvme" that no registry defines.
4. **End-to-end integrity is not established.** The receipt proves what the store holds, not that it equals what the person sent. RFC 9530 lets us ignore client digests (`HS:RFC9530-2-2`), and this design does, because the store can't validate any client-supplied full-object digest on a multipart CRC64NVME upload. Whether to validate client Repr-Digest some other way, and with which of the registered digest problem types, is undecided.
5. **Empty files.** Whether S3 completes a multipart upload with zero parts or with one empty part is not in the vendored text. Until it is, a zero-length upload gets 501.
6. **The Upload-Complete value on OffsetPastLength.** The draft makes the upload invalid (`UP:RESUMABLE-UPLOAD-13-4.4.2-7`) but doesn't say which Upload-Complete value the rejecting 413 should carry. With ?0, a draft client applies the 413 heuristic once and then gets 410. With ?1, it would think the target resource produced the error.
7. **No standard names our representations.** AIP-193 requires an ErrorInfo with a reason and domain in every error (`SS:AIP193-Status.details-3`, `SS:AIP193-ErrorInfo-2`, `SS:AIP193-ErrorInfo-3`), and any reason string would be vocabulary we invented. The same goes for `Status.message`, a problem's `detail`, and the JSON field names of a file representation. One way to avoid inventing would be to use the HTTP status registry as the domain and its registered names as reasons, but that needs a decision. The core only produces typed facts and leaves rendering to the shell until then.
8. **Close-delimited imports.** Treating a close-delimited end as an interruption is the conservative reading of `HS:RFC9110-6.1-1` and `HS:RFC9110-6.1-3`, but an origin that always closes instead of sending a length can then never be imported.
9. **Re-authorization for imports.** The draft's TOCTOU text is about uploads (`UP:RESUMABLE-UPLOAD-13-13-6`). Re-checking the owner's access before an import finalizes is our extension of it, and the shell has to supply that access in `FetchEnded`.
10. **Retrying a failed automatic retry.** `HS:RFC9110-9.2.2-8` says a client SHOULD NOT automatically retry a failed automatic retry. Our reading is that each supervised restart is a new attempt that the core decides on, bounded by intensity and the deadline, and that the mover's own HTTP client must make exactly one request per attempt. That reading needs agreement.
11. **Which pushback rule.** We follow gRFC A6 (use the server's delay exactly, then reset). The AWS SDK clamps `x-amz-retry-after` to `[backoff, backoff + 5000 ms]` (`PD:AWSSDK-RETRY-server-directed-retry-timing-1`) and never mentions the standard Retry-After.
12. **AIP-216 over TES and WES.** We use AIP-216 states. TES and WES define richer task states but no transitions, and their two definitions drift (`DO:TES-tesState.CANCELED-1` against `DO:WES-State.CANCELED-1`).
13. **Store-side backstops the core can't see.** Two things depend on store configuration the core can't verify. An orphaned CreateMultipartUpload (one that timed out and then succeeded) is invisible to the core, so the store needs an abort-incomplete-multipart lifecycle rule whose horizon is longer than `maxAge + finalizeBudget` (`PD:S3UG-MPU-LIFECYCLE-mpu-abort-incomplete-mpu-lifecycle-config-1`, `PD:S3API-CreateMultipartUpload-response-header-AbortDate-1`). The user guide's "there is no expiry" (`PD:S3UG-MPU-mpuoverview-1`) contradicts this. DeleteObject has no vendored S3 statement at all.
14. **Checksum widths.** Only CRC64NVME, CRC32 and SHA256 have a width quoted in a statement. The API pages for CRC32C, SHA1, SHA512, MD5 and the XXHASH family are vendored but not extracted.
15. **PATCH semantics.** RFC 5789 isn't vendored, so PATCH is treated as non-idempotent.
16. **The WWW-Authenticate challenge.** Its scheme and parameters aren't defined in any vendored reference. The shell supplies them, and the core only guarantees the header is present.
17. **Tombstones against uniqueness.** After the tombstone horizon, id uniqueness depends on the shell's random ids. The core can't prove it.
18. **Corruption on the way out.** If the shell finds that the store's bytes don't match the store's own receipt while streaming a download, the bytes may already be sent (`HS:RFC9530-6.4`). AIP-216's REPAIRING is a candidate state for that case, but nothing vendored defines what happens next. The CRC-64/NVME reference (`PD:AWS-CHECKSUMS-crc64_test-crc64nvme_reference-1`) is the natural oracle for that check in the shell.
19. **The AWS documentation contradicts itself.** BadDigest means a Content-MD5 mismatch in the error table (`PD:S3API-Error-BadDigest-1`) but any checksum mismatch in the user guide (`PD:S3UG-INTEGRITY-UPLOAD-using-additional-checksums-1`). Where a part fails with BadDigest on a checksum our mover computed, the design treats it as transient transmission damage (503), following `PD:DIGEST-PROBLEMS-3.3-5`. That reading is provisional.
20. **What a CREATING file's content returns.** We answer 404 (`HS:RFC9110-15.5.5-1`). FAILED_PRECONDITION (400) or DRS's 202 with Retry-After would also be defensible.
21. **Stuck deletes.** A file whose DeleteObject keeps failing stays DELETING with an alert. There is no event for an operator to re-drive it yet.
