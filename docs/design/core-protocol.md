# funknown-core: a protocol-first design

Status: design only, no Haskell source yet. Written 2026-10-09 against the five vendored reference groups under `references/` (the abandoned `experiments/` tree is ignored on purpose).

We have five folders of vendored standards and code, and no core yet. We want a pure Haskell core for a B2B drive (uploads from a browser, imports from a URL, downloads) that never invents its own vocabulary, so I'm designing it as a faithful model of the protocols themselves. The resumable-upload draft decides offsets and completion, RFC 9110 decides status codes, RFC 9530 decides digests, RFC 9457 decides error bodies, and a GA4GH DRS object is what a finished file is. What forces this shape is the pair of rules in the brief: every state, status, reason and recourse has to be one a standard already defines, and a file only becomes available when the store vouches for it with a full-object checksum receipt. If both rules are going to hold, it looks to me like they have to live in the types, because a test can only sample them.

The rest of this document says how citations work, the one structural idea everything else follows from, the package layout, every type with the statements its constructors come from, the `step` transition tables, what a client is told in each circumstance, which reference code gets ported and what we fix on the way, the theorem catalog, and the questions the sources leave open.

## How a citation is written here

Every claim cites a statement id from a `statements.json`, and I prefix each id with its group, because the ids are not unique across groups. The same id can carry a different quote in two groups. For example `RFC9110-15-5` is "Values outside the range 100..599 are invalid." in http-semantics, while in problems-and-digests the same id quotes the SHOULD about processing an invalid code as 5xx. Sixty-eight ids appear in more than one group, and forty-two of those carry different quotes. A citation therefore only means something as a (group, id) pair. The prefixes are:

- `HS:` references/http-semantics/statements.json
- `PD:` references/problems-and-digests/statements.json
- `UP:` references/uploads/statements.json
- `DO:` references/drive-and-objects/statements.json
- `SS:` references/status-and-supervision/statements.json

So `UP:RESUMABLE-UPLOAD-13-4.4.2-3` means the uploads group's quote of draft-ietf-httpbis-resumable-upload-13 section 4.4.2. Every citation in this file was checked against the statements files by script when I wrote it.

## One upload resource for every way bytes come in

The brief has two ways bytes arrive: a person's browser uploads them, or we import them from a URL. If we model those as two state machines, we would get two ideas of what an offset is, two completion rules, and two places where a file could become available without a receipt. The draft already gives us a way out. It says the server can obtain representation data on the client's behalf ("the offset can be greater than the amount of sent representation data, for example, if the server obtained additional representation data on behalf of the client", `UP:RESUMABLE-UPLOAD-13-4.3.1-2`), and it says an upload is complete once it is "explicitly marked as completed by the client or the server" (`UP:RESUMABLE-UPLOAD-13-4.1.2-1`). So I'd like every byte that enters the system to go through exactly one `UploadResource` type, with a field saying who appends to it: the client's requests, or our own fetcher reading the source URL. The receipt rule, the offset rules and the completion rule then exist in one place, and the compiler holds both paths to it.

The same reasoning applies on the way out. Only one function builds a `DrsObject`, and its argument is a `Receipt` that only the store-report parser can produce. A download, a DRS lookup and an access-URL request all start from that `DrsObject`, so nothing can describe a file as ready unless the store vouched for it.

## The package

One cabal package, `funknown-core`, with `build-depends: base, containers, liquidhaskell` and `ghc-options: -fplugin=LiquidHaskell`. It does no IO, no networking and no clock reads. Time comes in on events as an `Instant`, and anything that has to talk to S3, a browser or a source URL goes out as a `Command`.

I probed the toolchain in a scratch package before committing to this layout (GHC 9.14.1 via ghcup, `cabal build -w ghc-9.14.1`, LiquidHaskell 0.9.14.1.1, z3 4.16.0). Three things came out of it that the layout depends on:

- `{-# LANGUAGE Safe #-}` and the LiquidHaskell plugin coexist. A module with `Safe`, `{-@ LIQUID "--reflection" @-}` and `{-@ LIQUID "--ple" @-}` verified as `LIQUID: SAFE`, so every module below can be `Safe`.
- `default-language: GHC2021` drags in `GeneralizedNewtypeDeriving`, which Safe Haskell refuses with a warning, so we'd use `Haskell2010` plus explicit extensions.
- A status-class lemma written with `div` failed under PLE, while the same lemma written against a reflected `classBase :: Class -> Int` table with a case split verified. So I'd keep integer division out of reflected code and express classes as tables.

Module layout:

```
funknown-core/
  funknown-core.cabal
  src/Funknown/
    Provenance.hs          Group, StatementId; every closed type exports provenance :: T -> NonEmpty StatementId
    Http/Status.hs         generated from references/http-semantics/http-status-codes-1.csv
    Http/Method.hs         Method, safe, idempotent
    Http/Fields.hs         typed header values the core reads or writes, with their parsers
    Http/Conditional.hs    the RFC 9110 13.2.2 precondition ladder (port of Go net/http fs.go)
    Http/Range.hs          byte-range satisfiability and Content-Range
    Http/Retry.hs          outbound retry decision (port of urllib3 + Go transport)
    Http/Response.hs       Interim and Final: one constructor per response the core can emit, plus render
    Digest.hs              RFC 9530 algorithm keys and Repr-Digest
    Problem.hs             RFC 9457 problem types and their extension members
    Store/Checksum.hs      S3 checksum vocabulary, the support table, the composite parser, Receipt
    Store/Error.hs         S3 error codes and the retry classification
    Upload/Limits.hs       Upload-Limit keys
    Upload/Resource.hs     the draft's upload resource: parts, length, limits, phase
    Object/Drs.hs          DrsObject, Checksum, AccessMethod, AccessURL
    Rpc/Code.hs            google.rpc.Code, used only inside import Operations
    Import/Operation.hs    google.longrunning.Operation shape for imports
    Core/Event.hs          Event (everything the shell can tell the core)
    Core/Command.hs        Command (everything the core can ask the shell to do)
    Core/State.hs          State and its invariants
    Core/Step.hs           step :: State -> Event -> (State, [Command])
    Core/Project.hs        what a client is told, as pure functions of State
  test/Exhaustive.hs       proofs by exhaustion: each property enumerated over its whole finite domain
tools/
  gen-status.py            regenerates Http/Status.hs from the CSV and checks every row against HS:IANA-HTTP-Status-Codes-<value>
  check-cites.py           checks that every provenance id exists in its group's statements.json
```

The two scripts sit outside the package because the core may only depend on base and containers. They run with `python3 -I` and take the reference paths as arguments, so nothing in `references/` is executed.

## The vocabulary, type by type

Each table lists a type's constructors and the statements each one comes from. A constructor that can't be tied to a statement is left out, and if we need it anyway, it goes into the open questions at the end instead.

### Http.Status

`Status` has 64 constructors, one per assigned row of the IANA registry CSV (75 rows, of which 11 are unassigned ranges). Each row is quoted in http-semantics as `IANA-HTTP-Status-Codes-<value>`. Constructors are named after the registry's description, not the older reason phrases in Go, CPython or http-types (`Content Too Large`, not `Request Entity Too Large`; `Unprocessable Content`, not `Unprocessable Entity`), because those three tables disagree with the registry. The generator emits:

- `data Status = Continue | SwitchingProtocols | Processing | EarlyHints | UploadResumptionSupported | OK | Created | ... | NetworkAuthenticationRequired` (64 constructors, from `HS:IANA-HTTP-Status-Codes-100` through `HS:IANA-HTTP-Status-Codes-511`).
- `code :: Status -> {n:Int | 100 <= n && n <= 599}` (`HS:RFC9110-15-1`).
- `data Registration = Permanent | Temporary | Unused | Obsoleted` with `registration :: Status -> Registration`:
  - `Temporary` covers only 104 (`HS:IANA-HTTP-Status-Codes-104`, "TEMPORARY ... expires 2026-11-13").
  - `Unused` covers 306 and 418 (`HS:IANA-HTTP-Status-Codes-306`, `HS:IANA-HTTP-Status-Codes-418`, `HS:RFC9110-15.5.19`).
  - `Obsoleted` covers 510 (`HS:IANA-HTTP-Status-Codes-510`).
- `data Class = Informational | Successful | Redirection | ClientError | ServerError` (`HS:RFC9110-15-3`), with `classBase :: Class -> Int` giving 100, 200, 300, 400, 500.
- `data Received = Registered Status | Unrecognized {n:Int | 100 <= n && n <= 599} | Invalid Int`. This is how we read a status we did not generate, for example from a store or a source URL. `fromCode :: Int -> Received` builds it, and `interpret :: Received -> Class` treats an unrecognized code as the x00 code of its class (`HS:RFC9110-15-4`) and an invalid code as 5xx (`HS:RFC9110-15-5`, `HS:RFC9110-15-6`).

### Http.Method

| Constructor | Provenance |
|---|---|
| `GET`, `HEAD`, `OPTIONS`, `TRACE` | safe: `HS:RFC9110-9.2.1-2` |
| `PUT`, `DELETE` | idempotent and not safe: `HS:RFC9110-9.2.2-1` |
| `POST` | neither: `HS:RFC9110-9.3.3-1` |
| `PATCH` | the draft's append method, `UP:RESUMABLE-UPLOAD-13-4.4.1-1`. RFC 9110 does not define it, so `idempotent PATCH = False` by `HS:RFC9110-9.2.2-4` ("unless it has some means to know") |

`safe` and `idempotent` are reflected predicates. The idempotent set comes out equal to urllib3's `DEFAULT_ALLOWED_METHODS`, which is theorem T9.

### Http.Fields

These are the header values the core reads off an event or writes into a response. The shell parses the raw bytes, but the parsers themselves are pure and live here, so the "MUST cause the entire header field to be ignored" rules are decided in one place.

| Type | Shape | Provenance |
|---|---|---|
| `UploadOffset` | `{n:Integer \| n >= 0}`; anything else parses to "ignored" | `UP:RESUMABLE-UPLOAD-13-4.1.1-4` |
| `UploadComplete` | `Bool` (`?1` / `?0`); anything else ignored | `UP:RESUMABLE-UPLOAD-13-4.1.2-2` |
| `UploadLength` | `{n:Integer \| n >= 0}`; anything else ignored | `UP:RESUMABLE-UPLOAD-13-4.1.3-5` |
| `UploadLimit` | see Upload.Limits | `UP:RESUMABLE-UPLOAD-13-4.1.4-2` |
| `RetryAfter` | `DelaySeconds {n:Integer \| n >= 0}` only on output; input also accepts an HTTP-date | `HS:RFC9110-10.2.3-4`, `HS:RFC9110-10.2.3-5`, `HS:RFC9110-10.2.3-6`, `HS:RFC9110-10.2.3-7` |
| `EntityTag` | `Strong OpaqueTag \| Weak OpaqueTag` | `HS:RFC9110-8.8.3-2`, `HS:RFC9110-8.8.3-3` |
| `LastModified` | an `Instant` | `HS:RFC9110-8.8.2` |
| `ContentRange` | `Satisfied first last complete \| Unsatisfied complete` with `first <= last < complete` | `HS:RFC9110-14.4-1`, `HS:RFC9110-14.4-5` |
| `Challenge` | opaque, supplied by the shell | `HS:RFC9110-11.3`, `HS:RFC9110-11.6.1-1` |
| `Allow` | `NonEmpty Method` | `HS:RFC9110-15.5.6` |
| `CacheControlNoStore` | unit | `UP:RESUMABLE-UPLOAD-13-4.3.2-1`, `UP:TUS-1.0.0-Core.Requests.HEAD-3` |
| `ReprDigest` | see Digest | `PD:RFC9530-3-1` |
| `WantReprDigest` | `NonEmpty (DigestAlg, {w:Int \| 0 <= w && w <= 10})` | `PD:RFC9530-4-1`, `PD:RFC9530-4-3` |

