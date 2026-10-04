# Phase 0 — Current System Map

**Status:** Phase 0 diagnostic — corrected after full sync-payload inspection  
**Reference repository:** `atsisqual/SISQUALManagementConsole` — read-only  
**Initial code baseline inspected:** `master` @ `1050fbbc97b6b077302154dd2e7307cce2ca3bbc`  
**Full sync snapshot additionally inspected:** `master` @ `1e38c8ed860615c4039ea2ec870f245102943ae4`  
**Production evidence source:** approved knowledge-transfer document based on direct execution on 4+ real production servers  
**Target repository:** `atsisqual/SISQUALDeployConsole`

## Evidence vocabulary

- **[CONFIRMED-CODE]** visible in versioned reference-repository code.
- **[CONFIRMED-SNAPSHOT]** visible in the generated `database/sync/ManagementSync.sql` snapshot.
- **[CONFIRMED-PRODUCTION]** confirmed by the production knowledge-transfer evidence.
- **[INFERRED]** derived from confirmed evidence but not directly demonstrated end-to-end.
- **[PENDING]** requires later evidence, an implementation decision, or a technical spike.
- **[V]** requires validation on a real Windows/SISQUAL environment before it can be considered proven for the new product.

This document describes the current system only. It does not define implementation code for SISQUALDeployConsole.

## 1. Current control-plane topology

**[CONFIRMED-PRODUCTION]** The current SISQUAL Management Console is a central management platform composed of:

```text
Browser
  |
  v
.NET Web application on IIS
  |
  +----> _sisqualMANAGEMENT (SQL Server)
  |
  v
.NET Worker
  |
  +----> ops.Action / ops.ActionStep
  +----> ops.Engine.ScriptText
  |
  v
PowerShell engine
  |
  +----> local IIS / Windows services / files
  +----> local or target application SQL databases
  +----> Keycloak / TSplus / Web Access as required
```

**[CONFIRMED-PRODUCTION]** `_sisqualMANAGEMENT` is shared between the physical servers in the current estate and is synchronized once per night from the golden server `PT_DEMO`.

**[CONFIRMED-PRODUCTION]** Synchronization is one-way: `PT_DEMO` exports; other servers apply. Changes made outside the golden source are overwritten by the next synchronization.

**[CONFIRMED-CODE]** The Web/Worker implementation uses a SQL-backed job model. Migration `0006_operational_console_v310.sql` creates `app.Job`, `app.JobTarget`, `app.JobLog`, and `app.WorkerState`.

**[CONFIRMED-CODE]** Job claiming uses an atomic SQL queue pattern with `UPDLOCK`, `READPAST`, and `ROWLOCK`, scoped by `MachineName`.

## 2. Current action and engine execution model

**[CONFIRMED-PRODUCTION]** Executable PowerShell is stored in `ops.Engine.ScriptText`. The Worker invokes engines with the fixed seven-parameter contract:

```text
-ManagementSqlInstance
-ManagementDatabase
-InstanceCode
-RuleCode
-RepairGroup
-Apply
-BackupRoot
```

Not every engine consumes every parameter, but the production invocation contract is fixed.

**[CONFIRMED-SNAPSHOT]** The 2026-10-04 02:00:01 sync snapshot contains 24 `ops.Action` rows, 19 `ops.Engine` rows and 13 `ops.ActionStep` rows.

**[CONFIRMED-SNAPSHOT]** The core V1 engines are present with complete `ScriptText`, version, source filename, SHA-256, minimum PowerShell version and administrator requirement.

**[CONFIRMED-CODE]** The Worker is explicitly granted access to SQL procedures including:

- `ops.GetConsoleActionMenu`
- `ops.GetInstanceMenu`
- `ops.GetActionPlan`
- `ops.GetEngineScript`
- `ops.StartConsoleSession`
- `ops.EndConsoleSession`
- `ops.StartExecution`
- `ops.CompleteExecution`

This confirms that action composition and engine retrieval are SQL-owned in the current system.

**[CONFIRMED-CODE]** `Invoke-SISQUALManagementJob.ps1` validates engine content before execution. It parses PowerShell AST and rejects known interactive commands such as `Read-Host`, `Get-Credential`, `Out-GridView`, and `Pause`.

