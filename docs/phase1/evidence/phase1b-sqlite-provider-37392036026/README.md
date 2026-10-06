# Phase 1B SQLite provider evidence - run 37392036026

**Workflow:** `phase1b-sqlite-provider`
**Workflow ID:** `375792558`
**Run ID:** `37392036026`
**Run number:** `5`
**Attempt:** `1`
**Event:** `push`
**Branch:** `spike/phase1b-sqlite-managed-provider`
**Commit:** `71e1151b6747b1ceee9e5529db1d40d0759fcdad`
**PR:** #36
**Started UTC:** `2026-10-06T00:04:37Z`
**Completed UTC:** `2026-10-06T00:08:46Z`
**Status:** [CONFIRMED] accepted technical evidence for the Phase 1B managed SQLite provider spike.

## Accepted execution

[CONFIRMED] Both GitHub-hosted Windows jobs completed the full workflow successfully.

| OS | Job ID | Runner | Runner ID | Started UTC | Completed UTC | Result |
|---|---:|---|---:|---|---|---|
| windows-2022 | `112039131637` | `GitHub Actions 1000000658` | `1000000658` | 2026-10-06T00:04:39Z | 2026-10-06T00:08:45Z | success |
| windows-2025 | `112039131900` | `GitHub Actions 1000000659` | `1000000659` | 2026-10-06T00:04:39Z | 2026-10-06T00:08:43Z | success |

[CONFIRMED] Every workflow step completed successfully on both jobs: provider restore/materialization, pinned runtime verification, original-folder probe, copied-folder probe, NuGet locked restore, package-hash evidence, summary and artifact upload.

## GitHub artifacts

| OS | Artifact ID | Size | Digest | Expires UTC |
|---|---:|---:|---|---|
| windows-2022 | `11381318431` | 5167 bytes | `sha256:d436a7eadcfb728f9cbc446c333aef7fa3475e663ccd294c0c4d4b6450d90020` | 2027-01-04T00:04:37Z |
| windows-2025 | `11382140601` | 5171 bytes | `sha256:03f0a0ce92ed90d0634977dba284226f6db15c69d39c1c6dfd351b558097405d` | 2027-01-04T00:04:37Z |

[CONFIRMED] Both artifact ZIPs were downloaded and inspected before this run was accepted.

## Probe results

[CONFIRMED] The original provider folder and a copied provider folder both report `overall=PASS`, `9 PASS / 0 FAIL`, `fatalError=null` on both Windows images.

The nine gates are:

1. `HOST_POWERSHELL`
2. `PROVIDER_PAYLOAD`
3. `PROVIDER_LOAD`
4. `FIXTURE_CREATED`
5. `READ_ONLY_READS`
6. `WRITE_REJECTED`
7. `MISSING_FILE_REJECTED`
8. `MULTIPLE_READ_CONNECTIONS`
9. `NO_CATALOG_MUTATION`

[CONFIRMED] The test used portable PowerShell `7.6.6` and candidate `Microsoft.Data.Sqlite` `10.0.12`.

[CONFIRMED] Read-only behavior was demonstrated by successful parameterized reads and `PRAGMA integrity_check`, rejection of INSERT, rejection of a missing database without creating a file, 20 simultaneous read-only connections, identical catalog SHA-256 before/after and zero sidecar files.

[CONFIRMED] Copying the complete provider payload to another folder did not change the result.

## Native SQLite version

[CONFIRMED] `sqlite_version()` returned `3.53.3` from the native SQLite runtime loaded by `Microsoft.Data.Sqlite` in all four accepted probe reports.

[CONFIRMED] This is distinct from the repository's separately pinned SQLite CLI `3.53.4`, which created the fixture. The version difference did not prevent the tested read-only behavior.

[PENDING] Before product adoption, decide whether V1 deliberately carries these two pinned patch versions or whether the managed provider payload must be aligned to SQLite `3.53.4`.

## NuGet lock and package evidence

[CONFIRMED] The workflow restored `ProviderProbe.csproj` against `packages.lock.json` in `--locked-mode` using an empty package cache. The locked restore succeeded on both Windows images.

[CONFIRMED] The lock file and generated package graph are byte-identical across both artifacts:

- `packages.lock.json`, artifact bytes as produced on Windows (before the line-ending normalization of Git): 2206 bytes; SHA-256 `F0C6BAD7D4581F55ED79E0182429E89BE888E62AC6684E88D0D05095278948EA`
- `packages.lock.json`, bytes committed in Git (LF): 2148 bytes; SHA-256 `C380C7EC969189221C8B521B5218F7426B1ED03F519F6FCBCDAF3D0ABA35CAD4`
- `nuget-graph.json`, artifact bytes as produced on Windows (before the line-ending normalization of Git): 3567 bytes; SHA-256 `2F78A1CA873E2EA70901F4C67420847420C7B9CA7AF7CBB3B24C0F56DCE1A3C7`
- `nuget-graph.json`, bytes committed in Git (LF): 3505 bytes; SHA-256 `D0035D1A2640EB72C56A4038A60C536088D2367154D78A517C70BB3CFEF27F65`

