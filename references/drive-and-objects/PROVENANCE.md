# Provenance: drive-and-objects

Every file below was retrieved on 2026-10-09 and is stored byte-for-byte as fetched (git checkouts of release tags for the GA4GH specs and the reference code; a direct download for the RFC). Each sha256 was computed over the stored file, and a spot check against the raw.githubusercontent.com URL for two files gave identical hashes.

`statements.json` is derived, not fetched. Each quote in it was checked by script to occur in its `file` after collapsing runs of whitespace to a single space, so YAML folding, markdown line wraps and RFC line wraps are the only differences from the stored bytes. Levels for RFC 4918 come from the upper-case BCP 14 keywords only (lower-case "must" in RFC 4918 prose is graded informative). DRS declares RFC 2119 keywords in its Introduction but its schema descriptions often write them in lower case ("must be provided", "must be an integral relative time"), and those were graded MUST/SHOULD by their plain meaning. TES and WES declare no keyword convention, so their requirement words were graded the same way.

## RFC 4918 (HTTP Extensions for Web Distributed Authoring and Versioning (WebDAV), June 2007)

License: IETF Trust, Copyright (C) The IETF Trust (2007); subject to BCP 78 (see the Full Copyright Statement at the end of the file). Verbatim redistribution of RFCs is permitted.

Canonical plain-text form from the RFC Editor.


| file | URL | sha256 |
|---|---|---|
| `rfc4918.txt` | https://www.rfc-editor.org/rfc/rfc4918.txt | `619ad705b4c0e26af2d0652bb48ca1fa9bd080546993d46730d604b9fe2bdf25` |

Retrieved: 2026-10-09

## GA4GH Data Repository Service (DRS) 1.5.0, repo ga4gh/data-repository-service-schemas, tag drs-1.5.0 (annotated tag a0e65629c90182fe9daf60087fe9b89e0b953138 -> commit fe25c3953ae3398a31054d3f9f040d5e27aad517), released 2025-03-25. Latest non-prerelease DRS release as of retrieval.

License: Apache License 2.0 (ga4gh-drs-1.5.0/LICENSE).

The whole openapi/ tree is vendored because the root spec $refs into tags/, paths/ and components/. The site-only pages/ tree was not vendored.