The core only ever writes Retry-After as delay-seconds, because it has no clock to format a date, and because DRS's 202 requires "an integral relative time in seconds" (`DO:DRS-responses.202Accepted.Retry-After-1`). Reading it is different: a source URL or store may send either form, so `parseRetryAfter :: Instant -> String -> Maybe Seconds` takes `1*DIGIT` exactly. That means no decimals, which the smithy parser accepts and RFC 9110 does not. A date value is subtracted from the event's instant and clamped at 0, the way urllib3 clamps it.

### Upload.Limits

`UploadLimit` is a record of five `Maybe` fields, one per key in the draft:

| Field | Provenance |
|---|---|
| `maxSize` | `UP:RESUMABLE-UPLOAD-13-4.1.4-3` |
| `minSize` | `UP:RESUMABLE-UPLOAD-13-4.1.4-4` |
| `maxAppendSize` | `UP:RESUMABLE-UPLOAD-13-4.1.4-5` |
| `minAppendSize` | `UP:RESUMABLE-UPLOAD-13-4.1.4-6` |
| `maxAge` | stored as an absolute `expiresAt :: Instant`, rendered as `expiresAt - now`, `UP:RESUMABLE-UPLOAD-13-4.1.4-7` |

When every field is `Nothing`, `render` emits `min-size=0` (`UP:RESUMABLE-UPLOAD-13-4.1.4-15`). Unknown keys in a received Upload-Limit are dropped, and a known key with a non-Integer value drops the whole field (`UP:RESUMABLE-UPLOAD-13-4.1.4-12`).

The configured `minAppendSize` is the store's minimum part size ("Each part must be at least 5 MB in size, except the last part", `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-4`). The draft's own exemption lines up exactly with S3's "except the last part": min-append-size "does not apply to upload creation requests with no content, or to requests completing the upload" (`UP:RESUMABLE-UPLOAD-13-4.1.4-6`). With that one setting, every non-completing append can be stored as exactly one S3 part. Most of the upload invariants below depend on it.

### Digest

| Constructor of `DigestAlg` | Status | Provenance |
|---|---|---|
| `Sha512` (key `sha-512`) | Active | `PD:IANA-DIGEST-ALGS-sha-512-1`, `HS:RFC9530-7.2-1` |
| `Sha256` (key `sha-256`) | Active | `PD:IANA-DIGEST-ALGS-sha-256-1`, `HS:RFC9530-7.2-2` |
| `Md5` (key `md5`) | Deprecated | `PD:IANA-DIGEST-ALGS-md5-1`, `HS:RFC9530-7.2-3` |
| `Sha` (key `sha`) | Deprecated | `PD:IANA-DIGEST-ALGS-sha-1`, `HS:RFC9530-7.2-4` |
| `Unixsum` | Deprecated | `PD:IANA-DIGEST-ALGS-unixsum-1`, `HS:RFC9530-7.2-5` |
| `Unixcksum` | Deprecated | `PD:IANA-DIGEST-ALGS-unixcksum-1`, `HS:RFC9530-7.2-6` |
| `Adler` | Deprecated | `PD:IANA-DIGEST-ALGS-adler-1`, `HS:RFC9530-7.2-7` |
| `Crc32c` | Deprecated | `PD:IANA-DIGEST-ALGS-crc32c-1`, `HS:RFC9530-7.2-8` |

`data AlgStatus = Active | Provisional | Deprecated` (`PD:RFC9530-5-3`). `Provisional` exists because the status set defines it, even though no key has it today. `ReprDigest = NonEmpty (DigestAlg, ByteSeq)` (`PD:RFC9530-3-1`, `PD:RFC9530-2-1`), serialized as an sf-binary with `=` padding (`PD:RFC9651-3.3.5-1`, `PD:RFC9651-4.1.8-1`).

We never compute a digest. No function in this module, or anywhere else in the core, takes the bytes of a representation, and Event has no constructor that carries them (theorem T36). A `ReprDigest` can only come from a client field we are forwarding, or from `reprDigestOf :: Receipt -> Maybe ReprDigest`.

### Problem

`data ProblemType` is closed:

| Constructor | Extension members | Recommended status | Registration | Provenance |
|---|---|---|---|---|
| `AboutBlank` | none | the response's own | IANA | `PD:IANA-PROBLEM-TYPES-about:blank-1`, `PD:RFC9457-4.2.1-1`, `PD:RFC9457-3.1.1-2` |
| `DigestUnsupportedAlgorithms` | `unsupported_algorithms : [{algorithm, header}]` | 400 | IANA, citing a draft in the RFC Editor queue | `PD:IANA-PROBLEM-TYPES-digest-unsupported-algorithms-1`, `PD:DIGEST-PROBLEMS-3.1-2`, `PD:DIGEST-PROBLEMS-3.1-3`, `PD:DIGEST-PROBLEMS-3.1-4` |
| `DigestInvalidValues` | `invalid_digests : [{algorithm, header, reason}]` | 400 | IANA, same | `PD:IANA-PROBLEM-TYPES-digest-invalid-values-1`, `PD:DIGEST-PROBLEMS-3.2-3`, `PD:DIGEST-PROBLEMS-3.2-4` |
| `DigestMismatchedValues` | `mismatched_digests : [{algorithm, provided_digest, header}]` | 400 | IANA, same | `PD:IANA-PROBLEM-TYPES-digest-mismatched-values-1`, `PD:DIGEST-PROBLEMS-3.3-2`, `PD:DIGEST-PROBLEMS-3.3-3` |
| `MismatchingUploadOffset` | `expected-offset`, `provided-offset` | 409 | requested by the draft, not in the vendored IANA registry | `UP:RESUMABLE-UPLOAD-13-7.1-1`, `UP:RESUMABLE-UPLOAD-13-7.1-2`, `UP:RESUMABLE-UPLOAD-13-14.4-1` |
| `InconsistentUploadLength` | none | 400 | requested by the draft, not in the vendored IANA registry | `UP:RESUMABLE-UPLOAD-13-7.2-1`, `UP:RESUMABLE-UPLOAD-13-14.4-2` |

A `Problem` holds a `ProblemType` and its members, and nothing else. Its `title` is a function of the type (`PD:RFC9457-3.1.3-2`), and for `AboutBlank` it is the status's registry description (`PD:RFC9457-4.2.1-2`). `Problem` deliberately has no `status` field: the serializer copies the response's own status into the JSON, so the two can't disagree (`PD:RFC9457-3.1.2-2`, `PD:RFC9457-5-2`). The core never fills `detail` or `instance`, because both are prose or identifiers that belong to the shell (`PD:RFC9457-3.1.4-1`, `PD:RFC9457-3.1.5-1`). It also never puts the digest it would have expected into a mismatch problem (`PD:DIGEST-PROBLEMS-3.3-4`). The registration column matters because of a `Policy` switch, described under State. The two upload problem types are absent from `references/problems-and-digests/iana/http-problem-type-uris.csv`.

### Store.Checksum

This module is the store's vocabulary. Using it doesn't break the no-invented-vocabulary rule, because the receipt is the store's own statement and no IETF or IANA text defines one.

| Type | Constructors | Provenance |
|---|---|---|
| `ChecksumAlgorithm` | `CRC32 \| CRC32C \| SHA1 \| SHA256 \| CRC64NVME \| SHA512 \| MD5 \| XXHASH64 \| XXHASH3 \| XXHASH128` | `PD:S3API-CreateMultipartUpload-request-header-ChecksumAlgorithm-1` |
| `ChecksumType` | `COMPOSITE \| FULL_OBJECT` | `PD:S3-SMITHY-com.amazonaws.s3#ChecksumType-1`, `PD:S3API-CreateMultipartUpload-request-header-ChecksumType-1` |
| `UploadShape` | `SinglePart \| Multipart` | `PD:S3UG-INTEGRITY-UPLOAD-SinglePartUploads-Checksums-1`, `PD:S3UG-MPU-mpu-process-1` |
| `ChecksumValue` | `FullObjectValue ByteSeq \| CompositeValue ByteSeq {k:Int \| 1 <= k && k <= 10000}` | `PD:AWS-SDK-JS-isChecksumWithPartNumber-isChecksumWithPartNumber-1`, `PD:S3UG-INTEGRITY-UPLOAD-ChecksumTypes-Uploads-3` |
| `Receipt` (abstract) | `{alg, value, size, storeETag}` with `checksumType = FULL_OBJECT` and `size` equal to the recorded upload length | see below |

`supports :: ChecksumAlgorithm -> UploadShape -> ChecksumType -> Bool` is the multipart table in `PD:S3UG-INTEGRITY-UPLOAD-MultipartUploads-Checksums-1`, plus "single part is always FULL_OBJECT" (`PD:S3UG-INTEGRITY-UPLOAD-SinglePartUploads-Checksums-1`, `PD:S3API-PutObject-response-header-ChecksumType-1`), plus "The `CRC64NVME` checksum is always a full object checksum" (`PD:S3API-PutObject-request-header-ChecksumCRC64NVME-1`). The at-rest page contradicts the table (`PD:S3UG-INTEGRITY-AT-REST-using-additional-checksums-rest-1` says everything but CRC64NVME supports both types). I chose the table because it is the upload-time rule, and the upload is where we choose the algorithm.

`parseChecksumValue :: String -> Maybe ChecksumValue` is the composite detector, made total: base64 has no `-` in its alphabet, so a `-N` suffix with N in 1..10000 and no leading zero means composite and nothing else does. `width :: ChecksumAlgorithm -> Maybe Int` gives the byte width only where a statement does: CRC64NVME 8 (`PD:S3API-PutObject-request-header-ChecksumCRC64NVME-1`), CRC32 4 (`PD:S3API-CompleteMultipartUpload-response-ChecksumCRC32-1`) and SHA256 32 (`PD:S3API-Checksum-API_Checksum_Contents-3`). The value is the big-endian checksum (`PD:S3UG-INTEGRITY-UPLOAD-trailing-checksums-1`, `PD:AWS-SDK-JS-Crc64NvmeJs-digest-1`).

The only way to get a `Receipt` is `vouch :: Expected -> StoreReport -> Either NotVouched Receipt`. `NotVouched` uses the store's own words for why there is no receipt:

| `NotVouched` constructor | Provenance |
|---|---|
| `NoChecksumReturned` (a 2xx with no checksum at all) | `PD:S3UG-MPU-mpuAndPermissions-1`, `PD:S3UG-MPU-mpuAndPermissions-2`, `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-2` |
| `ChecksumTypeIs COMPOSITE` | `PD:S3UG-INTEGRITY-UPLOAD-ChecksumTypes-Uploads-3`, `PD:S3API-CompleteMultipartUpload-response-ChecksumCRC32-1` |
| `AlgorithmNotRequested` (the algorithm differs from the one we declared at creation) | `PD:S3UG-INTEGRITY-UPLOAD-Full-object-checksums-6`, `PD:S3API-UploadPart-request-header-ChecksumAlgorithm-2` |
| `SizeDiffers` | `PD:S3API-CompleteMultipartUpload-request-header-MpuObjectSize-1` |
| `MalformedValue` (wrong width, bad base64, missing padding) | `PD:RFC9651-4.1.8-1` |

`reprDigestOf :: Receipt -> Maybe ReprDigest` maps an algorithm to an RFC 9530 key only when both name the same algorithm: `SHA256 -> sha-256`, `SHA512 -> sha-512`, `MD5 -> md5`, `SHA1 -> sha`, `CRC32C -> crc32c`. Everything else maps to `Nothing`, and that includes `CRC64NVME`, the store's default. The consequence for downloads is in the open questions.

### Store.Error

