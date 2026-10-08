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
| `LINKS_VISIBILITY` | 8 | `MUTATING` [PENDING] | none | none |
| `V8_KEYCLOAK_CONFIG` | 8 (retired) | `RETIRED` (not active) | none | none |
| `DATABASE_COPY` | 9 | `MUTATING` | none | none |

## Classification rule and LINKS_VISIBILITY evidence

An engine is `READ_ONLY` only when every converted `ops_Action` row that uses that engine has `ModePolicy = NONE`; if any such action has another mode policy, the engine is `MUTATING`.

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

That result matches the raw snapshot SQL row checked separately. Under the rule above, the current executable classification is therefore `MUTATING`.

[PENDING] This conflicts with the `LINKS_VISIBILITY` specification and the owner decision of 2026-10-06, which describe a read-only visibility matrix/proposal flow with catalog changes performed by owner edit plus a new seal. If the owner wants the executable classification to be `READ_ONLY`, the `LINKS_VISIBILITY` action must be changed to `ModePolicy = NONE` by catalog edit and the catalog must be sealed again. Until then the matrix records `MUTATING`.

`V8_KEYCLOAK_CONFIG` is retired as an autonomous engine and is not an active host target; its behaviour is absorbed by `CONFIG_REPAIR`.
