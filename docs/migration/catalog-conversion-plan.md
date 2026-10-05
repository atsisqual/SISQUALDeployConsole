# Catalog conversion plan (task 4, step A)

**Status:** [PROPOSED] plan only. No code. Nothing here is approved; step B (implementation) starts only after the owner approves this plan.
**Depends on:** ADR-0007 (proposed, PR #11), `contracts/` drafts (PR #13), owner decisions of 2026-10-05.
**Does not change:** `docs/decisions-log.md`, `docs/roadmap.md` (the reviewer records decisions).
Tags: [CONFIRMED] read from the source or decided by the owner; [PROPOSED] design proposal; [PENDING] open decision; [V] only verifiable on a real server.

## 0. Scope, source and what was actually read

Owner decisions that drive this plan [CONFIRMED]:

- `_sisqualMANAGEMENT` (SQL Server) ceases to exist. Configuration becomes read-only SQLite files, ONE PER EXISTING MACHINE (`ServerCode`); machines in `dbo.ManagedServer`: PT_DEMO, SANDBOX_HUB, ES_DEMO, BR_DEMO, PRESALES, TENDERS.
- Engines become files and are exported separately as the base for the port. Credentials never enter a catalog.
- The pilot is on a server without the current system, so catalogs for NEW machines are prioritised (see 2.6).
- Sync SQL is read-only when a local database exists; the case of machines without a database is undecided and nothing is assumed here.
- The sync contract no longer exists; it becomes the signed package manifest plus the per-machine catalog schema (`contracts/`).

Source read, read-only [CONFIRMED]:

| Item | Value |
|---|---|
| Repository | `atsisqual/SISQUALManagementConsole`, branch `master`, head `9756ba956842884fabcf25b82c4fbf1d11cf56bd` (2026-10-05T01:00:43Z) |
| File | `database/sync/ManagementSync.sql`, blob `9401e2c3cb2517ca88848f902ff4d3786583e888` |
| Size | 29,516,382 bytes (matches the GitHub listing); SHA-256 of the downloaded bytes `9982f088188c0cdd34522a8b34cb3db26ac9ba1196af81920e4d31d9a71ddbf1` |
| Header | `_sisqualMANAGEMENT sync script - generated 2026-10-05 02:00:01` |
| Method | read in parts by statement (the longest line is a 268 KB image INSERT, so line tools truncate); tables, columns and keys parsed from the `CREATE TABLE` blocks; rows counted from the `INSERT` statements |
| Content | 117 tables (schemas `app`, `cfg`, `dbo`, `ops`, `sec`, `ui`), 103 with rows, 31,959 rows in total, about 28.1 MB of INSERT text; 6 views, 200 stored procedures, 5 functions, 5 triggers |

Important limits of this source [CONFIRMED]:

- The file is a data and key snapshot, not the full schema: it has primary keys only. No foreign keys, no CHECK constraints, no defaults and no indexes appear in it. The live database may have them (see 1.2).
- The 191 rows of `sec.ManagedCredential` are ciphertext made by a SQL Server symmetric key protected by a certificate that lives in the live database (`SISQUAL_ManagedCredential_Key` and `SISQUAL_ManagedCredential_Certificate`, authenticator `InstanceCode|CredentialType`). They cannot be decrypted from this file (see 4.2).

## 1. Table-by-table map

### 1.1 Type conversion (SQL Server to SQLite)

[PROPOSED] Tables are created `STRICT` (SQLite 3.37 or later; the pinned engine is 3.53.4). Counts are the columns of the 117 source tables.

| SQL Server type (columns) | SQLite type | Rule |
|---|---|---|
| `bit` (248) | `INTEGER` | `CHECK (col IN (0,1))`; NULL kept |
| `int`, `bigint` (127, 46) | `INTEGER` | exact |
| `identity` (24 columns; 4 in included tables: `cfg.ConfigFile.FileID`, `cfg.ConfigRule.RuleID`, `cfg.DatabaseObjectSettingRule.ObjectSettingRuleID`, `cfg.DatabaseSettingRule.SettingRuleID`) | `INTEGER PRIMARY KEY` | source values are kept (the source script uses `SET IDENTITY_INSERT`); no `AUTOINCREMENT` because the file is read-only |
| `varchar`, `nvarchar`, `sysname`, `nvarchar(max)` | `TEXT` | UTF-8; `CHECK (length(col) <= N)` for bounded types |
| `char(n)` (`char(64)` hashes, `char(2)` country, `char(7)` colour) | `TEXT` | right-trimmed on read, `CHECK (length(col) = n)` |
| `uniqueidentifier` (62) | `TEXT` | lower-case canonical form, `CHECK (length(col) = 36)` |
| `datetime2` (187) | `TEXT` | the source value is kept unchanged, ISO 8601 with `T`, no zone. See the warning below |
| `decimal(p,s)` (5) | `TEXT` | canonical decimal string; no arithmetic is done on them in a read-only catalog |
| `varbinary(max)` (6; 4 in included tables) | `BLOB` | see the BLOB decision in section 2.5 |
| `timestamp` / rowversion (11; 7 in included tables) | not converted | meaningless offline. Columns dropped: `app.Product.RowVersion`, `cfg.SettingDefinition.RowVersion`, `cfg.SettingValue.RowVersion`, `ops.ActionUiMetadata.RowVersion`, `ui.NavigationItem.RowVersion`, `ui.PublishedEnvironmentLink.RowVersion`, `ui.Resource.RowVersion` |
| `binary(8)` (3, all in excluded tables) | not converted | |

Warning on time values [CONFIRMED]: the sampled values come from `SYSDATETIME()` (the server's local time, for example `2026-10-03 01:18:15.8109469`), so they carry no time zone and are not UTC. Converting them as UTC would be wrong. [PROPOSED] keep them as text without a zone and say so in the catalog documentation. This corrects the draft text of `contracts/catalog-schema.md` (section 3), which said UTC; the correction is made in PR #13.

Collation [PENDING]: SQL Server comparisons depend on the database collation (usually case-insensitive). SQLite compares text case-sensitively by default. The conversion tool must read the collation (`DATABASEPROPERTYEX`) and the plan is to declare key columns (`ServerCode`, `InstanceCode`, `ApplicationCode` and other code columns used in joins) `COLLATE NOCASE`. `NOCASE` only folds ASCII; accented codes would differ. The collation of the live database is not in the file and must be read [V].

### 1.2 Constraints

- [CONFIRMED] 114 of the 117 tables have a primary key (`PK_<table>_sync`); the three tables without a key are copies (`ops.Action_BackupPhase1`, `ops.Engine_BackupIisFix`, `ops.MenuGroup_BackupPhase1`) and are excluded.
- [CONFIRMED] Composite keys among included tables: `app.VersionBaseline`, `cfg.LinksPageInstanceApplication`, `cfg.LinksProfileApplication`, `cfg.LinksProfileInstance`, `cfg.ManagedAssetDestination`, `cfg.SettingValue`, `ops.ActionRequirement`, `ops.ActionStep`, `sec.WindowsGroupPolicy`, `ui.Resource`.
- [PROPOSED] Primary keys are carried over as they are. Foreign keys, CHECKs, defaults and indexes: when the tool reads the live server it reads them from `sys.foreign_keys`, `sys.check_constraints`, `sys.default_constraints` and `sys.indexes` and recreates the ones that involve only included tables. When only the sync file is available (CI), no foreign keys exist, so the tool applies a small, explicit list of derived relationships by column name (`InstanceCode` to `dbo.ManagedInstance`, `ServerCode` to `dbo.ManagedServer`, `ApplicationCode` to `cfg.Application`, `FileID` to `cfg.ConfigFile`, `ProfileCode` to `cfg.LinksProfile`, `ActionCode` to `ops.Action`) and reports violations instead of failing silently. [PENDING] the owner confirms the list.
- [CONFIRMED] Data quality: 5 rows of `cfg.LinksProfileInstance` point to instance codes that do not exist in `dbo.ManagedInstance`. Cut by instance they belong to no machine, so they are dropped and listed in the conversion report (see 2.4).
- [PROPOSED] Every catalog is verified with `PRAGMA integrity_check`, `PRAGMA foreign_key_check` and `PRAGMA quick_check` and is opened read-only (`mode=ro`, `PRAGMA query_only = ON`).

### 1.3 Map of all 117 tables

Class: **Global** = identical in every catalog; **Cut** = only the rows of the machine; **Excluded** = not carried. Row counts are from the INSERT statements of the file. Summary: 51 global, 7 cut by `ServerCode`, 4 cut by `InstanceCode`, 55 excluded (62 tables carried, 1,618 rows carried of 31,959; 30,341 rows of history, plans, audit and state are left behind). SQLite names are `<schema>_<Table>` (SQLite has one namespace per file). Table names of excluded tables are shown for completeness.

| Source table | Rows | Class | SQLite table | Primary key | Note |
|---|---:|---|---|---|---|
| `app.ActionRuntimePolicy` | 10 | Global | `app_ActionRuntimePolicy` | `ActionCode` | action runtime limits |
| `app.ConfigurationChange` | 0 | Excluded | - | `ChangeID` | configuration studio workflow (replaced by manual catalog edit + seal tool) |
| `app.ConfigurationChangeSet` | 0 | Excluded | - | `ChangeSetID` | configuration studio workflow (replaced by manual catalog edit + seal tool) |
| `app.ConfigurationSnapshot` | 0 | Excluded | - | `SnapshotID` | configuration studio workflow (replaced by manual catalog edit + seal tool) |
| `app.DatabaseArchiveRestoreBatch` | 0 | Excluded | - | `BatchID` | operation plan or history |
| `app.DatabaseArchiveRestoreBatchPlan` | 0 | Excluded | - | `BatchID, PlanID` | operation plan or history |
| `app.DatabaseArchiveRestoreDatabase` | 21 | Excluded | - | `PlanID, EntryPath` | operation plan or history |
| `app.DatabaseArchiveRestoreEvent` | 16 | Excluded | - | `EventID` | operation plan or history |
| `app.DatabaseArchiveRestorePlan` | 3 | Excluded | - | `PlanID` | operation plan or history |
| `app.DatabaseCopyArtifact` | 59 | Excluded | - | `ArtifactID` | operation plan or history |
| `app.DatabaseCopyDatabaseDefinition` | 1 | Global | `app_DatabaseCopyDatabaseDefinition` | `DatabaseCode` | action runtime limits |
| `app.DatabaseCopyDiscoveredDatabase` | 37 | Excluded | - | `MachineName, SourceInstanceCode, DatabaseCode` | discovered or measured state (inventory, snapshots) |
| `app.DatabaseCopyPlan` | 14 | Excluded | - | `PlanID` | operation plan or history |
| `app.DatabaseCopyPlanApplicationVersion` | 540 | Excluded | - | `PlanID, InstanceCode, ApplicationCode` | operation plan or history |
| `app.DatabaseCopyPlanDatabase` | 75 | Excluded | - | `PlanID, DatabaseCode` | operation plan or history |
| `app.DatabaseCopyPlanDestination` | 32 | Excluded | - | `PlanID, DestinationInstanceCode` | operation plan or history |
| `app.DatabaseCopyPlanEvent` | 88 | Excluded | - | `EventID` | operation plan or history |
| `app.DatabaseCopyPlanOperation` | 179 | Excluded | - | `PlanID, DestinationInstanceCode, DatabaseCode` | operation plan or history |
| `app.DatabaseCopyPolicy` | 1 | Global | `app_DatabaseCopyPolicy` | `PolicyCode` | action runtime limits |
| `app.DatabaseCopyRecoveryPlan` | 0 | Excluded | - | `RecoveryID` | operation plan or history |
| `app.DatabaseCopySourceVersionInventory` | 43 | Excluded | - | `MachineName, SourceInstanceCode, SourceDatabaseName` | discovered or measured state (inventory, snapshots) |
| `app.EnvironmentCloneComponent` | 1108 | Excluded | - | `ComponentID` | operation plan or history |
| `app.EnvironmentCloneEvent` | 101 | Excluded | - | `EventID` | operation plan or history |
| `app.EnvironmentClonePlan` | 51 | Excluded | - | `PlanID` | operation plan or history |
| `app.EnvironmentCloneProfile` | 5 | Global | `app_EnvironmentCloneProfile` | `ProfileCode` | action runtime limits |
| `app.EnvironmentOperationalState` | 62 | Excluded | - | `InstanceCode` | discovered or measured state (inventory, snapshots) |
| `app.EnvironmentPowerPlan` | 4 | Excluded | - | `PlanID` | operation plan or history |
| `app.EnvironmentVersionInventory` | 278 | Excluded | - | `InventoryID` | discovered or measured state (inventory, snapshots) |
| `app.HousekeepingArtifact` | 0 | Excluded | - | `ArtifactID` | owner: HousekeepingArtifact not carried |
| `app.HousekeepingPlan` | 29 | Excluded | - | `PlanID` | operation plan or history |
| `app.HousekeepingPlanPolicy` | 174 | Excluded | - | `PlanID, PolicyCode` | operation plan or history |
| `app.HousekeepingPolicy` | 8 | Global | `app_HousekeepingPolicy` | `PolicyCode` | policy; RootPath may be machine specific [PENDING] |
| `app.HousekeepingStorageSnapshot` | 1364 | Excluded | - | `SnapshotID` | discovered or measured state (inventory, snapshots) |
| `app.Job` | 766 | Excluded | - | `JobID` | owner: job history and job log not carried |
| `app.JobLog` | 0 | Excluded | - | `LogID` | owner: job history and job log not carried |
| `app.JobStep` | 7793 | Excluded | - | `JobStepID` | owner: job history and job log not carried |
| `app.JobTarget` | 7631 | Excluded | - | `JobID, InstanceCode` | owner: job history and job log not carried |
| `app.LegacyObjectAssessment` | 9 | Excluded | - | `ObjectName` | worker or schema bookkeeping of the old system |
| `app.MigrationHistory` | 38 | Excluded | - | `MigrationCode` | worker or schema bookkeeping of the old system |
| `app.Product` | 1 | Global | `app_Product` | `ProductCode` | product metadata; ProductVersion stale, see note |
| `app.VersionBaseline` | 0 | Global | `app_VersionBaseline` | `BaselineCode, ItemType, ItemCode` | action runtime limits |
| `app.VersionInventoryRun` | 38 | Excluded | - | `RunID` | discovered or measured state (inventory, snapshots) |
| `app.WebsiteFolderCopyArtifact` | 3 | Excluded | - | `ArtifactID` | operation plan or history |
| `app.WebsiteFolderCopyBatch` | 50 | Excluded | - | `BatchID` | operation plan or history |
| `app.WebsiteFolderCopyBatchPlan` | 50 | Excluded | - | `BatchID, PlanID` | operation plan or history |
| `app.WorkerState` | 3 | Excluded | - | `WorkerName` | worker or schema bookkeeping of the old system |
| `cfg.Application` | 36 | Global | `cfg_Application` | `ApplicationCode` | catalog definition |
| `cfg.ApplicationCopyPolicy` | 22 | Global | `cfg_ApplicationCopyPolicy` | `ApplicationCode` | catalog definition |
| `cfg.ConfigFile` | 41 | Global | `cfg_ConfigFile` | `FileID` | catalog definition |
| `cfg.ConfigFileRepairPolicy` | 8 | Global | `cfg_ConfigFileRepairPolicy` | `FileID` | catalog definition |
| `cfg.ConfigRule` | 417 | Global | `cfg_ConfigRule` | `RuleID` | definitions only; literal secrets in sensitive ExpectedTemplate values are replaced (section 3) |
| `cfg.ConfigurationAdapterDefinition` | 8 | Global | `cfg_ConfigurationAdapterDefinition` | `AdapterCode` | catalog definition |
| `cfg.DatabaseCopyPolicy` | 4 | Cut by ServerCode | `cfg_DatabaseCopyPolicy` | `ServerCode` | ServerCode = this machine |
| `cfg.DatabaseDefinition` | 7 | Global | `cfg_DatabaseDefinition` | `DatabaseCode` | catalog definition |
| `cfg.DatabaseObjectSettingRule` | 61 | Global | `cfg_DatabaseObjectSettingRule` | `ObjectSettingRuleID` | definitions only; literal secrets in sensitive ExpectedTemplate values are replaced (section 3) |
| `cfg.DatabaseSettingRule` | 14 | Global | `cfg_DatabaseSettingRule` | `SettingRuleID` | definitions only; literal secrets in sensitive ExpectedTemplate values are replaced (section 3) |
| `cfg.EnvironmentCloneDatabasePolicy` | 7 | Global | `cfg_EnvironmentCloneDatabasePolicy` | `PolicyCode` | catalog definition |
| `cfg.IisApplicationAutoStartDefinition` | 1 | Global | `cfg_IisApplicationAutoStartDefinition` | `IisApplicationCode` | catalog definition |
| `cfg.IisApplicationDefinition` | 30 | Global | `cfg_IisApplicationDefinition` | `IisApplicationCode` | catalog definition |
| `cfg.IisBindingDefinition` | 3 | Global | `cfg_IisBindingDefinition` | `BindingCode` | catalog definition |
| `cfg.IisDirectoryDefinition` | 21 | Global | `cfg_IisDirectoryDefinition` | `DirectoryCode` | catalog definition |
| `cfg.IisPrerequisiteDefinition` | 8 | Global | `cfg_IisPrerequisiteDefinition` | `PrerequisiteCode` | catalog definition |
| `cfg.IisServerPolicy` | 4 | Cut by ServerCode | `cfg_IisServerPolicy` | `ServerCode` | ServerCode = this machine |
| `cfg.IisServiceAutoStartProviderDefinition` | 1 | Global | `cfg_IisServiceAutoStartProviderDefinition` | `ProviderName` | catalog definition |
| `cfg.KeycloakClientSecretRule` | 8 | Global | `cfg_KeycloakClientSecretRule` | `KeycloakClientId` | maps client ids to secret rule codes; contains no secret value |
| `cfg.LinksPageAsset` | 45 | Global | `cfg_LinksPageAsset` | `AssetCode` | binary assets (largest table, about 11.5 MB of INSERT text); BLOB handling [PENDING] |
| `cfg.LinksPageInstanceApplication` | 12 | Cut by InstanceCode | `cfg_LinksPageInstanceApplication` | `InstanceCode, ApplicationCode` | InstanceCode in this machine |
| `cfg.LinksPagePolicy` | 4 | Cut by ServerCode | `cfg_LinksPagePolicy` | `ServerCode` | ServerCode = this machine |
| `cfg.LinksPagePresentationResource` | 21 | Global | `cfg_LinksPagePresentationResource` | `ResourceCode` | catalog definition |
| `cfg.LinksPageTemplate` | 2 | Global | `cfg_LinksPageTemplate` | `TemplateCode` | catalog definition |
| `cfg.LinksProfile` | 17 | Global | `cfg_LinksProfile` | `ProfileCode` | catalog definition |
| `cfg.LinksProfileApplication` | 183 | Global | `cfg_LinksProfileApplication` | `ProfileCode, ApplicationCode` | catalog definition |
| `cfg.LinksProfileInstance` | 61 | Cut by InstanceCode | `cfg_LinksProfileInstance` | `ProfileCode, InstanceCode` | InstanceCode in this machine |
| `cfg.ManagedAssetDestination` | 3 | Global | `cfg_ManagedAssetDestination` | `AssetType, DestinationCode` | catalog definition |
| `cfg.PulseHttpPolicy` | 12 | Global | `cfg_PulseHttpPolicy` | `ApplicationCode` | catalog definition |
| `cfg.PulseProfile` | 4 | Cut by ServerCode | `cfg_PulseProfile` | `HubInstanceCode` | HubInstanceCode belongs to this machine (hub server) |
| `cfg.PulseResource` | 3 | Global | `cfg_PulseResource` | `ResourceCode` | binary content; BLOB handling [PENDING] |
| `cfg.SettingDefinition` | 3 | Global | `cfg_SettingDefinition` | `SettingCode` | catalog definition |
| `cfg.SettingSection` | 1 | Global | `cfg_SettingSection` | `SectionCode` | catalog definition |
| `cfg.SettingValue` | 0 | Global | `cfg_SettingValue` | `SettingCode, ScopeType, ScopeCode` | 0 rows today; rows scoped by ScopeType/ScopeCode; encrypted or secret rows excluded |
| `cfg.WebAccessPolicy` | 4 | Cut by ServerCode | `cfg_WebAccessPolicy` | `ServerCode` | ServerCode = this machine |
| `cfg.WebAccessTemplate` | 1 | Global | `cfg_WebAccessTemplate` | `TemplateCode` | catalog definition |
| `cfg.WebsiteBrandingAsset` | 3 | Global | `cfg_WebsiteBrandingAsset` | `AssetCode` | binary content; BLOB handling [PENDING] |
| `cfg.WebsiteBrandingProfile` | 1 | Global | `cfg_WebsiteBrandingProfile` | `ProfileCode` | catalog definition |
| `cfg.WebsiteFolderCopyPolicy` | 1 | Global | `cfg_WebsiteFolderCopyPolicy` | `PolicyCode` | catalog definition |
| `cfg.WindowsServiceDefinition` | 1 | Global | `cfg_WindowsServiceDefinition` | `ServiceCode` | catalog definition |
| `dbo.DemoProfileImage` | 0 | Excluded | - | `ImageID` | owner: not carried |
| `dbo.ManagedInstance` | 76 | Cut by InstanceCode | `dbo_ManagedInstance` | `InstanceCode` | InstanceCode with ServerCode = this machine; password and token columns excluded; CustomerLogo BLOB [PENDING] |
| `dbo.ManagedServer` | 6 | Cut by ServerCode | `dbo_ManagedServer` | `ServerCode` | one row: this machine |
| `ops.Action` | 24 | Global | `ops_Action` | `ActionCode` | action catalog (contains executable SqlCommand text, see risks) |
| `ops.ActionRequirement` | 63 | Global | `ops_ActionRequirement` | `ActionCode, RequirementCode` | catalog definition |
| `ops.ActionStep` | 13 | Global | `ops_ActionStep` | `ParentActionCode, StepOrder` | catalog definition |
| `ops.ActionUiMetadata` | 0 | Global | `ops_ActionUiMetadata` | `ActionCode` | catalog definition |
| `ops.Action_BackupPhase1` | 18 | Excluded | - | NONE | backup copy of a table (phase or fix) |
| `ops.ConsoleProfile` | 1 | Global | `ops_ConsoleProfile` | `ProfileCode` | catalog definition |
| `ops.ConsoleSession` | 774 | Excluded | - | `SessionID` | history, audit, sessions, locks, schedules, approvals, state |
| `ops.Engine` | 19 | Global | `ops_Engine` | `EngineCode` | metadata only; ScriptText and ScriptSha256 removed, engines become files (renamed ops_EngineCatalog) [PROPOSED] |
| `ops.Engine_BackupIisFix` | 1 | Excluded | - | NONE | backup copy of a table (phase or fix) |
| `ops.EnvironmentOperationLock` | 45 | Excluded | - | `LockID` | history, audit, sessions, locks, schedules, approvals, state |
| `ops.ExecutionLog` | 8068 | Excluded | - | `ExecutionID` | history, audit, sessions, locks, schedules, approvals, state |
| `ops.GovernanceAudit` | 5 | Excluded | - | `AuditID` | history, audit, sessions, locks, schedules, approvals, state |
| `ops.MenuGroup` | 7 | Global | `ops_MenuGroup` | `GroupCode` | catalog definition |
| `ops.MenuGroup_BackupPhase1` | 7 | Excluded | - | NONE | backup copy of a table (phase or fix) |
| `ops.OperationApproval` | 0 | Excluded | - | `ApprovalID` | history, audit, sessions, locks, schedules, approvals, state |
| `ops.OperationSchedule` | 4 | Excluded | - | `ScheduleID` | history, audit, sessions, locks, schedules, approvals, state |
| `ops.PulseCheckState` | 132 | Excluded | - | `HubInstanceCode, InstanceCode, CheckCode` | history, audit, sessions, locks, schedules, approvals, state |
| `ops.PulseRun` | 10 | Excluded | - | `PulseRunID` | history, audit, sessions, locks, schedules, approvals, state |
| `ops.ReviewDefinition` | 12 | Global | `ops_ReviewDefinition` | `ReviewCode` | review catalog (contains executable CommandText, see risks) |
| `ops.SharedResourceOperationLock` | 31 | Excluded | - | `LockID` | history, audit, sessions, locks, schedules, approvals, state |
| `sec.ManagedCredential` | 191 | Excluded | - | `InstanceCode, CredentialType` | owner: secrets (SecretCipher); goes to the vault, never to a catalog |
| `sec.ManagedCredentialAudit` | 384 | Excluded | - | `AuditID` | credential audit history |
| `sec.Policy` | 3 | Global | `sec_Policy` | `PolicyCode` | policy codes |
| `sec.WindowsGroupPolicy` | 0 | Cut by ServerCode | `sec_WindowsGroupPolicy` | `MachineName, WindowsGroupName, PolicyCode` | MachineName of this machine (0 rows today) |
| `ui.NavigationItem` | 16 | Global | `ui_NavigationItem` | `NavigationCode` | UI definitions |
| `ui.PublishedEnvironmentLink` | 55 | Cut by InstanceCode | `ui_PublishedEnvironmentLink` | `InstanceCode` | InstanceCode in this machine |
| `ui.PublishedEnvironmentLinkAudit` | 12 | Excluded | - | `AuditID` | audit history |
| `ui.Resource` | 214 | Global | `ui_Resource` | `ResourceCode, CultureCode` | UI definitions |


### 1.4 Views, procedures, functions and triggers

None of these is converted: a catalog contains tables only. What each group means for the port [PROPOSED]:

| Group | Count | Decision |
|---|---:|---|
| Views | 6 | `cfg.ManagedInstanceRuntime` decrypts passwords and tokens (see section 3), not converted; `app.HousekeepingStorageLatest` depends on an excluded table; the other four (`cfg.ApplicationCatalog`, `cfg.ExpectedValue`, `cfg.IisServiceAutoStartProviderCatalog`, `cfg.LinksPageInstanceApplicationCatalog`) are pure reads, to be recreated as SQLite views or as queries in the engines [PENDING] |
| Procedures `cfg.*` | 42 | 17 `Get*Plan` procedures (for example `cfg.GetIisDeploymentPlan`, `cfg.GetIisServiceAutoStartProviderPlan`, `cfg.GetIisApplicationAutoStartPlan`, `cfg.GetWebAccessDeploymentPlan`, `cfg.GetRepairPlan`) and 13 `Review*` procedures are the read model of the engines and must be reimplemented as modules over the catalog tables during the engine ports; `cfg.GetLocalManagementContext` is replaced by `catalog_meta` |
| Procedures `app.*` | 124 | queue, job, plan and worker logic of the old system; not needed (history and workflow are excluded) |
| Procedures `ops.*`, `ui.*`, `dbo.*` | 28, 5, 1 | locks, schedules, approvals, audit: not needed in V1; `ui.GetNavigation` and `ui.GetResourceSet` are simple reads over carried tables |
| Credential procedures | 6 | `app.SetManagedCredential`, `app.GetManagedCredentialRuntime`, `app.GetManagedCredentialCatalogue`, `app.GetManagedCredentialAudit`, `app.QueueManagedCredentialTest`, `cfg.SetManagedInstanceCredentials`: replaced by the credential tool and package |
| Engine distribution | 2 | `ops.GetEngineScript` and `ops.UpsertEngine` are replaced by files (R-027) |
| Functions | 5 | `cfg.ExpandTemplate` expands the `...Template` columns (paths, URLs, names) and must be ported into a PowerShell module with tests, because the catalog stores templates, not values; `cfg.NormalizeConnectionString`, `cfg.NormalizeValue`, `ui.ResolveResource` likewise; `ops.CalculateNextScheduleRun` belongs to schedules (excluded) |
| Triggers | 5 | all on excluded tables; dropped |

## 2. Cut rules per machine

### 2.1 Keys

[CONFIRMED] `dbo.ManagedServer.ServerCode` is the machine key (6 rows). Each instance belongs to exactly one server through `dbo.ManagedInstance.ServerCode` (primary key `InstanceCode`, one `ServerCode` per row), so every instance appears in exactly one catalog by construction. Instances per server: BR_DEMO 21, ES_DEMO 19, PT_DEMO 16, PRESALES 8, SANDBOX_HUB 6, TENDERS 6 (76 in total).

### 2.2 Rules by class

| Class | Tables | Rule |
|---|---|---|
| Global (51) | `cfg.*` definitions, rules and policies without a server key; `ops.Action`, `ActionRequirement`, `ActionStep`, `ActionUiMetadata`, `ConsoleProfile`, `MenuGroup`, `ReviewDefinition`, `ops.Engine` (metadata only); `sec.Policy`; `ui.NavigationItem`, `ui.Resource`; `app.*Policy`, `app.*Profile`, `app.Product`, `app.VersionBaseline` | copied in full; every catalog must hold the same logical content (tested, see 6) |
| Cut by ServerCode (7) | `dbo.ManagedServer`, `cfg.IisServerPolicy`, `cfg.WebAccessPolicy`, `cfg.LinksPagePolicy`, `cfg.DatabaseCopyPolicy`, `cfg.PulseProfile`, `sec.WindowsGroupPolicy` | `ServerCode = :ServerCode`; `cfg.PulseProfile` by the `ServerCode` of its `HubInstanceCode`; `sec.WindowsGroupPolicy` by the `MachineName` of the server (0 rows today) |
| Cut by InstanceCode (4) | `dbo.ManagedInstance`, `cfg.LinksPageInstanceApplication`, `cfg.LinksProfileInstance`, `ui.PublishedEnvironmentLink` | `InstanceCode IN (instances whose ServerCode = :ServerCode)` |
| Scoped values | `cfg.SettingValue` (0 rows today) | would be cut by `ScopeType` and `ScopeCode`; rows with `IsEncrypted = 1` are never carried |

### 2.3 Rows per machine (from the source file)

[CONFIRMED] counts of cut rows:

| Table | BR_DEMO | ES_DEMO | PT_DEMO | SANDBOX_HUB | PRESALES | TENDERS |
|---|---:|---:|---:|---:|---:|---:|
| `dbo.ManagedInstance` | 21 | 19 | 16 | 6 | 8 | 6 |
| `ui.PublishedEnvironmentLink` | 21 | 18 | 16 | 0 | 0 | 0 |
| `cfg.LinksProfileInstance` | 21 | 18 | 16 | 1 | 0 | 0 |
| `cfg.LinksPageInstanceApplication` | 0 | 12 | 0 | 0 | 0 | 0 |
| `cfg.IisServerPolicy`, `cfg.WebAccessPolicy`, `cfg.LinksPagePolicy`, `cfg.DatabaseCopyPolicy` (each) | 1 | 1 | 1 | 1 | 0 | 0 |
| `cfg.PulseProfile` | 1 | 1 | 1 | 1 | 0 | 0 |

`cfg.LinksProfileInstance` has 61 source rows: 56 match an existing instance (21 + 18 + 16 + 1) and 5 are orphans (see 2.4).

### 2.4 Cross-machine references and data problems

- [CONFIRMED] 5 rows of `cfg.LinksProfileInstance` reference instance codes that do not exist in `dbo.ManagedInstance`. [PROPOSED] they are dropped and written to the conversion report as findings, never silently.
- [CONFIRMED] `cfg.Application.LinksHubInstanceCode` is NULL in 35 of 36 rows; the one value points to an instance of PT_DEMO. As a global table this value appears in every catalog. [PROPOSED] it is stored as a plain code without a foreign key; whether other machines need more data of that instance is [PENDING].
- [CONFIRMED] Hub profiles: the 4 `cfg.PulseProfile` rows have their hub on BR_DEMO, ES_DEMO, PT_DEMO and SANDBOX_HUB. [PENDING] whether a machine's Pulse needs to know the hub of another machine.
- [PENDING] The old database lets one machine's console plan operations between instances of different machines (database copy, environment clone, folder copy). The plans are excluded and V1 executes locally, but the owner must say whether a catalog needs a small directory of instances of OTHER machines for such operations.

### 2.5 Binary content

[CONFIRMED] `cfg.LinksPageAsset` holds 45 image rows (about 11.5 MB of INSERT text, 41 percent of the whole file); `cfg.PulseResource.BinaryContent` and `cfg.WebsiteBrandingAsset.BinaryContent` hold a few more; `dbo.ManagedInstance.CustomerLogo` is set on 62 of 76 instances (about 1 MB together).
[PROPOSED] global binary assets are not stored in the catalogs (they would be duplicated in six files): the converter writes them as files under `assets/` in the package, the catalog keeps file name, mime type and SHA-256, and the package manifest lists each file. Per-instance logos stay as BLOB in the catalog of their machine. [PENDING] owner decision.

### 2.6 Machines without policy rows, and new machines

- [CONFIRMED] PRESALES and TENDERS exist in `dbo.ManagedServer` and have instances (8 and 6), but have NO rows in the four server policy tables, which exist only for BR_DEMO, ES_DEMO, PT_DEMO and SANDBOX_HUB. A plain cut would give these two machines empty policy tables, and engines that read `cfg.IisServerPolicy` (such as `IIS_RECONCILE`) would have nothing to apply. [PENDING] whether they get copies of a template server's policy rows.
- [PROPOSED] The pilot server has no row in `dbo.ManagedServer`, so it cannot be cut. The conversion tool gets a new-machine mode: all global tables, one `dbo_ManagedServer` row built from parameters (`ServerCode`, `MachineName`, roots), policy rows copied from a named template server [PENDING which one], and no instances. Because the pilot comes first, this mode is built before the cut mode (step B order).
- [PENDING] Machines without a local database: not decided; nothing is assumed.

## 3. What does NOT enter a catalog

### 3.1 Tables

- Secrets (owner): `sec.ManagedCredential` (191 rows: 76 `IIS_IDENTITY`, 76 `WEB_ACCESS`, 39 `MOBILE_APP_TOKEN`). Goes to the vault (section 4), never to a catalog or to Git.
- Credential history: `sec.ManagedCredentialAudit` (384 rows).
- Job history (owner): `app.Job` (766), `app.JobStep` (7,793), `app.JobTarget` (7,631), `app.JobLog` (0 rows), `ops.ExecutionLog` (8,068), `ops.ConsoleSession` (774), `ops.GovernanceAudit`, `ui.PublishedEnvironmentLinkAudit`.
- `app.HousekeepingArtifact` (owner, 0 rows) and `dbo.DemoProfileImage` (owner, 0 rows).
- Engine scripts (owner): the `ScriptText` of `ops.Engine` (19 rows) and of `ops.Engine_BackupIisFix`. The engines are exported as files, see 5.4. In the catalog, `ops_EngineCatalog` keeps only `EngineCode`, `DisplayName`, `SourceFileName`, `EngineVersion`, `MinimumPowerShell`, `RequiresAdministrator`, `IsEnabled`, `ModifiedAt`.
- Everything else classed Excluded in 1.3 (plans, inventories, locks, schedules, approvals, workers, backups of tables).

### 3.2 Columns and views

- `dbo.ManagedInstance.IisIdentityPassword`, `WebAccessPassword` and `MobileAppToken` are not carried. [CONFIRMED] they are NULL in all 76 rows of the sync file (the sync already empties them), but the live table may differ, so the tool excludes them by name and not by value.
- `rowversion` columns (7 in carried tables) and `ops.Engine.ScriptText` / `ScriptSha256`.
- View `cfg.ManagedInstanceRuntime` (decrypts `MobileAppToken`, `IisIdentityPassword`, `WebAccessPassword` through the certificate; referenced 25 times in the file). [PROPOSED] replaced by a plain view `cfg_ManagedInstanceCatalog` over `dbo_ManagedInstance` without the three secret columns. Every code path that read secrets through the old view or through `app.GetManagedCredentialRuntime` must ask the credential package instead (engine ports).

### 3.3 Secrets found INSIDE carried tables [CONFIRMED]

A scan of the carried tables found literal secret values in a global rule table, not only in the credential tables:

- `cfg.ConfigRule` has 55 rows with `IsSensitive = 1`. 39 of them are connection-string templates with placeholders and Windows integrated security (no secret). **16 rows hold a literal value in `ExpectedTemplate`**: 12 client secrets (rule codes ending `CLIENT_SECRET` or `CLIENTSECRET`), 1 API key (`API_V8_API_KEY`), 1 access token (`API_V8_KEYCLOAK_ACCESS_TOKEN`) and 2 Keycloak passwords (`KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD`, `KEYCLOAK_KEYSTORE_PASSWORD`). Eight of them are mapped to Keycloak client ids by `cfg.KeycloakClientSecretRule` (8 rows, no secret value in that table).
- `cfg.DatabaseObjectSettingRule` (3 sensitive rows) and `cfg.DatabaseSettingRule` (1 sensitive row) were checked by shape only and look like placeholder templates; [V] confirm on the live data.
- `cfg.SettingDefinition` has no row with `IsSecret = 1`; `cfg.SettingValue` has no rows.
- [PROPOSED] Rule for the conversion tool: in any row with `IsSensitive = 1` whose template has no placeholder, the literal part is replaced by a reference token (syntax [PENDING], for example `{{secret:RULE:<RuleCode>}}`), and the literal goes to the vault as a credential of kind `RULE_SECRET`, so the engines get it from the credential package like any other credential. The kind must be added to `contracts/credential-package.md` (open question Q6).
- [PROPOSED] Safety net: before writing a catalog the tool scans every text column of every carried table for secret patterns (`password=`, `pwd=`, `secret=`, `token=`, long random strings in sensitive rows) against an explicit allowlist, and refuses to write the file on any other hit. The same scan is part of `Test-CatalogConversion.ps1` (section 5).
- [CONFIRMED] These literals are also present in plain text in `ManagementSync.sql` in the reference repository. They have therefore been exposed to everyone with access to that repository and its history. [PROPOSED] rotate the 16 values after the cutover; the plan and the test reports never print them.

### 3.4 Executable text inside carried tables

`ops.Action.SqlCommand` and `ops.ReviewDefinition.CommandText` hold SQL text that the old system executed. [PROPOSED] they are carried as data but never executed by the new application (the application runs only local versioned modules, R-019, R-027); during the engine ports each is replaced by a module or dropped. The `...Template` columns are templates, expanded by the ported `ExpandTemplate`.
