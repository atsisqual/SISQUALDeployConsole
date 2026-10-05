# Phase 0 - Engine Porting Matrix

**Status:** Phase 0 diagnostic, corrected using the full 2026-10-04 central sync payload  
**Target:** SISQUALDeployConsole V1  
**Reference repository:** `atsisqual/SISQUALManagementConsole` read-only  
**Reference sync snapshot:** `master` @ `1e38c8ed860615c4039ea2ec870f245102943ae4`  
**V1 authoring policy:** central configuration is read-only; execution is local.

## Status vocabulary

- **[CONFIRMED-CODE]** demonstrated by reference code or the analysed sync payload.
- **[CONFIRMED-PRODUCTION]** demonstrated by production handoff.
- **[INFERRED]** reasonable mapping not yet proven end-to-end.
- **[PENDING]** evidence/decision still required.
- **[V]** must be validated on Windows/SISQUAL in a later phase.

## Porting principle

"Port" means preserve operational behavior and safety contracts while moving execution into local versioned PowerShell modules.

It does **not** mean continuing to execute mutable `ops.Engine.ScriptText` from central SQL in V1.

Every mutable V1 engine must eventually have:

- deterministic preview where technically possible;
- structured local result;
- explicit target scope;
- idempotency expectations;
- backup/rollback evidence where mutation is destructive;
- secret-safe logs;
- no dependency on Pode;
- no central writeback.

## Exact current engine catalogue for V1 scope

The analysed sync contains the following exact engine metadata.

| Engine | Source | Version | Min PS | Admin | Current action mapping |
|---|---|---:|---:|---:|---|
| `DEPLOYMENT_PREFLIGHT` | `Invoke-DeploymentPreflight.ps1` | 1.0 | 5.1 | No | `DEPLOYMENT_PREFLIGHT -> DEPLOYMENT_PREFLIGHT` |
| `PULSE_STATUS` | `Invoke-SISQUALPulseStatus.ps1` | v2 | 5.1 | Yes | `PULSE_STATUS -> PULSE_STATUS` |
| `CONFIG_REPAIR` | `Invoke-ConfigRepair.ps1` | 15.0 | 5.1 | Yes | `CONFIG_REPAIR -> CONFIG_REPAIR` |
| `DATABASE_CONTENT_SYNC` | `DATABASE_CONTENT_SYNC.ps1` | v4 | 5.1 | Yes | `DATABASE_SETTINGS -> DATABASE_CONTENT_SYNC` |
| `MANAGED_ASSETS` | `Invoke-ManagedAssets.ps1` | 1.0 | 5.1 | Yes | `MANAGED_ASSETS -> MANAGED_ASSETS` |
| `IIS_RECONCILE` | `Invoke-IISReconciliation.ps1` | 16.3 | 5.1 | Yes | `IIS_RECONCILE -> IIS_RECONCILE` |
| `WINDOWS_SERVICES` | `Invoke-WindowsServiceReconciliation.ps1` | 2.0 | 5.1 | Yes | `WINDOWS_SERVICES -> WINDOWS_SERVICES` |
| `V8_KEYCLOAK_PREREQUISITES` | `V8_KEYCLOAK_PREREQUISITES.ps1` | v7 | 5.1 | Yes | `V8_KEYCLOAK_PREREQUISITES -> V8_KEYCLOAK_PREREQUISITES` |
| `V8_KEYCLOAK_SERVICE` | `V8_KEYCLOAK_SERVICE.ps1` | v5 | 5.1 | Yes | `V8_KEYCLOAK_SERVICE -> V8_KEYCLOAK_SERVICE` |
| `KEYCLOAK_CLIENT_SECRETS` | `KEYCLOAK_CLIENT_SECRETS.ps1` | v1 | 5.1 | Yes | `KEYCLOAK_CLIENT_SECRETS -> KEYCLOAK_CLIENT_SECRETS` |
| `WEB_ACCESS` | `Invoke-WebAccessDeployment.ps1` | 5.0 | 5.1 | Yes | `WEB_ACCESS -> WEB_ACCESS` |
| `LINKS_PAGES` | `Invoke-LinksPageDeployment.ps1` | 7.1 | 5.1 | Yes | `LINKS_PAGES -> LINKS_PAGES` |

All listed engine rows are enabled in the analysed snapshot.

## Core V1 engines

### DEPLOYMENT_PREFLIGHT

**[CONFIRMED-CODE] Current SQL dependencies**
- `cfg.GetWindowsServiceDeploymentPlan`
- `ops.GetDeploymentPreflightFilePlan`
- `ops.GetReviewPlan`

**[CONFIRMED-CODE] Current behavior**
- read-only preflight engine metadata;
- does not require Administrator according to `ops.Engine`;
- action mode is `NONE`;
- requires instance selection and supports all enabled instances.

