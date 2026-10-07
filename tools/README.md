# tools/

Separate, on-demand tools run by a person. They are NOT part of the portable application
and are never shipped inside it. All of them run on the latest PowerShell (7), as decided by
the owner on 2026-10-05, and follow `docs/migration/catalog-conversion-plan.md`.

Status: [PROPOSED]. Step B of the conversion plan plus the approved follow-up tools, one small PR per tool.

| Tool | Step | State |
|---|---|---|
| `Export-ManagementEngines.ps1` | B1 | exports the `ops.Engine` scripts to files plus a hash manifest |
| `Convert-ManagementDb.ps1` | B2 | new-machine mode (global tables copied, cut tables empty, one ManagedServer row), redaction of literal secrets, safety-net scan, `.db` built with the pinned `sqlite3`; text is stored byte-exact (case and line endings unchanged), code columns compare exactly unless `-CodeCollation NoCase` |
| `Convert-ManagementDb.ps1` | B3 + C1/C2 | cut mode (default) - one catalog per existing machine of `dbo.ManagedServer`, each instance in exactly one catalog, orphans dropped and reported, completeness recorded in the manifest; C1/C2 additionally derives `cfg_LinksPageDirectory` from the full source for general Links pages, with seven public columns only, and records `linksPageDirectoryCount`; a machine without an enabled general page gets an empty directory |
| `Test-CatalogConversion.ps1` | B4 + C8 + C1/C2 | read-only verification of the catalogs against the source in ten groups (manifest, sqlite, exclusions, values, cut, global, secrets, stored-hash, action-xref, instance-directory); `instance-directory` independently recomputes `cfg_LinksPageDirectory`, checks its exact public shape and rows, the local-instance exclusion and the empty-directory rule; `action-xref` validates exact `cfg_ConfigurationAdapterDefinition.ActionCode -> ops_Action.ActionCode` and `ops_Action.EngineCode -> ops_Engine.EngineCode` references while allowing NULL/blank optional references; compares every cell, never prints a value; exit code 1 on any failure |
| `Seal-Package.ps1` | B5 | validates the catalog, rehashes every file, writes `package-manifest.json`, has it signed by an external signer (no algorithm in the tool); `-VerifyOnly`, `-DryRun`, `-Unsigned` (development) |
| credential tool (vault, issuer key, signer, import, issue) | B6 | in progress. Done: the shared module `modules/Sisqual.Credentials` (canonical JSON, signature, credential entries, package and machine identity formats, the eight-check validator, issuer public key text); the encrypted vault with the issuer key inside (`tools/lib/Sisqual.CredentialVault.psm1`) and, since B6.3a, its secrets model (derived references, salted fingerprints, access log); the importer `Import-CredentialsToVault.ps1` of B6.3b (DryRun by default, all-or-nothing Import, Verify), tested on LocalDB with the real certificate, key and procedures; the vault command `Invoke-CredentialVault.ps1` (Init, Info, ExportIssuerKey, Backup, Restore), the signer `Sign-PackageManifest.ps1` and the verifier `Verify-PackageSignature.ps1` for `Seal-Package`. Still to do: the run of the importer against the real database (owner, DryRun first) and the per-machine package issue (B6.4) |
| `Apply-CatalogChange.ps1` | C9 | offline owner tool for a structured `contracts/catalog-change.schema.json` proposal; no raw SQL, exact base-catalog SHA-256 and PK/expected-state checks, edit on a temporary copy, B5 catalog validation, baseline copy, atomic replacement; it does not reseal |

The C1/C2 directory is derived catalog data, not a 63rd SQL Server source table. It contains only `InstanceCode`, `ServerCode`, `CountryCode`, `CustomerCode`, `CustomerName`, `HostName` and public `AssignedUserName` (`LinksAssignedUserName`). It never carries tokens, passwords, database/SQL configuration, ports or paths. `CustomerCode` and `CustomerName` preserve source NULL values. On the isolated C1/C2 branch the catalog schema remains v1 and the real directory-enabled cut uses `cut_rule_version=2`; later C7 integration owns the schema-v2 transition.

Rules for every tool: read-only toward SQL Server, no secret is ever printed or written,
ASCII and LF in the repository, output outside the repository when it is not ASCII/LF,
and a unit test in `tests/Unit/` that needs no real server.

Run the tests: `pwsh -NoProfile -File tests/Unit/Test-ExportManagementEngines.ps1`; converter, directory, seal and C9 tests need `SQLITE3_PATH` pointing to the pinned sqlite3 executable (`Test-ConvertManagementDb.ps1`, `Test-LinksPageDirectory.ps1`).


## C9 catalog change flow

`Apply-CatalogChange.ps1` is the implementation of the accepted C9 / `LINKS_VISIBILITY` option A owner-edit step. It is not part of the runtime and it never updates `package-manifest.json`.

1. Generate or review a structured proposal that matches `contracts/catalog-change.schema.json`. The proposal is bound to the exact catalog by `catalogServerCode` and `baseCatalogSha256`.
2. Run `Apply-CatalogChange.ps1 -DryRun`. This validates the current catalog, proposal schema/rules and exact live schema/primary keys, then executes the proposal on a same-volume temporary copy. It requires every operation to affect exactly one row and runs the same B5 catalog safety checks as apply. The temporary copy is discarded; the catalog and baseline are not written.
3. For apply, choose a new `-BaselinePath` outside the package and confirm interactively or pass `-Yes`. The tool repeats the same staged execution and validation, writes a byte-exact baseline at a new path it will not overwrite, rechecks the source SHA-256 and atomically replaces the catalog.
4. The package is now intentionally **unsealed**: its old manifest still hashes the old catalog. Run `Seal-Package.ps1` with that baseline and the normal signer/confirmation flow. In production the approved second-reader procedure applies before the seal.
5. Keep the proposal, baseline according to the operational retention policy, and the external seal log as the review/audit trail. Do not hand-edit the derived `cfg_LinksPageDirectory`; cross-machine directory changes are handled by reconversion/reseal of all affected catalogs.

C9 V1 supports TEXT, INTEGER/bit and NULL cell values. REAL and BLOB edits are refused. `catalog_meta`, SQLite internal tables, the derived Links directory, secret tables and forbidden secret/script columns cannot be edited. UPDATE and DELETE require an `expected` object, and UPDATE must state the same non-key columns in `expected` and `values` so the diff is explicit and reviewable.

Signing: `Seal-Package.ps1` has no signature algorithm and never sees a private key. It passes the canonical bytes of the manifest to a signer script (`-SignerScript`, provided by the credential tool, step B6) and stores what it returns; a verifier script (`-VerifierScript`) is used by `-VerifyOnly`. C9 does not alter that integrity model.
