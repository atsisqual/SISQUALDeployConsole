# Catalog conversion plan (task 4, step A)

**Status:** [CONFIRMED] approved by the owner on 2026-10-05 ("Sim"), including the answers below. Plan only in this PR: no code. Step B (one small PR per tool) starts after this approval.
**Owner answers of 2026-10-05, second round ([CONFIRMED]): the SQL client is pinned with a Windows-runner workflow (spike PR, see section 5); `dbo.ManagedServer.ManagementDatabaseName` is dropped; collation is `Latin1_General_CI_AS` in every database.**
**Step B progress: B1 `Export-ManagementEngines` is PR #16, B2 `Convert-ManagementDb` (new-machine mode) is PR #17 (stacked on #16), the SQL client pin is PR #18; B3 to B6 not started.**
**Approval and answers of 2026-10-05 (owner, [CONFIRMED]): the plan is approved; engines without a policy row STOP (no built-in defaults); the SQL client is `Microsoft.Data.SqlClient` (version and hash still to be pinned); all tools and their CI parsing use the latest PowerShell (7).** Earlier answers: (1) no template server for policy rows; (2) global images stay as BLOB in every catalog; (3) the tools run on PowerShell 7 with a SQL client shipped with them. Sections 2.5, 2.6, 5, 7 and 8 were changed accordingly.
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

Case and collation [CONFIRMED, owner 2026-10-05]: the owner prefers that NOTHING about upper and lower case of what is stored changes (some identity-provider links are case-sensitive); the application databases use `Latin1_General_CI_AS`. Consequences: (1) every text value is stored exactly as in the source, including case and line endings (see 1.1b); (2) code columns compare exactly, which is the SQLite default (`-CodeCollation Binary`, the default of the converter); `-CodeCollation NoCase` is available but not used, because it would equate codes that differ only by case. Evidence on the 2026-10-05 snapshot [CONFIRMED]: no code column holds two values that differ only by case, no cross-table code reference matches only when case is ignored (1,677 exact matches, 0 case-insensitive-only matches in the candidate relations checked), and the six `MachineName` values are upper case. Exact comparison therefore gives the same results as the old case-insensitive comparison on today's data, and a code typed with the wrong case fails visibly instead of matching silently. The engines run their queries against the application databases with those databases' own collation; nothing in the catalog changes that. Windows names (machine, account) are case-insensitive in Windows: the engine ports must compare them case-insensitively in code, not through the catalog. [CONFIRMED] in the 2026-10-05 snapshot all 10,165 code values checked (62 carried tables and the history tables) are ASCII. The converter reports, as a finding with counts only, any non-ASCII value in a `NOCASE` column. Other text columns (names, descriptions, paths) are compared exactly in SQLite, as are the code columns by default: the engine ports must not rely on SQL Server's case-insensitive comparison for any of them. [V] the live collation of `_sisqualMANAGEMENT` is still read by the tool from the live database and compared with the value stated by the owner.

### 1.1b Text is stored byte-exact

