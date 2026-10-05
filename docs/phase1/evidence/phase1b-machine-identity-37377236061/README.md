# Phase 1B machine identity evidence - run 37377236061

**Workflow:** `phase1b-machine-identity`
**Workflow ID:** `375831032`
**Run ID:** `37377236061`
**Run number:** `2`
**Run attempt:** `1`
**Event:** `push`
**Branch:** `spike/phase1b-machine-identity-cng`
**Commit:** `3df9c920409b9061cf34f4f88ebdd0f28001809f`
**Created UTC:** `2026-10-05T21:38:56Z`
**Run result:** `failure`
**Classification:** [CONFIRMED] harness parameter-binding failure before any CNG key was created. Not evidence that CNG itself failed.

## Job ledger

| Job | Job ID | Label | Runner | Started UTC | Completed UTC | Result |
|---|---:|---|---|---|---|---|
| Machine A - create and reopen CNG identity | `111989440871` | `windows-2022` | `GitHub Actions 1000000537` (`runner_id=1000000537`) | 2026-10-05T21:38:58Z | 2026-10-05T21:41:34Z | failure |
| Machine B - copied folder has no source private key | `111990541311` | `windows-2025` | none assigned | 2026-10-05T21:41:35Z | 2026-10-05T21:41:35Z | skipped |

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
| Upload copied portable folder and source evidence | action succeeded, but no configured files existed |
| Post checkout | success |

Runner evidence:

- runner version `2.337.0`;
- Windows Server 2022 `10.0.20348` Datacenter;
- runner image `windows-2022`, image version `20260927.320.1`;
- portable PowerShell download, SHA-256 verification and expansion succeeded.

## Exact failure

[CONFIRMED] `SourceCreate` failed on the first `Add-Check` call with:

`Cannot bind argument to parameter 'List' because it is an empty collection.`

The cleanup action hit the same binder error.

Root cause:

- run 1 had been fixed so `$checks` was a real empty `List[object]` rather than `$null`;
- however the `List` parameter was still marked `Mandatory` without `AllowEmptyCollection`;
- the PowerShell parameter binder therefore rejected the valid empty list before the first gate could execute.

[CONFIRMED] The failure happened before `New-MachineKey` was called. No machine CNG key was created and no cryptographic gate ran.

## Artifacts

[CONFIRMED] No artifact was produced. The upload action executed with `if: always()` but reported that no configured evidence paths existed.

No artifact ID exists for this run. None is invented.

## Fix and superseding run

[CONFIRMED] Commit `09de75cb90eedc6015e7125d54da0d25253052c7` adds `AllowEmptyCollection` to the empty-list parameters used by the gate/report harness.

[CONFIRMED] That fix created superseding run `37377769448`, run number `3`, attempt `1`.

This run remains permanent evidence of a harness parameter-binding defect and must not be relabelled as either CNG PASS or CNG FAIL.
