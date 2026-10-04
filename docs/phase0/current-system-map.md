# Phase 0 — Current System Map

**Status:** Phase 0 diagnostic  
**Reference repository:** `atsisqual/SISQUALManagementConsole` — read-only  
**Reference branch/commit inspected:** `master` @ `1050fbbc97b6b077302154dd2e7307cce2ca3bbc`  
**Production evidence source:** approved knowledge-transfer document based on direct execution on 4+ real production servers  
**Target repository:** `atsisqual/SISQUALDeployConsole`

## Evidence vocabulary

- **[CONFIRMED-CODE]** visible in normal versioned source/migrations in the inspected reference-repository commit.
- **[CONFIRMED-SYNC]** visible in the generated `database/sync/ManagementSync.sql` snapshot committed in the reference repository.
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

**[CONFIRMED-CODE]** `database/engines/CONFIG_REPAIR.ps1` is present as a standalone reference script and currently declares `#requires -Version 5.1`.

**[CONFIRMED-CODE]** It resolves the local management SQL context, obtains a SQL-owned repair model through `cfg.ReviewRepairModel` and `cfg.GetRepairPlan`, and executes generic operations over JSON, XML, whole-file content and `TEXT_REGEX`.

**[CONFIRMED-CODE]** Preview is the default and `-Apply` enables writes.

**[CONFIRMED-CODE]** The engine creates a run-specific backup/report directory and a transcript.

**[CONFIRMED-PRODUCTION]** SISQUAL-specific decisions belong in configuration data, not hard-coded engine branches.

**[CONFIRMED-PRODUCTION]** Exact-string replacement is a known trap. T-SQL `REPLACE()` can silently make no change when the expected text differs. Parser/semantic validation is therefore required around script or configuration rewrites.

## 4. Database-content synchronization model

**[CONFIRMED-PRODUCTION]** `DATABASE_CONTENT_SYNC` exists in production and is implemented in PowerShell without cross-instance linked-server dependence.

**[CONFIRMED-PRODUCTION]** `cfg.DatabaseObjectSettingRule` expresses database-content changes using structured target metadata and rule types `FULL_REPLACE` / `SUBSTRING_REPLACE`. Its filter model is structured and must not become arbitrary SQL text supplied by a browser.

**[CONFIRMED-SYNC]** The generated central snapshot resolves the effective mapping precisely: `ops.Action.ActionCode = DATABASE_SETTINGS` is enabled and points to `ops.Engine.EngineCode = DATABASE_CONTENT_SYNC`; the stored engine is `DATABASE_CONTENT_SYNC.ps1`, version `v4`.

**[CONFIRMED-SYNC]** `cfg.ConfigurationAdapterDefinition` still contains `ActionCode = SETTINGS_SYNC` for the `DATABASE_SETTING` adapter, while its route is `/actions?action=DATABASE_SETTINGS`. No `ops.Action` or `ops.Engine` named `SETTINGS_SYNC` exists in the generated snapshot. Therefore `SETTINGS_SYNC` is stale/inconsistent adapter metadata, not the effective execution action.

## 5. Managed server and environment model

**[CONFIRMED-SYNC]** The generated snapshot contains the complete `dbo.ManagedServer` schema and six data rows. It represents a physical server and includes:

- `ServerCode`
- `MachineName`
- `ServicesRoot`
- `ConfigBackupRoot`

**[CONFIRMED-SYNC]** The generated snapshot contains the complete `dbo.ManagedInstance` schema and 76 data rows. It represents a managed WFM environment and includes operational identity/configuration such as:

- `InstanceCode`
- `ServerCode`
- `HostName`
- `CountryCode` / `CultureCode`
- `CustomerCode` / `ChannelID`
- `SqlInstanceName` / `LinkedServer`
- Keycloak ports
- TSplus administration path/settings
- enablement and customer metadata

**[CONFIRMED-CODE]** Current code joins `ManagedInstance.ServerCode` to `ManagedServer.ServerCode` and constrains operational work by local `MachineName`.

**[CONFIRMED-CODE]** `app.GetManagedEnvironments` resolves SQL data source from `ManagedServer.MachineName` plus `ManagedInstance.SqlInstanceName`.

## 6. Current credential model

**[CONFIRMED-CODE]** Migration `0030_operational_hardening_legacy_cleanup_v370.sql` creates `sec.ManagedCredential` and encrypts secrets with an AES-256 SQL symmetric key protected by a SQL certificate.

**[CONFIRMED-CODE]** Supported credential types are:

- `IIS_IDENTITY`
- `WEB_ACCESS`
- `MOBILE_APP_TOKEN`

