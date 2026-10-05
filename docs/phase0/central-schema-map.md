# Phase 0 - Central Schema Map

**Purpose:** identify the central-management data that SISQUALDeployConsole V1 must understand and classify it as central read-only mirror data, credential-delivery data, local-only state, or out-of-scope operational history.

**Reference sync snapshot:** `atsisqual/SISQUALManagementConsole` `master` @ `1e38c8ed860615c4039ea2ec870f245102943ae4`  
**Sync file:** `database/sync/ManagementSync.sql`  
**Blob SHA:** `4db6368dcab466bcd15cabdace92ebf3a408f798`  
**Blob size:** 29,516,382 bytes

This is a logical inventory and authority map, not SQLite DDL.

## 1. Sync-payload completeness

The original Phase 0 document incorrectly described the sync file as empty because the normal file-reader path returned an empty content string for the oversized blob.

**[CONFIRMED-CODE]** The full sync payload was re-read through an alternate GitHub content path and programmatically processed end-to-end.

It contains:

- **117** unique table schema definitions;
- **114** table data-export sections;
- exactly three explicit data exclusions:
  - `app.HousekeepingArtifact`
  - `app.JobLog`
  - `dbo.DemoProfileImage`.

The excluded tables still receive schema DDL; only their data is omitted. The generated file marks them with `-- SKIPPED (excluded): ...`.

Therefore the central schema/data inventory can be derived directly from this repository snapshot for the exported surfaces.

## 2. V1 authority model

**[CONFIRMED - approved product decision]**

```text
Central _sisqualMANAGEMENT
        |
        | READ ONLY
        | validated snapshot/sync
        v
Local management.db
        |
        +-- central mirror
        +-- local application state
        +-- local operation/audit state
```

V1 never authors configuration back to the central database.

Credential delivery is a separate flow:

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

Private-key material and credential plaintext are never part of normal central-cache synchronization.

## 3. Core central entities and current row counts

| Object | Rows in analysed sync | V1 classification |
|---|---:|---|
| `dbo.ManagedServer` | 6 | REQUIRED CENTRAL MIRROR |
| `dbo.ManagedInstance` | 76 | REQUIRED CENTRAL MIRROR, safe fields only |
| `cfg.Application` | 36 | REQUIRED CENTRAL MIRROR |
| `cfg.ConfigFile` | 41 | REQUIRED CENTRAL MIRROR |
| `cfg.ConfigRule` | 417 | REQUIRED CENTRAL MIRROR |
| `cfg.DatabaseObjectSettingRule` | 61 | REQUIRED CENTRAL MIRROR |
| `cfg.ApplicationCopyPolicy` | 22 | CENTRAL MIRROR only if a V1 engine consumes it |
| `cfg.WindowsServiceDefinition` | 1 | REQUIRED CENTRAL MIRROR |
| `cfg.KeycloakClientSecretRule` | 8 | REQUIRED NON-SECRET CENTRAL MIRROR |
| `cfg.PulseProfile` | 4 | REQUIRED CENTRAL MIRROR |
| `cfg.LinksPageInstanceApplication` | 12 | REQUIRED/DERIVED LINKS POLICY INPUT |
| `ops.Action` | 24 | REQUIRED CENTRAL MIRROR for centrally governed action catalogue |
| `ops.ActionStep` | 13 | REQUIRED CENTRAL MIRROR for composite ordering |
| `ops.Engine` | 19 | METADATA/MIGRATION SOURCE; NOT executable authority |
| `ops.PulseCheckState` | 132 | CURRENT CENTRAL RUNTIME STATE; not active V1 control state |
| `sec.ManagedCredential` | 191 | DO NOT mirror secret ciphertext into normal V1 cache |

## 4. Physical server model - dbo.ManagedServer

**[CONFIRMED-CODE] Exact current columns**

- `ServerCode varchar(30) NOT NULL`
- `MachineName sysname NOT NULL`
- `ServicesRoot nvarchar(1000) NOT NULL`
- `IsEnabled bit NOT NULL`
- `CreatedAt datetime2 NOT NULL`
- `ModifiedAt datetime2 NOT NULL`
- `ConfigBackupRoot nvarchar(1000) NOT NULL`
- `ManagementDatabaseName sysname NOT NULL`

Role:
- identifies a physical management target;
- scopes local environments;
- resolves filesystem roots and management DB identity.

V1 classification: **REQUIRED CENTRAL MIRROR**.

## 5. Environment model - dbo.ManagedInstance

