# Engine port specification: DATABASE_COPY

**Status:** [PROPOSED] specification for review (task 3, wave 9). No product code.
**Date:** 2026-10-05
**Sources (read only):** `ops.Engine` row `DATABASE_COPY` of `database/sync/ManagementSync.sql` of `atsisqual/SISQUALManagementConsole` (file `Invoke-DatabaseCopy.ps1`, version `6.0`, 1,064 lines, Windows PowerShell 5.1, requires administrator, stored `ScriptSha256` `95A51533...`; reference head `9756ba956842884fabcf25b82c4fbf1d11cf56bd`); the action `DATABASE_COPY`; the procedure `cfg.GetDatabaseCopyPlan`; the analysis of the copy and clone operations (task 1b, PR #28) and the specification of `DATABASE_CONTENT_SYNC` (wave 5, PR #39). Script text is not copied and no secret value appears here.
Tags: [CONFIRMED] read in the source; [PROPOSED] recommendation; [PENDING] needs a decision; [V] needs a real server.

## 1. Purpose

Copy the databases of one environment over the databases of one or more other environments of the same machine, safely: one compressed backup of the source, a verified safety backup of what will be overwritten, a restore, and the follow-up steps. [CONFIRMED] Action: group `DATABASES`, preview and apply, no instance selection (the engine asks), no timeout, hidden from the menu (the old web studio was the main interface). It is **destructive**: it overwrites databases of other environments.

## 2. Inputs

| Source (catalog) | Content |
|---|---|
| `cfg_DatabaseDefinition` (7 rows, all required) | `SISQUAL_FORECAST`, `SISQUAL_FORECAST_DATA`, `SISQUAL_PONTO_HISTORICO`, `SISQUAL_VIEW`, `SISQUAL_WFM`, `SP_DADOS_HISTORICO`, `SP_DADOS_TEMP`; `CopyEnabled`, `RunPhysicalCheck`, `PostRestoreOwner` |
| `cfg_DatabaseCopyPolicy` (1 row per machine; 4 exist) | backup file name template, copy-only, compression, checksum, verify, replace existing, single-user, multi-user, stop and start the destination IIS, sync database settings after the copy (all 1) |
| `dbo_ManagedInstance`, `dbo_ManagedServer` | each environment has its **own SQL Server instance** on the machine (76 named instances, 6 to 21 per machine) and the same database names; host name for the IIS site |
| `app_DatabaseCopyPolicy`, `app_DatabaseCopyDatabaseDefinition` | studio settings (retention 7 days, disk safety multiplier 1.25, plan validity 60 minutes, grouped archive): not used by the engine |

Credentials: none; the engine uses the Windows identity of the operator on the local SQL instances. Parameters: sources, destinations, databases, apply, skip settings sync.

## 3. Steps

1. Review the model locally; stop on errors. At least two enabled instances must exist.
2. Choose the source (one or more plans), the destination instances (not the source) and the databases. [CONFIRMED] `cfg.GetDatabaseCopyPlan` rejects the same instance as source and destination (50100) and any instance not enabled on this machine (50101 to 50103).
3. Show the plan. Preview stops here. Apply requires the typed word `COPY`.
4. In the source SQL instance's default backup folder create **exactly one compressed copy-only backup per database**, with checksum, and verify it; grant read access on the folder to each destination SQL service account.
5. Check that every destination can read each backup (file list).
6. Per destination: stop its IIS site and application pools (remembering which were started); per database: if the destination database exists, take a **safety backup** (copy-only, compressed, checksum) in the destination's backup folder and verify it; restore from the shared backup over the existing database (single-user with rollback of open sessions, replace, files moved to the destination's default folders, back to multi-user); optionally run a physical check.
7. If the policy says so and settings sync is not skipped, run the settings sync for the destination.
8. In every case start the IIS site and pools again that were started; write the results.

## 4. Side effects

Overwrites 7 databases per destination; leaves the source backups in the source backup folder (no cleanup) and the safety backups in each destination's folder; changes folder permissions for SQL service accounts; stops and starts IIS sites and pools (the destination is unavailable for the whole copy); sessions are cut by the single-user switch.

## 5. External dependencies

The local SQL Server instances (backup and restore permissions), the backup folders and disk space, IIS (site and pool state), the SQL service accounts, the settings sync.

