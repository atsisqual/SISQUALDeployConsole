# Phase 1B - Managed SQLite provider spike

**Date:** 2026-10-06
**Status:** [CONFIRMED] `Microsoft.Data.Sqlite` 10.0.12 is technically viable for the tested read-only portable scope on Windows Server 2022 and 2025. Product adoption remains [PROPOSED].
**Scope:** read-only catalog access only, as required by ADR-0007.
**PR:** #36, branch `spike/phase1b-sqlite-managed-provider`.

Tags: [CONFIRMED] demonstrated by repository evidence or an executed run; [PROPOSED] recommended but not approved; [PENDING] still undecided; [V] requires target/sandbox validation.

## 1. Requirement

[CONFIRMED] ADR-0007 requires one SQLite catalog per machine, opened read-only by the portable application. The application never writes the catalog and does not require WAL or concurrent writers.

[CONFIRMED] The portable runtime is PowerShell 7.6.6. The repository separately pins SQLite CLI 3.53.4 for tooling/diagnostics, but that CLI does not provide the ADO.NET API needed by the application.

The spike asks whether a managed provider can be copied with the portable, loaded directly by PowerShell 7.6.6 without installation, and enforce read-only access without changing catalog bytes or creating sidecar files.

## 2. Candidate

[PROPOSED] `Microsoft.Data.Sqlite` 10.0.12.

The candidate was tested because it provides a lightweight ADO.NET API, supports `Mode=ReadOnly`, supports parameterized commands, and can be materialized as copy-local managed assemblies plus a native SQLite payload.

No adoption decision is made by the spike. `AGENTS.md` requires approval before adding a runtime dependency.

## 3. Spike implementation

The spike consists of:

- `spikes/phase1B/sqlite-provider/ProviderProbe.csproj`;
- `spikes/phase1B/sqlite-provider/Test-SqliteManagedProvider.ps1`;
- `.github/workflows/phase1b-sqlite-provider.yml`.

[CONFIRMED] `dotnet` is used only in CI to restore/materialize the candidate and verify `packages.lock.json`. The actual compatibility probe is launched by the pinned portable `pwsh.exe`.

[CONFIRMED] The runtime payload requires these files, not only one provider DLL:

- `Microsoft.Data.Sqlite.dll`;
- `SQLitePCLRaw.core.dll`;
- `SQLitePCLRaw.provider.e_sqlite3.dll`;
- `SQLitePCLRaw.batteries_v2.dll`;
- `e_sqlite3.dll`.

## 4. Accepted execution

[CONFIRMED] Accepted workflow run:

- workflow ID `375792558`;
- run ID `37392036026`;
- run number `5`;
- attempt `1`;
- commit `71e1151b6747b1ceee9e5529db1d40d0759fcdad`;
- conclusion `success`.

Windows 2022:

- job `112039131637`;
- runner `GitHub Actions 1000000658`, runner ID `1000000658`;
- artifact `11381318431`;
- artifact digest `sha256:d436a7eadcfb728f9cbc446c333aef7fa3475e663ccd294c0c4d4b6450d90020`.

Windows 2025:

- job `112039131900`;
- runner `GitHub Actions 1000000659`, runner ID `1000000659`;
- artifact `11382140601`;
- artifact digest `sha256:03f0a0ce92ed90d0634977dba284226f6db15c69d39c1c6dfd351b558097405d`.

[CONFIRMED] Both artifact ZIPs were downloaded and inspected. Exact reports and dependency evidence are versioned under `docs/phase1/evidence/phase1b-sqlite-provider-37392036026/`.

## 5. Gates proved

[CONFIRMED] Both the original provider folder and a copied folder passed all nine gates on both Windows images, with `fatalError=null`:

1. `HOST_POWERSHELL` - exact PowerShell 7.6.6;
2. `PROVIDER_PAYLOAD` - required managed/native files present;
3. `PROVIDER_LOAD` - direct load without installation;
4. `FIXTURE_CREATED` - fixture created by pinned SQLite CLI;
5. `READ_ONLY_READS` - row count, parameterized query and `integrity_check` succeed;
6. `WRITE_REJECTED` - INSERT fails through `Mode=ReadOnly`;
7. `MISSING_FILE_REJECTED` - missing database is not created;
8. `MULTIPLE_READ_CONNECTIONS` - 20 simultaneous read-only connections succeed;
9. `NO_CATALOG_MUTATION` - catalog SHA-256 remains identical and no sidecars are created.

[CONFIRMED] Folder portability is therefore demonstrated for the tested provider payload.

## 6. Connection policy if adopted

The probe uses `Mode=ReadOnly;Cache=Private`.

[PROPOSED] Product code should centralize connection creation in one local catalog factory. That factory should:

- canonicalize the approved catalog path;
- require the file to exist before connection creation;
- always use `Mode=ReadOnly`;
- use parameterized SQL for values;
- reject browser/catalog-supplied connection options;
- load the provider only from manifest-verified package paths.

## 7. Dependency closure and exact hashes

[CONFIRMED] The accepted workflow verified `packages.lock.json` using `dotnet restore --locked-mode --no-cache --force` against an empty package cache on both Windows images.

