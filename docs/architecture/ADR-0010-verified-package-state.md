# ADR-0010: Verified package state

**Status:** [PROPOSED]. [PENDING] owner approval before any implementation.
**Date:** 2026-10-09
**Relates to:** ADR-0001, ADR-0006, ADR-0007, ADR-0008, `contracts/credential-package.md`, K3/K4 in `docs/handoff/pending-decisions-register.md`.

## Context

ADR-0007 requires every package file, including the catalog, to be covered by a signed manifest and verified before use. ADR-0008 records a remaining trust-boundary gap: the runtime does not yet keep one authenticated package state that downstream consumers can read.

Three current call paths rely on manifest-derived data that is supplied again by a caller or reread from disk:

1. `runtime/Sisqual.Runtime.EngineHost.psm1` receives `ManifestEntries` from its caller. It uses those entries to validate the catalog path, engine file, launcher and package secret contract before launching an engine.
2. `runtime/Sisqual.Runtime.Catalog.Core.ps1` receives expected catalog properties from its caller. `Open-SisqualRuntimeCatalog` takes the expected SHA-256, size, server code, schema version and origin, while provider initialization receives a `VerifiedFiles` list. The catalog code validates those values, but it does not authenticate the source that supplied them.
3. The `DEPLOYMENT_PREFLIGHT` port in PR #67 runs in a separate engine process and rereads `package-manifest.json` from disk. It then uses that copy for the hashes of `runtime/Sisqual.Runtime.Catalog.psm1`, `runtime/Sisqual.Runtime.Catalog.Core.ps1` and the materialized SQLite provider files. If the manifest and a package file are replaced together after startup, the engine can validate the changed file against the changed manifest.

The owner has already decided K3 and K4: the manifest carries a monotonic counter checked against the last accepted run on the machine, the portable folder is protected, and package members are reverified before load. The exact verified-state bootstrap that joins these decisions is not yet approved.

## Threat model

[PROPOSED] This ADR addresses package substitution and trust rebinding after startup, not compromise of the operating system administrator.

The relevant attacker or fault can:

- replace a package file after the initial startup verification;
- replace `package-manifest.json` together with the changed file, preserving self-consistency but not the original authenticated state;
- cause an in-process adapter to pass manifest entries, expected catalog hashes, sizes or metadata that were not the values authenticated at bootstrap;
- attempt rollback to an older package whose signature is valid but whose K3 counter is lower than the last accepted counter on the machine.

The design does **not** claim to protect against an administrator who controls the machine, can replace the running process, inspect its memory, replace pinned trust material, or alter the mechanism that stores the last accepted K3 counter. Protecting against that actor is outside this application's trust boundary.

## Proposed decision

### 1. Bootstrap owns the verified package state

[PROPOSED] The bootstrap verifies the package exactly once for a process lifetime before runtime consumers are enabled. Verification includes:

- the manifest signature against the already approved pinned issuer trust;
- package identity and canonical package root;
- every manifest entry's normalized path, SHA-256 and size;
- catalog entries and their expected metadata needed by the runtime catalog opener;
- the K3 monotonic counter against the last accepted counter on the machine;
- any manifest contract/version fields required to interpret those entries.

Only after all checks succeed may the bootstrap construct the verified package state.

[PENDING] K3 requires persistent state outside the replaceable package, but the exact storage path, ACL, atomic update rule and recovery procedure for the last accepted counter are not decided by this ADR. Those details change the package integrity/trust bootstrap and require owner approval.

### 2. The state is immutable after creation

[PROPOSED] The verified package state is an in-process read-only object owned by the bootstrap. It is set once. There is no public setter, refresh or caller-supplied replacement. A process that needs a different package must restart and repeat bootstrap verification.

The state should contain only authenticated metadata, for example:

- canonical package root;
- manifest contract version and manifest digest;
- verified K3 counter;
- exact file map keyed by normalized manifest path, with SHA-256 and size;
- verified catalog metadata required by `Open-SisqualRuntimeCatalog`;
- signature/trust result needed for diagnostics, without private key material.

Consumers receive read access to this state through a runtime-owned API. They do not receive raw, caller-selected manifest entries.

### 3. Host and catalog consume state, not caller trust assertions

[PROPOSED] `Sisqual.Runtime.EngineHost` stops accepting `ManifestEntries` as a trust input. It resolves engine, launcher, catalog and package-contract hashes from the bootstrap-owned verified package state and still rehashes each file immediately before use, as ADR-0008 requires.

[PROPOSED] `Sisqual.Runtime.Catalog.Core` stops treating caller-provided expected hash, size, server code, schema version and provider `VerifiedFiles` as authority. The runtime catalog resolves the authenticated expected values from the same verified package state and compares the on-disk catalog/provider files immediately before open/load.

