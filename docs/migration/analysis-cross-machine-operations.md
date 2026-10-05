# Analysis: operations that copy between instances (database copy, environment clone, file copy)

**Status:** [PROPOSED] analysis for review. It closes the open item in the conversion plan 2.4 and decision list 4: "does a catalog need a directory of instances of other machines for database copy, environment clone and folder copy". No product code.
**Date:** 2026-10-05
**Sources (read only):** `database/sync/ManagementSync.sql` of `atsisqual/SISQUALManagementConsole` (29,516,382 bytes, blob `9401e2c3cb2517ca88848f902ff4d3786583e888`, head `9756ba956842884fabcf25b82c4fbf1d11cf56bd`); the `DATABASE_COPY` engine exported from `ops.Engine` (`Invoke-DatabaseCopy.ps1`); the `docs/` folder of the reference repository. Script text is not copied; objects are cited by name.
Tags: [CONFIRMED] read in the source; [PROPOSED] recommendation; [PENDING] needs a decision; [V] needs a real server.

## 1. Answer

1. [CONFIRMED] None of these operations reads another machine or an instance of another machine. Every procedure that creates a plan requires the source and the destination instances to belong to the machine that runs it, and rejects anything else with an error that says so (section 4). In the whole history every plan ran on one machine, with its instances on that machine (two failed plans name an instance that has since been deleted).
2. [PROPOSED] A catalog therefore needs no directory of instances of other machines for these operations. The only reason to carry one is the general links page (task 1c).
3. [CONFIRMED] Data does cross machines in three ways, all as files carried by a person or by a share, never as live reads: a grouped database archive (a ZIP with a protocol name), a software update package, and a file-copy backup ZIP. These are "external sources" and are part of the operation, not of the catalog.
4. [CONFIRMED, new finding] Only `DATABASE_COPY` is an action and an engine of the 19. Environment clone, file copy, archive restore, housekeeping, environment power and the version inventory are features of the old console (SQL-owned plans, approval, a worker); none has a row in `ops.Action` or `ops.Engine`. They are outside "all 19 engines" and need a scope decision (section 7).

## 2. The operations and where they live

| Operation | Plan and state tables (all in `app` unless noted) | Policy tables | Job action codes seen in history | In the 19 engines? |
|---|---|---|---|---|
| Database copy | `DatabaseCopyPlan` (14 rows), `...PlanDestination` (32), `...PlanDatabase` (75), `...PlanOperation` (179), `...PlanEvent`, `...Artifact`, `...DiscoveredDatabase`, `...SourceVersionInventory`, `...RecoveryPlan` | `cfg.DatabaseCopyPolicy` (4, per server), `app.DatabaseCopyPolicy` (1), `app.DatabaseCopyDatabaseDefinition` (1) | `DATABASE_COPY` (3 jobs) | Yes: `DATABASE_COPY`, action `DATABASE_COPY`, wave 9 |
| Database archive restore | `DatabaseArchiveRestorePlan` (3), `...Database` (21), `...Event`, `...Batch`, `...BatchPlan` | the database copy policies | `DATABASE_ARCHIVE_RESTORE` (queue procedure) | No |
| Environment clone | `EnvironmentClonePlan` (51), `EnvironmentCloneComponent` (1,108, all `APPLICATION`), `EnvironmentCloneEvent` | `app.EnvironmentCloneProfile` (5), `cfg.EnvironmentCloneDatabasePolicy` (7), `cfg.ApplicationCopyPolicy` (22) | `ENVIRONMENT_CLONE_PREVIEW`, `ENVIRONMENT_CLONE_APPLY` (5 each) | No |
| File copy (website folders) | `WebsiteFolderCopyBatch` (50), `...BatchPlan` (50), `...Artifact` (3) | `cfg.WebsiteFolderCopyPolicy` (1, has `UpdateRoot`), `cfg.ApplicationCopyPolicy` | queued through the clone plans | No |
| Adjacent | `EnvironmentPowerPlan` (4); `HousekeepingPlan` (29), `HousekeepingPolicy` (8), `HousekeepingStorageSnapshot` (1,364); `DatabaseCopySourceVersionInventory` | `app.HousekeepingPolicy` | `ENVIRONMENT_POWER` (2), `HOUSEKEEPING_PREVIEW` and `_APPLY` (25 each), `VERSION_INVENTORY_SCAN` (27) | No (`STORAGE_SIZE_SCAN` is an engine and feeds housekeeping) |

The plan tables, events and job history are already excluded from the catalogs by the conversion plan (history, plans, approvals). The policy tables are carried: `cfg.DatabaseCopyPolicy` cut by server; the others global.

## 3. How the engine and the plans work

- **`DATABASE_COPY` (engine)** is an interactive script: it resolves the local management context, lists the enabled instances of this machine as a menu, builds the plan from `cfg.GetDatabaseCopyPlan`, and uses native SQL backup (copy-only, with checksum) and restore with verification; it can set the destination single-user and stops and starts the destination IIS around the restore. It has functions that read the SQL engine service account and grant it read access to the backup folder. It reads the source SQL instance and the destination SQL instances by name (always on this machine, see section 4). The copy policy has columns for compression, checksum, single-user switching and IIS stop and start.
- **The studio plans** (database copy, archive restore, clone, file copy) are created in the web application through `app.Create...Plan` procedures, previewed by the worker, approved by hash, and applied by the worker with locks, backups, health checks and rollback. A plan has an expiry and an approved hash.
- **Environment clone** copies the application folders (and optionally databases, IIS and services) from a source to a destination environment, with staging, a file snapshot, safety backups and configuration repair. Its source type is `ENVIRONMENT`, `BACKUP` or `UPDATE`.
- **File copy** copies selected website folders, directly or through a verified ZIP, with a destination safety archive.

