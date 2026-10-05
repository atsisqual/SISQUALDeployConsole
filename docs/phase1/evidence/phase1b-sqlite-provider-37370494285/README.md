# Phase 1B SQLite provider evidence - run 37370494285

**Workflow:** `phase1b-sqlite-provider`
**Branch:** `spike/phase1b-sqlite-managed-provider`
**PR:** #36
**Status:** [PENDING] technical evidence. The accepted compatibility result must come from a completed job that executed the probe.

## Attempt history

### Attempt 1

[CONFIRMED] Both jobs were cancelled before a GitHub-hosted runner was assigned.

- `windows-2022`: cancelled, zero executed steps.
- `windows-2025`: cancelled, zero executed steps.

This attempt is not compatibility evidence and must not be counted as PASS or FAIL for the provider.

### Attempt 2

[CONFIRMED] The failed/cancelled jobs were re-requested without changing the spike code.

[PENDING] At the time this evidence record was created, both `windows-2022` and `windows-2025` jobs were queued and had not executed any step.

## Required artifacts

A completed job is expected to upload these files:

- `report-windows-2022-original.json`
- `report-windows-2022-copy.json`
- `packages.lock-windows-2022.json`
- `nuget-graph-windows-2022.json`
- `report-windows-2025-original.json`
- `report-windows-2025-copy.json`
- `packages.lock-windows-2025.json`
- `nuget-graph-windows-2025.json`

The two operating-system jobs upload separate GitHub Actions artifacts named:

- `phase1b-sqlite-provider-windows-2022`
- `phase1b-sqlite-provider-windows-2025`

## Acceptance rule

[PENDING] This folder must be updated with the reports from a completed accepted run before the provider can be described as technically viable.

The minimum evidence is:

1. both Windows jobs actually execute;
2. both original-folder probes report `overall = PASS`;
3. both copied-folder probes report `overall = PASS`;
4. the read-only, write-rejection, missing-file, multiple-reader and no-mutation checks all PASS;
5. the resolved NuGet graph and native SQLite version are recorded;
6. the package/file hashes needed for future vendoring are preserved.

A workflow cancellation before runner assignment is an infrastructure event only and does not change the candidate status.
