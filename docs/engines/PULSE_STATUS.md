# Engine port specification: PULSE_STATUS

**Status:** [PROPOSED] specification for review (task 3, wave 1). No product code. It builds on `docs/migration/analysis-pulse.md` (PR #27, which records the owner answers of 2026-10-05); merge that PR first.
**Date:** 2026-10-05
**Sources (read only):** `ops.Engine` row `PULSE_STATUS` of `database/sync/ManagementSync.sql` of `atsisqual/SISQUALManagementConsole` (file `Invoke-SISQUALPulseStatus.ps1`, version `v2`, Windows PowerShell 5.1, requires administrator, stored `ScriptSha256` `60917424...`; reference head `9756ba956842884fabcf25b82c4fbf1d11cf56bd`); the action `PULSE_STATUS`; the Pulse procedures. Script text is not copied.
Tags: [CONFIRMED] read in the source; [PROPOSED] recommendation; [PENDING] needs a decision; [V] needs a real server.

## 1. Purpose

Deploy and run the "System Pulse" page of a hub instance: a branded static page, a collector that checks the HTTPS health of the applications of every enabled instance of the hub's machine and country once a minute, and a status file the page reads. [CONFIRMED] Action `PULSE_STATUS`: group `HEALTH`, preview and apply, no instance selection, 900 s timeout, hidden from the menu, step 75 of `FULL_DEPLOYMENT` (stop on error). Four hubs exist: DEMOBR, DEMOES, DEMOPT, SANDBOXMAIN.

## 2. Inputs

From the catalog of the hub's machine (see section 7 of the analysis for the table list): `cfg_PulseProfile` (1 row: titles, `RelativeDirectory`, `PublicUrlTemplate`, `StatusFileName`, `ScheduledTaskName`, interval 1, refresh 30, stale 300, yellow 1, red 3, `ScopePolicy`), `cfg_PulseHttpPolicy` (12 rows, 11 enabled: all `GET`, timeout 12 s, healthy `200-399`, responding `401,403` treated as healthy, redirects followed), `cfg_PulseResource` (3 rows with `ContentSha256`), `cfg_WebsiteBrandingProfile` and `cfg_WebsiteBrandingAsset` (global), `cfg_Application`, `dbo_ManagedServer` (`ServicesRoot`, `ConfigBackupRoot`, `MachineName`), `dbo_ManagedInstance` (`InstanceCode`, `HostName`, `CountryCode`, `CustomerCode`, `CustomerName`, `IsEnabled`). Credential: `IIS_IDENTITY` of the hub instance (`credentialRef`). Parameters [PROPOSED]: `HubInstanceCode` (optional), `Apply`.

## 3. Steps

**Preview / apply (operator):**
1. Resolve the hub: the given code, or the enabled profile whose hub instance is on this machine. [DECIDED, "Ok"] A machine without a profile reports "not applicable", not an error.
2. Review the model locally (codes `PULSE_HUB_NOT_FOUND`, `PULSE_TASK_CREDENTIAL_MISSING`, `PULSE_RESOURCE_HASH_MISMATCH`, `PULSE_HTTP_APPLICATION_MISSING`, `PULSE_PAGE_TEMPLATE_MISSING`, `PULSE_LOGO_MISSING`, plus the branding review); any error stops.
3. Resolve the page directory (`ServicesRoot` + host name + `RelativeDirectory`), the public URL and the status path; expand the page template with the 7 tokens (document title, page title, description, logo file, status file, refresh, stale); any unresolved token is an error.
4. Resolve the check plan: for each enabled instance of the same machine and country and each enabled policy, the target URL, method, status specs, timeout, required flag.
5. Preview prints hub, URL, directory, task name, interval, number of endpoints, and whether the task, page, plan file and branding differ from what is installed. It writes nothing.
6. Apply: back up the existing page, web config, logo and collector files; write the branding assets (hash verified), page, web config and logo atomically; write the resolved plan file next to the status file; grant modify rights on the page and collector directories to the task identity; register the scheduled task; run one collection.

**Collection (scheduled task, every interval):** read the plan file and the previous status file; run the checks; classify; write the status file atomically; append one line to the text log. It needs no catalog and no database.

## 4. Side effects

Files under the hub's IIS site (page, config, logo, assets, status file, plan file), branding files in the website root, the ACL of two directories, a Windows scheduled task running as the hub's IIS identity, backups under `ConfigBackupRoot\Pulse\<timestamp>`, text logs. No database writes (the old `ops.PulseCheckState` and `ops.PulseRun` are gone).

## 5. External dependencies

IIS site on the hub (files only), the scheduler service, HTTPS endpoints of the same machine's instances, the file system and ACLs, the portable `pwsh.exe` for the collector (decided: at its current path). [PENDING] the `ScheduledTasks` cmdlets under PowerShell 7 (test below); fallback the scheduler COM interface or `schtasks.exe`.

## 6. Preview and apply

Preview is deterministic and compares installed against desired: page hash, config hash, logo hash, branding hashes, plan hash, and the task (registered, action path, user, interval, last run time and result). Apply consumes the plan fingerprint of the confirmed preview and refuses if the inputs changed. [DECIDED, "Pode ser"] The task runs `pwsh.exe` from the portable at its current path; apply re-registers it, and preview shows a changed action path after the folder is replaced. How refreshes work (page, task credentials, plan) is in section 9a of the analysis.

## 7. Idempotency

Apply rewrites only files whose hash differs and re-registers the task only when it differs or its credential may be stale (the password cannot be read back, so apply may always re-register with the current credential). A second apply with no change reports no changes. The collection is idempotent per run.

## 8. Failures

- Model error or unresolved token: nothing is written.
- A write failure after the backup: restore the backed-up files for this run, report which were restored.
- Task registration failure (bad identity, password, policy): files stay, the result says the task is not registered and the page will go stale.
- A check that cannot connect: `FAILED` with the message; counters continue from the previous status file; yellow at 1 failure, red at 3. A missing or unreadable previous file restarts counters at zero and logs it.
- Status older than the stale limit is shown as unknown by the page; a collector that cannot finish within the interval leaves the file stale.
- [CONFIRMED] Worst case in the data: 231 sequential checks at 12 s each is 46 minutes, above the 1-minute interval and the 10-minute task limit (the old task ignores a new run while one is active).

## 9. Backup and restore

Copy the four files the old engine backed up (page, config, logo, collector) plus the plan file, and [PROPOSED] the previous ACL of the two directories (as text) and the previous task definition (exported text, no password). Restore puts files back atomically and re-applies the ACL; the task is re-registered from the exported definition with the current credential. Restore is tested before the engine is enabled (risk R-033).

## 10. Secret risks

The task password is the hub instance's IIS identity, passed once to the scheduler and never to the log, result, plan file, status file or backup. The scheduler's stored credential cannot be read back. Plan file and status file contain only URLs, codes and statuses. Test with a marker credential over every artifact.

## 11. What does not port as it is

Recording each run, the state between runs and the per-run plan and snapshot reads used the central database (analysis section 6): replaced by a text log line, the previous status file, and the plan file. The collector is no longer a copy of the engine; hard-coded `DEMOPT` texts become the hub code; `ScopePolicy` keeps today's behaviour and its value is renamed by a manual catalog edit [DECIDED, "Aceito"].

## 12. Test plan

- Runner: model review and plan building from a synthetic catalog; token expansion and the unresolved-token error; hash checks; apply, backup, atomic write and restore; the collector against a local test server (healthy, 401 and 403 treated as healthy, redirect, 500, timeout, refused); threshold 1 and 3; stale file; counters continued from the previous file; no secret anywhere (marker); scheduled task registered with a throw-away local user, run once, then removed; `ScheduledTasks` under PowerShell 7; not-applicable on a machine without a profile.
- [V] A real hub with the real identity, applications and ACLs; one-minute cadence over several days; the effect of 231 checks on a busy server.

## 13. Open questions

1. [DECIDED 2026-10-07] Sequential checks cannot finish in the worst case (section 8). Recommendation: bounded parallelism (for example 16) with an overall deadline shorter than the interval.
2. [DECIDED 2026-10-07] Certificate validation of the HTTPS checks (self-signed or private authority). Recommendation: validate by default and make an exception an explicit catalog setting.
3. [DECIDED 2026-10-07] Which scheduler interface to use if `ScheduledTasks` does not load under PowerShell 7 (recommend the COM interface).
4. [DECIDED 2026-10-07] The branding assets are global files written into every hub's website root: confirm they are part of this engine and not of `MANAGED_ASSETS`. Recommendation: keep them here, as today.

The owner accepted the recommendation of all four ("Aceito as 8 sugestoes", 2026-10-07, covering this engine and the other wave 1 engine); see `docs/decisions-log.md`.
