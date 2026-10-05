# Phase 1B - Machine identity with non-exportable CNG key

**Date:** 2026-10-05
**Status:** [PROPOSED] spike under runner validation. No product implementation or ADR decision is made by this document.
**Branch:** `spike/phase1b-machine-identity-cng`
**Base:** `main` at `ad598215fe3ab0bc715a797a37e2bcf9331eaa56`.

Tags: [CONFIRMED] supported by approved repository evidence or recorded execution; [PROPOSED] implementation/design candidate; [PENDING] still needs a decision or completed evidence; [V] requires target/sandbox validation.

## 1. Requirement

[CONFIRMED] ADR-0007 requires the machine private key to live outside the replaceable portable folder and to be non-exportable. Replacing or copying the portable folder must not carry a usable machine identity to another machine.

[CONFIRMED] `contracts/credential-package.md` binds a credential package to `target.serverCode` plus the SHA-256 fingerprint of the machine public key. The public key is carried manually to the credential tool; the private key never leaves the target machine.

[CONFIRMED] Owner answer Q2 selected ECDH P-256 for credential entries and SHA-256 fingerprints. `Sisqual.Credentials` already accepts an `ECDiffieHellman` object for decryption so a non-exportable CNG-backed key can be used.

[CONFIRMED] The Phase 1 roadmap requires a two-VM copied-folder test before selecting the machine-key implementation.

## 2. Candidate

[PROPOSED] Windows CNG, `Microsoft Software Key Storage Provider`, ECDH P-256, machine key store, `CngExportPolicies.None`.

The spike does not choose the final product key name or ACL. Its test key name is unique per workflow run and is deleted during cleanup.

[PROPOSED] CNG is preferred over a DPAPI-wrapped exportable key because it directly models the approved requirement: persisted private material outside the portable folder that normal cryptographic APIs cannot export.

[PENDING] DPAPI remains a fallback only if CNG fails a required gate or cannot be operated under the final application identity.

## 3. Spike and trigger

Files:

- `spikes/phase1B/machine-identity/Invoke-MachineIdentityCngSpike.ps1`
- `.github/workflows/phase1b-machine-identity.yml`
- `docs/phase1/evidence/phase1b-machine-identity/README.md`

[CONFIRMED external] GitHub documents that `workflow_dispatch` only receives events when the workflow file exists on the default branch. Therefore this pre-merge spike also has a `push` trigger restricted to this branch and to the spike/workflow paths. `workflow_dispatch` remains for later use after integration.

[CONFIRMED] The push trigger produced run `37376755238`, workflow ID `375831032`, run number `1`, attempt `1`, at commit `53cccd67cee9cd5e2cd9a9210995a6987c563adf`.

[CONFIRMED] Machine A job `111987660696` received a real `windows-2022` runner, ID `1000000536`, and started at `2026-10-05T21:34:43Z`. At the latest recorded check it was still executing; no CNG result is claimed yet.

No real key, credential or secret is committed. Test keys and random secret bytes exist only inside disposable runner VMs.

## 4. Machine A gates

Machine A runs the pinned portable PowerShell 7.6.6 after SHA-256 verification.

| Gate | Required result |
|---|---|
| Key absent | unique CNG key name does not pre-exist |
| Machine scope | `IsMachineKey = true` |
| Provider | Microsoft Software Key Storage Provider |
| Algorithm | ECDH P-256 / 256-bit curve |
| Export policy | `None` |
| Public export | SubjectPublicKeyInfo export succeeds |
| PKCS#8 private export | rejected |
| CNG private blob export | rejected |
| Credential interop | `Sisqual.Credentials` encrypts to public key and decrypts through non-exportable key |
| Persistence | key can be reopened by name in a later process |
| Folder replacement | delete first portable copy, run replacement copy, fingerprint remains identical |

The source identity artifact contains public data only: key name, provider, algorithm, key size, machine-key flag, export-policy label, SHA-256 fingerprint and public SPKI.

## 5. Machine B gates

Machine B uses `windows-2025` and downloads the exact replacement portable-folder artifact produced by Machine A.

