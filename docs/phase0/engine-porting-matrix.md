# Phase 0 — Engine Porting Matrix

**Status:** Phase 0 diagnostic — corrected after full sync-payload inspection  
**Target:** SISQUALDeployConsole V1  
**Reference repository:** `atsisqual/SISQUALManagementConsole` read-only  
**Snapshot inspected:** generated 2026-10-04 02:00:01, commit `1e38c8ed860615c4039ea2ec870f245102943ae4`  
**V1 authoring policy:** central configuration is read-only; execution is local.

## Status vocabulary

- **[CONFIRMED-CODE]** demonstrated by normal versioned source.
- **[CONFIRMED-SNAPSHOT]** demonstrated by the generated ManagementSync payload.
- **[CONFIRMED-PRODUCTION]** demonstrated by the production handoff.
- **[INFERRED]** reasonable mapping not yet proven end-to-end.
- **[PENDING]** evidence/decision still required.
- **[V]** must be validated on Windows/SISQUAL in a later phase.

## Porting principle

“Port” means preserve operational behavior and safety contracts while moving execution into local PowerShell modules. It does **not** mean copying current SQL-stored scripts verbatim.

The full snapshot means the current engine scripts are now available as migration evidence. V1 still treats local versioned modules as executable authority.

## 1. Exact active engine/action inventory

| V1 capability | Active ActionCode | Active EngineCode | Current engine | Admin | Confirmed central dependencies | Remaining V1 blocker |
|---|---|---|---|---:|---|---|
| `DEPLOYMENT_PREFLIGHT` | `DEPLOYMENT_PREFLIGHT` | `DEPLOYMENT_PREFLIGHT` | `Invoke-DeploymentPreflight.ps1` v1.0 | No | `cfg.GetWindowsServiceDeploymentPlan`, `ops.GetDeploymentPreflightFilePlan`, `ops.GetReviewPlan`; underlying Application/Config/WindowsService/ReviewDefinition/server/instance model | PowerShell 7 + local resolver parity [V] |
| `PULSE_STATUS` | `PULSE_STATUS` | `PULSE_STATUS` | `Invoke-SISQUALPulseStatus.ps1` v2 | Yes | PulseProfile/HttpPolicy/Resource, WebsiteBranding, ManagedInstance/Server, PulseRun/PulseCheckState; current `ops.RecordPulseRun` persistence | Replace central writeback with local operational state; runtime validation [V] |
| `CONFIG_REPAIR` | `CONFIG_REPAIR` | `CONFIG_REPAIR` | `Invoke-ConfigRepair.ps1` v15.0 | Yes | Application, ConfigFile, ConfigFileRepairPolicy, ConfigRule, ManagedInstance/Server; `cfg.GetRepairPlan`, `cfg.ReviewRepairModel` | Preserve encoding/parser/backup semantics; PS7 [V] |
| `DATABASE_CONTENT_SYNC` | `DATABASE_SETTINGS` | `DATABASE_CONTENT_SYNC` | `DATABASE_CONTENT_SYNC.ps1` v4 | Yes | DatabaseObjectSettingRule, ManagedInstance/Server, `cfg.ExpandTemplate`; direct SqlConnection | Convert trusted central rule model to local contract; target-DB validation [V] |
| `MANAGED_ASSETS` | `MANAGED_ASSETS` | `MANAGED_ASSETS` | `Invoke-ManagedAssets.ps1` v1.0 | Yes | ManagedAssetDestination, ManagedInstance/Server, ConsoleProfile; `cfg.GetManagedAssetPlan` | Local asset/package source contract and filesystem validation [V] |
| `IIS_RECONCILE` | `IIS_RECONCILE` | `IIS_RECONCILE` | `Invoke-IISReconciliation.ps1` v16.3 | Yes | IIS application/binding/directory/prerequisite/server/autostart definitions; ManagedInstance/Server | PowerShell 7 + WebAdministration/netsh compatibility [V] |
| `WINDOWS_SERVICES` | `WINDOWS_SERVICES` | `WINDOWS_SERVICES` | `Invoke-WindowsServiceReconciliation.ps1` v2.0 | Yes | WindowsServiceDefinition, ManagedInstance/Server; `cfg.GetWindowsServiceDeploymentPlan` | Windows service/CIM compatibility and credential handoff [V] |
| `V8_KEYCLOAK_PREREQUISITES` | `V8_KEYCLOAK_PREREQUISITES` | same | `V8_KEYCLOAK_PREREQUISITES.ps1` v7 | Yes | No central SQL object references in current engine | Portable runtime/filesystem/Java assumptions [V] |
| `V8_KEYCLOAK_SERVICE` | `V8_KEYCLOAK_SERVICE` | same | `V8_KEYCLOAK_SERVICE.ps1` v5 | Yes | ManagedInstance/Server + current credential runtime | Replace old credential-runtime dependency; service/HTTP health validation [V] |
| `KEYCLOAK_CLIENT_SECRETS` | `KEYCLOAK_CLIENT_SECRETS` | same | `KEYCLOAK_CLIENT_SECRETS.ps1` v1 | Yes | ConfigRule, KeycloakClientSecretRule, ManagedInstance/Server, target `dbo.CLIENT` | New offline envelope + redaction/idempotency; Keycloak DB/interface validation [V] |
| `WEB_ACCESS` | `WEB_ACCESS` | `WEB_ACCESS` | `Invoke-WebAccessDeployment.ps1` v5.0 | Yes | WebAccessPolicy/Template, IIS policy/definition, ManagedInstance/Server | TSplus/WebAdministration/shared-resource behavior [V] |
| `LINKS_PAGES` | `LINKS_PAGES` | `LINKS_PAGES` | `Invoke-LinksPageDeployment.ps1` v7.1 | Yes | Application, LinksPage*, LinksProfile*, WebsiteBranding*, ManagedInstance/Server | Preserve profile/override resolution while removing central writeback [V] |

