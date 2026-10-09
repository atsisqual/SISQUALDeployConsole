# Engine port specification: DATABASE_CONTENT_SYNC

**Status:** [PROPOSED] specification for review (task 3, wave 5). No product code.
**Owner decision (2026-10-06, Q3):** the legacy engine `DATABASE_SETTINGS` and the table `cfg.DatabaseSettingRule` are **not ported as an autonomous engine**: the behaviour is absorbed by this engine. **There is no functional loss.** Verified by the reviewer in the reference snapshot on 2026-10-06: all 14 rules of `cfg.DatabaseSettingRule` exist, one for one, in `cfg.DatabaseObjectSettingRule` (the 61 rules of this engine), with the same code, the same expected template, the same country, required and sensitive flags and the same enabled state, each targeting `sisqualWFM.dbo.Settings.Value` with a filter that names the old section and key; no action uses the legacy engine (the action `DATABASE_SETTINGS`, step 30 of `FULL_DEPLOYMENT`, runs `DATABASE_CONTENT_SYNC`). The action keeps its name; only the old engine row is retired.
**Date:** 2026-10-05
**Sources (read only):** `ops.Engine` row `DATABASE_CONTENT_SYNC` of `database/sync/ManagementSync.sql` of `atsisqual/SISQUALManagementConsole` (file `DATABASE_CONTENT_SYNC.ps1`, version `v4`, Windows PowerShell 5.1, requires administrator, stored `ScriptSha256` `3AE8F209...`; reference head `9756ba956842884fabcf25b82c4fbf1d11cf56bd`); the action `DATABASE_SETTINGS`, which runs this engine (step 30 of `FULL_DEPLOYMENT`); the older procedure `dbo.SyncDatabaseSettings`. Script text is not copied and no secret value appears here.
Tags: [CONFIRMED] read in the source; [PROPOSED] recommendation; [PENDING] needs a decision; [V] needs a real server.

## 1. Purpose

Set values in the application databases of each instance (Keycloak, the WFM database, the View database) to what the catalog defines, inserting a missing row where allowed. [CONFIRMED] The action `DATABASE_SETTINGS` runs this engine (group `CONFIGURATION`, preview and apply, all enabled instances, step 30 of `FULL_DEPLOYMENT`, stop on error). The older engine `DATABASE_SETTINGS` and the table `cfg.DatabaseSettingRule` (14 rules) are subsumed: all 14 codes are in the newer table, so no separate port (roadmap proposal confirmed by the data).

## 2. Inputs

`cfg_DatabaseObjectSettingRule` (61 rules, all enabled, none country-specific, all `FULL_REPLACE`): setting code, target database, schema (`dbo`) and table, target column, `ExpectedTemplate`, `FilterClause`, `CreateIfMissing` (14, all in the WFM `Settings` table, with `InsertColumnsJson`), `IsSensitive` (3), sort order.

| Target database | Rules | Tables |
|---|---:|---|
| `sisqualKeycloak` | 40 | `CLIENT` (24: root, base and management URLs), `REDIRECT_URIS` (8), `CLIENT_ATTRIBUTES` (8) |
| `sisqualWFM` | 18 | `Settings` (14), `mpSettings` (3), one more |
| `sisqualVIEW` | 3 | `DataSource`, `ReportScriptsDefaults` |

Templates use the tokens host name (51), culture (9), SQL instance (3), database name (3) and the mobile application token (1). [CONFIRMED] The 3 sensitive rules are two connection strings (integrated security, no password) and the mobile application access token (credential kind `MOBILE_APP_TOKEN`, `credentialRef` of the instance). Also: `dbo_ManagedInstance` (SQL instance name, culture, host) and the pinned SQL client.

## 3. Steps

1. Resolve the instances of this machine; for each, the SQL data source (machine and SQL instance name).
2. For each rule: expand the template with the instance data (the template function, ported); [CONFIRMED] a value that cannot be expanded is `EXPECTED_VALUE_UNAVAILABLE`.
3. Count the rows matching the filter. None: `REQUIRED_ROWS_MISSING`, or with `CreateIfMissing` `WOULD_INSERT` (preview) or an insert built from `InsertColumnsJson` (apply).
4. Read the current value and compare: `MATCHED`, `WOULD_UPDATE`, or an update (apply) reported `UPDATED`.
5. Report one row per instance and rule (status only); fail at the end if any row is `ERROR`.

