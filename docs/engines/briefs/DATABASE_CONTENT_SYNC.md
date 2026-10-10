# DATABASE_CONTENT_SYNC port brief

**Status:** [PROPOSED]
**Task:** T10 / M3.6
**Date:** 2026-10-10

This brief defines the implementation gate for `DATABASE_CONTENT_SYNC`. It is documentation only.

## 1. Sources and evidence boundary

[CONFIRMED] Checked now against `main`:

- `docs/engines/DATABASE_CONTENT_SYNC.md` documents source-era `DATABASE_CONTENT_SYNC.ps1`, action `DATABASE_SETTINGS`, the older `dbo.SyncDatabaseSettings` behavior and the owner-approved absorption of the retired `DATABASE_SETTINGS` engine.
- Owner decision Q3 (2026-10-06): there is no autonomous `DATABASE_SETTINGS` port. Its 14 rules are represented one-for-one in the newer database-object rule model; action `DATABASE_SETTINGS` executes `DATABASE_CONTENT_SYNC`.
- C7 is **already implemented**, not pending: catalog schema version 2 replaces raw `cfg.DatabaseObjectSettingRule.FilterClause` with `FilterPredicateJson`; unsupported filters fail conversion; the raw SQL filter is not carried. `contracts/catalog-schema.md`, converter and tests enforce this.
- The current specification records 61 enabled database-object rules, including 40 Keycloak, 18 WFM and 3 View rules in the reference snapshot.

[NOT VERIFIED] This brief did not execute the 61 rules against real WFM/View/Keycloak databases. Real SQL encryption/certificate topology and Keycloak runtime/cache behavior remain `[V]`.

## 2. Purpose and class

[CONFIRMED] `DATABASE_CONTENT_SYNC` is `MUTATING`. It makes approved rows/columns in each instance's application databases equal to the catalog rule model, inserting a row only where the rule explicitly allows creation.

[CONFIRMED] Action `DATABASE_SETTINGS` runs this engine at step 30 of `FULL_DEPLOYMENT`. The legacy engine/table do not reappear in V1.

## 3. Portable rule model

[CONFIRMED] The portable catalog uses `cfg_DatabaseObjectSettingRule` with structured `FilterPredicateJson`. Code must consume the structured predicate grammar from `contracts/catalog-schema.md`; it must never evaluate or reconstruct arbitrary SQL text from catalog data.

The engine also uses approved rule metadata such as setting code, target database/schema/table/column, expected template, create-if-missing/insert data, sensitivity and ordering. Every identifier is checked against an allowlisted catalog/database schema before it is quoted as an identifier; every data value is a SQL parameter.

[CONFIRMED] An empty legacy filter is represented explicitly as structured `ALL`, not as absent SQL text. The three source-era unfiltered View rules therefore remain explicit broad-target rules and need row-count guards rather than implicit update-all behavior.

## 4. Credentials

[CONFIRMED] The credential family is `MOBILE_APP_TOKEN.<InstanceCode>` for rules whose expected value needs the mobile token.

[DECIDED 2026-10-09] `MOBILE_APP_TOKEN.*` is an allowed instance-scoped family form. A concrete member is admitted only for an enabled instance of the verified catalog.

[PROPOSED] Resolve the token only for a rule that declares/needs it. Never include token value, length, digest prefix or SQL exception text containing the value in result/log/fingerprint/backup metadata.

The other sensitive rules documented by the existing specification are integrated-security connection strings without passwords; sensitivity still requires redacted diagnostics.

## 5. Target resolution

[PROPOSED] Resolve SQL target only from the selected enabled catalog instance and approved rule database name. Caller input cannot override server/database/table/column.

Before a rule runs:

1. validate database name against the finite rule model;
2. verify database/table/column existence and expected object type;
3. compile only the approved structured predicate grammar to parameterized SQL;
4. enforce lookup predicates through separately validated identifiers and parameters;
5. refuse any unexpected predicate kind/identifier rather than falling back to text SQL.

[PENDING] Final production encryption/certificate policy must be explicit. Trust-any-certificate source behavior is not carried forward by default.

## 6. Template expansion

[CONFIRMED] Existing rules use instance-derived host, culture, SQL-instance/database tokens and, for one rule, mobile token data.

[PROPOSED] Use one tested local template-expansion implementation shared with other engines where contracts match. Expansion is deterministic; unresolved required tokens produce `EXPECTED_VALUE_UNAVAILABLE` before any write. Secret substitutions occur only in memory after the non-secret plan has identified the rule.

## 7. Preview

For every selected instance/rule, preview must determine without mutation:

- target database/table/column is available;
- structured predicate resolves to the expected row set;
- current row count versus explicit expected constraints;
- whether a row may be inserted;
- whether **every** matching row equals the expected value.

[CONFIRMED, source-era defect] The old implementation could compare only the first matching row and then update all matches. V1 must inspect all matching rows and report differing/matched counts without exposing values.