## 4. Evidence: every operation is machine-local

[CONFIRMED] Each plan stores the machine that runs it (`MachineName`) and each creation procedure filters instances by it:

| Procedure | Error when the instance is on another machine |
|---|---|
| `app.CreateDatabaseCopyPlan` | 56602 "belongs to another management host" (source), 56605 (destinations) |
| `app.CreateEnvironmentClonePlan` | 56902 source and 56903 destination "not enabled on this host" |
| `app.CreateWebsiteFolderCopyBatch` | 57207 "source environment is unavailable on this management host" |
| `app.CreateDatabaseArchiveRestorePlan` | 56764 destination "not enabled on this management host" |

`app.GetDatabaseCopySourceConnection` builds the SQL data source from the machine name of the instance's server plus the SQL instance name, and only for instances of `@MachineName`. `app.GetEnvironmentCloneRuntime` builds the source and destination SQL data sources the same way, from the machine name of each instance's server; the machine filter itself is in the creation procedures above.

**History** (2026-10-05 snapshot):

| Plans | Count | Source on the running machine | Destinations on the running machine |
|---|---:|---|---|
| Database copy | 14 | all 14 (run on 2 machines) | all |
| Archive restore | 3 | all | all |
| Environment clone | 51 | 17 `ENVIRONMENT`; 30 `UPDATE` and 4 `BACKUP` have an external source | 49; the other 2 are failed plans whose destination instance `SANDBOXROOT` no longer exists |
| File copy batches | 50 | 16 `ENVIRONMENT`; 30 `UPDATE`, 4 `BACKUP` | 48; same 2 failed plans |

The source SQL data source of every database copy plan names the running machine.

## 5. What crosses machines, and how

| Item | Mechanism | Evidence |
|---|---|---|
| Grouped database archive | a ZIP created by a database copy (`CreateGroupedArchive`, protocol `SISQUAL_DATABASE_COPY_ARCHIVE_V2`) and restored by an archive restore plan on another machine; the plan takes an archive path and a hash | `app.DatabaseArchiveRestorePlan` columns `ArchivePath`, `ArchiveHash`, `ArchiveProtocol` |
| Software update package | clone and file copy with source type `UPDATE`; the reference is a JSON with a package id; the root is `UpdateRoot` of `cfg.WebsiteFolderCopyPolicy` and `UpdateSourceFamily` and `UpdateSourceRelativePath` of `cfg.ApplicationCopyPolicy` | 30 of 51 clone plans |
| File-copy backup | a verified ZIP (`TransferMode` `ARCHIVE`) kept as an artifact; clone source type `BACKUP` | 4 plans, `app.WebsiteFolderCopyArtifact` |

## 6. Impact of "V1 executes locally"

1. **Data flow: none.** The old system already ran locally. Moving to the portable changes nothing about which instances can be a source or a destination.
2. **Catalog: nothing to add.** The local instances come from `dbo_ManagedInstance` of the machine; the policies are carried. Machines without a row in `cfg_DatabaseCopyPolicy` (PRESALES, TENDERS, new machines) get "policy missing", as decided.
3. **Plan and approval state.** Plans, events, approval hash and expiry lived in `app` tables; ADR-0007 gives the application no database. [PENDING] where a plan lives between preview and apply (memory of the running process, or a text file in the log folder).
4. **Interactive menus.** `DATABASE_COPY` asks the operator in the console; in the portable the choice comes from the browser.
5. **A gap in the version update path.** 30 of the 51 clone plans were software updates deployed from an update package. Nothing in the 19 engines does that. See 7.

## 7. Recommendation and [PENDING] decisions

[PROPOSED] recommendations, none is an owner decision:

1. Close the open item of the conversion plan 2.4: no instance directory for database copy, environment clone or file copy; the directory exists only for the links page (task 1c).
2. Port `DATABASE_COPY` (wave 9) for local source and destinations only. Moving a database to another machine is done through a grouped archive carried as a file; the engine spec states the archive format and hash check.
3. Treat environment clone, file copy, archive restore, housekeeping, environment power and the version inventory as features outside the 19 engines.

[PENDING] for the owner, each with a recommendation:

1. **Scope.** Are those six features in V1? Recommendation: not in V1 as part of "all 19 engines"; plan them as a separate phase after wave 9, in this order: file copy and update deployment, archive restore, environment power, clone, version inventory, housekeeping.
2. **Software updates.** How are application versions deployed to managed instances in V1, given that the clone with source type `UPDATE` is the current way? Recommendation: decide before wave 5, because `FULL_DEPLOYMENT` assumes the files are already there.
3. **Where a plan lives** between preview and apply (item 3 of section 6). Recommendation: a signed text file in the log folder with the plan hash and expiry; the apply rereads and revalidates it.
4. **Archive restore into V1.** Recommendation: include it in the `DATABASE_COPY` spec as the way to move databases between machines.

## 8. Test plan for `DATABASE_COPY`

- Runner: backup and restore with SQL Server LocalDB (the runner image has it; collation set explicitly), checksum and verify, restore file mapping with several data and log files, single-user and multi-user switching, IIS stop and start on the runner, a refusal when source or destination is not on this machine, no secret in any log, a plan that expired or whose hash changed is refused.
- [V] Real SQL Server instances, volumes and disk-space safety margin, the service account rights on the backup folder, the effect on a live site.
