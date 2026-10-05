# Phase 0 - Current System Map

**Status:** Phase 0 diagnostic, corrected after full sync-payload analysis  
**Reference repository:** `atsisqual/SISQUALManagementConsole` - read-only  
**Initial reference commit inspected:** `1050fbbc97b6b077302154dd2e7307cce2ca3bbc`  
**Full sync snapshot analysed for this correction:** `master` @ `1e38c8ed860615c4039ea2ec870f245102943ae4`  
**Production evidence source:** approved knowledge-transfer document based on direct execution on 4+ real production servers  
**Target repository:** `atsisqual/SISQUALDeployConsole`

## Evidence vocabulary

- **[CONFIRMED-CODE]** visible in the inspected reference-repository code/sync payload.
- **[CONFIRMED-PRODUCTION]** confirmed by the production knowledge-transfer evidence.
- **[INFERRED]** derived from confirmed evidence but not directly demonstrated end-to-end.
- **[PENDING]** requires later evidence or a technical spike.
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

**[CONFIRMED-PRODUCTION]** Executable PowerShell is stored in `ops.Engine.ScriptText`. The Worker invokes engines with the fixed seven-parameter compatibility contract:

```text
-ManagementSqlInstance
-ManagementDatabase
-InstanceCode
-RuleCode
-RepairGroup
-Apply
-BackupRoot
```

Not every engine consumes every parameter. The live `ops.Engine` rows show several engines with narrower explicit parameter blocks, but the Worker compatibility contract is fixed around those seven names.

**[CONFIRMED-CODE]** The current sync payload contains **19 rows in `ops.Engine`**, **24 rows in `ops.Action`** and **13 rows in `ops.ActionStep`**.

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

**[CONFIRMED-CODE]** Engine integrity is hash-gated. The Worker computes engine SHA-256 over UTF-16 LE bytes because SQL Server converts `nvarchar` to `varbinary` using UTF-16 LE semantics.

**[CONFIRMED-PRODUCTION]** Hash misalignment is a known production failure mode: `ScriptSha256` / `ContentSha256` must match the stored content or execution is blocked.

## 3. Configuration-repair model

**[CONFIRMED-CODE]** The live sync payload contains `CONFIG_REPAIR` engine version **15.0**, source name `Invoke-ConfigRepair.ps1`, minimum PowerShell **5.1**, administrator required.

**[CONFIRMED-CODE]** Its exact SQL procedure dependencies include:

- `cfg.GetLocalManagementContext`
- `cfg.GetRepairPlan`
- `cfg.ReviewRepairModel`

**[CONFIRMED-CODE]** It executes SQL-owned generic configuration operations over JSON, XML and text. Current central data contains:

- 41 `cfg.ConfigFile` rows: 17 JSON, 21 XML, 3 TEXT;
- 417 `cfg.ConfigRule` rows;
- selector types: 242 `JSON_VALUE`, 99 `XML_TEXT`, 37 `XML_ATTRIBUTE`, 29 `XML_NODES_ALL`, 10 `TEXT_REGEX`;
- validation types: EXACT, INTEGER, BOOLEAN, URL, PATH and CONNECTION_STRING;
- all current repair actions are `SET_VALUE`.

**[CONFIRMED-CODE]** Preview is the default and `-Apply` enables writes.

**[CONFIRMED-CODE]** The engine creates backup/report artefacts and transcript output.

**[CONFIRMED-PRODUCTION]** SISQUAL-specific decisions belong in configuration data, not hard-coded engine branches.

**[CONFIRMED-PRODUCTION]** Exact-string replacement is a known trap. T-SQL `REPLACE()` can silently make no change when the expected text differs. Parser/semantic validation is therefore required around script or configuration rewrites.

## 4. Database-content synchronization model

**[CONFIRMED-CODE]** `DATABASE_CONTENT_SYNC` exists in `ops.Engine` as engine version **v4**, source `DATABASE_CONTENT_SYNC.ps1`, minimum PowerShell **5.1**, administrator required.

**[CONFIRMED-CODE]** Its script directly reads:

- `cfg.DatabaseObjectSettingRule`
- `dbo.ManagedInstance`
- `dbo.ManagedServer`

and uses direct SQL connectivity rather than linked-server execution.

**[CONFIRMED-CODE]** The current sync contains **61** `cfg.DatabaseObjectSettingRule` rows. All 61 current rows use `FULL_REPLACE`; 14 have `CreateIfMissing=1`.

**[CONFIRMED-PRODUCTION]** `SUBSTRING_REPLACE` is part of the production-capability model even though no current row in the analysed 2026-10-04 snapshot uses it.

