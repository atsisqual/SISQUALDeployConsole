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

Before loading provider code, the module establishes Win32 path guards: existing package directories and required provider files are opened with `FILE_FLAG_OPEN_REPARSE_POINT`, without delete or write sharing, and their handle-resolved final paths and reparse attributes are validated. Each provider file is then rebound to its verified manifest entry and its size and SHA-256 are recomputed while that retained guard is held. Those handles remain alive for the provider lifetime so path components cannot be renamed/replaced and trusted provider bytes cannot be modified after verification and before/during native or managed load.

The native `e_sqlite3.dll` is loaded by absolute path before the managed provider is initialised and remains loaded for the lifetime of the PowerShell process. No machine installation is required.

## Catalog open contract

The factory only opens an existing catalog below the same guarded package tree.

It uses `SqliteConnectionStringBuilder` with:

- a local file URI carrying `immutable=1`;
- `Mode=ReadOnly`;
- `Cache=Private`;
- `Pooling=false`;
- `PRAGMA query_only = ON`.

A catalog path/file guard is established before `SqliteConnection.Open` and retained until the session is closed. While that guard is held, the expected catalog size and SHA-256 are recomputed before SQLite is opened. The guard prevents path replacement and in-place write opens while the authenticated main database bytes are trusted.

A sealed catalog is defined as one authenticated main database image. Unverified SQLite sidecars are not part of that image. The factory therefore:

- rejects existing `<catalog>-wal`, `<catalog>-shm` and `<catalog>-journal` files before open;
- opens the authenticated main file through SQLite `immutable=1`, so a later sidecar is not part of the intended database view;
- checks sidecar absence again immediately after open and fails closed if one appeared in that window.

The factory fails closed unless:

1. the file name is exactly `catalog-<ExpectedServerCode>.db`;
2. the guarded main file still has the authenticated expected size and SHA-256;
3. no unverified SQLite sidecar is accepted into the sealed catalog view;
4. the native engine reports SQLite 3.53.3;
5. `PRAGMA integrity_check` returns exactly `ok`;
6. `catalog_meta` contains exactly one row;
7. that row has `meta_id=1`;
8. `schema_version` equals the already verified manifest value supplied by the caller;
9. `server_code` equals the expected ServerCode using ordinal/case-sensitive comparison;
10. `source_kind` equals the verified manifest origin;
11. when supplied, `source_reference` equals the verified manifest origin reference;
12. `source_reference` is printable ASCII and no longer than 200 characters;
13. `built_at_utc` is exactly UTC second-precision `YYYY-MM-DDTHH:MM:SSZ`.

The internal metadata lookup uses a SQLite parameter for `meta_id`; no browser-supplied SQL exists in this module. The public catalog session is opaque and does not expose the raw `Microsoft.Data.Sqlite.SqliteConnection`; connection and guard disposal remain module-private through `Close-SisqualRuntimeCatalog`.

## Filesystem and trust boundary

The catalog factory does not authenticate the package-manifest signature. It assumes a future startup layer has already verified the signed manifest and passes authenticated expected file hashes/sizes and catalog metadata.

The factory then binds those authenticated expectations to the files it actually uses: provider and catalog files are guarded first, then size/SHA-256 are revalidated under the retained guards before load/open. Package paths are restricted to a fixed local drive, reparse traversal is rejected, write/delete sharing is denied where trusted bytes are held, and catalog sessions use an immutable SQLite view intended to exclude unverified WAL/SHM/journal state.

This is still not a substitute for the bootstrap signature gate. The bootstrap must authenticate the manifest before this module is called.

## Accepted validation

[CONFIRMED] The accepted functional evidence is workflow `375949981`, run `37440720047`, run #20 attempt 1, exact tested commit `3fa27ffaf5a92001bb8cd14488a54e9f7a49b034`.

- Windows Server 2022 job `112193530442`: SUCCESS; the main runtime-catalog suite passed 34/34 and the sidecar-hardening suite passed 6/6; artifact `11401450858`, digest `sha256:e76db9433ce47ae98c9a59c1f37694016697d7a455d312e5b99778c99d85b204`.
- Windows Server 2025 job `112193530003`: SUCCESS; the same 34/34 + 6/6 checks passed; artifact `11400898174`, digest `sha256:e922d4ca2afebf545637bfe68afa900f83550c8738e4a929a768399bceaccc7b`.
- both jobs used PowerShell 7.6.6, provider 10.0.12, native SQLite 3.53.3 and the separately pinned CLI SQLite 3.53.4.
- CI run `37440720073`, CI #190, job `112193529141`: SUCCESS; parser, ASCII/LF and secret scan PASS.
- repository `tools-tests` run `37440720136`, run #90: SUCCESS.

`tests/Integration/Test-RuntimeCatalog.ps1` validates exact provider/native pins, package containment, provider/catalog hash and size rebinding under retained guards, metadata exactness, opaque-session trust evidence, no raw SQLite connection exposure, path/write guards, byte identity, zero sidecars, mismatch and missing-file failures, junction rejection, and 20 simultaneous sessions.

`tests/Integration/Test-RuntimeCatalog-Sidecars.ps1` separately proves that pre-existing unverified WAL/SHM sidecars fail closed without changing the authenticated main file, that the sealed catalog opens through the configured immutable guarded view without creating sidecars, and that a late sidecar attempt cannot alter the guarded main bytes. If late sidecar creation succeeds, the test requires a subsequent catalog open to reject it. This evidence deliberately does not claim observational proof that an already-open connection ignores a valid late WAL; `immutable=1` remains the runtime control for that design property.

Historical runs remain in the PR history but are superseded by run `37440720047` for acceptance of the tested functional implementation. The current evidence-clarification head changes only the sidecar assertion/wording described above and therefore requires a fresh execution before it can replace run `37440720047` as accepted evidence.

## Follow-up integration

[PENDING] Wire this factory after the signed-manifest verification gate in the runtime bootstrap. The bootstrap must supply only file trust data and catalog metadata already authenticated by that manifest.

[PENDING] Vendor the exact provider payload into the release package and cover each file with the signed package manifest.

[PENDING] Record the two SQLite roles semantically in manifest/package integration in addition to the provider-file hashes.

[V] Open one converted SISQUAL catalog on a target/sandbox Windows machine after package integration.