**[CONFIRMED-CODE] Exact current columns**

- `InstanceCode varchar(20) NOT NULL`
- `ServerCode varchar(30) NOT NULL`
- `CountryCode char(2) NOT NULL`
- `CultureCode nvarchar(10) NOT NULL`
- `CustomerCode int NULL`
- `CustomerName nvarchar(100) NULL`
- `HostName sysname NOT NULL`
- `SqlInstanceName sysname NULL`
- `LinkedServer sysname NULL`
- `DatabaseName sysname NOT NULL`
- `ChannelID int NULL`
- `MobileAppToken nvarchar(255) NULL`
- `IsEnabled bit NOT NULL`
- `Notes nvarchar(1000) NULL`
- `CreatedAt datetime2 NOT NULL`
- `ModifiedAt datetime2 NOT NULL`
- `CustomerLogo varbinary(max) NULL`
- `CustomerLogoFileName nvarchar(260) NULL`
- `CustomerLogoMimeType varchar(100) NULL`
- `CustomerLogoSha256 char(64) NULL`
- `CustomerLogoModifiedAt datetime2 NULL`
- `IisIdentityUserName nvarchar(255) NULL`
- `IisIdentityPassword nvarchar(255) NULL`
- `WebAccessUserName sysname NULL`
- `WebAccessPassword nvarchar(255) NULL`
- `WebAccessModifiedAt datetime2 NULL`
- `LinksIncludeAllInstances bit NOT NULL`
- `LinksAssignedUserName nvarchar(150) NULL`
- `TsplusAdminToolPath nvarchar(1000) NULL`
- `TsplusWebControlEnabled bit NOT NULL`
- `KeycloakHttpPort int NULL`
- `KeycloakHttpsPort int NULL`
- `KeycloakManagementPort int NULL`

V1 classification: **REQUIRED CENTRAL MIRROR, explicit safe-column contract only**.

The historical/plaintext secret columns must not be copied into V1 merely because they exist in the current schema.

## 6. Application/configuration model

### cfg.Application

**Current rows:** 36.

Exact columns:
- `ApplicationCode`
- `DisplayName`
- `FolderName`
- `IisPath`
- `PhysicalPathTemplate`
- `IsOptional`
- `IsEnabled`
- Links display/URL/icon/sort/publication/default/hub fields.

V1 use:
- application identity;
- physical-path resolution;
- IIS/config/link mappings.

### cfg.ConfigFile

**Current rows:** 41.

Exact columns:
- `FileID`
- `ApplicationCode`
- `RelativePath`
- `FileFormat`
- `IsRequired`
- `IsEnabled`

Current format distribution:
- JSON: 17
- XML: 21
- TEXT: 3

### cfg.ConfigRule

**Current rows:** 417.

Exact columns:
- `RuleID`
- `FileID`
- `CountryCode`
- `RuleCode`
- `Category`
- `SelectorType`
- `Selector`
- `ExpectedTemplate`
- `ValidationType`
- `IsRequired`
- `AllowEncrypted`
- `IsSensitive`
- `Severity`
- `Description`
- `IsEnabled`
- `CreatedAt`
- `ModifiedAt`
- `RepairAction`
- `RepairValueType`
- `RepairGroup`
- `RepairOrder`
- `CreateIfMissing`
- `MissingParentSelector`
- `MissingNodeTemplate`

Current selector distribution:
- JSON_VALUE: 242
- XML_TEXT: 99
- XML_ATTRIBUTE: 37
- XML_NODES_ALL: 29
- TEXT_REGEX: 10

Current validation types:
- EXACT
- INTEGER
- BOOLEAN
- URL
- PATH
- CONNECTION_STRING

Current repair data:
- all 417 current rows use `SET_VALUE`;
- repair value types: STRING 350, BOOLEAN 53, INTEGER 14.

V1 classification for all three: **REQUIRED CENTRAL MIRROR**.

## 7. Database-content rule model - cfg.DatabaseObjectSettingRule

**Current rows:** 61.

Exact columns:
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

**[CONFIRMED-CODE]** Current data:
- 61 `FULL_REPLACE`;
- 0 current `SUBSTRING_REPLACE` rows;
- 14 rows with `CreateIfMissing=1`.

**[CONFIRMED-PRODUCTION]** SUBSTRING_REPLACE remains a known supported production capability and should remain in the port contract unless later evidence deliberately removes it.

V1 security invariant:
- table/schema/column/filter configuration comes only from a validated trusted snapshot;
- REST/UI input never becomes arbitrary SQL;
- values are parameterized;
- identifiers/predicate grammar are validated against the local contract.

