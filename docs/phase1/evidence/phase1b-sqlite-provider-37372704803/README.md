# Phase 1B SQLite provider evidence - run 37372704803

**Workflow:** `phase1b-sqlite-provider`
**Workflow ID:** `375792558`
**Run ID:** `37372704803`
**Run number:** `2`
**Attempt:** `1`
**Event:** `push`
**Branch:** `spike/phase1b-sqlite-managed-provider`
**Commit:** `a1b8e28bc11d518c22e3aaf34a581f5e346a9ba3`
**PR:** #36
**Created UTC:** `2026-10-05T20:55:17Z`
**Status:** [PENDING] technical evidence. Both Windows jobs must execute before this run can support a compatibility conclusion.

## Why this is the candidate evidence run

[CONFIRMED] The earlier run `37370494285` used the first version of the workflow. Both of its attempts were cancelled without a runner and zero steps executed. A later review also found that its NuGet evidence step could emit a null SHA-256 when the global package cache did not retain a `.nupkg` archive.

[CONFIRMED] Commit `a1b8e28bc11d518c22e3aaf34a581f5e346a9ba3` corrected the evidence path. The workflow now:

1. reads every exact resolved package ID and version from `packages.lock.json`;
2. downloads each resolved `.nupkg` explicitly from the NuGet flat-container source;
3. records the archive SHA-256 and SHA-512;
4. compares the downloaded archive SHA-512 with the lock-file `contentHash`;
5. fails if an archive, SHA-256, lock hash or hash match is missing.

This run is therefore the first run eligible to become the accepted provider evidence.

## Execution ledger

| Attempt | Job | Job ID | Current state | Result |
|---|---|---:|---|---|
| 1 | windows-2022 | `111973546139` | queued; no executed steps at latest check | [PENDING] |
| 1 | windows-2025 | `111973546324` | queued; no executed steps at latest check | [PENDING] |

[CONFIRMED] At the latest recorded check, both jobs were still queued. No workflow artifact existed for this run yet. A queued job is not technical evidence.

When either job changes state, this ledger must be updated with runner identity when available, start/completion timestamps, conclusion, executed step results and artifact IDs.

## Required artifacts

Each operating-system job must upload:

- `report-<os>-original.json`
- `report-<os>-copy.json`
- `packages.lock-<os>.json`
- `nuget-graph-<os>.json`

Expected GitHub Actions artifacts:

- `phase1b-sqlite-provider-windows-2022`
- `phase1b-sqlite-provider-windows-2025`

The final evidence record must also preserve each GitHub artifact ID, not only its display name.

## Acceptance rule

The run can be recorded as [CONFIRMED] technical viability only when all of these are true:

1. both Windows jobs actually execute and complete successfully;
2. both original-folder probes report `overall = PASS`;
3. both copied-folder probes report `overall = PASS`;
4. `HOST_POWERSHELL`, `PROVIDER_PAYLOAD`, `PROVIDER_LOAD`, `FIXTURE_CREATED`, `READ_ONLY_READS`, `WRITE_REJECTED`, `MISSING_FILE_REJECTED`, `MULTIPLE_READ_CONNECTIONS` and `NO_CATALOG_MUTATION` all PASS;
5. the native SQLite version returned by `sqlite_version()` is recorded;
6. the exact resolved NuGet graph is present;
7. every resolved package has a non-empty SHA-256;
8. every downloaded package SHA-512 matches its `packages.lock.json` content hash;
9. the evidence files and their GitHub artifact IDs are copied into this directory before integration.

A failure must stay visible as evidence. It must not be relabelled PASS because the candidate is preferred.

## Re-run and supersession rule

[PROPOSED] Every re-run is recorded explicitly by `run ID + run_attempt + job IDs`. If code or workflow changes, the new push receives a new run ID and the previous run becomes superseded evidence rather than being overwritten.

[PROPOSED] A re-run caused only by runner infrastructure keeps the same run ID and increments `run_attempt`; both attempts remain in the ledger.

[PROPOSED] A candidate is accepted only from one explicitly named run/attempt combination whose exact commit SHA is recorded here.

## Decision boundary

Even if all gates pass:

- [CONFIRMED] may be used only for technical viability on the tested runner images;
- [PROPOSED] remains the status of adopting `Microsoft.Data.Sqlite` 10.0.12;
- [PENDING] owner/reviewer approval is still required for the new runtime dependency;
- [V] one converted SISQUAL catalog should be opened read-only on a target/sandbox Windows machine before production acceptance.
