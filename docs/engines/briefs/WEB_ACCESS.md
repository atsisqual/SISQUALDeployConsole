# WEB_ACCESS port brief

**Status:** [PROPOSED]
**Task:** T8 / M3.6
**Date:** 2026-10-10

This brief defines the evidence and safety gate for the `WEB_ACCESS` port. It is documentation only.

## 1. Sources and evidence boundary

[CONFIRMED] Checked now against `main`:

- `docs/engines/WEB_ACCESS.md` documents source-era `Invoke-WebAccessDeployment.ps1`, `cfg.GetWebAccessDeploymentPlan` and `cfg.ReviewWebAccessModel`.
- `tests/Fixtures/carried-schema.json` carries `cfg.WebAccessPolicy`, `cfg.WebAccessTemplate`, managed server/instance data and the Web Access user fields used by the specification.
- The integrated preflight and source evidence name seven Web Access review codes: `WEB_ACCESS_POLICY_MISSING`, `WEB_ACCESS_TEMPLATE_MISSING`, `WEB_ACCESS_USERNAME_MISSING`, `WEB_ACCESS_PASSWORD_MISSING`, `WEB_ACCESS_DUPLICATE_LOCAL_USER`, `WEB_ACCESS_BACKEND_URL_MISSING`, `WEB_ACCESS_PUBLIC_URL_MISSING`.
- PR #69 rules 6 and 7 apply: duplicate local-user checks are machine-wide; catalog-derived data/root/page/credential paths must be contained under approved roots after reparse-point resolution.

[NOT VERIFIED] TSplus/Web Access is not available on GitHub runners. The real backend response, certificate topology and impact of a real application-pool restart remain `[V]` evidence.

## 2. Purpose and class

[CONFIRMED] `WEB_ACCESS` is `MUTATING`. For each selected enabled instance it manages the local Web Access account, protected credential file, rendered root `Default.aspx`, IIS default-document ordering and backend health check.

[CONFIRMED] It supports all enabled instances or one selected instance and is step 70 of `FULL_DEPLOYMENT`.

## 3. Catalog model

| Source | Use |
|---|---|
| `cfg.WebAccessPolicy` | machine-scoped data/credential paths, backend/public URL templates, user/group/password flags, root-file backup policy and backend-certificate policy |
| `cfg.WebAccessTemplate` | root-page template and expected SHA-256 |
| `dbo.ManagedInstance` | instance/root/site/root-pool data and `WebAccessUserName` |
| `dbo.ManagedServer` | local machine/root policy data |
| credential package | `WEB_ACCESS.<InstanceCode>` password |

[CONFIRMED] Server policy is machine-scoped in conversion. The existing specification records policy rows on four machines and none on PRESALES/TENDERS; absence is an error, not a synthesized default.

## 4. Credentials and duplicate users

[DECIDED 2026-10-09] `WEB_ACCESS.*` is one of the three allowed instance-family forms, and a concrete member is admitted only for an enabled catalog instance.

[PROPOSED] `WEB_ACCESS_DUPLICATE_LOCAL_USER` compares every enabled instance on the machine using Windows case-insensitive username semantics. A run for one instance must detect a duplicate held by an enabled unselected instance and report the issue on the selected participant.

The password is used only in memory and in the machine-protected credential file. It never appears in page content, result, logs, plan fingerprint, backup notes or exception text.

## 5. Desired-state preview

[CONFIRMED, source-era defects] The old implementation treated an existing user as `WOULD_UPDATE`, rewrote the protected credential file every APPLY and restarted the root pool every APPLY even when nothing changed.

[PROPOSED] Preview computes actual drift without writes:

- local account exists and required account flags/group memberships;
- credential file exists, has the required ACL and decrypts to exactly the expected password;
- rendered `Default.aspx` hash equals desired bytes;
- `Default.aspx` is first in the IIS default-document list;
- root pool target/state relevant to restart planning;
- backend health state.

DPAPI ciphertext randomness is never used as a drift signal; compare decrypted content in memory.

## 6. Rendering and path safety

[CONFIRMED] The current specification records four page-template inputs: credential-file path, backend URL, public launch URL and certificate-error flag. Any unresolved token is a blocking item error.

[PROPOSED] Before reading/writing data, credential or root-page paths:

- reject UNC/device/non-local paths;
- require lexical containment under the approved machine data root or instance root, as applicable;
- resolve junctions/symlinks and re-check containment;
- report access denied as a structured item error.

The rendered page may contain encoded URLs and a credential-file path but never the password.

## 7. Apply and idempotency

[PROPOSED] APPLY consumes the confirmed preview fingerprint and changes only drifted objects:

1. create/correct the local user only as approved by policy;
2. add required built-in groups by well-known SID, not localized group names;
3. write/replace the protected credential file only when decrypted content or ACL is wrong;
4. back up and replace the root page only when bytes differ;
5. correct default-document ordering only when different;
6. restart the root pool only when a change that requires it occurred;
7. re-read every changed object and run the backend check.

A second APPLY after convergence performs no account/password reset, file rewrite, IIS write or pool restart.

## 8. Credential-file protection and ACL

[CONFIRMED] The existing design uses machine-scope protection because the website process must be able to decrypt the file. The file ACL is therefore the security boundary.

[PROPOSED] Post-condition tests prove:

- inheritance disabled where the policy requires it;
- SYSTEM/Administrators full control;
- only the approved root-pool identity receives the required read/execute access;
- no broad Users/Everyone access is introduced;
- round-trip decryption equals the expected password, then plaintext buffers are discarded.

Backup of a prior credential file keeps it protected and retains restrictive ACLs; ordinary result metadata never contains its decrypted content.

## 9. Backend/TLS behavior

[CONFIRMED] The documented backend is loopback and backend failure is a warning, not a deployment error. `IgnoreBackendCertificateErrors` is present in machine policy and is true in the four reference policy rows.

[PROPOSED] Any certificate-validation exception is scoped to the individual loopback backend request and only when the approved machine policy says so. It must never install a process-global certificate callback or weaken validation for non-loopback URLs.

[V] Real TSplus response semantics and certificate behavior must be confirmed on a pilot. Runner tests use a local HTTPS test server only.

## 10. Side effects

[CONFIRMED] APPLY may create/change local accounts/group memberships, write protected and root-page files, change IIS default-document configuration, restart an application pool and call the loopback backend.

No database write belongs to this engine.

## 11. Backup and restore

[CONFIRMED] The source behavior backs up an existing root page when policy enables it but not all other changed state.

[PROPOSED] The portable run manifest records/restores:

- previous root-page bytes/hash;
- previous protected credential file bytes/ACL if replaced;
- previous default-document list;
- readable local-user/group/flag state.

A created user is not automatically deleted on restore unless ownership/deletion semantics are explicitly approved. Password rollback requires protected credential material and must not create a plaintext secret store.

## 12. Failures and result semantics

Use the seven original review codes with their source severities. Beyond review errors, required-object/path/ACL/protection/IIS-write failures are blocking item errors. Backend health remains a warning under the current specification. A pool restart failure is recorded with its reason and final severity must follow approved source/owner behavior.

[PROPOSED] Results are per managed object (`USER`, `CREDENTIAL_FILE`, `ROOT_PAGE`, `DEFAULT_DOCUMENT`, `POOL`, `BACKEND`) and deterministic by instance/object. No row contains password-derived content.

## 13. Required tests

Runner tests must cover:

- all seven review codes, including duplicate local user against an enabled unselected instance;
- exact family authorization and missing `WEB_ACCESS.<InstanceCode>`;
- local user absent/create-forbidden/create/update/matched;
- well-known-SID group membership and case-insensitive account comparison;
- credential-file protect/decrypt exact round trip and ACL post-condition;
- marker password absent from all artifacts;
- no rewrite when decrypted content/ACL already match;
- page rendering, expected hash and unresolved-token failure;
- path traversal, UNC/device path, junction/symlink escape and access denied;
- default-document ordering through MWA;
- pool restart only when a relevant object changed; second APPLY no restart;
- local HTTPS backend valid cert, invalid cert with policy false, invalid cert with approved loopback-only ignore true, wrong response and unavailable backend;
- prove no global TLS-validation override;
- preview no-write, deterministic fingerprint and drift refusal;
- backup/restore for page, protected credential file and default-document list.

[V] Real TSplus Web Access and pool restart under realistic load.

## 14. Open questions

1. [PENDING] Whether `EnforcePasswordOnApply` means reset on every APPLY or only when credential state changed; recommendation remains change-only for idempotency.
2. [PENDING] Final severity of a root-pool restart failure.
3. [PENDING] Restore/delete semantics for a user created by this engine.
4. [V] Exact TSplus backend body/health semantics on supported deployments.

## 15. Entry gate for the code PR

The code PR may start when:

- all used policy/template/instance columns are confirmed in `carried-schema.json`;
- seven review predicates/severities are bound to tests;
- duplicate-user comparison is machine-wide;
- protected-file ACL and path-containment post-conditions are executable tests;
- MWA default-document/restart operations are runner-proven;
- TLS exception scope is restricted to approved loopback policy;
- TSplus itself remains clearly `[V]`, not inferred from the runner surrogate.
