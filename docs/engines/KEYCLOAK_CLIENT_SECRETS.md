# Engine port specification: KEYCLOAK_CLIENT_SECRETS

**Status:** [PROPOSED] specification for review (task 3, wave 4). No product code.
**Date:** 2026-10-05
**Sources (read only):** `ops.Engine` row `KEYCLOAK_CLIENT_SECRETS` of `database/sync/ManagementSync.sql` of `atsisqual/SISQUALManagementConsole` (file `KEYCLOAK_CLIENT_SECRETS.ps1`, version `v1`, Windows PowerShell 5.1, requires administrator, stored `ScriptSha256` `6001779F...`; reference head `9756ba956842884fabcf25b82c4fbf1d11cf56bd`); the action `KEYCLOAK_CLIENT_SECRETS`; step 64 of `FULL_DEPLOYMENT`. Script text is not copied and no secret value appears here.
Tags: [CONFIRMED] read in the source; [PROPOSED] recommendation; [PENDING] needs a decision; [V] needs a real server.

## 1. Purpose

Make the client secrets stored in each instance's Keycloak database equal to the secrets the configuration files carry. [CONFIRMED] Action: group `INFRASTRUCTURE`, preview and apply, all enabled instances or one, step 64 of `FULL_DEPLOYMENT` (stop on error).

## 2. Inputs

| Source | Content |
|---|---|
| `cfg_KeycloakClientSecretRule` (8 rows) | `KeycloakClientId` and `SecretRuleCode`, all enabled |
| credential package | the `RULE_SECRET` entry of each rule (`credentialRef` = the rule code) |
| `dbo_ManagedInstance`, `dbo_ManagedServer` | host name, SQL instance name, machine name |

[CONFIRMED] The 8 rule codes are `ESIGN_V8_CLIENT_SECRET`, `GEOFENCES_V8_CLIENT_SECRET`, `MESSENGER_V8_CLIENT_SECRET`, `VACATIONS_V8_CLIENT_SECRET`, `MAINSHELL_V8_CLIENT_SECRET`, `WEBAPI_V8_SWAGGER_CLIENT_SECRET`, `API_V8_KEYCLOAK_ACCESS_TOKEN` and `DASHBOARDS_V8_CLIENT_SECRET`. They are among the 16 sensitive rules whose literal values the converter replaced by references; the old engine used the rule's literal as the secret. One value per rule serves every instance.

## 3. Steps

1. Resolve the machine and the instances of this machine.
2. For each instance, connect to the instance's own SQL Server (machine name and SQL instance name) with the current Windows identity. If the Keycloak database `sisqualKeycloak` does not exist: `SKIPPED` ("not physically deployed yet").
3. For each mapping: read the stored secret of the client. No row: `CLIENT_NOT_FOUND`. Equal: `MATCHED`. Different: `WOULD_UPDATE` in preview; in apply, update the stored secret and report `UPDATED`.
4. Report one row per instance and client; fail at the end if any row is `ERROR`.

## 4. Side effects

Updates the client table of each instance's Keycloak database directly (not through the Keycloak admin interface). No backup is made.

## 5. External dependencies

Each instance's SQL Server (local to the machine) and the `sisqualKeycloak` database. [PENDING] connection encryption and certificate trust (the old script trusts any certificate).

## 6. Preview and apply

Preview compares and reports status only, with no values. Apply consumes the fingerprint of the preview and refuses if the package or the databases changed.

## 7. Idempotency

A second apply reports `MATCHED`. Comparison is exact on the stored text.

## 8. Failures

Database missing: `SKIPPED`. Client missing: `CLIENT_NOT_FOUND` (not an error, but a warning in the summary). Connection, permission or update failure: `ERROR` for that row, the others continue, the run fails at the end. An unresolved secret reference stops the run before any connection.

## 9. Backup and restore

[PROPOSED] Before updating, keep the previous secret of each changed client in a protected run manifest, encrypted for the machine key, so that a failed rollout can be reversed; the manifest is deleted on a configurable schedule. Restore re-applies it. This holds old secrets and must be treated as a credential store (risk R-008).

## 10. Secret risks

- The secrets are read into memory, compared and discarded; the old report holds statuses only and never a value. [PROPOSED] Keep it that way: no value, no hash prefix, no length in any output; marker secret test.
- [CONFIRMED] The old SQL is built by joining text, with quotes doubled for the secret. [PROPOSED] Use parameters throughout.
- The old script ignores its SQL and database parameters and reads the central database at fixed names; the port reads the catalog and the package.
- The stored secret is plain text in the Keycloak database (the engine compares it directly); access to that database equals access to the secrets (outside this engine).

## 11. What does not port as it is

The mapping query joins the rule table to read the literal template as the secret: it becomes a lookup of the `RULE_SECRET` entry. Connections use the pinned SQL client from the portable. The central database access goes.

## 12. Test plan

- Runner: SQL Server LocalDB with a throw-away `sisqualKeycloak` database and client table; database missing, client missing, equal, different, update, second run, an error on one row with the others continuing, quotes and special characters in a secret, the unresolved reference, no value in any artifact (marker), the instance filter.
- [V] A real Keycloak and database; whether a changed secret takes effect on a running Keycloak (13.2).

## 13. Open questions

1. [PENDING] **Order on a clean server.** Step 64 runs before the Keycloak service is first started (step 65), and the database may be created only when Keycloak first starts; then every row is `SKIPPED` and the secrets are set only by the next run. Recommendation: verify on the pilot [V] and, if so, run this engine again after the service step.
2. [PENDING] Keycloak may keep client data in memory; a direct database update may not take effect until a restart or cache refresh. Recommendation: test [V]; if needed, restart the service after a change, or use the admin interface instead.
3. [PENDING] One secret per rule for all instances (also open in the `CONFIG_REPAIR` specification, PR #32). Recommendation: keep, and review per-instance secrets before any customer-facing rollout.
4. [PENDING] Connection encryption defaults for the instance SQL Servers. Recommendation: encrypt and validate by default, with an explicit exception setting.
