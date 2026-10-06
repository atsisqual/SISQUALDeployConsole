# Phase 1B SQLite provider evidence - run 37370494285

**Workflow:** `phase1b-sqlite-provider`
**Workflow ID:** `375792558`
**Run ID:** `37370494285`
**Run number:** `1`
**Event:** `push`
**Branch:** `spike/phase1b-sqlite-managed-provider`
**Commit:** `1109656a846cabc5a43fca45a70705bd426c2375`
**PR:** #36
**Status:** [CONFIRMED] superseded evidence history. This run is not eligible to establish provider compatibility.

## Execution ledger

| Attempt | Job | Job ID | Runner state | Started UTC | Completed UTC | Result |
|---|---|---:|---|---|---|---|
| 1 | windows-2022 | `111966131168` | no runner assigned; `runner_id=0`; zero steps | 2026-10-05T20:33:37Z | 2026-10-05T20:48:39Z | cancelled |
| 1 | windows-2025 | `111966131543` | no runner assigned; `runner_id=0`; zero steps | 2026-10-05T20:33:38Z | 2026-10-05T20:48:39Z | cancelled |
| 2 | windows-2022 | `111971823366` | no runner assigned; `runner_id=0`; zero steps | 2026-10-05T20:50:10Z | 2026-10-05T21:05:12Z | cancelled |
| 2 | windows-2025 | `111971823059` | no runner assigned; `runner_id=0`; zero steps | 2026-10-05T20:50:10Z | 2026-10-05T21:05:12Z | cancelled |

[CONFIRMED] GitHub records `run_attempt=2` on the final run object, `status=completed` and `conclusion=failure`. That run-level failure is the aggregate result of the cancelled jobs; neither attempt executed a provider step.

[CONFIRMED] No workflow artifacts exist for this run.

## Attempt 1

Both jobs waited approximately 15 minutes without receiving a GitHub-hosted runner and were cancelled. This is infrastructure history only and is not a provider PASS or FAIL.

## Attempt 2

The cancelled jobs were re-requested without changing the spike commit. They again received no runner and executed zero steps.

Before this run could become accepted evidence, review also found a defect in the NuGet hash collection: a PackageReference restore does not guarantee that `.nupkg` archives remain in the global package directory, so `nupkgSha256` could be null.

[CONFIRMED] Commit `a1b8e28bc11d518c22e3aaf34a581f5e346a9ba3` changed the hash collection: it reads exact package IDs and versions from `packages.lock.json`, downloads every resolved archive explicitly and records SHA-256 and SHA-512. [CONFIRMED] That commit also verified the raw archive SHA-512 against the lock-file `contentHash`, which is not a valid comparison (see the README of run `37372704803`). That revision is therefore superseded and was never accepted.

## Superseding run

[CONFIRMED] Run `37372704803` used the `a1b8e28` workflow and was not accepted (see its README). The first fully accepted run is `37392036026`: `docs/phase1/evidence/phase1b-sqlite-provider-37392036026/README.md`.

See `docs/phase1/evidence/phase1b-sqlite-provider-37372704803/README.md`.

## Why this run cannot be accepted

Even if this historical run were re-run later, its workflow revision does not satisfy the dependency-evidence rule. Accepted evidence must:

1. execute both Windows jobs;
2. pass original-folder and copied-folder provider probes;
3. preserve the exact resolved NuGet graph;
4. record a non-empty SHA-256 for every resolved package archive;
5. validate `packages.lock.json` with `dotnet restore --locked-mode` on an empty package cache (the raw archive SHA-512 and the lock-file `contentHash` have different semantics: both are recorded, never compared);
6. record the native SQLite version loaded by the provider.

A cancellation before runner assignment is an infrastructure event only and does not change the candidate status.
