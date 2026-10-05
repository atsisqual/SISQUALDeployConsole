# Phase 1B - Managed SQLite provider spike

**Date:** 2026-10-05
**Status:** [PROPOSED] candidate under evaluation. No runtime dependency is approved by this document.
**Scope:** read-only catalog access only, as required by ADR-0007.
**PR:** #36, branch `spike/phase1b-sqlite-managed-provider`.

Tags: [CONFIRMED] demonstrated by repository evidence or an executed run; [PROPOSED] recommended but not approved; [PENDING] still undecided or not yet demonstrated; [V] requires validation outside the GitHub runner.

## 1. Why this spike exists

[CONFIRMED] ADR-0007 requires the portable application to open one SQLite catalog per machine read-only and never write to it. WAL and concurrent writers are not required. The managed SQLite provider is explicitly left [PENDING] for Phase 1B.

[CONFIRMED] The portable runtime is PowerShell 7.6.6. The existing SQLite 3.53.4 artifact in `vendor/manifest.json` is the CLI/engine used by tools and spikes; it does not provide an ADO.NET API to the PowerShell application.

The question for this spike is therefore narrow:

> Can a managed SQLite provider be copied with the portable folder, loaded directly by PowerShell 7.6.6 without installation, and enforce read-only catalog access without changing the catalog bytes or creating sidecar files?

## 2. Candidate

[PROPOSED] `Microsoft.Data.Sqlite` 10.0.12.

Reasons for testing it first:

- it is Microsoft's lightweight ADO.NET provider for SQLite;
- NuGet lists 10.0.12 as the current stable 10.x package on 2026-10-05;
- Microsoft documents `Mode=ReadOnly` as a supported connection mode;
- it supports parameterized ADO.NET commands;
- it can be materialized as ordinary managed assemblies plus the native SQLite payload and copied with the application.

External references checked on 2026-10-05:

- https://www.nuget.org/packages/Microsoft.Data.Sqlite/10.0.12
- https://learn.microsoft.com/dotnet/standard/data/sqlite/connection-strings

No selection or vendoring decision is made here. `AGENTS.md` requires owner approval before adding a new runtime dependency.

## 3. Spike implementation

[CONFIRMED] PR #36 contains only spike material and its workflow:

- `spikes/phase1B/sqlite-provider/ProviderProbe.csproj`
- `spikes/phase1B/sqlite-provider/Test-SqliteManagedProvider.ps1`
- `.github/workflows/phase1b-sqlite-provider.yml`

[CONFIRMED] `ProviderProbe.csproj` targets `net10.0`, `win-x64`, and references `Microsoft.Data.Sqlite` 10.0.12. `dotnet` is used only by the GitHub runner to restore and materialize the candidate payload. The actual compatibility probe is launched by the pinned portable `pwsh.exe`.

[CONFIRMED] The probe explicitly loads these files from the copied provider payload:

- `Microsoft.Data.Sqlite.dll`
- `SQLitePCLRaw.core.dll`
- `SQLitePCLRaw.provider.e_sqlite3.dll`
- `SQLitePCLRaw.batteries_v2.dll`
- `e_sqlite3.dll`

This is important for packaging: choosing `Microsoft.Data.Sqlite` means shipping a managed dependency closure and a native SQLite library, not only one DLL.

## 4. Gates

The workflow runs the same gates on `windows-2022` and `windows-2025`.

| Gate | Required result |
|---|---|
| Portable runtime | exact PowerShell 7.6.6 |
| Provider payload | all required managed and native files found |
| Direct load | `Microsoft.Data.Sqlite` loads without installation |
| Catalog fixture | created by the already pinned SQLite 3.53.4 CLI |
| Read-only reads | row count, parameterized query and `PRAGMA integrity_check` succeed |
| Write attempt | rejected by `Mode=ReadOnly` |
| Missing database | open fails and no file is created |
| Multiple readers | 20 simultaneous read-only connections query successfully |
| Catalog bytes | SHA-256 before and after is identical |
| Sidecars | no journal, WAL, SHM or other sidecar is created |
| Folder portability | the complete provider folder is copied elsewhere and the probe passes again |
| Dependency evidence | lock file and resolved package hashes are captured and verified |
| Native version evidence | `sqlite_version()` records the SQLite version actually loaded by the provider |

A green result means only that this candidate is technically viable for the tested scope.

## 5. Read-only semantics

[CONFIRMED] The probe constructs connections with:

`Mode=ReadOnly;Cache=Private`

[CONFIRMED] Microsoft documentation defines `ReadOnly` as opening the database read-only. The probe does not rely on that statement alone: it also attempts an INSERT, checks that opening a missing file does not create it, hashes the database before and after use, and checks the directory for sidecars.

[PROPOSED] If this provider is adopted, the application should centralize catalog connection creation so product code cannot silently fall back to the provider default `ReadWriteCreate` mode.

[PROPOSED] Production code should reject any catalog connection string not built by that local factory. Arbitrary browser/catalog input must never supply connection options.

## 6. Dependency and packaging implications

[CONFIRMED] `Microsoft.Data.Sqlite` depends on `Microsoft.Data.Sqlite.Core` and SQLitePCLRaw packages. The package also brings a native SQLite implementation through its SQLitePCLRaw bundle.

[CONFIRMED] The repository separately pins SQLite CLI 3.53.4. These are different deployment roles:

- SQLite CLI 3.53.4: conversion/diagnostic tooling and test fixture creation;
- native SQLite carried by the managed provider: runtime database engine used by `Microsoft.Data.Sqlite`.

[PENDING] The native version resolved by `Microsoft.Data.Sqlite` 10.0.12 must be recorded from the completed run and reviewed against the separately pinned CLI version. The versions do not have to be identical to prove read-only access, but a deliberate support and patching policy is required before vendoring.

[PROPOSED] If adopted, pin the complete runtime closure by version and SHA-256, not only the top-level NuGet package. The release package must contain all files required to load the provider on a clean win-x64 machine.

[PENDING] Whether `dotnet` is ever used outside CI. Recommendation: no. CI/build tooling should materialize the provider payload; the portable operator machine should need only the vendored files and portable PowerShell.

## 7. Alternatives

This spike does not claim that the first candidate is automatically the best provider.

| Option | Portability | Read-only API | Native dependency | Current assessment |
|---|---|---|---|---|
| `Microsoft.Data.Sqlite` 10.0.12 | [PROPOSED] copy-local payload | [CONFIRMED external] `Mode=ReadOnly` | yes, SQLitePCLRaw/e_sqlite3 | primary candidate |
| `System.Data.SQLite` / `System.Data.SQLite.Core` | possible copy-local provider | provider-specific | yes | [PENDING] fallback only if primary candidate fails a required gate |
| `sqlite3.exe` CLI only | already portable | command-line only | self-contained CLI | not suitable as the application's normal data-access API |
| custom P/Invoke to sqlite3 | technically possible | would be custom | yes | rejected as unnecessary complexity unless managed providers fail |

[PROPOSED] Do not spend a separate spike on every alternative unless `Microsoft.Data.Sqlite` fails a gate or introduces an unacceptable packaging/security issue. The product only needs simple read-only ADO.NET access, not an ORM.

## 8. Security considerations

[CONFIRMED] ADR-0007 makes the catalog part of the signed portable package and requires SHA-256 verification at startup.

[PROPOSED] Provider adoption does not replace package integrity checks. The provider must open only the already verified catalog path.

[PROPOSED] Runtime safeguards if adopted:

1. canonicalize and validate the catalog path before opening;
2. require the file to exist before connection creation;
3. use `Mode=ReadOnly` on every connection;
4. use parameterized SQL for values;
5. never execute SQL supplied by browser input or catalog data;
6. fail closed if the provider payload hash differs from the signed manifest;
7. never enable provider extensions or arbitrary native library loading from user-controlled paths.

No credentials are involved in this spike.

## 9. Execution evidence

[CONFIRMED] Run `37370494285` records the initial workflow attempt. Its first attempt was cancelled before either Windows job received a runner, so it is not compatibility evidence.

[CONFIRMED] Review of that workflow identified an evidence defect: PackageReference restores do not guarantee that `.nupkg` archives remain in the global package directory, so the original hash collector could have emitted `nupkgSha256 = null`.

[CONFIRMED] Commit `a1b8e28bc11d518c22e3aaf34a581f5e346a9ba3` fixes that defect. The workflow now resolves package IDs and versions from `packages.lock.json`, downloads each exact archive explicitly, records SHA-256 and SHA-512, verifies SHA-512 against the lock-file `contentHash`, and fails on missing or mismatched evidence.

[PENDING] The candidate accepted run is `37372704803`, workflow `phase1b-sqlite-provider`, commit `a1b8e28bc11d518c22e3aaf34a581f5e346a9ba3`. Its evidence record is `docs/phase1/evidence/phase1b-sqlite-provider-37372704803/README.md`.

Expected evidence artifacts per Windows version:

- `report-<os>-original.json`
- `report-<os>-copy.json`
- `packages.lock-<os>.json`
- `nuget-graph-<os>.json`

[PENDING] Until those reports exist from executed jobs, no compatibility gate is [CONFIRMED] by execution and the provider remains unselected.

## 10. Decision boundary

A completed green run on both GitHub Windows versions would support this conclusion:

- [CONFIRMED] candidate is technically viable for portable, read-only catalog access on the tested runner images;
- [PROPOSED] adopt `Microsoft.Data.Sqlite` 10.0.12 and vendor its exact win-x64 closure;
- [PENDING] owner/reviewer approval of the new runtime dependency;
- [PENDING] final dependency manifest entries and hashes from the accepted run;
- [V] a read-only open of one converted SISQUAL catalog on a target/sandbox Windows machine before production acceptance.

A failed required gate means the candidate is not accepted as-is. The failure must be documented before either changing the candidate version or evaluating the fallback provider.

## 11. What this does not decide

- machine private-key implementation;
- credential package storage or encryption;
- Phase 1C web/session security;
- catalog schema/content;
- catalog authority after cutover;
- any engine behavior;
- any application write path, because ADR-0007 forbids database writes.

## 12. Required follow-up after an accepted run

[PENDING] If the technical gates pass and the owner/reviewer approves the dependency:

1. record the accepted run under `docs/phase1/evidence/`;
2. record exact package/file hashes and native SQLite version;
3. add the approved provider payload to the release dependency manifest/package process;
4. update ADR-0007 only to close its managed-provider open item, without changing its read-only requirement;
5. add product tests that prove every catalog connection is read-only.

Until approval, ADR-0007 and `AGENTS.md` remain unchanged and the provider selection remains [PENDING].
