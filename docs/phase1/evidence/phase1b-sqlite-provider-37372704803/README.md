# Phase 1B SQLite provider evidence - run 37372704803

**Workflow:** `phase1b-sqlite-provider`
**Branch:** `spike/phase1b-sqlite-managed-provider`
**PR:** #36
**Commit:** `a1b8e28bc11d518c22e3aaf34a581f5e346a9ba3`
**Status:** [PENDING] technical evidence. Both Windows jobs must execute before this run can support a compatibility conclusion.

## Why this is the candidate evidence run

[CONFIRMED] The earlier run `37370494285` used the first version of the workflow. Its first attempt was cancelled before runner assignment. A later review also found that its NuGet evidence step could emit a null SHA-256 when the global package cache did not retain a `.nupkg` archive.

[CONFIRMED] Commit `a1b8e28bc11d518c22e3aaf34a581f5e346a9ba3` corrected the evidence path. The workflow now:

1. reads every exact resolved package ID and version from `packages.lock.json`;
2. downloads each resolved `.nupkg` explicitly from the NuGet flat-container source;
3. records the archive SHA-256 and SHA-512;
4. compares the downloaded archive SHA-512 with the lock-file `contentHash`;
5. fails if an archive, SHA-256, lock hash or hash match is missing.

This run is therefore the first run eligible to become the accepted provider evidence.

## Required jobs

- `SQLite managed provider on windows-2022`
- `SQLite managed provider on windows-2025`

[PENDING] At creation of this record the run was queued. A queued job is not technical evidence.

## Required artifacts

Each operating-system job must upload:

- `report-<os>-original.json`
- `report-<os>-copy.json`
- `packages.lock-<os>.json`
- `nuget-graph-<os>.json`

Expected GitHub Actions artifacts:

- `phase1b-sqlite-provider-windows-2022`
- `phase1b-sqlite-provider-windows-2025`

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
9. the evidence files are copied into this directory before integration.

A failure must stay visible as evidence. It must not be relabelled PASS because the candidate is preferred.

## Decision boundary

Even if all gates pass:

- [CONFIRMED] may be used only for technical viability on the tested runner images;
- [PROPOSED] remains the status of adopting `Microsoft.Data.Sqlite` 10.0.12;
- [PENDING] owner/reviewer approval is still required for the new runtime dependency;
- [V] one converted SISQUAL catalog should be opened read-only on a target/sandbox Windows machine before production acceptance.
