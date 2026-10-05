# Phase 1C operation coordinator evidence ledger

**Branch:** `spike/phase1c-operation-coordinator`
**Base main:** `ad598215fe3ab0bc715a797a37e2bcf9331eaa56`
**Workflow:** `phase1c-operation-coordinator`
**Workflow ID:** `375883256`
**Status:** [CONFIRMED] technical spike viability accepted from run `37388722410` (run number `9`) on Windows 2022 and Windows 2025.

## Evidence rule

An accepted execution records:

- workflow ID, run ID, run number and attempt;
- exact tested commit SHA and event;
- job IDs, runner labels and UTC execution window;
- artifact IDs, sizes, expiry and SHA-256 digests;
- secret-safe JSON reports;
- cancelled/superseded attempts with their real classification.

A run is accepted only when both Windows jobs execute the complete matrix, return `Fatal=null`, return zero failed checks, and the downloaded reports are inspected.

This ledger anchors the accepted technical result to the last runtime-changing commit tested by run 9: `1530858f02440b2be6e97012f6e87ce8818a88dd`. A later commit that changes only documentation/evidence does not invalidate that result. Any later change to the coordinator, harness or workflow requires a new accepted functional run.

## Run history

### Run `37386470742` - technical/harness failure

- run number `1`, attempt `1`;
- tested commit `d62f87d8f71ace21626f39265bb333433b1efc85`;
- conclusion `failure`.

Windows 2022:

- job `112020855786`;
- artifact ID `11380150982`, size `853` bytes;
- digest `sha256:4164916469814a5e5043543f9a3aa5a0e6e38b358d1d7819e334b7ad2e1f9fa2`.

Windows 2025:

- job `112020855313`;
- artifact ID `11379836311`, size `853` bytes;
- digest `sha256:21695ff7bb52ffe98d0a54990f1dd36beea3bc8f0eb2ed021aca75a46de101cc`.

[CONFIRMED] Both jobs stopped after `2 PASS / 0 FAIL` with non-null `Fatal`. A single canonical lock had been pipeline-unwrapped to a scalar under `Set-StrictMode`, and the coordinator then attempted `.Count` on that scalar.

### Run `37387027558` - technical coordinator failure

- run number `2`, attempt `1`;
- tested commit `93fc9649945439bbde574e92aefee0784a000fb1`;
- conclusion `failure`.

Windows 2022:

- job `112022685775`;
- artifact ID `11379517221`, size `856` bytes;
- digest `sha256:4108ade6e2c71b2bc0b1d5ed584a9ae527c76b49040621d137f74aab8f864b76`.

Windows 2025:

- job `112022685569`;
- artifact ID `11379407314`, size `856` bytes;
- digest `sha256:69a81cf7091b9e724703bc46b762699814700c8dfeef33a283ba8199c2e970d3`.

[CONFIRMED] Both jobs stopped after `2 PASS / 0 FAIL` with non-null `Fatal`. Root cause was PowerShell child-scope behavior in the lock helper: caller-local out-values such as operation/result/snapshot/active were assigned in a child scope and did not propagate.

[CONFIRMED] Commit `7c956d6830f93e42808efce6ddde5bc678ee1d90` removed that dependency by returning protected decisions/snapshots/active lists explicitly.

### Runs 3 through 8 - superseded before acceptance

The following runs were cancelled by workflow concurrency after newer corrective commits were pushed. They are supersession evidence, not technical failures and not accepted validation runs:

| Run | Run number | Tested commit | Conclusion |
|---|---:|---|---|
| `37387328062` | 3 | `e9c4de6fbc0484d195e1903c34e0bc71e716826b` | cancelled |
| `37387494783` | 4 | `7c956d6830f93e42808efce6ddde5bc678ee1d90` | cancelled |
| `37387789315` | 5 | `ae7a3ecd4a217f6487f3a5478ffa1a811d26b9d9` | cancelled |
| `37387933850` | 6 | `2806c28f5f8235774b32a31faf59d0c0d1f7a4c3` | cancelled |
| `37388275402` | 7 | `f50d446e9efd1fc73f4d4b80a7879ec36f1911df` | cancelled |
| `37388624154` | 8 | `0e72270f0eb498a5f4246c2660a36fdfe692e45a` | cancelled |

