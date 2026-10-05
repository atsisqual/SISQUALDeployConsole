# Phase 1B - Machine identity with non-exportable CNG key

**Date:** 2026-10-05
**Status:** [PROPOSED] spike ready for validation. No product implementation or ADR decision is made by this document.
**Branch:** `spike/phase1b-machine-identity-cng`
**Base:** `main` at `ad598215fe3ab0bc715a797a37e2bcf9331eaa56`.

Tags: [CONFIRMED] supported by approved repository evidence; [PROPOSED] implementation/design candidate; [PENDING] still needs a decision or executed evidence; [V] requires validation on a target/sandbox machine.

## 1. Why this spike exists

[CONFIRMED] ADR-0007 requires the machine private key to live outside the replaceable portable folder and to be non-exportable. Replacing or copying the portable folder must not carry a usable machine identity to another machine.

[CONFIRMED] `contracts/credential-package.md` binds a credential package to `target.serverCode` plus the SHA-256 fingerprint of the machine public key. The machine public key is manually carried to the credential tool; the private key never leaves the target machine.

[CONFIRMED] Owner answer Q2 selected ECDH P-256 for credential entries, with SHA-256 fingerprints. The existing `Sisqual.Credentials` module already accepts an `ECDiffieHellman` object for decryption specifically so a non-exportable CNG key can be used.

[CONFIRMED] The Phase 1 roadmap requires two VMs and a copied-folder test before the machine-key implementation is selected.

## 2. Candidate under test

[PROPOSED] Windows CNG, `Microsoft Software Key Storage Provider`, with an ECDH P-256 key in the machine key store and `CngExportPolicies.None`.

The spike does not choose the final product key name or ACL. Its test key name is unique per GitHub run and exists only for the duration of the runner job.

[PROPOSED] CNG is preferred over a DPAPI-wrapped exportable key because it directly models the approved requirement: a persisted private key that is not part of the portable files and whose private material cannot be exported through the normal cryptographic API.

[PENDING] DPAPI is a fallback only if CNG fails a required gate or cannot be operated under the final application identity.

## 3. Spike files

- `spikes/phase1B/machine-identity/Invoke-MachineIdentityCngSpike.ps1`
- `.github/workflows/phase1b-machine-identity.yml`

The workflow is `workflow_dispatch` only. It is intentionally not triggered by push because PR #36 recorded three Windows jobs/attempts that never received a GitHub-hosted runner. A reviewer or other AI can dispatch this spike when Windows capacity is available.

No real key, credential or secret is committed. Test keys and random marker bytes exist only inside disposable runner VMs.

## 4. Machine A gates

The first VM is `windows-2022` and runs the pinned portable PowerShell 7.6.6 after SHA-256 verification.

| Gate | Required result |
|---|---|
| Key absent | the unique CNG key name does not pre-exist |
| Machine scope | CNG reports `IsMachineKey = true` |
| Provider | Microsoft Software Key Storage Provider |
| Algorithm | ECDH P-256 / 256-bit curve |
| Export policy | `None` |
| Public export | SubjectPublicKeyInfo export succeeds |
| PKCS#8 private export | rejected |
| CNG private blob export | rejected |
| Credential interop | existing `Sisqual.Credentials` can encrypt to the public key and decrypt through the non-exportable key |
| Persistence | key can be reopened by name in a later process |
| Folder replacement | delete the first portable copy, run from a copied replacement folder, and obtain the same public-key fingerprint |

The source identity artifact contains public data only: CNG key name, provider, algorithm, key size, machine-key flag, export-policy label, SHA-256 fingerprint and public SPKI.

## 5. Machine B gates

The second VM is `windows-2025`. It downloads the exact portable-folder artifact produced by Machine A and runs the copied probe from that artifact.

| Gate | Required result |
|---|---|
| Source private key absent | the same logical CNG key name cannot be opened before local creation |
| Local creation | a new non-exportable machine key can be created under the same logical name |
| Different identity | Machine B fingerprint differs from Machine A fingerprint |
| Private export | PKCS#8 and CNG private-blob export remain rejected |
| Local credential interop | the B key works with `Sisqual.Credentials` |
| Wrong-machine rejection | an entry encrypted to Machine A public key fails decryption with Machine B private key |

