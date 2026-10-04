# Phase 0 — Engine Porting Matrix

**Status:** Phase 0 diagnostic  
**Target:** SISQUALDeployConsole V1  
**Reference repository:** `atsisqual/SISQUALManagementConsole` read-only  
**V1 authoring policy:** central configuration is read-only; execution is local.

## Status vocabulary

- **[CONFIRMED-CODE]** demonstrated by normal versioned source/migrations in the reference repository.
- **[CONFIRMED-SYNC]** demonstrated by the generated `ManagementSync.sql` snapshot, including live exported rows and SQL-stored engine text.
- **[CONFIRMED-PRODUCTION]** demonstrated by the production handoff.
- **[INFERRED]** reasonable mapping not yet proven end-to-end.
- **[PENDING]** evidence/decision still required.
- **[V]** must be validated on Windows/SISQUAL in a later phase.

## Porting principle

“Port” means preserve the operational behavior and safety contract while moving execution into local PowerShell modules. It does **not** mean copying the current SQL-stored script verbatim.

Every V1 engine must ultimately have a local contract with preview/apply semantics where applicable, structured output, explicit target scope, idempotency expectations, backup/rollback evidence, and no dependency on Pode.

## Core V1 engines

| Engine | Evidence | Current dependencies | Current side effects | V1 porting direction | Main blocker/risk | Phase |
|---|---|---|---|---|---|---|
| `DEPLOYMENT_PREFLIGHT` | [CONFIRMED-SYNC] engine `Invoke-DeploymentPreflight.ps1` v1.0 stored in `ops.Engine` | Managed server/instance catalogue, application catalogue, filesystem/IIS/SQL prerequisites | Read-only validation | Local diagnostic module reading cached central policy plus live local machine state | Semantic extraction + PowerShell 7/Windows validation [V] | First |
| `PULSE_STATUS` | [CONFIRMED-SYNC] engine `Invoke-SISQUALPulseStatus.ps1` v2; `ops.PulseCheckState` schema + 132 exported rows | Instance/server catalogue, pulse profile/check definitions, HTTP/SQL/IIS checks, pulse state/history | Probes plus deployment/reconciliation of Pulse page/status snapshot | Local probes; operational results/history stored locally in V1 | Decide which central pulse definitions are mirror inputs vs local result state; Windows/network validation [V] | First |
| `CONFIG_REPAIR` | [CONFIRMED-CODE] standalone engine v15 | `cfg.GetLocalManagementContext`, `cfg.ReviewRepairModel`, `cfg.GetRepairPlan`, config files, backup root | Backup + JSON/XML/whole-file/TEXT_REGEX modifications on Apply | Split plan resolution from generic file mutation; consume synchronized rule model locally | PS 5.1 compatibility; exact parser/encoding preservation; rule schema extraction | First |
| `DATABASE_CONTENT_SYNC` | [CONFIRMED-SYNC] engine `DATABASE_CONTENT_SYNC.ps1` v4; active action `DATABASE_SETTINGS` -> `DATABASE_CONTENT_SYNC` | exact `cfg.DatabaseObjectSettingRule` schema (61 exported rows), target application DBs, direct SQL connectivity | Updates configured DB values | Local generic DB-setting engine using structured predicates only and direct SqlConnection | No alias blocker remains; still prohibit arbitrary browser SQL and validate PS7/SQL behavior [V] | Later core |
| `MANAGED_ASSETS` | [CONFIRMED-SYNC] engine `Invoke-ManagedAssets.ps1` v1.0 is present in `ops.Engine` | Managed instance metadata/assets, filesystem, hashes | Writes/deploys managed assets | Local asset reconciliation from cache/package, hash verified | Extract exact consumed tables/fields from stored script; filesystem validation [V] | Mid |
| `IIS_RECONCILE` | [CONFIRMED-PRODUCTION]; [CONFIRMED-CODE] IIS adapter/runtime | IIS topology policy, `WebAdministration`, instance paths, bindings, pools, credentials | Creates/updates sites/apps/pools/bindings; starts pools | Local IIS module; preview desired/actual diff before Apply | PowerShell 7/WebAdministration compatibility [V]; destructive topology changes | Mid |
| `WINDOWS_SERVICES` | [CONFIRMED-SYNC] active action + engine are both `WINDOWS_SERVICES`; engine `Invoke-WindowsServiceReconciliation.ps1` v2.0 | exact `cfg.WindowsServiceDefinition` schema; current snapshot has one enabled WFM Mobile App definition; Win32 service APIs; IIS identity credential | Create/update/start/stop service configuration | Local Windows-service reconciliation module | `SERVICE_RECONCILE` is stale adapter metadata, not an active action/engine; service semantics still require [V] | Mid |
| `V8_KEYCLOAK_PREREQUISITES` | [CONFIRMED-SYNC] stored engine v7 | Keycloak files/runtime/ports/instance metadata | Verifies/reconciles prerequisites | Local prerequisite validator/reconciler | Java/runtime assumptions and PS7 behavior [V] | Mid |
| `V8_KEYCLOAK_SERVICE` | [CONFIRMED-SYNC] stored engine v5 | Keycloak service config, ports, filesystem, Windows service | Configures/operates Keycloak service and validates listeners/OpenID reachability | Local service/config module after prerequisite engine | Clone-origin leakage of URLs/secrets; service compatibility [V] | Mid |
| `KEYCLOAK_CLIENT_SECRETS` | [CONFIRMED-SYNC] stored engine v1 and enabled action | Keycloak clients, canonical config rules, credential material, instance URLs | Synchronizes Keycloak client secret and application config | Local engine consuming offline-delivered credential envelope; never normal sync | Secret handling/redaction/idempotency and Keycloak interface validation [V] | After credential Phase |
| `WEB_ACCESS` | [CONFIRMED-SYNC] stored engine `Invoke-WebAccessDeployment.ps1` v5.0; [CONFIRMED-CODE] TSplus runtime support | TSplus AdminTool, shared-resource semantics, instance metadata | Web Access/TSplus user/credential/broker deployment and control | Local module with explicit shared-resource lock | Shared controller can affect multiple environments; path/version differences [V] | Later |
| `LINKS_PAGES` | [CONFIRMED-SYNC] stored engine `Invoke-LinksPageDeployment.ps1` v7.1 plus profile/override data | Instance/app visibility/profile configuration, filesystem/web content | Publishes/repairs links pages and global website branding | Local generation/reconciliation from read-only central config | Preserve current profile/override precedence exactly; filesystem validation [V] | Later |

