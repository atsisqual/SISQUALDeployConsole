# tools/

Separate, on-demand tools run by a person. They are NOT part of the portable application
and are never shipped inside it. All of them run on the latest PowerShell (7), as decided by
the owner on 2026-10-05, and follow `docs/migration/catalog-conversion-plan.md`.

Status: [PROPOSED]. Step B of the conversion plan, one small PR per tool.

| Tool | Step | State |
|---|---|---|
| `Export-ManagementEngines.ps1` | B1 | this PR: exports the `ops.Engine` scripts to files plus a hash manifest |
| `Convert-ManagementDb.ps1` | B2 | new-machine mode (global tables copied, cut tables empty, one ManagedServer row), redaction of literal secrets, safety-net scan, `.db` built with the pinned `sqlite3`; text is stored byte-exact (case and line endings unchanged), code columns compare exactly unless `-CodeCollation NoCase` |
| `Convert-ManagementDb.ps1` | B3 + C1/C2 | cut mode (default) - one catalog per existing machine, each complete instance in exactly one catalog, orphans dropped/reported; C1/C2 additionally derives `cfg_LinksPageDirectory` from the full source for general Links pages, with seven public columns only, and records `linksPageDirectoryCount`; a machine without an enabled general page gets an empty directory |
| `Test-CatalogConversion.ps1` | B4 + C1/C2 | read-only verification against the source; the proven B4 groups compare every source-carried cell and never print values, while C1/C2 independently recomputes `cfg_LinksPageDirectory`, checks its exact public shape/rows, local-instance exclusion and empty-directory rule; exit code 1 on any failure |
| `Seal-Package.ps1` | B5 | validates the catalog, rehashes every file, writes `package-manifest.json`, has it signed by an external signer (no algorithm in the tool); `-VerifyOnly`, `-DryRun`, `-Unsigned` (development) |
| credential tool (vault, issuer key, signer, import, issue) | B6 | in progress: B6.1a is the shared module `modules/Sisqual.Credentials` (canonical JSON, signature, credential entries); B6.1b adds the package and machine identity formats and the validation of the eight checks; B6.2a adds the encrypted vault (`tools/lib/Sisqual.CredentialVault.psm1`) with the issuer key inside it; the vault command, the signer and verifier scripts for `Seal-Package`, the one-time import and the issue follow in small PRs |

The C1/C2 directory is derived catalog data, not a 63rd SQL Server source table. It contains only `InstanceCode`, `ServerCode`, `CountryCode`, `CustomerCode`, `CustomerName`, `HostName` and public `AssignedUserName` (`LinksAssignedUserName`). It never carries tokens, passwords, database/SQL configuration, ports or paths. `CustomerCode` and `CustomerName` preserve source NULL values. On the isolated C1/C2 branch the catalog schema remains v1 and the real directory-enabled cut uses `cut_rule_version=2`; later C7 integration owns the schema-v2 transition.

Rules for every tool: read-only toward SQL Server, no secret is ever printed or written,
ASCII and LF in the repository, output outside the repository when it is not ASCII/LF,
and a unit test in `tests/Unit/` that needs no real server.

Run the tests: `pwsh -NoProfile -File tests/Unit/Test-ExportManagementEngines.ps1`; converter/directory tests need `SQLITE3_PATH` (the pinned sqlite3 executable): `pwsh -NoProfile -File tests/Unit/Test-ConvertManagementDb.ps1` and `pwsh -NoProfile -File tests/Unit/Test-LinksPageDirectory.ps1`.

Signing: `Seal-Package.ps1` has no signature algorithm and never sees a private key. It passes the canonical bytes of the manifest to a signer script (`-SignerScript`, provided by the credential tool, step B6) and stores what it returns; a verifier script (`-VerifierScript`) is used by `-VerifyOnly`. The algorithm and the canonical form are [PENDING] owner approval (`contracts/credential-package.md`, Q2). The tests use a throw-away ECDSA key created by the test itself.