This proves the copied portable folder and its public identity data are insufficient to move the usable private identity.

## 6. Key lifecycle in the spike

[CONFIRMED by code review of the spike] The key is created only in the Windows machine CNG store. No private-key bytes are written by the script.

[CONFIRMED by code review of the spike] Private-export attempts are tests only. Any unexpectedly exported buffer is cleared immediately and the gate fails.

[CONFIRMED by code review of the spike] Both jobs contain cleanup steps that delete their test CNG key. GitHub-hosted runners are disposable as an additional boundary, but cleanup is still explicit.

[PENDING] Product lifecycle remains the contract lifecycle: first run creates the machine identity; key loss or rotation is manual and requires a new identity and credential package (owner answer Q5).

## 7. Interaction with credential cryptography

The spike deliberately uses the module already integrated in `main` rather than duplicating ECDH/HKDF/AES-GCM code.

[CONFIRMED] `Protect-CredentialEntry` encrypts to the exported public SPKI only.

[CONFIRMED] `Unprotect-CredentialEntry` accepts `System.Security.Cryptography.ECDiffieHellman`; a CNG-backed `ECDiffieHellmanCng` therefore exercises the intended product integration path.

[PROPOSED] Selection of CNG should require this interop gate to pass in both the source reopen and destination-local identity tests.

## 8. Security boundaries

The spike assumes the local Windows OS and local administrator are trusted, consistent with the project threat model boundary. A non-exportable software-KSP key is not a defence against a fully compromised local administrator or kernel.

The application must never accept a CNG key name from arbitrary browser input. The final key name and provider are application-controlled values.

The public identity is not secret. The private key, decrypted credential bytes and random test secret are never written to the report or artifact.

[PROPOSED] The product should fail closed if the expected CNG key is missing. It must not silently create a replacement key once credentials have already been issued for the old fingerprint.

## 9. Evidence ledger

[PENDING] No workflow run has been dispatched from this branch yet.

Reason: PR #36 demonstrated repeated GitHub-hosted Windows runner starvation. Per owner direction on 2026-10-05, this spike is prepared and documented now; another AI/reviewer may perform the Windows validation later.

The first dispatch must record under `docs/phase1/evidence/phase1b-machine-identity-<run-id>/`:

- workflow ID, run ID, run number and every `run_attempt`;
- exact commit SHA;
- Machine A and Machine B job IDs;
- labels, assigned runner ID/name, start and completion UTC;
- every executed step result;
- artifact names and artifact IDs;
- `report-machine-a-create.json`;
- `report-machine-a-reopen.json`;
- `report-machine-b.json`;
- source public identity artifact;
- any retry, cancellation or supersession reason.

A cancellation with zero steps is infrastructure evidence only, never a CNG PASS or FAIL.

## 10. Acceptance rule

CNG is technically viable for Phase 1B only if one explicitly named `run ID + attempt + commit SHA` proves all Machine A and Machine B gates.

A green runner result would support:

- [CONFIRMED] non-exportable machine-scope CNG ECDH P-256 works on the tested Windows images;
- [CONFIRMED] replacing the portable folder on the same VM preserves the identity;
- [CONFIRMED] copying the folder to the second VM does not transfer the usable private identity;
- [CONFIRMED] the existing credential module interoperates with the non-exportable key;
- [PROPOSED] adopt this CNG implementation for the machine identity;
- [PENDING] reviewer/owner acceptance of the implementation choice and an ADR/update that closes the Phase 1B machine-key item;
- [V] confirm the final application account can reopen the machine key on a SISQUAL sandbox/target server with the intended ACL.

## 11. [PENDING]

1. Execute the two-VM workflow and preserve all run/job/artifact IDs.
2. Decide the final product CNG key name; recommendation: application-controlled name derived from `ServerCode`, not browser input.
3. Define the final CNG key ACL and the Windows account(s) allowed to open it. This must match the portable application's operating identity.
4. Confirm whether administrators-only default machine-key ACL is sufficient or whether the application identity needs an explicit ACL grant.
5. [V] Validate reopen and credential decryption under the real intended operator identity on a target/sandbox Windows server.
6. Use DPAPI only if CNG fails one of the required gates; do not design both paths in V1 without a demonstrated need.
