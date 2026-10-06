# Handover - Phase 3 runtime catalog factory

**Date:** 2026-10-06
**PR:** #54 `feat(phase3): add read-only runtime catalog factory`
**Branch:** `feat/phase3-runtime-catalog`
**Status:** [CONFIRMED] technical implementation validated; review of the final documentation head may still be pending. No merge requested.

## 1. What this PR does

This PR is the first product implementation of the reusable read-only SQLite catalog factory. It is deliberately independent of the open runtime-bootstrap work and does not implement manifest signature verification, credentials, Pode, UI or engines.

Product module: `runtime/Sisqual.Runtime.Catalog.psm1`.

It loads the accepted managed provider from the portable package and opens only an existing per-machine catalog in read-only/private-cache/non-pooled mode, with `PRAGMA query_only=ON` and integrity/metadata validation.

## 2. Dependency decision

[CONFIRMED] Use these roles explicitly:

- `Microsoft.Data.Sqlite` 10.0.12;
- provider native SQLite 3.53.3;
- separate CLI/tooling SQLite 3.53.4.

Phase 1B evidence is run `37392036026`. No provider binaries are committed by #54; CI materializes the exact locked provider payload only for validation. Release packaging must vendor that accepted payload.

## 3. Accepted product evidence

Workflow: `phase3-runtime-catalog`
Workflow id: `375949981`
Run: `37402464400`
Run number: `4`
Attempt: `1`
Exact tested product commit: `1c8316a47d9d61fef4a427834d3b6f87c7e6ca7a`
Conclusion: SUCCESS

Windows Server 2022:
- job `112072458381`;
- runner `GitHub Actions 1000000758`, runner id `1000000758`;
- artifact `11385304398`;
- digest `sha256:75b873355b73bc77e5b9af615efcc30cc5835768c5a8864f4a40c661af070b3a`.

Windows Server 2025:
- job `112072458133`;
- runner `GitHub Actions 1000000757`, runner id `1000000757`;
- artifact `11386135630`;
- digest `sha256:ec292b8d71f3b6fd5709ed7b750c6ca0436947cb14d16668021e443e6630da79`.

Both artifact reports were downloaded and inspected: 25/25 PASS, 0 FAIL, PowerShell 7.6.6, provider 10.0.12, native SQLite 3.53.3 and CLI SQLite 3.53.4.

CI on the same product commit:
- run `37402464402`, run #156;
- job `112072457412`;
- parser, ASCII/LF and secret scan PASS.

Repository `tools-tests` run `37402464397`, run #56, also passed.

Evidence directory: `docs/phase3/evidence/runtime-catalog-37402464400/`.

## 4. Failure history that must remain preserved

[CONFIRMED] Run `37399118262` (#1) failed before product behavior because of a PowerShell interpolation parser bug (`$PathType:`). Do not classify it as provider failure.

[CONFIRMED] Run `37401225241` (#3) reached all 25 functional gates successfully and then failed during disposable cleanup because Windows kept `e_sqlite3.dll` locked after native load. The runtime was not changed to hide this. Test cleanup only tolerates that exact process-lifetime DLL lock; other cleanup errors still fail.

Run `37402464400` (#4) is the accepted full run.

## 5. Security and correctness boundaries

The factory:
- rejects provider/catalog paths outside `PackageRoot`;
- rejects existing reparse-point components;
- loads required provider files from the package tree;
- uses `Mode=ReadOnly`, `Cache=Private`, `Pooling=false`;
- enables and verifies `query_only`;
- verifies native SQLite 3.53.3;
- runs `integrity_check`;
- requires exactly one `catalog_meta` row;
- compares ServerCode/source kind/source reference case-sensitively where required;
- uses parameterized SQL for metadata lookup;
- never accepts raw SQL from a browser;
- creates no database when the catalog is missing;
- creates no WAL/SHM/journal sidecars in the accepted tests.

The factory does NOT authenticate the package manifest. It assumes a future bootstrap has already verified manifest signature/hash and supplies authenticated expected catalog metadata.

## 6. Remaining work

[PENDING] Integrate the factory after the signed-manifest verification gate in the runtime bootstrap.

[PENDING] Vendor the exact accepted provider payload in release packaging and list/hash every provider file in the signed manifest.

[PENDING] Add a semantic manifest/package record for both SQLite roles in addition to file hashes.

[V] Open a converted SISQUAL catalog on a target/sandbox Windows machine after package integration.

## 7. What not to do

- Do not redo the Phase 1B provider spike.
- Do not change to one SQLite version merely to make 3.53.3 and 3.53.4 visually match; their roles are explicit.
- Do not add `dotnet`/NuGet as an operator runtime dependency.
- Do not let the catalog factory verify a browser-supplied path/SQL contract instead of the package/bootstrap contract.
- Do not weaken read-only, `query_only`, path, integrity or metadata gates to simplify bootstrap integration.
- Do not treat the process-lifetime native DLL lock as a product failure; it is expected once the native provider is loaded.
- Do not merge #54 without owner delegation.

## 8. Resume checklist

1. Read current `AGENTS.md` and `docs/decisions-log.md`.
2. Confirm the current #54 head; another agent may have advanced documentation/review state.
3. Check the Codex review requested on the final implementation/documentation head and address only valid findings.
4. Confirm CI remains green after documentation-only commits.
5. Preserve run `37402464400` as the accepted functional evidence; docs-only heads do not supersede it.
6. Keep final real converted-catalog validation marked `[V]` until it actually runs on SISQUAL target/sandbox Windows.
