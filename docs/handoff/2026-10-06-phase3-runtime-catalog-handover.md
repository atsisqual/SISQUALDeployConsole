# Handover - Phase 3 runtime catalog factory

**Date:** 2026-10-06
**PR:** #54 `feat(phase3): add read-only runtime catalog factory`
**Branch:** `feat/phase3-runtime-catalog`
**Status:** [CONFIRMED] technical implementation validated on Windows Server 2022/2025. No merge requested.

## 1. What this PR does

This PR is the first product implementation of the reusable read-only SQLite catalog factory. It is independent of the open runtime-bootstrap work and does not implement manifest signature verification, credentials, Pode, UI or engines.

Product module: `runtime/Sisqual.Runtime.Catalog.psm1`.

It loads the accepted managed provider from the portable package and opens only an existing per-machine catalog in read-only/private-cache/non-pooled mode, with `PRAGMA query_only=ON`, integrity/metadata validation and handle-stable package-path guards.

## 2. Dependency decision

[CONFIRMED] Owner approval is recorded in `docs/phase3/sqlite-runtime-adoption.md`.

Approved roles:

- `Microsoft.Data.Sqlite` 10.0.12;
- provider native SQLite 3.53.3;
- separate CLI/tooling SQLite 3.53.4.

Phase 1B evidence is run `37392036026`. No provider binaries are committed by #54; CI materializes the exact locked provider payload only for validation. Release packaging must vendor that accepted payload.

## 3. Accepted final evidence

Workflow: `phase3-runtime-catalog`
Workflow id: `375949981`
Run: `37404050977`
Run number: `10`
Attempt: `1`
Exact tested commit: `c9905f6a82604073f4c6101f84abd783b8319f7e`
Conclusion: SUCCESS

Windows Server 2022:
- job `112077513923`;
- runner `GitHub Actions 1000000781`, runner id `1000000781`;
- artifact `11385919117`;
- digest `sha256:7c1801fbe1136946f359540a655ecfe975fd85c67c27d856961ae8f96afedcd8`.

Windows Server 2025:
- job `112077514091`;
- runner `GitHub Actions 1000000782`, runner id `1000000782`;
- artifact `11386607220`;
- digest `sha256:3a85059e32ed1a6b10bd3a2f163a89b06e8ccb7d384a483a48f881e8570c5596`.

Both artifact reports were downloaded and inspected: 28/28 PASS, 0 FAIL, PowerShell 7.6.6, provider 10.0.12, native SQLite 3.53.3 and CLI SQLite 3.53.4.

CI on the same commit:
- run `37404050941`, CI #162;
- job `112077513239`;
- parser, ASCII/LF and secret scan PASS.

Repository `tools-tests` run `37404050966`, run #62, also passed.

Evidence directory: `docs/phase3/evidence/runtime-catalog-37404050977/`.

## 4. Security hardening included in the accepted run

The current factory:

- requires the original `PackageRoot` argument to be absolute before normalization;
- rejects UNC/device paths and any root whose Windows `DriveType` is not `Fixed`, including mapped network drives;
- rejects provider/catalog paths outside `PackageRoot` and reparse-point components;
- compares the provider product version with exact ordinal equality to 10.0.12;
- opens/validates package path components and provider/catalog files with Win32 handles using `FILE_FLAG_OPEN_REPARSE_POINT` and no delete sharing;
- validates handle-resolved final paths and reparse attributes;
- keeps provider path guards alive across native/managed provider loading and for the provider process lifetime;
- keeps each catalog path guard alive until its SQLite connection is disposed;
- proves by test that provider and catalog directories cannot be renamed/replaced during guarded lifetimes;
- uses `Mode=ReadOnly`, `Cache=Private`, `Pooling=false`, and verifies `query_only`;
- verifies native SQLite 3.53.3 and `integrity_check`;
- requires exactly one `catalog_meta` row and validates expected metadata case-sensitively where required;
- uses parameterized SQL for metadata lookup;
- creates no database when missing and no WAL/SHM/journal sidecars in accepted tests.

The factory does NOT authenticate package content. Signed-manifest verification and re-verification remain bootstrap responsibilities.

## 5. History that must remain preserved

[CONFIRMED] Run `37399118262` (#1) failed before product behavior because of a PowerShell interpolation parser error. Not provider failure evidence.

[CONFIRMED] Run `37401225241` (#3) reached 25/25 PASS then failed only during disposable cleanup because process-loaded `e_sqlite3.dll` remained locked.

[CONFIRMED] Run `37402464400` (#4) was the first complete 25/25 PASS and was initially accepted. It is now explicitly superseded after Codex path-hardening findings.

[CONFIRMED] Run `37403483739` (#7) passed the hardened runtime before explicit path-guard tests were added.

[CONFIRMED] Run `37403821077` (#9) passed all 28 functional gates; its CI failure was only the temporary touch of the historical non-ASCII `docs/decisions-log.md`. The decision log was restored to main and approval moved to the ASCII-only approval document.

Run `37404050977` (#10) is the accepted final evidence.

## 6. Remaining work

[PENDING] Integrate this factory after the signed-manifest verification gate in the runtime bootstrap.

[PENDING] Vendor the exact accepted provider payload in release packaging and list/hash every provider file in the signed manifest.

[PENDING] Add a semantic manifest/package record for both SQLite roles in addition to per-file hashes.

[V] Open a converted SISQUAL catalog on a target/sandbox Windows machine after package integration.

## 7. What not to do

- Do not redo the Phase 1B provider spike.
- Do not collapse SQLite 3.53.3 and 3.53.4 into one version; their roles are explicit.
- Do not add `dotnet`/NuGet as an operator runtime dependency.
- Do not weaken the fixed-local-root or handle-guard requirements during bootstrap integration.
- Do not allow browser-supplied SQL or arbitrary catalog/provider paths.
- Do not treat the process-lifetime native DLL lock as a product failure.
- Do not merge #54 without owner delegation.

## 8. Resume checklist

1. Read current `AGENTS.md` and `docs/decisions-log.md`.
2. Confirm current PR #54 head; another agent may have advanced it.
3. Check the Codex review requested on the final head and address only valid findings.
4. Confirm CI remains green after documentation-only commits.
5. Preserve run `37404050977` as accepted final functional evidence unless runtime/test behavior changes again.
6. Keep real converted-catalog target validation `[V]` until actually executed.