**[CONFIRMED-CODE]** Historical plaintext fields in `dbo.ManagedInstance` are migrated into the encrypted vault and then cleared.

**[CONFIRMED-PRODUCTION]** The certificate/master-key chain is local to each SQL/server environment and is not naturally portable. A database/snapshot copied to another server does not make the credential vault usable there without explicit key export/import.

This is intentionally **not** the credential model selected for SISQUALDeployConsole V1. The approved new-product direction uses a local asymmetric machine identity and offline encrypted credential envelopes.

## 7. Current Windows privilege model

**[CONFIRMED-CODE]** The current Worker asserts local Administrator privileges before management execution.

**[CONFIRMED-CODE]** Current runtime code directly uses Windows/IIS APIs such as `WebAdministration`, `Get-Website`, `Get-WebApplication`, application-pool state functions, `Get-CimInstance Win32_Service`, and Windows service control.

**[CONFIRMED-CODE]** The reference PowerShell runtime declares Windows PowerShell 5.1 compatibility in key entry points.

**[V]** PowerShell 7 compatibility for the required IIS/Windows modules is not yet proven and belongs to Phase 1.

## 8. Current operational capabilities beyond the initial handoff scope

The reference `master` contains a wider operational surface than the core engine list in the production handoff.

**[CONFIRMED-CODE]** Current migrations/runtime include or reference:

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

**[CONFIRMED-CODE]** `database/engines/STORAGE_SIZE_SCAN.ps1` exists as an additional standalone engine and is not part of the initially approved SISQUALDeployConsole V1 engine list.

**[CONFIRMED]** Discovery of these capabilities does **not** expand V1 scope. They are inventory evidence only. Scope expansion requires an explicit later decision.

## 9. Generated sync payload in the repository

**[CORRECTED]** The earlier Phase 0 statement that `database/sync/ManagementSync.sql` was zero-length was false. The error came from treating an empty `fetch_file` response for an oversized blob as evidence that the Git blob itself was empty.

**[CONFIRMED-SYNC]** At the inspected `master` commit, the Git tree reports the `ManagementSync.sql` blob at approximately 29.5 MB. Its content begins:

```text
/* _sisqualMANAGEMENT sync script - generated 2026-10-04 02:00:01 from ./_sisqualMANAGEMENT */
```

The file contains real generated SQL for the central model: schema creation/repair plus data inserts. Automated inspection of the payload found 117 distinct `CREATE TABLE` definitions and data inserts across 103 tables.

**[CONFIRMED-SYNC + CONFIRMED-PRODUCTION]** The three known high-volume exclusions are handled as schema-only in this payload:

- `app.JobLog`
- `app.HousekeepingArtifact`
- `dbo.DemoProfileImage`

All three have schema blocks in the generated script and zero data `INSERT` statements. Their row data is excluded by design.

**[CONFIRMED-SYNC]** The payload also includes the actual rows for `ops.Engine`, `ops.Action`, `ops.ActionStep`, the central configuration tables, managed instances/servers, credential ciphertext rows, IIS/service definitions, links and pulse state. Consequently, many facts previously marked pending because they appeared to require a live DB can be proven directly from the committed generated snapshot.

### Repository-reading guardrail

A repository tool returning empty content for a large file must never again be interpreted as “zero-byte file” without independent metadata verification.

For large blobs the required sequence is:

1. inspect Git tree/contents metadata and record the real blob size;
2. if the normal file wrapper elides content, use the GitHub contents endpoint and process the payload inside the tool call;
3. extract targeted blocks/rows instead of emitting the entire large file;
4. only classify a file as empty when Git metadata reports size 0.

## 10. Current-system failure lessons that must carry forward

The following are **[CONFIRMED-PRODUCTION]** lessons:

1. Golden-source synchronization is one-way; edits on non-golden nodes are lost.
2. Credential encryption tied to local SQL certificate state is not portable.
3. Exact `REPLACE()` operations can fail silently.
4. Script/content hashes must be computed with exactly aligned encoding/content.
5. Cross-instance linked servers are fragile; direct `SqlConnection` is preferred.
6. Instance rename touches multiple foreign-key/dependent surfaces, including credentials, links and pulse state.
7. A cloned Keycloak environment inherits source URLs/secrets unless explicitly repaired.
8. Generated sync snapshots are authoritative evidence of the exported central state, but large-file tooling must be size-verified before conclusions are drawn.

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
- **Reference-code vs production-handoff differences identified:** yes.
- **Generated sync payload inspected directly:** yes; schema/data and action/engine mappings are now part of the evidence set.
- **Reference repository modified:** no.
- **Product code created:** no.
- **Unproven items marked:** yes, with `[INFERRED]`, `[PENDING]`, or `[V]`.