[CONFIRMED] The lock and generated graph were byte-identical on both systems:

- `packages.lock.json`, artifact bytes as produced on Windows (before the line-ending normalization of Git): 2206 bytes; SHA-256 `F0C6BAD7D4581F55ED79E0182429E89BE888E62AC6684E88D0D05095278948EA`
- `packages.lock.json`, bytes committed in Git (LF): 2148 bytes; SHA-256 `C380C7EC969189221C8B521B5218F7426B1ED03F519F6FCBCDAF3D0ABA35CAD4`
- `nuget-graph.json`, artifact bytes as produced on Windows (before the line-ending normalization of Git): 3567 bytes; SHA-256 `2F78A1CA873E2EA70901F4C67420847420C7B9CA7AF7CBB3B24C0F56DCE1A3C7`
- `nuget-graph.json`, bytes committed in Git (LF): 3505 bytes; SHA-256 `D0035D1A2640EB72C56A4038A60C536088D2367154D78A517C70BB3CFEF27F65`

The two kinds of hash differ only by line endings; the committed hashes are the ones to use when verifying from Git (the full table is in the evidence README).

Resolved packages:

| Package | Version | Raw `.nupkg` SHA-256 |
|---|---:|---|
| `Microsoft.Data.Sqlite` | 10.0.12 | `246679D8C6C83FFCF4C8A480066E3F4FC4E051C96B71BEDFD932FE7A5AF1F7D4` |
| `Microsoft.Data.Sqlite.Core` | 10.0.12 | `5E8ED353006DADF55D5C7F56D237321C20BB10C786262E6B25526756E1036332` |
| `SQLitePCLRaw.bundle_e_sqlite3` | 2.1.12 | `A9A06E6B5A313F6EF3675F91997D012ADEFFE8AA9E1FFD69ED46A4E685B054E1` |
| `SQLitePCLRaw.core` | 2.1.12 | `AF06904138FFA6DC95A599133D64D254716D6FACC7543A6B3B910793DAE9DCA5` |
| `SQLitePCLRaw.lib.e_sqlite3` | 2.1.12 | `4A22C02FFCF489792903CF263DEF9FCE27739716883F965F0B5EEFF1637430AC` |
| `SQLitePCLRaw.provider.e_sqlite3` | 2.1.12 | `DF2B3271992E5D719186C4671E3CF4F8658097C154CBCD41494AB594C5997595` |

The evidence JSON preserves raw SHA-512, NuGet `contentHash`, source URI and archive size as separate fields.

## 8. Native SQLite version

[CONFIRMED] `Microsoft.Data.Sqlite` 10.0.12 / SQLitePCLRaw 2.1.12 loaded native SQLite `3.53.3` on both Windows images and from both original/copied folders.

[CONFIRMED] The separate repository CLI remains SQLite `3.53.4`.

[PENDING] Packaging policy must explicitly choose one of these approaches before adoption:

1. accept and pin the two patch versions by role (runtime provider 3.53.3, CLI 3.53.4); or
2. change the provider/native payload so the runtime also uses an approved 3.53.4 build, then rerun the same gates.

Recommendation: do not reject the provider solely because of a one-patch version difference; decide based on support/security/update policy and keep both versions explicit in the manifest if option 1 is chosen.

## 9. Failure history

[CONFIRMED] Earlier failures were preserved rather than hidden:

- run `37370494285`: two infrastructure-only attempts, no runner and zero executed steps;
- run `37372704803` attempt 1: infrastructure-only, no runner;
- run `37372704803` attempt 2: actual runners; provider reached functional gates but the harness failed under `Set-StrictMode` on an empty sidecar result and the dependency evidence compared unlike NuGet hash semantics;
- run `37391452873`: original/copied provider probes passed on both OS, dependency-evidence/summary step failed;
- run `37391503600`: original/copied provider probes passed on both OS, manual NuGet content-hash comparison failed;
- run `37392036026`: first fully successful execution.

Detailed IDs, runners, artifacts and hashes are in the evidence ledger and handover.

## 10. Technical conclusion

[CONFIRMED] `Microsoft.Data.Sqlite` 10.0.12 is technically viable for portable read-only catalog access on the tested GitHub Windows Server 2022 and 2025 environments.

This conclusion is limited to the tested scope. It does not by itself approve a runtime dependency.

## 11. Decision boundary

[PROPOSED] Adopt `Microsoft.Data.Sqlite` 10.0.12 and vendor the exact tested win-x64 closure.

[PENDING] Owner/reviewer approval of the runtime dependency.

[DECIDED 2026-10-07] Native SQLite patch-version policy (3.53.3 provider versus 3.53.4 CLI): both are accepted by role, see ADR-0009.

[V] Open one converted SISQUAL catalog read-only on the intended target/sandbox Windows environment before production acceptance.

## 12. Next product work if approved

1. add the exact approved provider files/hashes to the portable dependency manifest/package process;
2. implement the read-only catalog connection factory;
3. add startup tests that reject missing/modified provider files and any write-capable catalog connection;
4. update ADR-0007 only to close the managed-provider open item after approval;
5. retain `dotnet` as CI/build tooling only, not an operator-machine requirement.
