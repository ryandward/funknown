# http-semantics references: provenance

Every file in this directory was fetched verbatim on 2026-10-09 and has not
been edited since. `statements.json` is the only derived file. Each quote in
it was checked by script to be a whitespace-normalised substring of the file
it cites, and the build refuses to write the JSON if any quote fails that check.

We pulled RFC 4918, RFC 8470 and RFC 9530 in addition to the requested set
because the IANA registry points 423/424/507 at RFC 4918 and 425 at RFC 8470,
and because RFC 9530 is the HTTP standard for content and representation
digests, which the core needs if it is going to name a store's full-object
digest with existing vocabulary.

We added RFC 5789 later on 2026-10-09, because the upload draft appends with PATCH and RFC 9110
does not define that method, so PATCH's safety, idempotency, atomicity and its 415 and
Accept-Patch rules have to come from its own RFC. Its statements are the `RFC5789-*` ids.

## Specifications

| File | URL | sha256 | License |
|---|---|---|---|
| rfc9110.txt | https://www.rfc-editor.org/rfc/rfc9110.txt | 21c1cdce6ab0e5509b04d84a28000836c7a087cf786efe6f04877ebfff47232a | IETF Trust Legal Provisions (BCP 78); verbatim reproduction permitted |
| rfc9111.txt | https://www.rfc-editor.org/rfc/rfc9111.txt | aeb52adb3279d5f23dae34f68af11bd5cef0a0aff7ffcd014c9ca93c5302cf3e | IETF Trust Legal Provisions (BCP 78) |
| rfc6585.txt | https://www.rfc-editor.org/rfc/rfc6585.txt | f6d55d1b491cd515c35827cf9181753b23b2a68c4df14e56d83dc445b3876e58 | IETF Trust Legal Provisions (BCP 78) |
| rfc7725.txt | https://www.rfc-editor.org/rfc/rfc7725.txt | 5817efa6758a33c42d3eed71311186730ab719499a510e40ea3049e62eae20b1 | IETF Trust Legal Provisions (BCP 78) |
| rfc4918.txt | https://www.rfc-editor.org/rfc/rfc4918.txt | 619ad705b4c0e26af2d0652bb48ca1fa9bd080546993d46730d604b9fe2bdf25 | IETF Trust (BCP 78, pre-2009 full copyright statement); verbatim reproduction permitted |
| rfc5789.txt | https://www.rfc-editor.org/rfc/rfc5789.txt | 9405262c2f3a33848c6cf1694e5e40222eb27a6858a6d93e70328b444d197e8f | IETF Trust Legal Provisions (BCP 78); verbatim reproduction permitted |
| rfc8470.txt | https://www.rfc-editor.org/rfc/rfc8470.txt | 483c316c2b5d2687357fc66e3da5acc153cc4cfe9817d92da8f63b9e21a62974 | IETF Trust Legal Provisions (BCP 78) |
| rfc9530.txt | https://www.rfc-editor.org/rfc/rfc9530.txt | 544dbb7d9afceafa8c9931d9924ca6cff2b4807274166d7ed2483342ef2cdd6a | IETF Trust Legal Provisions (BCP 78) |
| http-status-codes-1.csv | https://www.iana.org/assignments/http-status-codes/http-status-codes-1.csv | 4a9550d4b4ae49cf41cf9050cf9b56b0d6082ad1edfc0e2b09b07f251a36d7a4 | IANA Protocol Registry; CC0 1.0 per IANA/IETF joint statement of 2021-11-10 (https://www.iana.org/help/licensing-terms) |
| http-digest-hash-alg.xml | https://www.iana.org/assignments/http-digest-hash-alg/http-digest-hash-alg.xml | 6336a1abc58420f6fcabab4a0cd999ce3c0a8f12e034e543f05edf342cf927e7 | IANA Protocol Registry; CC0 1.0 (same statement). IANA publishes no CSV for this registry, so we took the XML. |

## Reference code

We pinned each of these to an exact release tag so that the hashes stay
reproducible.

