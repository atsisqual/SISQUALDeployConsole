# ADR-0010: Verified package state

**Status:** [PROPOSED]. [PENDING] owner approval before any implementation.
**Date:** 2026-10-09
**Relates to:** ADR-0001, ADR-0006, ADR-0007, ADR-0008, `contracts/credential-package.md`, K3/K4 in `docs/handoff/pending-decisions-register.md`.

## Context

ADR-0007 requires every package file, including the catalog, to be covered by a signed manifest and verified before use. ADR-0008 records a remaining trust-boundary gap: the runtime does not yet keep one authenticated package state that downstream consumers can read.

Three current call paths rely on manifest-derived data that is supplied again by a caller or reread from disk:

1. `runtime/Sisqual.Runtime.EngineHost.psm1` receives `ManifestEntries` from its caller. It uses those entries to validate the catalog path, engine file, launcher and package secret contract before launching an engine.
2. `runtime/Sisqual.Runtime.Catalog.Core.ps1` receives expected catalog properties from its caller. `Open-SisqualRuntimeCatalog` takes the expected SHA-256, size, server code, schema version, origin and optional origin reference, while provider initialization receives a `VerifiedFiles` list. The catalog code validates those values, but it does not authenticate the source that supplied them.
3. The `DEPLOYMENT_PREFLIGHT` port in PR #67 runs in a separate engine process and rereads `package-manifest.json` from disk. It then uses that copy for the hashes of `runtime/Sisqual.Runtime.Catalog.psm1`, `runtime/Sisqual.Runtime.Catalog.Core.ps1` and the materialized SQLite provider files. If the manifest and a package file are replaced together after startup, the engine can validate the changed file against the changed manifest.

The owner has already decided K3 and K4: the manifest carries a monotonic counter checked against the last accepted run on the machine, the portable folder is protected, and package members are reverified before load. The exact verified-state bootstrap that joins these decisions is not yet approved.

## Threat model

[PROPOSED] This ADR addresses package substitution and trust rebinding after startup, not compromise of the operating system administrator.

The relevant attacker or fault can:

- replace a package file after the initial startup verification;
- replace `package-manifest.json` together with the changed file, preserving self-consistency but not the original authenticated state;
- cause an in-process adapter to pass manifest entries, expected catalog hashes, sizes or metadata that were not the values authenticated at bootstrap;
- attempt rollback to an older package whose signature is valid but whose K3 counter is lower than the last accepted counter on the machine;
- attempt to reuse the same valid counter with a different signed manifest.

The design does **not** claim to protect against an administrator who controls the machine, can replace the running process, inspect its memory, replace pinned trust material, or alter the mechanism that stores the last accepted K3 record. Protecting against that actor is outside this application's trust boundary.

## Proposed decision

### 1. Bootstrap owns the verified package state

[PROPOSED] The bootstrap verifies the package exactly once for a process lifetime before runtime consumers are enabled. Verification includes:

- the manifest signature against the already approved pinned issuer trust;
- package identity and canonical package root;
- every manifest entry's normalized path, SHA-256 and size;
- catalog entries and their expected metadata needed by the runtime catalog opener, including `ExpectedOriginReference` when the signed manifest supplies it;
- the K3 monotonic counter against the last accepted package identity on the machine;
- any manifest contract/version fields required to interpret those entries.

Only after all checks succeed may the bootstrap construct the verified package state.

#### K3 persisted identity and restart equality

[PROPOSED] The persisted K3 identity is the pair `(counter, manifestDigest)`, where `manifestDigest` is the SHA-256 of the exact authenticated manifest bytes covered by the accepted signature. The counter namespace is one sequence per machine for this signed SISQUAL Deploy Console package trust domain; it is not per catalog, engine, file or caller. A future need for multiple independent package trust domains on one machine would require another owner decision before implementation.

Given persisted `(storedCounter, storedManifestDigest)` and an authenticated candidate `(counter, manifestDigest)`:

- `counter < storedCounter`: reject as rollback;
- `counter = storedCounter` and `manifestDigest = storedManifestDigest`: accept as an ordinary restart of the same authenticated package;
- `counter = storedCounter` and `manifestDigest <> storedManifestDigest`: reject same-counter manifest substitution;
- `counter > storedCounter`: continue full package verification and, only after every bootstrap verification succeeds, atomically replace the persisted pair with the new `(counter, manifestDigest)` before publishing verified state or enabling any runtime consumer.

A failed atomic persistence must fail startup; the process must not expose the newly verified state if the durable identity was not advanced. Re-accepting the same `(counter, digest)` does not rewrite the record. The persistence operation must be crash-safe as one atomic record replacement, so readers never observe a new counter with an old digest or the reverse.

#### Serialized compare-and-advance

[PROPOSED] The comparison and durable advance above are one serialized machine-wide operation. The proposed durable files live outside the replaceable portable folder under `C:\SISQUALWFM\WFM.Files\SISQUALDeployManagement\`: `package-state.json` holds the accepted `(counter, manifestDigest)` record and `package-state.lock` is the inter-process serialization point. The directory ACL is part of the trust bootstrap and remains subject to owner approval.

The bootstrap may perform signature, manifest and file verification before entering the critical section, but it **must not** accept or publish the candidate from a counter value read before the lock. To commit an authenticated candidate it must:

1. acquire an exclusive inter-process lock on `package-state.lock` (`FileShare.None` or an equivalent Windows exclusive-file primitive);
2. while holding that lock, reread `package-state.json` from disk and perform the `<`, equal-same-digest, equal-different-digest or `>` comparison against that fresh value;
3. for `counter > storedCounter`, write the complete new JSON record to a same-directory temporary file, flush and close it, then atomically replace `package-state.json`; the counter and digest are never updated as separate writes;
4. only after the atomic replace succeeds, publish the in-process verified package state and release the lock;
5. for equal-same-digest, accept the ordinary restart without rewriting the state record; for rollback or equal-different-digest, fail startup while still treating the reread value as authoritative.

This serialized reread is what prevents two processes that start concurrently with counter `N+1` from both deciding against an older `N` snapshot. The second process waits for the exclusive lock. After it acquires the lock it must reread the record advanced by the first process: the exact same `(N+1, digest)` is then the allowed restart case; a different digest at `N+1` is rejected as a same-counter conflict; a lower counter is rejected as rollback.

[PROPOSED] Lock acquisition is bounded. If the second process cannot obtain the lock before the bootstrap deadline, it fails closed with `PACKAGE_STATE_LOCK_TIMEOUT`; it does not use a stale pre-lock comparison and does not publish verified state. [PENDING] The exact lock timeout, ACL, recovery of an abandoned/stale lock, JSON schema/version and Windows atomic-replace/flush primitive require owner approval with the trust-bootstrap implementation.

[PENDING] The storage path, ACL, concrete atomic-replace mechanism, durability/flush details and recovery procedure remain owner decisions because they change the package integrity/trust bootstrap. The comparison/equality and serialized-update semantics above are the proposed behavior to be approved with that storage design.

### 2. The state is immutable after creation

[PROPOSED] The verified package state is an in-process read-only object owned by the bootstrap. It is set once. There is no public setter, refresh or caller-supplied replacement. A process that needs a different package must restart and repeat bootstrap verification.

The state should contain only authenticated metadata, for example:

- canonical package root;
- manifest contract version and manifest digest;
- verified K3 counter;
- exact file map keyed by normalized manifest path, with SHA-256 and size;
- verified catalog metadata required by `Open-SisqualRuntimeCatalog`: path, SHA-256, size, expected server code, expected schema version, expected origin and optional `ExpectedOriginReference`;
- signature/trust result needed for diagnostics, without private key material.

Consumers receive read access to this state through a runtime-owned API. They do not receive raw, caller-selected manifest entries.

### 3. Host and catalog consume state, not caller trust assertions

[PROPOSED] `Sisqual.Runtime.EngineHost` stops accepting `ManifestEntries` as a trust input. It resolves engine, launcher, catalog and package-contract hashes from the bootstrap-owned verified package state and still rehashes each file immediately before use, as ADR-0008 requires.

[PROPOSED] `Sisqual.Runtime.Catalog.Core` stops treating caller-provided expected hash, size, server code, schema version, origin, optional `ExpectedOriginReference` and provider `VerifiedFiles` as authority. The runtime catalog resolves the authenticated expected values from the same verified package state and compares the on-disk catalog/provider files immediately before open/load.

`ExpectedOriginReference` must be part of the bootstrap-owned catalog metadata when it is present in the signed manifest. Today `Open-SisqualRuntimeCatalog` skips the `catalog_meta.source_reference` comparison when `ExpectedOriginReference` is empty (`runtime/Sisqual.Runtime.Catalog.psm1`, current main lines 174-176). The proposed state therefore removes the caller's ability to turn that authenticated comparison off by passing an empty value when the manifest supplied one.

The caller may still choose which already-verified catalog/action to operate on where the public API needs selection, but it cannot supply the expected integrity values that make that selection trusted.

### 4. Engine process boundary

The engine host and catalog runtime are in-process consumers. An engine is not: ADR-0008 deliberately launches each engine in another process. The child cannot directly read the parent's verified package state.

[PROPOSED] The host therefore derives an immutable, engine-specific subset of authenticated package expectations from verified state and serializes it into the child request. For `DEPLOYMENT_PREFLIGHT`, the concrete proposed request subset is:

- `manifestDigest` and `manifestCounter`, for correlation with the parent-accepted package identity;
- `catalog.path`, `catalog.sha256` and `catalog.size`;
- `catalog.expectedServerCode`;
- `catalog.expectedSchemaVersion`;
- `catalog.expectedOrigin`;
- `catalog.expectedOriginReference` when supplied by the signed manifest;
- `files[]` entries containing normalized package-relative `path`, `sha256` and `size` for `runtime/Sisqual.Runtime.Catalog.psm1`, `runtime/Sisqual.Runtime.Catalog.Core.ps1` and every SQLite provider file the child loads.

The catalog path and file paths remain selections within the already authenticated package root; the integrity and catalog metadata in this subset are derived only from the parent's immutable verified state. The child rehashes those files against the supplied expectations immediately before use and opens the catalog with the supplied expected hash, size and metadata. It must not reread `package-manifest.json` as its source of trust.

[PENDING] This concrete subset changes the approved ADR-0008 engine input contract. It requires owner approval before implementation, including the request member name, exact JSON shape, compatibility/versioning and size limit. Until that approval, this is a proposed cross-process design, not an authorized contract change.

### 5. Reverification still happens at use time

The verified state does not mean "verify once and trust the disk forever". K4 and ADR-0008 still apply: immediately before a runtime module, engine, launcher, provider or catalog is used, the consumer rehashes the current file and compares it with the immutable authenticated expectation in verified state.

This closes the difference between:

- authenticating what the package was approved to contain; and
- checking that the file about to be loaded is still that approved file.

## Alternatives considered

### Each consumer verifies the manifest signature itself

Every host, catalog opener and engine could reread the manifest, verify its signature and apply K3 independently.

Cost: duplicated crypto/trust-bootstrap code, duplicated persistent-counter coordination, more opportunities for inconsistent validation, and each child process needs access to the pinned trust material. It also makes the accepted `(counter, manifestDigest)` ownership harder to define. Not recommended.

### Make the package folder read-only with ACLs

A protected install location is already part of K4 and remains useful defense in depth.

Cost/limit: ACLs reduce accidental or unprivileged modification but do not authenticate package contents and do not solve rollback of an older valid package. They also do not replace immediate hash verification. Not sufficient alone.

### Keep the current documented trust limit

ADR-0008 can continue to document that the caller supplies manifest-derived trust values and PR #67 can keep rereading the manifest in its child process.

Cost: the same manifest can be replaced together with a changed file, independent callers can bind different expected values, and an empty `ExpectedOriginReference` can suppress the origin-reference comparison. This preserves the known P1 in PR #67 and leaves K3/K4 only partially connected. Acceptable only if the owner explicitly chooses to retain the limit.

## Effect by consumer

| Consumer | Current state | Proposed effect |
|---|---|---|
| `RuntimeBootstrap.ps1` | establishes runtime/bootstrap conditions but does not expose immutable authenticated package state | verify signature and K3; serialize the fresh compare-and-advance under the durable state lock; enforce `(counter, manifestDigest)` restart semantics; atomically advance the durable pair before publishing new verified state |
| `Sisqual.Runtime.EngineHost.psm1` | receives `ManifestEntries` from caller | remove caller authority for manifest entries; read expected hashes/contracts from verified state and rehash before launch |
| `Sisqual.Runtime.Catalog.Core.ps1` / `Sisqual.Runtime.Catalog.psm1` | caller supplies expected catalog SHA-256, size, server/schema/origin, optional origin reference and provider verified-file entries | derive authenticated expectations from verified state; caller cannot redefine them or suppress a signed origin-reference expectation |
| `DEPLOYMENT_PREFLIGHT` child process | rereads `package-manifest.json` for runtime-module/provider hashes and opens the catalog in a separate process | receive the concrete authenticated catalog metadata plus module/provider path/hash/size subset in the engine request; rehash locally; do not trust a disk reread of the manifest |
| adapters/orchestrators | may forward manifest-derived values | select operations/catalogs only; do not act as a package-integrity authority |
| seal/verifier tooling | produces/verifies signed package material | K3 manifest member and release verification remain tooling concerns; no runtime consumer invents a counter |

## Consequences

- One authenticated state defines what every in-process runtime consumer means by "the verified package".
- Replacing a file and manifest together after bootstrap no longer changes the expected hash used by the running process.
- Restarting the exact same accepted package is possible without weakening rollback protection; reusing its counter with a different manifest is rejected.
- Concurrent bootstrap processes cannot both accept a higher counter from the same stale durable snapshot: compare-and-advance is serialized and the second process rereads under the exclusive lock.
- K3 rollback protection becomes part of the same trust bootstrap instead of an independent check with unclear ownership.
- Engines that need package/catalog expectations require a host-to-engine contract extension because of the process boundary.
- Process restart is required to accept a different package or higher manifest counter.

## Approval required

[PENDING] No implementation follows from this ADR until the owner approves it.

`AGENTS.md` requires human approval before changing:

- cryptographic algorithms, key ownership or trust bootstrap;
- the package integrity model (manifest, signing, seal tool);
- an approved engine input/result contract.

The owner therefore needs to approve at least:

1. bootstrap ownership of one immutable verified package state;
2. the proposed K3 `(counter, manifestDigest)` identity, equality/restart behavior, machine/package-trust-domain scope and atomic update point;
3. the proposed serialized K3 compare-and-advance mechanism, including the durable state/lock location, exclusive inter-process lock, second-process wait/fail behavior and `PACKAGE_STATE_LOCK_TIMEOUT`;
4. the K3 persistent storage/ACL/crash-recovery/atomic-replace mechanism and exact lock timeout;
5. removal of caller-supplied integrity expectations, including `ExpectedOriginReference`, from host/catalog APIs;
6. the proposed engine-request extension that carries catalog hash, size, signed catalog metadata and module/provider expectations across the process boundary.

Until those decisions are made, all of the design above remains `[PROPOSED]`/`[PENDING]` and the known ADR-0008 trust-boundary limitation remains in force.
