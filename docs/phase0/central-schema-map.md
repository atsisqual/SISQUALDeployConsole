# Phase 0 — Central Schema Map

**Purpose:** identify the central-management data that SISQUALDeployConsole V1 must understand and classify it as central read-only mirror data, credential-delivery data, local-only state, or out-of-scope operational history.

**Snapshot inspected:** `database/sync/ManagementSync.sql`, generated 2026-10-04 02:00:01, commit `1e38c8ed860615c4039ea2ec870f245102943ae4`.

This is a logical inventory for V1 design. It is not SQLite DDL.

## 1. Snapshot evidence — corrected

The previous version incorrectly treated `ManagementSync.sql` as empty.

**[CONFIRMED-SNAPSHOT]** The actual Git blob is 29,516,382 bytes and contains a full generated synchronization script.

Programmatic inspection of the complete payload found:

- 68,763 lines;
- 117 table DDL definitions;
- 200 procedures;
- 5 functions;
- 6 views;
- 31,959 generated INSERT statements;
- 24 `ops.Action` rows;
- 19 `ops.Engine` rows;
- 13 `ops.ActionStep` rows.

The known designed data exclusions are:

- `app.JobLog`
- `app.HousekeepingArtifact`
- `dbo.DemoProfileImage`

Their DDL is present, but each has zero data INSERTs.

This snapshot is sufficient to resolve the current table schemas and most engine-policy dependencies that were previously marked pending.

## 2. Authority model for V1

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

Credential delivery is separate and offline; it is not normal cache synchronization.

## 3. Core central identity entities

### `dbo.ManagedServer`

**[CONFIRMED-SNAPSHOT]** Exact current columns:

- `ServerCode varchar(30)`
- `MachineName sysname`
- `ServicesRoot nvarchar(1000)`
- `IsEnabled bit`
- `CreatedAt datetime2`
- `ModifiedAt datetime2`
- `ConfigBackupRoot nvarchar(1000)`
- `ManagementDatabaseName sysname`

Primary key: `ServerCode`.

V1 classification: **CENTRAL MIRROR — REQUIRED**.

### `dbo.ManagedInstance`

**[CONFIRMED-SNAPSHOT]** Exact current columns:

- `InstanceCode varchar(20)`
- `ServerCode varchar(30)`
- `CountryCode char(2)`
- `CultureCode nvarchar(10)`
- `CustomerCode int`
- `CustomerName nvarchar(100)`
- `HostName sysname`
- `SqlInstanceName sysname`
- `LinkedServer sysname`
- `DatabaseName sysname`
- `ChannelID int`
- legacy `MobileAppToken nvarchar(255)`
- `IsEnabled bit`
- `Notes nvarchar(1000)`
- `CreatedAt` / `ModifiedAt`
- customer-logo binary/name/MIME/SHA/time metadata
- `IisIdentityUserName`
- legacy `IisIdentityPassword`
- `WebAccessUserName`
- legacy `WebAccessPassword`
- `WebAccessModifiedAt`
- `LinksIncludeAllInstances`
- `LinksAssignedUserName`
- `TsplusAdminToolPath`
- `TsplusWebControlEnabled`
- `KeycloakHttpPort`
- `KeycloakHttpsPort`
- `KeycloakManagementPort`

Primary key: `InstanceCode`.

The snapshot contains 76 rows. All three legacy plaintext secret columns are NULL in those generated rows.

V1 classification: **CENTRAL MIRROR — REQUIRED, SAFE-FIELD CONTRACT ONLY**.

## 4. Configuration repair entities

### `cfg.Application`

**[CONFIRMED-SNAPSHOT]**

- `ApplicationCode`
- `DisplayName`
- `FolderName`
- `IisPath`
- `PhysicalPathTemplate`
- `IsOptional`
- `IsEnabled`
- Links display/URL/icon/sort/publish/new-tab/default/hub fields

V1 classification: **CENTRAL MIRROR — REQUIRED**.

### `cfg.ConfigFile`

