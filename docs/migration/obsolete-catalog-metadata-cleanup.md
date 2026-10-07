# Obsolete catalog metadata cleanup after C7 and C1/C2

**Status:** [CONFIRMED] implemented in PR #59; unmerged.
**Composition base:** `main@4ee2dbe9b96802c5ef9d933c77b46853dcacb500`.

This delta retires obsolete catalog metadata without replacing or reimplementing the converter/verifier layers already present on `main`.

## Layering and versions

The wrapper order is deliberately:

`Core -> C7 -> C1/C2 -> cleanup -> execution`

Each layer captures the function implementation that exists when the layer is loaded. The cleanup layer is therefore loaded after the C7 structured-filter layer and after the C1/C2 Links directory layer.

The established product versions remain unchanged:

- converter: `0.5.0`;
- verifier: `0.3.0`;
- catalog schema: `2`;
- `cut_rule_version`: `3`.

`cut_rule_version` is **not** incremented by this cleanup. Version 3 already identifies the C7 + C1/C2 machine-cut/derived-directory rule set. The cleanup changes global retirement metadata, not machine ownership, cut assignment or derived Links-directory rules. Its own audit version remains `retiredCatalogMetadata.version = 1`.

`tools/Convert-ManagementDb.Core.ps1` and `tools/Test-CatalogConversion.Core.ps1` remain exactly the files from the composition base.

## Raw legacy-filter preflight

`cfg.DatabaseSettingRule` is validation-only input. Legacy/replacement equivalence is evaluated against raw source rows **before** C7 converts `cfg.DatabaseObjectSettingRule.FilterClause` into structured predicate JSON.

The approved four-term source predicate is:

`Application = <Application> AND ISNULL([User], N'') = <SettingUser-or-empty> AND Section = <SectionName> AND [Key] = <SettingKey>`

`[User]` and `[Key]` remain mandatory delimiters. The replacement must also retain the approved target, `FULL_REPLACE`, `CreateIfMissing=1`, and the exact four-column insertion identity (`Application`, `User`, `Section`, `Key`). Any mismatch fails conversion before the legacy table can be omitted.

After that raw preflight, the normal main layers run. Cleanup is then applied as the final converter layer.

## Retirement transform

The portable catalog does not carry:

- source table `cfg.DatabaseSettingRule` (`cfg_DatabaseSettingRule` in SQLite);
- action `V8_KEYCLOAK_CONFIG`;
- engine `V8_KEYCLOAK_CONFIG`;
- legacy engine `DATABASE_SETTINGS`;
- disabled `FULL_DEPLOYMENT` step 63 -> `V8_KEYCLOAK_CONFIG`.

The retained `DATABASE_SETTINGS` action must remain enabled, map exactly once to an explicitly enabled `DATABASE_CONTENT_SYNC` engine, and remain the enabled `FULL_DEPLOYMENT` step 30.

V8 retirement remains conditional on the approved executable `KEYCLOAK_DB_URL` / `CONFIG_REPAIR` replacement contract. Residual retired identifiers are rejected under SQL Server case-insensitive/right-space-padded identifier equivalence.

The conversion manifest keeps the C7 `structuredDatabaseFilters` metadata and adds:

- `excludedTableCount = 56`;
- `retiredCatalogMetadata.version = 1`;
- excluded source table, removed action/engines/step, and retained `DATABASE_SETTINGS -> DATABASE_CONTENT_SYNC` mapping.

## Expected real-snapshot proof

The accepted baseline for `main@4ee2dbe` is owner-supplied:

- 6 catalogs;
- 76 instances;
- 16 redacted values;
- verifier: 130 passed / 6 failed;
- the six failures are the pre-existing action-xref findings.

Before PR #59 is considered proven on the real snapshot, its run must show the same catalog/instance/redaction counts, at least 130 verifier passes, exactly the same six action-xref failures and no new failures. It must additionally demonstrate:

- `cfg_DatabaseSettingRule` absent;
- `V8_KEYCLOAK_CONFIG` action absent;
- `V8_KEYCLOAK_CONFIG` engine absent;
- `DATABASE_SETTINGS` engine absent;
- `ops_Engine` row count changes from 19 to 17;
- `PRAGMA foreign_key_check` returns no rows.

Until that real-snapshot execution is actually performed on the recomposed head, it is [PENDING] evidence rather than inferred from synthetic CI.

No merge is requested by this delta.