`data S3ErrorCode` covers the 31 rows quoted in problems-and-digests as `S3API-Error-<Code>-1` (`AccessDenied` through `TokenRefreshRequired`), plus three documented elsewhere: `InvalidRequest` (`PD:S3UG-INTEGRITY-UPLOAD-Full-object-checksums-5`), `ConditionalRequestConflict` (`PD:S3API-PutObject-request-header-IfMatch-1`) and `NoSuchUpload` at UploadPart (`PD:S3API-UploadPart-API_UploadPart-1`). `s3Status :: S3ErrorCode -> Status` is the documented table, and `classify :: Maybe S3ErrorCode -> Received -> StoreRetry` returns `Transient | Throttling | NonRetryable`:

- error code first, status second (`PD:AWSSDK-RETRY-error-classification-4`);
- the throttling codes, which include `SlowDown` (`PD:AWSSDK-RETRY-error-classification-2`, `PD:SMITHY-TS-error-classification-constants-THROTTLING_ERROR_CODES-1`), or a 429 status (`PD:SMITHY-TS-service-error-classification-isThrottlingError-1`), give `Throttling`;
- `RequestTimeout`, `InternalError`, or 500/502/503/504 with no recognized code give `Transient` (`PD:AWSSDK-RETRY-error-classification-1`, `PD:SMITHY-TS-error-classification-constants-TRANSIENT_ERROR_CODES-1`, `PD:SMITHY-TS-error-classification-constants-TRANSIENT_ERROR_STATUS_CODES-1`);
- everything else is `NonRetryable` (`PD:AWSSDK-RETRY-error-classification-3`), and an abort is terminal (`PD:SMITHY-TS-service-error-classification-isTransientError-1`).

### Upload.Resource

The draft defines an upload resource's state as offset, completeness, length and limits (`UP:RESUMABLE-UPLOAD-13-4.1-1`). I'd add only what the draft forces on top of that: deactivation (`UP:RESUMABLE-UPLOAD-13-4.1.1-9`, `UP:RESUMABLE-UPLOAD-13-4.5.2-1`), invalidity (`UP:RESUMABLE-UPLOAD-13-4.4.2-7`) and at most one request in flight (`UP:RESUMABLE-UPLOAD-13-4.6-1`, `UP:RESUMABLE-UPLOAD-13-4.6-4`).

```
UploadResource
  { target    :: ObjectId                  -- the file this upload will become
  , appender  :: Appender                  -- who supplies bytes
  , shape     :: UploadShape
  , parts     :: Parts                     -- refined: numbered 1..k, k <= 10000, non-final sizes >= minAppendSize
  , length    :: Maybe UploadLength        -- Nothing until known; once Just, never changes
  , limits    :: UploadLimit               -- fixed at creation
  , expiresAt :: Instant
  , inFlight  :: Maybe ReqId
  , phase     :: UploadPhase
  }
offset :: UploadResource -> UploadOffset   -- defined as the sum of part sizes, never stored
```

| Constructor | Meaning | Provenance |
|---|---|---|
| `Appender = ClientAppends` | the browser sends PATCHes | `UP:RESUMABLE-UPLOAD-13-4.4.1-1` |
| `Appender = ServerAppends SourcePin` | our fetcher reads a URL on the client's behalf | `UP:RESUMABLE-UPLOAD-13-4.3.1-2` |
| `UploadPhase = Incomplete` | data can still be appended | `UP:RESUMABLE-UPLOAD-13-4.1.2-1` |
| `UploadPhase = Complete` | explicitly marked complete; nothing more can be appended | `UP:RESUMABLE-UPLOAD-13-4.1.2-1`, `UP:RESUMABLE-UPLOAD-13-4.1.2-3` |
| `UploadPhase = Deactivated Cancelled` | DELETE received | `UP:RESUMABLE-UPLOAD-13-4.5.1-1`, `UP:RESUMABLE-UPLOAD-13-4.5.2-1` |
| `UploadPhase = Deactivated StateLost` | any part of the state was lost (the store says `NoSuchUpload`) | `UP:RESUMABLE-UPLOAD-13-4.1.1-9`, `PD:S3API-UploadPart-API_UploadPart-1` |
| `UploadPhase = Deactivated LifetimeReached` | `max-age` elapsed | `UP:RESUMABLE-UPLOAD-13-4.1.4-7`, `UP:TUS-1.0.0-Expiration.Example-1` |
| `UploadPhase = Deactivated SizeLimitExceeded` | offset passed `max-size` | `UP:RESUMABLE-UPLOAD-13-4.1.4-3` |
| `UploadPhase = Deactivated SourceUnusable` | server appender can't supply data at the offset | `UP:RESUMABLE-UPLOAD-13-4.3.1-2` |
| `UploadPhase = Invalid` | offset exceeded a known length | `UP:RESUMABLE-UPLOAD-13-4.4.2-7` |

`offset` is a function, not a field, because then it can't disagree with the parts we actually stored. That is how the "MUST NOT decrease" rule (`UP:RESUMABLE-UPLOAD-13-4.1.1-7`) turns into a property of appending to a list. An offset only grows when the store acknowledges a part, so we never acknowledge bytes that a crash could take back. Acknowledging bytes that are only buffered would force us into `StateLost` after a restart.

`SourcePin` holds the source URL and the first strong `EntityTag` and length the source gave us, so a resumed fetch can be checked against them (theorem T43).

### Object.Drs

The finished file is a DRS object, and DRS requires `id`, `self_uri`, `size`, `created_time` and `checksums` (`DO:DRS-schemas.DrsObject-1`).

| Field | Source in the core | Provenance |
|---|---|---|
| `id :: ObjectId` | allocated when the upload resource is created | `DO:DRS-schemas.DrsObject.id-1` |
| `self_uri` | rendered by the shell from `id` | `DO:DRS-schemas.DrsObject.self_uri-1`, `DO:DRS-DrsApiPrinciples.Hostname-based-DRS-URIs-1` |
| `size` | `receiptSize`, which equals the upload length | `DO:DRS-schemas.DrsObject.size-1` |
| `created_time` | the instant of the event that produced the receipt | `DO:DRS-schemas.DrsObject.created_time-1` |
| `checksums :: NonEmpty DrsChecksum` | exactly one entry, the receipt, as a hex string | `DO:DRS-schemas.DrsObject.checksums-1`, `DO:DRS-schemas.DrsObject.checksums-2`, `DO:DRS-schemas.Checksum.checksum-1` |
| `mime_type` | the creation request's Content-Type | `DO:DRS-schemas.DrsObject.mime_type-1`, `UP:RESUMABLE-UPLOAD-13-4.2.1-9` |
| `name :: Maybe DrsName` | Content-Disposition filename, kept only if it matches `[A-Za-z0-9.-_]`, otherwise dropped | `DO:DRS-schemas.DrsObject.name-1`, `UP:RESUMABLE-UPLOAD-13-4.2.1-10`, `UP:RESUMABLE-UPLOAD-13-13-4` |
| `access_methods :: NonEmpty AccessMethod` | one `https` method with an `access_id` | `DO:DRS-schemas.DrsObject.access_methods-1`, `DO:DRS-schemas.AccessMethod-1`, `DO:DRS-schemas.AccessMethod.access_id-1` |
| `AccessMethod.available :: Bool` | `False` while the store reports the object archived | `DO:DRS-schemas.AccessMethod.available-1`, `PD:S3API-GetObject-Errors-1` |

`mkDrsObject :: Instant -> UploadResource -> Receipt -> DrsObject` is the only producer of `DrsObject`, and `Object.Drs` exports the type abstractly.

The file record that outlives the upload resource needs a lifecycle word, and here I'd borrow AIP-216's, since DRS has no state field. AIP-216 says ready resources are `ACTIVE` ("preferred over terms such as 'ready' or 'available'", `SS:AIP216-EnumValues-1`), resources being made are `CREATING`, and terminal failures are `FAILED` (`SS:AIP216-Active-3`, `SS:AIP216-Resting`).

| `FileState` constructor | Provenance |
|---|---|
| `CREATING UploadId` | `SS:AIP216-Active-3`, `SS:AIP151-StandardMethods-1` |
| `ACTIVE DrsObject` | `SS:AIP216-EnumValues-1`, `SS:AIP216-Resting` |
| `FAILED Final` (the response that ended it, kept verbatim) | `SS:AIP216-EnumValues-2`, `SS:AIP216-Resting` |

A `FAILED` record stores the response that killed it rather than a reason enum, so we don't have to invent reason words. A reason is always one of our `Final` responses.

### Rpc.Code and Import.Operation

An import is long-running work that the client didn't start with a single upload request, so it needs a status monitor (`HS:RFC9110-15.3.3-3`). The only vendored standard for "an async result that is either an error or a response" is google.longrunning, so I'd use its shape and nothing more:

```
Operation = InProgress OperationId ImportMeta                         -- done = false, no result  (SS:LRO-Operation-done, SS:LRO-Operation-result)
          | Done       OperationId ImportMeta (Either RpcStatus ObjectId)  -- done = true, exactly one result
ImportMeta = { offset :: UploadOffset, length :: Maybe UploadLength }     -- progress belongs in metadata (SS:LRO-Operation-metadata, SS:AIP151-Guidance-2)
RpcStatus  = { code :: {c:Code | c /= OK} }                                -- an error is never OK (SS:ABSL-STATUSOR-2)
```

`Code` has all 17 constructors (`SS:GRPC-STATUSCODES-OK` through `SS:GRPC-STATUSCODES-UNAUTHENTICATED`), with `codeNumber` from the `RPC-CODE-<NAME>-http` statements in status-and-supervision (UNAUTHENTICATED is 16 even though code.proto declares it right after PERMISSION_DENIED = 7). Cancelling gives `Done (Left CANCELLED)` and does not delete the operation (`SS:LRO-CancelOperation-3`). `Code` never becomes an HTTP status on its own. The code.proto mapping sends CANCELLED to 499 (`SS:RPC-CODE-CANCELLED-http`), and 499 is not in the IANA registry, so the core never emits it.

## The state and the events that move it

```
State = { uploads   :: Map UploadId UploadResource
        , files     :: Map ObjectId FileState
        , imports   :: Map OperationId (UploadId, Maybe RpcStatus)
        , tombstone :: Set UploadId           -- uploads we know are permanently gone; dropped by Forget
        , requests  :: Map ReqId PendingAnswer -- requests whose final answer waits on the store
        , policy    :: Policy }

Policy = { registry       :: Strict | AllowTemporaryAndRequested  -- gates 104 and the two draft problem types
         , storeAlgorithm :: {a:ChecksumAlgorithm | supports a Multipart FULL_OBJECT}
         , limits         :: UploadLimit                           -- minAppendSize = the store's minimum part size
         , pendingDelay   :: DelaySeconds                          -- Retry-After on DRS 202
         , transportRetry :: {n:Int | 0 <= n && n <= 1} }
```

`Event = Event { at :: Instant, what :: Occurrence }`. Every `Occurrence` is already parsed protocol data, and none of them carries representation bytes:

| Occurrence | Carries |
|---|---|
| `Requested ReqId Authz Request` | the shell's verdict on credentials, and a parsed request (below) |
| `PartStored UploadId PartNumber Size` | the store acknowledged one UploadPart |
| `ContentEnded ReqId Ending` | `FullyProcessed` or `Interrupted` (`UP:RESUMABLE-UPLOAD-13-4.4.2-2`) |
| `StoreAnswered StoreCall StoreReport` | the store's verdict on PutObject, CompleteMultipartUpload, HeadObject or AbortMultipartUpload |
| `SourceAnswered OperationId SourceReport` | the import source's status, validators, Content-Range and length |
| `SourceFailed OperationId TransportFault` | `NothingWritten`, `ReadFailed`, `IdleClosed`, `TimedOut` (ported from Go transport.go) |
| `DeadlineReached ReqId` | the shell's response deadline for a request whose answer waits on the store |
| `LifetimeReached UploadId` | the shell's timer for `expiresAt` |
| `Forget UploadId` | the shell drops a tombstone (`HS:RFC9110-15.5.11-3`) |

