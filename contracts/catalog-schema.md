# Per-machine catalog schema

**Status:** [PROPOSED] draft, version `0.1-proposed`. The table-by-table source-carried content follows the conversion plan (`docs/migration/catalog-conversion-plan.md`) and ADR-0007. C1/C2 defines the derived Links instance directory without changing `schema_version`; it changes the cut rules only.
Tags: [CONFIRMED] owner decision; [PROPOSED] draft; [PENDING] open decision.

## 1. What a catalog is

- [CONFIRMED] A SQLite file, read-only for the application, one file per existing machine (`ServerCode`), named `catalog-<ServerCode>.db`. Each complete instance row appears in exactly one catalog.
- [CONFIRMED, C1/C2, 2026-10-06] A catalog whose machine hosts an enabled general Links page also carries a read-only directory of enabled instances of the same country on other enabled machines. A machine without a general page carries an empty directory. The directory is derived public data and never replaces the complete local instance row.
- [CONFIRMED] Replaces the central database `_sisqualMANAGEMENT`, which ceases to exist. No runtime sync, no connection to any server to obtain configuration.
- [CONFIRMED] No secrets, no job history, no housekeeping artifacts, no stored engine scripts. Secret-bearing surfaces never enter a catalog (R-026).
- [PROPOSED] Created with the pinned `sqlite3.exe` 3.53.4; the runtime provider only has to open files read-only.
- [PROPOSED] Opened with a read-only URI and `PRAGMA query_only = ON`. The file is listed with its SHA-256 in the signed package manifest (`package-manifest.schema.json`).

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
| `cut_rule_version` | INTEGER NOT NULL | Version of the per-machine cutting and derived-table rules |

`schema_version` and `server_code` must agree with the package manifest, and `source_kind` must equal the manifest's `catalog.origin`; any difference is an integrity error. `built_at_utc` is the time the catalog content was produced or last sealed after a manual edit; it is not required to equal the manifest's `builtAt`.

C1/C2 is additive to catalog schema v1 and therefore keeps `schema_version = 1`; it bumps `cut_rule_version` from 1 to 2. The later C7 structured-filter work has its own schema-version transition and is reconciled when the PRs are integrated.

## 3. Conventions for all tables [PROPOSED]

- Text is stored byte-exact: case and line endings are never changed. All text columns, including `*Code`, compare exactly (`BINARY`) unless the converter is explicitly run with `-CodeCollation NoCase`.
- `dbo_ManagedServer` has no `ManagementDatabaseName` column.
- Text is UTF-8. SQL Server local `datetime2` values remain timezone-less ISO text; only values created by new tools and explicitly named UTC carry `Z`.
- SQL Server `bit` is INTEGER 0 or 1 with a `CHECK`.
- Identity values are preserved.
- Binary content is BLOB; secret-bearing binary content never enters a catalog.
- Foreign keys are checked at build time.
- Every source table cut per machine carries the key used to cut it.

## 4. Derived Links instance directory (C1/C2)

[CONFIRMED, owner Q9, 2026-10-06] The derived table is `cfg_LinksPageDirectory`. It is present in every catalog but is empty when that machine has no enabled instance with `LinksIncludeAllInstances = 1` (C2).

For a catalog of machine M, the directory contains exactly the enabled instances that:

- belong to an enabled machine other than M;
- have `CountryCode` equal, under the source database's case-insensitive comparison, to the country of at least one enabled general-page instance of M;
- are not complete local instance rows of M.

Only public data used by the general Links page is copied. C1 explicitly includes `LinksAssignedUserName`, because the current public page already prints it. Tokens, passwords, database names, ports, paths, SQL configuration and other private instance data never enter this table.

`cfg_LinksPageDirectory` is `STRICT`, has no foreign key to `dbo_ManagedInstance`, and has these columns in this order:

| Column | Type source | Nullability | Rule |
|---|---|---|---|
| `InstanceCode` | `dbo.ManagedInstance.InstanceCode` | NOT NULL, PRIMARY KEY | remote instance code |
| `ServerCode` | `dbo.ManagedInstance.ServerCode` | NOT NULL | provenance; never equals `catalog_meta.server_code` |
| `CountryCode` | `dbo.ManagedInstance.CountryCode` | NOT NULL | exactly two characters |
| `CustomerCode` | `dbo.ManagedInstance.CustomerCode` | NULL | preserved; general-page ordering already handles NULL last |
| `CustomerName` | `dbo.ManagedInstance.CustomerName` | NULL | preserved; the page falls back to `InstanceCode` when absent |
| `HostName` | `dbo.ManagedInstance.HostName` | NOT NULL | non-empty; used to build links |
| `AssignedUserName` | `dbo.ManagedInstance.LinksAssignedUserName` | NULL | public display value accepted by C1 |

The nullable `CustomerCode` and `CustomerName` definitions deliberately follow the real SQL schema and the existing page behavior; the earlier design draft that marked them NOT NULL was too strict.

The conversion manifest records `linksPageDirectoryCount` per catalog. `Test-CatalogConversion` independently recomputes the expected rows and values from the source, requires the exact seven-column shape, verifies no row is local or from the catalog's own server, and requires an empty table for C2 machines without a general page.

The directory is the only derived cross-machine instance table. `cfg.Application.LinksHubInstanceCode` remains a global code string and is not resolved through this directory.

## 5. Global versus cut source tables

[PENDING] The final assignment of each source table to global or cut-by-machine is produced by the conversion plan. The Links directory is not a 63rd source table: it is derived during the cut from `dbo.ManagedServer` and `dbo.ManagedInstance`.

## 6. Open items

- [PENDING] Final source table list and DDL for the remaining catalog tables.
- [PENDING] Whether the long-term authority for the catalog is declarative source in this repository or an editor tool.
- [CONFIRMED] Machines without policy rows are cut as they are (empty policy tables).
- [OBSOLETE, 2026-10-05] Machines without a local database are no longer applicable under ADR-0007.
- [PENDING] Whether a package contains one catalog or all catalogs.