All listed engines declare minimum PowerShell `5.1` in the current snapshot.

## 2. Alias ambiguity — resolved

The original Phase 0 matrix left two naming relationships pending. The snapshot resolves them.

### Database settings

**[CONFIRMED-SNAPSHOT]**

```text
cfg.ConfigurationAdapterDefinition
  DATABASE_SETTING -> ActionCode SETTINGS_SYNC   # stale metadata

ops.Action
  DATABASE_SETTINGS -> EngineCode DATABASE_CONTENT_SYNC

ops.Engine
  DATABASE_CONTENT_SYNC -> DATABASE_CONTENT_SYNC.ps1 v4
```

There is **no** `ops.Action` named `SETTINGS_SYNC` and **no** `ops.Engine` named `SETTINGS_SYNC`.

There is also an enabled `ops.Engine` entry named `DATABASE_SETTINGS` (`Invoke-DatabaseSettings.ps1` v1.0), but the active `DATABASE_SETTINGS` action does not reference it. It is therefore not the current execution target and must not be selected for V1 merely because it exists in the catalogue.

### Windows services

**[CONFIRMED-SNAPSHOT]**

```text
cfg.ConfigurationAdapterDefinition
  WINDOWS_SERVICE -> ActionCode SERVICE_RECONCILE   # stale metadata

ops.Action
  WINDOWS_SERVICES -> EngineCode WINDOWS_SERVICES

ops.Engine
  WINDOWS_SERVICES -> Invoke-WindowsServiceReconciliation.ps1 v2.0
```

There is **no** `ops.Action` or `ops.Engine` named `SERVICE_RECONCILE`.

**Porting rule:** for current execution semantics, `ops.Action` + `ops.Engine` are authoritative over stale adapter ActionCode metadata.

## 3. Exact FULL_DEPLOYMENT composition

**[CONFIRMED-SNAPSHOT]** `ops.ActionStep` contains 13 rows for `FULL_DEPLOYMENT`: 12 enabled and one disabled.

| Order | Phase | Child action | Enabled |
|---:|---|---|---:|
| 10 | PREFLIGHT | DEPLOYMENT_PREFLIGHT | 1 |
| 12 | PREFLIGHT | V8_KEYCLOAK_PREREQUISITES | 1 |
| 20 | EXECUTION | CONFIG_REPAIR | 1 |
| 30 | EXECUTION | DATABASE_SETTINGS | 1 |
| 40 | EXECUTION | MANAGED_ASSETS | 1 |
| 50 | EXECUTION | IIS_RECONCILE | 1 |
| 60 | EXECUTION | WINDOWS_SERVICES | 1 |
| 63 | EXECUTION | V8_KEYCLOAK_CONFIG | **0** |
| 64 | EXECUTION | KEYCLOAK_CLIENT_SECRETS | 1 |
| 65 | EXECUTION | V8_KEYCLOAK_SERVICE | 1 |
| 70 | EXECUTION | WEB_ACCESS | 1 |
| 75 | EXECUTION | PULSE_STATUS | 1 |
| 80 | EXECUTION | LINKS_PAGES | 1 |

All rows have `StopOnError=1`.

The previous description “approximately twelve steps” is now replaced by the exact current contract.

**Approved V1 direction:** do not port FULL_DEPLOYMENT as a monolithic script. Reconstruct it as orchestration over validated local modules using the centrally synchronized action-step contract or a normalized equivalent.

## 4. Current Worker behavior worth preserving

### Non-interactive execution

**[CONFIRMED-CODE]** The current Worker parses engine AST and rejects interactive commands. V1 should retain an equivalent static gate for shipped local modules.

### Integrity

**[CONFIRMED-CODE/SNAPSHOT]** Current execution uses `ScriptSha256`; every snapshot engine has a stored SHA-256.

**Approved V1 direction:** local modules use release/package integrity, not mutable SQL `ScriptText` as runtime authority.

### Target isolation

**[CONFIRMED-CODE]** Current job creation rejects disabled, unknown or foreign-machine targets.

V1 must preserve this invariant.

### Preview/apply

**[CONFIRMED-SNAPSHOT]** All core mutable actions use `PREVIEW_APPLY`. `DEPLOYMENT_PREFLIGHT` uses `NONE`.

