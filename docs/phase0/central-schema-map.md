# Phase 0 — Central Schema Map

**Purpose:** identify the central-management data that SISQUALDeployConsole V1 must understand and classify it as central read-only mirror data, credential-delivery data, local-only state, or out-of-scope operational history.

This is a logical map, not a SQLite DDL specification.

## Evidence sources and large-file correction

**[CONFIRMED-CODE]** The inspected reference repository contains migrations from multiple generations of the management platform.

**[CONFIRMED-SYNC]** The generated `database/sync/ManagementSync.sql` is not empty. The Git blob is approximately 29.5 MB and begins with the generated timestamp `2026-10-04 02:00:01`. The earlier zero-length conclusion was caused by an oversized-file limitation in the normal file wrapper.

The generated payload contains schema repair/creation plus exported data. Inspection found 117 distinct `CREATE TABLE` definitions and data inserts across 103 tables. The known data exclusions `app.JobLog`, `app.HousekeepingArtifact`, and `dbo.DemoProfileImage` still receive schema blocks but have no data inserts.

Accordingly this document now treats the generated snapshot as **[CONFIRMED-SYNC]** evidence for exact exported schema, rows, action mappings and SQL-stored engine content. The production handoff remains **[CONFIRMED-PRODUCTION]** evidence for runtime behavior observed on real servers.

## 1. Authority model for V1

**[CONFIRMED — approved product decision]**

```text
Central _sisqualMANAGEMENT
        |
        | READ ONLY
        | snapshot/sync
        v
Local management.db
        |
        +-- central mirror
        +-- local application state
        +-- local operation/audit state
```

V1 never authors configuration back to the central database.

The credential flow is separate:

```text
local machine public key
        |
        | manual/offline
        v
central credential packaging
        |
        | encrypted + signed package
        v
local machine private key
```

Credential plaintext/private-key material is never part of normal central-cache synchronization.

## 2. Core central entities

### `dbo.ManagedServer`

**Evidence:** [CONFIRMED-SYNC] + [CONFIRMED-PRODUCTION]. The snapshot contains six exported rows.

**Role:** physical-server identity and roots.

Exact exported schema fields:
- `ServerCode`
- `MachineName`
- `ServicesRoot`
- `IsEnabled`
- `CreatedAt`
- `ModifiedAt`
- `ConfigBackupRoot`
- `ManagementDatabaseName`

Relationships:
- one ManagedServer -> many ManagedInstance.

V1 classification: **CENTRAL MIRROR — REQUIRED**.

Use:
- bind current machine to an approved server identity;
- scope visible/operable environments;
- resolve roots/defaults.

### `dbo.ManagedInstance`

**Evidence:** [CONFIRMED-SYNC] + [CONFIRMED-PRODUCTION]. The snapshot contains 76 exported rows.

**Role:** authoritative environment identity and operational metadata.

The generated schema confirms:
- `InstanceCode`
- `ServerCode`
- `HostName`
- `CountryCode`
- `CultureCode`
- `CustomerCode`
- `CustomerName`
- `SqlInstanceName`
- `LinkedServer`
- `DatabaseName`
- `ChannelID`
- Keycloak HTTP/HTTPS/management ports [production evidence]
- `TsplusAdminToolPath`
- `TsplusWebControlEnabled`
- `IsEnabled`
- customer branding/assets metadata
- non-secret credential usernames where applicable

Current migration 0030 also shows historical secret columns being cleared after migration to `sec.ManagedCredential`.

V1 classification: **CENTRAL MIRROR — REQUIRED**, excluding plaintext secret material.

Invariant:
- local execution is restricted to enabled instances belonging to the current approved physical server.

### `cfg.Application`

**Evidence:** [CONFIRMED-SYNC]. The snapshot contains 36 exported rows.

**Role:** deployable application catalogue and physical-path templates.

Known production field examples:
- `ApplicationCode`
- `PhysicalPathTemplate`, e.g. `{INSTANCE_ROOT}\V8\sisqual-dashboard`

