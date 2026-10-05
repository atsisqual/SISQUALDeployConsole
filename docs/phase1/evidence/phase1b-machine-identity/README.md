# Phase 1B machine identity evidence ledger

**Branch:** `spike/phase1b-machine-identity-cng`
**Base main:** `ad598215fe3ab0bc715a797a37e2bcf9331eaa56`
**Workflow:** `phase1b-machine-identity`
**Workflow ID:** `375831032`
**Status:** [PENDING] corrected run `37377236061` is executing.

## Trigger model

[CONFIRMED] PR #36 recorded three GitHub-hosted Windows attempts that never received a runner and executed zero steps.

[CONFIRMED external] GitHub documents that `workflow_dispatch` only receives events when the workflow file exists on the default branch. Because this spike must be validated before merge, the workflow also has a `push` trigger limited to `spike/phase1b-machine-identity-cng` and only the spike/workflow paths. `workflow_dispatch` remains for later use after integration.

## Run history

### Run `37376755238` - preserved harness failure

- run number: `1`;
- attempt: `1`;
- event: `push`;
- commit: `53cccd67cee9cd5e2cd9a9210995a6987c563adf`;
- created: `2026-10-05T21:34:40Z`;
- conclusion: `failure`.

Machine A:

- job ID `111987660696`;
- `windows-2022`;
- runner `GitHub Actions 1000000536`, `runner_id=1000000536`;
- started `2026-10-05T21:34:43Z`;
- completed `2026-10-05T21:37:18Z`;
- failed before CNG key creation because the empty check-list helper returned `$null` through PowerShell pipeline enumeration.

Machine B:

- job ID `111988756769`;
- label `windows-2025`;
- no runner assigned;
- skipped because Machine A failed.

No artifact ID exists. The upload step ran but found no matching files.

Full record: `docs/phase1/evidence/phase1b-machine-identity-37376755238/README.md`.

### Run `37377236061` - corrected harness

- run number: `2`;
- attempt: `1`;
- event: `push`;
- commit: `3df9c920409b9061cf34f4f88ebdd0f28001809f`;
- created: `2026-10-05T21:38:56Z`;
- current status: [PENDING] in progress at latest check.

Machine A:

- job ID `111989440871`;
- `windows-2022`;
- runner `GitHub Actions 1000000537`, `runner_id=1000000537`;
- started `2026-10-05T21:38:58Z`;
- at latest check, setup and checkout passed and the verified PowerShell download step was running.

Machine B job ID does not exist yet at this recorded point because it is materialized after the Machine A dependency. No ID is invented.

## Required ledger for every execution

For every workflow execution record preserve:

- workflow ID;
- run ID and run number;
- every `run_attempt`;
- event and triggering actor;
- exact head commit SHA;
- Machine A and Machine B job IDs;
- runner labels, runner ID and runner name;
- created, started and completed UTC timestamps;
- conclusion of every job and every step;
- artifact names and GitHub artifact IDs;
- retry, cancellation and supersession reason.

A retry caused only by runner infrastructure stays under the same run ID with a new attempt. A code/workflow change creates a new commit and a new run; older evidence remains visible.

## Expected artifacts

### `phase1b-machine-identity-machine-a`

- copied replacement portable folder;
- `machine-identity-source.json` (public data only);
- `report-machine-a-create.json`;
- `report-machine-a-reopen.json`;
- `report-machine-a-cleanup.json`.

### `phase1b-machine-identity-machine-b`

- `report-machine-b.json`;
- `report-machine-b-cleanup.json`.

The final record preserves artifact IDs as well as display names.

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

Cleanup must report `KEY_REMOVED` for each VM.

## Acceptance rule

[PENDING] CNG machine identity is not [CONFIRMED] until one named `run ID + run_attempt + commit SHA` executes both VMs and every required check passes.

A cancellation with no runner or zero probe steps is infrastructure evidence only. A harness failure before key creation is a harness FAIL only. Neither may be relabelled as a CNG technical result.

After an accepted run, preserve its reports under:

`docs/phase1/evidence/phase1b-machine-identity-<run-id>/`

and update `docs/phase1/phase1b-machine-identity-cng.md` with exact evidence and remaining [V] items.
