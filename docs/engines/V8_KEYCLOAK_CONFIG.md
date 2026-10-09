# Engine port specification: V8_KEYCLOAK_CONFIG

**Status:** [PROPOSED] specification for review (task 3, wave 8). No product code.
**Owner decision (2026-10-06, Q3):** this engine is **not ported as an autonomous engine**. Its behaviour, pointing each instance's Keycloak at the SQL Server of the machine by rewriting `db-url` in `conf\keycloak.conf`, is absorbed by the `CONFIG_REPAIR` rule `KEYCLOAK_DB_URL` (specification `docs/engines/CONFIG_REPAIR.md`). **There is no functional loss.** Verified by the reviewer in the reference snapshot on 2026-10-06: the rule is enabled, belongs to the application `KEYCLOAK`, targets `conf\keycloak.conf`, selects the line `db-url=jdbc:sqlserver://...` and writes the database address from the instance's SQL instance name; the only step of this engine in `FULL_DEPLOYMENT` (63) is disabled. [CONFIRMED] The template of the rule carries `trustServerCertificate=true`; this decision does not change that value, and hardening it is a separate item.
**Date:** 2026-10-05
**Sources (read only):** `ops.Engine` row `V8_KEYCLOAK_CONFIG` of `database/sync/ManagementSync.sql` of `atsisqual/SISQUALManagementConsole` (file `V8_KEYCLOAK_CONFIG.ps1`, version `v3`, Windows PowerShell 5.1, requires administrator, stored `ScriptSha256` `BC604D4B...`; reference head `9756ba956842884fabcf25b82c4fbf1d11cf56bd`); the action `V8_KEYCLOAK_CONFIG` (step 63 of `FULL_DEPLOYMENT`, disabled) and the `CONFIG_REPAIR` rules of the Keycloak configuration file; the specification of `CONFIG_REPAIR` (wave 2, PR #32). Script text is not copied and no secret value appears here.
Tags: [CONFIRMED] read in the source; [PROPOSED] recommendation; [PENDING] needs a decision; [V] needs a real server.

## 1. Purpose

Point each instance's Keycloak server at the SQL Server of this machine by rewriting the database address in its configuration file. [CONFIRMED] Action: group `INFRASTRUCTURE`, preview and apply, all enabled instances, hidden from the menu. **Its step in `FULL_DEPLOYMENT` (63) is disabled**, and the roadmap keeps it disabled.

## 2. Inputs

`dbo_ManagedInstance` (enabled instances with Keycloak ports: all 76; host name, SQL instance name) and `dbo_ManagedServer` (machine name). The configuration file is at a fixed path under the instance's V8 folder.

## 3. Steps

For each instance: if the configuration file does not exist, `SKIPPED` ("not physically deployed yet"). If the file already contains the machine name anywhere, `OK`. Otherwise preview says `WOULD_UPDATE`; apply replaces the host (and the SQL instance name) in the database URL with the local machine and instance, and writes the file back, `UPDATED`.

## 4. Side effects

Rewrites one configuration file per instance, in place. [CONFIRMED] No backup, no atomic write; the file is written with the default text encoding of the PowerShell version (which re-encodes it) and without a final newline.

## 5. Defects [CONFIRMED]

1. The "already correct" test is a substring match of the machine name anywhere in the file, so a host name or comment containing it hides a wrong database address.
2. The replacement changes only the host and instance parts of the URL; the other settings of the URL are left as they are.
3. With no instance given the query filters on the server name of the central database connection, not on the machine being configured; with an instance given it does not filter by machine at all.
4. Fixed folder paths; no `ServicesRoot` from the catalog.

## 6. Covered by another engine

[CONFIRMED] `cfg_ConfigRule` has the rule `KEYCLOAK_DB_URL` (group `KEYCLOAK`, a text rule on the same `conf\keycloak.conf`, not sensitive) whose template sets the whole database setting from the instance's SQL instance name, with the database name, integrated security, encryption and timeout. The same file has 7 more rules (host name, three ports, administrator name and password, key store password). `CONFIG_REPAIR` therefore already does everything this engine does, with preview, backup, atomic write, encoding preservation and a verification pass.

## 7. Recommendation

[PROPOSED] **Do not port this engine.** Retire it: keep the action disabled and hidden until the owner confirms, then remove the action, the engine row and the disabled step 63 from the catalog in a separate change. The behaviour is provided by `CONFIG_REPAIR` with the rule `KEYCLOAK_DB_URL`. A decision of 2026-10-05 puts all engines in the V1 scope; this is a proposal to treat this one as already delivered by another, to be confirmed by the owner.

## 8. Idempotency, failures, backup and restore, preview and apply

Not applicable to a retired engine; the behaviour of `CONFIG_REPAIR` applies (its specification, PR #32).

## 9. Secret risks

None in this engine. The same configuration file holds secrets (the administrator and key store passwords): their handling is in the `CONFIG_REPAIR` specification (redaction, restricted backups).

## 10. Test plan

- Runner: through the `CONFIG_REPAIR` tests, add cases for the `KEYCLOAK_DB_URL` rule: a file with no URL, with another host, with another instance name, with extra URL options, with the machine name in a comment, with different encodings and line endings, and a second apply with no change. Compare with the result the old regular expression gives, so that nothing it handled is lost.
- [V] One real Keycloak configuration file of a moved environment.

## 11. Open questions

1. [DECIDED 2026-10-06, owner Q3] The retirement is confirmed. The catalog change that removes the action, the engine row and step 63 is a separate change (roadmap follow-ups).
2. [PENDING] The case this engine seems to serve, repointing the database after an environment is moved to another machine. Confirm that `CONFIG_REPAIR` run on the new machine is the intended way (recommended).
3. [PENDING] Whether the host name rule and the port rules are all expected to stay in sync with the instance data (they are, by the same engine).

## Host contract

- Engine class: `N/A - RETIRED / not an active host target`.
- `V8_KEYCLOAK_CONFIG` is not ported as an autonomous engine. Its behavior is absorbed by `CONFIG_REPAIR`; engine-host class gates do not apply and no standalone module should be created or invoked.
- Credential references: none.
