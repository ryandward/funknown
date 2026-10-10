# uploads references: provenance

Everything in this directory was fetched on 2026-10-09 and is stored byte-for-byte as fetched. Nothing has been edited or reflowed. The `statements.json` quotes are checked against these files after whitespace normalisation only, meaning every run of whitespace is collapsed to one space.

## How to read the quotes

The two IETF drafts are paginated plain text. A sentence that crosses a page break has the running footer and header (`Kleidl, et al. ... [Page N]`, form feed, `Internet-Draft  Resumable Uploads  October 2026`) in the middle of it. I didn't want to strip those lines out, because then the quotes would no longer be verbatim. So each sentence like that is split into two consecutive statements, and the topic of each half says "(sentence continues across page break ...)" or "(continuation)". In these files, words hyphenated at a line break show up as `Upload- Complete`, `non- negative` or `no- store`, and the quotes keep that form exactly.

`statements.json` cites draft -13, not -12. The datatracker listed `rev: 13` (published 2026-10-06), which is newer than the -12 named in the task. -12 is vendored as well for comparison. The -13 changelog (Appendix A) lists five changes from -12:

- Upload-Complete and Upload-Length are no longer required on offset retrieval responses.
- The discouragement against sending requests after expiration was removed.
- It clarifies how the upload offset is inferred from responses.
- Successful responses that report an incomplete upload are disallowed when the request indicated completion.
- It adds considerations for when the initially targeted resource and the upload resource have different origins (new Section 13.1).

For tus, `statements.json` cites the canonical GitHub source `tus-protocol.md`. The tus.io website copy (`tus-resumable-upload-1.0.x.md`) is the same text reflowed by the site's generator, plus front-matter. I diffed the two. Apart from line wrapping, the only differences are in the website copy: the checksum outcome list is numbered `1.` instead of `1)`, and "the`404 Not Found`" is missing a space.

The tusd and tus-js-client statements quote implementation source. They are marked `informative` with a `doc` that says "(implementation, not a standard)". They record what the reference implementations actually do and are not a source of vocabulary.

## Files

### IETF draft, Resumable Uploads for HTTP

- `draft-ietf-httpbis-resumable-upload-13.txt`
  - URL: https://www.ietf.org/archive/id/draft-ietf-httpbis-resumable-upload-13.txt
  - Retrieved: 2026-10-09
  - sha256: 3053c6e3fbdcffebf54d84dbecfe4644b0ca9e5e21c189e0269a37e4f4c5ce78
  - Version check: https://datatracker.ietf.org/api/v1/doc/document/draft-ietf-httpbis-resumable-upload/?format=json reported `"rev": "13"`, time 2026-10-06T16:50:06Z, expires 2027-04-09.
  - License: IETF Trust Legal Provisions (BCP 78). Code Components carry the Revised BSD License.
- `draft-ietf-httpbis-resumable-upload-12.txt`
  - URL: https://www.ietf.org/archive/id/draft-ietf-httpbis-resumable-upload-12.txt
  - Retrieved: 2026-10-09
  - sha256: 951149bea264fd50686dd05033b42fceb5eb42e4c3c3aef3a84b94180e17a440
  - License: IETF Trust Legal Provisions (BCP 78), same as above. It has been superseded by -13 and is not cited.

### tus resumable upload protocol 1.0.0

- `tus-protocol.md` (canonical, cited)
  - URL: https://raw.githubusercontent.com/tus/tus-resumable-upload-protocol/c6a11fa3d7b6198e00e4aa5289ccb71314162b84/protocol.md
  - Commit: c6a11fa3d7b6198e00e4aa5289ccb71314162b84 (main HEAD on 2026-10-09, committed 2026-06-08)
  - Retrieved: 2026-10-09
  - sha256: dfc82027d295c80c3ff799f8f6944115e6fb383373a0b41d0eec296200535bb6
  - License: MIT, Copyright (c) 2013-2016 Transloadit Ltd and Contributors (see `tus-protocol-LICENSE.txt`).
- `tus-protocol-LICENSE.txt`
  - URL: https://raw.githubusercontent.com/tus/tus-resumable-upload-protocol/c6a11fa3d7b6198e00e4aa5289ccb71314162b84/LICENSE.txt
  - Retrieved: 2026-10-09
  - sha256: ba905e8e46482566a80099b8abd28ec2f378e2f6bafc319ce9d6dc42fed81915
- `tus-protocol-openapi3.yaml` (machine-readable status-code table for each operation in core and extensions)
  - URL: https://raw.githubusercontent.com/tus/tus-resumable-upload-protocol/c6a11fa3d7b6198e00e4aa5289ccb71314162b84/OpenAPI/openapi3.yaml
  - Retrieved: 2026-10-09
  - sha256: db3565cd5936ea26b85f8f1f0e99cca2d40243fdb6008a5e520b73ecaf96ac77
  - License: MIT (same repository).