**[CONFIRMED-CODE]** Engine integrity is hash-gated. The Worker computes the engine SHA-256 over UTF-16 LE bytes because SQL Server converts `nvarchar` to `varbinary` using UTF-16 LE semantics. Changing that encoding produces an engine hash mismatch.

**[CONFIRMED-PRODUCTION]** Hash misalignment is a known production failure mode: `ScriptSha256` / `ContentSha256` must match the stored content or execution is blocked.

## 3. Configuration-repair model

**[CONFIRMED-CODE]** `database/engines/CONFIG_REPAIR.ps1` is present as a standalone reference script.

**[CONFIRMED-SNAPSHOT]** The active `ops.Engine` entry is:

- EngineCode: `CONFIG_REPAIR`
- SourceFileName: `Invoke-ConfigRepair.ps1`
- EngineVersion: `15.0`
- MinimumPowerShell: `5.1`
- RequiresAdministrator: `1`

**[CONFIRMED-SNAPSHOT]** Its central dependencies resolve through `cfg.GetLocalManagementContext`, `cfg.ReviewRepairModel` and `cfg.GetRepairPlan`, backed by `cfg.Application`, `cfg.ConfigFile`, `cfg.ConfigFileRepairPolicy`, `cfg.ConfigRule`, `dbo.ManagedInstance`, `dbo.ManagedServer` and the current credential runtime.

**[CONFIRMED-CODE/SNAPSHOT]** Preview is the default and `-Apply` enables writes. The engine performs generic JSON/XML/whole-file/TEXT_REGEX repair behavior and creates backup/report evidence.

**[CONFIRMED-PRODUCTION]** SISQUAL-specific decisions belong in configuration data, not hard-coded engine branches.

**[CONFIRMED-PRODUCTION]** Exact-string replacement is a known trap. T-SQL `REPLACE()` can silently make no change when the expected text differs. Parser/semantic validation is therefore required around script or configuration rewrites.

## 4. Database-content synchronization model

**[CONFIRMED-SNAPSHOT]** The current operational mapping is exact:

```text
ops.Action.ActionCode = DATABASE_SETTINGS
        |
        v
ops.Action.EngineCode = DATABASE_CONTENT_SYNC
        |
        v
ops.Engine.EngineCode = DATABASE_CONTENT_SYNC
```

The active engine is `DATABASE_CONTENT_SYNC.ps1`, version `v4`, minimum PowerShell `5.1`, administrator required.

**[CONFIRMED-SNAPSHOT]** `cfg.DatabaseObjectSettingRule` contains the current rule contract:

- `ObjectSettingRuleID`
- `SettingCode`
- `CountryCode`
- `TargetDatabaseName`
- `TargetSchemaName`
- `TargetTableName`
- `TargetColumnName`
- `ExpectedTemplate`
- `IsRequired`
- `IsSensitive`
- `SortOrder`
- `IsEnabled`
- `ModifiedAt`
- `FilterClause`
- `RuleType`
- `CreateIfMissing`
- `InsertColumnsJson`

**[CONFIRMED-SNAPSHOT]** The engine uses direct `System.Data.SqlClient.SqlConnection` connections and references `cfg.DatabaseObjectSettingRule`, `cfg.ExpandTemplate`, `dbo.ManagedInstance` and `dbo.ManagedServer`.

**[CONFIRMED-SNAPSHOT]** `cfg.ConfigurationAdapterDefinition` still contains `DATABASE_SETTING -> SETTINGS_SYNC`, but there is no `ops.Action` or `ops.Engine` named `SETTINGS_SYNC`. This is stale adapter metadata, not the active execution mapping.

The same pattern exists for Windows services: the adapter still says `SERVICE_RECONCILE`, while the active action and engine are both `WINDOWS_SERVICES`.

## 5. Managed server and environment model

**[CONFIRMED-SNAPSHOT]** `dbo.ManagedServer` has:

- `ServerCode`
- `MachineName`
- `ServicesRoot`
- `IsEnabled`
- `CreatedAt`
- `ModifiedAt`
- `ConfigBackupRoot`
- `ManagementDatabaseName`

**[CONFIRMED-SNAPSHOT]** `dbo.ManagedInstance` has:

- `InstanceCode`
- `ServerCode`
- `CountryCode`
- `CultureCode`
- `CustomerCode`
- `CustomerName`
- `HostName`
- `SqlInstanceName`
- `LinkedServer`
- `DatabaseName`
- `ChannelID`
- legacy `MobileAppToken`
- `IsEnabled`
- `Notes`
- creation/modification metadata
- customer-logo payload/metadata
- `IisIdentityUserName` / legacy `IisIdentityPassword`
- `WebAccessUserName` / legacy `WebAccessPassword`
- links settings
- `TsplusAdminToolPath`
- `TsplusWebControlEnabled`
- `KeycloakHttpPort`
- `KeycloakHttpsPort`
- `KeycloakManagementPort`

**[CONFIRMED-SNAPSHOT]** The 02:00 snapshot contains 76 ManagedInstance rows. The three historical plaintext secret columns `MobileAppToken`, `IisIdentityPassword` and `WebAccessPassword` are NULL in all 76 generated INSERT rows.

**[CONFIRMED-CODE]** Current code joins `ManagedInstance.ServerCode` to `ManagedServer.ServerCode` and constrains operational work by local `MachineName`.

## 6. Current credential model

**[CONFIRMED-CODE]** Migration `0030_operational_hardening_legacy_cleanup_v370.sql` creates `sec.ManagedCredential` and encrypts secrets with an AES-256 SQL symmetric key protected by a SQL certificate.

**[CONFIRMED-SNAPSHOT]** The generated sync payload contains 191 `sec.ManagedCredential` data rows and 384 `sec.ManagedCredentialAudit` rows.

**[CONFIRMED-CODE]** Supported credential types are:

- `IIS_IDENTITY`
- `WEB_ACCESS`
- `MOBILE_APP_TOKEN`

**[CONFIRMED-PRODUCTION]** The certificate/master-key chain is local to each SQL/server environment and is not naturally portable. Copying the encrypted rows does not make the secret usable on another server without the matching key material.

This is intentionally **not** the credential model selected for SISQUALDeployConsole V1. The approved new-product direction uses a local asymmetric machine identity and offline encrypted + signed credential envelopes. Normal central-cache synchronization must not import the old vault as executable credential authority.

## 7. Current Windows privilege model

**[CONFIRMED-CODE]** The current Worker asserts local Administrator privileges before management execution.

**[CONFIRMED-SNAPSHOT]** All core mutable engines except `DEPLOYMENT_PREFLIGHT` declare `RequiresAdministrator=1`; `DEPLOYMENT_PREFLIGHT` declares `0`.

**[CONFIRMED-CODE/SNAPSHOT]** Current runtime/engine code directly uses Windows/IIS APIs such as `WebAdministration`, `Get-Website`, `Get-WebApplication`, `Get-CimInstance Win32_Service`, Windows service control, `netsh`, `sc.exe` and local file operations depending on engine.

**[CONFIRMED-SNAPSHOT]** Every core engine declares minimum PowerShell `5.1`.

**[V]** PowerShell 7 compatibility for the required IIS/Windows behavior is not yet proven and belongs to Phase 1.

## 8. Current operational capabilities beyond the initial handoff scope

The reference `master` contains a wider operational surface than the core engine list in the production handoff.

**[CONFIRMED-CODE/SNAPSHOT]** Current migrations/runtime/snapshot include or reference:

- Database Copy / native backup-restore
- Environment Clone
- Environment power/maintenance operations
- Links publishing
- Housekeeping / retention
- Storage-size scanning
- Version intelligence
- Approvals and schedules
- TSplus portable operations
- Website-folder and file-copy studios

**[CONFIRMED]** Discovery of these capabilities does **not** expand V1 scope. They are inventory evidence only. Scope expansion requires an explicit later decision.

## 9. Repository sync payload — corrected finding

The previous version of this document incorrectly stated that `database/sync/ManagementSync.sql` was zero-length.

That conclusion was false.

**[CONFIRMED-CODE]** At the exact initial commit `1050fbbc97b6b077302154dd2e7307cce2ca3bbc`, Git tree metadata reports:

- blob SHA: `31d3792f377d759cf4164d8d4f77a987b3c3622d`
- size: **29,515,731 bytes**

**[CONFIRMED-SNAPSHOT]** At current master `1e38c8ed860615c4039ea2ec870f245102943ae4`, Git tree metadata reports:

- blob SHA: `4db6368dcab466bcd15cabdace92ebf3a408f798`
- size: **29,516,382 bytes**
- header: `_sisqualMANAGEMENT sync script - generated 2026-10-04 02:00:01 from ./_sisqualMANAGEMENT`

