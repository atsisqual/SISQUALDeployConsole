# Phase 3 runtime catalog factory - accepted evidence

**Status:** [CONFIRMED]
**Date:** 2026-10-06

## Accepted run

- workflow: `phase3-runtime-catalog`
- workflow id: `375949981`
- run: `37402464400`
- run number: `4`
- attempt: `1`
- exact tested commit: `1c8316a47d9d61fef4a427834d3b6f87c7e6ca7a`
- conclusion: `success`

### Windows Server 2022

- job: `112072458381`
- label: `windows-2022`
- runner: `GitHub Actions 1000000758`
- runner id: `1000000758`
- started: `2026-10-06T02:05:51Z`
- completed: `2026-10-06T02:06:58Z`
- artifact: `phase3-runtime-catalog-windows-2022`
- artifact id: `11385304398`
- artifact digest: `sha256:75b873355b73bc77e5b9af615efcc30cc5835768c5a8864f4a40c661af070b3a`

### Windows Server 2025

- job: `112072458133`
- label: `windows-2025`
- runner: `GitHub Actions 1000000757`
- runner id: `1000000757`
- started: `2026-10-06T02:05:52Z`
- completed: `2026-10-06T02:07:00Z`
- artifact: `phase3-runtime-catalog-windows-2025`
- artifact id: `11386135630`
- artifact digest: `sha256:ec292b8d71f3b6fd5709ed7b750c6ca0436947cb14d16668021e443e6630da79`

## Artifact verification

Both artifacts were downloaded and inspected. Each contains one report JSON. Both reports state:

- `status`: `PASS`
- PowerShell: `7.6.6`
- `Microsoft.Data.Sqlite`: `10.0.12`
- native runtime SQLite: `3.53.3`
- fixture/tooling CLI SQLite: `3.53.4`
- passed: `25`
- failed: `0`

All 25 checks are `PASS` in both reports:

1. provider version pin is 10.0.12;
2. native runtime SQLite pin is 3.53.3;
3. factory defaults are read-only private-cache with pooling disabled;
4. provider path outside package is rejected;
5. copied provider payload initializes from package tree;
6. valid catalog opens with `query_only` enabled;
7. native SQLite version is exact;
8. catalog metadata is exact and case-sensitive;
9. parameterized catalog reads work;
10. write through runtime catalog session is rejected;
11. catalog bytes remain unchanged;
12. read-only factory creates no SQLite sidecars;
13. missing catalog is rejected without creation;
14. missing catalog was not created;
15. catalog path outside package is rejected;
16. metadata ServerCode mismatch fails closed;
17. metadata schema version mismatch fails closed;
18. metadata source kind mismatch fails closed;
19. metadata source reference mismatch fails closed;
20. malformed `built_at_utc` fails closed;
21. multiple `catalog_meta` rows fail closed;
22. catalog path through junction is rejected;
23. twenty simultaneous read-only sessions open successfully;
24. catalog stays byte-identical after repeated sessions;
25. repeated sessions still create no sidecars.

The exact reports are versioned beside this README.

## Repository CI on the accepted commit

- CI run: `37402464402`
- CI run number: `156`
- job: `112072457412`
- conclusion: `success`
- PowerShell parser: PASS
- ASCII/LF: PASS
- simple secret scan: PASS

Repository `tools-tests` run `37402464397`, run number `56`, also completed `success` on the same commit.

## Superseded failures

[CONFIRMED] Run `37399118262` (run #1) did not reach product behavior because the new module had a PowerShell interpolation parser error (`$PathType:`). The provider materialization and pinned runtime downloads succeeded. This is a harness/code parse failure and not SQLite/provider evidence.

[CONFIRMED] Run `37401225241` (run #3) reached the full runtime catalog test and all 25 functional checks passed, but the job failed during disposable test cleanup because Windows kept the intentionally process-loaded `e_sqlite3.dll` locked until `pwsh` exits. The product module was not changed for this condition; the test cleanup was made best-effort only for that exact process-lifetime native DLL lock.

Run `37402464400` is the first accepted full result after those corrections.

## Boundaries

[CONFIRMED] The reusable runtime catalog factory is technically validated on disposable Windows Server 2022 and 2025 runners with the accepted provider payload.

[CONFIRMED] The runtime roles are explicit in this implementation: `Microsoft.Data.Sqlite` 10.0.12 with native SQLite 3.53.3; the separate build/test CLI is SQLite 3.53.4.

[PENDING] Release packaging must vendor the exact accepted provider payload and include every shipped provider file in the signed package manifest.

[PENDING] The manifest/package integration still needs a semantic record of the two SQLite roles in addition to per-file hashes.

[V] Open a converted SISQUAL catalog on the intended target/sandbox Windows machine after package integration.

No production server and no real credential was used by this run.