**V1 direction**
- local diagnostic module reading cached central policy plus live local machine state;
- no mutations;
- structured results: READY / WARNING / MISSING / INCOMPATIBLE / UNREACHABLE.

**[PENDING]**
- PowerShell 7 behavior for all prerequisite probes is a Phase 1/real-environment concern, not a schema-discovery gap.

### PULSE_STATUS

**[CONFIRMED-CODE] Current dependencies**
- procedures:
  - `cfg.GetPulseCheckPlan`
  - `cfg.GetPulseDeploymentPlan`
  - `cfg.GetPulseResourcePlan`
  - `cfg.GetWebsiteBrandingAssetPlan`
  - `cfg.GetWebsiteBrandingPlan`
  - `cfg.ReviewPulseModel`
  - `cfg.ReviewWebsiteBrandingModel`
  - `ops.GetPulseStatusSnapshot`
  - `ops.RecordPulseRun`
- tables directly referenced:
  - `cfg.PulseProfile`
  - `dbo.ManagedInstance`
  - `dbo.ManagedServer`

**[CONFIRMED-CODE]** The current central snapshot contains:
- 4 `cfg.PulseProfile` rows;
- 132 `ops.PulseCheckState` rows.

**[CONFIRMED-CODE]** Current engine behavior can persist pulse-run/state centrally through `ops.RecordPulseRun`.

**V1 direction**
- probes execute locally;
- historical/result state is local SQLite only;
- no V1 central writes;
- synchronized central pulse policy remains authoritative.

This is now a confirmed behavioral change from current architecture rather than a pending discovery item.

### CONFIG_REPAIR

**[CONFIRMED-CODE] Current dependencies**
- `cfg.GetLocalManagementContext`
- `cfg.GetRepairPlan`
- `cfg.ReviewRepairModel`
- filesystem/registry/SQL;
- backup/report output.

**[CONFIRMED-CODE] Current rule data**
- 41 config files: 17 JSON / 21 XML / 3 TEXT;
- 417 rules;
- selector types:
  - JSON_VALUE 242
  - XML_TEXT 99
  - XML_ATTRIBUTE 37
  - XML_NODES_ALL 29
  - TEXT_REGEX 10
- all current repair actions: `SET_VALUE`;
- repair value types:
  - STRING 350
  - BOOLEAN 53
  - INTEGER 14.

**V1 direction**

```text
cached central rules
  -> local resolver
  -> normalized plan
  -> preview
  -> backup
  -> apply
  -> verify
  -> structured result
```

The port must preserve encoding and must fail if an expected mutation does not actually occur.

### DATABASE_CONTENT_SYNC

**[CONFIRMED-CODE] Current dependencies**
- `cfg.DatabaseObjectSettingRule`
- `dbo.ManagedInstance`
- `dbo.ManagedServer`
- direct SQL connections.

**[CONFIRMED-CODE] Current rule data**
- 61 rules;
- all current rows are `FULL_REPLACE`;
- 14 have `CreateIfMissing=1`.

**[CONFIRMED-PRODUCTION]** `SUBSTRING_REPLACE` remains a known supported production capability even though it is not represented by a current row in this snapshot.

**[CONFIRMED-CODE] Exact action relationship**

```text
ActionCode  = DATABASE_SETTINGS
EngineCode  = DATABASE_CONTENT_SYNC
ModePolicy  = PREVIEW_APPLY
Enabled     = 1
```

**[CONFIRMED-CODE]** There is no current `ops.Action` named `SETTINGS_SYNC`.

**[CONFIRMED-SYNC] Legacy engine retained but unused by the current action catalogue**

`ops.Engine` still contains an enabled legacy engine row:

```text
EngineCode            = DATABASE_SETTINGS
SourceFileName        = Invoke-DatabaseSettings.ps1
EngineVersion         = 1.0
MinimumPowerShell     = 5.1
RequiresAdministrator = 0
IsEnabled             = 1
```

The current `ops.Action` row with `ActionCode = DATABASE_SETTINGS` does **not** reference that legacy engine; its `EngineCode` is `DATABASE_CONTENT_SYNC`. Therefore `DATABASE_SETTINGS` is simultaneously a current **action code** and a retained **legacy engine code**, but only `DATABASE_CONTENT_SYNC` is the effective engine for that action.

**V1 direction**
- direct `SqlConnection`;
- allowlisted/structured table/column/filter metadata;
- parameterized values;
- preview old/new values;
- affected-row expectations;
- no linked-server execution;
- no arbitrary SQL supplied by REST/UI.

### MANAGED_ASSETS

**[CONFIRMED-CODE] Current SQL dependencies**
- `cfg.GetManagedAssetPlan`
- `ops.GetConsoleBootstrap`

