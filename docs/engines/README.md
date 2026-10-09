# Engine host contract summary

This summary separates the 17 engine rows carried by the portable catalog from engines that the owner explicitly retired and from composite actions that are not engines.

`Intended credential references` are the reference families or exact references that the ported engine specification expects to need. `Host-accepted references today` records what the executable host contract accepts. In current `main`, `DEPLOYMENT_PREFLIGHT` has no accepted references: the contract is empty and the host accepts exact references only. After PR #67 is integrated, `DEPLOYMENT_PREFLIGHT` declares `IIS_IDENTITY.*` and `WEB_ACCESS.*`, accepted by family for active catalog instances. PR #67 adds host support for the family wildcard form `TYPE.*` only for `IIS_IDENTITY`, `WEB_ACCESS`, `MOBILE_APP_TOKEN`, and `RULE_SECRET`, and only for references belonging to active catalog instances. PR #68 documents that transition and does not modify the executable contract or host.

## Portable catalog engines

Reviewer evidence from the six real converted catalogs used:

```sql
SELECT COUNT(*) AS EngineCount
FROM ops_Engine;
```

and returned `17` in every catalog. The matrix below lists those 17 portable-catalog engine rows.

| Engine | Wave | Engine class | Intended credential references | Host-accepted references today |
|---|---:|---|---|---|
| `DEPLOYMENT_PREFLIGHT` | 1 | `READ_ONLY` | `IIS_IDENTITY.*`, `WEB_ACCESS.*` | none in current `main`; after #67: `IIS_IDENTITY.*`, `WEB_ACCESS.*`, accepted by family for active catalog instances |
| `PULSE_STATUS` | 1 | `MUTATING` | `IIS_IDENTITY.*` | none |
| `CONFIG_REPAIR` | 2 | `MUTATING` | `RULE_SECRET.*` | none |
| `MANAGED_ASSETS` | 2 | `MUTATING` | none | none |
| `IIS_RECONCILE` | 3 | `MUTATING` | `IIS_IDENTITY.*` | none |
| `WINDOWS_SERVICES` | 4 | `MUTATING` | `IIS_IDENTITY.*` | none |
| `V8_KEYCLOAK_PREREQUISITES` | 4 | `MUTATING` | none | none |
| `V8_KEYCLOAK_SERVICE` | 4 | `MUTATING` | `IIS_IDENTITY.*` | none |
| `KEYCLOAK_CLIENT_SECRETS` | 4 | `MUTATING` | `RULE_SECRET.ESIGN_V8_CLIENT_SECRET`, `RULE_SECRET.GEOFENCES_V8_CLIENT_SECRET`, `RULE_SECRET.MESSENGER_V8_CLIENT_SECRET`, `RULE_SECRET.VACATIONS_V8_CLIENT_SECRET`, `RULE_SECRET.MAINSHELL_V8_CLIENT_SECRET`, `RULE_SECRET.WEBAPI_V8_SWAGGER_CLIENT_SECRET`, `RULE_SECRET.API_V8_KEYCLOAK_ACCESS_TOKEN`, `RULE_SECRET.DASHBOARDS_V8_CLIENT_SECRET` | none |
| `WEB_ACCESS` | 5 | `MUTATING` | `WEB_ACCESS.*` | none |
| `LINKS_PAGES` | 5 | `MUTATING` | none | none |
| `DATABASE_CONTENT_SYNC` | 5 | `MUTATING` | `MOBILE_APP_TOKEN.*` | none |
| `ENVIRONMENT_STATE_PROBE` | 7 | `OBSERVATIONAL` | none | none |
| `STORAGE_SIZE_SCAN` | 7 | `OBSERVATIONAL` | none | none |
| `MODEL_REVIEW` | 7 | `READ_ONLY` | none | none |
| `LINKS_VISIBILITY` | 8 | `OBSERVATIONAL` [PROPOSED] | none | none |
| `DATABASE_COPY` | 9 | `MUTATING` | none | none |

## Retired engines

[DECIDED 2026-10-06] Q3 in `docs/decisions-log.md` says that `DATABASE_SETTINGS` and `V8_KEYCLOAK_CONFIG` are not ported as autonomous engines because their required behavior is provided by newer engines. They are not members of the 17-row portable engine catalog above and are not active host targets.