| Gate | Required result |
|---|---|
| Source private key absent | same logical CNG key name cannot be opened before local creation |
| Local creation | same logical key name creates a local non-exportable key |
| Different identity | Machine B fingerprint differs from Machine A |
| Private export | PKCS#8 and CNG private-blob export rejected |
| Credential interop | local B key works with `Sisqual.Credentials` |
| Wrong-machine rejection | entry encrypted to Machine A public key cannot decrypt with Machine B private key |

A PASS demonstrates that copying the portable folder and public identity is insufficient to transfer the usable private identity.

## 6. Key lifecycle and cleanup

[CONFIRMED by code review] The private key is created only in the Windows machine CNG store. The script never serializes private-key bytes to a file or artifact.

[CONFIRMED by code review] Private-export attempts are negative tests. If an export unexpectedly succeeds, the returned buffer is cleared and the gate fails.

[CONFIRMED by code review] Both jobs explicitly delete their test CNG key and preserve a cleanup report. GitHub-hosted runners are disposable as an additional boundary, not as a substitute for cleanup.

[PENDING] Product lifecycle remains the approved contract lifecycle: first run creates identity; key loss/rotation is manual and requires a new identity and credential package (Q5).

## 7. Credential-module integration

[CONFIRMED] The spike reuses the integrated `modules/Sisqual.Credentials/Sisqual.Credentials.psm1`; it does not duplicate ECDH/HKDF/AES-GCM implementation.

[CONFIRMED] `Protect-CredentialEntry` consumes only the exported public SPKI.

[CONFIRMED] `Unprotect-CredentialEntry` accepts `System.Security.Cryptography.ECDiffieHellman`; the CNG-backed `ECDiffieHellmanCng` tests the intended integration path.

[PROPOSED] CNG selection requires this interop gate to pass on Machine A creation, Machine A reopen and Machine B local identity.

## 8. Security boundary

The spike assumes the Windows OS and local administrator are trusted, consistent with the project threat boundary. A non-exportable software-KSP key does not defend against a fully compromised local administrator or kernel.

The final application must control the CNG key name/provider; neither may come from arbitrary browser input.

The public identity is not secret. Private key material, decrypted credential bytes and random test secrets are never included in reports or artifacts.

[PROPOSED] Once credentials have been issued, a missing expected key must fail closed rather than silently creating a replacement identity.

## 9. Evidence ledger

The canonical live ledger is:

`docs/phase1/evidence/phase1b-machine-identity/README.md`

It records workflow/run/attempt/job IDs, exact commit, runner identity, UTC timestamps, steps, artifacts and supersession/retry reasons. No missing identifier is invented.

Expected Machine A evidence:

- replacement portable folder;
- `machine-identity-source.json`;
- create, reopen and cleanup reports.

Expected Machine B evidence:

- destination report;
- cleanup report.

A cancellation with no runner or zero probe steps is infrastructure evidence only, never a CNG technical PASS/FAIL.

## 10. Acceptance rule

CNG is technically viable only if one explicitly named `run ID + run_attempt + commit SHA` proves every required gate on both VMs and preserves the artifact IDs.

A green two-VM result would support:

- [CONFIRMED] non-exportable machine-scope CNG ECDH P-256 works on the tested Windows images;
- [CONFIRMED] replacing the portable folder on one VM preserves identity;
- [CONFIRMED] copying the folder to another VM does not transfer private identity;
- [CONFIRMED] the existing credential module interoperates with the key;
- [PROPOSED] adopt this CNG implementation;
- [PENDING] reviewer/owner acceptance and ADR/update closing the Phase 1B machine-key item;
- [V] final application identity/ACL validation on a SISQUAL target or sandbox server.

## 11. [PENDING]

1. Complete run `37376755238` (or preserve its failure and name a later accepted run) and record both job/artifact IDs.
2. Decide final product CNG key name; recommendation: application-controlled and derived from `ServerCode`, never browser supplied.
3. Define the CNG key ACL and Windows account(s) allowed to open it.
4. Confirm whether the machine-key default ACL is sufficient or an explicit application-identity grant is needed.
5. [V] Validate reopen and credential decryption under the intended real operator/application identity on a target/sandbox Windows server.
6. Use DPAPI only if CNG fails a required gate; do not maintain two V1 identity mechanisms without demonstrated need.
