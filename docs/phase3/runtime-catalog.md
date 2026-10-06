# Phase 3 - Runtime read-only catalog factory

**Date:** 2026-10-06
**Status:** [CONFIRMED] product implementation technically validated on disposable Windows Server 2022 and 2025; final converted-catalog target validation remains [V].

## Decision used by this slice

[CONFIRMED] Phase 1B run `37392036026` technically demonstrated `Microsoft.Data.Sqlite` 10.0.12 with the SQLitePCLRaw 2.1.12 closure on Windows 2022 and Windows 2025.

[CONFIRMED] The project owner authorised runtime adoption and proceeding with the catalog factory. The traceable approval is recorded in `docs/phase3/sqlite-runtime-adoption.md`.

The approved roles are explicit:

- runtime ADO.NET provider: `Microsoft.Data.Sqlite` 10.0.12;
- native SQLite used by that provider: 3.53.3;
- separate CLI/tooling SQLite: 3.53.4.

The versions are not interchangeable or hidden behind one label. Runtime code checks the provider product version with exact ordinal equality and checks the native SQLite version exactly. Release packaging must vendor the accepted provider payload; the operator machine does not require `dotnet` or a NuGet restore.

[PENDING] The package-manifest contract currently hashes every shipped provider file but has no semantic dependency-version member. A separate manifest/package integration change must record the two SQLite roles explicitly before release.

## Scope

This slice implements the reusable catalog factory only. It does not wire the factory into `Start.cmd` or the open runtime-bootstrap PR, and it does not implement manifest signature verification, credentials, Pode routes, UI or engines.

`runtime/Sisqual.Runtime.Catalog.psm1` provides:

- `Get-SisqualRuntimeSqliteDefaults`;
- `Initialize-SisqualRuntimeSqliteProvider`;
- `Open-SisqualRuntimeCatalog`;
- `Close-SisqualRuntimeCatalog`.

## Provider load

The provider is loaded from a package-relative path under an absolute fixed local-drive `PackageRoot` only. The module fails closed when:

- the original `PackageRoot` argument is relative;
- `PackageRoot` is UNC, a device path, non-existent, on a mapped/network/non-fixed drive, or contains a reparse point;
- `ProviderRoot` escapes the package root or crosses a reparse point;
- any required managed/native provider file is missing or duplicated;
- `Microsoft.Data.Sqlite` does not report exactly 10.0.12.

Before loading provider code, the module establishes Win32 path guards: existing package directories and required provider files are opened with `FILE_FLAG_OPEN_REPARSE_POINT`, without delete sharing, and their handle-resolved final paths and reparse attributes are validated. Those handles remain alive for the provider lifetime so path components cannot be renamed/replaced between validation and native/managed load.

The native `e_sqlite3.dll` is loaded by absolute path before the managed provider is initialised and remains loaded for the lifetime of the PowerShell process. No machine installation is required.

## Catalog open contract

The factory only opens an existing catalog below the same guarded package tree.

It uses `SqliteConnectionStringBuilder`, not string concatenation, with:

- `Mode=ReadOnly`;
- `Cache=Private`;
- `Pooling=false`;
- `PRAGMA query_only = ON`.

A catalog path guard is established before `SqliteConnection.Open` and is retained until the session connection is disposed. The guard validates the handle-resolved path and prevents rename/replacement of the guarded package path while the session is active.

The factory fails closed unless:

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

The metadata lookup uses a SQLite parameter for `meta_id`; no browser-supplied SQL exists in this module.

## Filesystem and trust boundary

The catalog factory does not authenticate the package manifest. It assumes a future startup layer has already verified the signed manifest and file hashes and supplies authenticated expected catalog metadata.

This module adds a separate path-stability boundary: it rejects relative/non-fixed/network/reparse package roots and keeps handle guards across provider loading and catalog sessions so a validated package path cannot be replaced with a junction/symlink through a rename race.

Content integrity remains the responsibility of the signed-manifest verification/reverification flow required by the bootstrap and ADR-0007.

## Accepted validation

[CONFIRMED] The accepted evidence is workflow `375949981`, run `37404050977`, run #10 attempt 1, exact tested commit `c9905f6a82604073f4c6101f84abd783b8319f7e`.

- Windows Server 2022 job `112077513923`, runner `1000000781`: SUCCESS, 28/28 checks PASS, artifact `11385919117`, digest `sha256:7c1801fbe1136946f359540a655ecfe975fd85c67c27d856961ae8f96afedcd8`.
- Windows Server 2025 job `112077514091`, runner `1000000782`: SUCCESS, 28/28 checks PASS, artifact `11386607220`, digest `sha256:3a85059e32ed1a6b10bd3a2f163a89b06e8ccb7d384a483a48f881e8570c5596`.
- both reports: PowerShell 7.6.6, provider 10.0.12, native SQLite 3.53.3, CLI SQLite 3.53.4, 0 failures.
- CI run `37404050941`, CI #162, job `112077513239`: SUCCESS, parser/ASCII-LF/secret scan PASS.
- repository `tools-tests` run `37404050966`, run #62: SUCCESS.

The artifact reports were downloaded and inspected before acceptance. Full evidence is under `docs/phase3/evidence/runtime-catalog-37404050977/`.

`tests/Integration/Test-RuntimeCatalog.ps1` validates exact pins, read-only behavior, query-only, metadata, parameterized reads, write rejection, byte identity, zero sidecars, missing-file behavior, mismatch failures, junction rejection, 20 simultaneous sessions, relative-root rejection, and active path guards that prevent provider/catalog directory replacement.

The earlier 25/25 run `37402464400` remains historical evidence but is superseded by the 28/28 security-hardened run.

## Follow-up integration

[PENDING] Wire this factory after the signed-manifest verification gate in the runtime bootstrap. The bootstrap must supply only catalog metadata already authenticated by that manifest.

[PENDING] Vendor the exact provider payload into the release package and cover each file with the signed package manifest.

[PENDING] Record the two SQLite roles semantically in manifest/package integration in addition to the provider-file hashes.

[V] Open one converted SISQUAL catalog on a target/sandbox Windows machine after package integration.
