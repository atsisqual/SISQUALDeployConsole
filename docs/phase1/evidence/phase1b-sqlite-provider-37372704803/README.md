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
**Completed UTC:** `2026-10-05T21:10:20Z`
**Status:** [CONFIRMED] infrastructure cancellation. This attempt is not technical compatibility evidence.

## Why this is the corrected-workflow run

[CONFIRMED] The earlier run `37370494285` used the first version of the workflow. Both of its attempts were cancelled without a runner and zero steps executed. A later review also found that its NuGet evidence step could emit a null SHA-256 when the global package cache did not retain a `.nupkg` archive.

[CONFIRMED] Commit `a1b8e28bc11d518c22e3aaf34a581f5e346a9ba3` corrected the evidence path. The workflow now:

1. reads every exact resolved package ID and version from `packages.lock.json`;
2. downloads each resolved `.nupkg` explicitly from the NuGet flat-container source;
3. records the archive SHA-256 and SHA-512;
4. compares the downloaded archive SHA-512 with the lock-file `contentHash`;
5. fails if an archive, SHA-256, lock hash or hash match is missing.

This run remains the first run with the corrected workflow, but attempt 1 cannot establish compatibility because neither job received a runner.

## Execution ledger

| Attempt | Job | Job ID | Runner state | Started UTC | Completed UTC | Result |
|---|---|---:|---|---|---|---|
| 1 | windows-2022 | `111973546139` | no runner assigned; `runner_id=0`; zero steps | 2026-10-05T20:55:18Z | 2026-10-05T21:10:19Z | cancelled |
| 1 | windows-2025 | `111973546324` | no runner assigned; `runner_id=0`; zero steps | 2026-10-05T20:55:18Z | 2026-10-05T21:10:19Z | cancelled |

[CONFIRMED] GitHub records the run as `status=completed`, `conclusion=failure`. That run-level failure is the aggregate result of the cancelled jobs; no provider step executed, so this is not a technical provider failure.

[CONFIRMED] No workflow artifacts were produced by this attempt.

## Required artifacts for future validation

A successful executed attempt must upload:

- `report-<os>-original.json`
- `report-<os>-copy.json`
- `packages.lock-<os>.json`
- `nuget-graph-<os>.json`

Expected GitHub Actions artifacts:

- `phase1b-sqlite-provider-windows-2022`
- `phase1b-sqlite-provider-windows-2025`

The final evidence record must also preserve each GitHub artifact ID, not only its display name.

## Acceptance rule

The provider can be recorded as [CONFIRMED] technically viable only when all of these are true:

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

## Handoff

[CONFIRMED] Per owner direction on 2026-10-05, no additional runner retry is being spent on this spike now. Three recorded attempts across runs `37370494285` and `37372704803` all ended without a Windows runner and with zero executed steps.

[PENDING] Another AI/reviewer may re-run the corrected workflow later. The next accepted attempt must receive actual GitHub-hosted runners and execute the probe before any compatibility conclusion can be made.

This handoff is caused by runner infrastructure and is not a rejection of `Microsoft.Data.Sqlite`.

## Decision boundary

Even if a later attempt passes all gates:

- [CONFIRMED] may be used only for technical viability on the tested runner images;
- [PROPOSED] remains the status of adopting `Microsoft.Data.Sqlite` 10.0.12;
- [PENDING] owner/reviewer approval is still required for the new runtime dependency;
- [V] one converted SISQUAL catalog should be opened read-only on a target/sandbox Windows machine before production acceptance.
