# Phase 1B machine identity evidence - run 37376755238

**Workflow:** `phase1b-machine-identity`
**Workflow ID:** `375831032`
**Run ID:** `37376755238`
**Run number:** `1`
**Run attempt:** `1`
**Event:** `push`
**Branch:** `spike/phase1b-machine-identity-cng`
**Commit:** `53cccd67cee9cd5e2cd9a9210995a6987c563adf`
**Created UTC:** `2026-10-05T21:34:40Z`
**Completed UTC:** `2026-10-05T21:37:19Z`
**Run result:** `failure`
**Classification:** [CONFIRMED] harness failure before any CNG key was created. Not evidence that CNG itself failed.

## Job ledger

| Job | Job ID | Label | Runner | Started UTC | Completed UTC | Result |
|---|---:|---|---|---|---|---|
| Machine A - create and reopen CNG identity | `111987660696` | `windows-2022` | `GitHub Actions 1000000536` (`runner_id=1000000536`) | 2026-10-05T21:34:43Z | 2026-10-05T21:37:18Z | failure |
| Machine B - copied folder has no source private key | `111988756769` | `windows-2025` | none assigned | 2026-10-05T21:37:19Z | 2026-10-05T21:37:19Z | skipped |

## Machine A step ledger

| Step | Result |
|---|---|
| Set up job | success |
| actions/checkout@v4 | success |
| Download verified portable PowerShell | success |
| Materialize portable folder A | success |
| Create non-exportable machine identity | failure |
| Replace portable folder and reopen same identity | skipped |
| Clean source test key | failure |
| Upload copied portable folder and source evidence | success, but no matching files existed |
| Post checkout | success |

Runner evidence:

- runner version: `2.337.0`;
- Windows Server 2022 `10.0.20348` Datacenter;
- runner image `windows-2022`, image version `20260927.320.1`;
- portable PowerShell download/hash/expand step succeeded.

## Exact failure

[CONFIRMED] `SourceCreate` failed on the first `Add-Check` call with:

`Cannot bind argument to parameter 'List' because it is null.`

The same harness defect also caused the cleanup action to fail on its `Add-Check` call.

Root cause:

- the spike used a helper that returned a newly created but empty `List[object]` through the PowerShell success pipeline;
- PowerShell enumerated the empty collection to zero output objects;
- assignment therefore produced `$null` rather than a list instance.

[CONFIRMED] The failure occurred before `New-MachineKey` was called, so no machine CNG key was created and none of the cryptographic gates executed.

## Artifacts

[CONFIRMED] No artifact was produced. `actions/upload-artifact` ran with `if: always()` but reported that none of the configured paths existed because execution failed before the replacement folder, identity file and reports were created.

No artifact ID therefore exists for this run. None is invented.

## Fix and superseding run

[CONFIRMED] Commit `3df9c920409b9061cf34f4f88ebdd0f28001809f` removes the empty-list pipeline ambiguity by constructing the `List[object]` directly at the call site and suppresses the integer returned by `.Add()`.

It also makes report failure filtering explicit and parenthesizes the P-256 key-size check without changing the test semantics.

[CONFIRMED] The fix created superseding run `37377236061`, run number `2`, attempt `1`.

This run remains permanent evidence of a harness defect. It must not be relabelled as either CNG PASS or CNG FAIL.
