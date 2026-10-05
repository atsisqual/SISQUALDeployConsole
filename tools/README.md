# tools/

Separate, on-demand tools run by a person. They are NOT part of the portable application
and are never shipped inside it. All of them run on the latest PowerShell (7), as decided by
the owner on 2026-10-05, and follow `docs/migration/catalog-conversion-plan.md`.

Status: [PROPOSED]. Step B of the conversion plan, one small PR per tool.

| Tool | Step | State |
|---|---|---|
| `Export-ManagementEngines.ps1` | B1 | this PR: exports the `ops.Engine` scripts to files plus a hash manifest |
| `Convert-ManagementDb.ps1` | B2 | this PR: new-machine mode (global tables copied, cut tables empty, one ManagedServer row), redaction of literal secrets, safety-net scan, `.db` built with the pinned `sqlite3`; text is stored byte-exact (case and line endings unchanged), code columns compare exactly unless `-CodeCollation NoCase` |
| `Convert-ManagementDb.ps1` | B3 | this PR: cut mode (default) - one catalog per existing machine of `dbo.ManagedServer`, each instance in exactly one catalog, orphans dropped and reported, completeness recorded in the manifest |
| `Test-CatalogConversion.ps1` | B4 | this PR: read-only verification of the catalogs against the source in eight groups (manifest, sqlite, exclusions, values, cut, global, secrets, stored-hash); compares every cell, never prints a value; exit code 1 on any failure |
| seal tool | B5 | not started |
| vault import and credential issue | B6 | not started; needs the credential contract questions answered |

Rules for every tool: read-only toward SQL Server, no secret is ever printed or written,
ASCII and LF in the repository, output outside the repository when it is not ASCII/LF,
and a unit test in `tests/Unit/` that needs no real server.

Run the tests: `pwsh -NoProfile -File tests/Unit/Test-ExportManagementEngines.ps1`; the converter tests need `SQLITE3_PATH` (the pinned sqlite3 executable): `pwsh -NoProfile -File tests/Unit/Test-ConvertManagementDb.ps1`.