[CONFIRMED] Rule: a text or binary value in the catalog is byte-for-byte the value in the source, with two documented exceptions (`datetime2` gets a `T` instead of the space, `char(n)` is right-trimmed) and the 16 redacted rule templates (3.3).
[CONFIRMED] Defect found and fixed in step B2 (PR #17): the `sqlite3` shell removes the carriage return of every CRLF it reads, even inside a quoted string, so multi-line texts lost their `\r` (9 rows: file-content templates, page and presentation resources, Pulse resources). The unit tests did not catch it because no test value had several lines, and a comparison of the real data with the source did. Fix: any text that contains a control character is written as `CAST(X'<UTF-8 hex>' AS TEXT)`. A mutation test (fix disabled) now fails as it should.
[CONFIRMED] Evidence after the fix, on the real snapshot: 18,125 cells of all global tables compared with the source, 9 of them with a CR in the text, 0 differences; the stored `ContentSha256` of every template and resource (SHA-256 of the UTF-16LE text) equals the hash of the catalog value, and every image BLOB equals its stored hash.
[PROPOSED] `Test-CatalogConversion.ps1` (B4) must repeat this value-level comparison for every table, not only counts and keys, using the stored SHA-256 columns where they exist.

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

[CONFIRMED] `cfg.LinksPageAsset` holds 45 image rows (about 11.5 MB of INSERT text, 41 percent of all INSERT text); `cfg.PulseResource.BinaryContent` and `cfg.WebsiteBrandingAsset.BinaryContent` hold a few more; `dbo.ManagedInstance.CustomerLogo` is set on 62 of 76 instances (about 1 MB together).
[CONFIRMED] Owner answer of 2026-10-05: binary content stays as BLOB in EVERY catalog. Global assets are therefore duplicated in each catalog file; per-instance logos stay in the catalog of their machine. Consequences: measured in step B2 on the real data, a new-machine catalog is 6.85 MB (the hex text of the INSERT statements is twice the size of the bytes), so six catalogs are about 40 MB [CONFIRMED, replaces the earlier estimate of 80 MB]; each is hashed in its package manifest; the catalog must still open read-only quickly, so BLOBs are read on demand and never selected with `SELECT *`. The `Content` columns keep their SHA-256 (`ContentSha256`) so a test can verify every BLOB against it.

### 2.6 Machines without policy rows, and new machines

- [CONFIRMED] PRESALES and TENDERS exist in `dbo.ManagedServer` and have instances (8 and 6), but have NO rows in the four server policy tables (`cfg.IisServerPolicy`, `cfg.WebAccessPolicy`, `cfg.LinksPagePolicy`, `cfg.DatabaseCopyPolicy`), which exist only for BR_DEMO, ES_DEMO, PT_DEMO and SANDBOX_HUB.
- [CONFIRMED] Owner answer of 2026-10-05: there is no template server. Machines without policy rows, and the pilot, are cut exactly as they are in the source: empty policy tables, nothing copied from another server. The owner's reason is that the engines already create these settings.
- [CONFIRMED, from the source] This is NOT what the reference system does today: `cfg.GetIisDeploymentPlan` stops with error 50010 when the machine is not an enabled `ManagedServer` and with error 50011 ("No enabled IIS server policy exists for the resolved ManagedServer") when the server has no row in `cfg.IisServerPolicy`. No stored procedure and none of the 19 engine scripts inserts rows into the four policy tables; the only rows are the data rows of the sync file. So the defaults would have to come from the new engines. [CONFIRMED] Owner answer of 2026-10-05: the ported engines have NO built-in defaults; on a machine without a policy row they stop and report "policy missing" (like the reference procedures do with errors 50010 and 50011). The converter and tests make no assumption: an empty policy table is valid and is reported as a finding, never filled.
- [PROPOSED] The pilot server has no row in `dbo.ManagedServer`, so it cannot be cut. The converter gets a new-machine mode: all global tables, one `dbo_ManagedServer` row built from parameters (`ServerCode`, `MachineName`, roots), no instances and no policy rows. Because the pilot comes first, this mode is built before the cut mode (step B order).
- [PENDING] Machines without a local database: not decided; nothing is assumed.

## 3. What does NOT enter a catalog

### 3.1 Tables

- Secrets (owner): `sec.ManagedCredential` (191 rows: 76 `IIS_IDENTITY`, 76 `WEB_ACCESS`, 39 `MOBILE_APP_TOKEN`). Goes to the vault (section 4), never to a catalog or to Git.
- Credential history: `sec.ManagedCredentialAudit` (384 rows).
- Job history (owner): `app.Job` (766), `app.JobStep` (7,793), `app.JobTarget` (7,631), `app.JobLog` (0 rows), `ops.ExecutionLog` (8,068), `ops.ConsoleSession` (774), `ops.GovernanceAudit`, `ui.PublishedEnvironmentLinkAudit`.
- `app.HousekeepingArtifact` (owner, 0 rows) and `dbo.DemoProfileImage` (owner, 0 rows).
- Engine scripts (owner): the `ScriptText` of `ops.Engine` (19 rows) and of `ops.Engine_BackupIisFix`. The engines are exported as files, see 5.4. In the catalog, `ops_Engine` (same naming rule as every table, `<schema>_<Table>`) keeps only `EngineCode`, `DisplayName`, `SourceFileName`, `EngineVersion`, `MinimumPowerShell`, `RequiresAdministrator`, `IsEnabled`, `ModifiedAt`.
- Everything else classed Excluded in 1.3 (plans, inventories, locks, schedules, approvals, workers, backups of tables).

### 3.2 Columns and views

- `dbo.ManagedInstance.IisIdentityPassword`, `WebAccessPassword` and `MobileAppToken` are not carried. [CONFIRMED] they are NULL in all 76 rows of the sync file (the sync already empties them), but the live table may differ, so the tool excludes them by name and not by value.
- `rowversion` columns (7 in carried tables), `ops.Engine.ScriptText` / `ScriptSha256`, and `dbo.ManagedServer.ManagementDatabaseName` ([DECIDED 2026-10-05]: it names the old central database, which ceases to exist).
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

## 4. Credentials in two phases

### 4.1 Phase (i): now, catalogs without secrets

[PROPOSED] The catalogs are built and shipped with no secret at all. Until phase (ii) an engine that needs a credential stops with a clear "credential package missing" result. The pilot server needs no import from the old system: its credentials are entered directly in the vault by the credential tool when the machine is ready.

### 4.2 One-time import into the vault (before the old database disappears)

- [CONFIRMED] The 191 values in `sec.ManagedCredential` are ciphertext made with the SQL Server symmetric key `SISQUAL_ManagedCredential_Key`, protected by the certificate `SISQUAL_ManagedCredential_Certificate`, with the authenticator `InstanceCode|CredentialType`. They are readable only through the LIVE database. The sync file cannot be used for this step.
- [PROPOSED] The import runs once, by a person, with a login that can execute the existing read path (`cfg.ManagedInstanceRuntime` or `app.GetManagedCredentialRuntime`, which runs `WITH EXECUTE AS OWNER` and decrypts through the certificate), over a direct read-only connection (no linked server, R-020). It only reads.
- [PROPOSED] What is imported: the 191 instance credentials (76 `IIS_IDENTITY`, 76 `WEB_ACCESS`, 39 `MOBILE_APP_TOKEN`) keyed by `InstanceCode` and `CredentialType`, plus the 16 literal rule secrets of 3.3 (kind `RULE_SECRET`, keyed by `RuleCode`), read from the live database so that current values are taken. Expected total: 207; the tool compares counts per kind with the source and reports them, never values.
- [PROPOSED] Each plaintext value exists only in memory and is encrypted into the vault immediately; nothing is written in clear, nothing is logged. For later verification the vault stores, per entry, a salted SHA-256 fingerprint of the value (salt kept in the vault), so a re-read of the source can be compared without exposing it.
- [V] Check on the live server that the read path does not write audit rows or change state (`sec.ManagedCredentialAudit` exists and `app.GetManagedCredentialRuntime` is a procedure), and which login may use the certificate.
- [PROPOSED] Order of events: (1) import into the vault; (2) verify counts and fingerprints; (3) make two encrypted backups of the vault in two places; (4) only then may the owner decommission `_sisqualMANAGEMENT`. Losing the vault after step 4 means resetting every credential at the services.

### 4.3 Vault protection

[PROPOSED] (format and algorithms [PENDING], decided with the machine-key ADR of Phase 1B and `contracts/credential-package.md` Q2)

- One encrypted file, outside Git and outside the portable folder, on the credential tool operator's machine only; never on a shared folder or a synchronised cloud folder; restrictive file permissions; `*.vault` and similar patterns in `.gitignore` and in the CI secret scan.
- Protection by a key derived from a passphrase held by the owner, optionally combined with protection bound to the operator's Windows identity. The passphrase is not stored anywhere in the repository or in the tool.
- Entries: `credentialRef`, kind, instance code, ciphertext, creation and import time, source description, salted fingerprint. Metadata is not secret; values are.
- An access log with metadata only (who, when, which refs), never values.
- Two encrypted backups, tested by a restore into a temporary folder.

### 4.4 Phase (ii): per machine, after its public key exists

[PROPOSED] When a machine has run the portable once and its machine identity text (public key and fingerprint, `contracts/credential-package.md` 3a) has been carried to the credential tool, the tool selects from the vault the entries of the instances in that machine's catalog plus the `RULE_SECRET` entries its engines need, encrypts them for that machine key, signs the package with the tool key and issues it with `sequence` greater than the previous one. Whether the result is a text package imported by the operator or a `credentials.db` file is the open question Q3 of the credential contract and is not decided here. The same issuer key signs the package manifest (ADR-0007 item 3).

## 5. Tools

Where SQL Server appears in this plan [CONFIRMED, answer to an owner question of 2026-10-05]: ONLY as the source of the one-off conversion (reading `_sisqualMANAGEMENT`, read-only) and of the one-time credential import. The catalogs, the application and its tests use SQLite only; nothing in the portable application talks to SQL Server for configuration. The SQL Server code path of the tools is optional: the same conversion also works offline from `ManagementSync.sql`, which is what the tests and CI use. The credential import is the exception, because the ciphertext can only be read through the live database (4.2).

All tools live under `tools/`, are run on demand by a person, and are not part of the portable application. [CONFIRMED] Owner answer of 2026-10-05: they run on PowerShell 7 with a SQL client shipped with them. [PROPOSED] consequences:

- The SQL client is a new vendored dependency. [CONFIRMED] approved by the owner (`Microsoft.Data.SqlClient`) and pinned by the spike of PR #18 (docs/phase1/sqlclient-pin.md): version 7.1.1, package SHA-256 `1da22a633fb44406d9a9400b00471039e8895ac3e717afe2e3beedba2f049e37`, SHA-512 equal to the NuGet catalog `packageHash`, signature valid (Microsoft Corporation), MIT, a closure of 25 files pinned one by one, loads in the pinned PowerShell 7.6.6 on .NET 10.0.12. [PENDING] how the 25 files reach the operator machine, and the encryption and certificate-trust defaults for the real servers [V]. The tools use PowerShell 7 from the pinned `vendor/` ZIP (7.6.6), not a machine installation.
- [CONFIRMED] Owner answer of 2026-10-05: everything in the latest PowerShell. The CI parser step of PR #10 parses every `.ps1` with the Windows PowerShell 5.1 parser, which rejects PowerShell 7 syntax. [PROPOSED] CI parses `tools/` with the PowerShell 7 parser (`pwsh`) and keeps the 5.1 parser only for files that must run in 5.1 (the engines, because ADR-0006 keeps a 5.1 fallback). [PENDING] the owner confirms whether the engines also move fully to PowerShell 7.
- Integrated authentication to SQL Server works with the client from PowerShell 7; encryption and certificate trust settings of the connection are decided with the live server [V].

All output is ASCII with LF except where a tool copies bytes it must not change (5.4).

### 5.1 `tools/Convert-ManagementDb.ps1`

- Reads SQL Server over a direct connection with the vendored SQL client, read-only (`ApplicationIntent=ReadOnly`, integrated security, SELECT statements against an explicit whitelist of the 62 carried tables). It refuses any other table, never touches `sec.*`, and never logs the connection string.
- Parameters [PROPOSED]: `-SqlInstance`, `-Database` (default `_sisqualMANAGEMENT`), `-OutputFolder`, `-ServerCode` (one, several or `ALL`), `-NewMachine` with `-MachineName` (no template server, see 2.6), and `-WhatIf`. The pinned `sqlite3.exe` 3.53.4 is taken from `vendor/manifest.json` and its SHA-256 is verified before use.
- Output per machine: `catalog-<ServerCode>.db`, plus one `conversion-manifest.json` with the SHA-256 of each `.db`, row counts per table (source and destination), source identity (server, database, collation, read time), tool version, findings (for example the 5 orphan rows) and the list of excluded objects. No values.
- Method [PROPOSED]: the tool generates a UTF-8 SQL script without BOM and with LF (`CREATE TABLE ... STRICT`, one transaction of `INSERT` statements, text escaped by doubling quotes, BLOBs as `X'..'` literals) and runs `sqlite3.exe` on it, then `PRAGMA integrity_check`, `foreign_key_check` and `VACUUM`, and sets `PRAGMA user_version` to the schema version. It needs no managed SQLite provider.
- Applies, in this order: column exclusions by name, rowversion dropping, type conversion (1.1), the cut (2.2), the rule-secret redaction and the safety-net scan (3.3), the `catalog_meta` row (`contracts/catalog-schema.md`).
- Builds the new-machine mode first, because the pilot is a server that does not exist in the old database (2.6).
- Writes to a temporary folder and renames at the end, so a failed run leaves no half-written catalog.

### 5.2 `tools/Test-CatalogConversion.ps1`

Checks the result against the source without printing values. It exits non-zero on the first failed group and writes a report with counts and hashes only [PROPOSED]:

- counts source versus destination per table and per machine (carried rows equal source rows after the cut, minus the reported orphans);
- primary-key sets (hash of the sorted keys) per table, and null counts per column;
- completeness of the cut: the union of the instance-cut rows over all catalogs equals the source set, no instance appears in two catalogs, every instance of the source appears in one;
- global tables hold identical logical content in every catalog (hash per table);
- exclusions: no `sec_*` table, no excluded column, no `ScriptText`, no rowversion column;
- secret safety: the scan of 3.3 on every text column, and a marker test (known marker values planted in the fixture must not appear anywhere in the output);
- SQLite checks: `integrity_check`, `foreign_key_check`, `STRICT` tables, opens read-only (`mode=ro`) and a write attempt fails;
- the manifest hashes recomputed and compared.

### 5.3 Seal tool

Name [PENDING], for example `tools/Seal-Package.ps1`. Used when the owner edits the catalog by hand (ADR-0007 item 7). It [PROPOSED]:

- recomputes SHA-256 and size of every file of the package folder, updates the package manifest (`contracts/package-manifest.schema.json`) with `origin = manual-edit-sealed`, a new `packageId` and `builtAt`;
- validates the edited catalog before sealing: `catalog_meta` agrees with the manifest, `integrity_check`, `foreign_key_check`, the secret scan of 3.3, and that the schema version is supported;
- shows the owner a summary of what changed (files and tables) and asks for confirmation;
- signs the manifest with the issuer key of the credential tool; the private key is never in the repository and never in the portable folder;
- appends a line to a local seal log (time, package id, file count), without secrets.

Because it uses the issuer key it is built with, or next to, the credential tool; whether it is the same program is [PENDING].

### 5.4 Engine export

[PROPOSED] A mode or small script of the conversion tool (`tools/Export-ManagementEngines.ps1`) reads `ops.Engine` read-only and writes each `ScriptText` to a file `<SourceFileName>` plus `engines-export-manifest.json` (engine code, version, stored hash, computed hash, size, line endings, encoding). From PR #12 it is known that the stored `ScriptSha256` equals the SHA-256 of the UTF-16LE text and that the text uses CRLF; the tool must reproduce this exactly and report any mismatch. Two constraints [PENDING]: the exported files are not ASCII-only and use CRLF, which conflicts with the repository rule (ASCII and LF) and would be changed by line-ending normalisation. [PROPOSED] keep the export outside Git as a hash-verified artifact; each engine port PR then writes a clean ASCII/LF file of its own. The files are scanned for secrets before being handed over. They are only the base for the port; they are never copied into a catalog or executed (R-027).

### 5.5 Order of step B (after approval)

One small PR per tool [PROPOSED]: B1 engine export; B2 `Convert-ManagementDb.ps1` new-machine mode plus the SQLite script writer and tests; B3 the cut mode; B4 `Test-CatalogConversion.ps1`; B5 seal tool; B6 the vault import and issue steps of the credential tool (after the credential contract questions are answered). The pilot machine is served after B2.

## 6. Test strategy without real servers

Principle [PROPOSED]: the real `ManagementSync.sql` is not copied into CI. It contains real data and the 16 literal secrets of 3.3, and would duplicate that exposure. CI uses a fixture built from the SHAPE of the sync file and synthetic rows.

| Level | What | Where |
|---|---|---|
| L1 static | Windows PowerShell 5.1 parser, ASCII and LF, secret scan on every changed file (the existing CI of PR #10) | windows-2022 |
| L2 unit | pure functions: type conversion, literal escaping, `ExpandTemplate`-style placeholder detection, rule-secret redaction, cut-rule SQL generation, manifest hashing | windows-2022, Pester [PENDING vendoring] |
| L3 integration | a SQL Server restored from a generated fixture: the 117 `CREATE TABLE` blocks of the sync file plus synthetic rows (6 servers, instances spread over them, 5 orphan rows, sensitive rules with MARKER values, rows in `sec.ManagedCredential` with marker ciphertext, a server without policy rows, a rule with no placeholder); run the converter for every `ServerCode` and the new-machine mode, then `Test-CatalogConversion.ps1` | SQL Server in a container on a Linux runner, or a SQL Server on the Windows runner [CONFIRMED by the spike of PR #18: the `windows-2022` runner carries SQL Server LocalDB (15.0.4382.1) and the pinned client queried it; its default collation is `SQL_Latin1_General_CP1_CI_AS`, so the test database must be created with `Latin1_General_CI_AS`. The next step is an integration test that runs both tools with `-SqlInstance` against LocalDB] |
| L4 SQLite | the pinned `sqlite3.exe` 3.53.4 verified by hash; integrity and read-only opening of each produced catalog | windows-2022 |
| Negative tests | marker found in output (must fail), a table outside the whitelist (refused), an instance claimed by two servers (fail), a changed catalog byte (seal tool and manifest check fail), an unsupported schema version (refused) | L2 and L3 |

Only on the real servers [V]:

- the collation and the real constraints (`sys.foreign_keys`, checks, defaults, indexes) of the live database;
- the real row counts compared with the 2026-10-05 snapshot, and the real orphans and duplicates;
- the permission to read credentials, whether the read path writes audit, and the credential import with decryption through the certificate;
- the `datetime2` columns (time zone of the data in the live database);
- opening every catalog from the portable on the real machine and with its machine identity;
- the policy defaults chosen for PRESALES, TENDERS and the pilot machine;
- performance and size of the real catalogs.

## 7. Risks

| Id | Risk | Mitigation proposed |
|---|---|---|
| C-01 | 16 literal secrets in `cfg.ConfigRule`, plain in the reference repository | redaction to references, vault import, scan in tool and CI, rotate after cutover |
| C-02 | The credentials exist only as certificate-bound ciphertext in the live database; if it is retired before the import they are lost | import before decommission, counts and fingerprints, two tested backups (4.2) |
| C-03 | The vault is lost or stolen | passphrase, restrictive permissions, backups, never in Git or shared folders |
| C-04 | A stale catalog is used without anyone noticing (the old and new systems coexist until each server is switched) | catalog source and build time shown in the UI, re-run the conversion before each cutover and agree a change freeze [PENDING] |
| C-05 | Manual edits of the SQLite catalog have no review history and can break invariants | the seal tool validates; edits recorded in the seal log; authority later decided (deferred by the owner) |
| C-06 | Case and collation differences between SQL Server and SQLite break joins silently | read the collation, `COLLATE NOCASE` on code columns, tests with mixed-case codes |
| C-07 | Source times have no zone | keep as text, document, never assume UTC |
| C-08 | The sync file has no foreign keys; relations are implicit; hidden orphans (5 found) | derived relationship list, orphan report, live metadata when available |
| C-09 | PRESALES, TENDERS and the pilot have no policy rows, and the reference plan procedures fail (errors 50010, 50011) without them | no template and no built-in defaults (owner): empty policy tables are valid and reported; the ported engines stop with a clear "policy missing" result. Consequence: those machines cannot run policy-driven engines until their policy rows are added by hand to the catalog and the package is sealed |
| C-10 | Template expansion lives in a SQL function (`cfg.ExpandTemplate`) | port with tests before any engine that uses templates |
| C-11 | Executable SQL text in `ops.Action.SqlCommand` and `ops.ReviewDefinition.CommandText` | carried as data, never executed (R-019, R-027) |
| C-12 | A conversion bug lets a secret column or value through | explicit whitelist, exclusion by name, scan, marker tests, review of every PR of step B |
| C-13 | 11.5 MB of global images duplicated in six catalogs (owner chose BLOB in every catalog) | about 40 MB in total, measured in B2; read BLOBs on demand; verify each against `ContentSha256` |
| C-16 | The SQL client (`Microsoft.Data.SqlClient`, approved by the owner) is not yet pinned | pin version and SHA-256 in `vendor/manifest.json`, verify before use (step B2) |
| C-17 | PowerShell 7 syntax in `tools/` breaks the 5.1 parser step of CI | CI parses `tools/` with the PowerShell 7 parser; the 5.1 parser stays for the engines [PENDING owner on engines] |
| C-14 | The old database changes between the snapshot (2026-10-05 02:00) and the conversion | convert from the live database, record read time, compare counts with the snapshot |
| C-15 | Reading credentials through the old procedure may write audit rows or fail on permissions | verify on the live server before the import [V] |

## 8. Decisions needed from the owner

1. Approve the table classification (51 global, 7 cut by server, 4 cut by instance, 55 excluded) and the redaction of the 16 literal secrets with a new credential kind `RULE_SECRET`.
2. [DECIDED 2026-10-05] Binary content: BLOB in every catalog (global assets duplicated; per-instance logos in their machine catalog).
3. [DECIDED 2026-10-05] No template server for policy rows and no built-in defaults: engines stop when the policy row is missing (2.6). Open consequence for the owner: how policy rows for the pilot and for PRESALES and TENDERS are authored (manual edit and seal, ADR-0007 item 7).
4. Whether a catalog needs a directory of instances of other machines (cross-machine operations), and what a machine's Pulse needs of other hubs.
5. [DECIDED 2026-10-05] No case folding anywhere: stored text is unchanged and code columns compare exactly (binary). The databases use `Latin1_General_CI_AS`. Still to do [V]: read the live collation of `_sisqualMANAGEMENT` and compare.
6. Whether the four pure-read views are recreated.
7. Where the exported engines live (outside Git proposed) and the exception to ASCII and LF.
8. [DECIDED 2026-10-05] Tool runtime: PowerShell 7 with `Microsoft.Data.SqlClient` shipped with the tools; everything, including CI parsing of the tools, in the latest PowerShell (7). Still to do: pin the exact package version and SHA-256 and check the licence (step B2).
9. Vault format, protection (passphrase and Windows identity) and where the two backups are kept.
10. The credential contract questions Q1 to Q8, especially Q3 (text package or `credentials.db`) and Q6 (kinds, including `RULE_SECRET`).
11. Whether the seal tool and the credential tool are the same program.
12. [DECIDED by evidence, PR #18] CI gets a SQL Server from the runner image (LocalDB). Still to approve: the integration test that uses it.
13. Machines without a local database (not decided).
14. Whether the 16 exposed values are rotated after the cutover, and the change freeze and refresh cadence for catalogs while the old system is still in production.

Not decided and not assumed anywhere in this plan: the long-term authority of the catalog (deferred by the owner), the SQLite managed provider (Phase 1B), and the crypto algorithms (Phase 1B).
