# KEYCLOAK_CLIENT_SECRETS port brief

**Status:** [PROPOSED]
**Task:** T7 / M3.5
**Date:** 2026-10-10

This brief defines the implementation gate for `KEYCLOAK_CLIENT_SECRETS`. It is documentation only.

## 1. Sources and evidence boundary

[CONFIRMED] Checked now against `main`:

- `docs/engines/KEYCLOAK_CLIENT_SECRETS.md` documents source-era `KEYCLOAK_CLIENT_SECRETS.ps1`, action `KEYCLOAK_CLIENT_SECRETS` and step 64 of `FULL_DEPLOYMENT`.
- `tests/Fixtures/carried-schema.json` confirms `cfg.KeycloakClientSecretRule` with the non-secret mapping fields including `KeycloakClientId` and `SecretRuleCode`, plus the managed-instance SQL-location fields used by the specification.
- The current host-contract specification already declares the eight exact `RULE_SECRET.<RuleCode>` references; this matches the 2026-10-09 owner decision that `RULE_SECRET` is always exact and never a wildcard family.

[NOT VERIFIED] The original v1 script and real Keycloak database schema were not re-extracted or executed for this brief. Direct-database cache behavior, real SQL encryption/certificate topology and whether changes require a Keycloak restart remain `[V]` evidence.

## 2. Purpose and class

[CONFIRMED] `KEYCLOAK_CLIENT_SECRETS` is `MUTATING`. It compares each configured Keycloak client secret with the exact rule secret from the credential package and, on APPLY, updates differing client rows.

[CONFIRMED] It supports all enabled instances or one selected instance and is step 64 of `FULL_DEPLOYMENT`.

## 3. Mapping and credentials

[CONFIRMED] `cfg.KeycloakClientSecretRule` is non-secret mapping data. The current specification records eight enabled mappings:

- `RULE_SECRET.ESIGN_V8_CLIENT_SECRET`
- `RULE_SECRET.GEOFENCES_V8_CLIENT_SECRET`
- `RULE_SECRET.MESSENGER_V8_CLIENT_SECRET`
- `RULE_SECRET.VACATIONS_V8_CLIENT_SECRET`
- `RULE_SECRET.MAINSHELL_V8_CLIENT_SECRET`
- `RULE_SECRET.WEBAPI_V8_SWAGGER_CLIENT_SECRET`
- `RULE_SECRET.API_V8_KEYCLOAK_ACCESS_TOKEN`
- `RULE_SECRET.DASHBOARDS_V8_CLIENT_SECRET`

[DECIDED 2026-10-09] These references are exact. The engine must not request `RULE_SECRET.*` and must fail before opening any instance database if a required exact reference cannot be resolved.

No result, log, fingerprint or backup metadata may expose secret value, length, prefix or hash fragment.

## 4. Database targeting

[PROPOSED] Resolve each target database exclusively from the verified catalog and an allowlisted database name `sisqualKeycloak`; never accept a caller-supplied SQL/database override.

Connections use the pinned SQL client and parameterized commands. Instance/catalog identifiers select approved targets; client IDs and values are SQL parameters, never concatenated text.

[PENDING] Connection encryption/certificate policy must be explicit before production. Default recommendation remains encrypted and validated; no trust-any-certificate behavior is accepted merely because the old engine used it.

## 5. Preview and apply

[CONFIRMED] Source-era status semantics recorded by the specification are:

- database absent: `SKIPPED` / not physically deployed;
- client absent: `CLIENT_NOT_FOUND` warning-like state;
- exact secret equal: `MATCHED`;
- different in preview: `WOULD_UPDATE`;
- different after successful APPLY: `UPDATED`;
- connection/update failure: `ERROR`.

[PROPOSED] Preview opens databases read-only where practical and performs no update. APPLY consumes the exact confirmed preview fingerprint, rechecks target/client state and changes only rows that still match the preview precondition.

Comparison is exact on secret text but produces only boolean equality internally; no diagnostic includes either value.

## 6. Clean-server ordering

[PENDING] The current order runs this engine at step 64 before first Keycloak service start at step 65. If `sisqualKeycloak` is created only on first Keycloak startup, a clean-server run would skip every row.

The orchestration must resolve this explicitly: prove the database already exists before step 64, or execute the client-secret reconciliation again after service/database initialization. `SKIPPED` must not silently count as completed secret deployment on a clean server.

## 7. Side effects and cache behavior

[CONFIRMED] APPLY directly updates client-secret data in each instance's Keycloak database; it does not use the Keycloak Admin API.

[V] Determine whether running Keycloak observes the direct change immediately or requires cache invalidation/restart. Until proven, the engine must not claim that `UPDATED` means the running Keycloak process has consumed the new value.

## 8. Backup and restore

A rollback copy of an old client secret is itself a credential.

[PROPOSED] If rollback is required, store previous values only in a machine-protected encrypted run artifact with strict lifetime/ACL and no values in the ordinary engine result. Restore accepts that protected artifact and writes via parameterized SQL. If the project cannot meet credential-store requirements for the artifact, use a forward-fix model instead of writing plaintext/ordinary backup manifests.

[PENDING] Retention/deletion schedule for protected secret rollback material requires an owner-approved policy.

## 9. Failure/result semantics

[PROPOSED] One result row per selected instance/client mapping, deterministic by instance and client ID. It may include instance code, client ID, rule code and status, but never secret-derived data.

- unresolved required secret: fail before target connections;
- missing database: preserve `SKIPPED` only as deployment-state information and let orchestration decide whether it is acceptable for the current milestone;
- missing client: warning unless source/owner evidence says it is blocking;
- connection/permission/SQL/update/post-update mismatch: `ERROR`;
- one instance/client failure does not reveal or skip the status of independent mappings; overall run fails on any blocking error.

## 10. Required tests

Runner/LocalDB coverage must include:

- exact eight-reference authorization and rejection of `RULE_SECRET.*`;
- missing exact credential stops before any database connection;
- database absent, client absent, matched, would-update, updated and second-run matched;
- one failing mapping with independent mappings still reported;
- quotes, Unicode and SQL metacharacters proving fully parameterized SQL;
- marker secret absent from result, text log, process arguments, exception text and ordinary backup artifacts;
- preview makes no update; fingerprint drift blocks APPLY;
- target database allowlist prevents caller/catalog path manipulation to another database;
- connection failure and permission failure;
- post-update re-read verifies exact equality without logging values;
- selected-instance filtering;
- protected rollback artifact round trip if rollback is implemented.

[V] Real Keycloak database schema and cache/restart behavior; real encrypted SQL connectivity/certificate validation.

## 11. Open questions

1. [PENDING] Clean-server ordering relative to first Keycloak database creation.
2. [PENDING] Whether direct DB updates require Keycloak restart/cache refresh or should be replaced by an Admin API flow.
3. [PENDING] Whether one secret per rule intentionally serves all instances in V1.
4. [PENDING] Exact SQL encryption/certificate policy.
5. [PENDING] Whether secret rollback artifacts are permitted and their retention/ACL policy.
6. [PENDING] Final severity of `CLIENT_NOT_FOUND`.

## 12. Entry gate for the code PR

The code PR may start when:

- the carried mapping/instance columns used by code are confirmed;
- the exact eight `RULE_SECRET.<RuleCode>` references are the host contract;
- the real Keycloak client table/columns used for read/update are captured as approved evidence;
- clean-server ordering is resolved or explicitly tested as an incomplete state;
- SQL encryption policy is defined for runner and production paths;
- rollback strategy does not create an unprotected credential store;
- tests prove parameterization and total secret non-disclosure.