`Authz = NoCredentials | InvalidCredentials | Insufficient Disclosure | Authorized` and `Disclosure = Reveal | Hide`. The shell checks credentials, but the core decides what that means on the wire.

`Request` is a closed sum: `CreateUpload`, `AppendUpload`, `RetrieveOffset`, `CancelUpload`, `DiscoverOptions`, `GetDrsObject`, `GetAccessUrl`, `GetBytes`, `StartImport`, `GetOperation`, `CancelOperation`. Each carries only the parsed fields the protocol defines for it. For example, `AppendUpload` carries `Maybe UploadOffset`, `Maybe UploadComplete`, `Maybe UploadLength`, `Maybe ContentLength` and `Maybe ReprDigest`.

`Command` is equally closed:

- `SendInterim ReqId Interim` and `Respond ReqId Answer`;
- `TerminateRequest ReqId` (`UP:RESUMABLE-UPLOAD-13-4.6-4`, `UP:RESUMABLE-UPLOAD-13-4.5.2-2`);
- the store calls, named after the S3 operations they are: `CreateMultipartUpload key alg FULL_OBJECT`, `UploadPart key n`, `CompleteMultipartUpload key parts mpuObjectSize (Maybe forwardedDigest)`, `PutObject key alg (Maybe forwardedDigest)`, `HeadObjectChecksum key` (ChecksumMode `ENABLED`, `PD:S3API-GetObject-request-header-ChecksumMode-1`), `AbortMultipartUpload key`, `ListParts key`;
- `FetchSource OperationId Url (Maybe (Offset, EntityTag))`, which resumes with Range plus If-Range;
- `ArmTimer UploadId Instant`.

## The step function, row by row

`step :: State -> Event -> (State, [Command])` is total (LiquidHaskell checks totality and termination by default). Every request goes through the same gate, in this order, before any per-request row applies:

1. Authorization. `NoCredentials` and `InvalidCredentials` give 401 with a `Challenge` (`HS:RFC9110-11.4-1`, `HS:RFC9110-15.5.2-2`). `Insufficient Reveal` gives 403 (`HS:RFC9110-11.4-2`) and `Insufficient Hide` gives 404 (`HS:RFC9110-15.5.4-4`). Authorization runs before everything else because servers "MUST return authorization errors in preference to other errors" (`DO:RFC4918-8.1-1`), "MUST do authorization checks before checking any HTTP conditional header" (`DO:RFC4918-8.5-1`), and permission "must be checked prior to checking if the resource or parent exists" (`SS:AIP193-PermissionDenied-1`).
2. Existence. An id in `tombstone` gives 410 (`HS:RFC9110-15.5.11-1`; "SHOULD be used if the Server is keeping track of expired uploads", `UP:TUS-1.0.0-Expiration.Headers.Upload-Expires-3`; `UP:TUS-1.0.0-Termination.Requests.DELETE-1`). An unknown id gives 404 (`HS:RFC9110-15.5.5-1`, `DO:DRS-responses.404NotFoundDrsObject-1`).
3. Required fields. A field the method requires that parsed as absent gives 400 (`UP:RESUMABLE-UPLOAD-13-4.4.1-2`, `UP:RESUMABLE-UPLOAD-13-4.4.1-3`, `HS:RFC9110-15.5.1`).
4. The per-request rows below. Preconditions only run inside a row that would otherwise answer 2xx (`HS:RFC9110-13.2.1-2`).

### Upload resource rows

`o` is `offset u`, `L` is `length u`, `c` is a request's content length, and "?0" and "?1" are the Upload-Complete values on the response.

| Phase | Event | Next phase | Commands | Answer | Provenance |
|---|---|---|---|---|---|
| (none) | `CreateUpload` with `?0`, lengths consistent, within limits, `c = 0` or `c >= minAppendSize` | `Incomplete`; file `CREATING` | `CreateMultipartUpload`; `SendInterim 104 Location Upload-Limit` only under `AllowTemporaryAndRequested` | after content: 201, Location, Upload-Limit, ?0 | `UP:RESUMABLE-UPLOAD-13-4.2.2-1`, `UP:RESUMABLE-UPLOAD-13-4.2.2-2`, `UP:RESUMABLE-UPLOAD-13-4.2.2-5`, `UP:RESUMABLE-UPLOAD-13-4.2.1-8` |
| (none) | `CreateUpload` with `?1` (whole representation in one request) | `Complete`, shape `SinglePart`; file `CREATING` | `PutObject alg forwardedDigest` | waits on the store (rows below) | `UP:RESUMABLE-UPLOAD-13-4.2.2-4`, `UP:RESUMABLE-UPLOAD-13-10.1.1-2`, `PD:S3UG-INTEGRITY-UPLOAD-SinglePartUploads-Checksums-1` |
| (none) | `CreateUpload` with Upload-Length and Content-Length disagreeing on `?1` | unchanged | none | 400 `InconsistentUploadLength` (or `AboutBlank` under `Strict`), ?0 | `UP:RESUMABLE-UPLOAD-13-4.1.3-6`, `UP:RESUMABLE-UPLOAD-13-4.1.3-7`, `UP:RESUMABLE-UPLOAD-13-7.2-2` |
| (none) | `CreateUpload` with a length above `maxSize` | unchanged | none | 413, Upload-Limit | `UP:RESUMABLE-UPLOAD-13-4.1.4-3`, `UP:RESUMABLE-UPLOAD-13-4.1.4-17`, `UP:TUS-1.0.0-Creation.Requests.POST-7` |
| (none) | `CreateUpload` that names a destination the shell rejected | unchanged | none | the `DestinationFault` status (see "What a client is told") | |
| (none) | `CreateUpload` with a client Repr-Digest the store can't validate as full-object for this shape | unchanged | none | 400 `DigestUnsupportedAlgorithms`, with Want-Repr-Digest naming what we can check | `PD:DIGEST-PROBLEMS-3.1-1`, `PD:DIGEST-PROBLEMS-3.1-5`, `PD:RFC9530-4-1` |
| `Incomplete` | `AppendUpload` while `inFlight = Just r` | same | `TerminateRequest r`, then the row that applies | as that row | `UP:RESUMABLE-UPLOAD-13-4.6-4`, `UP:RESUMABLE-UPLOAD-13-4.6-5` |
| `Incomplete` | `AppendUpload` with Upload-Offset `p /= o` | unchanged | none | 409, ?0, Upload-Offset `o`, `MismatchingUploadOffset {expected = o, provided = p}` (`AboutBlank` under `Strict`) | `UP:RESUMABLE-UPLOAD-13-4.4.2-3`, `UP:RESUMABLE-UPLOAD-13-7.1-2`, `UP:TUS-1.0.0-Core.Requests.PATCH-2` |
| `Incomplete` | `AppendUpload ?0`, `p = o`, `c < minAppendSize` | unchanged | none | 400, Upload-Limit, ?0 | `UP:RESUMABLE-UPLOAD-13-4.1.4-6`, `UP:RESUMABLE-UPLOAD-13-4.1.4-17` |
| `Incomplete` | `AppendUpload`, `p = o`, `L = Just l`, `o + c > l` | unchanged | none | 413, ?0 | `UP:RESUMABLE-UPLOAD-13-4.4.2-7`, `UP:TUSD-2.10.1-writeChunk-1`, `HS:RFC9110-15.5.14-1` |
| `Incomplete` | `AppendUpload ?0`, `p = o`, sizes fine | same, `inFlight = Just r` | `UploadPart key (k+1)` | waits for `ContentEnded` | `UP:RESUMABLE-UPLOAD-13-4.4.2-1` |
| `Incomplete` | `PartStored` that would push offset past a known `L` | `Invalid` | `AbortMultipartUpload` | the in-flight request gets 413 | `UP:RESUMABLE-UPLOAD-13-4.4.2-7` |
| `Incomplete` | `PartStored` that would push offset past `maxSize` | `Deactivated SizeLimitExceeded` | `AbortMultipartUpload` | the in-flight request gets 413, Upload-Limit | `UP:RESUMABLE-UPLOAD-13-4.1.4-3`, `UP:RESUMABLE-UPLOAD-13-4.1.4-17` |
| `Incomplete` | `PartStored` otherwise | same, parts extended | none | none yet | `UP:RESUMABLE-UPLOAD-13-4.1.1-1` |
| `Incomplete` | `ContentEnded r FullyProcessed` for a `?0` append | same, `inFlight = Nothing` | none | 204, ?0, Upload-Offset `o` | `UP:RESUMABLE-UPLOAD-13-4.4.2-5`, `UP:RESUMABLE-UPLOAD-13-4.1.1-6`, `UP:TUS-1.0.0-Core.Requests.PATCH-4` |
| `Incomplete` | `ContentEnded r Interrupted` | same, `inFlight = Nothing`, only the stored prefix counts | none | none (the connection is gone) | `UP:RESUMABLE-UPLOAD-13-4.4.2-2`, `UP:RESUMABLE-UPLOAD-13-4.2.2-11` |
| `Incomplete` | `AppendUpload ?1`, `p = o`, `L` consistent with `o + c` | same, `length = Just (o + c)`, `inFlight = Just r` | `UploadPart key (k+1)` if `c > 0` | waits for `ContentEnded` | `UP:RESUMABLE-UPLOAD-13-4.4.1-3`, `UP:RESUMABLE-UPLOAD-13-4.1.3-3`, `UP:RESUMABLE-UPLOAD-13-4.4.2-7` |
| `Incomplete` | `ContentEnded r FullyProcessed` for a `?1` append, authz `Authorized` | `Complete` | `CompleteMultipartUpload key parts (o) forwardedDigest` | waits on the store | `UP:RESUMABLE-UPLOAD-13-4.1.2-3`, `UP:RESUMABLE-UPLOAD-13-13-6`, `UP:RESUMABLE-UPLOAD-13-13-7`, `PD:S3API-CompleteMultipartUpload-request-header-MpuObjectSize-1` |
| `Incomplete` | `AppendUpload ?1` with an inconsistent length | unchanged | none | 400 `InconsistentUploadLength`, ?0 | `UP:RESUMABLE-UPLOAD-13-4.1.3-6`, `UP:RESUMABLE-UPLOAD-13-7.2-1` |
| `Incomplete` | `RetrieveOffset` | same (in-flight request terminated first) | `TerminateRequest` if any | 204, ?0, Upload-Offset `o`, Upload-Length if known, Upload-Limit, Cache-Control: no-store | `UP:RESUMABLE-UPLOAD-13-4.3.2-1`, `UP:RESUMABLE-UPLOAD-13-4.3.3-1`, `UP:RESUMABLE-UPLOAD-13-4.6-4`, `UP:TUS-1.0.0-Core.Requests.HEAD-1` |
| `Complete` | `RetrieveOffset` | same | none | 204, ?1, Upload-Offset = Upload-Length, Cache-Control: no-store | `UP:RESUMABLE-UPLOAD-13-4.1.2-5`, `UP:TUS-1.0.0-Concatenation-7` |
| `Complete` | `AppendUpload ?1`, `p = L`, `c = 0`, final answer already given | same | none | the stored final answer, replayed | `UP:RESUMABLE-UPLOAD-13-4.4.2-6` |
| `Complete` | any other `AppendUpload` | same | none | 409, ?0, Upload-Offset `L` (the status is a choice; see open questions) | `UP:RESUMABLE-UPLOAD-13-4.1.2-6` |
| `Incomplete` or `Complete` | `CancelUpload` | `Deactivated Cancelled`; file stays as it is | `TerminateRequest` for any in-flight request; `AbortMultipartUpload` then `ListParts` if the upload never completed | 204 | `UP:RESUMABLE-UPLOAD-13-4.5.2-1`, `UP:RESUMABLE-UPLOAD-13-4.5.2-2`, `UP:RESUMABLE-UPLOAD-13-4.5.3-1`, `HS:RFC9110-9.3.5-3`, `PD:S3API-AbortMultipartUpload-API_AbortMultipartUpload-2` |
| `Incomplete` | `LifetimeReached` | `Deactivated LifetimeReached` | `TerminateRequest` if any, `AbortMultipartUpload` | none | `UP:RESUMABLE-UPLOAD-13-4.1.4-7`, `UP:TUS-1.0.0-Expiration-1` |
| `Incomplete` | `StoreAnswered _ (Failed NoSuchUpload)` | `Deactivated StateLost`; file `FAILED` | `TerminateRequest` if any | in-flight request: 410 | `UP:RESUMABLE-UPLOAD-13-4.1.1-9`, `PD:S3API-Error-NoSuchUpload-1` |
| `Deactivated _` or `Invalid` | any request | unchanged; the id is in `tombstone` | none | 410 | `UP:RESUMABLE-UPLOAD-13-4.1.1-9`, `UP:RESUMABLE-UPLOAD-13-4.4.2-7`, `HS:RFC9110-15.5.11-1` |

