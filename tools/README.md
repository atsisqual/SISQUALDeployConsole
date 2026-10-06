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
| `Seal-Package.ps1` | B5 | this PR: validates the catalog, rehashes every file, writes `package-manifest.json`, has it signed by an external signer (no algorithm in the tool); `-VerifyOnly`, `-DryRun`, `-Unsigned` (development) |
| credential tool (vault, issuer key, signer, import, issue) | B6 | in progress: B6.1a is the shared module `modules/Sisqual.Credentials` (canonical JSON, signature, credential entries); B6.1b adds the package and machine identity formats and the validation of the eight checks; B6.2a adds the encrypted vault (`tools/lib/Sisqual.CredentialVault.psm1`) with the issuer key inside it; the vault command, the signer and verifier scripts for `Seal-Package`, the one-time import and the issue follow in small PRs |

Rules for every tool: read-only toward SQL Server, no secret is ever printed or written,
ASCII and LF in the repository, output outside the repository when it is not ASCII/LF,
and a unit test in `tests/Unit/` that needs no real server.

Run the tests: `pwsh -NoProfile -File tests/Unit/Test-ExportManagementEngines.ps1`; the converter tests need `SQLITE3_PATH` (the pinned sqlite3 executable): `pwsh -NoProfile -File tests/Unit/Test-ConvertManagementDb.ps1`.

Signing: `Seal-Package.ps1` has no signature algorithm and never sees a private key. It passes the canonical bytes of the manifest to a signer script (`-SignerScript`, provided by the credential tool, step B6) and stores what it returns; a verifier script (`-VerifierScript`) is used by `-VerifyOnly`. The algorithm and the canonical form are [PENDING] owner approval (`contracts/credential-package.md`, Q2). The tests use a throw-away ECDSA key created by the test itself.
