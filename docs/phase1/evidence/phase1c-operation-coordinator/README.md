# Phase 1C operation coordinator evidence ledger

**Branch:** `spike/phase1c-operation-coordinator`
**Base main:** `ad598215fe3ab0bc715a797a37e2bcf9331eaa56`
**Workflow:** `phase1c-operation-coordinator`
**Status:** [PENDING] waiting for an executed two-OS Windows run.

## Evidence rule

An accepted execution must record:

- workflow ID, run ID, run number and attempt;
- exact tested commit SHA and event;
- job IDs, runner labels/names/IDs and UTC times;
- artifact IDs, sizes, expiry and SHA-256 digests;
- exact secret-safe JSON reports;
- any cancelled/superseded attempts with their real classification.

A run is accepted only when both Windows jobs execute the complete matrix and the downloaded reports are inspected.

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

[PENDING] No technical PASS/FAIL is recorded here until the functional workflow executes the probes. Infrastructure cancellation or supersession is not a coordinator technical failure unless a gate actually ran and failed.