A request that leaves `Incomplete` for `Deactivated` or `Invalid` also puts the id into `tombstone` and removes the resource, and `Forget` later drops the tombstone. After that the id answers 404, which RFC 9110 allows because the 410 mark doesn't have to be kept "for any length of time" (`HS:RFC9110-15.5.11-3`).

### File and store rows

| File state | Event | Next | Commands | Answer to the waiting completing request | Provenance |
|---|---|---|---|---|---|
| `CREATING` | `StoreAnswered` with a report that `vouch` accepts | `ACTIVE (mkDrsObject at u receipt)` | none | 201, Location = the DRS object, ?1, ETag, Repr-Digest when `reprDigestOf` is `Just` | `HS:RFC9110-9.3.3-3`, `HS:RFC9110-15.3.2-1`, `UP:RESUMABLE-UPLOAD-13-4.4.2-4`, `PD:S3UG-INTEGRITY-UPLOAD-checking-object-integrity-upload-1` |
| `CREATING` | `StoreAnswered` 2xx with `NotVouched NoChecksumReturned` | `CREATING` | `HeadObjectChecksum` (once) | none yet | `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-2`, `PD:S3UG-MPU-mpuAndPermissions-1` |
| `CREATING` | the second `NotVouched` for the same object, or any other `NotVouched` | `FAILED f`, where `f` is the answer | none (cleanup is an open question) | 500, ?1 | `HS:RFC9110-15.6.1`, `UP:RESUMABLE-UPLOAD-13-4.4.1-5` |
| `CREATING` | `StoreAnswered (Failed BadDigest)` when we forwarded a client digest | `FAILED f` | none | 400 `DigestMismatchedValues`, ?1 | `PD:S3UG-INTEGRITY-UPLOAD-Full-object-checksums-2`, `PD:DIGEST-PROBLEMS-3.3-1`, `PD:S3API-CompleteMultipartUpload-request-header-ChecksumType-1` |
| `CREATING` | `StoreAnswered (Failed e)` with `classify e` `Transient` or `Throttling`, attempts left | `CREATING` | the same store call again | none yet | `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-3`, `PD:AWSSDK-RETRY-which-errors-are-retried-1` |
| `CREATING` | the same, attempts exhausted | `CREATING` (the store call stays outstanding at the shell's next retry window) | none | 503, ?1, Retry-After | `HS:RFC9110-15.6.4-1`, `HS:RFC9110-15.6.4-2` |
| `CREATING` | `StoreAnswered (Failed e)` with `classify e = NonRetryable` | `FAILED f` | none | 500, ?1 | `PD:AWSSDK-RETRY-error-classification-3`, `HS:RFC9110-15.6.1` |
| `CREATING` | `DeadlineReached r` | unchanged | none | 202, ?1, Location = the DRS object | `HS:RFC9110-15.3.3-1`, `HS:RFC9110-15.3.3-3`, `UP:RESUMABLE-UPLOAD-13-4.4.2-4` |
| `ACTIVE` | `StoreAnswered (Failed InvalidObjectState)` on a download | `ACTIVE` with `available = False` | none | see downloads | `PD:S3API-GetObject-Errors-1`, `DO:DRS-schemas.AccessMethod.available-1` |

The 202 on a deadline is allowed because the draft only forbids a 2xx with Upload-Complete false or missing in reply to a completing request (`UP:RESUMABLE-UPLOAD-13-4.4.2-4`), and our 202 carries ?1. After that, the client learns the outcome from the DRS object: 202 with Retry-After while it is `CREATING`, 200 once it is `ACTIVE`.

### Import rows

`StartImport` creates an upload resource with `ServerAppends`, a `CREATING` file and an `InProgress` operation, emits `CreateMultipartUpload` and `FetchSource`, and answers 202 with Location = the operation (`HS:RFC9110-15.3.3-1`, `HS:RFC9110-15.3.3-3`, `SS:AIP151-Guidance-1`). From then on the fetcher is just another appender, so the upload rows above apply unchanged. The rows specific to imports decide what the fetcher does with the source's answers:

| Source event | Decision | Provenance |
|---|---|---|
| 200 with a strong ETag and Content-Length | pin `(etag, length)`, set `length`; content flows as parts | `HS:RFC9110-8.8.1-6`, `HS:RFC9110-15.3.1-1` |
| 206 whose Content-Range first-pos equals `o` and whose ETag strongly matches the pin | append | `HS:RFC9110-15.3.7.3-1`, `HS:RFC9110-15.3.7.3-2`, `HS:RFC9110-8.8.3.2-1` |
| 206 with any other first-pos or validator, or an invalid Content-Range | `Deactivated SourceUnusable`; the operation finishes with `Done (Left ABORTED)` | `HS:RFC9110-14.4-5`, `UP:RESUMABLE-UPLOAD-13-4.3.1-2`, `SS:GRPC-STATUSCODES-ABORTED` |
| 200 to a resumed (If-Range) fetch | the source changed: same as above | `HS:RFC9110-13.1.5-1`, `HS:RFC9110-13.1.5-6` |
| source content ended with a known length reached | the server marks the upload complete; `CompleteMultipartUpload` | `UP:RESUMABLE-UPLOAD-13-4.1.2-1` |
| 3xx with Location | follow, up to a configured bound | `HS:RFC9110-15.4-2`, `HS:RFC9110-15.4-3` |
| a status or fault where `retryDecision` says retry | `FetchSource` again with Range and If-Range | `HS:RFC9110-14-1`, `HS:RFC9110-13.1.5-1` |
| a status where `retryDecision` says stop | `Deactivated SourceUnusable`; `Done (Left (fromHttp status))` | `SS:GRPC-HTTPMAP-scope-2` and the table rows; see open questions |
| `SourceFailed` (deadline) | `Done (Left DEADLINE_EXCEEDED)` | `SS:GRPC-STATUSCODES-libgen-noresponse` |
| `SourceFailed` (connection broke mid-transfer), no retries left | `Done (Left UNAVAILABLE)` | `SS:GRPC-STATUSCODES-libgen-connbreak` |
| `CancelOperation` | `Deactivated Cancelled`; `Done (Left CANCELLED)`; the operation is kept | `SS:LRO-CancelOperation-3`, `UP:RESUMABLE-UPLOAD-13-4.5.1-1` |
| file becomes `ACTIVE` | `Done (Right objectId)` | `SS:LRO-Operation-result`, `SS:AIP151-Guidance-4` |

### Download rows

`GetBytes` never changes state. After the gate, the core finds the file, and a file that is not `ACTIVE` answers 404 for `GetBytes`. It then runs the precondition ladder (port 1 below) with our own ETag and Last-Modified, then the range rules, and answers:

- 304 with ETag (`HS:RFC9110-15.4.5-2`);
- 412 (`HS:RFC9110-15.5.13`);
- 200 with ETag, Last-Modified, Content-Length, Accept-Ranges: bytes, and Repr-Digest when expressible (`HS:RFC9110-15.3.1-2`, `PD:RFC9530-3-1`);
- 206 with one Content-Range (`HS:RFC9110-15.3.7.1`), when exactly one valid, satisfiable range is requested and If-Range, if present, is true;
- 416 with `Content-Range: bytes */len` (`HS:RFC9110-14.4-6`, `HS:RFC9110-15.5.17-2`), when the ranges-specifier is valid but unsatisfiable.

A request for several ranges is answered as if Range were absent (200), since a server MAY ignore Range (`HS:RFC9110-14.2-1`) and that keeps multipart responses out of the core.

The ETag is the store's ETag for the object, sent strong. That is justified because a DRS id "MUST always return the same object data" (`DO:DRS-DrsApiPrinciples.DRS-IDs-2`), so the one representation never changes and the tag is trivially unique over the resource's lifetime (`HS:RFC9110-8.8.1-2`), and because S3 says objects with different data get different entity tags (`PD:S3API-CompleteMultipartUpload-response-ETag-1`). Last-Modified is `created_time`.

## What a client is told

The brief names eight circumstances a person can be in with a file. Each one maps to fields a standard already defines:

| Circumstance | Request | What the core answers | Provenance |
|---|---|---|---|
| in flight up (browser) | HEAD on the upload resource | 204, `Upload-Complete: ?0`, `Upload-Offset`, `Upload-Length` if known, `Upload-Limit`, `Cache-Control: no-store` | `UP:RESUMABLE-UPLOAD-13-4.3.2-1`, `UP:RESUMABLE-UPLOAD-13-4.3.3-1` |
| in flight up (browser or import) | DRS GetObject | 202, `Retry-After: <delay-seconds>` | `DO:DRS-responses.202Accepted-1`, `DO:DRS-responses.202Accepted.Retry-After-1`, `DO:DRS-paths.objects.{object_id}.get-1` |
| in flight up (import) | GetOperation | 200, `Operation{done:false, metadata:{offset, length}}` | `SS:LRO-Operation-done`, `SS:LRO-Operation-metadata` |
| ready | DRS GetObject | 200, the `DrsObject` with `size` and at least one checksum | `DO:DRS-schemas.DrsObject-1`, `DO:DRS-schemas.DrsObject.checksums-1` |
| accessible | the DrsObject's access method | `available: true` | `DO:DRS-schemas.AccessMethod.available-1` |
| downloadable | GetAccessURL, then GET | 200 `AccessURL{url, headers}`; GET then answers 200 or 206 with ETag, Last-Modified, Accept-Ranges | `DO:DRS-paths.objects.{object_id}.access.{access_id}.get-1`, `DO:DRS-paths.objects.{object_id}.access.{access_id}.get-2`, `HS:RFC9110-15.3.1-2` |
| in flight down | GET with Range | 206 with Content-Range, one piece per request; the server keeps no state for this | `HS:RFC9110-15.3.7-1`, `HS:RFC9110-14-1` |
| inaccessible (archived or thawing) | the DrsObject, then GetAccessURL | `available: false`; GetAccessURL answers 202 with Retry-After | `DO:DRS-schemas.AccessMethod.available-1`, `DO:DRS-responses.202Accepted-1` |
| inaccessible (upload gone) | anything on the upload resource | 410 while the tombstone is kept, 404 after | `HS:RFC9110-15.5.11-1`, `HS:RFC9110-15.5.5-1`, `UP:TUS-1.0.0-Expiration.Headers.Upload-Expires-3` |
| inaccessible (file never became ready) | DRS GetObject on a `FAILED` file | 404 (DRS's table has no 410) | `DO:DRS-responses.404NotFoundDrsObject-1`, `DO:DRS-paths.objects.{object_id}.get-1` |
| wrong permissions (no or bad credentials) | any | 401 with `WWW-Authenticate` | `HS:RFC9110-11.4-1`, `HS:RFC9110-15.5.2-2`, `DO:DRS-responses.401Unauthorized-1` |
| wrong permissions (valid but insufficient) | any | 403, or 404 when the shell asks us to hide existence | `HS:RFC9110-11.4-2`, `HS:RFC9110-15.5.4-3`, `HS:RFC9110-15.5.4-4`, `DO:DRS-responses.403Forbidden-1` |
| wrong destination | CreateUpload or StartImport | the `DestinationFault` status, below | |

`DestinationFault` is a closed sum the shell hands the core, because the core does not own a namespace yet (that is an open question):

| Constructor | Status | Provenance |
|---|---|---|
| `ParentMissing` | 409 | `DO:RFC4918-9.7.1-2`, `HS:RFC9110-15.5.10-1` |
| `AlreadyExistsWithIfNoneMatchStar` | 412 | `HS:RFC9110-13.1.2-3`, `HS:RFC9110-13.1.2-6` |
| `NotOurOrigin` | 421 | `HS:RFC9110-15.5.20-1`, `HS:RFC9110-7.4-3` |
| `MediaTypeRefused` | 415 | `HS:RFC9110-15.5.16`, `HS:RFC9110-9.3.4-6` |
| `QuotaExhausted` | 507 | `DO:RFC4918-11.5-1`, `UP:RESUMABLE-UPLOAD-13-13-7` |
| `TooLargeForDestination` | 413 | `HS:RFC9110-15.5.14-1` |

Rendering applies these rules to every response:

- Every 4xx and 5xx answer to anything but HEAD carries a problem document, `AboutBlank` at minimum (`HS:RFC9110-15.5-2`, `HS:RFC9110-15.6-2`, `PD:RFC9457-3-1`). A HEAD answer carries none (`HS:RFC9110-9.3.2-1`).
- An `Answer` is either `ForUpload UploadComplete Final` or `Plain Final`. Anything that answers a completing request is built by a constructor that hard-codes `?1`.
- Retry-After appears only on 3xx, 413, 429, 503 and DRS 202, the codes whose text mentions it (`HS:RFC9110-10.2.3-3`, `HS:RFC9110-15.5.14-3`, `HS:RFC6585-4-2`, `HS:RFC9110-15.6.4-2`, `DO:DRS-responses.202Accepted-1`).
- No 301, 302 or 303 is ever emitted on the upload surface (`UP:RESUMABLE-UPLOAD-13-4.2.2-10`, `UP:RESUMABLE-UPLOAD-13-4.3.2-2`, `UP:RESUMABLE-UPLOAD-13-4.4.2-9`, `UP:RESUMABLE-UPLOAD-13-4.5.2-3`).
- A 104 progress interim never carries Location (`UP:RESUMABLE-UPLOAD-13-4.4.2-8`). A 104 announce interim always carries Location and Upload-Limit (`UP:RESUMABLE-UPLOAD-13-4.2.2-2`). Both exist only under `AllowTemporaryAndRequested`.
- OPTIONS on a creation target answers with Upload-Limit (`UP:RESUMABLE-UPLOAD-13-4.1.4-13`).

## Code we port and what we fix on the way

### 1. The precondition ladder (Go net/http fs.go)

The source is `references/http-semantics/code/go/fs.go:431-468` (scanETag, etagStrongMatch, etagWeakMatch) and `:470-669` (condResult, the five check functions, checkPreconditions). It goes into `Http.Conditional` as `ladder :: LadderInput -> LadderOutcome`. `LadderInput` holds, for each of If-Match, If-Unmodified-Since, If-None-Match, If-Modified-Since and If-Range, one of `Absent | Holds | Fails`, plus the method class (`GetOrHead`, `Get`, `Other`), whether Range is present, and whether the state change already happened. `LadderOutcome = Fail412 | NotModified304 | AlreadyApplied2xx | Proceed RangeUse`. The domain is finite, so the whole function is checked against `HS:RFC9110-13.2.2-1` through `HS:RFC9110-13.2.2-7` by exhaustion. I'm fixing five things rather than copying them:

- Go never takes the "already succeeded" branch of `HS:RFC9110-13.2.2-2` and `HS:RFC9110-13.2.2-3` (`HS:RFC9110-13.1.1-6`, `HS:RFC9110-13.1.4-7`). The port has an explicit `AlreadyApplied2xx` constructor. No request we accept today is a conditional state change, so it stays unreachable for now, but the ladder is honest about it.
- `checkIfRange` compares HTTP-dates to the exact second without first asking whether the date is a strong validator (`HS:RFC9110-13.1.5-4` step 1, `HS:RFC9110-8.8.2.2`). The port treats a date in If-Range as weak, so the condition is false, unless strength can be deduced. The deduction rules aren't in our statements, so for now it is always weak.
- Go evaluates If-Match without checking that it is the origin server (`HS:RFC9110-13.2.2-2`, `HS:RFC9110-13.2.1-3`). The core is always the origin, so the port carries that as a type-level fact rather than a runtime check.
- Go evaluates If-Range for HEAD too. RFC 9110 defines Range only for GET (`HS:RFC9110-14.2-2`) and step 5 says GET (`HS:RFC9110-13.2.2-6`).
- Header parsing (scanETag) stays in the shell's parser. The ladder only sees the three-valued results, so the "ignore when invalid" rules (`HS:RFC9110-13.1.3-2`, `HS:RFC9110-13.1.4-2`) live in one parser.

### 2. Outbound retry (urllib3 retry.py and Go transport.go)

These come from `references/http-semantics/code/urllib3/retry.py:184-189, 308-333, 379-407`, `references/http-semantics/code/go/request.go:1543-1557` and `references/http-semantics/code/go/transport.go:756-800`. The port is `retryDecision :: Method -> Outcome -> Attempts -> RetryDecision`, where `Outcome` is either a received status with a parsed Retry-After, or a transport fault. `RetryDecision = DoNotRetry | RetryAfter Seconds | RetryOnNewConnection | RetryWithBackoff`. It applies to our own outbound calls (the import fetcher, and the store if the shell routes store calls through it). Here is what changes from the sources:

- The method set is urllib3's `DEFAULT_ALLOWED_METHODS`, which is exactly the safe-or-idempotent set (T9). Go's `isReplayable` leaves out PUT and DELETE, even though they are idempotent (`HS:RFC9110-9.2.2-1`). It also adds the non-standard Idempotency-Key header, which can't enter our vocabulary.
- urllib3's `RETRY_AFTER_STATUS_CODES = {413, 429, 503}` is kept. 413 only counts when Retry-After is present, since 413 is temporary only then (`HS:RFC9110-15.5.14-3`).
- 421 gives `RetryOnNewConnection` for any method (`HS:RFC9110-15.5.20-2`). urllib3 doesn't model it.
- 507 always gives `DoNotRetry` (`HS:RFC4918-11.5-2`). urllib3 doesn't model it.
- A transport fault is retried only when nothing was written, or when the method is idempotent and the fault is a read failure or an idle close (Go's `shouldRetryRequest`, `HS:RFC9110-9.2.2-4`). A connection-failure retry is attempted at most once, because "A client SHOULD NOT automatically retry a failed automatic retry" (`HS:RFC9110-9.2.2-8`). That budget is `Policy.transportRetry`, refined to 0 or 1. Status-driven waits with Retry-After are a different thing: the server asked for the follow-up request (`HS:RFC9110-10.2.3-1`), so they get their own budget.

### 3. The status table (http-types Status.hs, Go status.go, CPython http/__init__.py)

These are used only for shape: the class predicates at `references/http-semantics/code/http-types/Status.hs:783-830` became `Class` and `classOf`. The data comes from the IANA CSV through `tools/gen-status.py`, for the reason given under Http.Status.

### 4. The composite checksum detector (aws-sdk-js-v3 isChecksumWithPartNumber.ts)

It ports into `Store.Checksum.parseChecksumValue` as a total parser, which is theorem T31. The middleware that uses it (`PD:AWS-SDK-JS-flexibleChecksumsResponseMiddleware-flexibleChecksumsResponseMiddleware-1`) silently skips validation when every checksum is composite. The port turns that silence into the `NotVouched (ChecksumTypeIs COMPOSITE)` constructor, so a composite value can't reach `Receipt`.

### 5. S3 tables (api-models-aws, aws docs, smithy-typescript)

`ChecksumAlgorithm`, `ChecksumType`, the support table, the error table and the classifier are data, ported as closed sums with total functions. They are cited above. The AWS SDK also retries internally, with a default of 3 attempts (`PD:AWSSDK-RETRY-retry-settings-1`). If the SDK retries and then the core retries again, we'd have two retry authorities with different budgets, which is exactly the duplication I'm trying to remove. I'd ask the shell to run the SDK with max attempts 1 so the core decides every retry.

### 6. Deliberately not ported into the core

- CRC-64/NVME (`aws-checksums/tests/crc64_test.c`, `Crc64NvmeJs.ts`, the combine routine in `crc64_sw.c`). The brief says we never compute our own digest and call it proof, so this belongs in a test-oracle package if we ever want one. The combine identity is still worth keeping as a documented reason why S3 offers FULL_OBJECT for multipart uploads only with CRCs (`PD:S3UG-INTEGRITY-UPLOAD-Full-object-checksums-3`, `PD:AWS-CHECKSUMS-crc.h-aws_checksums_crc64nvme_combine-1`).
- Funnel's TES transitions (`code/funnel-v0.11.14/tes/states.go`, `database/boltdb/events.go`). TES states describe compute tasks, Funnel's two functions disagree with each other, and our files are covered by the draft plus AIP-216, so nothing here needs them.
- golang.org/x/net/webdav handlers. Only their 409-for-missing-parent and 412-for-Overwrite rules survive, as `DestinationFault` data.
- tusd's error table. Its statuses are kept where a spec MUSTs them (409, 413, 412, 404), but its codes are tusd vocabulary and stay out. Its 500 for timeouts (`UP:TUSD-2.10.1-errors.ErrReadTimeout-2`) exists to coax clients into retrying, and the draft's own heuristics (`UP:RESUMABLE-UPLOAD-13-4.7-2` through `UP:RESUMABLE-UPLOAD-13-4.7-5`) make that unnecessary.
- OTP supervision and gRPC A6 backoff. They are runtime policy for the shell, not decisions about what a client is told.

## Theorems

"LH" means a LiquidHaskell refinement or reflection proof checked by z3 at compile time. "Exhaustion" means a check in `test/Exhaustive.hs` that enumerates the whole finite domain (every input type derives `Bounded` and `Enum`, or carries an explicit universe list whose completeness is itself proven). "Construction" means the type can't express the bad case at all.

| # | Name | Statement | Method | Cites |
|---|---|---|---|---|
| T1 | status-registry | `code` is injective on the 64 constructors, `fromCode (code s) = Registered s` for every `s`, and every unassigned range row maps to `Unrecognized` | Exhaustion (64 constructors, 100..599) | `HS:RFC9110-15-1`, `HS:IANA-HTTP-Status-Codes-105-199`, `HS:IANA-HTTP-Status-Codes-512-599` |
| T2 | unrecognized-is-x00 | for every `n` in 100..599 with no registered row, `classOf (interpretCode n) = classOf n` and `interpretCode n = classBase (classOf n)` | LH reflection with a case split on `classOf` (the probed technique) | `HS:RFC9110-15-4`, `HS:RFC9110-15-2` |
| T3 | invalid-is-5xx | for every `n` outside 100..599, `interpret (Invalid n) = ServerError` | LH refinement | `HS:RFC9110-15-5`, `HS:RFC9110-15-6` |
| T4 | emitted-are-registered | every status `render` can produce has `registration` `Permanent`, or `Temporary` only under `AllowTemporaryAndRequested`; no `Unused` or `Obsoleted` status, and no 499 | Exhaustion over `Final` and `Interim` constructors | `HS:IANA-HTTP-Status-Codes-104`, `HS:IANA-HTTP-Status-Codes-306`, `HS:IANA-HTTP-Status-Codes-418`, `HS:IANA-HTTP-Status-Codes-510`, `SS:RPC-CODE-CANCELLED-http` |
| T5 | required-fields | 401 carries WWW-Authenticate, 405 carries Allow, 206 carries Content-Range, 304 carries ETag, 1xx and 204 carry no Content-Length | Construction (the fields are constructor arguments) plus exhaustion over `render` | `HS:RFC9110-15.5.2-2`, `HS:RFC9110-15.5.6`, `HS:RFC9110-15.3.7.1`, `HS:RFC9110-15.4.5-2`, `HS:RFC9110-8.6-4` |
| T6 | problem-status-agrees | the `status` member of every rendered problem equals the response status, and every non-`AboutBlank` type is only paired with its recommended status | Construction (no status field) plus exhaustion over `Final` | `PD:RFC9457-3.1.2-2`, `PD:IANA-PROBLEM-TYPES-digest-mismatched-values-1`, `UP:RESUMABLE-UPLOAD-13-14.4-1`, `UP:RESUMABLE-UPLOAD-13-14.4-2` |
| T7 | strict-registry | under `Strict`, every emitted problem type is a row of the IANA problem-types registry, and no 104 is emitted | Exhaustion over `ProblemType` x `Policy` | `PD:IANA-PROBLEM-TYPES-about:blank-1`, `PD:IANA-PROBLEM-TYPES-registry-1`, `HS:IANA-HTTP-Status-Codes-104` |
| T8 | retry-after-placement | Retry-After is rendered only on 3xx, 413, 429, 503 and DRS 202, and is always delay-seconds | Exhaustion over `Final` | `HS:RFC9110-10.2.3-3`, `HS:RFC9110-15.5.14-3`, `HS:RFC6585-4-2`, `HS:RFC9110-15.6.4-2`, `DO:DRS-responses.202Accepted.Retry-After-1` |
| T9 | method-classes | `safe m` implies `idempotent m`; the idempotent set is exactly {GET, HEAD, OPTIONS, TRACE, PUT, DELETE}, which equals urllib3's DEFAULT_ALLOWED_METHODS; PATCH and POST are not idempotent | LH reflection with a case split (probed) | `HS:RFC9110-9.2.1-2`, `HS:RFC9110-9.2.2-1`, `HS:RFC9110-9.2.2-4` |
| T10 | no-replay-of-unsafe | `retryDecision` never retries a non-idempotent method, except on 421 (new connection) or a `NothingWritten` fault | Exhaustion over Method x Outcome x Attempts (attempts bounded by policy) | `HS:RFC9110-9.2.2-4`, `HS:RFC9110-15.5.20-2`, `HS:RFC9110-9.2.2-7` |
| T11 | no-retry-507 | `retryDecision m (Status 507) a = DoNotRetry` for all `m`, `a` | Exhaustion | `HS:RFC4918-11.5-2` |
| T12 | one-transport-retry | no sequence of transport faults produces more than `transportRetry <= 1` automatic retries | LH refinement on the attempt counter | `HS:RFC9110-9.2.2-8` |
| T13 | retry-after-parse | `parseRetryAfter` accepts a delay exactly when the input matches `1*DIGIT`, every result is `>= 0`, and dates are clamped at 0 | LH refinement on the output, plus exhaustion over single-character inputs for the grammar | `HS:RFC9110-10.2.3-5`, `HS:RFC9110-10.2.3-6`, `HS:RFC9110-10.2.3-7` |
| T14 | store-classification | the code decides before the status; every listed throttling code gives `Throttling`; 500/502/503/504 with no recognized code give `Transient`; aborts are terminal | Exhaustion over `Maybe S3ErrorCode` x the four statuses plus 429 | `PD:AWSSDK-RETRY-error-classification-1`, `PD:AWSSDK-RETRY-error-classification-2`, `PD:AWSSDK-RETRY-error-classification-4`, `PD:SMITHY-TS-service-error-classification-isTransientError-1` |
| T15 | offset-monotone | for every `step`, if upload `u` exists before and after, `offset u' >= offset u` | LH (`offset` is a reflected sum over `parts`; `parts` is only ever extended) | `UP:RESUMABLE-UPLOAD-13-4.1.1-7`, `UP:RESUMABLE-UPLOAD-13-4.1.1-8` |
| T16 | offset-within-length | in `Incomplete` and `Complete`, `length = Just l` implies `offset <= l`, and a step that would break it lands in `Invalid` instead | LH invariant on `UploadResource` | `UP:RESUMABLE-UPLOAD-13-4.4.2-7` |
| T17 | length-immutable | if `length u = Just l` then `length u' = Just l` | LH refinement on the update functions | `UP:RESUMABLE-UPLOAD-13-4.1.3-6`, `UP:TUS-1.0.0-Creation.Requests.POST-4` |
| T18 | completion-is-explicit | `phase` becomes `Complete` only from a `?1` request whose content was fully processed, or from the server appender reaching the pinned length; never from `offset = length` alone | Exhaustion over `Occurrence` constructors in `step` | `UP:RESUMABLE-UPLOAD-13-4.1.2-1`, `UP:RESUMABLE-UPLOAD-13-4.1.2-3`, `UP:RESUMABLE-UPLOAD-13-4.1.3-8` |
| T19 | interruption-never-completes | `ContentEnded _ Interrupted` never sets `Complete` | Exhaustion | `UP:RESUMABLE-UPLOAD-13-4.2.2-11`, `UP:RESUMABLE-UPLOAD-13-4.4.2-2` |
| T20 | completing-answers-say-complete | every answer to a request with Upload-Complete `?1` renders `Upload-Complete: ?1`; in particular no 2xx answer to such a request has `?0` or omits the field | Construction (`ForUpload` built by a `?1`-only smart constructor on that path) | `UP:RESUMABLE-UPLOAD-13-4.2.2-4`, `UP:RESUMABLE-UPLOAD-13-4.4.2-4`, `UP:RESUMABLE-UPLOAD-13-A-2` |
| T21 | offset-conflict | an append with `p /= offset u` answers 409 with `?0` and `Upload-Offset = offset u`, and leaves `u` unchanged | LH | `UP:RESUMABLE-UPLOAD-13-4.4.2-3`, `UP:TUS-1.0.0-Core.Requests.PATCH-2` |
| T22 | told-offsets-are-usable | if a final answer told the client `Upload-Offset = o`, and no append or cancel for `u` arrived since, an append at `o` is not rejected for mismatch | LH (the told value is `offset u`, and acceptance is equality with `offset u`) | `UP:RESUMABLE-UPLOAD-13-4.6-3` |
| T23 | parts-are-store-valid | part numbers are exactly 1..k with k <= 10000, and every part but the last has size >= `minAppendSize` | LH refinement on `Parts` | `PD:S3UG-MPU-mpuchecksums-2`, `PD:S3UG-MPU-mpu-process-2`, `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-4`, `UP:RESUMABLE-UPLOAD-13-4.1.4-6` |
| T24 | one-transfer-at-a-time | at most one `inFlight` request per upload, and a new request for the same upload emits `TerminateRequest` for the old one before anything else | Exhaustion over `step` branches | `UP:RESUMABLE-UPLOAD-13-4.6-1`, `UP:RESUMABLE-UPLOAD-13-4.6-4` |
| T25 | limits-stable | `limits u` never changes after creation and `expiresAt` never decreases, which implies the draft's max-* SHOULD NOT decrease, min-* SHOULD NOT increase, and end-of-lifetime SHOULD NOT decrease | Construction (no setter) plus LH on `expiresAt` | `UP:RESUMABLE-UPLOAD-13-4.1.4-8`, `UP:RESUMABLE-UPLOAD-13-4.1.4-9`, `UP:RESUMABLE-UPLOAD-13-4.1.4-10`, `UP:RESUMABLE-UPLOAD-13-4.1.4-11` |
| T26 | limit-never-empty | a rendered Upload-Limit always has at least one member (`min-size=0` when nothing is limited) | Construction | `UP:RESUMABLE-UPLOAD-13-4.1.4-15` |
| T27 | location-consistent | every interim and final answer to one creation request carries the same Location, derived from the `UploadId` fixed at creation | Construction | `UP:RESUMABLE-UPLOAD-13-4.2.2-8` |
| T28 | reauthorize-before-finalize | `CompleteMultipartUpload` and `PutObject` are emitted only by a request whose `Authz` is `Authorized` | Exhaustion over `step` branches | `UP:RESUMABLE-UPLOAD-13-13-6`, `UP:RESUMABLE-UPLOAD-13-13-7` |
| T29 | gone-stays-gone | in `Deactivated` or `Invalid`, every request answers 410 and emits no store command except abort and list | Exhaustion | `UP:RESUMABLE-UPLOAD-13-4.1.1-9`, `UP:RESUMABLE-UPLOAD-13-4.4.2-7`, `UP:RESUMABLE-UPLOAD-13-4.5.2-1`, `HS:RFC9110-15.5.11-1` |
| T30 | available-means-vouched | a `DrsObject` exists only via `mkDrsObject`, which needs a `Receipt`; a `Receipt` has `checksumType = FULL_OBJECT`, `supports alg shape FULL_OBJECT`, and `size = length u` | Construction (abstract types) plus LH refinements on `Receipt` | `PD:S3UG-INTEGRITY-UPLOAD-checking-object-integrity-upload-1`, `PD:S3UG-INTEGRITY-UPLOAD-MultipartUploads-Checksums-1`, `DO:DRS-schemas.DrsObject-1`, `DO:DRS-schemas.DrsObject.checksums-1` |
| T31 | composite-is-never-a-receipt | `parseChecksumValue s = Just (CompositeValue _ k)` exactly when `s` ends in `-N` with N in 1..10000 and no leading zero, and `vouch` rejects every `CompositeValue` | LH on the parser plus construction | `PD:AWS-SDK-JS-isChecksumWithPartNumber-isChecksumWithPartNumber-1`, `PD:S3UG-INTEGRITY-UPLOAD-ChecksumTypes-Uploads-3` |
| T32 | success-is-not-proof | a 2xx `StoreReport` without a checksum never yields a `Receipt` | Exhaustion over `StoreReport` constructors | `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-2`, `PD:S3UG-MPU-mpuAndPermissions-1`, `PD:S3UG-MPU-mpuAndPermissions-2`, `PD:S3UG-INTEGRITY-UPLOAD-Full-object-checksums-6` |
| T33 | checksum-support-table | CRC64NVME supports only FULL_OBJECT; SHA1, SHA256, SHA512, MD5 and the XXHASH family support only COMPOSITE in multipart; every algorithm is FULL_OBJECT in single part | Exhaustion (10 x 2 x 2) | `PD:S3UG-INTEGRITY-UPLOAD-MultipartUploads-Checksums-1`, `PD:S3API-PutObject-request-header-ChecksumCRC64NVME-1`, `PD:S3API-PutObject-response-header-ChecksumType-1` |
| T34 | receipt-width | a CRC64NVME receipt decodes to exactly 8 bytes and its base64 text is 12 characters ending in one `=`; CRC32 is 4 bytes and SHA256 is 32 | LH (the base64 encoder is defined by recursion over 3-byte groups, with an inductive length lemma and no `div`) | `PD:S3API-PutObject-request-header-ChecksumCRC64NVME-1`, `PD:S3UG-INTEGRITY-UPLOAD-trailing-checksums-1`, `PD:RFC9651-4.1.8-1`, `PD:AWS-SDK-JS-Crc64NvmeJs-digest-1` |
| T35 | repr-digest-only-registered | `reprDigestOf r` is `Just` exactly for SHA256, SHA512, MD5, SHA1 and CRC32C, always uses the registered key, and marks Deprecated keys as corruption-only | Exhaustion over 10 algorithms | `PD:IANA-DIGEST-ALGS-sha-256-1`, `PD:IANA-DIGEST-ALGS-crc32c-1`, `PD:RFC9530-5-2`, `PD:RFC9530-3-1` |
| T36 | no-self-digest | no `Occurrence` carries representation bytes, and no exported function has a byte-sequence argument and a `Receipt`, `ReprDigest` or `DrsChecksum` result | Construction, checked by a module-interface review in `tools/check-cites.py` | `PD:RFC9530-6.5-1`, `PD:S3UG-INTEGRITY-UPLOAD-checking-object-integrity-upload-1` |
| T37 | ladder-is-rfc9110 | `ladder` equals a direct transcription of steps 1 to 6: If-Match false gives 412 unless already applied; If-Match present means If-Unmodified-Since is ignored; If-None-Match false gives 304 for GET/HEAD and 412 otherwise; If-None-Match present means If-Modified-Since is ignored; If-Modified-Since only for GET/HEAD; If-Range only for GET with Range; an If-Range date is never strong | Exhaustion (3^5 x 3 x 2 x 2 inputs) | `HS:RFC9110-13.2.2-2`, `HS:RFC9110-13.2.2-3`, `HS:RFC9110-13.2.2-4`, `HS:RFC9110-13.2.2-5`, `HS:RFC9110-13.2.2-6`, `HS:RFC9110-13.1.4-1`, `HS:RFC9110-13.1.3-1`, `HS:RFC9110-13.1.5-4` |
| T38 | preconditions-only-on-success-path | `ladder` is called only on branches that would otherwise answer 2xx | Exhaustion over `step` branches | `HS:RFC9110-13.2.1-2`, `HS:RFC9110-14.2-6` |
| T39 | range-arithmetic | with representation length `n`: 206 iff exactly one valid range with `first < n` (or a nonzero suffix) and If-Range true or absent; then `last = min(last, n-1)`; 416 iff valid and unsatisfiable, with `*/n`; for `n = 0` only a nonzero suffix is satisfiable | LH (linear arithmetic) | `HS:RFC9110-14.1.2-3`, `HS:RFC9110-14.1.2-5`, `HS:RFC9110-14.1.2-6`, `HS:RFC9110-14.1.1-2`, `HS:RFC9110-14.4-7` |
| T40 | active-is-immutable | once a file is `ACTIVE`, its size, checksums and ETag never change; only `available` does | LH on the `files` map update | `DO:DRS-DrsApiPrinciples.DRS-IDs-2`, `HS:RFC9110-8.8.1-2` |
| T41 | authorization-first | for every request with `Authz /= Authorized`, the answer is 401, 403 or 404, the state is unchanged, and no store or source command is emitted | Exhaustion over `Request` x `Authz` | `DO:RFC4918-8.1-1`, `DO:RFC4918-8.5-1`, `SS:AIP193-PermissionDenied-1` |
| T42 | credentials-split | `NoCredentials` and `InvalidCredentials` give 401 with a challenge, `Insufficient Reveal` gives 403, and `Insufficient Hide` gives 404 | Exhaustion | `HS:RFC9110-11.4-1`, `HS:RFC9110-11.4-2`, `HS:RFC9110-15.5.4-4` |
| T43 | import-append-matches | the server appender appends a source response only when its first byte position equals `offset u` and its ETag strongly equals the pinned one; otherwise the upload deactivates | Exhaustion over the `SourceReport` shape | `HS:RFC9110-15.3.7.3-1`, `HS:RFC9110-14.4-5`, `UP:RESUMABLE-UPLOAD-13-4.3.1-2` |
| T44 | operation-shape | an `InProgress` operation has no result, a `Done` operation has exactly one, an error result is never OK, and cancelling gives `Done (Left CANCELLED)` without deleting the operation | Construction plus LH (`{c:Code \| c /= OK}`) | `SS:LRO-Operation-result`, `SS:LRO-CancelOperation-3`, `SS:ABSL-STATUSOR-2` |
| T45 | reads-are-safe | `RetrieveOffset`, `GetDrsObject`, `GetAccessUrl`, `GetBytes` and `GetOperation` leave `State` unchanged, apart from terminating an in-flight transfer | LH (the state component of `step` equals its input on those branches) | `HS:RFC9110-9.2.1-1`, `UP:RESUMABLE-UPLOAD-13-4.6-4` |
| T46 | step-total | `step` is total and terminating | LH totality and termination checking | none; this is the brief's totality requirement, not a protocol rule |
| T47 | provenance-nonempty | every constructor of every closed type has at least one statement id, and every id exists in its group | Construction (`provenance :: T -> NonEmpty StatementId`) plus `tools/check-cites.py` | none; this is the brief's no-invented-vocabulary rule |

## What the sources leave open

These are the places where I couldn't ground a decision in a vendored statement. Where the tables above make a choice anyway, it is marked as a choice here, so we can change it before the code exists.

1. Statement ids collide across groups. Sixty-eight ids appear in more than one `statements.json`, forty-two of them with different quotes (for example `HS:RFC9110-15-5` vs `PD:RFC9110-15-5`). This document keys by group, but `tools/check-cites.py` and anything else that reads ids has to as well. It would probably be simpler to regenerate the duplicates with distinct ids.
2. Registration status. The two upload problem types (`mismatching-upload-offset`, `inconsistent-upload-length`) are requested by the draft but are not rows in the vendored IANA registry, and 104 is a TEMPORARY registration that expires 2026-11-13, five weeks from now. I put both behind `Policy.registry`. Under `Strict` there is no 104 and the problem type falls back to `about:blank`. Without a 104, a client can only resume a creation it started with an empty body (`UP:RESUMABLE-UPLOAD-13-10.1-1`, `UP:RESUMABLE-UPLOAD-13-4.2.1-8`), so `Strict` makes "create empty, then append" the only resumable flow. We need to decide which policy ships.
3. CRC64NVME can't be a Repr-Digest. It has no RFC 9530 key, no Named Information name, and it isn't in DRS's list of suggested `type` strings. For multipart uploads, S3 offers full-object checksums only for CRC64NVME, CRC32 and CRC32C (`PD:S3UG-INTEGRITY-UPLOAD-Full-object-checksums-3`). So the only multipart receipt that can become a Repr-Digest is `crc32c`, which is Deprecated and "MUST NOT be used in a potentially adversarial setting" (`PD:RFC9530-5-2`). We have three options:
   - keep CRC64NVME and send no Repr-Digest on downloads;
   - request CRC32C and send a Deprecated digest that is good only against corruption;
   - use single-part SHA256 uploads where size allows.

   The DRS `checksums[].type` string for CRC64NVME would rest on DRS's "Other values MAY be used" (`DO:DRS-schemas.Checksum.type-1`), so we'd be writing `crc64nvme` in a field that wants an IANA name.
4. Nothing vendored says that S3's `CRC32C` and RFC 9530's `crc32c` produce the same byte string. They plausibly name the same Castagnoli CRC, but RFC 9530's Appendix A and RFC 9260 aren't vendored, and S3 states the byte order (big-endian) while RFC 9530 doesn't in our statements. T35 assumes they match.
5. The Named Information registry has a row for sha-512, but only sha-256 is quoted as a statement (`PD:IANA-NI-hash-alg-1-1`). If we ever write a DRS checksum of type `sha-512`, it needs a statement.
6. The draft names no status for several rejections. I chose these:
   - 409 for a non-replay append to a completed upload, with `Upload-Complete: ?0`. The draft only says Upload-Complete "can be false in response to an invalid operation performed on a completed upload" (`UP:RESUMABLE-UPLOAD-13-4.1.2-6`).
   - 400 with Upload-Limit for an append below min-append-size. The draft says only that the server "might reject".
   - 413 for an append that would pass a known length. The draft says "rejecting the request"; tusd uses 413.
   - 410 then 404 for a deactivated upload, taken from tus and RFC 9110 since the draft names nothing.
7. AWS docs contradict each other in ways that can produce silent failures:
   - The at-rest support claim conflicts with the multipart table; I chose the table.
   - BadDigest is described as Content-MD5 only in the error list but as any checksum mismatch in the user guide; the core treats it as any mismatch, and only when we forwarded a client digest.
   - Non-consecutive composite parts give a 500; T23 makes that unreachable.
   - The multipart overview says uploads have "no expiry", but lifecycle rules can abort them; the core treats a store `NoSuchUpload` as `StateLost`.
   - `OperationAborted` says "Try again" but appears in neither retry list; the classifier says `NonRetryable`, and that may be wrong.
8. Zero-byte multipart completion. A creation with `?0` followed by an empty completing append would ask S3 to complete an upload with no parts, and nothing vendored says whether that works. I'd route it to `AbortMultipartUpload` plus an empty `PutObject`, but that is a guess about the store.
9. "5 MB" in `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-4` doesn't say whether that is 5,000,000 or 5,242,880 bytes, and S3's maximum part size isn't vendored at all, so `maxAppendSize` and therefore `maxSize` (10,000 parts) have no grounded value yet.
10. Import failures and google.rpc.Code. The gRPC HTTP mapping is defined for "clients that received a response that did not include grpc-status" (`SS:GRPC-HTTPMAP-scope-2`), which our fetcher literally is. But it maps 404 to UNIMPLEMENTED (`SS:GRPC-HTTPMAP-table-404`) and every other 4xx to UNKNOWN, so a person whose source URL is dead would be told "unimplemented". We could accept that literal reading, or decide that imports need a vocabulary none of the vendored standards supply.
11. If the shell ever renders an Operation's error through AIP-193's HTTP JSON form, where `code` is an HTTP status (`SS:AIP193-HTTP-1`), CANCELLED would become 499, which IANA doesn't register. T4 keeps 499 out of `render`, but the Operation rendering path needs the same rule.
12. "In flight down" has no server-side state in any vendored standard. It is a client doing range requests. The table answers with 206 per piece and nothing else. If people need to see a download's progress from another device, that needs vocabulary we don't have.
13. Whether to hide a forbidden resource's existence (404) or admit it (403) is left open by RFC 9110 (`HS:RFC9110-15.5.4-4`). S3 decides it by ListBucket permission (`PD:S3API-GetObject-API_GetObject-1`), and gRPC by whether a whole class of users is denied (`SS:GRPC-STATUSCODES-NOT_FOUND-2`). The core takes a `Disclosure` from the shell, but the policy that produces it isn't decided.
14. The If-Range strong-date rules. `HS:RFC9110-8.8.2.2` is quoted only up to "using the following rules:", and the rules themselves aren't in our statements. The ladder treats every If-Range date as weak until they are vendored.
15. RFC 9651's Integer and Boolean grammars (sections 3.3.1 and 3.3.6) aren't vendored, so the Upload-Offset, Upload-Length and Upload-Complete parsers rest on the draft's prose rather than on the grammar, and the sf-integer 15-digit bound isn't enforced.
16. Cleanup of an object the store wrote without a receipt (the `FAILED` row after `NoChecksumReturned`). S3 DeleteObject isn't vendored, so the core emits nothing for it yet. Leaving it means storage we pay for and can't vouch for, which is the resource-exhaustion case in our blind-spot order.
17. Destinations. The brief implies folders, but no vendored standard covers a drive namespace beyond WebDAV's collections. The core takes a `DestinationFault` verdict from the shell for now. Moving the namespace into the core would mean adopting RFC 4918's collection model wholesale.
18. A client digest the store can't check. When a client sends Repr-Digest in an algorithm the store can't validate as a full object for this upload shape, I chose to refuse with `DigestUnsupportedAlgorithms` rather than ignore it as RFC 9530 allows (`PD:RFC9530-2-2`). Ignoring it would let a client believe its digest was checked when it wasn't, which is a silent failure.
19. The DRS 202 Retry-After value. DRS asks for the minimum wait "with a reasonable expectation of success" (`DO:DRS-responses.202Accepted.Retry-After-2`), but nothing tells us how long a CompleteMultipartUpload takes, so `pendingDelay` is a constant in `Policy`.
20. Content scanning before availability (`UP:RESUMABLE-UPLOAD-13-13-5`) would sit between "store vouched" and `ACTIVE`. No vendored standard gives it a state name, so the design leaves it out.