V1 classification: **CENTRAL MIRROR — REQUIRED** for deployment/config/IIS engines.

### `cfg.ConfigFile`

**Evidence:** [CONFIRMED-SYNC]. The snapshot contains 41 exported rows and confirms `FileID`, `ApplicationCode`, `RelativePath`, `FileFormat`, `IsRequired`, and `IsEnabled`.

**Role:** associates managed configuration files with applications/paths/formats.

V1 classification: **CENTRAL MIRROR — REQUIRED** for CONFIG_REPAIR.

### `cfg.ConfigRule`

**Evidence:** [CONFIRMED-SYNC]. The snapshot contains 417 exported rows and the full rule schema including selector, validation, repair action/value/group/order and missing-node creation fields.

**Role:** desired configuration mutations.

Confirmed supported conceptual formats include JSON, XML and TEXT_REGEX/whole-file operations.

V1 classification: **CENTRAL MIRROR — REQUIRED**.

Security rule:
- rule content is trusted only after snapshot validation; REST clients cannot supply arbitrary mutation expressions that bypass synchronized rules.

### `cfg.DatabaseObjectSettingRule`

**Evidence:** [CONFIRMED-SYNC]. The snapshot contains 61 exported rows.

**Role:** generic application-database setting synchronization.

Exact exported schema includes:
- `ObjectSettingRuleID`
- `SettingCode`
- `CountryCode`
- `TargetDatabaseName`
- `TargetSchemaName`
- `TargetTableName`
- `TargetColumnName`
- `ExpectedTemplate`
- `IsRequired` / `IsSensitive`
- `SortOrder` / `IsEnabled` / `ModifiedAt`
- structured `FilterClause`
- `RuleType`
- `CreateIfMissing`
- `InsertColumnsJson`

V1 classification: **CENTRAL MIRROR — REQUIRED** for DATABASE_CONTENT_SYNC.

Security invariant:
- “structured predicates, never arbitrary SQL from UI/API” is part of the porting contract.

### `cfg.ApplicationCopyPolicy`

**Evidence:** [CONFIRMED-SYNC]. The snapshot contains 22 exported rows and confirms the full field list: `ApplicationCode`, `DisplayName`, `RelativePath`, `CopyBinaries`, `CopyStaticAssets`, `PreserveDestinationConfig`, `ExcludePatterns`, `AssociatedServicePattern`, `HealthCheckPath`, `SortOrder`, `IsEnabled`, `ModifiedAt`, `UpdateSourceFamily`, and `UpdateSourceRelativePath`.

**Role:** authoritative mapping from build/package source to deployed application destination.

V1 classification: **CENTRAL MIRROR — REQUIRED IF a selected V1 engine consumes it**.

The field-list uncertainty is resolved. Exact V1 consumers remain a porting-contract question, not a missing-schema question.

### `ops.Action`

**Evidence:** [CONFIRMED-SYNC] + [CONFIRMED-PRODUCTION]. The snapshot contains 24 exported `ops.Action` rows.

**Role:** action catalogue, mode policy, target requirements and enablement.

Current code confirms policies such as:
- mode policy;
- instance selection requirement;
- allow-all-instances;
- confirmation text;
- enablement.

V1 classification: **CENTRAL MIRROR — REQUIRED** if the local UI/action catalogue remains centrally governed.

V1 does not use this table as a central write queue.

### `ops.ActionStep`

**Evidence:** [CONFIRMED-SYNC]. The snapshot contains 13 exported `ops.ActionStep` rows for `FULL_DEPLOYMENT`: 12 enabled plus disabled `V8_KEYCLOAK_CONFIG` at order 63.

**Role:** ordered composition of actions such as `FULL_DEPLOYMENT`.

V1 classification: **CENTRAL MIRROR — REQUIRED** for centrally governed composite action ordering, subject to contract normalization.

### `ops.Engine`

**Evidence:** [CONFIRMED-SYNC] + [CONFIRMED-PRODUCTION]. The snapshot contains 19 exported engine rows including complete `ScriptText` and integrity hashes.