**[CONFIRMED-CODE] Current behavior**
- filesystem mutation;
- backup-related logic present;
- action is PREVIEW/APPLY.

**V1 direction**
- local asset reconciliation from synchronized policy;
- hash verification;
- desired/actual diff before write.

**[PENDING]**
- filesystem behavior remains subject to Windows validation, not schema discovery.

### IIS_RECONCILE

**[CONFIRMED-CODE] Current SQL dependencies**
- `cfg.GetIisApplicationAutoStartPlan`
- `cfg.GetIisDeploymentPlan`
- `cfg.GetIisServiceAutoStartProviderPlan`
- `cfg.GetLocalManagementContext`
- `cfg.ReviewIisDeploymentModel`

**[CONFIRMED-CODE] Current platform dependencies**
- `WebAdministration`;
- IIS provider/site/application-pool/binding operations;
- Windows services;
- registry;
- filesystem;
- credential material.

**V1 direction**
- local IIS desired-vs-actual engine;
- machine/instance ownership checks;
- explicit preview;
- controlled Apply;
- post-apply verification.

**[V]**
- PowerShell 7 + WebAdministration compatibility;
- IIS/SNI/binding behavior on target Windows versions.

### WINDOWS_SERVICES

**[CONFIRMED-CODE] Current SQL dependency**
- `cfg.GetWindowsServiceDeploymentPlan`.

**[CONFIRMED-CODE] Current platform dependencies**
- Windows services;
- CIM;
- registry;
- filesystem;
- credentials.

**[CONFIRMED-CODE]** Current `cfg.WindowsServiceDefinition` has one enabled required definition:
- `ServiceCode = WFM_MOBILE_APP`
- `ServiceNameTemplate = sisqualWFMMobileAppService - {HOST_NAME}`.

**[CONFIRMED-CODE] Exact action relationship**

```text
ActionCode = WINDOWS_SERVICES
EngineCode = WINDOWS_SERVICES
ModePolicy = PREVIEW_APPLY
Enabled    = 1
```

There is no current `ops.Action` named `SERVICE_RECONCILE`.

**V1 direction**
- definition -> discovery -> diff -> apply -> verification;
- protected-management-service denylist;
- no service operation without environment ownership proof.

### V8_KEYCLOAK_PREREQUISITES

**[CONFIRMED-CODE] Current behavior**
- filesystem checks;
- NSSM checks;
- backup-related paths;
- no direct central SQL object dependency detected in the engine script itself beyond common invocation context.

**V1 direction**
- local prerequisite detector/reconciler;
- no hidden installation assumptions.

**[V]**
- exact Java/NSSM/runtime behavior on supported servers.

### V8_KEYCLOAK_SERVICE

**[CONFIRMED-CODE] Current dependencies**
- `app.GetManagedCredentialRuntime`
- `dbo.ManagedInstance`
- `dbo.ManagedServer`
- Windows services/CIM;
- registry;
- HTTP health/OpenID probe;
- NSSM;
- credential material.

**V1 direction**
- consume credentials from the approved local credential-envelope mechanism;
- never call the current central decrypted-credential runtime procedure;
- validate target-specific ports/URLs/client state after service reconciliation.

**[V]**
- NSSM/Java/HTTP behavior on real servers.

### KEYCLOAK_CLIENT_SECRETS

**[CONFIRMED-CODE] Current dependencies**
- `cfg.ConfigRule`
- `cfg.KeycloakClientSecretRule`
- target application table `dbo.CLIENT`
- `dbo.ManagedInstance`
- `dbo.ManagedServer`.

**[CONFIRMED-CODE]** Current central snapshot contains 8 `cfg.KeycloakClientSecretRule` rows.

**V1 direction**
- local credential envelope is authoritative for transported secret material;
- synchronized non-secret rule metadata can remain central;
- no secret plaintext in logs/SQLite/general sync.

### WEB_ACCESS

**[CONFIRMED-CODE] Current SQL dependencies**
- `cfg.GetLocalManagementContext`
- `cfg.GetWebAccessDeploymentPlan`
- `cfg.ReviewWebAccessModel`

**[CONFIRMED-CODE] Current platform dependencies**
- registry;
- filesystem;
- HTTP;
- IIS-related functions;
- credential material.

**V1 direction**
- local module;
- explicit shared-controller/resource locking;
- no assumption that Web Access operations are isolated per environment.

### LINKS_PAGES

**[CONFIRMED-CODE] Current SQL dependencies**
- `cfg.GetLinksPageDeploymentPlan`
- `cfg.GetLinksPageItemPlan`
- `cfg.GetLinksPagePresentationResourcePlan`
- `cfg.GetLinksPageResourcePlan`
- `cfg.GetWebsiteBrandingAssetPlan`
- `cfg.GetWebsiteBrandingPlan`
- `cfg.ReviewLinksPageModel`
- `cfg.ReviewLinksPagePresentationResources`
- `cfg.ReviewLinksPageQrCodes`
- `cfg.ReviewWebsiteBrandingModel`
- `cfg.SyncLinksPageInstanceApplications`

