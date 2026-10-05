# Per-machine catalog schema

**Status:** [PROPOSED] draft, version `0.1-proposed`. Only the frame is defined here. The table-by-table content is [PENDING] the conversion plan (`docs/migration/catalog-conversion-plan.md`, task 4 step A) and ADR-0007 (proposed, PR #11).
Tags: [CONFIRMED] owner decision; [PROPOSED] draft; [PENDING] open decision.

## 1. What a catalog is

- [CONFIRMED] A SQLite file, read-only for the application, one file per existing machine (`ServerCode`), named `catalog-<ServerCode>.db`. Each instance appears in exactly one catalog.
- [CONFIRMED] Replaces the central database `_sisqualMANAGEMENT`, which ceases to exist. No runtime sync, no connection to any server to obtain configuration.
- [CONFIRMED] No secrets, no job history, no housekeeping artifacts, no stored engine scripts (engines become files). Secret-bearing surfaces never enter a catalog (R-026).
- [PROPOSED] Created with the pinned `sqlite3.exe` 3.53.4, so no managed SQLite provider is needed to build it (the provider is decided in Phase 1B and only has to open files read-only).
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
| `cut_rule_version` | INTEGER NOT NULL | Version of the per-machine cutting rules used by the conversion tool |

`schema_version`, `server_code` and `built_at_utc` must agree with the package manifest; any difference is an integrity error and the application refuses to start (except with the logged development flag).

## 3. Conventions for all tables [PROPOSED]

- Text is UTF-8. Dates and times converted from SQL Server `datetime2` are ISO 8601 text kept exactly as in the source, WITHOUT a time zone: the source values come from `SYSDATETIME()` (server local time), so they are not UTC and must not be treated as UTC. Only values created by the new tools (`built_at_utc`, manifest times) are UTC with a `Z`. See `docs/migration/catalog-conversion-plan.md` section 1.1.
- Booleans (SQL Server `bit`) are INTEGER 0 or 1 with a `CHECK`.
- Identity columns keep their source values so that origin and destination rows can be compared by key.
- Binary content (`varbinary`) is stored as BLOB in every catalog (owner answer of 2026-10-05), together with its SHA-256 column where the source has one; BLOBs are read on demand. Secret-bearing binary content never enters a catalog.
- Foreign keys are declared and checked at build time (`PRAGMA foreign_key_check` must return no rows).
- Every table that is cut per machine carries the key it is cut by (`ServerCode` or `InstanceCode`) so completeness of the cut can be tested.

## 4. Global versus cut tables

[PENDING] The assignment of each source table to "global (identical in every catalog)" or "cut by ServerCode/InstanceCode" is produced by the conversion plan and then copied here as a table. Examples named by the owner as global: applications, rules, policies, action definitions.

## 5. Open items

- [PENDING] Final table list and DDL (conversion plan).
- [PENDING] Whether the long-term authority for the catalog is a declarative source in this repository compiled by a build tool, or an editor tool (deferred by the owner, ADR-0007 item 1).
- [CONFIRMED] Machines without policy rows in the server policy tables are cut as they are (empty tables, no template server); see the conversion plan section 2.6.
- [PENDING] Behaviour for machines that have no local database: not decided, nothing is assumed here.
- [PENDING] Whether a package contains one catalog or all catalogs (see the manifest schema).
