# funknown-core: a proof-first design

Status: design only, no Haskell source in the repo yet. Written 2026-10-09 against the five vendored reference groups under `references/`. The abandoned `experiments/` tree was ignored on purpose. Every encoding this document promises was spike-tested on LiquidHaskell 0.9.14.1.1 with GHC 9.14.1 and z3 4.16.0 before I wrote it down, and the section on the spike says exactly which ones went through and which did not.

We want a pure Haskell core for a B2B drive that takes files in (a person's browser uploads them, or we import them from a URL) and lets people take them out again (downloads), and we want its correctness proven rather than sampled. The brief adds two rules that shape everything else. Every state, status, reason and recourse the core can express has to come from an existing standard, and a file becomes available only when the store vouches for it with a full-object checksum receipt. If both rules are going to hold, it looks to me like they have to be facts the compiler checks, so I designed the types first and the functions second. Wherever I could, I made a violation impossible to construct. Where that wasn't possible, I stated the rule as a refinement that z3 has to discharge at compile time, in the standard's own words.

The document runs in this order: how citations work, what the spike taught us about the prover, the package layout, every type with the statements its constructors come from, the state and its events and commands, the `step` transition table row by row, what a client is told, which reference code gets ported and what we fix on the way, the theorem catalog, and finally the questions the sources leave open.

## How a citation is written here

Every claim cites a statement id from one group's `statements.json`, prefixed with the group. The prefix is not decoration. Sixty-eight ids appear in more than one group, and forty-two of those carry different quotes in different groups. For example, `RFC9110-15-5` is "Values outside the range 100..599 are invalid." in http-semantics, but in problems-and-digests the same id quotes the SHOULD about treating an invalid code as 5xx. A citation therefore only identifies a quote as a (group, id) pair. I use the same prefixes as the sibling design in `docs/design/core-protocol.md`, so the two documents can be compared line by line:

- `HS:` references/http-semantics/statements.json
- `PD:` references/problems-and-digests/statements.json
- `UP:` references/uploads/statements.json
- `DO:` references/drive-and-objects/statements.json
- `SS:` references/status-and-supervision/statements.json

Each statement carries `doc`, `section` and the verbatim `quote`, so an id resolves to the document, section and normative text the brief asks for. I'd like the Haskell source to carry only the prefixed id in a comment next to each constructor and refinement, and a small checker outside the core package (`tools/check-cites`, not written yet) to fail the build when an id does not resolve or resolves to a different quote than the one last reviewed. I ran the same check over this document before committing to it.

## What the spike taught us about the prover

I built a scratch package (`spike`, under this session's scratchpad at `design-proof/spike/`) with five modules that exercise the riskiest encodings, and the design below only promises proofs whose shape went through there. A clean build of all five modules reported `LIQUID: SAFE` on every module in 57 seconds. I also checked the negative side twice: a deliberately false refinement on a one-line function was rejected, and a deliberately false conjunct added to the `step` postcondition was rejected at three sites. The things that went through are these:

- The IANA status type generated from `http-status-codes-1.csv` (62 constructors) with `statusCode` refined to 100..599, a `fromWire :: Int -> Status` whose class-preservation and invalid-to-500 properties hold for every `Int` (symbolically, not by enumeration), and a per-constructor round trip `fromWire (statusCode s) == s` proved by exhaustion in 62 equational cases, from which injectivity follows in one line. This module alone takes about 45 seconds.
- A per-file `step :: State -> Event -> State` whose output refinement carries offset monotonicity, length immutability, completion being absorbing, terminal states being absorbing, and "ACTIVE only from a completed upload plus a FULL_OBJECT receipt". A reflected `run :: State -> [Event] -> State` then gave a two-line inductive proof that terminal states absorb any event sequence.
- The RFC 9110 13.2.2 precondition ladder, with its postcondition restating steps 1 through 5; authorization-before-existence admission; a retry decision carrying the 507, 421 and non-idempotent rules; byte-range resolution whose satisfied ranges are provably inside the representation; the base64 padding arithmetic for every checksum width; and the S3 algorithm-by-type table proved by exhaustion over its ten rows.
- A `Response` sum type whose MUST-carry headers are constructor fields (a 401 cannot be built without a challenge), a proof by exhaustion that every response status is a Permanent registry entry, and a reply refinement for the draft's rule that a completing request never gets a 2xx without `Upload-Complete: ?1`.

Four encodings failed, and each one turned into a design rule:

1. `isJust` and `fromJust` are not logic names in this build, so specs cannot talk about `Maybe`. Every optional thing in the core is our own two-constructor type with a measure (`Opt a = Absent | Present a`, `Len = Unknown | Known Nat`, `Lookup = Found s | NotFound`). I'd consider this a good outcome anyway, because each of those types gets a name from the standard that defines it.
2. A refinement on a record field only enters the context when the code pattern-matches that constructor. When the code reaches the field through a selector, the refinement is never seen. My first `step` failed because a branch used `len u` and never mentioned `complete`, so the invariant "complete implies length known" was invisible there. The core will pattern-match `Upload o l c` wherever a field invariant matters.
3. `Language.Haskell.Liquid.ProofCombinators` is not exposed by `liquidhaskell-0.9.14.1.1` in this store, so the core carries its own fifteen-line `Funknown.Proof` with `===`, `***`, `?` and `QED`. Exhaustive proofs over large enumerations needed explicit equational steps (`fromWire (statusCode s) === fromWire 404 === H404_NotFound *** QED`). A bare `()` was not enough for PLE to unfold the reflected lookup through the measure.
4. z3 can tell distinct `Char` literals apart, but it cannot order them, and `ord`/`chr` are uninterpreted. A digit test written as `'0' <= c && c <= '9'` did not verify, while the same test written as ten literal equalities did. Character classes in the core are therefore written as explicit equality disjunctions, and anything that genuinely needs ranges (the RFC 9110 `etagc` grammar, for example) stays in the shell. That rule is the reason header parsing is outside the proven core.

Two smaller observations. `{-# LANGUAGE Safe #-}` works together with `-fplugin=LiquidHaskell`, so every core module can be Safe Haskell. And reflecting `run`, which calls the non-reflected `step`, prints an "Assume Overwrites Specifications for step" warning. I checked that the warning is harmless: `step`'s spec was still verified, because the false-conjunct probe was caught with the warning present. I'd still like CI to grep for that warning text on any function other than `step`, so that a real assumed spec can't slip in.

## The package

One cabal package, `funknown-core`, with `build-depends: base, liquidhaskell == 0.9.14.1.1` and `ghc-options: -fplugin=LiquidHaskell`, built with `cabal build -w ghc-9.14.1`. It does no IO, reads no clock and holds no `Map`. The verified unit is a single file's state machine. The shell keeps the map from file id to state and routes each event to `stepFile`, which is a one-line `alter` lift that I'd rather leave in the shell than verify against `containers` specs we don't have. Every module is `{-# LANGUAGE Safe #-}` and turns on `--reflection` and `--ple` only where it reflects something.

```
funknown-core/
  funknown-core.cabal
  gen/StatusTable.hs            -- input: references/http-semantics/http-status-codes-1.csv (generator, not in the library)
  src/Funknown/
    Proof.hs                    -- Proof, QED, (===), (***), (?)  (ProofCombinators is not exposed)
    Opt.hs                      -- Opt a = Absent | Present a, with measures
    Http/Status.hs              -- GENERATED: Status, Registration, Class, statusCode, classOf, fromWire, x00
    Http/Method.hs              -- Method, safe, idempotent
    Http/Validator.hs           -- EntityTag, strongMatch, weakMatch, DateValidator
    Http/Precondition.hs        -- Cond, MethodKind, RangeReq, Verdict, gate, ladder
    Http/Range.hs               -- RangeSpec, Resolved, resolve
    Http/Admission.hs           -- Authn, Authz, Existence, Disclosure, admit
    Http/Retry.hs               -- RetryAfter, Initiator, Decision, retryDecision, backoff
    Digest.hs                   -- DigestKey, KeyStatus, ReprDigest
    Problem.hs                  -- ProblemType, Problem (status computed, never stored)
    Rpc/Code.hs                 -- Code (google.rpc), codeNumber, codeName, Recourse, recourse
    Store/Checksum.hs           -- ChecksumAlgorithm, ChecksumType, UploadPath, supports, Width, Shape, Receipt, vouch
    Store/Outcome.hs            -- StoreCall, StoreOutcome, AwsErrorCode, classifyStoreError
    Upload.hs                   -- Len, Upload, UploadLimit, Transfer, admitAppend, applyProcessed
    File.hs                     -- FileState (AIP-216 names), Creation, Source, Object, Reason, code
    Event.hs, Command.hs, Response.hs
    Step.hs                     -- stepFile, run
    Tell.hs                     -- fields :: Response -> [Field], view :: FileState -> FileView, operation :: FileState -> Op
    Theorems.hs                 -- multi-step theorems over run (the per-step ones live next to their functions)
```

The generator under `gen/` is the only place the CSV is read. I'd like its output to be committed and checked by CI for drift, so the registry can't change under us without a diff.

## The types, module by module

Each block below lists the constructors and, for each one, the statement it comes from. Haskell identifiers are internal names. What reaches a client is always a token the cited statement defines: a registry code, a header field name, a problem type URI, an AIP-216 state name, or a google.rpc.Code name.

### Funknown.Http.Status (generated)

```
data Registration = Permanent | Temporary | Obsoleted
data Class = Informational | Successful | Redirection | ClientError | ServerError
data Status = H100_Continue | H101_SwitchingProtocols | ... | H511_NetworkAuthenticationRequired   -- 62 constructors
statusCode :: Status -> {v:Int | 100 <= v && v <= 599}
fromWire   :: n:Int -> {v:Status | (valid n => classOf v == classOfCode n) && (not (valid n) => v == H500_InternalServerError)}
```

- One constructor per assigned row of the registry (`HS:IANA-HTTP-Status-Codes-100` through `HS:IANA-HTTP-Status-Codes-511`, one statement per row), named from the registry's description, not from the reason phrases in Go, CPython or http-types (those still say 413 "Request Entity Too Large" and 422 "Unprocessable Entity").
- `Class` is the five classes of `HS:RFC9110-15-3`, and the first digit decides it (`HS:RFC9110-15-2`).
- 306 and 418 are registered "(Unused)" (`HS:IANA-HTTP-Status-Codes-306`, `HS:IANA-HTTP-Status-Codes-418`, `HS:RFC9110-15.5.19`), so they get no constructor, and an incoming 418 decodes to 400 like any unrecognized 4xx.
- 104 is `Temporary` (`HS:IANA-HTTP-Status-Codes-104`, which expires 2026-11-13) and 510 is `Obsoleted` (`HS:IANA-HTTP-Status-Codes-510`). Both exist only so that `fromWire` can name them; no `Response` constructor maps to them.
- `fromWire` implements `HS:RFC9110-15-4` (an unrecognized code is its class's x00) and `HS:RFC9110-15-5` with `HS:RFC9110-15-6` (outside 100..599 is invalid and processed as 5xx). It only ever runs on codes we receive: an import source's final status, or a store's status.
- 499 has no constructor, because the registry has no 499 (`HS:IANA-HTTP-Status-Codes-452-499`). That is how the core refuses code.proto's "HTTP Mapping: 499 Client Closed Request" (`SS:RPC-CODE-CANCELLED-http`) without anyone having to remember to.

### Funknown.Http.Method

```
data Method = GET | HEAD | POST | PUT | DELETE | OPTIONS | TRACE | PATCH
safe       :: Method -> Bool   -- GET, HEAD, OPTIONS, TRACE
idempotent :: Method -> Bool   -- safe ones plus PUT, DELETE
```

- GET, HEAD, OPTIONS and TRACE are safe (`HS:RFC9110-9.2.1-2`). PUT, DELETE and the safe methods are idempotent (`HS:RFC9110-9.2.2-1`). POST is defined by `HS:RFC9110-9.3.3-1`.
- PATCH is in the type only because the draft appends with it (`UP:RESUMABLE-UPLOAD-13-4.4.1-1`). RFC 9110 does not define PATCH, so it is not "of the request methods defined by this specification" and we can't call it idempotent. It therefore falls under `HS:RFC9110-9.2.2-4` (no automatic retry without other means to know) and `HS:RFC8470-4-1` ("methods whose safety is not known").
- CONNECT is left out. No statement covers it and the core has no use for it.

### Funknown.Http.Validator

```
data EntityTag = EntityTag { weak :: Bool, opaque :: OpaqueTag }
strongMatch a b = not (weak a) && not (weak b) && opaque a == opaque b
weakMatch   a b = opaque a == opaque b
data DateValidator = DateValidator { seconds :: Int }      -- always treated as weak, see below
```

- The shape is `HS:RFC9110-8.8.3-2` and `HS:RFC9110-8.8.3-3`; strong and weak comparison are `HS:RFC9110-8.8.3.2-1` and `HS:RFC9110-8.8.3.2-2`, and the four-row table `HS:RFC9110-8.8.3.2-3` becomes a theorem.
- The ETag grammar (`etagc = %x21 / %x23-7E / obs-text`) needs character ranges, and the spike showed those can't be reasoned about in this LH build, so scanning ETags stays in the shell and the core receives `[EntityTag]`.
- `HS:RFC9110-8.8.2.2` says a Last-Modified date "is implicitly weak unless it is possible to deduce that it is strong, using the following rules", but the rules themselves were not extracted. Until they are, the core treats every date validator as weak. That makes If-Range with an HTTP-date always false (`HS:RFC9110-13.1.5-4` step 1), which is the conservative side of Go's divergence (b): Go compares dates by exact second without the strong-date test.

### Funknown.Http.Precondition

```
data Cond       = Absent | Holds | Fails                  -- Absent also means "ignored" (invalid date, no modification date, ...)
data MethodKind = MGet | MHead | MUnsafe
data RangeReq   = NoRange | RangeOnly | RangeIfRange Cond
data Ranged     = WithRange | WithoutRange
data Verdict    = V412 | V304 | AlreadyApplied | Proceed Ranged
data Gate       = Blocked Response | Clear
```

- `Cond` is the evaluation result of each header (`HS:RFC9110-13.1.1-4`, `HS:RFC9110-13.1.2-5`, `HS:RFC9110-13.1.3-4`, `HS:RFC9110-13.1.4-5`, `HS:RFC9110-13.1.5-5`). The "MUST ignore" cases (`HS:RFC9110-13.1.3-1`, `HS:RFC9110-13.1.3-2`, `HS:RFC9110-13.1.3-3`, `HS:RFC9110-13.1.4-1`, `HS:RFC9110-13.1.4-2`, `HS:RFC9110-13.1.4-3`, `HS:RFC9110-13.1.5-2`) map to `Absent` before the ladder runs, so the ladder can't consult an ignored header.
- `AlreadyApplied` is the MAY in `HS:RFC9110-13.1.1-6` and `HS:RFC9110-13.1.4-7`. Go never takes that branch (divergence (a)); we take it for exactly one case, a DELETE whose If-Match names the tombstoned ETag of a file we already deleted.
- `Gate` encodes `HS:RFC9110-13.2.1-2`: if the response without preconditions would be something other than 2xx or 412, the preconditions are ignored.
- The ladder only takes the If-Match and If-Unmodified-Since steps "when recipient is the origin server" (`HS:RFC9110-13.2.2-2`, `HS:RFC9110-13.2.2-3`). The core is always the origin, so the `origin` argument is the constant `True` at every call site. It stays a parameter so the theorem that a non-origin recipient ignores those two headers is stated and checked, which also answers Go's divergence (c).

### Funknown.Http.Range

```
data RangeSpec = IntRange { first :: Nat, last :: Nat } | OpenRange { first :: Nat } | Suffix { suffixLength :: Nat }
data Resolved  = Satisfied { first :: Nat, lastPos :: {v:Nat | first <= v} } | Unsatisfiable | Ignore
resolve :: n:Nat -> RangeSpec -> {v:Resolved | (n == 0 => v == Ignore) && (isSatisfied v => lastPos v < n)}
```

- The forms are `HS:RFC9110-14.1.1-1` and `HS:RFC9110-14.1.1-3`. `last < first` is invalid (`HS:RFC9110-14.1.1-2`) and we take the MAY to ignore it (`HS:RFC9110-14.2-4`). An absent or too-large last-pos becomes length minus 1 (`HS:RFC9110-14.1.2-3`). A suffix longer than the representation selects all of it (`HS:RFC9110-14.1.2-4`). Satisfiability is `HS:RFC9110-14.1.2-5`.
- On a zero-length representation we take the MAY in `HS:RFC9110-14.2-5` and ignore Range. That sidesteps the corner of `HS:RFC9110-14.1.2-6` where a "satisfiable" suffix range would select zero bytes, which `Content-Range` can't express.
- Only GET honours Range (`HS:RFC9110-14.2-2`), and only one range is served, so the multipart rule (`HS:RFC9110-15.3.7.2`) never comes up. A list of several ranges is out of scope; the shell passes the first one, which `HS:RFC9110-14.2-8` allows for when it says a server need not send every requested range.

### Funknown.Http.Admission

```
data Authn      = NoCredentials | BadCredentials | Authenticated
data Authz      = Permitted | Denied
data Existence  = Missing | KnownGone | Present
data Disclosure = Reveal | Hide                         -- policy for HS:RFC9110-15.5.4-4
data Admit      = A401 | A403 | A404 | A410 | Clear
```

- 401 is for missing, invalid or partial credentials (`HS:RFC9110-11.4-1`). 403 is for valid but inadequate ones (`HS:RFC9110-11.4-2`, `HS:RFC9110-15.5.4-1`). An origin MAY hide a forbidden resource behind 404 (`HS:RFC9110-15.5.4-4`), which is `Disclosure`.
- The order is the whole point of this module: authorization before everything else (`DO:RFC4918-8.1-1`, `DO:RFC4918-8.5-1`), and permission before existence (`SS:AIP193-PermissionDenied-1`, `SS:AIP193-PermissionDenied-2`).
- `KnownGone` gives 410 because we know the condition is permanent (`HS:RFC9110-15.5.11-1`, `HS:RFC9110-15.5.5-2`).

### Funknown.Http.Retry

This module decides what we do with a status we *received*: an import source's response, or a store's.

```
data RetryAfter = NoRetryAfter | DelaySeconds Nat | DateDelta Int      -- DateDelta: date minus now, may be negative
data Initiator  = UserAction | Automatic
data Decision   = RetryIn Nat | RetryOnNewConnection | DoNotRetry
retryDecision :: Method -> {c:Int | 100 <= c && c <= 599} -> RetryAfter -> Initiator -> Decision
data MaxAttempts = {n:Int | 1 < n && n <= 5}
backoff :: initial:Nat -> multiplier:Nat -> cap:Nat -> attempt:{n:Int | n >= 1} -> {d:Nat | d <= cap}
```

- `RetryAfter` is the field's two forms, `HS:RFC9110-10.2.3-4` and `HS:RFC9110-10.2.3-5`, with `delay-seconds = 1*DIGIT` (`HS:RFC9110-10.2.3-7`). That rules out the decimals that smithy's `parseRetryAfterHeader.ts` accepts. A date in the past clamps to zero, as urllib3's `parse_retry_after` does.
- The rules, in the order they are tried:
  - 507 after a user action is never repeated automatically (`DO:RFC4918-11.5-2`).
  - 421 MAY be retried on a different connection even for non-idempotent methods (`HS:RFC9110-15.5.20-2`).
  - A non-idempotent method is not retried (`HS:RFC9110-9.2.2-4`).
  - 425 SHOULD be retried, outside early data (`HS:RFC8470-5.2-2`).
  - 408 MAY be repeated (`HS:RFC9110-15.5.9-2`).
  - 413, 429 or 503 *with* Retry-After are retried after the delay (`HS:RFC9110-15.5.14-3`, `HS:RFC6585-4-2`, `HS:RFC9110-15.6.4-2`). This is urllib3's `RETRY_AFTER_STATUS_CODES`.
  - Everything else is `DoNotRetry`.
- `MaxAttempts` is gRFC A6's validation rule (`SS:GRFC-A6-Validation-1`): greater than 1, and values above 5 are treated as 5. I'm borrowing it because RFC 9110 gives no budget at all. That borrowing is an open question below.
- `backoff` is gRFC A6's `min(initialBackoff*backoffMultiplier**(n-1), maxBackoff)` (`SS:GRFC-A6-Backoff`) without the jitter, which the shell applies so the core stays deterministic.
- A connection failure, as opposed to a status, gets at most one automatic retry, because "A client SHOULD NOT automatically retry a failed automatic retry" (`HS:RFC9110-9.2.2-8`). The import record holds that as a single `Bool`, so there is nowhere to count past one.

### Funknown.Digest

```
data DigestKey = Sha512 | Sha256 | Md5 | Sha | Unixsum | Unixcksum | Adler | Crc32c
data KeyStatus = Active | Deprecated                     -- Provisional exists in RFC 9530 but no key has it
keyStatus :: DigestKey -> KeyStatus
data ReprDigest = ReprDigest { key :: {k:DigestKey | keyStatus k == Active}, value :: B64Value }
```

- The keys and their statuses are the IANA "Hash Algorithms for HTTP Digest Fields" rows: `PD:IANA-DIGEST-ALGS-sha-512-1`, `PD:IANA-DIGEST-ALGS-sha-256-1`, `PD:IANA-DIGEST-ALGS-md5-1`, `PD:IANA-DIGEST-ALGS-sha-1`, `PD:IANA-DIGEST-ALGS-unixsum-1`, `PD:IANA-DIGEST-ALGS-unixcksum-1`, `PD:IANA-DIGEST-ALGS-adler-1` and `PD:IANA-DIGEST-ALGS-crc32c-1`, with the status vocabulary of `PD:RFC9530-5-3`.
- `ReprDigest` can only carry an Active key. That is our reading of `PD:RFC9530-5-1` ("it is RECOMMENDED that applications use these algorithms") together with `PD:RFC9530-5-2` (Deprecated keys "MUST NOT be used in a potentially adversarial setting"). A B2B drive serving files to other parties looks adversarial enough to me that I'd rather not emit `crc32c=` at all. Its meaning is `PD:RFC9530-3-1`: a digest over the entire selected representation data.
- The core never computes a digest. `value` is copied from the store's receipt, because the receipt and Repr-Digest are both base64 with "=" padding (`PD:RFC9651-3.3.5-1`, `PD:RFC9651-4.1.8-1`, `PD:S3UG-INTEGRITY-UPLOAD-trailing-checksums-1`).

### Funknown.Problem

```
data ProblemType
  = AboutBlank                     -- PD:RFC9457-4.2.1-1, PD:IANA-PROBLEM-TYPES-about:blank-1
  | DigestUnsupportedAlgorithms    -- PD:IANA-PROBLEM-TYPES-digest-unsupported-algorithms-1 (400)
  | DigestInvalidValues            -- PD:IANA-PROBLEM-TYPES-digest-invalid-values-1 (400)
  | DigestMismatchedValues         -- PD:IANA-PROBLEM-TYPES-digest-mismatched-values-1 (400)
  | MismatchingUploadOffset        -- UP:RESUMABLE-UPLOAD-13-7.1-1, UP:RESUMABLE-UPLOAD-13-14.4-1 (409), draft only
  | InconsistentUploadLength       -- UP:RESUMABLE-UPLOAD-13-7.2-1, UP:RESUMABLE-UPLOAD-13-14.4-2 (400), draft only
data Problem = Problem { ptype :: ProblemType, members :: Members ptype }
```

- A `Problem` has no status field. `Tell` renders `"status"` from the response that encloses it, so the rule that generators "MUST use the same status code in the actual HTTP response" (`PD:RFC9457-3.1.2-2`) holds by construction, and the duplication risk named in `PD:RFC9457-5-2` can't occur.
- The extension members are exactly the registered ones: `unsupported_algorithms`, `invalid_digests` and `mismatched_digests` (`PD:DIGEST-PROBLEMS-3.1-2`, `PD:DIGEST-PROBLEMS-3.2-3`, `PD:DIGEST-PROBLEMS-3.3-2`), plus the draft's `expected-offset` and `provided-offset` (`UP:RESUMABLE-UPLOAD-13-7.1-2`). We never send the digest we calculated (`PD:DIGEST-PROBLEMS-3.3-4`).
- The last two types are only requested from IANA, not registered. A policy flag `draftProblemTypes :: Bool` gates them, and with the flag off the same responses carry `about:blank`. Both choices keep the status code the draft requires. Whether draft vocabulary counts as "an existing standard" is the second open question below.

### Funknown.Rpc.Code

The reason a file failed, and what a client can do about it, come from google.rpc.Code and AIP-194, because AIP-216 and AIP-151 are where the resource-state vocabulary lives.

```
data Code = OK | CANCELLED | UNKNOWN | INVALID_ARGUMENT | DEADLINE_EXCEEDED | NOT_FOUND | ALREADY_EXISTS
          | PERMISSION_DENIED | UNAUTHENTICATED | RESOURCE_EXHAUSTED | FAILED_PRECONDITION | ABORTED
          | OUT_OF_RANGE | UNIMPLEMENTED | INTERNAL | UNAVAILABLE | DATA_LOSS
codeNumber :: Code -> {v:Int | 0 <= v && v <= 16}
codeName   :: Code -> String                              -- the enum name, nothing else
data Recourse = Retryable | NonRetryable | GenerallyNonRetryable Until | SurfaceImmediately
recourse :: Code -> Recourse
```

- The constructors and numbers are `SS:GRPC-STATUSCODES-OK` through `SS:GRPC-STATUSCODES-UNAUTHENTICATED`, and the numbers also appear in `SS:RPC-CODE-OK-http` through `SS:RPC-CODE-DATA_LOSS-http`. They are declared out of numeric order (UNAUTHENTICATED = 16 sits between 7 and 8), so `codeNumber` is a table and its injectivity is a theorem rather than an assumption.
- `Recourse` reuses AIP-194's own section headings:
  - `Retryable`: UNAVAILABLE (`SS:AIP194-Retryable-UNAVAILABLE`).
  - `NonRetryable`: OK, CANCELLED, DEADLINE_EXCEEDED and INVALID_ARGUMENT (`SS:AIP194-NonRetryable-OK`, `SS:AIP194-NonRetryable-CANCELLED`, `SS:AIP194-NonRetryable-DEADLINE_EXCEEDED`, `SS:AIP194-NonRetryable-INVALID_ARGUMENT`).
  - `SurfaceImmediately`: DATA_LOSS (`SS:AIP194-NonRetryable-DATA_LOSS`, a MUST), and also INTERNAL and UNKNOWN (`SS:AIP194-GenerallyNonRetryable-INTERNAL`, `SS:AIP194-GenerallyNonRetryable-UNKNOWN`).
  - `GenerallyNonRetryable Until`: RESOURCE_EXHAUSTED (`SS:AIP194-GenerallyNonRetryable-RESOURCE_EXHAUSTED`), ABORTED at a higher level (`SS:AIP194-GenerallyNonRetryable-ABORTED`), and NOT_FOUND, ALREADY_EXISTS, PERMISSION_DENIED, UNAUTHENTICATED, FAILED_PRECONDITION, OUT_OF_RANGE and UNIMPLEMENTED, each with its "until" condition (`SS:AIP194-GenerallyNonRetryable-NOT_FOUND`, `SS:AIP194-GenerallyNonRetryable-ALREADY_EXISTS`, `SS:AIP194-GenerallyNonRetryable-PERMISSION_DENIED`, `SS:AIP194-GenerallyNonRetryable-UNAUTHENTICATED`, `SS:AIP194-GenerallyNonRetryable-FAILED_PRECONDITION`, `SS:AIP194-GenerallyNonRetryable-OUT_OF_RANGE`, `SS:AIP194-GenerallyNonRetryable-UNIMPLEMENTED`).
- `Until` has one constructor per "until" clause, and those clauses are AIP-194's words. AIP-194 also lists `UNAUTHORIZED` (`SS:AIP194-GenerallyNonRetryable-UNAUTHORIZED`), which is not a google.rpc.Code value, so it gets no constructor.
- Deliberately missing: code.proto's HTTP mapping (it needs 499, which `Status` cannot represent) and the gRPC HTTP-to-Code table (`SS:GRPC-HTTPMAP-scope-2` restricts it to gRPC clients that got no grpc-status, which an HTTP import source never sends).

### Funknown.Store.Checksum

This is where "the store vouches" becomes a type.

```
data ChecksumAlgorithm = CRC64NVME | CRC32 | CRC32C | SHA1 | SHA256 | MD5 | XXHASH64 | XXHASH3 | XXHASH128 | SHA512
data ChecksumType      = COMPOSITE | FULL_OBJECT
data UploadPath        = SinglePart | Multipart
supports :: UploadPath -> ChecksumAlgorithm -> ChecksumType -> Bool
data Width = W32 | W64 | W128 | W160 | W256 | W512
width :: ChecksumAlgorithm -> Width
data Shape = Padded Width | PartSuffixed PartCount | Malformed      -- result of classify :: [Char] -> Shape
data Receipt  -- abstract: constructor not exported
  = Receipt { alg :: ChecksumAlgorithm, ctype :: {t:ChecksumType | t == FULL_OBJECT}, path :: UploadPath
            , value :: {v:B64Value | shapeOf v == Padded (width alg)} }
vouch :: UploadPath -> StoreReport -> Either Refusal {r:Receipt | supports (path r) (alg r) FULL_OBJECT}
data Refusal = NoChecksum | NotFullObject | CompositeValue | WrongShape | AlgorithmMismatch
```

- The ten algorithms are the S3 `ChecksumAlgorithm` values (`PD:S3API-CreateMultipartUpload-request-header-ChecksumAlgorithm-1`), and the two types are the Smithy enum (`PD:S3-SMITHY-com.amazonaws.s3#ChecksumType-1`, `PD:S3API-CreateMultipartUpload-request-header-ChecksumType-1`).
- On the `SinglePart` path every algorithm is FULL_OBJECT only (`PD:S3UG-INTEGRITY-UPLOAD-SinglePartUploads-Checksums-1`, `PD:S3API-PutObject-response-header-ChecksumType-1`).
- On the `Multipart` path, `supports` is the table in `PD:S3UG-INTEGRITY-UPLOAD-MultipartUploads-Checksums-1`. In that table CRC64NVME is FULL_OBJECT only, and the three CRCs are the only full-object algorithms (`PD:S3UG-INTEGRITY-UPLOAD-Full-object-checksums-3`). The at-rest page claims every algorithm except CRC64NVME supports both types (`PD:S3UG-INTEGRITY-AT-REST-using-additional-checksums-rest-1`), which contradicts the table. We follow the table because it is the more restrictive of the two.
- `width` is grounded today for CRC64NVME (64, `PD:S3API-PutObject-request-header-ChecksumCRC64NVME-1`), CRC32 (32, `PD:S3API-CompleteMultipartUpload-response-ChecksumCRC32-1`) and SHA256 (256, `PD:S3API-Checksum-API_Checksum_Contents-3`). The other seven widths are present in the vendored `aws/api-API_Checksum.md` but were not extracted as statements, so they need extracting before this table is written.
- `classify` is the port of `isChecksumWithPartNumber` (`PD:AWS-SDK-JS-isChecksumWithPartNumber-isChecksumWithPartNumber-1`): a "-N" suffix with N from 1 to 10000 means composite. Every width pads with one or two "=" characters, so a valid full-object value always ends in "=" while a composite value always ends in a digit. The spike proved that disjointness using literal-equality character classes. So the core does not depend on the SDK's silent skip in `PD:AWS-SDK-JS-flexibleChecksumsResponseMiddleware-flexibleChecksumsResponseMiddleware-1`, and it can't mistake a composite for a receipt even if a header says FULL_OBJECT.
- `vouch` is the only function that returns a `Receipt`, and the constructor isn't exported, so this is a by-construction guarantee rather than a convention. Its refusals are each a documented S3 failure mode:
  - `NoChecksum`: objects created "without a checksum value" (`PD:S3UG-MPU-mpuAndPermissions-1`, `PD:S3UG-MPU-mpuAndPermissions-2`).
  - `NotFullObject`: the reported type is COMPOSITE (`PD:S3API-CompleteMultipartUpload-response-ChecksumType-1`).
  - `CompositeValue`: a part-suffixed value (`PD:S3API-CompleteMultipartUpload-response-ChecksumCRC32-1`: "this value may not be a direct checksum value of the full object").
  - `WrongShape`: the wrong length or padding for the algorithm's width.
  - `AlgorithmMismatch`: the report names a different algorithm than the one our `StoreBegin` declared (`PD:S3API-CompleteMultipartUpload-request-header-ChecksumType-1`).
- A 200 from the store is not a receipt. `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-2` says a 200 can carry an embedded error, and `PD:S3UG-INTEGRITY-UPLOAD-Full-object-checksums-6` says checksums at Complete can be "accepted but not validated or stored". Success is just one input to `vouch`; it never decides availability on its own.

### Funknown.Store.Outcome

```
data StoreCall    = Begin | Append | Finalize | Abort | Remove
data StoreOutcome = Answered StoreReport | Refused AwsErrorCode Status | NoAnswer
data AwsErrorCode = BadDigest | InvalidRequest | EntityTooSmall | InvalidPart | InvalidPartOrder | NoSuchUpload
                  | AccessDenied | SlowDown | InternalError | ServiceUnavailable | RequestTimeout | OperationAborted
                  | PreconditionFailed | ConditionalRequestConflict | OtherCode
data StoreClass   = Transient | Throttling | NonRetryable
classifyStoreError :: AwsErrorCode -> Status -> StoreClass
```

- The codes are the rows we can act on from `PD:S3API-Error-BadDigest-1`, `PD:S3API-Error-EntityTooSmall-1`, `PD:S3API-Error-InvalidPart-1`, `PD:S3API-Error-InvalidPartOrder-1`, `PD:S3API-Error-NoSuchUpload-1`, `PD:S3API-Error-AccessDenied-1`, `PD:S3API-Error-SlowDown-1`, `PD:S3API-Error-InternalError-1`, `PD:S3API-Error-ServiceUnavailable-1`, `PD:S3API-Error-RequestTimeout-1`, `PD:S3API-Error-OperationAborted-1` and `PD:S3API-Error-PreconditionFailed-1`, plus `PD:S3UG-INTEGRITY-UPLOAD-Full-object-checksums-5` for InvalidRequest and `PD:S3API-PutObject-request-header-IfMatch-1` for the 409 ConditionalRequestConflict that the error list omits.
- These are AWS vocabulary used inside the core only. A client never sees one; they are translated into a `Reason` and a registry status first.
- `classifyStoreError` ports smithy-typescript's classifier:
  - It matches the error code first and falls back to the status (`PD:AWSSDK-RETRY-error-classification-4`).
  - Throttling is 429 or a throttling code (`PD:SMITHY-TS-service-error-classification-isThrottlingError-1`, `PD:AWSSDK-RETRY-error-classification-2`).
  - Transient is a transient code or 500, 502, 503 or 504 (`PD:SMITHY-TS-error-classification-constants-TRANSIENT_ERROR_CODES-1`, `PD:SMITHY-TS-error-classification-constants-TRANSIENT_ERROR_STATUS_CODES-1`, `PD:AWSSDK-RETRY-error-classification-1`).
  - Everything else is NonRetryable (`PD:AWSSDK-RETRY-error-classification-3`).
  - Backoff for store calls is `min(20000 ms, base * 2^retry)` before jitter, with base 50 ms or 1000 ms (`PD:AWSSDK-RETRY-backoff-formula-1`, `PD:AWSSDK-RETRY-backoff-formula-2`).

### Funknown.Upload

All the draft's upload-resource properties live in one record, and the invariants live in its type.

```
data Len = Unknown | Known Nat
data Upload = Upload
  { offset   :: Nat
  , len      :: {l:Len  | isKnown l => offset <= lenOr l}            -- UP:RESUMABLE-UPLOAD-13-4.4.2-7
  , complete :: {c:Bool | c => (isKnown len && lenOr len == offset)}  -- UP:RESUMABLE-UPLOAD-13-4.1.3-1, UP:RESUMABLE-UPLOAD-13-4.1.3-3
  }
data UploadLimit = UploadLimit { maxSize, minSize, maxAppendSize, minAppendSize :: Opt Nat, maxAge :: Opt Nat }
data Transfer = Idle | InFlight ReqId Budget
data Budget = Bounded Nat | Unbounded
```

- `offset`, `len` and `complete` are the three properties of `UP:RESUMABLE-UPLOAD-13-4.1-1`, defined by `UP:RESUMABLE-UPLOAD-13-4.1.1-1`, `UP:RESUMABLE-UPLOAD-13-4.1.2-1` and `UP:RESUMABLE-UPLOAD-13-4.1.3-1`. `Len` replaces tusd's `Size int64` plus `SizeIsDeferred bool` (`UP:TUSD-2.10.1-FileInfo-1`), so a meaningless size can't exist.
- `complete` is set only by an explicit event, never derived from `offset == len` as tusd does (`UP:TUSD-2.10.1-finishUploadIfComplete-1`). The draft is explicit about this: "the length and offset values do not determine whether an upload is complete" (`UP:RESUMABLE-UPLOAD-13-4.1.3-8`). The type allows `offset == len` with `complete == False`, and it rules out `complete == True` with any other pairing.
- `UploadLimit` has the five keys of `UP:RESUMABLE-UPLOAD-13-4.1.4-3` through `UP:RESUMABLE-UPLOAD-13-4.1.4-7`. The limits are fixed when the upload is created and never change afterwards. That is stronger than the SHOULD NOT decrease / SHOULD NOT increase rules (`UP:RESUMABLE-UPLOAD-13-4.1.4-9`, `UP:RESUMABLE-UPLOAD-13-4.1.4-10`, `UP:RESUMABLE-UPLOAD-13-4.1.4-11`), so those rules hold trivially. When no limit applies, the rendered field is `min-size=0` (`UP:RESUMABLE-UPLOAD-13-4.1.4-15`).
- `Transfer` has one slot, so two concurrent transfers on one upload are unrepresentable (`UP:RESUMABLE-UPLOAD-13-4.6-1`, `UP:RESUMABLE-UPLOAD-13-4.6-3`). `Budget` is how many bytes the shell may still stream into the store: `len - offset` when the length is known, otherwise `maxSize - offset`, otherwise `Unbounded`. A shell that obeys the budget can never push the offset past the length, and a shell that disobeys gets the upload failed (`UP:RESUMABLE-UPLOAD-13-4.4.2-7`).

### Funknown.File

```
data FileState                  -- AIP-216 State values, SS:AIP216-Guidance-1
  = CREATING Creation           -- SS:AIP216-Active-3 ("CREATING (usually becomes ACTIVE)"), SS:AIP151-StandardMethods-1
  | ACTIVE Object               -- SS:AIP216-EnumValues-1 ("available for use are ACTIVE")
  | FAILED Reason               -- SS:AIP216-Resting, SS:AIP216-EnumValues-2
  | CANCELLED                   -- SS:AIP216-Resting, UP:RESUMABLE-UPLOAD-13-4.5.1-1, SS:LRO-CancelOperation-3
  | DELETING Object             -- SS:AIP216-Active-3 ("DELETING (usually becomes DELETED)")
  | DELETED Tombstone           -- SS:AIP216-Resting
data Creation = Creation { source :: Source, upload :: Upload, transfer :: Transfer, limits :: UploadLimit
                         , awaiting :: Awaiting, expiresAt :: Opt Instant, metadata :: Metadata }
data Source   = FromClient | FromUrl Import
data Import   = Import { url :: Url, attempt :: {n:Nat | n <= maxAttempts}, connRetryUsed :: Bool, sourceTag :: Opt EntityTag }
data Awaiting = NotWaiting | Reauthorization ReqId | StoreAnswer StoreCall (Opt ReqId) Nat
data Object   = Object { receipt :: Receipt, size :: Nat, etag :: EntityTag, metadata :: Metadata }
data Tombstone = Tombstone { lastEtag :: EntityTag }
```

- Only six of AIP-216's names appear, because "each state must come with a use case" (`SS:AIP216-EnumValues-4`). PENDING, RUNNING, REPAIRING, SUSPENDING, ACCEPTED, SUCCEEDED, SUSPENDED and VERIFIED have no use here. The state is output-only and changes only through `step` (`SS:AIP216-OutputOnly-1`, `SS:AIP216-OutputOnly-2`).
- An upload and an import share one `Upload` record and one append function, which is the same idea the sibling design calls "one upload resource for every way bytes come in". The draft allows the server to obtain data "on behalf of the client" (`UP:RESUMABLE-UPLOAD-13-4.3.1-2`) and to mark an upload completed itself (`UP:RESUMABLE-UPLOAD-13-4.1.2-1`), so the import path needs no second notion of offset or completion.
- `Awaiting` is not a new state name. It records which command's answer the file is waiting for, and every constructor names a `Command` defined below.

```
data Reason
  = StateLost                     -- UP:RESUMABLE-UPLOAD-13-4.1.1-9            -> DATA_LOSS
  | OffsetPastLength              -- UP:RESUMABLE-UPLOAD-13-4.4.2-7            -> OUT_OF_RANGE
  | LifetimeReached               -- UP:RESUMABLE-UPLOAD-13-4.1.4-7, UP:TUS-1.0.0-Expiration-1 -> DEADLINE_EXCEEDED
  | StoreRefusedDigest            -- PD:S3UG-INTEGRITY-UPLOAD-Full-object-checksums-2 (BadDigest) -> DATA_LOSS
  | StoreGaveNoReceipt Refusal    -- see vouch                                 -> INTERNAL
  | StoreOutOfSpace               -- DO:RFC4918-11.5-1 (507)                   -> RESOURCE_EXHAUSTED
  | StoreUnavailable              -- retries exhausted                         -> UNAVAILABLE
  | NotPermittedAtFinalize        -- UP:RESUMABLE-UPLOAD-13-13-6, UP:RESUMABLE-UPLOAD-13-13-7 -> PERMISSION_DENIED
  | QuotaAtFinalize               -- UP:RESUMABLE-UPLOAD-13-13-7               -> RESOURCE_EXHAUSTED
  | SourceAnswered Status         -- import source's final non-2xx, decoded by fromWire -> UNKNOWN
  | SourceUnreachable             -- connection failures after the one retry   -> UNAVAILABLE
  | SourceChanged                 -- resumed fetch got a different entity       -> ABORTED
code :: Reason -> {c:Code | c /= OK && c /= CANCELLED}
```

Each `code` assignment cites the text in code.proto or statuscodes.md that defines the condition:

- DATA_LOSS is "Unrecoverable data loss or corruption" (`SS:GRPC-STATUSCODES-DATA_LOSS`).
- OUT_OF_RANGE is "attempted past the valid range" (`SS:GRPC-STATUSCODES-OUT_OF_RANGE`), preferred over FAILED_PRECONDITION when both apply (`SS:RPC-CODE-Code-1`).
- DEADLINE_EXCEEDED is "The deadline expired before the operation could complete" (`SS:RPC-CODE-DEADLINE_EXCEEDED-1`).
- INTERNAL is "some invariants expected by the underlying system have been broken" (`SS:GRPC-STATUSCODES-INTERNAL`).
- RESOURCE_EXHAUSTED is "perhaps a per-user quota, or perhaps the entire file system is out of space" (`SS:GRPC-STATUSCODES-RESOURCE_EXHAUSTED`). PERMISSION_DENIED "must not be used for rejections caused by exhausting some resource" (`SS:GRPC-STATUSCODES-PERMISSION_DENIED-2`), which is why quota and permission are two separate reasons.
- UNAVAILABLE is "most likely a transient condition" (`SS:GRPC-STATUSCODES-UNAVAILABLE`).
- ABORTED is "typically due to a concurrency issue such as a sequencer check failure" (`SS:GRPC-STATUSCODES-ABORTED`).
- UNKNOWN is for "a `Status` value received from another address space [that] belongs to an error space that is not known in this address space" (`SS:GRPC-STATUSCODES-UNKNOWN`). An upstream HTTP status is exactly that.

The refinement that `code` never returns OK or CANCELLED comes from two places. A failure is never OK (`SS:ABSL-STATUSOR-2`). And cancellation has its own state, so `FAILED` with CANCELLED would be a second way to say the same thing.

## The state, the events and the commands

`stepFile :: Opt FileState -> Event -> Out` is total and non-recursive, with `data Out = Out { next :: Opt FileState, commands :: [Command] }`, and `Absent` means no record exists for this file id. I chose a named record over a tuple because the spike verified postconditions on a plain returned state and on separately returned replies, not on tuple projections. With named measures `next` and `commands`, the postconditions keep that verified shape. Events carry `now :: Instant`, which the shell supplies, because the core reads no clock. Every event carries parsed data. An invalid header field has already become `Absent`, because the draft and RFC 9110 both say invalid values "MUST cause the entire header field to be ignored" (`UP:RESUMABLE-UPLOAD-13-4.1.1-4`, `UP:RESUMABLE-UPLOAD-13-4.1.2-2`, `UP:RESUMABLE-UPLOAD-13-4.1.3-5`).

```
data Event = Event { now :: Instant, what :: Occurrence }
data Occurrence
  = Request ReqId Principal Req                -- Principal = (Authn, Authz) as checked by the shell
  | TransferEnded ReqId Nat Ending             -- bytes durably stored; Ending = FullyProcessed | Interrupted
  | StoreAnswered StoreCall StoreOutcome
  | Reauthorized ReqId Verdict                 -- Verdict = Allowed | NoPermission | OverQuota
  | SourceResponded {c:Int | 100 <= c && c <= 599} RetryAfter SourceMeta
  | SourceFailed TransportFault                -- NothingWritten | ReadFailed | IdleClosed | FreshConnClosed
  | Woken                                      -- a WakeAt the core asked for
  | LifetimeReached
  | StateLost
data Req
  = CreateUpload { uc :: UC, uploadLength :: Opt Nat, contentLength :: Opt Nat, clientDigest :: Opt ClientDigest, metadata :: Metadata }
  | AppendUpload { claimedOffset :: Opt Nat, ucOpt :: Opt UC, uploadLength :: Opt Nat, contentLength :: Opt Nat, mediaTypeOk :: Bool }
  | RetrieveOffset
  | CancelUpload
  | StartImport Url
  | CancelImport
  | GetFile Preconds RangeReq | HeadFile Preconds
  | DeleteFile Preconds
data Command
  = Reply ReqId Response
  | AcceptContent ReqId Budget                 -- stream at most Budget bytes of this request into the store
  | Terminate ReqId                            -- UP:RESUMABLE-UPLOAD-13-4.6-4, UP:RESUMABLE-UPLOAD-13-4.6-5, UP:RESUMABLE-UPLOAD-13-4.5.2-2
  | Defer ReqId                                -- re-deliver after the terminated request's TransferEnded
  | Reauthorize ReqId                          -- UP:RESUMABLE-UPLOAD-13-13-6, UP:RESUMABLE-UPLOAD-13-13-7
  | StoreBegin {a:ChecksumAlgorithm | supports Multipart a FULL_OBJECT} -- CreateMultipartUpload with x-amz-checksum-type FULL_OBJECT
  | StoreFinalize Nat (Opt ClientDigest)       -- CompleteMultipartUpload with MpuObjectSize
  | StoreAbort                                 -- AbortMultipartUpload
  | StoreRemove                                -- DeleteObject
  | Fetch Url (Opt (Nat, EntityTag)) Connection -- GET, resuming with Range: bytes=n- and If-Range: <strong etag>
  | WakeAt Instant
```

- `StoreBegin` can't name an algorithm the store won't vouch for as FULL_OBJECT. That removes the S3 path where checksums at Complete are "accepted but not validated or stored" when the algorithm wasn't declared up front (`PD:S3UG-INTEGRITY-UPLOAD-Full-object-checksums-6`).
- `StoreFinalize` passes the size so S3 checks it (`PD:S3API-CompleteMultipartUpload-request-header-MpuObjectSize-1`).
- `Fetch` resumes only with a strong ETag in If-Range (`HS:RFC9110-13.1.5-3`).
- `Defer` exists because the core can't answer a new request until the old one's processed bytes are known. The shell's side of the contract is to deliver `TransferEnded` for a terminated request before it re-delivers the deferred one.

## The step function, row by row

Every `Request` first passes the admission gate, in this order, before any row below applies: 401, then 403 or the hidden 404, then 404 or 410 for a missing or known-gone record (`Funknown.Http.Admission`). The rows below therefore assume `admit == Clear`, except the rows marked "no record" or "gone", which are the admission results themselves. "UC" abbreviates the `Upload-Complete` field.

### Creating an upload, and appending to it

| # | From | Event and guard | To | Reply | Commands | Cites |
|---|---|---|---|---|---|---|
| U1 | no record | CreateUpload, uc ?0, no content, limits respected | CREATING, offset 0, len from Upload-Length or Unknown | 201, Location, Upload-Limit, UC ?0 | StoreBegin | `UP:RESUMABLE-UPLOAD-13-4.2.1-8`, `UP:RESUMABLE-UPLOAD-13-4.2.2-5`, `UP:RESUMABLE-UPLOAD-13-4.2.2-6`, `UP:TUS-1.0.0-Creation.Example-1` |
| U2 | no record | CreateUpload with content | as U1, then the content is admitted as an append at offset 0 (U5) | answered when the content ends (U9 to U12) | StoreBegin, AcceptContent | `UP:RESUMABLE-UPLOAD-13-4.2.1-1`, `UP:RESUMABLE-UPLOAD-13-4.2.2-4`, `UP:RESUMABLE-UPLOAD-13-4.2.2-11` |
| U3 | no record | CreateUpload whose length exceeds max-size | no record | 413 with Upload-Limit | none | `UP:RESUMABLE-UPLOAD-13-4.1.4-3`, `UP:RESUMABLE-UPLOAD-13-4.1.4-17`, `UP:RESUMABLE-UPLOAD-13-4.1.4-18` |
| U4 | no record | any upload request other than create | no record | 404 | none | `UP:TUS-1.0.0-Core.Requests.PATCH-5`, `HS:RFC9110-15.5.5-1` |
| U5 | CREATING, Idle, not complete | AppendUpload, offset matches, media type ok, lengths consistent, size within max-append-size | Transfer becomes InFlight r budget | none yet | AcceptContent r budget | `UP:RESUMABLE-UPLOAD-13-4.4.1-1`, `UP:RESUMABLE-UPLOAD-13-4.4.1-2`, `UP:RESUMABLE-UPLOAD-13-4.4.2-1` |
| U6 | CREATING, Idle, not complete | AppendUpload, claimed offset differs | unchanged | 409, Upload-Offset = offset, UC ?0, problem mismatching-upload-offset (gated) or about:blank | none | `UP:RESUMABLE-UPLOAD-13-4.4.2-3`, `UP:TUS-1.0.0-Core.Requests.PATCH-2`, `UP:RESUMABLE-UPLOAD-13-7.1-2` |
| U7 | CREATING, Idle | AppendUpload without Upload-Offset | unchanged | 400, UC ?0 | none | `UP:RESUMABLE-UPLOAD-13-4.4.1-2`, `HS:RFC9110-15.5.1` |
| U8a | CREATING, Idle | AppendUpload with the wrong media type | unchanged | 415, UC ?0 | none | `UP:TUS-1.0.0-Core.Requests.PATCH-1`, `HS:RFC9110-15.5.16` |
| U8b | CREATING, Idle | Upload-Length contradicts the known length or is below offset, or offset plus Content-Length on a completing request differs from Upload-Length | unchanged | 400, UC ?0, problem inconsistent-upload-length (gated) or about:blank | none | `UP:RESUMABLE-UPLOAD-13-4.1.3-6`, `UP:RESUMABLE-UPLOAD-13-7.2-1`, `UP:TUSD-2.10.1-getIETFDraftUploadLength-1` |
| U8c | CREATING, Idle | Content-Length above max-append-size | unchanged | 413, Upload-Limit | none | `UP:RESUMABLE-UPLOAD-13-4.1.4-5`, `UP:RESUMABLE-UPLOAD-13-4.1.4-17` |
| U8d | CREATING, InFlight r1 | any request on the upload resource (r2) | unchanged | none | Terminate r1, Defer r2 | `UP:RESUMABLE-UPLOAD-13-4.6-4`, `UP:RESUMABLE-UPLOAD-13-4.6-5` |
| U9 | CREATING, InFlight r b | TransferEnded r n FullyProcessed, UC ?0, n <= b | offset + n, Idle | 204, UC ?0, Upload-Offset = new offset | none | `UP:RESUMABLE-UPLOAD-13-4.4.2-5`, `UP:RESUMABLE-UPLOAD-13-4.1.1-6`, `UP:TUS-1.0.0-Core.Requests.PATCH-4` |
| U10 | CREATING, InFlight r b | TransferEnded r n Interrupted, n <= b | offset + n, Idle, still not complete | none (the connection is gone) | none | `UP:RESUMABLE-UPLOAD-13-4.4.2-2`, `UP:RESUMABLE-UPLOAD-13-4.2.2-11`, `UP:TUS-1.0.0-Core.Requests.PATCH-7` |
| U11 | CREATING, InFlight r b | TransferEnded r n FullyProcessed, UC ?1, offset + n equals the known length (or the length was Unknown) | offset + n, len Known (offset + n), complete, Awaiting Reauthorization r | held | Reauthorize r | `UP:RESUMABLE-UPLOAD-13-4.1.2-3`, `UP:RESUMABLE-UPLOAD-13-4.1.3-3`, `UP:RESUMABLE-UPLOAD-13-13-6`, `UP:RESUMABLE-UPLOAD-13-13-7` |
| U11b | as U11 | same, but offset + n differs from the known length | offset + n, Idle, not complete | 400, UC ?0, inconsistent-upload-length | none | `UP:RESUMABLE-UPLOAD-13-4.1.3-6` |
| U12 | CREATING, InFlight r b | TransferEnded r n _, n > b | FAILED OffsetPastLength | 413, UC ?0 | StoreAbort | `UP:RESUMABLE-UPLOAD-13-4.4.2-7`, `HS:RFC9110-15.5.14-1` |
| U13 | CREATING, Awaiting Reauthorization r | Reauthorized r Allowed | Awaiting StoreAnswer Finalize r 1 | held | StoreFinalize size digest | `UP:RESUMABLE-UPLOAD-13-13-7`, `PD:S3API-CompleteMultipartUpload-request-header-MpuObjectSize-1` |
| U14 | as U13 | Reauthorized r NoPermission | FAILED NotPermittedAtFinalize | 403, UC ?1 | StoreAbort | `UP:RESUMABLE-UPLOAD-13-13-7`, `HS:RFC9110-15.5.4-1`, `UP:RESUMABLE-UPLOAD-13-4.4.2-4` |
| U15 | as U13 | Reauthorized r OverQuota | FAILED QuotaAtFinalize | 507, UC ?1 (status choice is an open question) | StoreAbort | `UP:RESUMABLE-UPLOAD-13-13-7`, `DO:RFC4918-11.5-1` |
| U16 | CREATING, Awaiting StoreAnswer Finalize r k | StoreAnswered Finalize (Answered report), vouch gives a receipt | ACTIVE Object | 201, Location, ETag, Repr-Digest when the receipt's key is Active, UC ?1 | none | `UP:RESUMABLE-UPLOAD-13-4.4.2-4`, `HS:RFC9110-15.3.2-1`, `HS:RFC9110-8.8-3`, `PD:S3UG-INTEGRITY-UPLOAD-checking-object-integrity-upload-1` |
| U17 | as U16 | Answered report, vouch refuses | FAILED (StoreGaveNoReceipt refusal) | 500, UC ?1 | StoreRemove | `PD:S3UG-MPU-mpuAndPermissions-1`, `HS:RFC9110-15.6.1`, `UP:RESUMABLE-UPLOAD-13-4.2.1-11` |
| U18 | as U16 | Refused BadDigest | FAILED StoreRefusedDigest | 400, UC ?1, digest-mismatched-values if the client sent a digest, else about:blank | StoreAbort | `PD:S3UG-INTEGRITY-UPLOAD-Full-object-checksums-2`, `PD:IANA-PROBLEM-TYPES-digest-mismatched-values-1`, `PD:DIGEST-PROBLEMS-3.3-1` |
| U19 | as U16 | Refused with a Transient or Throttling class, k < maxAttempts | Awaiting StoreAnswer Finalize r (k + 1) | held | WakeAt (now + backoff), then StoreFinalize on Woken | `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-3`, `PD:AWSSDK-RETRY-backoff-formula-1` |
| U20 | as U16 | Refused Transient or Throttling with k = maxAttempts, or NoAnswer | FAILED StoreUnavailable | 503, UC ?1 | StoreAbort | `HS:RFC9110-15.6.4-1`, `SS:GRPC-STATUSCODES-UNAVAILABLE` |
| U21 | as U16 | Refused with status 507 | FAILED StoreOutOfSpace | 507, UC ?1 | StoreAbort | `DO:RFC4918-11.5-1` |
| U22 | CREATING (any) | RetrieveOffset | unchanged | 204, Upload-Offset, UC ?0 or ?1, Upload-Length when known, Upload-Limit, Cache-Control: no-store | none | `UP:RESUMABLE-UPLOAD-13-4.3.2-1`, `UP:TUS-1.0.0-Core.Requests.HEAD-1`, `UP:TUS-1.0.0-Core.Requests.HEAD-3`, `UP:RESUMABLE-UPLOAD-13-4.3.3-1` |
| U23 | CREATING, Idle | CancelUpload | CANCELLED | 204 | StoreAbort | `UP:RESUMABLE-UPLOAD-13-4.5.2-1`, `UP:TUS-1.0.0-Termination.Requests.DELETE-1`, `HS:RFC9110-9.3.5-3` |
| U24 | CREATING | LifetimeReached | FAILED LifetimeReached | none | StoreAbort, plus Terminate r if InFlight | `UP:RESUMABLE-UPLOAD-13-4.1.4-7`, `UP:TUS-1.0.0-Expiration-1`, `PD:S3UG-MPU-LIFECYCLE-mpu-abort-incomplete-mpu-lifecycle-config-1` |
| U25 | CREATING | StateLost | FAILED StateLost | none | StoreAbort, plus Terminate r if InFlight | `UP:RESUMABLE-UPLOAD-13-4.1.1-9` |
| U26 | CREATING, complete | AppendUpload, empty, UC ?1, at offset = length | unchanged, the request joins the held reply | answered with the same final reply as the original request | none | `UP:RESUMABLE-UPLOAD-13-4.4.2-6` |
| U27 | CREATING, complete | any other AppendUpload | unchanged | 409, Upload-Offset = length, UC ?0 | none | `UP:RESUMABLE-UPLOAD-13-4.1.2-6`, `HS:RFC9110-15.5.10-1` |
| U28 | ACTIVE | RetrieveOffset, or an empty UC ?1 append at offset = length | unchanged | the 204 of U22 with UC ?1, or a replay of U16's 201 | none | `UP:RESUMABLE-UPLOAD-13-4-3`, `UP:RESUMABLE-UPLOAD-13-4.4.2-6` |
| U29 | ACTIVE | any other upload request | unchanged | 409, Upload-Offset = length, UC ?0 | none | `UP:RESUMABLE-UPLOAD-13-4.1.2-6` |
| U30 | FAILED, CANCELLED, DELETING or DELETED | any upload request | unchanged | 410 | none | `HS:RFC9110-15.5.11-1`, `UP:TUS-1.0.0-Expiration.Headers.Upload-Expires-3`, `UP:TUS-1.0.0-Termination.Requests.DELETE-1` |

U2 works, but it is not resumable before its final reply: the core never sends interim responses, and without a 104 carrying the upload's URI "the client cannot resume that upload" (`UP:RESUMABLE-UPLOAD-13-10.1-1`). I'd recommend that clients create with empty content and UC ?0 (U1), which the draft offers for exactly this reason ("This can be used to retrieve the upload resource's URI before transferring any representation data", `UP:RESUMABLE-UPLOAD-13-4.2.1-8`). The temporary 104 registration then never matters to us.

U12 answers 413 with UC ?0 even though the upload is now invalid. A ?1 would tell the client the reply comes from the targeted resource, which isn't true here. With ?0, a client following the 413 heuristic (`UP:RESUMABLE-UPLOAD-13-4.7-3`) gets a 410 on its next request and stops.

### Importing from a URL

An import is the same `Creation` with `Source = FromUrl`. The source's bytes reach the upload through the same `TransferEnded` rows (U9, U10, U11, U12), and the end of the source's body is the server marking the upload complete (`UP:RESUMABLE-UPLOAD-13-4.1.2-1`). The import differs only in how it starts and how a failure on the source side is handled.

| # | From | Event and guard | To | Reply | Commands | Cites |
|---|---|---|---|---|---|---|
| I1 | no record | StartImport url | CREATING FromUrl, attempt 1, offset 0, len Unknown | 202, Location of the file | StoreBegin, Fetch url Absent fresh | `HS:RFC9110-15.3.3-1`, `HS:RFC9110-15.3.3-3`, `SS:AIP151-StandardMethods-1`, `DO:TES-tesInput.url-1` |
| I2 | CREATING FromUrl | SourceResponded 2xx with a length | len Known, InFlight fetch budget | none | AcceptContent | `UP:RESUMABLE-UPLOAD-13-4.1.3-2`, `HS:RFC9110-8.6-1` |
| I3 | CREATING FromUrl | SourceResponded c, retryDecision GET c ra Automatic == RetryIn d, attempt < maxAttempts | attempt + 1 | none | WakeAt (now + d), then Fetch on Woken | `HS:RFC6585-4-2`, `HS:RFC9110-15.6.4-2`, `HS:RFC9110-15.5.9-2`, `SS:GRFC-A6-Validation-1` |
| I4 | CREATING FromUrl | SourceResponded 421 | attempt + 1 | none | Fetch on a new connection | `HS:RFC9110-15.5.20-2` |
| I5 | CREATING FromUrl | SourceResponded c, DoNotRetry, or attempts exhausted | FAILED (SourceAnswered (fromWire c)) | none | StoreAbort | `HS:RFC9110-15-4`, `SS:GRPC-STATUSCODES-UNKNOWN` |
| I6 | CREATING FromUrl, connRetryUsed False | SourceFailed NothingWritten, ReadFailed or IdleClosed | connRetryUsed True | none | Fetch, resuming at offset with If-Range when sourceTag is strong | `HS:RFC9110-9.2.2-2`, `HS:RFC9110-13.1.5-1`, `HS:RFC9110-13.1.5-3` |
| I7 | CREATING FromUrl | SourceFailed with connRetryUsed True, or FreshConnClosed | FAILED SourceUnreachable | none | StoreAbort | `HS:RFC9110-9.2.2-8` |
| I8 | CREATING FromUrl, offset > 0 | resumed Fetch answered 200 instead of 206 | FAILED SourceChanged | none | StoreAbort | `HS:RFC9110-13.1.5-6`, `UP:RESUMABLE-UPLOAD-13-4.1.1-7`, `SS:GRPC-STATUSCODES-ABORTED` |
| I9 | CREATING FromUrl | CancelImport | CANCELLED | 204 | Terminate fetch, StoreAbort | `SS:LRO-CancelOperation-1`, `SS:LRO-CancelOperation-3`, `HS:RFC9110-9.3.5-3` |

I8 is where the draft's monotonic offset meets a source that changed. Restarting from byte 0 would decrease the offset, which "MUST NOT decrease" (`UP:RESUMABLE-UPLOAD-13-4.1.1-7`), so the only honest outcome is to fail this import with ABORTED. AIP-194 says that code is retried "at a level higher" (`SS:AIP194-GenerallyNonRetryable-ABORTED`), which here means starting a new import.

### Downloading, and deleting

| # | From | Event and guard | To | Reply | Commands | Cites |
|---|---|---|---|---|---|---|
| D1 | ACTIVE | GetFile p r, ladder gives Proceed WithRange, resolve gives Satisfied f l | unchanged | 206, Content-Range f-l/size, ETag | none | `HS:RFC9110-13.2.2-6`, `HS:RFC9110-14.2-7`, `HS:RFC9110-15.3.7.1`, `HS:RFC9110-15.3.7-3` |
| D2 | ACTIVE | as D1, resolve gives Unsatisfiable | unchanged | 416, Content-Range */size | none | `HS:RFC9110-14.2-9`, `HS:RFC9110-14.4-6`, `HS:RFC9110-14.4-7` |
| D3 | ACTIVE | ladder gives Proceed (no range, or Ignore) | unchanged | 200, ETag, Last-Modified, Content-Length, Repr-Digest when Active | none | `HS:RFC9110-15.3.1-2`, `HS:RFC9110-8.8.3.1-2`, `PD:RFC9530-3-1` |
| D4 | ACTIVE | ladder gives V304 | unchanged | 304, ETag | none | `HS:RFC9110-13.1.2-6`, `HS:RFC9110-15.4.5-2` |
| D5 | ACTIVE | ladder gives V412 | unchanged | 412 | none | `HS:RFC9110-13.1.1-5`, `HS:RFC9110-15.5.13` |
| D6 | ACTIVE | HeadFile p | unchanged | the headers of D3 or D4, without content | none | `HS:RFC9110-9.3.2-1`, `HS:RFC9110-9.3.2-2` |
| D7 | CREATING | GetFile or HeadFile; ladder run with no current representation | unchanged | 202 with Retry-After (a fixed delay-seconds policy value), or 412 if If-Match is present | none | `DO:DRS-responses.202Accepted-1`, `DO:DRS-responses.202Accepted.Retry-After-1`, `DO:DRS-responses.202Accepted.Retry-After-2`, `HS:RFC9110-13.1.1-4` |
| D8 | FAILED, CANCELLED, DELETING or DELETED | GetFile or HeadFile | unchanged | 410 | none | `HS:RFC9110-15.5.11-1`, `HS:RFC9110-15.5.5-2` |
| X1 | ACTIVE | DeleteFile p, ladder gives Proceed | DELETING | 202 | StoreRemove | `HS:RFC9110-9.3.5-1`, `HS:RFC9110-9.3.5-3`, `HS:RFC9110-13-2` |
| X2 | DELETING | StoreAnswered Remove (Answered) | DELETED (tombstone keeps the last ETag) | none | none | `SS:AIP216-Active-3` |
| X3 | DELETING | StoreAnswered Remove, Refused (any class) | unchanged | none | WakeAt (now + backoff), then StoreRemove | `PD:AWSSDK-RETRY-backoff-formula-1` |
| X4 | DELETED | DeleteFile with If-Match equal to the tombstone ETag | unchanged | 204 | none | `HS:RFC9110-13.1.1-6` |
| X5 | DELETED | DeleteFile otherwise | unchanged | 410 | none | `HS:RFC9110-15.5.11-1` |
| X6 | CREATING | DeleteFile | CANCELLED | 204 | Terminate the in-flight request if any, StoreAbort | `UP:RESUMABLE-UPLOAD-13-4.5.2-2`, `HS:RFC9110-9.3.5-3` |
| X7 | FAILED or CANCELLED | DeleteFile | unchanged | 410 | none | `HS:RFC9110-15.5.11-1` |

D7 is the one place I'm using DRS's reading of 202. DRS defines 202 with Retry-After on its GetObject, PostObject and GetAccessURL paths as "The operation is delayed and will continue asynchronously" (`DO:DRS-paths.objects.{object_id}.get-1`, `DO:DRS-responses.202Accepted-1`), which is the "object is not ready yet" answer we need. RFC 9110 itself attaches no meaning to Retry-After on a 2xx (`HS:RFC9110-10.2.3-2`, `HS:RFC9110-10.2.3-3`), so the field rides on DRS's authority there and nowhere else.

X2 and D8 answer 410 for a deleted file, not the 404 that RFC 4918 requires after a successful DELETE (`DO:RFC4918-9.6-3`). That MUST binds WebDAV resources, which ours are not. RFC 9110 prefers 410 "if the origin server knows ... that the condition is likely to be permanent" (`HS:RFC9110-15.5.5-2`), and a tombstone is that knowledge. Once the shell drops a tombstone (`HS:RFC9110-15.5.11-3`), the record is gone and admission answers 404.

## What a client is told

The `step` replies are already the client's answer, but they go through three projections in `Funknown.Tell`, and each one is a pure total function.

### The response, and which fields it can carry

```
data Response
  = Created201 { location :: Uri, created :: Created }
  | Ok200 { etag :: EntityTag, lastModified :: Opt HttpDate, size :: Nat, reprDigest :: Opt ReprDigest }
  | Accepted202 { location :: Opt Uri, retryAfter :: Opt Nat }
  | NoContent204 { upload :: Opt UploadFields }                   -- no Content-Length field exists here
  | PartialContent206 { range :: {r:Resolved | isSatisfied r}, size :: Nat, etag :: EntityTag }
  | NotModified304 { etag :: EntityTag }
  | BadRequest400 { uc :: Opt UC, problem :: {p:Problem | recommended p == 400 || isAboutBlank p} }
  | Unauthorized401 { challenges :: NonEmpty Challenge }
  | Forbidden403 { uc :: Opt UC }
  | NotFound404
  | MethodNotAllowed405 { allow :: NonEmpty Method }
  | Conflict409 { uploadOffset :: Nat, problem :: {p:Problem | recommended p == 409 || isAboutBlank p} }
  | Gone410
  | PreconditionFailed412
  | ContentTooLarge413 { uc :: Opt UC, uploadLimit :: Opt UploadLimit, retryAfter :: Opt Nat }
  | UnsupportedMediaType415 { uc :: Opt UC }
  | RangeNotSatisfiable416 { size :: Nat }
  | TooManyRequests429 { retryAfter :: Opt Nat }
  | InternalServerError500 { uc :: Opt UC }
  | ServiceUnavailable503 { uc :: Opt UC, retryAfter :: Opt Nat }
  | InsufficientStorage507 { uc :: Opt UC }
status :: Response -> Status            -- reflected, one equation per constructor

data Created                            -- the two different things a 201 can announce
  = UploadResourceCreated UploadLimit   -- UC ?0; UP:RESUMABLE-UPLOAD-13-4.2.2-5 (Location and Upload-Limit MUST)
  | FileCreated EntityTag (Opt ReprDigest) -- UC ?1; UP:RESUMABLE-UPLOAD-13-4.4.2-4, HS:RFC9110-15.3.2-2
```

The obligations this type discharges without any proof are these:

- 401 always carries a challenge (`HS:RFC9110-15.5.2-2`, `HS:RFC9110-11.6.1-1`).
- 405 always carries Allow (`HS:RFC9110-15.5.6`).
- A 201 for a new upload resource always carries Location and Upload-Limit (`UP:RESUMABLE-UPLOAD-13-4.2.2-5`). A 201 for a finished file always carries an ETag (`HS:RFC9110-15.3.2-2`). Upload-Complete follows from which of the two it is.
- A 206 always carries a Content-Range for a satisfied range (`HS:RFC9110-15.3.7.1`), and its complete-length is strictly greater than its last-pos (`HS:RFC9110-14.4-5`).
- The upload 409 always carries the current offset with UC ?0 (`UP:RESUMABLE-UPLOAD-13-4.4.2-3`).
- A 204 can't carry Content-Length (`HS:RFC9110-8.6-4`).
- Retry-After exists only on 202, 413, 429 and 503, the four places a vendored text gives it meaning (`DO:DRS-responses.202Accepted-1`, `HS:RFC9110-15.5.14-3`, `HS:RFC6585-4-2`, `HS:RFC9110-15.6.4-2`).
- 304 carries ETag (`HS:RFC9110-15.4.5-2`).
- A problem's type always agrees with its status (`PD:RFC9457-3.1.2-2`).

The upload reply to a completing request goes through one function, `replyAfterComplete`, whose refinement says that a 2xx carries UC ?1. That is the draft's "MUST NOT emit a 2xx successful response with the Upload-Complete header field set to false or missing" (`UP:RESUMABLE-UPLOAD-13-4.2.2-4`, `UP:RESUMABLE-UPLOAD-13-4.4.2-4`). The spike verified this shape.

### The fields

`fields :: Response -> [Field]` renders the constructor fields into header lines. Upload-Offset and Upload-Length are Structured Field Integers, UC is `?0` or `?1`, and Upload-Limit is a Dictionary with only the five known keys (`UP:RESUMABLE-UPLOAD-13-4.1.1-4`, `UP:RESUMABLE-UPLOAD-13-4.1.3-5`, `UP:RESUMABLE-UPLOAD-13-4.1.2-2`, `UP:RESUMABLE-UPLOAD-13-4.1.4-2`). Retry-After is always `delay-seconds` rendered from a `Nat` (`HS:RFC9110-10.2.3-6`), and we never send the HTTP-date form, because DRS requires "an integral relative time in seconds" (`DO:DRS-responses.202Accepted.Retry-After-1`) and RFC 9110 allows either. Repr-Digest renders as `sha-256=:<value>:` (`PD:RFC9530-3-1`, `PD:RFC9651-3.3.5-1`). Cache-Control: no-store goes on every offset retrieval (`UP:TUS-1.0.0-Core.Requests.HEAD-3`). The problem body is `application/problem+json` (`PD:RFC9457-3-1`), with `type` omitted for about:blank (`PD:RFC9457-3.1.1-2`) and the title equal to the registry's phrase for that code (`PD:RFC9457-4.2.1-2`).

### The file's own state

`view :: FileState -> FileView` is what a GET on the file's metadata returns. It holds the AIP-216 state token (`SS:AIP216-EnumValues-1`, `SS:AIP216-EnumValues-2`, `SS:AIP216-EnumValues-3`, `SS:AIP216-Active-3`), and for `FAILED` or `CANCELLED` it adds the google.rpc.Code name from `code`, together with the AIP-194 recourse token. For an upload, the recourse after any terminal state is the tus text "the Client SHOULD start a new upload" (`UP:TUS-1.0.0-Expiration.Headers.Upload-Expires-3`). `operation :: FileState -> Op` gives the same information in long-running-operation shape:

```
data Op = InProgress | Done (Result)
data Result = Failed {c:Code | c /= OK} | Succeeded Object
```

- `done=false` sets neither error nor response, and `done=true` sets exactly one (`SS:LRO-Operation-done`, `SS:LRO-Operation-result`), so an illegal operation can't be built.
- CANCELLED becomes `Done (Failed CANCELLED)`, which is how a cancelled operation is reported (`SS:LRO-CancelOperation-3`).
- Whether we expose `Op` over HTTP is open. AIP-193's HTTP JSON puts the HTTP status in `code` (`SS:AIP193-HTTP-1`), and CANCELLED would need the unregistered 499.

## Code we port, and what we fix on the way

The brief welcomes porting from other languages, and the spike shows which parts survive the move into LiquidHaskell. The table only lists the decision each port carries; the reasons are in the type sections above.

| Source | Port target | What changes in the port |
|---|---|---|
| `references/http-semantics/code/go/fs.go:470-662` (condResult, checkIfMatch, checkIfUnmodifiedSince, checkIfNoneMatch, checkIfModifiedSince, checkIfRange, checkPreconditions) | `Http.Precondition.ladder` | (a) the 13.1.1 / 13.1.4 MAY 2xx becomes `AlreadyApplied`; (b) date If-Range is false until 8.8.2.2 is vendored; (c) the If-Match and If-Unmodified-Since steps are guarded by `origin`. The three-valued `condResult` becomes `Cond`. |
| `go/fs.go:431-468` (scanETag, etagStrongMatch, etagWeakMatch) | `Http.Validator` comparisons only | Scanning stays in the shell, because character ranges are not provable here. Comparison becomes the two-line definitions plus the 8.8.3.2 table theorem. |
| `references/http-semantics/code/urllib3/retry.py:184-189, 308-333, 379-407` | `Http.Retry.retryDecision` | Adds 507 after a user action, 421 on a new connection, 425 and 408. Delay-seconds is 1*DIGIT. A past date clamps to 0 as urllib3 does. The allowed-methods set becomes `idempotent`, proved equal to `DEFAULT_ALLOWED_METHODS`. |
| `go/request.go:1543-1557` (isReplayable), `go/transport.go:756-800` (shouldRetryRequest) | the I6 and I7 rows | Idempotency-Key is dropped because it isn't a standard. The "fresh connection, don't retry" and "read error or idle close on a reused connection" cases become `TransportFault` constructors. Go leaves PUT and DELETE out of isReplayable, which RFC 9110 calls idempotent; that doesn't matter to us, since imports only GET. |
| `go/status.go:9-80`, `cpython/http__init__.py:7-175`, `http-types/Status.hs:783-830` | none (shape only) | Status is generated from the IANA CSV. The class predicates become `classOf`, proved against `fromWire`. |
| `references/uploads/tusd/unrouted_handler.go:734` (PatchFile) | the order of rows U5 to U8 | We keep the check order (media type, offset parse, lookup, final, offset match, completed no-op) but drop tus's 412 version check, because we implement the draft rather than tus. |
| `tusd/unrouted_handler.go:881` (writeChunk), `:993` (finishUploadIfComplete) | arithmetic only | new offset = old offset + bytes written (`UP:TUSD-2.10.1-writeChunk-2`). The completion rule `Offset == Size` is not ported, because it contradicts `UP:RESUMABLE-UPLOAD-13-4.1.3-8`. |
| `tusd/unrouted_handler.go:43-73` (error table), `:1283` (sendError) | not ported as a table | Only rows whose status a standard backs survive, and they survive as `Response` constructors: 409 offset, 413 size, 404, 403. 423 (`UP:TUSD-2.10.1-errors.ErrFileLocked-1`) and the 400 for interruption (`UP:TUSD-2.10.1-errors.ErrUploadInterrupted-1`) are dropped. An interrupted request gets no reply at all. |
| `tusd/unrouted_handler.go:1449` (validateNewUploadLengthHeaders), `:1562` (getIETFDraftUploadLength) | U1 and U8b guards | Becomes the draft's two length indicators, which must match (`UP:RESUMABLE-UPLOAD-13-4.1.3-6`). Upload-Defer-Length is tus-only, so it isn't ported. |
| `tusd/datastore.go:12-31` (FileInfo) | `Upload` | `Size` plus `SizeIsDeferred` becomes `Len`. `IsPartial` and `IsFinal` (concatenation) are not ported. |
| `references/uploads/tus-js-client/upload.js:1078` (defaultOnShouldRetry) | not ported | Kept as a contrast. It retries 423, which the draft never mentions, and treats 413 and 429 like any other 4xx. |
| `references/problems-and-digests/code/aws-sdk-js-v3/.../isChecksumWithPartNumber.ts` | `Store.Checksum.classify` | Becomes a total classifier into `Shape`, with a proved disjointness between full-object and part-suffixed values. |
| S3 Smithy model (`api-models-aws/.../s3-2006-03-01.json`) and the S3 user guide table | `Store.Checksum` enums and `supports` | The user-guide table wins over the contradicting at-rest sentence. |
| `smithy-typescript/.../service-error-classification` | `Store.Outcome.classifyStoreError` | Code is matched before status (`PD:AWSSDK-RETRY-error-classification-4`). AbortError has no counterpart, because cancellation is an event, not an error. |
| `aws-checksums/tests/crc64_test.c`, `source/crc64_sw.c`, `Crc64NvmeJs.ts` | not in funknown-core | The brief says we never compute our own digest and call it proof. If we want a CRC-64/NVME oracle for shell tests, it belongs in a separate package. Its check value 0xAE8B14860A799888 (`PD:REVENG-crc.cat.crc-64-nvme-1`) could be proved there by evaluation. |
| `references/drive-and-objects/code/funnel-v0.11.14/tes/states.go:30` (ValidateTransition), `database/boltdb/events.go:188` (transitionTaskState) | not ported as code | The two Go functions disagree about EXECUTOR_ERROR to QUEUED. Our `allowed` relation answers that disagreement: nothing leaves a terminal state, and it's proved by exhaustion and by `terminalAbsorbs`. |
| `funnel-v0.11.14/server/tes.go` (CancelTask) | not ported | Funnel answers success when cancelling a terminal task. We answer 410 (U30, X7), because tus says requests after termination get 404 or 410. |
| `golang-x-net-webdav-v0.61.0/webdav.go`, `lock.go`, `if.go` | not ported | We implement no locks. Their one lesson that applies, authorization before the 412-vs-423 split, is in `admit`. |
| `references/status-and-supervision/googleapis/code.proto`, `aip/0194.md` | `Rpc.Code` | The HTTP mapping is not ported, because it needs 499. |
| `grpc/A6-client-retries.md` | `Http.Retry.backoff`, `MaxAttempts` | Jitter is left to the shell. The token bucket isn't per-file, so it isn't in the core. |
| `otp/supervisor.erl`, `abseil/status.cc` (ErrnoToStatusCode) | not in funknown-core | Supervision of fetchers and errno mapping happen before an event exists. They belong to the shell. |

## Theorem catalog

Every theorem names the statements it encodes and its proof method. "Spike: verified" means the same shape was SAFE in the scratch package. "Spike: pattern" means a structurally identical proof was SAFE there, and only the constructor set differs. "Not spiked" means I expect a plain refinement and haven't run it yet.

### Status, method and validators

- **T-STATUS-1 `statusRange`.** For every `s :: Status`, `100 <= statusCode s <= 599`. Cites `HS:RFC9110-15-1`. Method: refinement on `statusCode`, by construction. Spike: verified.
- **T-STATUS-2 `fromWireClass`.** For every `n :: Int` with `100 <= n <= 599`, `classOf (fromWire n) == classOfCode n`. Cites `HS:RFC9110-15-2`, `HS:RFC9110-15-4`. Method: LiquidHaskell refinement on `fromWire`, symbolic over all `Int`. Spike: verified.
- **T-STATUS-3 `fromWireUnknownIsX00`.** If `n` is valid and unregistered, `fromWire n == x00 (classOfCode n)`, and `statusCode (x00 c) mod 100 == 0`. Cites `HS:RFC9110-15-4`. Method: refinement on `orDefault` and `x00`. Spike: verified.
- **T-STATUS-4 `fromWireInvalid`.** If `n < 100` or `n > 599`, `fromWire n == H500_InternalServerError`. Cites `HS:RFC9110-15-5`, `HS:RFC9110-15-6`. Method: refinement. Spike: verified.
- **T-STATUS-5 `roundTrip` and `codeInjective`.** For every `s`, `fromWire (statusCode s) == s`, and `statusCode a == statusCode b` implies `a == b`. Cites every assigned registry row, `HS:IANA-HTTP-Status-Codes-100` through `HS:IANA-HTTP-Status-Codes-511`, that has a constructor. Method: proof by exhaustion with 62 equational cases, then injectivity as a one-line reflection proof. Spike: verified (about 45 s).
- **T-STATUS-6 `emitPermanent`.** For every `r :: Response`, `registration (status r) == Permanent`. So 104 (Temporary) and 510 (Obsoleted) are never sent, and 306, 418 and 499 are not even representable. Cites `HS:IANA-HTTP-Status-Codes-104`, `HS:IANA-HTTP-Status-Codes-510`, `HS:IANA-HTTP-Status-Codes-306`, `HS:IANA-HTTP-Status-Codes-418`, `HS:IANA-HTTP-Status-Codes-452-499`, `SS:RPC-CODE-CANCELLED-http`. Method: proof by exhaustion over `Response` constructors. Spike: pattern.
- **T-METHOD-1 `safeIsIdempotent`.** `safe m` implies `idempotent m`, and `idempotent PATCH == False`. Cites `HS:RFC9110-9.2.1-2`, `HS:RFC9110-9.2.2-1`, `HS:RFC9110-9.2.2-4`. Method: exhaustion over 8 constructors. Not spiked.
- **T-METHOD-2 `urllib3DefaultsAreIdempotent`.** `m` is in urllib3's `DEFAULT_ALLOWED_METHODS` if and only if `idempotent m`, over our `Method`. Cites `HS:RFC9110-9.2.2-1`. Method: exhaustion. Not spiked.
- **T-ETAG-1 `strongImpliesWeak`.** `strongMatch a b` implies `weakMatch a b`. Cites `HS:RFC9110-8.8.3.2-1`, `HS:RFC9110-8.8.3.2-2`. Method: refinement. Not spiked.
- **T-ETAG-2 `comparisonTable`.** The four rows of `HS:RFC9110-8.8.3.2-3` hold as stated (W/"1" vs W/"1": no strong match, weak match; and so on). Method: exhaustion over the four concrete rows. Not spiked.

### Preconditions, ranges and admission

- **T-PRE-1.** With `origin`, If-Match false, and not (unsafe method and already applied), the verdict is 412. Cites `HS:RFC9110-13.2.2-2`, `HS:RFC9110-13.1.1-5`. Method: refinement on `ladder`. Spike: verified.
- **T-PRE-2.** With `origin`, If-Match absent and If-Unmodified-Since false, the verdict is 412 under the same exception. Cites `HS:RFC9110-13.2.2-3`, `HS:RFC9110-13.1.4-1`, `HS:RFC9110-13.1.4-6`. Method: refinement. Spike: verified.
- **T-PRE-3.** When steps 1 and 2 pass and If-None-Match is false, GET and HEAD get 304 and every other method gets 412. Cites `HS:RFC9110-13.2.2-4`, `HS:RFC9110-13.1.2-6`. Method: refinement. Spike: verified.
- **T-PRE-4.** A 304 only ever comes from If-None-Match false, or from If-None-Match absent with If-Modified-Since false, and only on GET or HEAD. Cites `HS:RFC9110-13.2.2-5`, `HS:RFC9110-13.1.3-1`, `HS:RFC9110-13.1.3-2`. Method: refinement. Spike: verified.
- **T-PRE-5.** A 412 only ever comes from step 1 or 2 failing, or from If-None-Match false on a method other than GET or HEAD. Cites `HS:RFC9110-13.2.2-2`, `HS:RFC9110-13.2.2-3`, `HS:RFC9110-13.2.2-4`. Method: refinement. Spike: verified.
- **T-PRE-6.** `AlreadyApplied` only for an unsafe method whose step 1 or 2 failed and whose change has already been applied. Cites `HS:RFC9110-13.1.1-6`, `HS:RFC9110-13.1.4-7`. Method: refinement. Spike: verified.
- **T-PRE-7.** Range is honoured only for GET with Range present, If-Range absent or true, and the range applicable. Cites `HS:RFC9110-13.2.2-6`, `HS:RFC9110-14.2-2`, `HS:RFC9110-13.1.5-6`. Method: refinement. Spike: verified.
- **T-PRE-8 `nonOriginIgnores`.** If not `origin`, steps 1 and 2 never fail. Cites `HS:RFC9110-13.2.2-2`, `HS:RFC9110-13.2.1-3`. Method: reflection of `gate12Fails`. Spike: pattern.
- **T-PRE-9 `blockedIgnoresPreconditions`.** `gate (Blocked r) _ == r`. Cites `HS:RFC9110-13.2.1-2`. Method: refinement. Not spiked.
- **T-PRE-10 `dateIfRangeFalse`.** If-Range carrying a date always evaluates false. Cites `HS:RFC9110-8.8.2.2`, `HS:RFC9110-13.1.5-4`. Method: by construction (`DateValidator` has no strong form). Not spiked.
- **T-RANGE-1 `satisfiedInside`.** `resolve n spec == Satisfied f l` implies `0 <= f <= l < n`, and `n == 0` implies `Ignore`. Cites `HS:RFC9110-14.1.2-3`, `HS:RFC9110-14.1.2-5`, `HS:RFC9110-14.2-5`, `HS:RFC9110-14.4-5`. Method: refinement. Spike: verified.
- **T-RANGE-2 `unsatisfiableOnlyWhen`.** `Unsatisfiable` only when first-pos is at least `n` or the suffix length is 0. Cites `HS:RFC9110-14.1.2-5`. Method: refinement. Not spiked.
- **T-ADMIT-1 `authnFirst`.** If not `Authenticated`, the result is 401 whatever the authorization and existence. Cites `HS:RFC9110-11.4-1`, `DO:RFC4918-8.1-1`. Method: refinement. Spike: verified.
- **T-ADMIT-2 `noExistenceLeak`.** If authenticated and denied, the result is 404 with `Hide` and 403 with `Reveal`, whatever the existence. Cites `SS:AIP193-PermissionDenied-1`, `HS:RFC9110-15.5.4-4`, `DO:RFC4918-8.5-1`. Method: refinement. Spike: verified.
- **T-ADMIT-3.** 410 only for `KnownGone`, and `Clear` only when all three checks pass. Cites `HS:RFC9110-15.5.11-1`, `SS:AIP193-PermissionDenied-2`. Method: refinement. Spike: verified.

### Retry

- **T-RETRY-1 `noRepeat507`.** Status 507 after a `UserAction` gives `DoNotRetry`. Cites `DO:RFC4918-11.5-2`. Method: refinement. Spike: verified.
- **T-RETRY-2 `nonIdempotentNotRetried`.** Not idempotent and status other than 421 gives `DoNotRetry`. Cites `HS:RFC9110-9.2.2-4`. Method: refinement. Spike: verified.
- **T-RETRY-3 `misdirectedNewConnection`.** Status 421 gives `RetryOnNewConnection`. Cites `HS:RFC9110-15.5.20-2`. Method: refinement. Spike: verified.
- **T-RETRY-4 `nonNegativeDelay`.** `RetryIn d` implies `d >= 0`, and statuses below 400 are never retried. Cites `HS:RFC9110-10.2.3-6`. Method: refinement on the `Decision` constructor. Spike: verified.
- **T-RETRY-5 `oneConnectionRetry`.** Between two `SourceFailed` events, a second `Fetch` is only emitted while `connRetryUsed` is False. Cites `HS:RFC9110-9.2.2-8`. Method: refinement on the import rows. Not spiked.
- **T-RETRY-6 `attemptsBounded`.** `attempt <= maxAttempts <= 5` holds in every reachable state, so status-driven retries terminate. Cites `SS:GRFC-A6-Validation-1`, `UP:RESUMABLE-UPLOAD-13-4.7-7`. Method: data refinement on `Import`. Not spiked.
- **T-RETRY-7 `backoffCapped`.** `backoff ... cap n <= cap`. Cites `SS:GRFC-A6-Backoff`, `PD:AWSSDK-RETRY-backoff-formula-2`. Method: refinement. Not spiked.

### Upload invariants

All of these are conjuncts of `stepFile`'s postcondition or of the `Upload` data refinement, so every reachable state satisfies them.

- **T-UP-1 `offsetNeverDecreases`.** If both the old and new state are CREATING, the offset doesn't decrease. Cites `UP:RESUMABLE-UPLOAD-13-4.1.1-7`. Method: postcondition. Spike: verified.
- **T-UP-2 `lengthImmutable`.** A known length is unchanged by every event. Cites `UP:RESUMABLE-UPLOAD-13-4.1.3-6`, `UP:TUS-1.0.0-Creation.Requests.POST-4`. Method: postcondition. Spike: verified.
- **T-UP-3 `offsetWithinLength`.** A known length implies offset <= length. Cites `UP:RESUMABLE-UPLOAD-13-4.4.2-7`. Method: data refinement. Spike: verified.
- **T-UP-4 `completeMeansLengthIsOffset`.** `complete` implies the length is known and equals the offset. Cites `UP:RESUMABLE-UPLOAD-13-4.1.3-1`, `UP:RESUMABLE-UPLOAD-13-4.1.3-3`. Method: data refinement. Spike: verified.
- **T-UP-5 `completionOnlyExplicit`.** If `complete` goes from False to True, the event was `TransferEnded _ _ FullyProcessed` for a request carrying UC ?1, or the end of an import's body. Cites `UP:RESUMABLE-UPLOAD-13-4.1.2-1`, `UP:RESUMABLE-UPLOAD-13-4.1.2-3`, `UP:RESUMABLE-UPLOAD-13-4.1.3-8`. Method: postcondition. Spike: pattern.
- **T-UP-6 `completeAbsorbing`.** Once complete, the upload stays complete and its offset never changes again. Cites `UP:RESUMABLE-UPLOAD-13-4.1.2-1`. Method: postcondition. Spike: verified.
- **T-UP-7 `interruptedNeverCompletes`.** An `Interrupted` ending never sets `complete`. Cites `UP:RESUMABLE-UPLOAD-13-4.2.2-11`, `UP:RESUMABLE-UPLOAD-13-4.4.2-2`. Method: postcondition. Not spiked.
- **T-UP-8 `offsetMismatchConflict`.** If the claimed offset differs from the current one, the state is unchanged and the reply is `Conflict409` carrying the current offset. Cites `UP:RESUMABLE-UPLOAD-13-4.4.2-3`, `UP:TUS-1.0.0-Core.Requests.PATCH-2`. Method: postcondition on `admitAppend`. Not spiked.
- **T-UP-9 `completingNever2xxIncomplete`.** A request with UC ?1 never gets a 2xx unless UC ?1 is on the reply. Cites `UP:RESUMABLE-UPLOAD-13-4.2.2-4`, `UP:RESUMABLE-UPLOAD-13-4.4.2-4`. Method: refinement on `replyAfterComplete`. Spike: verified.
- **T-UP-10 `oneTransfer`.** At most one request is in flight per upload, and a request arriving while another is in flight yields `Terminate` for the old one before anything else. Cites `UP:RESUMABLE-UPLOAD-13-4.6-1`, `UP:RESUMABLE-UPLOAD-13-4.6-3`, `UP:RESUMABLE-UPLOAD-13-4.6-4`. Method: by construction (`Transfer` has one slot), plus a postcondition. Not spiked.
- **T-UP-11 `inferredOffsetMatches`.** A 2xx append reply with UC ?0 carries an Upload-Offset equal to the old offset plus the bytes processed. Cites `UP:RESUMABLE-UPLOAD-13-4.1.1-6`, `UP:TUS-1.0.0-Core.Requests.PATCH-4`. Method: postcondition. Not spiked.
- **T-UP-12 `budgetGuardsLength`.** `AcceptContent r (Bounded b)` with a known length has `b == len - offset`, and a `TransferEnded` above the budget yields `FAILED OffsetPastLength`. Cites `UP:RESUMABLE-UPLOAD-13-4.4.2-7`. Method: postcondition. Not spiked.
- **T-UP-13 `limitsFrozen`.** `limits` and `expiresAt` never change after creation. Cites `UP:RESUMABLE-UPLOAD-13-4.1.4-8`, `UP:RESUMABLE-UPLOAD-13-4.1.4-9`, `UP:RESUMABLE-UPLOAD-13-4.1.4-10`, `UP:RESUMABLE-UPLOAD-13-4.1.4-11`. Method: postcondition. Not spiked.

### Files, receipts and the store

- **T-FILE-1 `availableOnlyWithReceipt`.** If the new state is ACTIVE, then either the old state was ACTIVE, or the old state was a complete CREATING awaiting Finalize and the event was `StoreAnswered Finalize (Answered report)` with `vouch report == Right receipt`, and that receipt is the new `Object`'s receipt. Cites `PD:S3UG-INTEGRITY-UPLOAD-checking-object-integrity-upload-1`, `PD:S3UG-INTEGRITY-UPLOAD-Full-object-checksums-2`, `PD:S3API-CompleteMultipartUpload-API_CompleteMultipartUpload-2`. Method: postcondition on `stepFile`. Spike: verified (same conjunct shape).
- **T-FILE-2 `receiptIsFullObject`.** Every `Receipt` has `ctype == FULL_OBJECT`, `supports path alg FULL_OBJECT`, and a value shaped for `width alg`. Cites `PD:S3-SMITHY-com.amazonaws.s3#ChecksumType-1`, `PD:S3UG-INTEGRITY-UPLOAD-ChecksumTypes-Uploads-1`, `PD:S3UG-INTEGRITY-UPLOAD-MultipartUploads-Checksums-1`. Method: by construction (refined constructor, not exported). Spike: verified.
- **T-FILE-3 `compositeNeverReceipt`.** `classify v == PartSuffixed n` implies `vouch` refuses, and no string is both `Padded w` and part-suffixed. Cites `PD:AWS-SDK-JS-isChecksumWithPartNumber-isChecksumWithPartNumber-1`, `PD:RFC9651-4.1.8-1`. Method: reflection with induction on the string. Spike: verified (`disjoint`).
- **T-FILE-4 `terminalAbsorbs`.** For FAILED, CANCELLED and DELETED states, `run s es == s` for every event list. Cites `SS:AIP216-Resting` and `UP:TUS-1.0.0-Termination.Requests.DELETE-1`; it is also the answer to Funnel's two disagreeing transition functions. Method: reflection with induction over the event list, using `stepFile`'s postcondition. Spike: verified.
- **T-FILE-5 `transitionsAllowed`.** `allowed (tag s) (tag s')` holds for every step. The relation is: CREATING to {CREATING, ACTIVE, FAILED, CANCELLED}; ACTIVE to {ACTIVE, DELETING}; DELETING to {DELETING, DELETED}; terminal states to themselves. Cites `SS:AIP216-Active-3`, `SS:AIP216-Transition-1`, `SS:AIP216-OutputOnly-2`. Method: postcondition, plus exhaustion over the 6x6 relation for the stated table. Spike: pattern.
- **T-FILE-6 `failureCodeIsError`.** `code r` is neither OK nor CANCELLED. Cites `SS:ABSL-STATUSOR-2`, `SS:LRO-CancelOperation-3`. Method: refinement on `code`, by exhaustion over 12 reasons. Not spiked.
- **T-FILE-7 `operationShape`.** `operation` maps CREATING to `InProgress`, ACTIVE to `Done (Succeeded _)`, FAILED r to `Done (Failed (code r))` and CANCELLED to `Done (Failed CANCELLED)`. Cites `SS:LRO-Operation-done`, `SS:LRO-Operation-result`, `SS:LRO-CancelOperation-3`. Method: by construction (`Op` can't express done with neither result or with both) plus a total function. Not spiked.
- **T-CMD-1 `beginDeclaresFullObject`.** Every `StoreBegin a` has `supports Multipart a FULL_OBJECT`. Cites `PD:S3UG-INTEGRITY-UPLOAD-Full-object-checksums-6`, `PD:S3UG-INTEGRITY-UPLOAD-MultipartUploads-Checksums-1`. Method: refinement on the `Command` constructor. Spike: pattern.
- **T-S3-1 `fullObjectIffCrc`.** `supports Multipart a FULL_OBJECT` holds if and only if `a` is CRC64NVME, CRC32 or CRC32C. Cites `PD:S3UG-INTEGRITY-UPLOAD-MultipartUploads-Checksums-1`, `PD:S3UG-INTEGRITY-UPLOAD-Full-object-checksums-3`. Method: exhaustion over 10 rows. Spike: verified.
- **T-S3-2 `crc64nvmeFullOnly`.** `supports p CRC64NVME COMPOSITE == False` on both paths. Cites `PD:S3API-CompleteMultipartUpload-request-header-ChecksumCRC64NVME-1`. Method: exhaustion. Spike: pattern.
- **T-S3-3 `receiptWidths`.** For every width, the padding count is 1 or 2, and a 64-bit value encodes to 12 characters with one "=". Cites `PD:RFC9651-4.1.8-1`, `PD:S3UG-INTEGRITY-UPLOAD-trailing-checksums-1`, `PD:S3API-PutObject-request-header-ChecksumCRC64NVME-1`. Method: exhaustion over 6 widths, plus one evaluation. Spike: verified.
- **T-S3-4 `storeClassCodeFirst`.** A throttling code is `Throttling` whatever the status, and 500, 502, 503 or 504 with an unrecognized code is `Transient`. Cites `PD:AWSSDK-RETRY-error-classification-4`, `PD:SMITHY-TS-error-classification-constants-TRANSIENT_ERROR_STATUS_CODES-1`. Method: refinement. Not spiked.

### Responses, digests, problems and codes

- **T-DIGEST-1 `reprDigestActiveOnly`.** Every emitted Repr-Digest key has status Active. Cites `PD:RFC9530-5-1`, `PD:RFC9530-5-2`, `PD:IANA-DIGEST-ALGS-sha-256-1`, `PD:IANA-DIGEST-ALGS-sha-512-1`. Method: by construction (refined field). Not spiked.
- **T-PROB-1 `problemAgreesWithStatus`.** The rendered `"status"` member equals `statusCode (status r)`, and a problem type other than about:blank sits only in a response whose status is that type's recommended status. Cites `PD:RFC9457-3.1.2-2`, `PD:IANA-PROBLEM-TYPES-digest-mismatched-values-1`, `UP:RESUMABLE-UPLOAD-13-14.4-1`, `UP:RESUMABLE-UPLOAD-13-14.4-2`. Method: by construction (status computed, refined problem fields) plus exhaustion over 6 problem types. Spike: pattern (`problemStatus`).
- **T-RESP-1 `requiredFields`.** 401 has a challenge, 405 has Allow, 206 has a satisfied Content-Range, the upload 409 has Upload-Offset, 304 has ETag, and 201 has Location. Cites `HS:RFC9110-15.5.2-2`, `HS:RFC9110-15.5.6`, `HS:RFC9110-15.3.7.1`, `UP:RESUMABLE-UPLOAD-13-4.4.2-3`, `HS:RFC9110-15.4.5-2`, `HS:RFC9110-9.3.3-3`. Method: by construction. Spike: verified (401).
- **T-RESP-2 `retryAfterWhereDefined`.** Retry-After is rendered only on 202, 413, 429 and 503. Cites `DO:DRS-responses.202Accepted-1`, `HS:RFC9110-15.5.14-3`, `HS:RFC6585-4-2`, `HS:RFC9110-15.6.4-2`. Method: by construction. Not spiked.
- **T-RESP-3 `noContentLengthOn204`.** `fields (NoContent204 _)` contains no Content-Length. Cites `HS:RFC9110-8.6-4`. Method: by construction. Not spiked.
- **T-RESP-4 `offsetRetrievalNoStore`.** Every reply to `RetrieveOffset` carries Cache-Control: no-store. Cites `UP:TUS-1.0.0-Core.Requests.HEAD-3`, `UP:RESUMABLE-UPLOAD-13-4.3.2-1`. Method: postcondition. Not spiked.
- **T-RPC-1 `codeNumbering`.** `codeNumber` is injective and its range is exactly 0..16. Cites `SS:GRPC-STATUSCODES-OK`, `SS:GRPC-STATUSCODES-UNAUTHENTICATED`, `SS:RPC-CODE-UNAUTHENTICATED-http`. Method: exhaustion with 17 round-trip cases, in the same shape as T-STATUS-5. Spike: pattern.
- **T-RPC-2 `recourseTable`.** `recourse c == Retryable` if and only if `c == UNAVAILABLE`, and DATA_LOSS, INTERNAL and UNKNOWN are `SurfaceImmediately`. Cites `SS:AIP194-Retryable-UNAVAILABLE`, `SS:AIP194-NonRetryable-DATA_LOSS`, `SS:AIP194-GenerallyNonRetryable-INTERNAL`, `SS:AIP194-GenerallyNonRetryable-UNKNOWN`. Method: exhaustion. Not spiked.

The whole catalog should take a few minutes to check. The status module is the slowest piece the spike measured at about 45 seconds, and nothing else came close.

## What the sources leave open

These are the decisions I couldn't ground in a vendored statement. I'd rather we settle them than have the core quietly pick.

1. **For multipart uploads, no receipt can become an Active Repr-Digest.** In multipart uploads S3 offers FULL_OBJECT only for CRC64NVME, CRC32 and CRC32C (`PD:S3UG-INTEGRITY-UPLOAD-Full-object-checksums-3`). The IANA digest registry has no key for the first two, and lists `crc32c` as Deprecated (`PD:IANA-DIGEST-ALGS-crc32c-1`). So for a multipart upload, the store's vouching and an Active `Repr-Digest` can't both exist. DRS has the same gap: its checksum `type` SHOULD come from the Named Information registry, and its fallback list has `crc32c` but no CRC-64 (`DO:DRS-schemas.Checksum.type-1`, `DO:DRS-schemas.Checksum.type-2`). These are the options I can see:
   - Accept that multipart files carry no Repr-Digest.
   - Emit Deprecated `crc32c` with the store set to CRC32C. `PD:RFC9530-5-2` allows that "to preserve integrity against corruption" but not in an adversarial setting.
   - Send small files through single-part PutObject with SHA256, where FULL_OBJECT is guaranteed (`PD:S3API-PutObject-response-header-ChecksumType-1`), and accept that this sets a size ceiling.

   The core's types work under all three. Only `Policy.storeAlgorithm` and the `ReprDigest` refinement would change.
2. **Is draft vocabulary standard enough?** Upload-Offset, Upload-Complete, Upload-Length, Upload-Limit, application/partial-upload and the two upload problem types all come from draft-ietf-httpbis-resumable-upload-13, an Internet-Draft. The problem types are IANA requests, not registry entries, and 104 is a temporary registration that expires 2026-11-13 (`HS:IANA-HTTP-Status-Codes-104`). The core gates the problem types behind a flag and never emits 104, but the header fields themselves have no registered alternative except tus, which is not an IETF standard either.
3. **Hiding forbidden files.** `HS:RFC9110-15.5.4-4` lets us answer 404 instead of 403, and S3 makes that choice depend on the ListBucket permission (`PD:S3API-GetObject-API_GetObject-1`). `Disclosure` is a parameter; someone has to pick the default.
4. **What code a failed import gets.** I chose UNKNOWN with the source's status attached, because the gRPC HTTP-to-Code table is explicitly not for this use (`SS:GRPC-HTTPMAP-scope-2`) and code.proto's mapping only runs from Code to HTTP. If we want a source's 404 to show up as NOT_FOUND, we'd need a mapping that no vendored text defines.
5. **Which status for quota exceeded at finalize.** U15 uses 507 because RFC 4918 describes it as being "unable to store the representation" (`DO:RFC4918-11.5-1`) and its no-automatic-retry rule fits a quota. But RFC 4918 also says that a 5xx implies the problem is the server's (`DO:RFC4918-20.2-2`). 403 and 429 are the alternatives, and no vendored text settles it.
6. **504 or 503 when the store doesn't answer in time.** U20 uses 503. 504 fits "did not receive a timely response from an upstream server" (`HS:RFC9110-15.6.5`), but that text describes a server "acting as a gateway or proxy", which we aren't from the client's point of view.
7. **The retry budget.** RFC 9110 gives none. gRFC A6 (`SS:GRFC-A6-Validation-1`) is about gRPC, AWS's "3" (`PD:AWSSDK-RETRY-retry-settings-1`) is an example rather than a default, and the draft only says to limit retries (`UP:RESUMABLE-UPLOAD-13-4.7-7`). The `MaxAttempts` refinement holds for any value in 2..5; we only need to pick one.
8. **500 from an import source.** AWS calls 500 transient (`PD:SMITHY-TS-error-classification-constants-TRANSIENT_ERROR_STATUS_CODES-1`). urllib3 doesn't retry it, and RFC 9110 doesn't say either way. I followed urllib3 for sources and AWS for the store, which means the same status gets two treatments depending on who sent it. I can defend that, but it should be a conscious decision.
9. **How long a completed upload resource lives.** Keeping it lets a client whose final response was lost recover (`UP:RESUMABLE-UPLOAD-13-4-3`, `UP:RESUMABLE-UPLOAD-13-4.4.2-6`). How long is a cost decision, and so is how long DELETED tombstones live (`HS:RFC9110-15.5.11-3`).
10. **Statements to extract before we write code.** Each of these blocks a type or theorem above:
    - The bit widths of CRC32C, SHA1, SHA512, MD5 and the three XXHASH variants. They are in `aws/api-API_Checksum.md` but not in `statements.json`.
    - The rules of RFC 9110 8.8.2.2, so that date validators can ever be strong.
    - RFC 4648 section 4 (the base64 alphabet and its length), which `PD:RFC9651-3.3.5-1` points to but which isn't vendored.
    - RFC 9651's Integer, Boolean and Dictionary serialisation, needed for the Upload-* fields.
    - RFC 5789, if we want PATCH's semantics from its own source rather than the draft's.
11. **The status of a file whose store copy disappeared.** If a store read later finds the object missing, nothing vendored says whether an ACTIVE file may go back to some other state. The `allowed` relation forbids it today, and AIP-216 says nothing about it either way.
12. **What the prover can't reach.** Header parsing (ETag lists, HTTP-dates, Structured Fields) needs character ranges, which this LiquidHaskell build can't order. If we want those parsers proven too, the honest route looks to me like a byte-level (`[Word8]`) encoding, where comparisons are integer comparisons z3 handles. That is a separate spike.
