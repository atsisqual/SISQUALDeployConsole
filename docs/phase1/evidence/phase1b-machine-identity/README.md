# Phase 1B machine identity evidence ledger

**Branch:** `spike/phase1b-machine-identity-cng`
**Base main:** `ad598215fe3ab0bc715a797a37e2bcf9331eaa56`
**Workflow:** `phase1b-machine-identity`
**Status:** [PENDING] no Windows execution has been dispatched yet.

## Why there is no run ID yet

[CONFIRMED] PR #36 recorded three GitHub-hosted Windows attempts that never received a runner and executed zero steps. Per owner direction on 2026-10-05, this machine-identity workflow is manual (`workflow_dispatch`) so another AI/reviewer can validate it when Windows capacity is available instead of spending automatic attempts now.

No run ID, attempt ID, job ID or artifact ID exists for this spike until the first manual dispatch. None is invented here.

## Required ledger for every dispatch

For every workflow execution record:

- workflow ID;
- run ID;
- run number;
- `run_attempt`;
- event and triggering actor;
- exact head commit SHA;
- Machine A job ID (`windows-2022`);
- Machine B job ID (`windows-2025`);
- runner labels, runner ID and runner name;
- created, started and completed UTC timestamps;
- conclusion of every job and every step;
- artifact name and GitHub artifact ID;
- retry, cancellation and supersession reason.

A retry caused only by runner infrastructure stays under the same run ID with a new attempt. A code or workflow change creates a new commit and new run; older evidence remains visible.

## Expected artifacts

### `phase1b-machine-identity-machine-a`

- copied replacement portable folder used by Machine A;
- `machine-identity-source.json` (public data only);
- `report-machine-a-create.json`;
- `report-machine-a-reopen.json`.

### `phase1b-machine-identity-machine-b`

- `report-machine-b.json`.

The final evidence record must preserve artifact IDs as well as display names.

## Required PASS checks

Machine A:

- `KEY_ABSENT_BEFORE_CREATE`;
- `MACHINE_SCOPE`;
- `SOFTWARE_KSP`;
- `ECDH_P256`;
- `EXPORT_POLICY_NONE`;
- `PUBLIC_EXPORT`;
- `PRIVATE_EXPORT_PKCS8_BLOCKED`;
- `PRIVATE_EXPORT_CNG_BLOCKED`;
- `CREDENTIAL_MODULE_INTEROP`;
- `KEY_PRESENT_AFTER_FOLDER_REPLACEMENT`;
- `FINGERPRINT_STABLE`.

Machine B:

- `COPIED_FOLDER_HAS_NO_PRIVATE_KEY`;
- `DESTINATION_IDENTITY_DIFFERENT`;
- `PRIVATE_EXPORT_PKCS8_BLOCKED`;
- `PRIVATE_EXPORT_CNG_BLOCKED`;
- `CREDENTIAL_MODULE_INTEROP`;
- `SOURCE_ENTRY_REJECTED_ON_DESTINATION`.

Cleanup should report `KEY_REMOVED` for each VM when the cleanup action runs.

## Acceptance rule

[PENDING] CNG machine identity is not [CONFIRMED] until one named `run ID + run_attempt + commit SHA` actually executes both VMs and all required checks pass.

A job cancellation with no assigned runner or zero executed probe steps is infrastructure evidence only and must never be counted as a CNG PASS or FAIL.

After a successful runner validation, keep the reports in a run-specific subdirectory:

`docs/phase1/evidence/phase1b-machine-identity-<run-id>/`

and update `docs/phase1/phase1b-machine-identity-cng.md` with the exact evidence and remaining [V] items.