## Composite action

### `FULL_DEPLOYMENT`

**[CONFIRMED-SYNC]** The exported central state contains exactly 13 `FULL_DEPLOYMENT` rows in `ops.ActionStep`: 12 enabled steps and one disabled step (`V8_KEYCLOAK_CONFIG`, order 63). The enabled sequence is preflight, Keycloak prerequisites, config repair, database settings, managed assets, IIS, Windows services, Keycloak client secrets, Keycloak service, Web Access, Pulse and links pages.

**[PROPOSED/APPROVED PLAN]** Do not port `FULL_DEPLOYMENT` as a monolithic engine. In V1 it should become orchestration over already-validated local engines.

It is the last core capability to enable because its safety depends on the correctness, idempotency and rollback behavior of the individual engines.

## Current Worker behavior worth preserving as contracts

### Non-interactive execution

**[CONFIRMED-CODE]** The current Worker parses engine AST and rejects interactive commands. V1 should retain an equivalent static test/gate for shipped local modules.

### Integrity

**[CONFIRMED-CODE]** The current runtime verifies engine hashes before execution.

**[PROPOSED]** V1 local modules should be release-manifest/hash verified rather than fetched as mutable SQL text at execution time. The exact package-signing mechanism is outside Phase 0.

### Job lifecycle

**[CONFIRMED-CODE]** Current states include a SQL-backed queue/claim/run/complete/fail lifecycle; later migrations add richer failure states and runtime policy.

**[PROPOSED]** V1 keeps structured operation state locally rather than reproducing the central Worker queue.

### Target isolation

**[CONFIRMED-CODE]** Current job creation rejects disabled, unknown or foreign-machine targets.

**[PROPOSED]** V1 must preserve this invariant: an operation may only target an enabled environment whose synchronized `ServerCode/MachineName` maps to the current machine, unless a future explicitly approved operation is designed for a remote target.

### Preview first

**[CONFIRMED-CODE]** `CONFIG_REPAIR` defaults to preview.

**[CONFIRMED-CODE]** Configuration adapters declare preview/apply capability.