**Current role:** stores executable PowerShell `ScriptText`, engine metadata and integrity hash.

V1 classification: **MIGRATION SOURCE / METADATA ONLY — NOT EXECUTABLE AUTHORITY**.

Approved V1 architecture ports engines into local versioned modules. The central database must not be able to replace local executable code merely by changing `ScriptText`.

Possible V1 mirrored metadata:
- engine code;
- enabled status;
- descriptive/action mapping;
- source/version/hash for diagnostics/migration traceability.

**[PENDING]** Exact V1 mirrored metadata subset will be defined after the porting contract is frozen. The source schema itself is no longer pending.

## 2.1 Effective action/engine mappings resolved from the snapshot

The generated central state resolves two previously ambiguous names:

- **[CONFIRMED-SYNC]** `DATABASE_SETTINGS` is the enabled `ops.Action` and its `EngineCode` is `DATABASE_CONTENT_SYNC`. The stored engine is `DATABASE_CONTENT_SYNC.ps1` v4.
- **[CONFIRMED-SYNC]** `WINDOWS_SERVICES` is both the enabled action and engine. The stored engine is `Invoke-WindowsServiceReconciliation.ps1` v2.0.
- **[CONFIRMED-SYNC]** `cfg.ConfigurationAdapterDefinition` still contains `SETTINGS_SYNC` and `SERVICE_RECONCILE`, but neither exists as an `ops.Action` or `ops.Engine` in the snapshot. They are stale/inconsistent adapter metadata and must not drive V1 execution mapping.
- **[CONFIRMED-SYNC]** The Windows-service definition schema is present and the current snapshot contains one exported definition: `WFM_MOBILE_APP`, using `AccountSource = IIS_IDENTITY`.
- **[CONFIRMED-SYNC]** `cfg.IisApplicationDefinition` is fully present; the snapshot contains 30 exported rows.

## 3. Credential entities

### `sec.ManagedCredential`

**Evidence:** [CONFIRMED-SYNC] + [CONFIRMED-CODE]. The snapshot contains 191 encrypted credential rows.

Current schema includes:
- `InstanceCode`
- `CredentialType`
- encrypted `SecretCipher`
- secret version
- rotation/modification metadata
- row version

Current credential types:
- IIS_IDENTITY
- WEB_ACCESS
- MOBILE_APP_TOKEN

V1 classification: **DO NOT MIRROR SECRET CIPHERTEXT AS NORMAL CACHE DATA**.

Reason:
- current ciphertext is protected by the existing SQL certificate/key model and is not the approved new portability model.

The new credential-envelope mechanism must be independent of this table's SQL encryption implementation.

### `sec.ManagedCredentialAudit`

Current central audit is useful historical evidence but is not required to execute V1 local operations.

V1 classification: **OPTIONAL READ-ONLY MIRROR / OUT OF INITIAL EXECUTION CONTRACT**.

Local credential package import/use must have its own local audit trail.

## 4. Runtime and UI support surfaces

### `cfg.ManagedInstanceRuntime`

**[CONFIRMED-CODE]** Current migration 0030 creates this view to join instance metadata with decrypted managed credentials.

V1 classification: **DO NOT SYNC AS-IS** because it can expose decrypted secrets.

The sync contract should select explicit safe fields rather than “SELECT *” from runtime views.

### `cfg.ConfigurationAdapterDefinition`

**[CONFIRMED-CODE]** Maps logical configuration surfaces to action codes and preview/apply capability.

V1 classification: **OPTIONAL CENTRAL MIRROR**. Useful for UI metadata, not required as execution authority.

### UI resources/navigation/settings

Current repo contains:
- `ui.Resource`
- `ui.NavigationItem`
- `cfg.SettingSection`
- `cfg.SettingDefinition`
- `cfg.SettingValue`
- `sec.Policy`
- `sec.WindowsGroupPolicy`

V1 classification: **NOT AUTOMATICALLY REQUIRED**.

The new portable product owns its own local UI. Central operational configuration should not be conflated with the old .NET application's navigation/settings model.

