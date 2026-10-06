# Phase 3 runtime catalog factory - accepted evidence

**Status:** [CONFIRMED]
**Date:** 2026-10-06

## Accepted run

- workflow: `phase3-runtime-catalog`
- workflow id: `375949981`
- run: `37404050977`
- run number: `10`
- attempt: `1`
- exact tested commit: `c9905f6a82604073f4c6101f84abd783b8319f7e`
- conclusion: `success`

### Windows Server 2022

- job: `112077513923`
- label: `windows-2022`
- runner: `GitHub Actions 1000000781`
- runner id: `1000000781`
- started: `2026-10-06T02:25:29Z`
- completed: `2026-10-06T02:27:00Z`
- artifact: `phase3-runtime-catalog-windows-2022`
- artifact id: `11385919117`
- artifact digest: `sha256:7c1801fbe1136946f359540a655ecfe975fd85c67c27d856961ae8f96afedcd8`

### Windows Server 2025

- job: `112077514091`
- label: `windows-2025`
- runner: `GitHub Actions 1000000782`
- runner id: `1000000782`
- started: `2026-10-06T02:25:30Z`
- completed: `2026-10-06T02:26:51Z`
- artifact: `phase3-runtime-catalog-windows-2025`
- artifact id: `11386607220`
- artifact digest: `sha256:3a85059e32ed1a6b10bd3a2f163a89b06e8ccb7d384a483a48f881e8570c5596`

## Artifact verification

Both artifacts were downloaded and inspected before this run was accepted. Each report states:

- `status`: `PASS`
- PowerShell: `7.6.6`
- `Microsoft.Data.Sqlite`: `10.0.12`
- native runtime SQLite: `3.53.3`
- fixture/tooling CLI SQLite: `3.53.4`
- passed: `28`
- failed: `0`

All 28 checks are PASS in both reports. The three security gates added after Codex review also pass on both operating systems:

- relative `PackageRoot` is rejected before normalization;
- the provider path guard blocks directory replacement after initialization;
- the catalog path guard blocks directory replacement while a session is open.

The JSON files beside this README preserve the artifact report content with repository-standard LF line endings.

## Repository CI on the same commit

- CI run: `37404050941`
- CI run number: `162`
- job: `112077513239`
- conclusion: `success`
- PowerShell parser: PASS
- ASCII/LF: PASS
- simple secret scan: PASS

Repository `tools-tests` run `37404050966`, run number `62`, also completed `success` on the same commit.

## Security changes covered by this accepted run

[CONFIRMED] Compared with the earlier 25-check run, this accepted commit additionally:

- rejects a relative `PackageRoot` before calling `GetFullPath`;
- accepts only a Windows fixed local drive for `PackageRoot`, rejecting mapped network drives;
- compares the `Microsoft.Data.Sqlite` product version with exact ordinal equality;
- holds non-delete-shared Win32 handles for the provider path and required provider files while native/managed provider loading occurs;
- validates the final path and reparse attributes of those handles;
- holds a path/file guard for each open catalog session until the SQLite connection is disposed;
- verifies by test that provider and catalog directories cannot be renamed/replaced during their guarded lifetime.

## Previous runs

[CONFIRMED] Run `37399118262` (#1) failed before product behavior because of a PowerShell interpolation parser error (`$PathType:`). It is not provider failure evidence.

[CONFIRMED] Run `37401225241` (#3) reached 25/25 functional PASS and then failed only during disposable cleanup because Windows kept the process-loaded `e_sqlite3.dll` locked.

[CONFIRMED] Run `37402464400` (#4) was the first complete 25/25 PASS and was initially accepted. It is now superseded by this 28/28 run after Codex path-hardening findings.

[CONFIRMED] Run `37403483739` (#7) passed the hardened runtime on both Windows versions before the three explicit guard tests were added.

[CONFIRMED] Run `37403821077` (#9) passed all 28 functional gates, but its CI failed only because the branch temporarily modified the historical non-ASCII `docs/decisions-log.md`. The decision log was restored byte-for-byte to `main`, and the approval was moved to the ASCII-only `docs/phase3/sqlite-runtime-adoption.md`.

Run `37404050977` (#10) is the accepted final evidence for the current code and approval-document state.

## Boundaries

[CONFIRMED] The reusable runtime catalog factory is technically validated on disposable Windows Server 2022 and 2025 runners with the accepted provider payload and the path-hardening described above.

[CONFIRMED] Runtime roles remain explicit: `Microsoft.Data.Sqlite` 10.0.12 with native SQLite 3.53.3; separate build/tooling CLI SQLite 3.53.4.

[PENDING] Release packaging must vendor the exact accepted provider payload and include every shipped provider file in the signed package manifest.

[PENDING] Manifest/package integration must record the two SQLite roles semantically in addition to per-file hashes.

[V] Open a converted SISQUAL catalog on the intended target/sandbox Windows machine after package integration.

No production server and no real credential was used by this run.
