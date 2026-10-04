# Phase 0 — Current System Map

**Status:** Phase 0 diagnostic  
**Reference repository:** `atsisqual/SISQUALManagementConsole` — read-only  
**Reference branch/commit inspected:** `master` @ `1050fbbc97b6b077302154dd2e7307cce2ca3bbc`  
**Production evidence source:** approved knowledge-transfer document based on direct execution on 4+ real production servers  
**Target repository:** `atsisqual/SISQUALDeployConsole`

## Evidence vocabulary

- **[CONFIRMED-CODE]** visible in the inspected reference-repository commit.
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

**[CONFIRMED-CODE]** The newer Configuration Adapter catalogue labels the equivalent database-settings surface as `DATABASE_SETTING_RULE` and maps it to action code `SETTINGS_SYNC`.

**[PENDING]** The exact relationship among the production engine name `DATABASE_CONTENT_SYNC`, current action code `SETTINGS_SYNC`, and any aliases in the live central database cannot be proven without the live database/snapshot.

## 5. Managed server and environment model

**[CONFIRMED-PRODUCTION]** `dbo.ManagedServer` represents a physical server and includes at least:

- `ServerCode`
- `MachineName`
- `ServicesRoot`
- `ConfigBackupRoot`

**[CONFIRMED-PRODUCTION]** `dbo.ManagedInstance` represents a managed WFM environment and includes operational identity/configuration such as:

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

## 9. Important repository/evidence gap

**[CONFIRMED-CODE]** `database/sync/ManagementSync.sql` at the inspected `master` commit is a zero-length file.

Therefore the current repository alone cannot reconstruct the production synchronization payload or every pre-existing table definition.

For those areas, this Phase 0 inventory uses the approved production handoff as the authoritative evidence source.

## 10. Current-system failure lessons that must carry forward

The following are **[CONFIRMED-PRODUCTION]** lessons:

1. Golden-source synchronization is one-way; edits on non-golden nodes are lost.
2. Credential encryption tied to local SQL certificate state is not portable.
3. Exact `REPLACE()` operations can fail silently.
4. Script/content hashes must be computed with exactly aligned encoding/content.
5. Cross-instance linked servers are fragile; direct `SqlConnection` is preferred.
6. Instance rename touches multiple foreign-key/dependent surfaces, including credentials, links and pulse state.
7. A cloned Keycloak environment inherits source URLs/secrets unless explicitly repaired.

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
- **Reference repository modified:** no.
- **Product code created:** no.
- **Unproven items marked:** yes, with `[INFERRED]`, `[PENDING]`, or `[V]`.