The earlier error occurred because the high-level `fetch_file` read returned an empty content string for this ~29.5 MB file. That empty tool response was incorrectly interpreted as an empty Git blob. Tree/blob metadata and the contents endpoint prove otherwise.

### Evidence-collection guardrail

From this correction onward:

1. an empty content response for a large repository file is **not** evidence that the file is empty;
2. verify blob SHA and byte size from the Git tree;
3. use the contents/blob endpoint or segmented/programmatic parsing for oversized files;
4. only conclude “empty file” when repository metadata also reports zero bytes.

**[CONFIRMED-SNAPSHOT]** The 02:00:01 payload was parsed as a complete generated sync script containing:

- 68,763 lines;
- 117 table DDL definitions;
- 200 `CREATE OR ALTER PROCEDURE` definitions;
- 5 functions;
- 6 views;
- 31,959 generated INSERT statements;
- schema plus data for the central model.

**[CONFIRMED-SNAPSHOT]** The known designed data exclusions are:

- `app.JobLog`
- `app.HousekeepingArtifact`
- `dbo.DemoProfileImage`

For all three, the table DDL is present but there are zero generated data INSERTs. This confirms that the exclusion is from synchronized data, not from schema creation.

Other tables may also have zero current rows; zero rows alone must not be interpreted as a design exclusion.

## 10. What the full sync payload resolves

The snapshot removes several Phase 0 uncertainties.

**[CONFIRMED-SNAPSHOT]**

- the complete active `ops.Action` catalogue is available;
- the complete `ops.Engine.ScriptText` for the core engines is available;
- the exact `FULL_DEPLOYMENT` composition is available;
- exact central table schemas are available;
- exact current engine versions, minimum PowerShell and administrator requirements are available;
- engine-to-action mappings are available;
- engine SQL/procedure dependencies can be derived from the actual stored scripts and procedure definitions.

The snapshot is therefore a primary Phase 0 source alongside the production handoff and versioned source code.

It does **not** change the V1 authority decision: current SQL-stored `ScriptText` is migration/reference evidence only; V1 executable authority will be local versioned modules.

## 11. Current-system failure lessons that must carry forward

The following are **[CONFIRMED-PRODUCTION]** lessons:

1. Golden-source synchronization is one-way; edits on non-golden nodes are lost.
2. Credential encryption tied to local SQL certificate state is not portable.
3. Exact `REPLACE()` operations can fail silently.
4. Script/content hashes must be computed with exactly aligned encoding/content.
5. Cross-instance linked servers are fragile; direct `SqlConnection` is preferred.
6. Instance rename touches multiple foreign-key/dependent surfaces, including credentials, links and pulse state.
7. A cloned Keycloak environment inherits source URLs/secrets unless explicitly repaired.

An additional **[CONFIRMED-CODE]** metadata-consistency lesson is now visible: `cfg.ConfigurationAdapterDefinition` can contain stale action names that no longer exist in `ops.Action`. V1 must validate cross-catalogue references instead of trusting adapter metadata blindly.

## 12. Approved SISQUALDeployConsole V1 boundary derived from this map

**[CONFIRMED]** The approved V1 direction is:

```text
central configuration
        |
        | read-only synchronization
        v
local SQLite cache
        |
        v
local PowerShell modules
        |
        v
local execution
```

No V1 authoring writes configuration back to the central database.

**[CONFIRMED]** The central database remains authoritative for configuration.

**[CONFIRMED]** Local SQLite stores a mirror/cache plus local application/operation state; it is not a replacement central database.

**[CONFIRMED]** The new Pode process is transient and is not installed as a service or scheduled task.

**[CONFIRMED]** Credentials use the separate offline asymmetric flow, not normal central-cache synchronization.

## 13. Phase 0 acceptance check

- **All handoff engines classified:** yes; see `engine-porting-matrix.md`.
- **Full generated sync payload inspected:** yes.
- **Reference-code vs production-handoff differences identified:** yes.
- **Action/engine alias ambiguity resolved where the snapshot permits:** yes.
- **Reference repository modified:** no.
- **Product code created:** no.
- **Remaining unproven items marked:** yes, with `[INFERRED]`, `[PENDING]`, or `[V]`.
