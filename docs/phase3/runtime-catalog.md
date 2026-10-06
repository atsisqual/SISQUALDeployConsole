# Phase 3 - Runtime read-only catalog factory

**Date:** 2026-10-06
**Status:** [CONFIRMED] product implementation technically validated on disposable Windows Server 2022 and 2025; final converted-catalog target validation remains [V].

## Decision used by this slice

[CONFIRMED] Phase 1B run `37392036026` technically demonstrated `Microsoft.Data.Sqlite` 10.0.12 with the SQLitePCLRaw 2.1.12 closure on Windows 2022 and Windows 2025.

[CONFIRMED] The project owner authorised proceeding with the runtime catalog factory after that validation and accepted the two SQLite patch versions explicitly by role:

- runtime ADO.NET provider: `Microsoft.Data.Sqlite` 10.0.12;
- native SQLite used by that provider: 3.53.3;
- separate CLI/tooling SQLite: 3.53.4.

The versions are not interchangeable or hidden behind one label. Runtime code checks the provider and native versions explicitly. Release packaging must vendor the accepted provider payload; the operator machine does not require `dotnet` or a NuGet restore.

[PENDING] The package-manifest contract currently hashes every shipped provider file but has no semantic dependency-version member. A separate manifest-contract/package integration change must record the two SQLite roles explicitly before release.

## Scope

This slice implements the reusable catalog factory only. It does not wire the factory into `Start.cmd` or the open runtime-bootstrap PR, and it does not implement manifest signature verification, credentials, Pode routes, UI or engines.

`runtime/Sisqual.Runtime.Catalog.psm1` provides:

- `Get-SisqualRuntimeSqliteDefaults`;
- `Initialize-SisqualRuntimeSqliteProvider`;
- `Open-SisqualRuntimeCatalog`;
- `Close-SisqualRuntimeCatalog`.

## Provider load

The provider is loaded from a package-relative, local path only. The module fails closed when:

- `PackageRoot` is missing, non-local or contains a reparse point;
- `ProviderRoot` escapes the package root or crosses a reparse point;
- any required managed/native provider file is missing or duplicated;
- `Microsoft.Data.Sqlite` does not report the accepted 10.0.12 product version family.

The native `e_sqlite3.dll` is loaded by absolute path before the managed provider is initialised and remains loaded for the lifetime of the PowerShell process. No machine installation is required.

## Catalog open contract

The factory only opens an existing catalog below the same verified package tree.

It uses `SqliteConnectionStringBuilder`, not string concatenation, with:

- `Mode=ReadOnly`;
- `Cache=Private`;
- `Pooling=false`;
- `PRAGMA query_only = ON`.

The factory then fails closed unless:

1. the file name is exactly `catalog-<ExpectedServerCode>.db`;
2. the native engine reports SQLite 3.53.3;
3. `PRAGMA integrity_check` returns exactly `ok`;
4. `catalog_meta` contains exactly one row;
5. that row has `meta_id=1`;
6. `schema_version` equals the already verified manifest value supplied by the caller;
7. `server_code` equals the expected ServerCode using ordinal/case-sensitive comparison;
8. `source_kind` equals the verified manifest origin;
9. when supplied, `source_reference` equals the verified manifest origin reference;
10. `source_reference` is printable ASCII and no longer than 200 characters;
11. `built_at_utc` is exactly UTC second-precision `YYYY-MM-DDTHH:MM:SSZ`.

The metadata lookup itself uses a SQLite parameter for `meta_id`; no browser-supplied SQL exists in this module.

## Filesystem boundary

Both provider and catalog paths are required to remain lexically inside `PackageRoot`, and every existing path component is rejected if it is a Windows reparse point. This prevents a junction/symlink inside the portable tree from redirecting provider or catalog access outside the approved package tree.

The future startup integration still has to verify the signed package manifest and file hashes before calling this module. This factory does not replace that integrity gate.

## Accepted validation

[CONFIRMED] The accepted functional evidence is workflow `375949981`, run `37402464400`, run #4 attempt 1, exact product commit `1c8316a47d9d61fef4a427834d3b6f87c7e6ca7a`.

- Windows Server 2022 job `112072458381`, runner `1000000758`: SUCCESS, 25/25 checks PASS, artifact `11385304398`.
- Windows Server 2025 job `112072458133`, runner `1000000757`: SUCCESS, 25/25 checks PASS, artifact `11386135630`.
- both reports: PowerShell 7.6.6, provider 10.0.12, native SQLite 3.53.3, CLI SQLite 3.53.4, 0 failures.
- CI run `37402464402`, job `112072457412`: SUCCESS, parser/ASCII-LF/secret scan PASS.
- repository `tools-tests` run `37402464397`: SUCCESS.

The reports and full run ledger are under `docs/phase3/evidence/runtime-catalog-37402464400/`.

`tests/Integration/Test-RuntimeCatalog.ps1` validates exact pins, package containment, read-only behavior, `query_only`, metadata, parameterized reads, write rejection, byte identity, zero sidecars, missing-file behavior, mismatch failures, junction rejection and 20 simultaneous sessions.

[CONFIRMED] A prior run reached all 25 product checks successfully but failed only when test cleanup tried to delete the process-loaded native `e_sqlite3.dll`. The product runtime was not weakened; only disposable cleanup now tolerates that exact process-lifetime lock while rethrowing other cleanup failures.

## Follow-up integration

[PENDING] Wire this factory after the signed-manifest verification gate in the runtime bootstrap. The bootstrap must supply only catalog metadata already authenticated by that manifest.

[PENDING] Vendor the exact provider payload into the release package and cover each file with the signed package manifest.

[V] Open one converted SISQUAL catalog on a target/sandbox Windows machine after package integration.