**[CONFIRMED-CODE]** The exact enabled action mapping is:

```text
ops.Action.ActionCode = DATABASE_SETTINGS
ops.Action.EngineCode = DATABASE_CONTENT_SYNC
```

There is **no `ops.Action` row named `SETTINGS_SYNC`** in the analysed snapshot.

**[CONFIRMED-CODE]** `cfg.ConfigurationAdapterDefinition` still contains `DATABASE_SETTING -> SETTINGS_SYNC`. This is stale/inconsistent metadata relative to the executable `ops.Action` catalogue and must not be treated as a valid alias during the V1 port.

**[CONFIRMED-SYNC]** The same inconsistency exists for Windows services: the effective catalogue is `WINDOWS_SERVICES -> WINDOWS_SERVICES`, while `cfg.ConfigurationAdapterDefinition` still contains `WINDOWS_SERVICE -> SERVICE_RECONCILE`. There are no current `ops.Action` or `ops.Engine` rows named `SETTINGS_SYNC` or `SERVICE_RECONCILE`; both names are stale adapter metadata.

**[CONFIRMED-SYNC]** `ops.Engine` still retains an enabled legacy engine named `DATABASE_SETTINGS` (`Invoke-DatabaseSettings.ps1`, version `1.0`, minimum PowerShell `5.1`, no administrator requirement). The current action `DATABASE_SETTINGS` no longer uses that engine; it selects `DATABASE_CONTENT_SYNC` v4 instead.

**[CONFIRMED-SYNC]** `FULL_DEPLOYMENT` contains 13 rows in `ops.ActionStep`: 12 enabled steps and one disabled step. The disabled row is `V8_KEYCLOAK_CONFIG` at order 63 with `IsEnabled = 0` and `StopOnError = 1`.

## 5. Managed server and environment model

**[CONFIRMED-CODE]** The analysed sync contains **6 `dbo.ManagedServer` rows** and **76 `dbo.ManagedInstance` rows**.

**[CONFIRMED-CODE]** `dbo.ManagedServer` currently contains:

- `ServerCode`
- `MachineName`
- `ServicesRoot`
- `IsEnabled`
- `CreatedAt`
- `ModifiedAt`
- `ConfigBackupRoot`
- `ManagementDatabaseName`

**[CONFIRMED-CODE]** `dbo.ManagedInstance` currently contains, among other fields:

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
- enablement/notes/audit timestamps;
- customer-logo binary/hash metadata;
- IIS/Web Access usernames and historical plaintext password columns;
- links/TSplus settings;
- `KeycloakHttpPort`, `KeycloakHttpsPort`, `KeycloakManagementPort`.

**[CONFIRMED-CODE]** Current code joins `ManagedInstance.ServerCode` to `ManagedServer.ServerCode` and constrains operational work by local `MachineName`.

## 6. Current credential model

**[CONFIRMED-CODE]** Migration `0030_operational_hardening_legacy_cleanup_v370.sql` creates `sec.ManagedCredential` and encrypts secrets with an AES-256 SQL symmetric key protected by a SQL certificate.

**[CONFIRMED-CODE]** The analysed sync contains **191 `sec.ManagedCredential` rows**:

- 76 `IIS_IDENTITY`
- 76 `WEB_ACCESS`
- 39 `MOBILE_APP_TOKEN`

**[CONFIRMED-CODE]** The sync therefore carries the current encrypted `SecretCipher` values as data. This does not make them portable: the associated SQL certificate/key chain remains local to the current security model.

**[CONFIRMED-CODE]** Historical plaintext fields in `dbo.ManagedInstance` are migrated into the encrypted vault and cleared by the v3.7.0 migration.

**[CONFIRMED-PRODUCTION]** The certificate/master-key chain is not naturally portable between management servers.

This is intentionally **not** the credential model selected for SISQUALDeployConsole V1. The approved new-product direction uses a local asymmetric machine identity and offline encrypted credential envelopes.

## 7. Current Windows privilege model

**[CONFIRMED-CODE]** The current Worker asserts local Administrator privileges before management execution.

**[CONFIRMED-CODE]** Current runtime/engine code directly uses Windows/IIS APIs such as `WebAdministration`, IIS provider paths, CIM/Windows service APIs, registry access and filesystem operations.

**[CONFIRMED-CODE]** Every core engine in the analysed `ops.Engine` catalogue has `MinimumPowerShell='5.1'`. All core engines except `DEPLOYMENT_PREFLIGHT` require Administrator according to engine metadata.

**[V]** PowerShell 7 compatibility for the required IIS/Windows modules remains a Phase 1 spike.

## 8. Current operational capabilities beyond the initial handoff scope

