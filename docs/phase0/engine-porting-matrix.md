# Phase 0 — Engine Porting Matrix

**Status:** Phase 0 diagnostic  
**Target:** SISQUALDeployConsole V1  
**Reference repository:** `atsisqual/SISQUALManagementConsole` read-only  
**V1 authoring policy:** central configuration is read-only; execution is local.

## Status vocabulary

- **[CONFIRMED-CODE]** demonstrated by the reference repository.
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
| `DEPLOYMENT_PREFLIGHT` | [CONFIRMED-PRODUCTION]; current repo retains deployment-preflight support surfaces | Managed server/instance catalogue, application catalogue, filesystem/IIS/SQL prerequisites | Intended read-only validation | Local diagnostic module reading cached central policy plus live local machine state | Exact production script not available as standalone repo file | First |
| `PULSE_STATUS` | [CONFIRMED-PRODUCTION]; pulse/profile surfaces visible in current migrations | Instance/server catalogue, URLs/services/SQL/IIS depending on checks, pulse state/history | Primarily probes; current system may persist state centrally | Local probes; results/history stored only in local SQLite in V1 | Exact live check catalogue/state contract not fully available | First |
| `CONFIG_REPAIR` | [CONFIRMED-CODE] standalone engine v15 | `cfg.GetLocalManagementContext`, `cfg.ReviewRepairModel`, `cfg.GetRepairPlan`, config files, backup root | Backup + JSON/XML/whole-file/TEXT_REGEX modifications on Apply | Split plan resolution from generic file mutation; consume synchronized rule model locally | PS 5.1 compatibility; exact parser/encoding preservation; rule schema extraction | First |
| `DATABASE_CONTENT_SYNC` | [CONFIRMED-PRODUCTION]; adapter maps database settings to `SETTINGS_SYNC` | `cfg.DatabaseObjectSettingRule`, target application DBs, direct SQL connectivity | Updates configured DB values | Local generic DB-setting engine using structured predicates only and direct SqlConnection | Need exact rule schema and live alias mapping; prohibit arbitrary browser SQL | Later core |
| `MANAGED_ASSETS` | [CONFIRMED-PRODUCTION] | Managed instance metadata/assets, filesystem, hashes | Writes/deploys managed assets | Local asset reconciliation from cache/package, hash verified | Exact asset table/contract needs extraction | Mid |
| `IIS_RECONCILE` | [CONFIRMED-PRODUCTION]; [CONFIRMED-CODE] IIS adapter/runtime | IIS topology policy, `WebAdministration`, instance paths, bindings, pools, credentials | Creates/updates sites/apps/pools/bindings; starts pools | Local IIS module; preview desired/actual diff before Apply | PowerShell 7/WebAdministration compatibility [V]; destructive topology changes | Mid |
| `WINDOWS_SERVICES` | [CONFIRMED-PRODUCTION]; current adapter action is `SERVICE_RECONCILE` | Service definitions, Win32_Service/Get-Service, instance/hostname mapping, credentials where applicable | Create/update/start/stop service configuration | Local Windows-service reconciliation module | Exact production naming/action alias; service privilege semantics [V] | Mid |
| `V8_KEYCLOAK_PREREQUISITES` | [CONFIRMED-PRODUCTION] | Keycloak files/runtime/ports/instance metadata | Repairs/installs prerequisites | Local prerequisite validator/reconciler | Exact script not standalone; Java/runtime assumptions [V] | Mid |
| `V8_KEYCLOAK_SERVICE` | [CONFIRMED-PRODUCTION] | Keycloak service config, ports, filesystem, Windows service | Configures/operates Keycloak service | Local service/config module after prerequisite engine | Clone-origin leakage of URLs/secrets; service compatibility [V] | Mid |
| `KEYCLOAK_CLIENT_SECRETS` | [CONFIRMED-PRODUCTION] | Keycloak clients, credential material, instance URLs | Updates client secrets/config | Local engine consuming offline-delivered credential envelope; never normal sync | Secret handling, redaction, idempotency; exact Keycloak interface [V] | After credential Phase |
| `WEB_ACCESS` | [CONFIRMED-PRODUCTION]; [CONFIRMED-CODE] TSplus portable runtime exists | TSplus AdminTool, shared-resource semantics, instance metadata | Web Access/TSplus start-stop/configuration | Local module with explicit shared-resource lock | Shared controller can affect multiple environments; path/version differences [V] | Later |
| `LINKS_PAGES` | [CONFIRMED-PRODUCTION]; links publishing/profile code exists | Instance/app visibility/profile configuration, filesystem/web content | Publishes/repairs links pages | Local generation/reconciliation from read-only central config | Current repo has multiple generations/profile override precedence | Later |

## Composite action

### `FULL_DEPLOYMENT`

**[CONFIRMED-PRODUCTION]** The current system composes approximately twelve action steps through `ops.Action` / `ops.ActionStep`.

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

**[PENDING]** Extract exact current preflight definition/procedures and all enabled requirements from available migrations/seed material or later central snapshot.

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

| Production handoff | Current repo evidence | Status |
|---|---|---|
| `DATABASE_CONTENT_SYNC` | Configuration adapter uses `SETTINGS_SYNC` | [PENDING] alias/rename relationship |
| `WINDOWS_SERVICES` | Adapter uses `SERVICE_RECONCILE` | [PENDING] alias/rename relationship |
| SQL-stored engine catalogue | Only `CONFIG_REPAIR.ps1` and `STORAGE_SIZE_SCAN.ps1` are visible as standalone `database/engines` scripts plus runtime orchestrators | [CONFIRMED] repo is not a complete export of live `ops.Engine` |
| nightly sync payload | `database/sync/ManagementSync.sql` is empty at inspected master | [CONFIRMED] cannot reconstruct sync solely from this file |

## Capabilities discovered but not automatically in V1 scope

The current reference repo includes Database Copy, Environment Clone, Housekeeping, Environment Power, Version Intelligence, scheduling/approvals and file-copy features.

**[CONFIRMED]** They are recorded as future inventory only. Their presence in the reference repo does not make them V1 requirements.

## Phase 0 classification result

All engines explicitly named in the production handoff have been classified.

No engine is marked “ready to port” without later Phase 1/runtime validation or extraction of its exact configuration contract.

No production/reference repository file was modified.
