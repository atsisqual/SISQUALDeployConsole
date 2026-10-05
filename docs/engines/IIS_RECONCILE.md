# Engine port specification: IIS_RECONCILE

**Status:** [PROPOSED] specification for review (task 3, wave 3). No product code.
**Date:** 2026-10-05
**Sources (read only):** `ops.Engine` row `IIS_RECONCILE` of `database/sync/ManagementSync.sql` of `atsisqual/SISQUALManagementConsole` (file `Invoke-IISReconciliation.ps1`, version `16.3`, 91,834 characters, Windows PowerShell 5.1, requires administrator, stored `ScriptSha256` `77D8B883...`; reference head `9756ba956842884fabcf25b82c4fbf1d11cf56bd`); the action `IIS_RECONCILE`; the four plan procedures `cfg.GetIisDeploymentPlan`, `cfg.GetIisServiceAutoStartProviderPlan`, `cfg.GetIisApplicationAutoStartPlan`, `cfg.ReviewIisDeploymentModel`; `docs/phase1/iis-reconcile-mwa-equivalence.md` (the 32 operations, IIS-01 to IIS-32, and tests T-01 to T-11); ADR-0006 (IIS through `Microsoft.Web.Administration`, four conditions). Script text is not copied.
Tags: [CONFIRMED] read in the source; [PROPOSED] recommendation; [PENDING] needs a decision; [V] needs a real server.

## 1. Purpose

Bring IIS on the machine to the state the catalog defines for every enabled instance: prerequisites, directories and their ACLs, application pools, one site per instance, applications, bindings and certificates, auto-start settings; then start and verify. [CONFIRMED] Preview by default, `-Apply` to change; action `IIS_RECONCILE`: all enabled instances or one, step 50 of `FULL_DEPLOYMENT` (stop on error).

## 2. Inputs

From the catalog of the machine (the whole IIS model is global except the server policy):

| Source | Content (counts at the 2026-10-05 snapshot) |
|---|---|
| `cfg_IisServerPolicy` (1 row per machine; 4 rows exist) | `ReconcileMode` (`CREATE_AND_CORRECT`), `DeleteUnmanagedObjects` (0), `PoolIdentityTemplate`, `CreatePoolIdentityIfMissing` (0), `CertificateSubjectTemplate`, `CertificateStoreName`, `SiteLogDirectoryTemplate`, `SiteAutoStart`, `StartAfterApply` |
| `cfg_IisApplicationDefinition` (30) | path, physical path and pool templates, runtime, pipeline, 32-bit, start mode, queue, profile, recycling, protocols, authentication flags, preload, `IsSiteRoot` (1), `IsRequired` (24) |
| `cfg_IisBindingDefinition` (3) | `HTTP`, `HTTPS` (`SslFlags` 1, uses a certificate), `NET_TCP` (port 808) |
| `cfg_IisDirectoryDefinition` (21) | path template, create if missing, ACL for the pool identity (`FULL_CONTROL` 19, `MODIFY` 2) |
| `cfg_IisPrerequisiteDefinition` (8) | 6 Windows features (installable) and 2 IIS modules (`AspNetCoreModuleV2`, `RewriteModule`, not installable) |
| `cfg_IisServiceAutoStartProviderDefinition`, `cfg_IisApplicationAutoStartDefinition` (1 each) | auto-start providers and applications |
| `dbo_ManagedServer`, `dbo_ManagedInstance` | host name, roots, pool identity user name, SQL and port data used by templates |
| credential package | `IIS_IDENTITY` of each instance (`credentialRef`), the pool identity password |

[CONFIRMED] PRESALES and TENDERS have no server policy row, so the engine stops with "policy missing" there (decision of 2026-10-05). Scale: the largest machine has 21 enabled instances, so about 630 applications and pools (30 definitions each), which is the "hundreds of pools" of ADR-0006 condition 2.

## 3. Steps

Apply order today, kept in the port: prerequisites (IIS-01, IIS-02), auto-start providers (IIS-04), site policy, local identities (IIS-32), configuration backup (IIS-30), directories and ACLs (IIS-31), pools (IIS-06 to IIS-10), sites (IIS-11 to IIS-16), applications (IIS-17 to IIS-22), application auto-start (IIS-05), bindings and certificates (IIS-23 to IIS-29), start and verify. All reads and writes of IIS go through `Microsoft.Web.Administration` (ADR-0006); `netsh.exe` (http.sys certificate registry, IIS-28) and `appcmd.exe` (backup, IIS-30) stay external processes. The model review (9 issue codes for the IIS model and 10 for the extended application model, for example `SERVER_POLICY_MISSING`, `IIS_IDENTITY_PASSWORD_PENDING`, `AUTO_START_POOL_NOT_ALWAYS_RUNNING`) becomes local code and stops the run on errors.

## 4. Side effects