**[CONFIRMED-CODE]** Current implementation can write central link-instance application assignments through `cfg.SyncLinksPageInstanceApplications`.

**V1 direction**
- no central writeback;
- local rendering/reconciliation from synchronized authoritative link/profile policy;
- any currently write-producing central resolution must be converted to read-only deterministic resolution or local derived state.

## FULL_DEPLOYMENT exact composition

**[CONFIRMED-CODE]** The analysed snapshot contains 13 `ops.ActionStep` rows for `FULL_DEPLOYMENT`; 12 are enabled.

| Order | Child action | Phase | Enabled |
|---:|---|---|---:|
| 10 | DEPLOYMENT_PREFLIGHT | PREFLIGHT | 1 |
| 12 | V8_KEYCLOAK_PREREQUISITES | PREFLIGHT | 1 |
| 20 | CONFIG_REPAIR | EXECUTION | 1 |
| 30 | DATABASE_SETTINGS | EXECUTION | 1 |
| 40 | MANAGED_ASSETS | EXECUTION | 1 |
| 50 | IIS_RECONCILE | EXECUTION | 1 |
| 60 | WINDOWS_SERVICES | EXECUTION | 1 |
| 63 | V8_KEYCLOAK_CONFIG | EXECUTION | 0 |
| 64 | KEYCLOAK_CLIENT_SECRETS | EXECUTION | 1 |
| 65 | V8_KEYCLOAK_SERVICE | EXECUTION | 1 |
| 70 | WEB_ACCESS | EXECUTION | 1 |
| 75 | PULSE_STATUS | EXECUTION | 1 |
| 80 | LINKS_PAGES | EXECUTION | 1 |

**Approved V1 direction:** `FULL_DEPLOYMENT` becomes orchestration over validated local engines, not a monolithic engine.

## Action/adaptor inconsistency resolved

The previous Phase 0 matrix left these names pending:

| Surface | Current executable catalogue | Current adapter metadata | Conclusion |
|---|---|---|---|
| Database settings | `DATABASE_SETTINGS -> DATABASE_CONTENT_SYNC` | `DATABASE_SETTING -> SETTINGS_SYNC` | Adapter metadata is stale/inconsistent; `SETTINGS_SYNC` is not a current action |
| Windows services | `WINDOWS_SERVICES -> WINDOWS_SERVICES` | `WINDOWS_SERVICE -> SERVICE_RECONCILE` | Adapter metadata is stale/inconsistent; `SERVICE_RECONCILE` is not a current action |

These are now **[CONFIRMED-CODE]**, not `[PENDING]`.

The V1 port must use the executable action/engine contracts and must not invent aliases merely to preserve stale Configuration Studio metadata.

## Current Worker behavior worth preserving as contracts

### Non-interactive execution

**[CONFIRMED-CODE]** The current Worker parses engine AST and rejects interactive commands.

V1 should retain equivalent static tests for shipped local modules.

### Integrity

**[CONFIRMED-CODE]** Current engine rows include `ScriptSha256`.

V1 local modules should use release/package integrity rather than mutable central SQL script text as runtime authority.

### Target isolation

**[CONFIRMED-CODE]** Current job creation rejects disabled, unknown or foreign-machine targets.

V1 must preserve this invariant.

### Preview/apply

**[CONFIRMED-CODE]** All mutable core actions in the current catalogue use `PREVIEW_APPLY`, except `DEPLOYMENT_PREFLIGHT` which uses `NONE`.

Apply should consume the same normalized plan/fingerprint when feasible.

## Capabilities discovered but not automatically in V1 scope

The current sync also contains enabled or historical capabilities such as:

- DATABASE_COPY
- ENVIRONMENT_STATE_PROBE
- LINKS_VISIBILITY
- MODEL_REVIEW
- STORAGE_SIZE_SCAN
- V8_KEYCLOAK_CONFIG
- additional SQL/composite actions.

Their existence is inventory evidence only. V1 scope is unchanged unless explicitly expanded.

## Phase 0 classification result

- All handoff engines are classified against their actual current `ops.Engine` rows.
- Exact core engine source/version/minimum-PowerShell/admin metadata is known.
- Exact `FULL_DEPLOYMENT` step composition is known.
- Database-settings and Windows-service action-name ambiguity is resolved.
- Current central-write behavior in PULSE_STATUS and LINKS_PAGES is explicitly identified for removal/localization in V1.
- Remaining `[PENDING]` items are now primarily technical/runtime validation items rather than missing-sync-data items.
- No reference repository file was modified.