**[PROPOSED]** Every mutable V1 engine should expose a deterministic preview where technically possible. Apply must use the same normalized plan rather than independently recalculating an unrelated action.

## Detailed port notes

### DEPLOYMENT_PREFLIGHT

Required output should distinguish:
- missing prerequisite;
- incompatible prerequisite;
- unreachable dependency;
- warning;
- ready.

No mutations should occur.

**[CONFIRMED-SYNC]** The exact current preflight engine text is available in `ops.Engine.ScriptText` in the generated snapshot. Dependency extraction remains porting work, but it no longer requires access to a live central database.

### PULSE_STATUS

Read-only local probe execution is a good early proof of the portable architecture because it exercises Windows, IIS, SQL and HTTP access without making changes.

**[PENDING]** Define whether historical pulse results are purely local V1 state or whether central read-only snapshots include historical status. No central writes are allowed.

### CONFIG_REPAIR

Confirmed generic operations include JSON/XML/whole-file/TEXT_REGEX behavior.

Port decomposition should be:

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

The engine must preserve file encoding and must never perform an unverified silent exact-string replacement.

### DATABASE_CONTENT_SYNC

The local engine must:
- connect directly to the destination SQL instance;
- use parameterized SQL;
- derive table/column/predicate only from trusted synchronized configuration;
- reject free-form SQL originating from REST/UI input;
- support preview of old/new values;
- verify affected-row expectations.

Linked-server execution is explicitly not a V1 design.

### IIS_RECONCILE

Known production requirements include one pool per application, application/pool reassignment, SNI/bindings, site creation and local identity behavior.

Those requirements are operational evidence, not permission to hard-code one estate layout. Desired state must come from synchronized configuration.

### WINDOWS_SERVICES

The current platform code demonstrates service discovery through CIM and state control. V1 must separate:
- definition;
- discovery;
- diff;
- apply;
- health verification.

### Keycloak engines

A clone cannot be considered safe merely because the service starts. URL/client/secret provenance must be validated explicitly.

### WEB_ACCESS

Current platform code uses a TSplus AdminTool and SQL-owned shared-resource locking. V1 needs an equivalent local lock because the shared controller can affect more than one environment.

### LINKS_PAGES

Current repo contains profile/override precedence. V1 should synchronize resolved configuration or reproduce the resolution deterministically; it must not invent a second authoring model.

## Name/contract differences discovered

| Production/effective contract | Generated snapshot evidence | Status |
|---|---|---|
| `DATABASE_CONTENT_SYNC` | Active `ops.Action DATABASE_SETTINGS` -> `ops.Engine DATABASE_CONTENT_SYNC` v4. Adapter still says `SETTINGS_SYNC`, but its route points to `DATABASE_SETTINGS`; no `SETTINGS_SYNC` action/engine exists. | [CONFIRMED-SYNC] effective mapping resolved; adapter metadata is stale/inconsistent |
| `WINDOWS_SERVICES` | Active action and engine are both `WINDOWS_SERVICES` v2.0. Adapter says `SERVICE_RECONCILE`; no such action/engine exists. | [CONFIRMED-SYNC] effective mapping resolved; adapter metadata is stale/inconsistent |
| SQL-stored engine catalogue | Generated sync payload contains 19 `ops.Engine` rows including the V1 engine scripts even when no standalone file exists under `database/engines`. | [CONFIRMED-SYNC] sync snapshot is a usable source for exact stored engine text |
| `FULL_DEPLOYMENT` | 13 action-step rows, 12 enabled + disabled `V8_KEYCLOAK_CONFIG`. | [CONFIRMED-SYNC] exact current composition resolved |
| nightly sync payload | Generated `ManagementSync.sql` is ~29.5 MB and contains schema + data export. | [CONFIRMED-SYNC] previous “empty file” conclusion corrected |

## Capabilities discovered but not automatically in V1 scope

The current reference repo includes Database Copy, Environment Clone, Housekeeping, Environment Power, Version Intelligence, scheduling/approvals and file-copy features.

**[CONFIRMED]** They are recorded as future inventory only. Their presence in the reference repo does not make them V1 requirements.

## Phase 0 classification result

All engines explicitly named in the production handoff have been classified.

The exact SQL-stored script text for the V1 engines is now available from the generated snapshot. No engine is nevertheless marked “ready to port” without Phase 1/runtime validation and an explicit local contract.

No production/reference repository file was modified.