| File | URL | sha256 | License |
|---|---|---|---|
| code/go/status.go | https://raw.githubusercontent.com/golang/go/go1.23.4/src/net/http/status.go | 7633ca0ca545767f3db3d8960a96ee4ecd68fb39439c88b7c03efcb3d1786297 | BSD-3-Clause (code/go/LICENSE) |
| code/go/fs.go | https://raw.githubusercontent.com/golang/go/go1.23.4/src/net/http/fs.go | d18ccb17490c1063dd97aa11a0aeebcdfcfd08eb746cf366dd401598fefa1b4c | BSD-3-Clause |
| code/go/request.go | https://raw.githubusercontent.com/golang/go/go1.23.4/src/net/http/request.go | b132187068ae96610d49095fcd8d61611265ad590042b71f803b39ad412f025e | BSD-3-Clause |
| code/go/transport.go | https://raw.githubusercontent.com/golang/go/go1.23.4/src/net/http/transport.go | de87c053e4c90297a76656d1c7eb15c757e03d959a1a943303ba22db03c93f3c | BSD-3-Clause |
| code/go/LICENSE | https://raw.githubusercontent.com/golang/go/go1.23.4/LICENSE | 2d36597f7117c38b006835ae7f537487207d8ec407aa9d9980794b2030cbc067 | (license text) |
| code/urllib3/retry.py | https://raw.githubusercontent.com/urllib3/urllib3/2.2.3/src/urllib3/util/retry.py | 6e3fb6614a9b9712e5bfc4c78397f1c30f83339e1709b8e0657210ef55e2a026 | MIT (code/urllib3/LICENSE.txt) |
| code/urllib3/LICENSE.txt | https://raw.githubusercontent.com/urllib3/urllib3/2.2.3/LICENSE.txt | 130e3a64d5fdd5d096a752694634a7d9df284469de86e5732100268041e3d686 | (license text) |
| code/cpython/http__init__.py | https://raw.githubusercontent.com/python/cpython/v3.12.7/Lib/http/__init__.py | 17f4f6832cfc84b5b9600414bab80b77e67ccb611bdfed10a3f2beca9d0d568b | PSF License v2 (code/cpython/LICENSE) |
| code/cpython/LICENSE | https://raw.githubusercontent.com/python/cpython/v3.12.7/LICENSE | 3b2f81fe21d181c499c59a256c8e1968455d6689d269aa85373bfb6af41da3bf | (license text) |
| code/http-types/Status.hs | https://hackage.haskell.org/package/http-types-0.12.4/src/Network/HTTP/Types/Status.hs | 84273bd7bec28fbc087932481a72614a9c713cda17e93035243de9bcfa375b33 | BSD-3-Clause (code/http-types/LICENSE) |
| code/http-types/Method.hs | https://hackage.haskell.org/package/http-types-0.12.4/src/Network/HTTP/Types/Method.hs | 12f4deb11bbf598e2323f6f832b4b22846392dfd94ccfc80f69fe22ef707e8b6 | BSD-3-Clause |
| code/http-types/LICENSE | https://hackage.haskell.org/package/http-types-0.12.4/src/LICENSE | 18fdcbbfc576fa4da1473406dfb266c33183c6a3858bc8886283493130b25455 | (license text) |

## How statements.json is shaped

- `id` is `<DOC>-<section>` with `-<n>` appended when a section yields more
  than one statement. For the IANA CSV, `section` is the registry `Value`
  column (a code such as `507` or a range such as `432-450`), and the quote is
  the whole CSV line.
- `level` is the strongest BCP 14 keyword in the quote (`MUST` covers MUST NOT
  and REQUIRED, `SHOULD` covers SHOULD NOT and RECOMMENDED). We used
  `definition` for "status code X indicates ..." text and for grammar and
  registry rows, and `informative` for everything else.
- `topic` is one of: status-code, registry, registry-unassigned, retry,
  recourse, idempotency, conditional, validator, range, upload, upload-offset,
  completion, finished-object-metadata, object-state, integrity, expiry,
  cancellation, authn-authz, destination, gateway, misdirected, rate-limit,
  size-limit, redirect, download, error-handling.
- Quotes from RFC 9110 note blocks keep their `|` margin characters, because
  those characters really are in the vendored text.