Creates and changes pools, sites, applications, bindings and per-location settings; installs Windows features (if allowed); sets folder ACLs; creates a local account only if `CreatePoolIdentityIfMissing` (0 in all policies); registers certificates in http.sys; stops and restarts pools in the order stop, change, restore state; may restart WAS or W3SVC. Writes a configuration backup and text logs.

## 5. External dependencies

IIS and WAS, `Microsoft.Web.Administration.dll` from `inetsrv`, the certificate stores, `netsh.exe`, `appcmd.exe`, the `LocalAccounts` module (IIS-32), and a mechanism for Windows features under PowerShell 7 [PENDING, IIS-01 after T-01].

## 6. Preview and apply

Preview lists, per object, desired against actual and the kind of change, grouped by phase; it writes nothing. Apply consumes the fingerprint of the confirmed preview and refuses if IIS or the catalog changed. Commits are batched per phase (ADR-0006 condition 4), keeping stop, change, restore state per pool, and a fresh `ServerManager` after any external change.

## 7. Idempotency

A second apply reports no differences. The store name is compared case-insensitively. Objects not defined by the catalog are never touched.

## 8. Failures

- Transient `0x80070425` and WAS or W3SVC not ready: bounded retry and wait (IIS-09, IIS-10); exception types under PowerShell 7 are to be tested (T-09).
- Locked configuration sections or inherited conflicts: a `WARNING` row naming the section, not a silent skip (matrix finding 3, decision pending).
- [PROPOSED] A failure on one object stops that instance's remaining phases, the other instances continue, and the run fails at the end with the counts.
- [PROPOSED] A failed commit leaves the batch unapplied (the commit is atomic) and the backup remains.

## 9. Backup and restore

Back up the IIS configuration before the first change (IIS-30). [PENDING] mechanism: keep `appcmd`, or copy the configuration files directly. [PROPOSED] record a run manifest (backup id, objects changed, before and after values) and test a restore, which is blunt for `appcmd` (the whole configuration), so state its scope in the result (risk R-033; matrix T-11).

## 10. Secret risks

The pool identity password is read from the package in memory, handed to MWA and discarded. The old engine could receive it in the SQL plan or as a credential parameter and wrote reports and a transcript to a run folder (matrix findings 7 and 8). The port writes no transcript of the call and never puts a password in a command line, report, log or backup note; `netsh` and `appcmd` receive none. Marker credential test over every artifact. Certificates: only the hash and store are handled, never private key material.

## 11. What does not port as it is

The four plan procedures become a plan builder over the catalog (analysed here: they raise errors 50010 to 50012 for an unknown machine, missing policy or no matching instance, 53710 to 53712 and 53720 for auto-start problems, and carry the pool password in each row). The WebAdministration cmdlets and the `IIS:\` provider are replaced by MWA; IIS-18 and IIS-20 (folder or virtual directory under a site, conversion to an application) need explicit design. Layer-3 error-text matching for certificate assignment is replaced by a check of the http.sys entry (finding 9). The `Add-Type` load, the SQL context procedure, the SQL parameters and the transcript go.

## 12. Test plan

- Runner (windows-2022 and windows-2025): T-01 features, T-02 `LocalAccounts`, T-03 providers and application auto-start, T-04 folder, virtual directory and conversion cases, T-07 SNI and re-assignment, T-09 transient errors; plus a binding with a certificate in the `WebHosting` store (see 13.1); preview determinism; idempotency; batched commits; a marker pool password in every artifact; a catalog for another machine refused.
- [V] T-05 locked sections, T-06 real pool identities (ADR-0006 condition 3), T-08 central certificate store, T-10 batched commits over hundreds of pools with drift, T-11 backup size and time, and a run on a sandbox with a real topology (condition 2).

## 13. Open questions

1. [PENDING] **The certificate store.** ADR-0006 condition 4 says to standardise the store name as `MY`, but all four server policies use the `WebHosting` store, and the spike used a self-signed certificate in the personal store. Recommendation: treat the store as policy data, compare the case of the name only, test a `WebHosting` binding on the runner, and reword condition 4 to "standardise the case of the name".
2. [PENDING] `DeleteUnmanagedObjects` is 0 in all policies but exists in the model. Recommendation: V1 never deletes.
3. [PENDING] IIS-29 (central certificate store): no catalog binding definition uses that flag (`SslFlags` values 0, 1, 0). Recommendation: out of V1 scope; check real servers for sites that use it [V].
4. [PENDING] The matrix's open points: IIS-01 mechanism, IIS-20 policy (recommend report and require approval when a virtual directory has children or settings), swallowed errors as warnings (recommend yes), backup mechanism.
5. [PENDING] Where the pool identity account (`PoolIdentityTemplate`) lives and who creates it, since no policy allows creating it. Recommendation: a preflight error if it does not exist.