## 4. Side effects

Updates and inserts rows in other applications' databases, directly, with no transaction and no backup. The Keycloak rows change that server's own tables, outside its admin interface.

## 5. External dependencies

Each instance's local SQL Server and databases, with Windows integrated login. [PENDING] connection encryption and certificate trust (the old script trusts any certificate).

## 6. Preview and apply

Preview reports status per rule with no values (sensitive or not). Apply consumes the fingerprint of the preview and refuses if the catalog, the package or the row counts changed.

## 7. Idempotency

A second apply reports `MATCHED`. [CONFIRMED] The old script compares only the first matching row but updates every matching row, so a table with several rows can look matched while others differ. [PROPOSED] Compare every matching row and report the number that differ.

## 8. Failures

[CONFIRMED] A database that does not exist is an `ERROR` for each of its rules (the Keycloak database may not exist yet on a clean server, since its 40 rules run at step 30 and the service starts at step 65). [PROPOSED] Check that the database and table exist first and report `SKIPPED` (as the client-secrets engine does), with a summary warning. Row-level failures are `ERROR`, the others continue, the run fails at the end.

## 9. Backup and restore

[PROPOSED] Before each change keep the previous value of the affected rows in a protected run manifest (encrypted for the machine key for sensitive rules), and make each rule's update one transaction. Restore re-applies the manifest. A database backup before the first run on a real database is a procedure, outside the engine [V].

## 10. Secret risks

- [CONFIRMED] The old script prepares a mask for sensitive rules but never uses it, because it prints no value; its error rows carry the SQL exception text, which for a key violation can include the value. [PROPOSED] Redact exception text for sensitive rules and never print values, hashes or lengths.
- **[CONFIRMED] The `FilterClause` is raw SQL text from the catalog joined into the query**, and table and column names are joined with brackets. This is the risk R-019. [PROPOSED] Replace it by a structured predicate (column, comparison, value, or a lookup of an id by another column): the 61 filters have only 7 shapes (equality on one to four columns, three of them with a lookup), so a one-off conversion is mechanical and checked by the verifier; refuse a rule whose filter does not parse; check each target table and column against the database catalog; use parameters for every value.
- [CONFIRMED] 3 rules have **no filter** (the View database `DataSource` and `ReportScriptsDefaults` tables), so they update every row. [PROPOSED] Require an explicit expected row count for a rule without a filter.

## 11. What does not port as it is

The template expansion ran in the central database through a SQL function: it moves to a tested local function (the same one `CONFIG_REPAIR` needs). The unused `SUBSTRING_REPLACE` branch (it replaces a fixed old domain pattern) is dropped, because all 61 rules are `FULL_REPLACE`. The SQL parameters and the central reads go; connections use the pinned client.

## 12. Test plan

- Runner: SQL Server LocalDB with throw-away databases that have the real table shapes; each of the 7 predicate shapes, the lookup predicate, a rule without a filter and the row-count guard, the insert path, update, multi-row mismatch, a transaction rolled back on error, quotes and special characters in values, a missing database and table (`SKIPPED`), masked sensitive output (marker), an unparsable filter refused, the instance filter.
- [V] The real databases (counts compared with a preview), and whether a changed Keycloak row takes effect on a running Keycloak.

## 13. Open questions

1. [PENDING] Convert the 61 filters to structured predicates in a conversion step (a change to the conversion tool and the catalog contract, in a separate PR). Recommendation: yes, before this engine is ported.
2. [PENDING] Keycloak data through the database or through its admin interface. Recommendation: test [V]; keep the database path only if a running Keycloak picks up the change.
3. [PENDING] Whether this engine runs at step 30 on a clean server, before the Keycloak and View databases are populated. Recommendation: skip missing databases with a warning and run the engine again after the service steps.

## Host contract

- Engine class: `MUTATING`.
- Credential references: `MOBILE_APP_TOKEN.*`.
