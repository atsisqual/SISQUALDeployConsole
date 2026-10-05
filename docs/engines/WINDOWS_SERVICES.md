# Engine port specification: WINDOWS_SERVICES

**Status:** [PROPOSED] specification for review (task 3, wave 4). No product code.
**Date:** 2026-10-05
**Sources (read only):** `ops.Engine` row `WINDOWS_SERVICES` of `database/sync/ManagementSync.sql` of `atsisqual/SISQUALManagementConsole` (file `Invoke-WindowsServiceReconciliation.ps1`, version `2.0`, Windows PowerShell 5.1, requires administrator, stored `ScriptSha256` `9ACC7347...`; reference head `9756ba956842884fabcf25b82c4fbf1d11cf56bd`); the action `WINDOWS_SERVICES`; the procedures `cfg.GetWindowsServiceDeploymentPlan` and `cfg.ReviewWindowsServiceModel`. Script text is not copied and no secret value appears here.
Tags: [CONFIRMED] read in the source; [PROPOSED] recommendation; [PENDING] needs a decision; [V] needs a real server.

## 1. Purpose

Create or correct the Windows services defined by the catalog for every enabled instance, with the logon account of the instance's IIS identity, then start them. [CONFIRMED] Action: group `INFRASTRUCTURE`, preview and apply, all enabled instances or one, step 60 of `FULL_DEPLOYMENT` (stop on error). Today there is one definition, the mobile connector service, so one service per instance (76 in all).

## 2. Inputs

| Source (catalog) | Content |
|---|---|
| `cfg_WindowsServiceDefinition` (1 row) | `ServiceCode` (`WFM_MOBILE_APP`), name, display name and description templates, `ExecutablePathTemplate` (the connector executable under the instance root), `ArgumentsTemplate`, `StartupType` (Automatic), `DelayedAutoStart` (1), `StartAfterApply` (1), `RestartOnApply` (1), `AccountSource` (`IIS_IDENTITY`), `CreateAccountIfMissing` (1), `PasswordNeverExpires` (1), `IsRequired` |
| `dbo_ManagedInstance`, `dbo_ManagedServer` | `HostName`, roots, `IisIdentityUserName`, `ConfigBackupRoot` |
| credential package | `IIS_IDENTITY` of each instance (`credentialRef`): the account password |

Review (6 codes): `DUPLICATE_SERVICE_NAME`, `SERVICE_NAME_TOO_LONG`, `SERVICE_ACCOUNT_USERNAME_MISSING`, `SERVICE_ACCOUNT_PASSWORD_MISSING`, `SERVICE_IDENTITY_PASSWORD_CONFLICT` (one account, two passwords), `WINDOWS_SERVICE_DEFINITION_MISSING`. Parameters: instance (optional), apply.

## 3. Steps

1. Check administrator rights; resolve the machine; review the model locally; stop on errors.
2. Plan: each enabled instance times each enabled definition; expand names and paths.
3. Per row: the executable must exist (else `NOT_READY` in preview, `ERROR` in apply); user name and password must be present.
4. Compare six attributes with the live service: binary path, logon account, display name, startup type, delayed start, running state (`MISSING`, `DIFFERS` or `MATCHED`).
5. Preview: `MATCHED`, `WOULD_UPDATE` or `NOT_READY`; nothing is changed.
6. Apply: ensure the local account exists (create if allowed; set its password; password never expires); grant the "log on as a service" right; stop the service if it exists and `RestartOnApply`; create it (Win32 service create) or change it; write `DelayedAutoStart` and the description in the registry; start it (60 s wait); verify against the plan again (a mismatch is an error).
7. Report: one row per service (instance, name, account, startup, state, status, message) to the result and log; fail at the end if any row is `ERROR` or `NOT_READY`.

## 4. Side effects

Creates local accounts and **resets the password of an existing local account** to the credential value; adds the logon-as-a-service right to the account; creates, changes, stops and starts services (the mobile connector is unavailable while it restarts); registry values under the service key. [CONFIRMED] No service configuration backup is made.

## 5. External dependencies

Service Control Manager through CIM (`Win32_Service`), the local account store (ADSI `WinNT` or the `LocalAccounts` module, matrix IIS-32), the local security policy for the logon right (the old engine compiles a small native-call helper at run time), the executable of the connector. [PENDING] each of these under PowerShell 7 (tests below).

## 6. Preview and apply

Preview is deterministic. Apply consumes the fingerprint of the previewed plan and refuses if services, accounts or catalog changed.

## 7. Idempotency

[CONFIRMED, defect] The old apply runs the whole sequence for **every** row, even `MATCHED` ones: it resets the account password and, with `RestartOnApply`, stops and restarts every service on every apply. [PROPOSED] Skip a `MATCHED` row entirely; restart only a service that is changed (and only if `RestartOnApply`); reset a password only when it is known to differ or the account is new. A second apply then changes nothing and restarts nothing.

## 8. Failures

- Missing executable, missing user or password: the row fails, the others continue, the run fails at the end.
- A failed create or change (Win32 return code) or a service that does not reach `Running` in 60 s: `ERROR` with the code; verification failure is an error.
- A password conflict on a shared account is reported by the review before any change.
- [CONFIRMED] In the old code the `IsRequired` flag has no effect (both branches continue); the port honours it: an optional service that is not ready is a warning.

## 9. Backup and restore

[PROPOSED] Before a change record the current service definition (binary path, account name, start mode, delayed flag, description, state) in a run manifest, and offer a restore that re-applies it. A password cannot be read back, so restoring an account needs the credential again; the result says so (R-033).

## 10. Secret risks

[CONFIRMED] The password reaches the operating system as an argument of the Win32 create and change methods and of the account API, not on a command line, which is the right shape to keep. It must never reach the report, log, result, run manifest or an exception message. The old report holds the account name only. Marker password test over every artifact. The account is shared with the application pools (same `IIS_IDENTITY`), so a password reset here affects them (review code above).

## 11. What does not port as it is

The plan and review procedures become a local plan builder and review. The native-call helper compiled with `Add-Type` must be re-tested under PowerShell 7 (it may need another approach). The SQL parameters, the report folder under the backup root and the console banner go; the result follows the engine contract.

## 12. Test plan

- Runner (Windows): a throw-away executable that behaves as a service, and a throw-away local user. Create, `MATCHED`, each of the six differences, change, stop and start, wait and timeout, post-apply verification, a missing executable, missing credentials, a password conflict, idempotency (no restart on a second apply), account creation and password reset, the logon right, the optional-service rule, the instance filter, and a marker password in every artifact. Win32 create argument types (a past type-mismatch failure is documented in the old code), ADSI and the logon helper under PowerShell 7.
- [V] A pilot server with the real connector and identity; the effect of a restart on the mobile app.

## 13. Open questions

1. [PENDING] **Order on a clean server.** `FULL_DEPLOYMENT` runs IIS at step 50 and this engine at step 60, but `CreatePoolIdentityIfMissing` is 0 in every IIS policy while this definition creates the account. On a server without the account, pools are created before the account exists. Recommendation: ensure the shared account in an earlier step (or allow creation in the IIS policy for new machines) and test it on the pilot, which is a clean server.
2. [PENDING] One account for 76 instances: confirm that all instances of a machine share user and password (the review checks it). Recommendation: yes, one credential per machine for that account.
3. [PENDING] Whether a restart is wanted on every change or only when the binary or account changed. Recommendation: only then.
4. [PENDING] The logon-right helper: keep a native call, or use a tool. Recommendation: keep a small native call, tested under PowerShell 7.