The caller may still choose which already-verified catalog/action to operate on where the public API needs selection, but it cannot supply the expected integrity values that make that selection trusted.

### 4. Engine process boundary

The engine host and catalog runtime are in-process consumers. An engine is not: ADR-0008 deliberately launches each engine in another process. The child cannot directly read the parent's verified package state.

[PROPOSED] The host therefore derives a minimal, engine-specific subset of authenticated package expectations from the verified state and includes that subset in the engine request. For `DEPLOYMENT_PREFLIGHT`, that subset would include the exact expected path/hash/size records needed to verify the runtime catalog modules and the SQLite provider files that the engine loads.

The engine must use those host-supplied authenticated expectations and must not reread `package-manifest.json` as its source of trust.

[PENDING] Adding verified package expectations to the engine request changes the approved ADR-0008 engine input contract. `AGENTS.md` requires owner approval for engine input/result contract changes. The exact request member name, schema and size limit are therefore intentionally not decided here.

### 5. Reverification still happens at use time

The verified state does not mean "verify once and trust the disk forever". K4 and ADR-0008 still apply: immediately before a runtime module, engine, launcher, provider or catalog is used, the consumer rehashes the current file and compares it with the immutable authenticated expectation in verified state.

This closes the difference between:

- authenticating what the package was approved to contain; and
- checking that the file about to be loaded is still that approved file.

## Alternatives considered

### Each consumer verifies the manifest signature itself

Every host, catalog opener and engine could reread the manifest, verify its signature and apply K3 independently.

Cost: duplicated crypto/trust-bootstrap code, duplicated persistent-counter coordination, more opportunities for inconsistent validation, and each child process needs access to the pinned trust material. It also makes "last accepted counter" ownership harder to define. Not recommended.

### Make the package folder read-only with ACLs

A protected install location is already part of K4 and remains useful defense in depth.

Cost/limit: ACLs reduce accidental or unprivileged modification but do not authenticate package contents and do not solve rollback of an older valid package. They also do not replace immediate hash verification. Not sufficient alone.

### Keep the current documented trust limit

ADR-0008 can continue to document that the caller supplies manifest-derived trust values and PR #67 can keep rereading the manifest in its child process.

Cost: the same manifest can be replaced together with a changed file, and independent callers can bind different expected values. This preserves the known P1 in PR #67 and leaves K3/K4 only partially connected. Acceptable only if the owner explicitly chooses to retain the limit.

## Effect by consumer

| Consumer | Current state | Proposed effect |
|---|---|---|
| `RuntimeBootstrap.ps1` | establishes runtime/bootstrap conditions but does not expose immutable authenticated package state | verify signature and K3, create verified state once, expose read-only access |
| `Sisqual.Runtime.EngineHost.psm1` | receives `ManifestEntries` from caller | remove caller authority for manifest entries; read expected hashes/contracts from verified state and rehash before launch |
| `Sisqual.Runtime.Catalog.Core.ps1` | caller supplies expected catalog SHA-256, size, server/schema/origin and provider verified-file entries | derive authenticated expectations from verified state; caller cannot redefine them |
| `DEPLOYMENT_PREFLIGHT` child process | rereads `package-manifest.json` for runtime-module/provider hashes | receive only the authenticated expectations it needs in the engine request; do not trust a disk reread of the manifest |
| adapters/orchestrators | may forward manifest-derived values | select operations/catalogs only; do not act as a package-integrity authority |
| seal/verifier tooling | produces/verifies signed package material | K3 manifest member and release verification remain tooling concerns; no runtime consumer invents a counter |

## Consequences

- One authenticated state defines what every in-process runtime consumer means by "the verified package".
- Replacing a file and manifest together after bootstrap no longer changes the expected hash used by the running process.
- K3 rollback protection becomes part of the same trust bootstrap instead of an independent check with unclear ownership.
- Engines that need package hashes require a host-to-engine contract extension because of the process boundary.
- Process restart is required to accept a different package or higher manifest counter.

## Approval required

[PENDING] No implementation follows from this ADR until the owner approves it.

`AGENTS.md` requires human approval before changing:

- cryptographic algorithms, key ownership or trust bootstrap;
- the package integrity model (manifest, signing, seal tool);
- an approved engine input/result contract.

The owner therefore needs to approve at least:

1. bootstrap ownership of one immutable verified package state;
2. K3 persistent-counter storage/update semantics;
3. removal of caller-supplied integrity expectations from host/catalog APIs;
4. the engine-request extension used to carry authenticated hashes across the process boundary.

Until those decisions are made, all of the design above remains `[PROPOSED]`/`[PENDING]` and the known ADR-0008 trust-boundary limitation remains in force.
