# Phase 1B - Machine identity with non-exportable CNG key

**Date:** 2026-10-05
**Status:** [PROPOSED] CNG candidate; [CONFIRMED] two-VM technical viability at accepted run `37377769448`.
**Branch:** `spike/phase1b-machine-identity-cng`
**Base:** `main` at `ad598215fe3ab0bc715a797a37e2bcf9331eaa56`.

Tags: [CONFIRMED] repository content or recorded execution is verified; [PROPOSED] implementation/design candidate or not-yet-approved contract choice; [PENDING] still needs a decision; [V] requires target/sandbox validation.

## 1. Requirement status

[PROPOSED] ADR-0007 describes a machine private key outside the replaceable portable folder, non-exportable, so replacing or copying the portable folder does not carry a usable machine identity. ADR-0007 keeps this credential decision proposed pending approval of the credential contract.

[CONFIRMED] The current `contracts/credential-package.md` draft specifies binding a package to `target.serverCode` plus the SHA-256 fingerprint of the machine public key; the public key is carried to the credential tool while the private key remains on the target machine.

[CONFIRMED] `docs/decisions-log.md` records owner answer Q2 as ECDH P-256 for credential entries with SHA-256 fingerprints. The integrated `Sisqual.Credentials` module accepts an `ECDiffieHellman` object for decryption.

[CONFIRMED] The Phase 1 roadmap calls for a two-VM copied-folder spike before the machine-key implementation is selected.

## 2. Candidate

[PROPOSED] Windows CNG using `Microsoft Software Key Storage Provider`, ECDH P-256, machine key store and `CngExportPolicies.None`.

[PROPOSED] CNG is preferred over a DPAPI-wrapped exportable key because it directly models the proposed requirement: persisted private material outside the portable folder that normal cryptographic export APIs reject.

[PENDING] DPAPI remains a fallback only if CNG fails a required gate or cannot be operated under the final application identity.

## 3. Spike files and trigger

- `spikes/phase1B/machine-identity/Invoke-MachineIdentityCngSpike.ps1`
- `.github/workflows/phase1b-machine-identity.yml`
- `docs/phase1/evidence/phase1b-machine-identity/README.md`

[CONFIRMED external] GitHub documents that `workflow_dispatch` only receives events when the workflow file exists on the default branch. The pre-merge spike therefore also uses a `push` trigger restricted to this branch and to the spike/workflow paths. `workflow_dispatch` remains for later use after integration.

No real credential, private key or secret is committed. Test keys and random secret bytes exist only inside disposable runner VMs.

## 4. Machine A gates

Machine A uses `windows-2022` and the pinned portable PowerShell 7.6.6 after SHA-256 verification.

Required gates:

- key name absent before creation;
- machine-scope CNG key;
- Microsoft Software Key Storage Provider;
- ECDH P-256;
- export policy `None`;
- public SPKI export succeeds;
- PKCS#8 private export rejected;
- CNG private-blob export rejected;
- `Sisqual.Credentials` encrypt/decrypt interoperability;
- key reopen succeeds in a later process;
- deleting the first portable folder and running from its copied replacement preserves the same public-key fingerprint;
- cleanup deletes the test key.

## 5. Machine B gates

Machine B uses `windows-2025` and downloads the exact Machine A portable-folder artifact.

Required gates:

- Machine A private key is absent on Machine B;
- same logical key name creates a different local identity;
- private exports remain rejected;
- local `Sisqual.Credentials` interoperability succeeds;
- an entry encrypted to Machine A public key cannot decrypt with Machine B private key;
- cleanup deletes the test key.

## 6. Execution history

### Run 1 - harness failure

[CONFIRMED] Run `37376755238`, run number 1, attempt 1, commit `53cccd67cee9cd5e2cd9a9210995a6987c563adf` failed before key creation because an empty generic list was enumerated to no pipeline output. Machine A job `111987660696`; Machine B job `111988756769` skipped.

Evidence: `docs/phase1/evidence/phase1b-machine-identity-37376755238/README.md`.

### Run 2 - harness binder failure

[CONFIRMED] Run `37377236061`, run number 2, attempt 1, commit `3df9c920409b9061cf34f4f88ebdd0f28001809f` failed before key creation because the mandatory parameter binder rejected an empty collection. Machine A job `111989440871`; Machine B job `111990541311` skipped.

Evidence: `docs/phase1/evidence/phase1b-machine-identity-37377236061/README.md`.

### Run 3 - accepted technical evidence

[CONFIRMED] Run `37377769448`, run number 3, attempt 1, commit `09de75cb90eedc6015e7125d54da0d25253052c7` completed successfully on both machines.

Machine A:

- job `111991358773`;
- runner `GitHub Actions 1000000539`, `runner_id=1000000539`;
- all create, folder-replacement/reopen and cleanup gates passed;
- artifact ID `11373000213`;
- artifact digest `sha256:a8ffa576c2331b555f9e15cb841c071c14eb058c8fca56863b4203d07fdcb132`.

Machine B:

- job `111992501724`;
- runner `GitHub Actions 1000000542`, `runner_id=1000000542`;
- downloaded and digest-verified Machine A artifact;
- all copied-folder, different-identity, wrong-machine-decrypt, interop and cleanup gates passed;
- artifact ID `11373310252`;
- artifact digest `sha256:fddf5bb8175218c851ed102c90284e82cac922d6ea460bd4b6261ec9e67f4579`.

Full evidence and the five versioned gate reports:

`docs/phase1/evidence/phase1b-machine-identity-37377769448/`

## 7. Technical conclusions

[CONFIRMED] A machine-scope ECDH P-256 key in Microsoft Software Key Storage Provider with export policy `None` worked on the tested Windows Server 2022 runner.

[CONFIRMED] Public-key export succeeded while PKCS#8 and CNG private-blob export were rejected.

[CONFIRMED] `Sisqual.Credentials` interoperated with the non-exportable CNG-backed key.

[CONFIRMED] Replacing the portable folder on Machine A preserved the same identity.

[CONFIRMED] Copying that folder to the Windows Server 2025 runner did not transfer the private identity; Machine B created a different identity and could not decrypt an entry intended for Machine A.

[CONFIRMED] Test keys were explicitly deleted on both machines.

## 8. Security boundary

The spike assumes the Windows OS and local administrator are trusted. A non-exportable software-KSP key is not a defence against a fully compromised local administrator or kernel.

The final application must control the CNG key name/provider; neither should come from browser input.

The public identity is not secret. Private key material, decrypted credential bytes and random test secrets are not included in evidence files.

[PROPOSED] Once credentials have been issued, a missing expected key should fail closed rather than silently creating a replacement identity.

## 9. Decision boundary

The accepted run proves technical viability only; it does not approve the proposed credential contract or select CNG as an architectural decision by itself.

[PROPOSED] Adopt this CNG approach for the V1 machine identity, subject to reviewer/owner acceptance and final ACL validation.

[PENDING] A later ADR/contract update should close the Phase 1B machine-key item only after that acceptance.

## 10. [PENDING] / [V]

1. Decide the final product CNG key name; recommendation: application-controlled and derived from `ServerCode`, never browser supplied.
2. Define the final CNG key ACL and the Windows account(s) permitted to open it.
3. Confirm whether the default machine-key ACL is sufficient or an explicit application-identity grant is needed.
4. [V] Validate reopen and credential decryption under the intended real operator/application identity on a SISQUAL target/sandbox Windows server.
5. Use DPAPI only if CNG fails a required operational gate; do not maintain two V1 identity mechanisms without demonstrated need.