- `tus-resumable-upload-1.0.x.md` (the source behind https://tus.io/protocols/resumable-upload)
  - URL: https://raw.githubusercontent.com/tus/tus.io/main/src/content/protocols/1.0.x.md
  - tus.io main HEAD on retrieval: 180e64ff090d33488c3ae1286f1d8168cd67bf72. The last commit to this file was 9ec1dd16a220d4caf2ee2a7113b808607d69807d (2025-06-26).
  - Retrieved: 2026-10-09
  - sha256: 85c29a12d68f8cf0f49f28b9e104e10c0a7f3cd772379c8efbee2d16d14caa3b
  - License: the protocol text says it is MIT (Transloadit Ltd and Contributors). The website repository's own LICENSE.md is MIT and is vendored as `tus.io-LICENSE.md`.
- `tus.io-LICENSE.md`
  - URL: https://raw.githubusercontent.com/tus/tus.io/main/LICENSE.md
  - Retrieved: 2026-10-09
  - sha256: f1369b2d0b7576d3b8b1cb15ce2011dcf6974623f567ad520a67d2cc411c8c26

### tusd v2.10.1 (reference server, Go), `pkg/handler`

All files were fetched from tag v2.10.1, commit 388a27cb81c33b2349e0308b5e97e23797e86fd9, released 2026-09-16. The tag's base URL is https://raw.githubusercontent.com/tus/tusd/v2.10.1/pkg/handler/. License: MIT, Copyright (c) 2013-2017 Transloadit Ltd and Contributors (`tusd/LICENSE.txt`).

- `tusd/unrouted_handler.go`: the error table (the `Err*` vars, each with code, message and HTTP status), POST/HEAD/PATCH/DELETE handling, offset/length/completion rules, and IETF-draft interop. sha256: bc124f164bf6f55059ed24755da8af0691d2be08bd13d22eb9000eca1fb72d1a
- `tusd/error.go`: the `Error` type and `NewError`. sha256: 5b23ee580b5a162dfc6891dafa9fc3f0e8687e71f1d11c7fa94b62d52e6b38dd
- `tusd/datastore.go`: `FileInfo` (Size, SizeIsDeferred, Offset, IsPartial, IsFinal) and the store interfaces. sha256: 957a59f43ef22a2ba0b7f9aace7c38b2f7d7ab8326df562f600bd986763f68e1
- `tusd/body_reader.go`: maps body read failures to the error table (EOF, reset, timeout, size). sha256: fbf8ed85ce00ba6ca7ae5eda69cfdc699c7c2bc94e9605033cdcd75caf9c06cf
- `tusd/http.go`: `HTTPResponse` / `MergeWith`. sha256: e2638567ac51a1e0711180ddf734c50f9b9dc10454e4b4ad64967d70cfec825f
- `tusd/hooks.go`: sha256: 27bb46fb759280ec35f2d2479ca6bd872826ff3ea3913c719a3b44a406efc175
- `tusd/config.go`: timeouts (lock, network, graceful completion) and MaxSize. sha256: 284f91c03868118a8bc3aa867b53fe6d0104b4258b44ddbf12554fa85f72dbee
- `tusd/composer.go`: sha256: 2464866f92419cddd30696a7923a9b7c79008f13538e4e38d85aef95eca712c2
- `tusd/handler.go`: routing. sha256: 3cbb00170ed948aecbf3fa7c4c5a49bded3527cf799e3012a9b3c908d1e4fa36
- `tusd/LICENSE.txt`
  - URL: https://raw.githubusercontent.com/tus/tusd/v2.10.1/LICENSE.txt
  - sha256: 6ffc8271ebdc9f41112f385e7a80ca0c5167650883c90c4727848f5dc291fb5c

### tus-js-client v4.3.1 (reference client, JavaScript), client-side retry policy

All files were fetched from tag v4.3.1, commit bf3337ce4921ed9103a085d258afc39cff2b4e7a, released 2025-01-16. License: MIT, Copyright (c) 2015 tus - Resumable File Uploads (`tus-js-client/LICENSE`).

- `tus-js-client/upload.js`
  - URL: https://raw.githubusercontent.com/tus/tus-js-client/v4.3.1/lib/upload.js
  - sha256: d27c3fbeaf95dd2103b79cf9e8d27d20564c8673ebff84ac5cc67baf2f56364b
- `tus-js-client/error.js`
  - URL: https://raw.githubusercontent.com/tus/tus-js-client/v4.3.1/lib/error.js
  - sha256: 8c5c9af4ee61b4453ce2c06519bffc0a0ef866a40f86e56782382a640cb0abda
- `tus-js-client/LICENSE`
  - URL: https://raw.githubusercontent.com/tus/tus-js-client/v4.3.1/LICENSE
  - sha256: 2ec372e137fa65938a6551e9abaa3d3ea21f5ebd398fca00a13354ea881e6539

### Derived

- `statements.json`: 276 statements: 171 from draft -13, 51 from tus 1.0.0, 49 from tusd, and 5 from tus-js-client. Every `quote` was checked mechanically to be a substring of its `file` after whitespace normalisation. Its sha256 changes whenever it is regenerated, so it is not pinned here.
