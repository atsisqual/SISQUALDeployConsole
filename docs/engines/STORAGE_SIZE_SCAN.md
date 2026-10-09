# Engine port specification: STORAGE_SIZE_SCAN

**Status:** [PROPOSED] specification for review (task 3, wave 7). No product code.
**Date:** 2026-10-05
**Sources (read only):** `ops.Engine` row `STORAGE_SIZE_SCAN` of `database/sync/ManagementSync.sql` of `atsisqual/SISQUALManagementConsole` (file `STORAGE_SIZE_SCAN.ps1`, version `1.0`, Windows PowerShell 5.1, administrator not required, stored `ScriptSha256` `CCB0E9D5...`; reference head `9756ba956842884fabcf25b82c4fbf1d11cf56bd`); the action `STORAGE_SIZE_SCAN` and the table `app.HousekeepingPolicy` (8 rows). Script text is not copied and no secret value appears here.
Tags: [CONFIRMED] read in the source; [PROPOSED] recommendation; [PENDING] needs a decision; [V] needs a real server.

## 1. Purpose

Measure the real size and number of files of each housekeeping policy's folders, so that a screen can show usage against the ceiling. [CONFIRMED] A read-only scan; the action is in group `HEALTH`, preview and apply, no instance selection, 300 s timeout, hidden from the menu. It does not delete or move anything (cleanup is a separate feature of the old console, outside the 17-engine portable catalog). Reviewer evidence from the six real converted catalogs used `SELECT COUNT(*) AS EngineCount FROM ops_Engine;` and returned `17` in each catalog.

## 2. Inputs

`app_HousekeepingPolicy` (8 enabled rows): policy code, root path template, file pattern, `MaximumTotalSizeGB`. Roots use the host name and the temporary-folder token, and may contain a wildcard.

| Policy | Ceiling (GB) | How it is measured |
|---|---:|---|
| `APPLICATION_LOGS` | 100 | per host: every folder under the host's log folder except `IIS` |
| `IIS_LOGS` | 50 | per host: the `IIS` folder only |
| `CONFIG_BACKUPS` | 100 | one aggregate |
| `CLONE_SNAPSHOTS` | 300 | one aggregate |
| `DATABASE_COPY` | 500 | one aggregate |
| `SQL_NATIVE_DATABASE_COPY` | 1,000 | the default backup folder of each local SQL instance, once per distinct folder, plus the same figure for each instance that shares it |
| `WORKER_TEMP` | 5 | wildcard folders under the temporary folder, one aggregate |
| `STORAGE_SNAPSHOTS` | 0 | a table of the old console (rows, not files): not applicable |

Also the instances of this machine (host names, SQL data sources).

## 3. Steps

1. Resolve the machine and its enabled instances; read the enabled policies.
2. For each policy measure as in the table: sum the size of files and count them; a missing folder is 0.
3. The SQL native roots are resolved by asking each local SQL instance for its default backup path.
4. Preview prints what would be recorded; apply records one row per policy and instance (policy, instance or none, bytes, file count, time).

## 4. Side effects

None on the machine. [CONFIRMED] Apply writes snapshot rows into a table of the central database (1,364 rows in the history of the reference snapshot); the port has no database.

## 5. External dependencies

The file system (roots can be large and may be on other volumes), the local SQL instances for one question each.

## 6. Preview and apply

[PROPOSED] A single measurement that returns the result. Recording is the open point 13.1.

## 7. Idempotency

Repeatable; each run is a new measurement.

## 8. Failures

[CONFIRMED, defect] Errors while walking folders are silently ignored, so an unreadable folder makes the figure too small without a trace; and the walk loads every file object into memory before summing. [PROPOSED] Stream the enumeration, count unreadable items and report them as a warning with the number, and stop at a time budget (300 s) reporting a partial figure marked as such. A SQL instance whose backup path cannot be resolved is a warning for that root.

## 9. Backup and restore

Not applicable.

## 10. Secret risks

None: paths, sizes and counts. Folder names can contain customer host names; they are not secrets.

## 11. What does not port as it is

- The central snapshot table and the context procedure go.
- [CONFIRMED] A hard-coded folder of the old management console (`management.sisqualwfm.cloud`) is measured as a pseudo-instance in the two log policies: the console does not exist in V1; drop it.
- The `STORAGE_SNAPSHOTS` policy measures the snapshot table itself: not applicable.
- Several policies point at folders of features outside the 17-engine portable catalog (clone snapshots, database-copy artifacts); they can still be measured if the folder exists.

## 12. Test plan

- Runner: temporary trees with many files; the two log splits; excluded subfolders and loose files; wildcard roots; an unreadable folder counted and reported; a symbolic link loop; a missing root; the time budget with a partial result; shared SQL backup roots counted once in the aggregate and repeated per instance; LocalDB default backup path; no recording on preview.
- [V] Real roots: a folder of hundreds of gigabytes and millions of files, and the time it takes.

## 13. Open questions

1. [PENDING] Where measurements are kept. Recommendation: one JSON line per measurement in a history file in the log folder (latest and a bounded history), read by the screen.
2. [PENDING] Whether a measurement may exceed the time budget when the owner asks for a full scan. Recommendation: yes, as an explicit option.
3. [PENDING] Gigabytes: decimal or binary for the ceilings. Recommendation: binary, stated in the screen.

## Host contract

- Engine class: `OBSERVATIONAL`.
- Credential references: none.