## 8. Windows-service model - cfg.WindowsServiceDefinition

**Current rows:** 1.

Exact columns:
- `ServiceCode`
- `DisplayName`
- `ServiceNameTemplate`
- `DisplayNameTemplate`
- `DescriptionTemplate`
- `ExecutablePathTemplate`
- `ArgumentsTemplate`
- `StartupType`
- `DelayedAutoStart`
- `StartAfterApply`
- `RestartOnApply`
- `AccountSource`
- `CreateAccountIfMissing`
- `PasswordNeverExpires`
- `IsRequired`
- `SortOrder`
- `IsEnabled`
- `ModifiedAt`

Current enabled definition:
- `ServiceCode = WFM_MOBILE_APP`
- `ServiceNameTemplate = sisqualWFMMobileAppService - {HOST_NAME}`
- required = 1.

V1 classification: **REQUIRED CENTRAL MIRROR**.

## 9. Application-copy policy - cfg.ApplicationCopyPolicy

**Current rows:** 22.

Exact columns:
- `ApplicationCode`
- `DisplayName`
- `RelativePath`
- `CopyBinaries`
- `CopyStaticAssets`
- `PreserveDestinationConfig`
- `ExcludePatterns`
- `AssociatedServicePattern`
- `HealthCheckPath`
- `SortOrder`
- `IsEnabled`
- `ModifiedAt`
- `UpdateSourceFamily`
- `UpdateSourceRelativePath`

**[CONFIRMED-CODE]** None of the twelve approved core V1 engine scripts directly references this table.

Therefore V1 classification is now:
- **KNOWN CENTRAL POLICY**
- **not automatically required in the initial local mirror**
- include only if a ported core procedure/plan contract proves a dependency or if Database Copy/related functionality enters V1 scope.

This replaces the previous schema-discovery `[PENDING]` with a narrower runtime/dependency decision.

## 10. Action/engine composition

### ops.Action

**Current rows:** 24.

Columns include:
- `ActionCode`
- `GroupCode`
- `DisplayName`
- `Description`
- `ActionType`
- `EngineCode`
- `SqlCommand`
- `ModePolicy`
- target-selection flags/policy
- apply/pass flags
- confirmation/timeout/sort/menu/error/enablement metadata.

V1 classification: **REQUIRED CENTRAL MIRROR** for action catalogue and centrally governed composition metadata.

### ops.ActionStep

**Current rows:** 13, all belonging to the current FULL_DEPLOYMENT definition; one step is disabled.

Exact columns:
- `ParentActionCode`
- `StepOrder`
- `ChildActionCode`
- `StepPhase`
- `StopOnError`
- `IsEnabled`
- `ModifiedAt`

V1 classification: **REQUIRED CENTRAL MIRROR**.

### ops.Engine

**Current rows:** 19.

Exact columns:
- `EngineCode`
- `DisplayName`
- `SourceFileName`
- `EngineVersion`
- `ScriptText`
- `ScriptSha256`
- `MinimumPowerShell`
- `RequiresAdministrator`
- `IsEnabled`
- `ModifiedAt`

V1 classification:
- **engine identity/version/hash metadata may be mirrored**;
- **central `ScriptText` is not executable authority in V1**;
- local versioned modules are executable authority.

## 11. Confirmed current action-name inconsistency

The full payload resolves the prior ambiguity.

**Executable `ops.Action` catalogue:**

```text
DATABASE_SETTINGS -> DATABASE_CONTENT_SYNC
WINDOWS_SERVICES  -> WINDOWS_SERVICES
```

**Configuration Adapter metadata:**

```text
DATABASE_SETTING -> SETTINGS_SYNC
WINDOWS_SERVICE  -> SERVICE_RECONCILE
```

There are no current `ops.Action` rows named `SETTINGS_SYNC` or `SERVICE_RECONCILE`.

Conclusion: the adapter rows are stale/inconsistent metadata, not valid aliases that V1 should reproduce.

**[CONFIRMED-SYNC]** `ops.Engine` also retains an enabled legacy engine named `DATABASE_SETTINGS` (`Invoke-DatabaseSettings.ps1`, version `1.0`, PowerShell `5.1`, no administrator requirement). This does not alter the effective mapping above: the current `ops.Action` row `DATABASE_SETTINGS` points to `DATABASE_CONTENT_SYNC`, not to the legacy `DATABASE_SETTINGS` engine. The legacy engine is therefore retained catalogue/history, not the engine selected by the current action.

