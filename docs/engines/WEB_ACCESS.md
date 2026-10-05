# Engine port specification: WEB_ACCESS

**Status:** [PROPOSED] specification for review (task 3, wave 5). No product code.
**Date:** 2026-10-05
**Sources (read only):** `ops.Engine` row `WEB_ACCESS` of `database/sync/ManagementSync.sql` of `atsisqual/SISQUALManagementConsole` (file `Invoke-WebAccessDeployment.ps1`, version `5.0`, Windows PowerShell 5.1, requires administrator, stored `ScriptSha256` `D8C9F80F...`; reference head `9756ba956842884fabcf25b82c4fbf1d11cf56bd`); the action `WEB_ACCESS`; the procedures `cfg.GetWebAccessDeploymentPlan` and `cfg.ReviewWebAccessModel`. Script text is not copied and no secret value appears here.
Tags: [CONFIRMED] read in the source; [PROPOSED] recommendation; [PENDING] needs a decision; [V] needs a real server.

## 1. Purpose

Set up the Web Access entry point of each instance: a local Windows user, a protected credential file, the root page that launches Web Access, the default document, and a check of the Web Access backend. [CONFIRMED] Action: group `ACCESS`, preview and apply, all enabled instances or one, step 70 of `FULL_DEPLOYMENT` (stop on error). All 76 enabled instances have a Web Access user name; a server policy exists on 4 machines (not PRESALES, TENDERS, which stop with "policy missing").

## 2. Inputs

| Source (catalog) | Content |
|---|---|
| `cfg_WebAccessPolicy` (1 row per machine) | data root, credential file path and backend and public launch URL templates (backend `https://127.0.0.1:8443`), `CreateLocalUserIfMissing`, `EnforcePasswordOnApply`, group flags (Remote Desktop Users, Users), `PasswordNeverExpires`, `UserMayNotChangePassword`, `BackupExistingRootFiles`, `IgnoreBackendCertificateErrors` (1 in all four) |
| `cfg_WebAccessTemplate` (1 row) | the root page template and its SHA-256 |
| `dbo_ManagedInstance`, `dbo_ManagedServer` | host name, instance root, site and root pool name and identity, `WebAccessUserName` |
| credential package | `WEB_ACCESS` of the instance (`credentialRef`): the password |

Review (7 codes): `WEB_ACCESS_POLICY_MISSING`, `WEB_ACCESS_TEMPLATE_MISSING`, `WEB_ACCESS_USERNAME_MISSING`, `WEB_ACCESS_PASSWORD_MISSING`, `WEB_ACCESS_DUPLICATE_LOCAL_USER`, `WEB_ACCESS_BACKEND_URL_MISSING`, `WEB_ACCESS_PUBLIC_URL_MISSING`.

## 3. Steps

1. Check administrator rights (apply); review the model locally; stop on errors; resolve the plan for this machine.
2. Per instance render the page: four tokens (credential file path, backend URL and public launch URL as base64, and the certificate-errors flag); an unresolved token is an error.
3. Preview: the user is `WOULD_CREATE` or `WOULD_UPDATE`; the root file by hash (`MATCHED`, `WOULD_UPDATE`); the backend check. Nothing is written.
4. Apply: ensure the local user (create if allowed, set the password, flags); add it to the two built-in groups by well-known SID; write the credential file protected for the machine, verify it by decrypting and comparing exactly, and restrict its ACL (SYSTEM and Administrators full control, inheritance removed, the root pool identity read and execute); back up and write `Default.aspx` at the instance root; make `Default.aspx` the first default document of the site; restart the root pool; check the backend.
5. Report one row per object (local user, root file, credential file, default document, backend) to the result and log; the backend check is a warning, never an error.

## 4. Side effects

Creates and changes up to 76 local accounts and their group memberships, writes files under the machine data folder and each instance root, changes IIS configuration (default document), **restarts the root application pool of the instance**, and calls the backend over loopback.

## 5. External dependencies

The Web Access backend (TSplus) on the loopback port, IIS (through `Microsoft.Web.Administration`), the local account store, DPAPI (machine scope), the file system and ACLs. [CONFIRMED] TSplus and Web Access cannot be tested on a runner.

## 6. Preview and apply

[PROPOSED] A real preview: compare the user (exists, flags, group membership), the credential file (does it decrypt to the expected value), the root file, the default document and the pool, and report each. Apply consumes the fingerprint of the preview and refuses on drift.

## 7. Idempotency

[CONFIRMED, defects] An existing user is always `WOULD_UPDATE`; apply rewrites the credential file every time (protected output differs on every write) and restarts the root pool every time, even when nothing changed. [PROPOSED] Decide by comparing decrypted content with the expected value, rewrite only on difference, and restart the pool only when the page or the default document changed.

## 8. Failures

Policy or template missing, empty user name, or a user that does not exist when creation is forbidden: error for that instance, the others continue, the run fails at the end. A round-trip mismatch removes nothing and is an error. A pool restart that fails is a warning with the reason. An unreachable backend is `WARNING`.

## 9. Backup and restore

The root page is backed up before it is replaced (`BackupExistingRootFiles`); the credential file and the default document order are not. [PROPOSED] Back up the previous credential file (still protected) and record the default document list in a run manifest. A created user is not removed on restore (it is reported).

## 10. Secret risks

- The password comes from the package in memory. It is written only into the protected credential file; [CONFIRMED] the old page and report never contain it, and the engine clears the decrypted bytes after the check. Keep that, and make sure no exception text, log, result or backup note holds it (marker test).
- [CONFIRMED] Machine-scope protection means any process on the machine that can read the file can decrypt it; the ACL is the control. Keep the ACL check as a post-condition.
- `IgnoreBackendCertificateErrors` applies only to loopback in the old code. [PROPOSED] keep that limit in code, not only in the policy.

## 11. What does not port as it is

The old script uses the WebAdministration provider for the site test and the pool restart, which does not work under PowerShell 7 (ADR-0006): use `Microsoft.Web.Administration` for those and for the default document (the old code already did for the latter). The assembly loading for the protection API needs a re-test. The SQL plan and review procedures, the context procedure and the run folder go.

## 12. Test plan

- Runner: local user lifecycle with a throw-away name; both group memberships; credential file write, exact round trip, ACL result; page rendering and the unresolved-token error; default document ordering; pool restart only on change; a local TLS test server standing in for the backend (valid, invalid certificate, wrong body, down); idempotency; preview equals apply; marker password in every artifact.
- [V] Real TSplus Web Access, the real backend response, a real pool restart under load.

## 13. Open questions

1. [PENDING] One local user per instance (76) with a reset password on every apply (`EnforcePasswordOnApply`). Recommendation: reset only when the credential changed, to avoid logging out users.
2. [PENDING] Restart of the root pool: only when something changed (recommended).
3. [PENDING] Whether the credential file may use the machine key of the portable instead of machine-scope protection. Recommendation: no, because the website process must read it.