`PULSE_STATUS` also currently has `PREVIEW_APPLY`, because the existing engine records operational state. V1 should separate probing from local result persistence rather than write pulse state to central SQL.

## 5. Engine-specific port notes

### DEPLOYMENT_PREFLIGHT

The exact stored script is now available, so “script unavailable” is no longer pending.

Its current transitive central model includes:
- `cfg.Application`
- `cfg.ConfigFile`
- `cfg.ConfigFileRepairPolicy`
- `cfg.ConfigRule`
- `cfg.WindowsServiceDefinition`
- `ops.ReviewDefinition`
- `dbo.ManagedInstance`
- `dbo.ManagedServer`

Remaining work is conversion of the SQL procedures into a local read model and validation of runtime behavior under PowerShell 7.

### PULSE_STATUS

The exact stored script and current pulse persistence model are now known.

Current central tables include:
- `cfg.PulseProfile`
- `cfg.PulseHttpPolicy`
- `cfg.PulseResource`
- `ops.PulseRun`
- `ops.PulseCheckState`
- WebsiteBranding tables
- server/instance catalogues

V1 must not call central `ops.RecordPulseRun`; equivalent state belongs to local SQLite.

### CONFIG_REPAIR

The rule schema and supporting policy tables are now available from the snapshot. Remaining uncertainty is implementation parity, not schema discovery.

Port decomposition remains:

```text
cached rules
  -> local rule resolver
  -> normalized repair plan
  -> preview
  -> backup
  -> apply
  -> verify
  -> structured result
```

### DATABASE_CONTENT_SYNC

The exact `DatabaseObjectSettingRule` schema and active action/engine mapping are resolved.

The V1 engine must still:
- connect directly to the target;
- parameterize values;
- validate identifiers/predicates from trusted configuration;
- never accept arbitrary SQL from REST/UI;
- preview old/new values and expected row counts.

### MANAGED_ASSETS

Exact current policy source is `cfg.ManagedAssetDestination` plus console/server/instance metadata. “Asset contract needs extraction” is resolved at the Phase 0 inventory level.

### IIS_RECONCILE

Current transitive policy tables are confirmed:

- `cfg.IisApplicationDefinition`
- `cfg.IisBindingDefinition`
- `cfg.IisDirectoryDefinition`
- `cfg.IisPrerequisiteDefinition`
- `cfg.IisServerPolicy`
- `cfg.IisApplicationAutoStartDefinition`
- `cfg.IisServiceAutoStartProviderDefinition`

The remaining blocker is real PowerShell 7/Windows validation, not discovery of the existing model.

### WINDOWS_SERVICES

Exact current policy source is `cfg.WindowsServiceDefinition`; the stored engine uses CIM/service cmdlets and `cfg.GetWindowsServiceDeploymentPlan`.

### Keycloak engines

The exact stored scripts are now available.

`V8_KEYCLOAK_PREREQUISITES` has no central SQL object dependency in its current script.

`V8_KEYCLOAK_SERVICE` depends on server/instance data and the current credential runtime.

`KEYCLOAK_CLIENT_SECRETS` depends on `cfg.KeycloakClientSecretRule`, `cfg.ConfigRule`, server/instance data and the target `dbo.CLIENT` model.

V1 must substitute the approved credential envelope for current credential runtime access.

### WEB_ACCESS

Exact current policy source includes `cfg.WebAccessPolicy`, `cfg.WebAccessTemplate`, IIS definitions and server/instance data.

### LINKS_PAGES

The snapshot confirms the current model includes LinksPage policy/assets/templates/presentation resources, LinksProfile mappings and WebsiteBranding profiles/assets.

## 6. Capabilities discovered but not automatically in V1 scope

The snapshot also contains other current engines/actions for Database Copy, Clone, Housekeeping, Environment operations, storage scanning and related features.

Their presence does not expand V1 scope.

## 7. Remaining [PENDING] items after full-snapshot review

The following remain genuinely pending, because the sync file cannot prove them:

- PowerShell 7 compatibility on the target Windows versions [V];
- portable SQLite provider/runtime choice [V];
- private-key storage mechanism (CNG vs DPAPI fallback) [V];
- exact new local SQLite snapshot contract and migration strategy;
- exact central-to-local transport mechanism for V1;
- package signing/integrity implementation;
- real IIS, Keycloak, TSplus and service behavior in a disposable/controlled Windows environment [V];
- credential-envelope trust bootstrap and signing-key distribution.

The following are **no longer pending**:

- core stored engine availability;
- core engine versions/minimum PowerShell/admin flags;
- DATABASE_CONTENT_SYNC action mapping;
- WINDOWS_SERVICES action mapping;
- exact FULL_DEPLOYMENT step order;
- exact schemas for the principal current central policy tables;
- current engine SQL/procedure dependency inventory.

## 8. Phase 0 classification result

All engines explicitly named in the production handoff have been classified against their current stored scripts and central dependencies.

No reference-repository file was modified.

No engine is considered production-validated for the new portable runtime until its later `[V]` gate passes.
