# tools/

Separate, on-demand tools run by a person. They are NOT part of the portable application
and are never shipped inside it. All of them run on the latest PowerShell (7), as decided by
the owner on 2026-10-05, and follow `docs/migration/catalog-conversion-plan.md`.

Status: [PROPOSED]. Step B of the conversion plan, one small PR per tool.

| Tool | Step | State |
|---|---|---|
| `Export-ManagementEngines.ps1` | B1 | this PR: exports the `ops.Engine` scripts to files plus a hash manifest |
| `Convert-ManagementDb.ps1` | B2, B3 | not started |
| `Test-CatalogConversion.ps1` | B4 | not started |
| seal tool | B5 | not started |
| vault import and credential issue | B6 | not started; needs the credential contract questions answered |

Rules for every tool: read-only toward SQL Server, no secret is ever printed or written,
ASCII and LF in the repository, output outside the repository when it is not ASCII/LF,
and a unit test in `tests/Unit/` that needs no real server.

Run the tests: `pwsh -NoProfile -File tests/Unit/Test-ExportManagementEngines.ps1`
