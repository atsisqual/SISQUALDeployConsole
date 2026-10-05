# Phase 1B machine identity evidence - run 37377769448

**Workflow:** `phase1b-machine-identity`
**Workflow ID:** `375831032`
**Run ID:** `37377769448`
**Run number:** `3`
**Run attempt:** `1`
**Event:** `push`
**Branch:** `spike/phase1b-machine-identity-cng`
**Commit:** `09de75cb90eedc6015e7125d54da0d25253052c7`
**Created UTC:** `2026-10-05T21:43:35Z`
**Completed UTC:** `2026-10-05T21:48:17Z`
**Run result:** `success`
**Classification:** [CONFIRMED] accepted technical two-VM evidence for the CNG spike at the exact commit above.

## Job ledger

| Job | Job ID | Label | Runner | Started UTC | Completed UTC | Result |
|---|---:|---|---|---|---|---|
| Machine A - create and reopen CNG identity | `111991358773` | `windows-2022` | `GitHub Actions 1000000539` (`runner_id=1000000539`) | 2026-10-05T21:43:39Z | 2026-10-05T21:46:24Z | success |
| Machine B - copied folder has no source private key | `111992501724` | `windows-2025` | `GitHub Actions 1000000542` (`runner_id=1000000542`) | 2026-10-05T21:46:27Z | 2026-10-05T21:48:16Z | success |

## Runner images

Machine A:

- runner version `2.337.0`;
- Microsoft Windows Server 2022 Datacenter `10.0.20348`;
- image `windows-2022`;
- image version `20260927.320.1`.

Machine B:

- runner version `2.337.0`;
- Microsoft Windows Server 2025 Datacenter `10.0.26100`;
- image `windows-2025-vs2026`;
- image version `20260925.250.1`.

Both jobs downloaded the pinned portable PowerShell 7.6.6 archive and verified SHA-256 `02FE458BE20493FBDF43F61EA20610B811EE6C738AB1676C61B9CFCD1A33C860` before running the probe.

## Machine A step ledger

| Step | Start UTC | End UTC | Result |
|---|---|---|---|
| Set up job | 21:43:41 | 21:43:42 | success |
| Checkout | 21:43:42 | 21:43:48 | success |
| Download verified portable PowerShell | 21:43:48 | 21:46:16 | success |
| Materialize portable folder A | 21:46:16 | 21:46:17 | success |
| Create non-exportable machine identity | 21:46:17 | 21:46:18 | success |
| Replace portable folder and reopen same identity | 21:46:18 | 21:46:19 | success |
| Clean source test key | 21:46:19 | 21:46:20 | success |
| Upload source evidence | 21:46:20 | 21:46:21 | success |
| Post checkout | 21:46:21 | 21:46:23 | success |

## Machine A report results

`report-machine-a-create.json` reported `overall = PASS` and all gates passed:

- `KEY_ABSENT_BEFORE_CREATE`;
- `MACHINE_SCOPE`;
- `SOFTWARE_KSP`;
- `ECDH_P256`;
- `EXPORT_POLICY_NONE`;
- `PUBLIC_EXPORT`;
- `PRIVATE_EXPORT_PKCS8_BLOCKED`;
- `PRIVATE_EXPORT_CNG_BLOCKED`;
- `CREDENTIAL_MODULE_INTEROP`.

`report-machine-a-reopen.json` reported `overall = PASS` and all gates passed:

- `KEY_PRESENT_AFTER_FOLDER_REPLACEMENT`;
- `FINGERPRINT_STABLE`;
- `PRIVATE_EXPORT_PKCS8_BLOCKED`;
- `PRIVATE_EXPORT_CNG_BLOCKED`;
- `CREDENTIAL_MODULE_INTEROP`.

`report-machine-a-cleanup.json` reported `overall = PASS` with `KEY_REMOVED = PASS`.

The create and reopen reports recorded the same public-key fingerprint, proving identity stability after the original portable folder was removed and the copied replacement folder was used.

