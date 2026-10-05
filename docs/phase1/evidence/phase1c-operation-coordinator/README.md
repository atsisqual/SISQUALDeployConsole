# Phase 1C operation coordinator evidence ledger

**Branch:** `spike/phase1c-operation-coordinator`
**Base main:** `ad598215fe3ab0bc715a797a37e2bcf9331eaa56`
**Workflow:** `phase1c-operation-coordinator`
**Workflow ID:** `375883256`
**Status:** [PENDING] run 1 failed in the coordinator/harness; corrected run 2 is under execution.

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

[CONFIRMED] Both Windows jobs failed the operation-coordinator step, so this is a cross-OS coordinator/harness defect, not infrastructure failure. The correction in commit `93fc9649945439bbde574e92aefee0784a000fb1` forces the canonical lock result into an array and simplifies the ordinal dictionary type.

### Run `37387027558` - corrected candidate

- run number `2`, attempt `1`;
- tested commit `93fc9649945439bbde574e92aefee0784a000fb1`;
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
