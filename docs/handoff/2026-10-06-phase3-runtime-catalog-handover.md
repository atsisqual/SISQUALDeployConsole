# Handover - Phase 3 runtime catalog factory

**Date:** 2026-10-06
**PR:** #54 `feat(phase3): add read-only runtime catalog factory`
**Branch:** `feat/phase3-runtime-catalog`
**Status:** [CONFIRMED] functional runtime implementation validated on Windows Server 2022/2025 at run #20. Current head contains test/evidence clarification after that functional commit and still requires execution. No merge requested.

## 1. What this PR does

This PR is the first product implementation of the reusable read-only SQLite catalog factory. It is independent of the open runtime-bootstrap work and does not implement manifest signature verification, credentials, Pode, UI or engines.

Product module: `runtime/Sisqual.Runtime.Catalog.psm1`.

It loads the accepted managed provider from the portable package and opens only an existing per-machine catalog in read-only/private-cache/non-pooled mode, with `PRAGMA query_only=ON`, integrity/metadata validation, sealed-catalog sidecar controls and handle-stable package-path guards.

## 2. Dependency decision

[CONFIRMED] Owner approval is recorded in `docs/phase3/sqlite-runtime-adoption.md`.

Approved roles:

- `Microsoft.Data.Sqlite` 10.0.12;
- provider native SQLite 3.53.3;
- separate CLI/tooling SQLite 3.53.4.

Phase 1B evidence is run `37392036026`. No provider binaries are committed by #54; CI materializes the exact locked provider payload only for validation. Release packaging must vendor that accepted payload.

## 3. Accepted functional evidence

Workflow: `phase3-runtime-catalog`
Workflow id: `375949981`
Run: `37440720047`
Run number: `20`
Exact tested functional commit: `3fa27ffaf5a92001bb8cd14488a54e9f7a49b034`
Conclusion: SUCCESS

Windows Server 2022:
- job `112193530442`;
- artifact `11401450858`;
- digest `sha256:e76db9433ce47ae98c9a59c1f37694016697d7a455d312e5b99778c99d85b204`;
- 34/34 main checks PASS;
- 6/6 sidecar checks PASS.

Windows Server 2025:
- job `112193530003`;
- artifact `11400898174`;
- digest `sha256:e922d4ca2afebf545637bfe68afa900f83550c8738e4a929a768399bceaccc7b`;
- 34/34 main checks PASS;
- 6/6 sidecar checks PASS.

CI on the same functional commit:
- run `37440720073`, CI #190: SUCCESS.

Repository `tools-tests` on the same functional commit:
- run `37440720136`, run #90: SUCCESS.

The downloaded reports from both artifacts are committed under:
`docs/phase3/evidence/runtime-catalog-37440720047/`.

The GitHub artifacts expire on 2027-01-04; the committed JSON reports preserve the accepted evidence in-repository.

## 4. Current head after accepted functional evidence

Current PR head at this handover update is `ef85a68a76ab91d0c5e3b37768980bc6266936f7`.

Runtime code has not changed since `3fa27ffaf5a92001bb8cd14488a54e9f7a49b034`. The later change narrows the late-sidecar test/evidence claim so the suite no longer treats the public `Immutable` flag as observational proof that an already-open connection ignores a valid late WAL.

[CONFIRMED] Codex review of `ef85a68...` completed with no new finding.

[PENDING] The current head itself has not executed because the latest attempts received no GitHub runner and executed zero steps. Do not promote the current head to executed evidence until a Windows 2022/2025 run actually executes.

## 5. Security hardening included in accepted functional run #20

The factory:

- requires the original `PackageRoot` argument to be absolute before normalization;
- rejects UNC/device paths and roots whose Windows `DriveType` is not `Fixed`, including mapped network drives;
- uses conservative case-sensitive package containment;
- opens and validates package path components and provider/catalog files through retained Win32 no-reparse guards;
- denies write sharing while verified provider/catalog bytes are trusted;
- rebinds provider/catalog size and SHA-256 after guards are acquired;
- keeps provider guards for process lifetime and the catalog guard until session disposal;
- hides the raw SQLite connection behind an opaque public session;
- rejects pre-existing `-wal`, `-shm` and `-journal` sidecars for the sealed catalog;
- opens the catalog through an `immutable=1` SQLite file URI with `Mode=ReadOnly`, `Cache=Private`, `Pooling=false`;
- rechecks sidecar absence immediately after open;
- verifies `query_only`, exact native SQLite 3.53.3 and `integrity_check`;
- requires exactly one `catalog_meta` row and validates expected metadata case-sensitively where required;
- uses parameterized SQL internally;
- verifies twenty simultaneous read-only sessions and byte identity.

The factory does NOT authenticate package content by itself. Signed-manifest verification remains a bootstrap/package responsibility.

## 6. Evidence history

[CONFIRMED] Run `37399118262` (#1) failed before product behavior because of a PowerShell interpolation parser error. Not provider-failure evidence.

[CONFIRMED] Run `37401225241` (#3) reached 25/25 PASS then failed only during disposable cleanup because process-loaded `e_sqlite3.dll` remained locked.

[CONFIRMED] Run `37402464400` (#4) was the first complete 25/25 PASS and was later superseded.

[CONFIRMED] Run `37403483739` (#7) passed hardened runtime behavior before explicit path-guard tests were added.

[CONFIRMED] Run `37403821077` (#9) passed all then-current 28 functional gates; its CI failure was caused by a temporary documentation encoding change.

[CONFIRMED] Run `37404050977` (#10), commit `c9905f6...`, passed 28/28 and was previously called final evidence. It is **superseded** by run `37440720047` (#20), which covers the later guarded-byte rebinding, opaque session and sealed-sidecar implementation with 34/34 main + 6/6 sidecar checks on both Windows versions.

## 7. Remaining work

[PENDING] Execute current head `ef85a68...` on Windows 2022/2025 when GitHub runners are available.

[PENDING] Integrate this factory after the signed-manifest verification gate in the runtime bootstrap.

[PENDING] Vendor the exact accepted provider payload in release packaging and list/hash every provider file in the signed manifest.

[PENDING] Add semantic manifest/package records for both SQLite roles in addition to per-file hashes.

[V] Open a converted SISQUAL catalog on a target/sandbox Windows machine after package integration.

## 8. What not to do

- Do not redo the Phase 1B provider spike.
- Do not collapse SQLite 3.53.3 and 3.53.4 into one version.
- Do not add `dotnet`/NuGet as an operator runtime dependency.
- Do not weaken fixed-local-root, byte-rebinding, sidecar or handle-guard requirements.
- Do not expose raw SQLite connections or browser-supplied SQL.
- Do not merge #54 without owner delegation.