[CONFIRMED] Run 3 was cancelled during the portable PowerShell download before the functional probe. Later superseded runs are retained in GitHub Actions history; none replaces the accepted run 9 evidence.

### Run `37388722410` - accepted technical validation

- run number `9`, attempt `1`;
- event `push`;
- tested commit `1530858f02440b2be6e97012f6e87ce8818a88dd`;
- commit message `test(phase1c): cover PREVIEW/APPLY idempotency semantics`;
- conclusion `success`;
- started `2026-10-05T23:28:53Z` and completed `2026-10-05T23:31:42Z`.

Windows 2022:

- job `112028466619`;
- runner label `windows-2022`;
- report platform `Microsoft Windows NT 10.0.20348.0`;
- PowerShell `7.6.6`;
- artifact `phase1c-operation-coordinator-windows-2022`, ID `11380570202`;
- size `2481` bytes;
- digest `sha256:1d98f017e6a31293b89ade6a7baed38c2e221bf2edec130cf615edec8e37af31`;
- expiry `2027-01-03T23:28:54Z`;
- report `34 PASS / 0 FAIL`, `Fatal=null`.

Windows 2025:

- job `112028466875`;
- runner label `windows-2025`;
- report platform `Microsoft Windows NT 10.0.26100.0`;
- PowerShell `7.6.6`;
- artifact `phase1c-operation-coordinator-windows-2025`, ID `11380385480`;
- size `2480` bytes;
- digest `sha256:d472672eb8204ae1397a3a1c53e811070492811cd2805cea34128149e9e891bd`;
- expiry `2027-01-03T23:28:54Z`;
- report `34 PASS / 0 FAIL`, `Fatal=null`.

[CONFIRMED] Both artifacts were downloaded and the JSON reports were inspected. Both use schema `SISQUAL_PHASE1C_OPERATION_COORDINATOR_V1`; all 34 checks are `PASS` and no raw idempotency key is present.

[CONFIRMED] The accepted matrix covers:

- lowercase plan-fingerprint contract;
- first operation acceptance;
- idempotent replay while running and after completion;
- conflicts when the same idempotency key changes plan or operation mode;
- per-instance and shared-resource locking plus lock release;
- non-conflicting parallel execution;
- PREVIEW without a confirmed APPLY fingerprint;
- concurrent finalization without duplicate `EndInvoke`/dispose errors;
- explicit cooperative cancellation before simulated mutation;
- rejection of cancellation for `NONE` operations;
- shutdown admission closure and cooperative drain;
- shutdown blocking on non-cancellable active work;
- refusal to force-close while active;
- readiness only after drain;
- exact lowercase APPLY plan-fingerprint preservation;
- stable terminal reads;
- clean close after drain;
- absence of raw idempotency tokens from the report.

## Report contract

Schema: `SISQUAL_PHASE1C_OPERATION_COORDINATOR_V1`.

The report may contain operation IDs, plan/request fingerprints, statuses and counts. It must not contain raw idempotency keys, credentials or other secret/token values.

## Historical reference

Reference behavior was inspected read-only at `atsisqual/SISQUALManagementConsole` commit `9756ba956842884fabcf25b82c4fbf1d11cf56bd`.

Relevant files include:

- `src/SISQUAL.Management.Web/Components/Pages/Governance.razor`;
- `src/SISQUAL.Management.Web/Components/Pages/Jobs.razor`;
- `src/SISQUAL.Management.Web/Components/Pages/WebsiteFolderCopyBatchPage.razor`;
- the operations/platform repository layer used by those pages.

The reference console uses database-backed jobs, SQL-owned locks and a worker model. Those persistence/governance mechanisms are historical evidence only and are not copied into ADR-0007's transient local runtime.

## Acceptance

[CONFIRMED] The Phase 1C operation-coordinator spike is technically viable on the tested Windows Server 2022 and Windows Server 2025 GitHub-hosted environments for the behavior represented by the 34-gate matrix.

[PROPOSED] This lifecycle model remains a candidate for the Phase 3 runtime coordinator; this spike does not itself approve the final product architecture or REST surface.

[PENDING] Each real engine still requires explicit cancellation classification, shared-resource lock keys, stale-plan/precondition behavior and destructive backup/restore evidence.

[V] Selected destructive engines still require SISQUAL sandbox/real-topology validation where their dependencies cannot be represented faithfully in GitHub-hosted runners.