## 12. Credential entities

### sec.ManagedCredential

**Current rows:** 191.

Exact columns:
- `InstanceCode`
- `CredentialType`
- `SecretCipher varbinary(max)`
- `SecretVersion`
- `LastRotatedAt`
- `ModifiedBy`
- `ModifiedAt`
- `RowVersion timestamp`

Current type distribution:
- IIS_IDENTITY: 76
- WEB_ACCESS: 76
- MOBILE_APP_TOKEN: 39

**Important:** current ManagementSync includes these encrypted ciphertext rows.

V1 classification: **DO NOT COPY `SecretCipher` INTO THE GENERAL LOCAL MIRROR**.

Reason:
- current SQL encryption is not the approved V1 portability mechanism;
- ciphertext is tied to the existing SQL certificate/symmetric-key security model;
- normal sync must not become a second credential transport.

### cfg.KeycloakClientSecretRule

**Current rows:** 8.

This contains non-secret mapping:
- `KeycloakClientId`
- `SecretRuleCode`
- `IsEnabled`
- `ModifiedAt`

V1 classification: **safe non-secret central mirror input**, subject to contract review.

## 13. Pulse and links state

### cfg.PulseProfile

**Current rows:** 4.

Contains hub/page/path/scheduled-task/interval/threshold/scope configuration.

This is central policy and is mirrorable.

### ops.PulseCheckState

**Current rows:** 132.

Contains current probe state such as:
- target/check identity;
- raw/display status;
- consecutive failures;
- messages/timings/HTTP status;
- last checked/success timestamps.

V1 classification:
- do not use it as active local execution state;
- current central values may be optionally exposed as read-only imported history/status;
- new V1 run state is local.

### cfg.LinksPageInstanceApplication

**Current rows:** 12.

Contains:
- `InstanceCode`
- `ApplicationCode`
- `IsPublished`
- `ModifiedAt`

This confirms the rename dependency identified in production.

## 14. Current central job/runtime state

Current system contains:
- `app.Job`
- `app.JobTarget`
- `app.JobLog` schema
- `app.WorkerState`
- `app.ActionRuntimePolicy`
- richer later runtime/operation tables.

The sync intentionally excludes **app.JobLog data**, even though its schema is present.

V1 classification: **DO NOT MIRROR AS ACTIVE CONTROL STATE**.

Equivalent V1 concepts are local:
- Operation
- OperationTarget
- OperationLog
- lock/lease state
- local session/process state.

## 15. Snapshot contract requirements derived from the real payload

The future V1 snapshot must not simply ingest every current ManagementSync table.

It needs an explicit safe contract containing only the central policy required for local execution.

At minimum the snapshot manifest must include:
- contract/schema version;
- snapshot ID;
- generation timestamp UTC;
- source identity;
- per-entity counts;
- per-entity/content hashes;
- compatibility version;
- target/machine applicability information.

Activation:
1. download/read into staging;
2. validate schema, counts, hashes and required relationships;
3. reject secret-bearing/unapproved entities;
4. atomically activate only after complete validation;
5. keep previous valid snapshot on failure.

## 16. First-run behavior

Without a valid trusted snapshot, an empty local SQLite database must never mean "there are zero environments".

The application remains in **INITIAL SETUP** and exposes only:
- machine identity/public-key bootstrap;
- central connection/sync configuration;
- connectivity diagnostics;
- initial sync;
- logs/about.

Operational execution remains blocked until a trusted central snapshot is active.

## 17. Remaining open work after full sync analysis

The sync payload eliminates most Phase 0 schema-discovery uncertainty.

Remaining items are mainly implementation/runtime questions for later phases:

- exact minimal V1 snapshot entity/column whitelist;
- snapshot transport mechanism;
- contract/version negotiation;
- whether some current SQL procedures should be represented as materialized policy rows or reimplemented as deterministic local resolvers;
- PowerShell 7/IIS/SQLite compatibility;
- private-key storage mechanism;
- central signing-key trust bootstrap.

These are not user decisions required before Phase 1.

## 18. Phase 0 acceptance

- Full sync schema/data payload has been inspected.
- Exact intentional data exclusions are known.
- Core schema and row counts are known.
- Core action/engine mappings are known.
- Stale adapter mappings are identified.
- Secret-bearing central data is explicitly excluded from generic V1 mirroring.
- Remaining uncertainties are runtime/contract-design issues, not artefacts of an unread sync file.
- No product code was created.
- Reference repository remained read-only.