Statuses include the source/specification concepts `MATCHED`, `WOULD_UPDATE`, `WOULD_INSERT`, required-row failure and expected-value-unavailable, with exact final names bound to the engine result contract.

## 8. Missing databases and clean-server order

[CONFIRMED] Source behavior treated a missing database as an error for each rule. The existing portable specification proposes `SKIPPED` with warning because Keycloak/View may not yet exist on a clean server at step 30.

[PENDING] Orchestration must decide this, not hide it. If missing DB is allowed at step 30, `FULL_DEPLOYMENT` must schedule a later rerun after the relevant service/database initialization and must not mark those rules completed merely because they were skipped.

## 9. Apply and transaction boundaries

[PROPOSED] APPLY consumes the confirmed fingerprint, rechecks row identity/count/current state and mutates one rule atomically:

- `UPDATE`: all and only rows selected by the confirmed structured predicate;
- `INSERT`: only when `CreateIfMissing` and approved insert-column data allow it;
- transaction rollback on any rule-level write/postcondition failure;
- independent rules may continue after a failure where transaction/target isolation is clear, but overall run fails on blocking errors.

After commit, re-read the selected rows and verify exact equality/count constraints. A second run must be all matched.

## 10. Broad-target `ALL` predicates

[CONFIRMED] Source evidence has three rules with no legacy filter, converted to explicit `ALL` predicates.

[PROPOSED] Every `ALL` rule needs an explicit approved row-count expectation/range before APPLY. Preview reports row count. APPLY refuses if current count differs from the confirmed plan or allowed count. This prevents an unexpected newly-added row from being silently overwritten.

## 11. Backup and restore

Previous database values can include sensitive content.

[PROPOSED] If row rollback is supported, write before-images into a machine-protected encrypted run artifact keyed by stable target identity, not ordinary JSON/log output. Record only non-secret target/count/hash-of-structure metadata in the normal result. Restore is parameterized and verifies row identity and restored values.

[V] A database-level backup before first production use is an operator procedure, not something this engine silently creates/deletes.

## 12. Keycloak direct-database caveat

[CONFIRMED] Forty reference rules target Keycloak tables directly. This bypasses the Keycloak Admin API.

[V] Prove whether a running Keycloak observes each changed category without restart/cache refresh. Until then `UPDATED` means database state verified, not necessarily runtime state consumed.

## 13. Result/failure semantics

[PROPOSED] One row per instance/rule with setting code, non-secret target identity, matching/differing row counts and status. Never include values.

Blocking errors include invalid structured predicate, unapproved identifier, target schema mismatch, required rows absent, row-count drift, SQL/permission failure, transaction/postcondition failure and unresolved required value/credential. Sensitive SQL exception text is normalized/redacted.

## 14. Required tests

Runner/LocalDB or SQL Server coverage must include:

- all seven C7 predicate shapes and structured lookups;
- prove no `FilterClause`/raw catalog SQL is consumed;
- unsupported predicate kind/identifier fails closed;
- all 14 absorbed legacy setting rules represented through the new rule model;
- each target database/table family used by reference rules;
- missing DB/table/column behavior;
- required row missing and create-if-missing insert;
- `ALL` predicate row-count guard;
- multi-row mixed matched/different case catches every differing row;
- transaction rollback on write/postcondition error;
- quotes/Unicode/SQL metacharacters remain parameters;
- `MOBILE_APP_TOKEN` exact selected-instance resolution and missing token;
- marker token absent from every ordinary artifact/exception;
- preview no-write, fingerprint drift and row-count drift refusal;
- idempotent second APPLY;
- protected rollback artifact if row rollback is implemented.

[V] Real WFM/View/Keycloak preview counts, SQL encryption/certificates and Keycloak runtime pickup.

## 15. Open questions

1. [CLOSED] C7 structured predicate conversion is already implemented; do not reopen raw `FilterClause` as an engine design choice.
2. [PENDING] Missing-database semantics and required rerun point in clean-server orchestration.
3. [PENDING] Keycloak direct DB versus Admin API/runtime refresh behavior.
4. [PENDING] Production SQL encryption/certificate policy.
5. [PENDING] Explicit row-count expectations for the three `ALL` predicate rules.
6. [PENDING] Protected row rollback retention/ACL policy.

## 16. Entry gate for the code PR

The code PR may start when:

- it targets catalog schema v2+ structured predicates and contains no raw-filter execution path;
- all target identifiers/rule columns used by code are confirmed in the catalog contract;
- the 14 absorbed `DATABASE_SETTINGS` behaviors are mapped to the newer rules/tests;
- `ALL` row-count policy is explicit;
- missing-database clean-server orchestration is decided or represented as an explicitly incomplete state;
- SQL encryption policy is set for production validation;
- sensitive diagnostics/rollback never create an unprotected secret store.
