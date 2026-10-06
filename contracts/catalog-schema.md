# Per-machine catalog schema

**Status:** [PROPOSED] draft, version `0.2-proposed`. C7 adds the structured database-content predicate contract. The remaining table-by-table content still follows the conversion plan (`docs/migration/catalog-conversion-plan.md`) and ADR-0007.
Tags: [CONFIRMED] owner decision; [PROPOSED] draft; [PENDING] open decision.

## 1. What a catalog is

- [CONFIRMED] A SQLite file, read-only for the application, one file per existing machine (`ServerCode`), named `catalog-<ServerCode>.db`. Each instance appears in exactly one catalog.
- [PLANNED, 2026-10-05] Exception for links pages: a catalog that hosts a general links page also carries a read-only directory of the instances of other machines (public columns only), because the general page lists every enabled instance of the same country across all machines (`cfg.GetLinksPageItemPlan`). The directory is a separate table; the rule above is about the full instance rows.
- [CONFIRMED] Replaces the central database `_sisqualMANAGEMENT`, which ceases to exist. No runtime sync, no connection to any server to obtain configuration.
- [CONFIRMED] No secrets, no job history, no housekeeping artifacts, no stored engine scripts. Secret-bearing surfaces never enter a catalog (R-026).
- [PROPOSED] Created with the pinned `sqlite3.exe` 3.53.4; the runtime provider only has to open files read-only.
- [PROPOSED] Opened with a read-only URI and `PRAGMA query_only = ON`. The file is listed with its SHA-256 in the signed package manifest.

## 2. Mandatory metadata table

[PROPOSED] Every catalog contains exactly one row in `catalog_meta`:

| Column | Type | Rule |
|---|---|---|
| `meta_id` | INTEGER PRIMARY KEY | Always 1 (`CHECK (meta_id = 1)`) |
| `schema_version` | INTEGER NOT NULL | Same as `catalog.schemaVersion` in the package manifest |
| `server_code` | TEXT NOT NULL | The ServerCode this catalog was cut for |
| `source_kind` | TEXT NOT NULL | `conversion-tool`, `manual-edit-sealed` or `build` |
| `source_reference` | TEXT NOT NULL | Conversion run id, repository commit or seal note; ASCII, no secrets |
| `built_at_utc` | TEXT NOT NULL | `YYYY-MM-DDTHH:MM:SSZ`, shown in the UI |
| `cut_rule_version` | INTEGER NOT NULL | Version of the per-machine cutting/transformation rules |

Catalog schema version **2** is the first version with C7 structured database filters. `schema_version` and `server_code` must agree with the package manifest, and `source_kind` must equal the manifest's `catalog.origin`; any difference is an integrity error.

## 3. Conventions for all tables [PROPOSED]

- Text is stored byte-exact: case and line endings are never changed. All text columns, including `*Code`, compare exactly (`BINARY`) unless the converter is explicitly run with `-CodeCollation NoCase`.
- `dbo_ManagedServer` has no `ManagementDatabaseName` column.
- Text is UTF-8. SQL Server local `datetime2` values remain timezone-less ISO text; only values created by new tools and explicitly named UTC carry `Z`.
- SQL Server `bit` is INTEGER 0 or 1 with a `CHECK`.
- Identity values are preserved.
- Binary content is BLOB; secret-bearing binary content never enters a catalog.
- Foreign keys are checked at build time.
- Every machine-cut table carries the key used to cut it.

## 4. Structured database-content predicates (C7)

[CONFIRMED, owner decision] Runtime code must never execute the source `cfg.DatabaseObjectSettingRule.FilterClause` as SQL text. The Portable representation is zero or more column/value equality predicates joined only by `AND`; conversion is one-way and fail-closed.

For catalog schema version 2:

- source `cfg.DatabaseObjectSettingRule.FilterClause` is **not present** in `cfg_DatabaseObjectSettingRule`;
- the destination has `FilterPredicateJson TEXT NOT NULL`;
- an empty/null source filter becomes exactly an explicit `ALL` predicate;
- a non-empty source filter must parse completely into equality terms joined by `AND`; otherwise conversion stops before a catalog is accepted;
- the conversion manifest records that raw filter SQL is not carried.

### 4.1 JSON grammar

An unfiltered rule is:

```json
{"kind":"ALL"}
```

A filtered rule is:

```json
{"kind":"AND","terms":[{"column":"ColumnName","operator":"EQ","value":{"kind":"LITERAL","type":"TEXT","value":"value"}}]}
```

`terms` contains one or more equality comparisons; the current converter applies a defensive maximum of 16. `operator` is currently only `EQ`. Literal `type` is `TEXT` or `NUMBER`; numeric values are stored as invariant text so conversion does not silently change precision.

There is no subquery, lookup, expression or free-SQL node in the C7 contract.

### 4.2 Approved snapshot reconciliation

The approved baseline contains exactly seven `cfg.DatabaseObjectSettingRule` rows. Three are intentionally unfiltered and therefore convert to `ALL`:

- `SISQUAL_VIEW_DATASOURCE_CONNECTION`
- `SISQUAL_VIEW_REPORT_DEFAULT_CONNECTION`
- `SISQUAL_VIEW_REPORT_DEFAULT_WFM_DATABASE`

The four populated filters convert to the following ordered equality predicates:

| SettingCode | Equality predicates joined by `AND` |
|---|---|
| `SISQUALPONTO_LANGUAGE_LOGIN` | `Aplicacao = 'SisqualPonto'`; `Seccao = 'Parametros'`; `Chave = 'LanguageLogin'` |
| `SISQUALPONTO_LANGUAGE_TRANSLATION` | `Aplicacao = 'SisqualPonto'`; `Seccao = 'Parametros'`; `Chave = 'LanguageTranslation'` |
| `PAPERLESS_LANGUAGE_ID` | `Aplicacao = 'sisqualPAPERLESS'`; `Seccao = 'Geral'`; `Chave = 'LanguageID'` |
| `DASHBOARDS_DATA_CONNECTION` | `id = 'AD704BE6-AE67-43E3-BDB2-A89AEEEA2900'` |

Bracketed identifiers and T-SQL `N'...'` string literals are accepted as syntax variants of the same equality-only grammar. Doubled single quotes decode to one quote.

The converter rejects, rather than preserves or executes, every construct outside that grammar, including `SELECT`/subqueries, `OR`, `LIKE`, `IN`, functions/expressions, non-equality comparisons, comments, statement terminators, parentheses and trailing SQL. The complete input must be consumed by the parser.

### 4.3 Runtime consumption

The future `DATABASE_CONTENT_SYNC` engine must validate target database/table/column identifiers against database metadata and compile this structure into parameterized SQL. Literal values must be SQL parameters; JSON text must never be concatenated back into executable SQL. `ALL` means an intentionally unfiltered rule and must remain subject to the engine's separate row-count guard.

The textual GUID used by `DASHBOARDS_DATA_CONNECTION` remains text in the C7 catalog representation. Its SQL parameter type is selected by the future engine from the real destination column metadata; C7 does not infer SQL type from the column name.

## 5. Global versus cut tables

[PENDING] The assignment of each source table to global or machine-cut is produced by the conversion plan. C7 does not change that assignment; `cfg.DatabaseObjectSettingRule` remains global.

## 6. Open items

- [PENDING] Final table list and DDL for the remaining catalog tables.
- [PENDING] Whether the long-term authority for the catalog is declarative source in this repository or an editor tool.
- [CONFIRMED] Machines without policy rows are cut as they are (empty policy tables).
- [OBSOLETE, 2026-10-05] Machines without a local database are no longer applicable under ADR-0007.
- [PENDING] Whether a package contains one catalog or all catalogs.