The reference `master` contains a wider operational surface than the core V1 engine list.

**[CONFIRMED-CODE]** Current action/engine data includes or references:

- Database Copy / native backup-restore
- Environment state probe / clone support
- Links visibility
- Housekeeping / retention
- Storage-size scanning
- Version/model review
- Keycloak configuration
- approvals/schedules and other current-platform governance surfaces

**[CONFIRMED]** Discovery of these capabilities does **not** expand V1 scope. They are inventory evidence only.

## 9. ManagementSync.sql completeness and the original reading error

The original Phase 0 conclusion that `database/sync/ManagementSync.sql` was a zero-length file was **incorrect**.

### What actually happened

**[CONFIRMED-CODE]** At the original frozen commit `1050fbbc97b6b077302154dd2e7307cce2ca3bbc`, the Git tree reports:

- blob SHA: `31d3792f377d759cf4164d8d4f77a987b3c3622d`
- size: **29,515,731 bytes**

However, the connector's `fetch_file` path returned an empty `content` string for this oversized file, including when a small line range was requested. That empty return was mistakenly interpreted as a property of the repository file.

**[CONFIRMED-CODE]** A second read path through the GitHub contents API returns the actual SQL.

### Snapshot used for the corrected inventory

By the time of correction, `master` had advanced to commit:

`1e38c8ed860615c4039ea2ec870f245102943ae4`

with commit message:

`Nightly _sisqualMANAGEMENT sync export (2026-10-04 02:00)`

For that commit the tree reports:

- blob SHA: `4db6368dcab466bcd15cabdace92ebf3a408f798`
- size: **29,516,382 bytes**

and the file starts with:

```text
/* _sisqualMANAGEMENT sync script - generated 2026-10-04 02:00:01 from ./_sisqualMANAGEMENT */
```

### What the payload actually contains

**[CONFIRMED-CODE]** The full payload was processed, not sampled only from the start.

It contains:

- **117** unique `CREATE TABLE` schema definitions;
- **200** `CREATE OR ALTER PROCEDURE` definitions;
- **5** `CREATE OR ALTER FUNCTION` definitions;
- **6** `CREATE OR ALTER VIEW` definitions;
- **31,959** generated `INSERT INTO [...]` statements;
- **200** `CREATE OR ALTER PROCEDURE` definitions;
- **5** functions;
- **6** views;
- **31,959** generated `INSERT` statements;
- exported data sections for **114** tables;
- exactly three explicit data exclusions:
  - `app.HousekeepingArtifact`
  - `app.JobLog`
  - `dbo.DemoProfileImage`

The three excluded tables still have schema/column DDL in the script; their **data rows** are intentionally omitted. The script marks each with `-- SKIPPED (excluded): ...`.

This means the repository **does contain the central synchronization payload needed for schema/data inventory**, subject to the intentional exclusions above.

### Evidence-handling rule from now on

For large repository artefacts, an empty content result is never sufficient evidence that the file is empty.

The minimum verification sequence is:

1. inspect Git tree metadata and blob `size`/SHA;
2. use an alternate content path when the normal file reader returns empty/truncated output;
3. record the exact commit/SHA used;
4. distinguish tool/read failure from repository content.

## 10. Current-system failure and design lessons that must carry forward

The following are **[CONFIRMED-PRODUCTION]** unless stated otherwise:

1. Golden-source synchronization is one-way; edits on non-golden nodes are lost.
2. Credential encryption tied to local SQL certificate state is not portable.
3. Exact `REPLACE()` operations can fail silently.
4. Script/content hashes must be computed with exactly aligned encoding/content.
5. Cross-instance linked servers are fragile; direct `SqlConnection` is preferred.
6. Instance rename touches multiple dependent surfaces, including credentials, links and pulse state.
7. A cloned Keycloak environment inherits source URLs/secrets unless explicitly repaired.
8. **[CONFIRMED-CODE]** Large generated repository artefacts can exceed a reader's normal content path; blob metadata and alternate retrieval must be checked before declaring content absent.

## 11. Approved SISQUALDeployConsole V1 boundary derived from this map

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

## 12. Phase 0 acceptance check

- **All handoff engines classified:** yes; see `engine-porting-matrix.md`.
- **Full current sync payload analysed:** yes, snapshot `1e38c8ed...`.
- **Schema/data exclusions identified:** yes; exactly three intentional data exclusions.
- **Reference-code vs production-handoff differences identified:** yes.
- **Stale adapter action names identified:** yes.
- **Reference repository modified:** no.
- **Product code created:** no.
- **Unproven technical-spike items marked:** yes, with `[PENDING]` or `[V]`.