**[CONFIRMED-SNAPSHOT]**

- `FileID`
- `ApplicationCode`
- `RelativePath`
- `FileFormat`
- `IsRequired`
- `IsEnabled`

V1 classification: **CENTRAL MIRROR — REQUIRED**.

### `cfg.ConfigRule`

**[CONFIRMED-SNAPSHOT]**

- identity/file/country/rule/category fields;
- `SelectorType`, `Selector`;
- `ExpectedTemplate`;
- validation/required/encryption/sensitivity/severity fields;
- description/enablement/timestamps;
- `RepairAction`, `RepairValueType`, `RepairGroup`, `RepairOrder`;
- `CreateIfMissing`, `MissingParentSelector`, `MissingNodeTemplate`.

V1 classification: **CENTRAL MIRROR — REQUIRED**.

### `cfg.ConfigFileRepairPolicy`

**[CONFIRMED-SNAPSHOT]** This is also a transitive dependency of CONFIG_REPAIR and DEPLOYMENT_PREFLIGHT and therefore belongs in the V1 policy mirror if those procedures are replaced by local resolution.

## 5. Database setting entities

### `cfg.DatabaseObjectSettingRule`

**[CONFIRMED-SNAPSHOT]** Exact current columns:

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

The snapshot contains 61 data rows.

V1 classification: **CENTRAL MIRROR — REQUIRED** for DATABASE_CONTENT_SYNC.

Security invariant: browser/API clients never supply arbitrary SQL. Identifiers/predicate configuration comes only from the trusted synchronized model and is validated locally before execution.

## 6. Deployment/copy policy

### `cfg.ApplicationCopyPolicy`

**[CONFIRMED-SNAPSHOT]** Exact current columns:

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

The snapshot contains 22 data rows.

The previous “field list requires extraction” pending item is resolved.

V1 classification: **CENTRAL MIRROR WHEN CONSUMED BY AN APPROVED V1 DEPLOYMENT CAPABILITY**. Presence in the central model does not by itself expand V1 scope.

## 7. Engine-specific policy domains now confirmed

The stored engine scripts and the procedures included in the snapshot allow transitive dependency mapping.

### DEPLOYMENT_PREFLIGHT

Required current central model includes:
- `cfg.Application`
- `cfg.ConfigFile`
- `cfg.ConfigFileRepairPolicy`
- `cfg.ConfigRule`
- `cfg.WindowsServiceDefinition`
- `ops.ReviewDefinition`
- `dbo.ManagedInstance`
- `dbo.ManagedServer`

### CONFIG_REPAIR

- `cfg.Application`
- `cfg.ConfigFile`
- `cfg.ConfigFileRepairPolicy`
- `cfg.ConfigRule`
- server/instance identity

### DATABASE_CONTENT_SYNC

- `cfg.DatabaseObjectSettingRule`
- server/instance identity

### IIS_RECONCILE

- `cfg.IisApplicationAutoStartDefinition`
- `cfg.IisApplicationDefinition`
- `cfg.IisBindingDefinition`
- `cfg.IisDirectoryDefinition`
- `cfg.IisPrerequisiteDefinition`
- `cfg.IisServerPolicy`
- `cfg.IisServiceAutoStartProviderDefinition`
- server/instance identity

### WINDOWS_SERVICES

- `cfg.WindowsServiceDefinition`
- server/instance identity

### MANAGED_ASSETS

- `cfg.ManagedAssetDestination`
- `ops.ConsoleProfile`
- server/instance identity

### PULSE_STATUS

- `cfg.Application`
- `cfg.PulseHttpPolicy`
- `cfg.PulseProfile`
- `cfg.PulseResource`
- `cfg.WebsiteBrandingAsset`
- `cfg.WebsiteBrandingProfile`
- `ops.PulseCheckState`
- `ops.PulseRun`
- server/instance identity

### KE YCLOAK_CLIENT_SECRETS

- `cfg.ConfigRule`
- `cfg.KeycloakClientSecretRule`
- server/instance identity
- target application `dbo.CLIENT`

