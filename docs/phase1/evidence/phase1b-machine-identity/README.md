# Phase 1B machine identity evidence ledger

**Branch:** `spike/phase1b-machine-identity-cng`
**Base main:** `ad598215fe3ab0bc715a797a37e2bcf9331eaa56`
**Workflow:** `phase1b-machine-identity`
**Workflow ID:** `375831032`
**Current run ID:** `37376755238`
**Run number:** `1`
**Run attempt:** `1`
**Event:** `push`
**Head commit:** `53cccd67cee9cd5e2cd9a9210995a6987c563adf`
**Created UTC:** `2026-10-05T21:34:40Z`
**Status:** [PENDING] first Windows execution is in progress.

## Why the trigger changed

[CONFIRMED] PR #36 recorded three GitHub-hosted Windows attempts that never received a runner and executed zero steps.

[CONFIRMED external] GitHub documents that `workflow_dispatch` only receives events when the workflow file exists on the default branch. Because this spike must be validated before merge, the workflow also has a `push` trigger limited to `spike/phase1b-machine-identity-cng` and only the spike/workflow paths. `workflow_dispatch` remains for later use after integration.

## Current execution ledger

### Run `37376755238`, attempt `1`

| Job | Job ID | Label | Runner | Created UTC | Started UTC | State |
|---|---:|---|---|---|---|---|
| Machine A - create and reopen CNG identity | `111987660696` | `windows-2022` | `GitHub Actions 1000000536` (`runner_id=1000000536`) | 2026-10-05T21:34:41Z | 2026-10-05T21:34:43Z | in progress at latest check |
| Machine B - copied folder has no source private key | [PENDING] | `windows-2025` | [PENDING] | [PENDING] | [PENDING] | created only after Machine A succeeds |

[CONFIRMED] At the latest recorded check, Machine A had received a real GitHub-hosted runner. `Set up job` and `actions/checkout@v4` had succeeded; `Download verified portable PowerShell` was in progress. No CNG compatibility result is claimed yet.

[PENDING] Machine B has no job ID yet because the workflow uses `needs: machine-a`; GitHub will materialize it after Machine A reaches the dependency point. No ID is invented.

## Required ledger for every execution

For every workflow execution record:

- workflow ID;
- run ID;
- run number;
- `run_attempt`;
- event and triggering actor;
- exact head commit SHA;
- Machine A and Machine B job IDs;
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
- `report-machine-a-reopen.json`;
- `report-machine-a-cleanup.json`.

### `phase1b-machine-identity-machine-b`

- `report-machine-b.json`;
- `report-machine-b-cleanup.json`.

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

Cleanup must report `KEY_REMOVED` for each VM when the cleanup action runs.

## Acceptance rule

[PENDING] CNG machine identity is not [CONFIRMED] until one named `run ID + run_attempt + commit SHA` actually executes both VMs and all required checks pass.

A job cancellation with no assigned runner or zero executed probe steps is infrastructure evidence only and must never be counted as a CNG PASS or FAIL.

After a successful runner validation, keep the reports in a run-specific subdirectory:

`docs/phase1/evidence/phase1b-machine-identity-<run-id>/`

and update `docs/phase1/phase1b-machine-identity-cng.md` with the exact evidence and remaining [V] items.
