# Phase 1B machine identity evidence ledger

**Branch:** `spike/phase1b-machine-identity-cng`
**Base main:** `ad598215fe3ab0bc715a797a37e2bcf9331eaa56`
**Workflow:** `phase1b-machine-identity`
**Workflow ID:** `375831032`
**Status:** [CONFIRMED] technical two-VM viability demonstrated by accepted run `37377769448`, attempt `1`, commit `09de75cb90eedc6015e7125d54da0d25253052c7`.

## Trigger model

[CONFIRMED external] GitHub documents that `workflow_dispatch` only receives events when the workflow file exists on the default branch. The pre-merge spike therefore also has a `push` trigger limited to `spike/phase1b-machine-identity-cng` and to the spike/workflow paths. `workflow_dispatch` remains for later use after integration.

## Run history

### Run `37376755238` - harness failure

- run number `1`, attempt `1`, event `push`;
- commit `53cccd67cee9cd5e2cd9a9210995a6987c563adf`;
- created `2026-10-05T21:34:40Z`, completed `2026-10-05T21:37:19Z`;
- Machine A job `111987660696`, runner `GitHub Actions 1000000536` (`runner_id=1000000536`), failure before key creation;
- Machine B job `111988756769`, skipped;
- no artifact ID.

Cause: empty `List[object]` was enumerated to zero pipeline objects and assignment produced `$null`.

Full record: `docs/phase1/evidence/phase1b-machine-identity-37376755238/README.md`.

### Run `37377236061` - second harness failure

- run number `2`, attempt `1`, event `push`;
- commit `3df9c920409b9061cf34f4f88ebdd0f28001809f`;
- created `2026-10-05T21:38:56Z`;
- Machine A job `111989440871`, runner `GitHub Actions 1000000537` (`runner_id=1000000537`), started `2026-10-05T21:38:58Z`, completed `2026-10-05T21:41:34Z`, failure before key creation;
- Machine B job `111990541311`, skipped at `2026-10-05T21:41:35Z`;
- no artifact ID.

Cause: the real empty collection was rejected by the mandatory parameter binder because `AllowEmptyCollection` was missing.

Full record: `docs/phase1/evidence/phase1b-machine-identity-37377236061/README.md`.

### Run `37377769448` - accepted technical evidence

- run number `3`, attempt `1`, event `push`;
- commit `09de75cb90eedc6015e7125d54da0d25253052c7`;
- created `2026-10-05T21:43:35Z`, completed `2026-10-05T21:48:17Z`;
- run conclusion `success`.

Machine A:

- job ID `111991358773`;
- label `windows-2022`;
- runner `GitHub Actions 1000000539`, `runner_id=1000000539`;
- started `2026-10-05T21:43:39Z`, completed `2026-10-05T21:46:24Z`;
- all workflow steps succeeded;
- create, reopen and cleanup reports all `PASS`.

Machine B:

- job ID `111992501724`;
- label `windows-2025`;
- runner `GitHub Actions 1000000542`, `runner_id=1000000542`;
- started `2026-10-05T21:46:27Z`, completed `2026-10-05T21:48:16Z`;
- all workflow steps succeeded;
- destination and cleanup reports both `PASS`.

Artifacts:

- Machine A: ID `11373000213`, `10931` bytes, digest `sha256:a8ffa576c2331b555f9e15cb841c071c14eb058c8fca56863b4203d07fdcb132`, expires `2027-01-03T21:43:35Z`;
- Machine B: ID `11373310252`, `1188` bytes, digest `sha256:fddf5bb8175218c851ed102c90284e82cac922d6ea460bd4b6261ec9e67f4579`, expires `2027-01-03T21:43:35Z`.

Machine B downloaded Machine A artifact ID `11373000213` and GitHub verified the expected SHA-256 before running the copied-folder test.

All required gates passed, including private-export rejection, credential-module interop, stable identity after folder replacement, different destination identity, wrong-machine decrypt rejection and explicit key cleanup.

Full accepted record and versioned reports:

`docs/phase1/evidence/phase1b-machine-identity-37377769448/`

## Accepted technical conclusion

[CONFIRMED] The CNG candidate is technically viable on the tested GitHub-hosted Windows Server 2022 and Windows Server 2025 images at the exact accepted commit.

[CONFIRMED] Replacing the portable folder on Machine A did not replace the machine identity.

[CONFIRMED] Copying the portable folder to Machine B did not transfer the private identity.

[CONFIRMED] `Sisqual.Credentials` interoperated with the non-exportable key and Machine B could not decrypt an entry intended for Machine A.

[CONFIRMED] Test keys were explicitly deleted on both machines.

## Evidence policy

Every workflow execution preserves workflow ID, run ID, run number, attempt, exact commit, job IDs, runner identity, UTC timestamps, step results, artifact names/IDs/digests and retry/supersession reasons.

Infrastructure cancellations and harness failures remain visible and are never rewritten as cryptographic results.

## Remaining boundary

[PROPOSED] Adoption of CNG as the product implementation still requires reviewer/owner acceptance because the credential contract remains proposed.

[PENDING] Final product key name and CNG ACL/application identity must be decided.

[V] Reopen and credential decryption must be validated under the intended real Windows account on a SISQUAL target/sandbox server.
