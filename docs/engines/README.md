# Engine host contract summary

This table is derived from the `Host contract` section in each engine specification. It records the engine class required by ADR-0008 and the credential references that the host may pass to the engine.

| Engine | Wave | Engine class | Credential references |
|---|---:|---|---|
| `DEPLOYMENT_PREFLIGHT` | 1 | `READ_ONLY` | `IIS_IDENTITY.*` |
| `PULSE_STATUS` | 1 | `MUTATING` | `IIS_IDENTITY.*` |
| `CONFIG_REPAIR` | 2 | `MUTATING` | `RULE_SECRET.*` |
| `MANAGED_ASSETS` | 2 | `MUTATING` | none |
| `IIS_RECONCILE` | 3 | `MUTATING` | `IIS_IDENTITY.*` |
| `WINDOWS_SERVICES` | 4 | `MUTATING` | `IIS_IDENTITY.*` |
| `V8_KEYCLOAK_PREREQUISITES` | 4 | `MUTATING` | none |
| `V8_KEYCLOAK_SERVICE` | 4 | `MUTATING` | `IIS_IDENTITY.*` |
| `KEYCLOAK_CLIENT_SECRETS` | 4 | `MUTATING` | `RULE_SECRET.ESIGN_V8_CLIENT_SECRET`, `RULE_SECRET.GEOFENCES_V8_CLIENT_SECRET`, `RULE_SECRET.MESSENGER_V8_CLIENT_SECRET`, `RULE_SECRET.VACATIONS_V8_CLIENT_SECRET`, `RULE_SECRET.MAINSHELL_V8_CLIENT_SECRET`, `RULE_SECRET.WEBAPI_V8_SWAGGER_CLIENT_SECRET`, `RULE_SECRET.API_V8_KEYCLOAK_ACCESS_TOKEN`, `RULE_SECRET.DASHBOARDS_V8_CLIENT_SECRET` |
| `WEB_ACCESS` | 5 | `MUTATING` | `WEB_ACCESS.*` |
| `LINKS_PAGES` | 5 | `MUTATING` | none |
| `DATABASE_CONTENT_SYNC` | 5 | `MUTATING` | `MOBILE_APP_TOKEN.*` |
| `FULL_DEPLOYMENT` | 6 | `MUTATING` | none (child engines declare their own references) |
| `ENVIRONMENT_STATE_PROBE` | 7 | `OBSERVATIONAL` | none |
| `STORAGE_SIZE_SCAN` | 7 | `OBSERVATIONAL` | none |
| `MODEL_REVIEW` | 7 | `READ_ONLY` | none |
| `LINKS_VISIBILITY` | 8 | `MUTATING` [PENDING] | none |
| `V8_KEYCLOAK_CONFIG` | 8 (retired) | `MUTATING` | none |
| `DATABASE_COPY` | 9 | `MUTATING` | none |

`LINKS_VISIBILITY` is conservatively classified as `MUTATING` pending owner confirmation because its catalog action supports apply and the legacy behaviour writes configuration. `V8_KEYCLOAK_CONFIG` is retired as an autonomous engine; its behaviour is absorbed by `CONFIG_REPAIR`.
