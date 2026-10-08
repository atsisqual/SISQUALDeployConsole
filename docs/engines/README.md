# Engine host contract summary

This table is derived from the `Host contract` section in each engine specification. It separates intended port requirements from executable host acceptance.

`Intended credential references` are the references the ported engine specification expects to need. They are not executable permission. `Host-accepted references today` are the references the executable host contract accepts. The host accepts exact references declared in `contracts/engine-secret-references.json`; wildcard notation below is descriptive only. In the current integration sequence, after PR #67 is integrated, only `DEPLOYMENT_PREFLIGHT` has declared host acceptance, for the exact `IIS_IDENTITY.*` references added by that PR. Every other engine remains `none` until its own port adds exact declarations to the executable contract.

| Engine | Wave | Engine class | Intended credential references | Host-accepted references today |
|---|---:|---|---|---|
| `DEPLOYMENT_PREFLIGHT` | 1 | `READ_ONLY` | `IIS_IDENTITY.*` | `IIS_IDENTITY.*` after #67; exact declared references only |
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
| `FULL_DEPLOYMENT` | 6 | `MUTATING` | none (child engines declare their own references) | none |
| `ENVIRONMENT_STATE_PROBE` | 7 | `OBSERVATIONAL` | none | none |
| `STORAGE_SIZE_SCAN` | 7 | `OBSERVATIONAL` | none | none |
| `MODEL_REVIEW` | 7 | `READ_ONLY` | none | none |
| `LINKS_VISIBILITY` | 8 | `OBSERVATIONAL` [PROPOSED] | none | none |
| `V8_KEYCLOAK_CONFIG` | 8 (retired) | `RETIRED` (not active) | none | none |
| `DATABASE_COPY` | 9 | `MUTATING` | none | none |

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

The remaining engine classes were rechecked against their current specifications with this rule. No other class changes are required: `DEPLOYMENT_PREFLIGHT` and `MODEL_REVIEW` remain `READ_ONLY`; `ENVIRONMENT_STATE_PROBE` and `STORAGE_SIZE_SCAN` remain `OBSERVATIONAL`; every other active engine in the table remains `MUTATING` because its approved side effects change managed targets. `V8_KEYCLOAK_CONFIG` remains retired and is not an active host target; its behaviour is absorbed by `CONFIG_REPAIR`.
