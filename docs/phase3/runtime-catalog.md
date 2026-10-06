# Phase 3 - Runtime read-only catalog factory

**Date:** 2026-10-06
**Status:** [PROPOSED] product implementation; provider adoption authorised by the project owner, pending CI evidence and review of this implementation.

## Decision used by this slice

[CONFIRMED] Phase 1B run `37392036026` technically demonstrated `Microsoft.Data.Sqlite` 10.0.12 with the SQLitePCLRaw 2.1.12 closure on Windows 2022 and Windows 2025.

[CONFIRMED] The project owner authorised proceeding with the proposed runtime catalog factory after that validation. This formalises the previously recorded owner preference for two explicit SQLite patch versions by role:

- runtime ADO.NET provider: `Microsoft.Data.Sqlite` 10.0.12;
- native SQLite used by that provider: 3.53.3;
- separate CLI/tooling SQLite: 3.53.4.

The versions are not interchangeable or hidden behind one label. Runtime code checks the provider and native versions explicitly. Release packaging must vendor the accepted provider payload; the operator machine does not require `dotnet` or a NuGet restore.

[PENDING] The package-manifest contract currently hashes every shipped provider file but has no semantic dependency-version member. A separate manifest-contract/package integration change must record the two SQLite roles explicitly before release, matching the owner's decision.

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
- `Microsoft.Data.Sqlite` does not report product version 10.0.12.

The native `e_sqlite3.dll` is loaded by absolute path before the managed provider is initialised. No machine installation is required.

## Catalog open contract

The factory only opens an existing catalog below the same verified package tree.

It uses `SqliteConnectionStringBuilder`, not string concatenation, with:

- `Mode=ReadOnly`;
- `Cache=Private`;
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

## Validation

`tests/Integration/Test-RuntimeCatalog.ps1` creates disposable catalogs with the pinned SQLite 3.53.4 CLI and validates:

- exact provider/runtime pins;
- provider payload copied into a package-shaped folder;
- provider path containment;
- valid read-only open and exact metadata;
- parameterized read;
- write rejection;
- unchanged catalog SHA-256;
- no WAL/SHM/journal sidecars;
- missing-file rejection without creation;
- catalog path containment and junction rejection;
- exact ServerCode/schema/origin/origin-reference mismatch failures;
- invalid `built_at_utc` rejection;
- multiple `catalog_meta` rows rejection;
- 20 simultaneous read-only sessions;
- byte identity and no sidecars after repeated sessions.

`.github/workflows/phase3-runtime-catalog.yml` runs the integration test on Windows 2022 and Windows 2025 under the pinned portable PowerShell 7.6.6. For CI preparation only, it materializes the already accepted provider closure using the accepted Phase 1B `packages.lock.json`; this build-time SDK is not a product/runtime dependency.

## Follow-up integration

[PENDING] Wire this factory after the future signed-manifest verification gate in the runtime bootstrap. The bootstrap must supply only catalog metadata already authenticated by that manifest.

[PENDING] Vendor the exact provider payload into the release package and cover each file with the signed package manifest.

[V] Open one converted SISQUAL catalog on a target/sandbox Windows machine after package integration.
