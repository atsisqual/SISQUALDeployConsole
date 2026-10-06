# Phase 1B SQLite provider evidence - run 37372704803

**Workflow:** `phase1b-sqlite-provider`
**Workflow ID:** `375792558`
**Run ID:** `37372704803`
**Run number:** `2`
**Event:** `push`
**Branch:** `spike/phase1b-sqlite-managed-provider`
**Commit:** `a1b8e28bc11d518c22e3aaf34a581f5e346a9ba3`
**PR:** #36
**Status:** [CONFIRMED] historical evidence. Attempt 1 was infrastructure-only; attempt 2 executed and exposed harness/evidence defects. Neither attempt is accepted provider evidence.

## Attempt 1 - no runner

| Job | Job ID | Runner state | Started UTC | Completed UTC | Result |
|---|---:|---|---|---|---|
| windows-2022 | `111973546139` | no runner assigned; `runner_id=0`; zero steps | 2026-10-05T20:55:18Z | 2026-10-05T21:10:19Z | cancelled |
| windows-2025 | `111973546324` | no runner assigned; `runner_id=0`; zero steps | 2026-10-05T20:55:18Z | 2026-10-05T21:10:19Z | cancelled |

[CONFIRMED] No artifacts were produced. The run-level failure was not a provider result.

## Attempt 2 - first executed Windows attempt

[CONFIRMED] The same run ID was rerun after Windows runners became available.

| Job | Job ID | Runner | Runner ID | Started UTC | Completed UTC | Result |
|---|---:|---|---:|---|---|---|
| windows-2022 | `112035154375` | `GitHub Actions 1000000644` | `1000000644` | 2026-10-05T23:50:59Z | 2026-10-05T23:54:59Z | failure |
| windows-2025 | `112035154659` | `GitHub Actions 1000000643` | `1000000643` | 2026-10-05T23:51:01Z | 2026-10-05T23:54:39Z | failure |

Artifacts:

| OS | Artifact ID | Size | Digest |
|---|---:|---:|---|
| windows-2022 | `11381246946` | 2257 bytes | `sha256:afaab5d7c7e1838ec4576e2c6c45ea590e76c96a540748a4199ae1e450562b9d` |
| windows-2025 | `11380983142` | 2254 bytes | `sha256:7b8b5216a10dc7851d5b7675b4779d4d0ffb65838bc41e7186b6399851c34e6c` |

[CONFIRMED] Both jobs successfully restored/materialized the provider and verified the pinned portable PowerShell/SQLite CLI before entering the probe.

[CONFIRMED] The probe reached working provider behavior but failed in its own post-check because `Set-StrictMode` made an empty sidecar result unsafe when accessed as a scalar property. This was corrected in commit `6fa275a180d48271cdc2e98dff86f638e805bded`.

[CONFIRMED] The dependency-evidence step also used an invalid assumption: the raw downloaded `.nupkg` SHA-512 was treated as equivalent to NuGet's lock-file `contentHash`. That is not the correct verification model. The final workflow instead uses NuGet `--locked-mode` against an isolated empty cache and records raw archive hashes separately.

[CONFIRMED] The summary step also contained a PowerShell interpolation bug around a variable followed by `:`; later workflow revisions corrected it.

## Supersession

This run remains important negative evidence, but it is superseded for acceptance by run `37392036026` / attempt `1`, which completed all provider and dependency-evidence steps successfully on both Windows images.

The accepted evidence is under:

`docs/phase1/evidence/phase1b-sqlite-provider-37392036026/`
