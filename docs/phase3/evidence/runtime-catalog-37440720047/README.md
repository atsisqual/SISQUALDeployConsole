# Phase 3 runtime catalog factory - accepted functional evidence

**Status:** [CONFIRMED]
**Date:** 2026-10-06

## Accepted run

- workflow: `phase3-runtime-catalog`
- workflow id: `375949981`
- run: `37440720047`
- run number: `20`
- exact tested functional commit: `3fa27ffaf5a92001bb8cd14488a54e9f7a49b034`
- conclusion: `success`

### Windows Server 2022

- job: `112193530442`
- artifact: `phase3-runtime-catalog-windows-2022`
- artifact id: `11401450858`
- artifact digest: `sha256:e76db9433ce47ae98c9a59c1f37694016697d7a455d312e5b99778c99d85b204`
- artifact expires: `2027-01-04`
- main suite: 34/34 PASS
- sidecar suite: 6/6 PASS

### Windows Server 2025

- job: `112193530003`
- artifact: `phase3-runtime-catalog-windows-2025`
- artifact id: `11400898174`
- artifact digest: `sha256:e922d4ca2afebf545637bfe68afa900f83550c8738e4a929a768399bceaccc7b`
- artifact expires: `2027-01-04`
- main suite: 34/34 PASS
- sidecar suite: 6/6 PASS

## Repository CI on the same functional commit

- CI run `37440720073`, run #190: SUCCESS
- tools-tests run `37440720136`, run #90: SUCCESS

## Committed reports

The four JSON files in this directory were downloaded directly from the two
GitHub Actions artifacts for run #20 and are preserved here because the
GitHub-hosted artifacts expire.

- `runtime-catalog-windows-2022.json`
- `runtime-catalog-sidecars-windows-2022.json`
- `runtime-catalog-windows-2025.json`
- `runtime-catalog-sidecars-windows-2025.json`

The main reports record PowerShell 7.6.6, `Microsoft.Data.Sqlite` 10.0.12,
native SQLite 3.53.3 and tooling CLI SQLite 3.53.4.

## Evidence boundary

Run #20 is the accepted **functional runtime** evidence.

The current PR head after run #20 contains only test/evidence clarification:
it narrows what the late-sidecar fixture is allowed to claim. It does not
change runtime code. That later head must still execute on Windows before it
can be promoted to executed current-head evidence.

Historical run `37404050977` (#10, 28/28) remains preserved under
`docs/phase3/evidence/runtime-catalog-37404050977/` but is explicitly
superseded by this run for the later runtime implementation.