| Retired engine | Former wave | Engine class | Replacement / retained behavior |
|---|---:|---|---|
| `DATABASE_SETTINGS` | 5 | `RETIRED` (not active) | `DATABASE_CONTENT_SYNC`; the executable `DATABASE_SETTINGS` action uses `DATABASE_CONTENT_SYNC`, so the legacy engine is not ported independently |
| `V8_KEYCLOAK_CONFIG` | 8 | `RETIRED` (not active) | `CONFIG_REPAIR`, through the `KEYCLOAK_DB_URL` rule; no standalone module or host invocation |

## Composite actions

`FULL_DEPLOYMENT` is not an engine and has no engine class. Its catalog action is `COMPOSITE`, it has no engine script of its own, and the engine host refuses non-`ENGINE` actions before engine resolution.

| Action | Wave | Class | Credential semantics | Execution semantics |
|---|---:|---|---|---|
| `FULL_DEPLOYMENT` | 6 | `N/A - COMPOSITE / orchestrator` | child engines declare their own references | the orchestrator runs the child engines; its side effects are the union of the child-engine side effects and are orchestrator semantics, never a `MUTATING` engine class |

## Classification rule and LINKS_VISIBILITY evidence

`READ_ONLY` is mechanical: every converted `ops_Action` row that uses the engine must have `ModePolicy = NONE`. This is the only engine-class distinction the host uses for its timeout kill policy.

If any action that uses the engine has a mode policy other than `NONE`, `ModePolicy` does not distinguish `MUTATING` from `OBSERVATIONAL`. That distinction comes from the approved specification and decisions log:

- `MUTATING`: apply changes a managed target, including files, services, IIS, databases, scheduled tasks or the catalog.
- `OBSERVATIONAL`: apply only measures or produces reports or proposals outside managed targets.
- If the approved specification is insufficient to decide, mark the class `[PENDING]` and use `MUTATING` provisionally.

Third-party evidence supplied by the reviewer on 2026-10-08, not independently verified in this change, used this query:

```sql
SELECT ActionCode, EngineCode, ModePolicy, IsEnabled
FROM ops_Action
WHERE EngineCode = 'LINKS_VISIBILITY'
ORDER BY ActionCode;
```

Across all six converted catalogs from the 29516382-byte snapshot (`BR_DEMO`, `ES_DEMO`, `PRESALES`, `PT_DEMO`, `SANDBOX_HUB`, `TENDERS`), the reviewer reported exactly one row in each catalog:

```text
LINKS_VISIBILITY | LINKS_VISIBILITY | PREVIEW_APPLY | 1
```

The non-`NONE` mode means `LINKS_VISIBILITY` is not `READ_ONLY`. It does not make the engine `MUTATING`. The owner decision of 2026-10-06 Q9 selects option A: a read-only effective visibility matrix, with changes made by an owner editing and resealing the catalog. Section 7 of `docs/engines/LINKS_VISIBILITY.md` says there is no apply that changes the catalog; apply produces a text proposal file and performs no database write. The approved port therefore has class `OBSERVATIONAL` [PROPOSED]. `PREVIEW_APPLY` is consistent with that proposal-producing apply.

Because its `ModePolicy` is not `NONE`, the host does not kill `LINKS_VISIBILITY` when its timeout expires.

The remaining engine classes were rechecked against their current specifications with this rule. No other engine-class changes are required: `DEPLOYMENT_PREFLIGHT` and `MODEL_REVIEW` remain `READ_ONLY`; `ENVIRONMENT_STATE_PROBE` and `STORAGE_SIZE_SCAN` remain `OBSERVATIONAL`; every other engine in the 17-row portable catalog remains `MUTATING` because its approved side effects change managed targets. The two retired engines are listed separately above and are not active host targets.

## DEPLOYMENT_PREFLIGHT credential correction

Reviewer-verified legacy behaviour requires both credential families: `IIS_IDENTITY.*` and `WEB_ACCESS.*`. The old preflight verifies the Web Access password (`WEB_ACCESS_PASSWORD_MISSING`), and the owner decision of 2026-10-07 requires all 12 reviews and all their issue codes to be ported.

The individual `DEPLOYMENT_PREFLIGHT` specification records both families. In current `main`, the executable contract is empty and the host accepts only exact references, so `DEPLOYMENT_PREFLIGHT` has no accepted references. After PR #67 is integrated, the contract declares `IIS_IDENTITY.*` and `WEB_ACCESS.*` and the host accepts those families for active catalog instances.