## Machine A artifact

- artifact name: `phase1b-machine-identity-machine-a`;
- artifact ID: `11373000213`;
- size: `10931` bytes;
- created: `2026-10-05T21:46:21Z`;
- expires: `2027-01-03T21:43:35Z`;
- artifact ZIP digest: `sha256:a8ffa576c2331b555f9e15cb841c071c14eb058c8fca56863b4203d07fdcb132`.

Machine B downloaded artifact ID `11373000213` and GitHub verified the same SHA-256 digest before use.

## Machine B step ledger

| Step | Start UTC | End UTC | Result |
|---|---|---|---|
| Set up job | 21:46:28 | 21:46:29 | success |
| Checkout | 21:46:29 | 21:46:33 | success |
| Download Machine A artifact | 21:46:33 | 21:46:33 | success |
| Download verified portable PowerShell | 21:46:33 | 21:48:10 | success |
| Run copied folder on Machine B | 21:48:10 | 21:48:11 | success |
| Clean destination test key | 21:48:11 | 21:48:12 | success |
| Upload Machine B evidence | 21:48:12 | 21:48:13 | success |
| Post checkout | 21:48:13 | 21:48:14 | success |

## Machine B report results

`report-machine-b.json` reported `overall = PASS` and all gates passed:

- `COPIED_FOLDER_HAS_NO_PRIVATE_KEY`;
- `DESTINATION_IDENTITY_DIFFERENT`;
- `PRIVATE_EXPORT_PKCS8_BLOCKED`;
- `PRIVATE_EXPORT_CNG_BLOCKED`;
- `CREDENTIAL_MODULE_INTEROP`;
- `SOURCE_ENTRY_REJECTED_ON_DESTINATION`.

`report-machine-b-cleanup.json` reported `overall = PASS` with `KEY_REMOVED = PASS`.

This proves that the copied Machine A portable folder and public identity data did not transfer a usable Machine A private key. Machine B created a distinct local identity, and an entry encrypted to Machine A could not be decrypted with Machine B private key.

## Machine B artifact

- artifact name: `phase1b-machine-identity-machine-b`;
- artifact ID: `11373310252`;
- size: `1188` bytes;
- created: `2026-10-05T21:48:12Z`;
- expires: `2027-01-03T21:43:35Z`;
- artifact ZIP digest: `sha256:fddf5bb8175218c851ed102c90284e82cac922d6ea460bd4b6261ec9e67f4579`.

## Accepted technical conclusions

[CONFIRMED] At commit `09de75cb90eedc6015e7125d54da0d25253052c7`, a machine-scope ECDH P-256 key in Microsoft Software Key Storage Provider with export policy `None` worked on the tested Windows Server 2022 runner.

[CONFIRMED] Public-key export succeeded while PKCS#8 and CNG private-blob export were rejected.

[CONFIRMED] The integrated `Sisqual.Credentials` module successfully encrypted to and decrypted with the non-exportable CNG-backed identity.

[CONFIRMED] Replacing the portable folder on Machine A preserved the same machine identity.

[CONFIRMED] Copying that portable folder to a separate Windows Server 2025 runner did not transfer the private identity; the destination created a different identity and could not decrypt an entry intended for Machine A.

[CONFIRMED] Explicit cleanup removed the test key on both machines.

## Boundary of this evidence

This run proves technical viability on the two GitHub-hosted Windows images only. It does not approve the still-[PROPOSED] credential contract or select CNG as a product decision by itself.

[PENDING] Reviewer/owner acceptance is required before the implementation choice is promoted into an ADR/contract closure.

[V] The final application/operator Windows identity and its CNG key ACL must still be tested on a SISQUAL target or sandbox server.

## Historical runs

The accepted result does not erase earlier failures:

- run `37376755238`: harness returned `$null` instead of an empty check list before key creation;
- run `37377236061`: PowerShell binder rejected the real empty list before key creation.

Both remain separate run-specific evidence and are explicitly not CNG technical failures.