## 5. Current central job/runtime state

Current code contains:
- `app.Job`
- `app.JobTarget`
- `app.JobLog`
- `app.WorkerState`
- `app.ActionRuntimePolicy`
- additional later operational-state tables

These exist to coordinate the current central Web + Worker platform.

V1 classification: **DO NOT MIRROR AS ACTIVE CONTROL STATE**.

Equivalent concepts are local-only in the new product:
- Operation
- OperationTarget
- OperationLog
- lock/lease state
- local process/session state

Historical central job data may be surfaced later only as a separate read-only feature.

## 6. Known rename/dependency surfaces

**[CONFIRMED-SYNC + CONFIRMED-PRODUCTION]** Renaming `InstanceCode` affects at least:
- `sec.ManagedCredential`
- `cfg.LinksPageInstanceApplication`
- `ops.PulseCheckState`

The current repo also contains newer links/profile and operational-state surfaces.

Consequence:
- the future `rename-instance` skill cannot assume `dbo.ManagedInstance` is the only authoritative reference.
- V1 read-only central policy means a true central rename cannot be authored by SISQUALDeployConsole V1. The skill can diagnose/plan or operate only within an explicitly approved local/target-system scope.

## 7. Sync classification

### Required central mirror domains

At minimum, with the core source schemas now directly confirmed by the generated snapshot:

```text
ManagedServer
ManagedInstance (safe fields only)
Application
ConfigFile
ConfigRule
DatabaseObjectSettingRule
ApplicationCopyPolicy (when consumed)
Action
ActionStep
safe engine metadata
engine-specific definition/policy tables required by V1
```

### Explicit exclusions from generic snapshot

```text
decrypted secrets
SQL master keys/certificates/symmetric keys
current central Worker queue ownership
central write/approval state not required for local execution
arbitrary executable ScriptText as runtime authority
temporary SQL session/runtime state
```

## 8. Snapshot contract requirements derived from schema

The future sync manifest must include at least:

- contract/schema version;
- snapshot ID;
- generation timestamp UTC;
- source identity;
- per-entity counts;
- per-entity/content hashes;
- compatibility version;
- enough server identity to prove the snapshot applies to the local machine.

Activation must occur only after complete staging validation.

A failed/incompatible snapshot must leave the last valid snapshot active.

## 9. First-run behavior derived from schema authority

Without a valid central snapshot, the application must not interpret an empty local database as “no managed environments”.

It remains in INITIAL SETUP and exposes only bootstrap/identity/connection/sync diagnostics until the first trusted snapshot is activated.

## 10. Open schema work for later phases

**[PENDING]**
- the **new V1** column-level snapshot contract (selection/minimization), even though the current central schemas are now known;
- exact V1 schema/version negotiation;
- exact safe subset of engine metadata;
- exact set of Keycloak/IIS/service policy tables each local engine should mirror (the source tables can now be extracted from the committed payload without live-DB access);
- whether V1 consumes a dedicated read-only export procedure/snapshot endpoint or performs explicit read-only SELECTs;
- snapshot transport and atomic activation details.

**Resolved in Phase 0 correction:** the current source schemas for the core tables, the SQL-stored V1 engine texts, `DATABASE_SETTINGS -> DATABASE_CONTENT_SYNC`, `WINDOWS_SERVICES -> WINDOWS_SERVICES`, and the fact that `SETTINGS_SYNC` / `SERVICE_RECONCILE` are stale adapter metadata rather than active execution identifiers.

These are not user decisions required now; they are implementation/technical work for subsequent phases.

## 11. Phase 0 acceptance

- Core central objects from the handoff are mapped.
- Central-authoritative vs local-only state is explicit.
- Secret-bearing current views/tables are identified as unsafe for generic mirroring.
- V1 read-only authoring policy is encoded.
- Core live-export schema detail is now derived directly from the committed generated snapshot; remaining [PENDING] items are V1 design/porting questions rather than missing central-schema evidence.
- No DDL/product implementation has been created.