### V8_KEYCLOAK_SERVICE

- server/instance identity
- current credential-runtime access

### V8_KEYCLOAK_PREREQUISITES

The current stored script has no central SQL object references.

### WEB_ACCESS

- `cfg.IisApplicationDefinition`
- `cfg.IisServerPolicy`
- `cfg.WebAccessPolicy`
- `cfg.WebAccessTemplate`
- server/instance identity

### LINKS_PAGES

- `cfg.Application`
- `cfg.LinksPageAsset`
- `cfg.LinksPageInstanceApplication`
- `cfg.LinksPagePolicy`
- `cfg.LinksPagePresentationResource`
- `cfg.LinksPageTemplate`
- `cfg.LinksProfileApplication`
- `cfg.LinksProfileInstance`
- `cfg.WebsiteBrandingAsset`
- `cfg.WebsiteBrandingProfile`
- server/instance identity

These are current-system dependencies, not an instruction to clone every central procedure into SQLite.

## 8. Action/engine catalogue

### `ops.Action`

**[CONFIRMED-SNAPSHOT]** Exact schema includes:

- `ActionCode`
- `GroupCode`
- `DisplayName`
- `Description`
- `ActionType`
- `EngineCode`
- `SqlCommand`
- `ModePolicy`
- instance-selection policy fields
- apply/instance passing flags
- confirmation/timeout/sort/menu/stop/error/enablement metadata
- `ModifiedAt`

V1 classification: **CENTRAL MIRROR — REQUIRED** if central action governance is retained.

### `ops.ActionStep`

**[CONFIRMED-SNAPSHOT]**

- `ParentActionCode`
- `StepOrder`
- `ChildActionCode`
- `StepPhase`
- `StopOnError`
- `IsEnabled`
- `ModifiedAt`

V1 classification: **CENTRAL MIRROR — REQUIRED** for composite orchestration.

### `ops.Engine`

**[CONFIRMED-SNAPSHOT]**

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

V1 classification: **MIGRATION/REFERENCE METADATA — NOT EXECUTABLE AUTHORITY**.

The local product may mirror safe metadata such as code/version/hash for diagnostics, but central `ScriptText` must not replace local shipped modules at runtime.

## 9. Adapter drift confirmed

`cfg.ConfigurationAdapterDefinition` still contains:

- `DATABASE_SETTING -> SETTINGS_SYNC`
- `WINDOWS_SERVICE -> SERVICE_RECONCILE`

Neither `SETTINGS_SYNC` nor `SERVICE_RECONCILE` exists in the current `ops.Action` or `ops.Engine` catalogue.

Current execution uses:

- `DATABASE_SETTINGS -> DATABASE_CONTENT_SYNC`
- `WINDOWS_SERVICES -> WINDOWS_SERVICES`

V1 must include referential/contract validation for catalogue data and must not treat the adapter ActionCode field as authoritative without resolution.

## 10. Credential entities and sync behavior

### `sec.ManagedCredential`

**[CONFIRMED-SNAPSHOT]** Exact current schema includes:

- `InstanceCode`
- `CredentialType`
- `SecretCipher varbinary(max)`
- `SecretVersion`
- rotation/modification metadata
- row version

The current generated sync contains **191 encrypted credential rows** and **384 credential-audit rows**.

This means the existing nightly payload synchronizes the encrypted vault data even though decryption portability still depends on the SQL certificate/key material.

V1 classification: **EXCLUDE SECRET CIPHERTEXT FROM NORMAL LOCAL CACHE AUTHORITY**.

The new credential-envelope mechanism is independent of this current SQL vault.

### `cfg.ManagedInstanceRuntime`

Current view joins instance data with decrypted credential values.

V1 classification: **DO NOT SYNC/REPRODUCE AS A GENERIC VIEW**.

Local engines that require a secret obtain it only through the approved local credential service/envelope.

## 11. Current central runtime state

The current snapshot contains central Worker/job/governance state such as:

