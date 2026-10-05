# Phase 1B SQLite provider evidence - run 37370494285

**Workflow:** `phase1b-sqlite-provider`
**Branch:** `spike/phase1b-sqlite-managed-provider`
**PR:** #36
**Status:** [CONFIRMED] superseded evidence history. This run is not eligible to establish provider compatibility.

## Attempt history

### Attempt 1

[CONFIRMED] Both jobs were cancelled before a GitHub-hosted runner was assigned.

- `windows-2022`: cancelled, zero executed steps.
- `windows-2025`: cancelled, zero executed steps.

This attempt is not compatibility evidence and must not be counted as PASS or FAIL for the provider.

### Attempt 2

[CONFIRMED] The failed/cancelled jobs were re-requested without changing the spike code.

[CONFIRMED] Before this run could become accepted evidence, review found a defect in the NuGet hash collection: a PackageReference restore does not guarantee that `.nupkg` archives remain in the global package directory, so `nupkgSha256` could be null.

The defect was fixed in commit `a1b8e28bc11d518c22e3aaf34a581f5e346a9ba3`. This older run remains in the repository only to preserve the evidence history.

## Superseding run

[CONFIRMED] Run `37372704803` is the first run eligible for acceptance because it uses the corrected package-evidence workflow.

See:

`docs/phase1/evidence/phase1b-sqlite-provider-37372704803/README.md`

## Why this run cannot be accepted

Even if a later attempt of this old run were to execute the provider probe successfully, its workflow revision does not satisfy the required dependency-evidence rule. The accepted run must:

1. execute both Windows jobs;
2. pass original-folder and copied-folder provider probes;
3. preserve the exact resolved NuGet graph;
4. record a non-empty SHA-256 for every resolved package archive;
5. verify each archive SHA-512 against the lock-file `contentHash`;
6. record the native SQLite version loaded by the provider.

A workflow cancellation before runner assignment is an infrastructure event only and does not change the candidate status.