| file | URL | sha256 |
|---|---|---|
| `ga4gh-drs-1.5.0/LICENSE` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/LICENSE | `d680f254d680e2320f4b53e5266ecfab3311f91633dae92b7119d32323917e90` |
| `ga4gh-drs-1.5.0/README.md` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/README.md | `4972487ecf5e959b4f5bd372a408cd6fae8fd370e34fb9146a175283c3d69be7` |
| `ga4gh-drs-1.5.0/openapi/components/parameters/AccessId.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/parameters/AccessId.yaml | `1633c5e06f5b9eef7feeeefb8e37f0ceca5664f126159530cf18a204c86f076c` |
| `ga4gh-drs-1.5.0/openapi/components/parameters/BulkObjectAccessId.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/parameters/BulkObjectAccessId.yaml | `8398720a7a2ec15b4b7a2071b5652f8fa95827aed267f4f963e8af84a6e8fc7d` |
| `ga4gh-drs-1.5.0/openapi/components/parameters/BulkObjectId.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/parameters/BulkObjectId.yaml | `5833311e3987c3e93c66343fb338f963fd84460d1a63747e0e2594b59451a729` |
| `ga4gh-drs-1.5.0/openapi/components/parameters/BulkObjectIdNoPassport.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/parameters/BulkObjectIdNoPassport.yaml | `a1f3d2e3d04b923e4ecb84ebb743798a3a9a2f07990083cdd52798eb13170f04` |
| `ga4gh-drs-1.5.0/openapi/components/parameters/BulkObjectSingleAccessId.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/parameters/BulkObjectSingleAccessId.yaml | `7b5f7c79c61129ac48e973253be56020625840cd043ee0490be7e25319422832` |
| `ga4gh-drs-1.5.0/openapi/components/parameters/Expand.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/parameters/Expand.yaml | `bf2cedb85919aa7bff4346106a0a3a758418a30c1f76d5cde414aa15208c0976` |
| `ga4gh-drs-1.5.0/openapi/components/parameters/ObjectId.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/parameters/ObjectId.yaml | `2da8b579821279500c529650f9453d8e2d84efd23600d81964e5a37b36e5670b` |
| `ga4gh-drs-1.5.0/openapi/components/requestBodies/Passports.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/requestBodies/Passports.yaml | `8c6c0a43c87f0559df18c7d08b9420e9ae2b901338adaba3e081c260c2a7b8b9` |
| `ga4gh-drs-1.5.0/openapi/components/requestBodies/PostObjectBody.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/requestBodies/PostObjectBody.yaml | `787627599414f6e739ad4dfbb3c76c3d4b9ed3574b221a3c41e4165f9e2a3241` |
| `ga4gh-drs-1.5.0/openapi/components/responses/200OkAccess.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/responses/200OkAccess.yaml | `f8d59e21bf23d0148f4dc551115abf0feb4a6bf394afefc103b29a2e8dd9468b` |
| `ga4gh-drs-1.5.0/openapi/components/responses/200OkAccesses.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/responses/200OkAccesses.yaml | `b02a2c7d57034ff7922bf4e9553125a50360b77c39eae4526b80929c8abb8f16` |
| `ga4gh-drs-1.5.0/openapi/components/responses/200OkAuthorizations.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/responses/200OkAuthorizations.yaml | `3a216afbcc1abc8879ebdcfe6e70bbc9d7760c6398d75d77e83940b940200d28` |
| `ga4gh-drs-1.5.0/openapi/components/responses/200OkBulkAuthorizations.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/responses/200OkBulkAuthorizations.yaml | `2bb38375bd1b35f32debb135f722ae4e3c184b655e8b4f41d716f46a7db5bcf5` |
| `ga4gh-drs-1.5.0/openapi/components/responses/200OkDrsObject.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/responses/200OkDrsObject.yaml | `eb60ef8cf1c1860203a6096c9f2d70bff0c7f5e16537e3220c603acf63b094ba` |
| `ga4gh-drs-1.5.0/openapi/components/responses/200OkDrsObjects.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/responses/200OkDrsObjects.yaml | `ea39e6cea7fc823603b0f46747c0a33e63dd985a46d560e3d7d585ca5f9dcf7f` |
| `ga4gh-drs-1.5.0/openapi/components/responses/200ServiceInfo.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/responses/200ServiceInfo.yaml | `f2c339113ee71e38c3bdc07b3374a29336bd2865b085dfdf634e692c5c615617` |
| `ga4gh-drs-1.5.0/openapi/components/responses/202Accepted.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/responses/202Accepted.yaml | `550f074e9c8996ab219dc667ba0a466880d9c0e7a5fc67bb58c46e2efa54a5d0` |
| `ga4gh-drs-1.5.0/openapi/components/responses/400BadRequest.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/responses/400BadRequest.yaml | `be42d56d9b62d578cad5e224388cf76bb2d293e4976532c3f2a7b80745dc37a3` |
| `ga4gh-drs-1.5.0/openapi/components/responses/401Unauthorized.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/responses/401Unauthorized.yaml | `3188b6a9adca7ab6a5d0c90714adc522ddd8310b0bbceb66f751ddf626feb26e` |
| `ga4gh-drs-1.5.0/openapi/components/responses/403Forbidden.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/responses/403Forbidden.yaml | `b7dbf6dfebc01497cd009b80c16a865ca2180a4f74e4498154ac4727f0c4265c` |
| `ga4gh-drs-1.5.0/openapi/components/responses/404NotFoundAccess.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/responses/404NotFoundAccess.yaml | `be3bd46cbd46603bb776c15dd2dba3fa4a6628eabd5dc75e16ba8168ad41cd05` |
| `ga4gh-drs-1.5.0/openapi/components/responses/404NotFoundDrsObject.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/responses/404NotFoundDrsObject.yaml | `5c8ff26234b315464f57bf0fbc7f0adc3592f7460f6dfec59a91902957092e28` |
| `ga4gh-drs-1.5.0/openapi/components/responses/413RequestTooLarge.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/responses/413RequestTooLarge.yaml | `af899dddce515fd0a473e443586e9ff3a088afeb2ea124682e999c1a82dbc3da` |
| `ga4gh-drs-1.5.0/openapi/components/responses/500InternalServerError.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/responses/500InternalServerError.yaml | `b3a2e88ba55a5188c76ab90daa76df19c6ff242fe541a5b87bce1e64af1d9f66` |
| `ga4gh-drs-1.5.0/openapi/components/responses/AuthorizationsNotSupported.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/responses/AuthorizationsNotSupported.yaml | `b231d7e70082b818ca12c0f53bd5030f90061007f40bc2de5fea2c2ef56cf29f` |
| `ga4gh-drs-1.5.0/openapi/components/schemas/AccessMethod.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/schemas/AccessMethod.yaml | `1b89737df4876f464f57c92f7d1838c681fe2f73742b68331dbe9a38f6952e07` |
| `ga4gh-drs-1.5.0/openapi/components/schemas/AccessURL.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/schemas/AccessURL.yaml | `787f2168ba7fbd424eb7f95f08074658dfa5a871a3083b170cb0de18267b6447` |
| `ga4gh-drs-1.5.0/openapi/components/schemas/Authorizations.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/schemas/Authorizations.yaml | `db030896b2b826c444b36bf595c9a5bd3ac6e68f60294376756a8b7e734603e1` |
| `ga4gh-drs-1.5.0/openapi/components/schemas/BulkAccessURL.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/schemas/BulkAccessURL.yaml | `7583ab3006b8ae69e81f262b0ab75ebf73aff4a42dc0328e4e98e518073b5eec` |
| `ga4gh-drs-1.5.0/openapi/components/schemas/Checksum.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/schemas/Checksum.yaml | `5d5a87751dfe78288b64234d0fc20c21ddf1946f771bf61ef4bc724087a3e1e1` |
| `ga4gh-drs-1.5.0/openapi/components/schemas/ContentsObject.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/schemas/ContentsObject.yaml | `e15a3ed368ecd67578125e217fe28502c3e13c99e5b5dad6f5e57bbf98d5246f` |
| `ga4gh-drs-1.5.0/openapi/components/schemas/DrsObject.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/schemas/DrsObject.yaml | `352d80a06a43645ef801d17006f4ff962a6c499fcb6d336024597141ad2a415d` |
| `ga4gh-drs-1.5.0/openapi/components/schemas/DrsService.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/schemas/DrsService.yaml | `ead92d07ad61cb90becdde9ad2d7739da8bd86dc19d0b91293b59aae2d69e373` |
| `ga4gh-drs-1.5.0/openapi/components/schemas/Error.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/schemas/Error.yaml | `c0bb8594e25ceeba8d829c542577cb6f576b187df62783063fc7451e03da3e30` |
| `ga4gh-drs-1.5.0/openapi/components/schemas/summary.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/schemas/summary.yaml | `c764547fd57d0285fda3458a34ad3fb11a2b012ae4bfa195a6763631f6c125b2` |
| `ga4gh-drs-1.5.0/openapi/components/schemas/unresolved.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/components/schemas/unresolved.yaml | `2429d2376c0805bcb88f38abe9c15625587393703e143291eaae2b86c179861d` |
| `ga4gh-drs-1.5.0/openapi/data_repository_service.openapi.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/data_repository_service.openapi.yaml | `2abb9b11449ba24cd5d092011be340de61aa8b1a0fb9d28b0de3df2e17a2fc45` |
| `ga4gh-drs-1.5.0/openapi/paths/bulkobjects@access@{access_id}.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/paths/bulkobjects@access@{access_id}.yaml | `79e1a24111a756ced801edcbe5cbaa32f3ad85c97701be3da56cf81921b7c4f5` |
| `ga4gh-drs-1.5.0/openapi/paths/bulkobjects@{object_id}.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/paths/bulkobjects@{object_id}.yaml | `2d7add0274cd8841f8de3f3c0f1140af52bfd8f287e2e580f636086b56cae675` |
| `ga4gh-drs-1.5.0/openapi/paths/objects@{object_id}.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/paths/objects@{object_id}.yaml | `eb608cdd4bc5d6a83b358fb96c720233596064367b77a6f6d6f5cd2bf09ccf02` |
| `ga4gh-drs-1.5.0/openapi/paths/objects@{object_id}@access@{access_id}.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/paths/objects@{object_id}@access@{access_id}.yaml | `987d6a975805d62ffd2f766c2bf1ab6fb38c1c49a4c166aa16880cedce126fec` |
| `ga4gh-drs-1.5.0/openapi/paths/service-info.yaml` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/paths/service-info.yaml | `6f2e6db966c1f461a4696e32194e5b36b3fd99ba7f11ecd4cbde65acbb2ff904` |
| `ga4gh-drs-1.5.0/openapi/tags/Auth.md` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/tags/Auth.md | `adf5218bdc27a1cd75813b9d7c966d21ab7921687113181cf7457d0f8c042ddc` |
| `ga4gh-drs-1.5.0/openapi/tags/BackgroundNotesOnDRSURIs.md` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/tags/BackgroundNotesOnDRSURIs.md | `55b6ed95a8043bb4fae7e1ccc380667016ba4bbe540e1d9ec0613fb39449ac70` |
| `ga4gh-drs-1.5.0/openapi/tags/CompactIdentifierBasedURIs.md` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/tags/CompactIdentifierBasedURIs.md | `ef22fc160ede8a5d7701ae20fac4edbb821637d49986e8a77b60ec3cc10f0138` |
| `ga4gh-drs-1.5.0/openapi/tags/CompoundObjects.md` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/tags/CompoundObjects.md | `75d0c41cebc1c061ccc56414338e9aabcfbc9207559fa94d45b40593af80018d` |
| `ga4gh-drs-1.5.0/openapi/tags/DrsApiPrinciples.md` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/tags/DrsApiPrinciples.md | `bdaf85cf481c9c7dafa96a20b35029366feef069398739871000c69d4d8551e7` |
| `ga4gh-drs-1.5.0/openapi/tags/HostnameBasedURIs.md` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/tags/HostnameBasedURIs.md | `7737fdd20edbde5a55cc5f706474b3129cf5cc3c7720bda66a57dbee15107d29` |
| `ga4gh-drs-1.5.0/openapi/tags/Introduction.md` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/tags/Introduction.md | `93cf177300084886a8e558141291c096f542286651facffadb0eed3241a290f8` |
| `ga4gh-drs-1.5.0/openapi/tags/Motivation.md` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/tags/Motivation.md | `6dc966abae8c8129759cbe0585fd9357b53403aaac140dd0a6ba3434fa62378e` |
| `ga4gh-drs-1.5.0/openapi/tags/ServiceRegistry.md` | https://raw.githubusercontent.com/ga4gh/data-repository-service-schemas/drs-1.5.0/openapi/tags/ServiceRegistry.md | `3203a11f9bd1eec79056b7ec51fae6ffe9f06ffc63386662e4cf9626e3ac50f1` |

Retrieved: 2026-10-09

## GA4GH Task Execution Service (TES) 1.1, repo ga4gh/task-execution-schemas, tag v1.1 (commit 117cd927aa119469ee80cedbd8940c968b81c5d6), released 2022-11-15. Latest non-prerelease TES release as of retrieval.

License: Apache License 2.0 (ga4gh-tes-1.1/LICENSE).


| file | URL | sha256 |
|---|---|---|
| `ga4gh-tes-1.1/LICENSE` | https://raw.githubusercontent.com/ga4gh/task-execution-schemas/v1.1/LICENSE | `d680f254d680e2320f4b53e5266ecfab3311f91633dae92b7119d32323917e90` |
| `ga4gh-tes-1.1/README.md` | https://raw.githubusercontent.com/ga4gh/task-execution-schemas/v1.1/README.md | `05529497b1546e1f3cf2b0c8d8dd8c4bcbe74e7a32336f53db30cc8e088aa8eb` |
| `ga4gh-tes-1.1/openapi/task_execution_service.openapi.yaml` | https://raw.githubusercontent.com/ga4gh/task-execution-schemas/v1.1/openapi/task_execution_service.openapi.yaml | `d0bf4c2eff568f7be55ccf283833a4b5ca6fdf4f80e402d72bad7378907e12ea` |

Retrieved: 2026-10-09

## GA4GH Workflow Execution Service (WES) 1.1.0, repo ga4gh/workflow-execution-service-schemas, tag 1.1.0 (commit 226f43b1fec97ad3778897a27a9651ccfa631d77), released 2023-09-14. Latest non-prerelease WES release as of retrieval.

License: Apache License 2.0 (ga4gh-wes-1.1.0/LICENSE).


| file | URL | sha256 |
|---|---|---|
| `ga4gh-wes-1.1.0/LICENSE` | https://raw.githubusercontent.com/ga4gh/workflow-execution-service-schemas/1.1.0/LICENSE | `2f2eba13a14f9b5f0a1547a135f7012a11f6828762f14abced299efe870b7c09` |
| `ga4gh-wes-1.1.0/README.md` | https://raw.githubusercontent.com/ga4gh/workflow-execution-service-schemas/1.1.0/README.md | `ccc8c10a2e7a434533266de0588a588df16c1094d4d132992cd4f524faf7f563` |
| `ga4gh-wes-1.1.0/openapi/workflow_execution_service.openapi.yaml` | https://raw.githubusercontent.com/ga4gh/workflow-execution-service-schemas/1.1.0/openapi/workflow_execution_service.openapi.yaml | `9cdbcdf5871a05dec05b90e2dc10e8d8cb60a84efda6e17d3531a21c1129e467` |

Retrieved: 2026-10-09

## Reference code: golang.org/x/net/webdav (Go), repo golang/net, tag v0.61.0 (commit c1d31df183e51b1075a2fd670d6f6f4efb871773). Only the handler, file-op, lock and If-header files were vendored; tests, prop.go and xml.go were left out.

License: BSD-3-Clause (code/golang-x-net-webdav-v0.61.0/LICENSE, Copyright 2009 The Go Authors).


| file | URL | sha256 |
|---|---|---|
| `code/golang-x-net-webdav-v0.61.0/LICENSE` | https://raw.githubusercontent.com/golang/net/v0.61.0/LICENSE | `911f8f5782931320f5b8d1160a76365b83aea6447ee6c04fa6d5591467db9dad` |
| `code/golang-x-net-webdav-v0.61.0/file.go` | https://raw.githubusercontent.com/golang/net/v0.61.0/webdav/file.go | `12599d679571bf96b469426e71c7e6615c198a27c94501a9fa0425518b00fa02` |
| `code/golang-x-net-webdav-v0.61.0/if.go` | https://raw.githubusercontent.com/golang/net/v0.61.0/webdav/if.go | `873318386c937f383f1713e16911f091ba4635b20486e2390553e8da8e571021` |
| `code/golang-x-net-webdav-v0.61.0/lock.go` | https://raw.githubusercontent.com/golang/net/v0.61.0/webdav/lock.go | `a29231c7bb38de6f0d527ac84c6b2e3bfec449d0b6afef07d29f01601793f3c4` |
| `code/golang-x-net-webdav-v0.61.0/webdav.go` | https://raw.githubusercontent.com/golang/net/v0.61.0/webdav/webdav.go | `e8a1cff63e0a00dfe1c8a3c62e43e24a896e35baced173dfc8d60a56e0d63143` |

Retrieved: 2026-10-09

## Reference code: Funnel, a GA4GH TES server (Go), repo calypr/funnel (moved from ohsu-comp-bio/funnel), tag v0.11.14 (commit 2e54ad745dff41c1acff47f812d6f32497f37b3e), released 2026-06-11.

License: MIT (code/funnel-v0.11.14/License.txt, Copyright (c) 2017 Oregon Health and Science University Computational Biology).

Only the state-transition, terminal-state, cancel and status-mapping files were vendored, keeping their repo-relative paths.


| file | URL | sha256 |
|---|---|---|
| `code/funnel-v0.11.14/License.txt` | https://raw.githubusercontent.com/calypr/funnel/v0.11.14/License.txt | `62148f4e448a72f5a58dbf1897c63280070775ad7a145f05f823aafc65737c9a` |
| `code/funnel-v0.11.14/database/boltdb/events.go` | https://raw.githubusercontent.com/calypr/funnel/v0.11.14/database/boltdb/events.go | `e9b014a89d45a7243dcdff568012c9eda40ead7ebc55ab45fcc53915a1031879` |
| `code/funnel-v0.11.14/server/tes.go` | https://raw.githubusercontent.com/calypr/funnel/v0.11.14/server/tes.go | `9d240691ebd3461d5064022b947a817dcac9f9f75867bc767476b903bb57c9c6` |
| `code/funnel-v0.11.14/tes/states.go` | https://raw.githubusercontent.com/calypr/funnel/v0.11.14/tes/states.go | `d1b418b470819835bd467d30b1f288c66dc38fc8f45bbe0b3ae43f5e2c9ec3ea` |
| `code/funnel-v0.11.14/tes/tes.proto` | https://raw.githubusercontent.com/calypr/funnel/v0.11.14/tes/tes.proto | `5376ad4080662000714e4d2a5e57a1b4462f752d3b3e209e738a94cd35829125` |
| `code/funnel-v0.11.14/tes/utils.go` | https://raw.githubusercontent.com/calypr/funnel/v0.11.14/tes/utils.go | `c6174837f8584d4ee799afad2167389feaf0abd3a00b5bd5f0a556b13c13a763` |
| `code/funnel-v0.11.14/util/server/server.go` | https://raw.githubusercontent.com/calypr/funnel/v0.11.14/util/server/server.go | `d8818344cb5be6cfad194024d9ae370f63a6b2dd7a9098403d784bc6d2b81fd2` |

Retrieved: 2026-10-09