- `app.Job`
- `app.JobTarget`
- `app.JobStep`
- `app.WorkerState`
- `app.ActionRuntimePolicy`
- approval/schedule/operation tables
- pulse run state

These exist for the central .NET/Worker platform.

V1 classification: **DO NOT MIRROR AS ACTIVE CONTROL STATE** unless a specific read-only diagnostic requirement is later approved.

Equivalent DeployConsole runtime concepts are local-only.

## 12. Known rename/dependency surfaces

**[CONFIRMED-PRODUCTION/SNAPSHOT]** `InstanceCode` participates in at least:

- `sec.ManagedCredential`
- `cfg.LinksPageInstanceApplication`
- `ops.PulseCheckState`
- multiple newer link/profile and operational-state entities

Therefore rename planning must perform dependency discovery. V1 cannot author a central rename because central authoring is explicitly out of scope.

## 13. Initial V1 mirror domain derived from actual engine dependencies

The precise column-level SQLite contract remains a design task, but the candidate central domains are no longer speculative.

At minimum:

```text
dbo.ManagedServer
dbo.ManagedInstance (safe fields only)

cfg.Application
cfg.ConfigFile
cfg.ConfigFileRepairPolicy
cfg.ConfigRule
cfg.DatabaseObjectSettingRule
cfg.WindowsServiceDefinition
cfg.ManagedAssetDestination

cfg.IisApplicationAutoStartDefinition
cfg.IisApplicationDefinition
cfg.IisBindingDefinition
cfg.IisDirectoryDefinition
cfg.IisPrerequisiteDefinition
cfg.IisServerPolicy
cfg.IisServiceAutoStartProviderDefinition

cfg.KeycloakClientSecretRule

cfg.PulseHttpPolicy
cfg.PulseProfile
cfg.PulseResource

cfg.WebAccessPolicy
cfg.WebAccessTemplate

cfg.LinksPageAsset
cfg.LinksPageInstanceApplication
cfg.LinksPagePolicy
cfg.LinksPagePresentationResource
cfg.LinksPageTemplate
cfg.LinksProfileApplication
cfg.LinksProfileInstance

cfg.WebsiteBrandingAsset
cfg.WebsiteBrandingProfile

ops.ReviewDefinition
ops.ConsoleProfile
ops.Action
ops.ActionStep
safe ops.Engine metadata
```

This list is to be normalized during architecture/contract work; it is not a mandate to mirror current SQL schema one-for-one.

## 14. Explicit exclusions from generic local snapshot authority

```text
plaintext/decrypted secrets
sec.ManagedCredential.SecretCipher as usable local credential authority
SQL master keys/certificates/symmetric keys
central Worker queue ownership
central approval/schedule state not required by V1
ops.Engine.ScriptText as executable runtime authority
temporary SQL session state
```

## 15. Snapshot contract requirements

The future local sync contract must include:

- contract/schema version;
- snapshot ID;
- generation timestamp UTC;
- source identity;
- entity counts;
- content hashes;
- compatibility version;
- target/server identity constraints.

Activation occurs only after complete staging validation. Failure leaves the previous trusted snapshot active.

## 16. Remaining schema work

Still **[PENDING]** by design/implementation, not because the central schema is missing:

- exact SQLite column subset and normalization;
- schema/version negotiation;
- exact safe `ops.Engine` metadata subset;
- direct-SQL vs exported-snapshot transport;
- delta vs full snapshot strategy, if any;
- local migration/retention strategy.

Resolved by the full sync inspection:

- principal central table schemas;
- core engine script availability;
- engine/action aliases;
- FULL_DEPLOYMENT composition;
- engine-specific policy-table dependencies.

## 17. Phase 0 acceptance

- Full sync payload reviewed programmatically.
- Core central objects and exact key schemas mapped.
- Central-authoritative vs local-only state explicit.
- Current encrypted credential rows identified and excluded from V1 credential authority.
- Stale adapter references identified.
- Remaining pending items are genuine V1 design/spike work, not missing Phase 0 evidence.