[CONFIRMED] The artifact bytes and the committed bytes differ only by line endings (Git stores these files with LF). To verify the accepted evidence from Git use the committed hashes; the artifact hashes apply to the files inside the workflow artifacts.

Committed bytes of every JSON file of this directory:

| File | Bytes | SHA-256 |
|---|---:|---|
| `report-windows-2022-original.json` | 3175 | `9A59252C12A207C2039220695CC3CAE118A6E92D4E89D8C516D4B664C38EFCD4` |
| `report-windows-2022-copy.json` | 3180 | `F80624405EAB368A586421634FC81D2D7D445A8862713EC4791357CA6CE7276F` |
| `report-windows-2025-original.json` | 3175 | `2E3503E148A6CE4671227BAA260D7AED99EA638D234A68A6FAF3944C6890DA58` |
| `report-windows-2025-copy.json` | 3180 | `0508D783B8FBB51C4423AD54E4622748F457C118C9E103BF5C56A711046FF390` |
| `packages.lock.json` | 2148 | `C380C7EC969189221C8B521B5218F7426B1ED03F519F6FCBCDAF3D0ABA35CAD4` |
| `nuget-graph.json` | 3505 | `D0035D1A2640EB72C56A4038A60C536088D2367154D78A517C70BB3CFEF27F65` |

Exact resolved package archives:

| Package | Version | Bytes | Raw `.nupkg` SHA-256 |
|---|---:|---:|---|
| `Microsoft.Data.Sqlite` | 10.0.12 | 30207 | `246679D8C6C83FFCF4C8A480066E3F4FC4E051C96B71BEDFD932FE7A5AF1F7D4` |
| `Microsoft.Data.Sqlite.Core` | 10.0.12 | 208143 | `5E8ED353006DADF55D5C7F56D237321C20BB10C786262E6B25526756E1036332` |
| `SQLitePCLRaw.bundle_e_sqlite3` | 2.1.12 | 34064 | `A9A06E6B5A313F6EF3675F91997D012ADEFFE8AA9E1FFD69ED46A4E685B054E1` |
| `SQLitePCLRaw.core` | 2.1.12 | 36016 | `AF06904138FFA6DC95A599133D64D254716D6FACC7543A6B3B910793DAE9DCA5` |
| `SQLitePCLRaw.lib.e_sqlite3` | 2.1.12 | 18762916 | `4A22C02FFCF489792903CF263DEF9FCE27739716883F965F0B5EEFF1637430AC` |
| `SQLitePCLRaw.provider.e_sqlite3` | 2.1.12 | 60225 | `DF2B3271992E5D719186C4671E3CF4F8658097C154CBCD41494AB594C5997595` |

The versioned `nuget-graph.json` also preserves each archive's raw SHA-512, lock-file `contentHash`, source URI and `lockedRestoreVerified=true`.

## Evidence files in this directory

- `report-windows-2022-original.json`
- `report-windows-2022-copy.json`
- `report-windows-2025-original.json`
- `report-windows-2025-copy.json`
- `packages.lock.json`
- `nuget-graph.json`

[CONFIRMED] The two OS-specific lock files were identical, so one exact copy is versioned here. The same applies to the two OS-specific NuGet graph files.

## Prior-run chronology

[CONFIRMED] Earlier failures remain evidence and are not rewritten as PASS:

- run `37370494285`, run #1: attempts 1 and 2 received no Windows runner and executed zero steps;
- run `37372704803`, run #2 attempt 1: no runner, zero steps;
- run `37372704803`, run #2 attempt 2: actual runners; failed because the probe harness accessed an empty sidecar collection unsafely under `Set-StrictMode`, and the dependency-evidence logic compared unlike NuGet hash semantics;
- run `37391452873`, run #3: original and copied provider probes passed on both OS; dependency-evidence/summary logic failed;
- run `37391503600`, run #4: original and copied provider probes passed on both OS; only the manual NuGet content-hash comparison failed;
- run `37392036026`, run #5: first fully successful run after the harness and lock-verification corrections.

Detailed historical IDs are retained in the earlier evidence records and in the Phase 1B handover.

## Decision boundary

[CONFIRMED] `Microsoft.Data.Sqlite` 10.0.12 is technically viable for the tested portable read-only catalog scope on GitHub-hosted Windows Server 2022 and 2025.

[PROPOSED] Adopt `Microsoft.Data.Sqlite` 10.0.12 for V1 and vendor the exact tested win-x64 dependency closure.

[PENDING] Owner/reviewer approval is required before this becomes a new runtime dependency.

[PENDING] Resolve or explicitly accept the native SQLite 3.53.3 versus CLI 3.53.4 patch-version difference before final packaging.

[V] Open one converted SISQUAL catalog read-only on a target/sandbox Windows server before production acceptance.
