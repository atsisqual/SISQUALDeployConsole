# Phase 1C operation coordinator evidence ledger

**Branch:** `spike/phase1c-operation-coordinator`
**Base main:** `ad598215fe3ab0bc715a797a37e2bcf9331eaa56`
**Workflow:** `phase1c-operation-coordinator`
**Workflow ID:** `375883256`
**Status:** [PENDING] runs 1 and 2 exposed coordinator/harness defects; run 3 was superseded before probe execution; corrected run 4 is under execution.

## Evidence rule

An accepted execution must record:

- workflow ID, run ID, run number and attempt;
- exact tested commit SHA and event;
- job IDs, runner labels/names/IDs and UTC times;
- artifact IDs, sizes, expiry and SHA-256 digests;
- exact secret-safe JSON reports;
- any cancelled/superseded attempts with their real classification.

A run is accepted only when both Windows jobs execute the complete matrix and the downloaded reports are inspected. A report with `Fatal` is a technical failure even when `FailCount=0` because the matrix did not complete.

## Run history

### Run `37386470742` - technical/harness failure

- run number `1`, attempt `1`;
- event `push`;
- tested commit `d62f87d8f71ace21626f39265bb333433b1efc85`;
- conclusion `failure`;
- workflow ID `375883256`.

Windows 2022:

- job `112020855786`;
- artifact `phase1c-operation-coordinator-windows-2022`, ID `11380150982`;
- size `853` bytes;
- digest `sha256:4164916469814a5e5043543f9a3aa5a0e6e38b358d1d7819e334b7ad2e1f9fa2`;
- expiry `2027-01-03T23:05:33Z`;
- report schema `SISQUAL_PHASE1C_OPERATION_COORDINATOR_V1`, PowerShell `7.6.6`;
- report reached only `2 PASS / 0 FAIL` and has a non-null `Fatal`.

Windows 2025:

- job `112020855313`;
- artifact `phase1c-operation-coordinator-windows-2025`, ID `11379836311`;
- size `853` bytes;
- digest `sha256:21695ff7bb52ffe98d0a54990f1dd36beea3bc8f0eb2ed021aca75a46de101cc`;
- expiry `2027-01-03T23:05:33Z`.

[CONFIRMED] Windows 2022 artifact was downloaded and inspected. The matrix stopped immediately after coordinator creation because a single canonical lock was pipeline-unwrapped to a scalar under `Set-StrictMode`; `Start-SisqualOperation` then attempted `.Count` on that scalar and raised `PropertyNotFoundException`.

[CONFIRMED] Both Windows jobs failed the operation-coordinator step, so this is a cross-OS coordinator/harness defect, not infrastructure failure. The first correction in commit `93fc9649945439bbde574e92aefee0784a000fb1` forced the canonical lock result into an array and simplified the ordinal dictionary type.

### Run `37387027558` - technical coordinator failure

- run number `2`, attempt `1`;
- event `push`;
- tested commit `93fc9649945439bbde574e92aefee0784a000fb1`;
- conclusion `failure`.

Windows 2022:

- job `112022685775`;
- artifact ID `11379517221`, size `856` bytes;
- digest `sha256:4108ade6e2c71b2bc0b1d5ed584a9ae527c76b49040621d137f74aab8f864b76`;
- expiry `2027-01-03T23:11:16Z`.

Windows 2025:

- job `112022685569`;
- artifact ID `11379407314`, size `856` bytes;
- digest `sha256:69a81cf7091b9e724703bc46b762699814700c8dfeef33a283ba8199c2e970d3`;
- expiry `2027-01-03T23:11:16Z`.

[CONFIRMED] Both jobs reached the functional probe and failed after `2 PASS / 0 FAIL` with non-null `Fatal`. Windows 2022 logs show `PropertyNotFoundException: The property 'OperationId' cannot be found on this object`.

[CONFIRMED] Root cause is PowerShell child-scope behavior in `Invoke-WithCoordinatorLock`: assignments such as operation/result/snapshot/active performed inside the helper scriptblock did not update caller-local variables. Object property mutations did persist, making the bug easy to miss by static inspection.

[CONFIRMED] Commit `7c956d6830f93e42808efce6ddde5bc678ee1d90` removes that dependency: protected code now returns decisions/snapshots/active lists explicitly, while only object-property mutations are used for shared state.

### Run `37387328062` - superseded before probe execution

- run number `3`, attempt `1`;
- tested commit `e9c4de6fbc0484d195e1903c34e0bc71e716826b`;
- conclusion `cancelled` by workflow concurrency after the subsequent coordinator fix;
- windows-2022 job `112023717746`;
- windows-2025 job `112023717895`.

[CONFIRMED] Both jobs were cancelled during the portable PowerShell download. The operation-coordinator probe was skipped. This is supersession evidence only, not a technical coordinator result.

### Run `37387494783` - corrected candidate

- run number `4`, attempt `1`;
- tested commit `7c956d6830f93e42808efce6ddde5bc678ee1d90`;
- status: [PENDING] executing on Windows 2022 and Windows 2025.

## Report contract

Schema: `SISQUAL_PHASE1C_OPERATION_COORDINATOR_V1`.

The report may contain operation IDs, plan/request fingerprints, statuses and counts. It must not contain raw idempotency keys, credentials or other secret/token values.

## Required behavior

The matrix covers:

- idempotent replay while running and after completion;
- conflict on key reuse with a different plan;
- per-instance locking;
- non-conflicting parallel execution;
- shared-resource locking across instances;
- lock release after terminal state;
- cooperative cancellation;
- rejection of cancellation for `NONE` operations;
- shutdown admission closure;
- cooperative cancellation/drain during shutdown;
- shutdown blocking on non-cancellable active work;
- refusal to force-close with active work;
- readiness only after drain;
- exact plan fingerprint preservation;
- raw idempotency-token absence from the report.

## Historical reference

Reference behavior was inspected read-only at `atsisqual/SISQUALManagementConsole` commit `9756ba956842884fabcf25b82c4fbf1d11cf56bd`.

Relevant files include:

- `src/SISQUAL.Management.Web/Components/Pages/Governance.razor`;
- `src/SISQUAL.Management.Web/Components/Pages/Jobs.razor`;
- `src/SISQUAL.Management.Web/Components/Pages/WebsiteFolderCopyBatchPage.razor`;
- the operations/platform repository layer used by those pages.

The reference console uses database-backed jobs, SQL-owned locks and a worker model. Those persistence/governance mechanisms are historical evidence only and are not copied into ADR-0007's transient local runtime.

## Acceptance

[PENDING] No run is accepted yet. The corrected candidate must complete the full matrix on both Windows versions and its downloaded reports must be inspected before technical viability can become `[CONFIRMED]`.