## 6. Preview and apply

[PROPOSED] A deterministic plan that lists, per destination and database, what will be overwritten, and checks free space on the backup and data volumes with a safety margin (the studio default is 1.25 times the size) before apply. Apply consumes the fingerprint of the plan, expires after a time (the studio default is 60 minutes) and needs the confirmation word.

## 7. Idempotency

Not idempotent by nature: each run copies the current source. File names include a timestamp, so runs do not collide. A repeated run is safe only because of the safety backup.

## 8. Failures

[CONFIRMED] A failure at one destination stops that destination (a `finally` restarts its IIS) and the others continue; the run fails at the end with the list. After a failed restore the engine tries to put the database back to multi-user; the destination database may be restoring or gone. [PROPOSED] Report exactly what state each destination database is in and the safety backup file to restore from.

## 9. Backup and restore

The safety backup is the undo. [PROPOSED] A run manifest (source, destinations, database, backup files and sizes, hashes of the verify results) and a tested **restore from safety backup** function (risk R-033); the engine is not enabled until that test passes. Old source and safety backups are removed by the retention policy (7 days in the studio; the housekeeping ceilings are 500 GB and 1,000 GB), which is a feature outside the 19 engines [PENDING].

## 10. Secret risks

- No credentials are used. The databases themselves hold customer data and, in `Settings`, values such as the mobile application token and URLs of the source environment.
- [CONFIRMED] The post-copy settings sync rewrites those values for the destination; **skipping it leaves the destination pointing at the source's settings**. [PROPOSED] Make skipping an explicit, logged choice shown in the plan.
- Backups are readable by the SQL service accounts and administrators; they contain all data. [PROPOSED] Restrict the folders, remove the grants after the run, and never copy backups out of the machine without the archive process (below).
- Logs and results contain names, counts and file names only.

## 11. What does not port as it is

The interactive menus become browser choices; the script that calls itself once per source becomes a loop in one operation; the central procedures (model review, plan, context, `dbo.SyncDatabaseSettings`) go: the plan comes from the catalog and the settings sync is the `DATABASE_CONTENT_SYNC` module run against the destination. IIS stop and start use the WebAdministration provider, which does not work under PowerShell 7: use `Microsoft.Web.Administration`. The transcript and the run folder become the text log and the manifest. The Keycloak database is not in the copy set; its rows are handled by the settings sync.

## 12. Test plan

- Runner: two SQL Server LocalDB named instances with small databases that have several data and log files; plan and preview; apply with the confirmation word; the source backup, its verify, readability by the destination, the safety backup and its verify, restore with moved files and replace, single-user and back to multi-user, the physical check; failure injection at each stage (backup, verify, safety backup, restore, settings sync) and the resulting state and IIS restart; restore from the safety backup; same source and destination refused; an instance of another machine refused; destination not online; low disk space refused; plan expiry and fingerprint change; compression where LocalDB supports it, otherwise a test that the option is emitted; IIS site stop and start through MWA; no secret in any artifact.
- [V] Real instances: sizes of tens or hundreds of gigabytes, time, service-account folder rights, antivirus on backup files, disk space on the real volumes.

## 13. Open questions

1. [PENDING] **Which source and destination pairs are allowed.** Instances belong to customers and demos; copying one over another moves customer data between environments and destroys the destination's. Recommendation: an allowlist of pairs (or a "may be overwritten" flag on the destination) in the catalog, checked in the plan.
2. [PENDING] Moving databases to **another machine** is not done by this engine (all plans in the history were local); the old studio did it through a grouped archive. Recommendation: include archive creation and restore in this engine's scope (decision proposed in the analysis of copy operations).
3. [PENDING] Cleanup of source and safety backups: retention and who deletes (recommend a retention in the policy and a cleanup step that never deletes the newest safety backup of a destination).
4. [PENDING] Whether the settings sync after the copy is mandatory (recommend yes unless explicitly skipped and logged).
5. [PENDING] Whether the destination's Keycloak database should be refreshed or reset after a copy.
6. [PENDING] The permissions of the operator on the SQL instances (backup and restore, the logon rights) [V].

## Host contract

- Engine class: `MUTATING`.
- Credential references: none.
