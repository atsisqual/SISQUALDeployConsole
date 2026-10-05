# Session handoff - 2026-10-05

**Purpose:** let a new Claude session (or a human) continue exactly where this session stopped, without the chat history.
**Status:** [PROPOSED] working note. It records state and method; it is not a decision record. `docs/decisions-log.md` and `docs/roadmap.md` are untouched (the reviewer records decisions).
**Contains no credentials.** The GitHub token used in this session was pasted in a chat; it must be revoked and replaced (see section 9).

Tags: [CONFIRMED] verified in this session; [PROPOSED] design proposal; [PENDING] open decision; [V] only verifiable on a real server; [NOT DONE] not done or not verified.

## 1. First ten minutes for the next session

1. The old token was still valid at the end of the session (it was used again to record the answers). Ask the owner for a NEW fine-grained GitHub token (repository access only to `atsisqual/SISQUALDeployConsole` and read access to `atsisqual/SISQUALManagementConsole`; contents, pull requests, actions read). Do not reuse the old one.
2. Read, in this order: `docs/decisions-log.md`, `docs/architecture/ADR-0001-*.md`, `ADR-0006-*.md`, the ADR-0007 branch (PR #11), `docs/roadmap.md`, and from PR #10: `AGENTS.md`, `CLAUDE.md`.
3. List open PRs (rule of the project) and the branches. Reuse an existing branch for the same work after any timeout.
4. Read `docs/migration/catalog-conversion-plan.md` (PR #14) section 8 and section 7 of this file: they hold the open decisions.
5. The owner APPROVED the plan (PR #14) on 2026-10-05 and answered: no template server and no built-in defaults (engines stop when a policy row is missing); `Microsoft.Data.SqlClient` for the SQL client; everything on the latest PowerShell (7), including CI parsing of `tools/`. Step B is in progress: see section 12.

## 2. Project in one paragraph

SISQUALDeployConsole is a Windows-only portable administration tool for SISQUAL WFM environments: copy a folder, run `Start.cmd`, install nothing, operate it in a browser on loopback. Runtime: PowerShell 7.6.6, Pode 2.14.1 (HTTP adapter only), SQLite 3.53.4 (ADR-0001, accepted). IIS is managed through `Microsoft.Web.Administration` (ADR-0006, accepted with four conditions). The current system is `atsisqual/SISQUALManagementConsole` (read-only reference) with a central SQL Server database `_sisqualMANAGEMENT`; the new tool replaces it. Repositories: `atsisqual/SISQUALDeployConsole` (this one), `atsisqual/SISQUALManagementConsole` (reference, default branch `master`), plus `Email-Availibility` and `Dashboards` (unrelated to this work).

## 3. Rules of work (from the owner)

- One branch and one PR per task, branched from `main`; no direct push to `main`; small commits; never merge (the reviewer integrates).
- List open PRs before starting each task.
- ASCII only and LF line endings in every text file; no real credentials anywhere.
- Tags `[CONFIRMED]`, `[PROPOSED]`, `[PENDING]`, `[V]`.
- Read before working: `docs/decisions-log.md`, ADR-0001, ADR-0006, `docs/roadmap.md`.
- Do not edit `docs/decisions-log.md` or `docs/roadmap.md`.
- After a timeout resume the same branch. Work in small parts and push after each part.
- At the end of each PR tell the owner the PR number and what is left to decide.

## 4. Owner decisions of 2026-10-05 that apply to the new work

- [CONFIRMED] Credentials: a SEPARATE tool under `tools/`, outside the portable application, issues a package or key valid for ONE target machine. The portable application never contacts any server for this. There is no permanent master server. The package is machine-bound, signed by the tool, imported manually as text.
- [CONFIRMED] In `docs/skills/credential-portability/SKILL.md` the phrase "trusted central signing identity" becomes "signing identity of the credential tool (separate tool)". (Done in PR #10; also fixed in `SECURITY.md`.)
- [CONFIRMED] V1 scope: all engines. Sync: SQL is read-only when a local database exists; the case of machines without a local database is undecided (assume nothing).
- [CONFIRMED] `_sisqualMANAGEMENT` ceases to exist. Configuration becomes read-only SQLite files, one per existing machine (`ServerCode`): PT_DEMO, SANDBOX_HUB, ES_DEMO, BR_DEMO, PRESALES, TENDERS (rows of `dbo.ManagedServer`). The pilot is a server without the current system, so catalogs for new machines come first.
- [CONFIRMED] The sync contract no longer exists: it is replaced by the signed package manifest (hashes of all files) and the per-machine catalog schema.
- [CONFIRMED] Answers of 2026-10-05 (after the plan, PR #14): (1) NO template server for policy rows; machines without policy rows are cut empty, the owner says the engines create them. Note: in the reference system `cfg.GetIisDeploymentPlan` fails with errors 50010 and 50011 when there is no policy row and no engine inserts policy rows, so the defaults must come from the ported engines [PENDING owner]. (2) Binary content stays as BLOB in every catalog. (3) The conversion tools run on PowerShell 7 with a SQL client shipped with them (a new vendored dependency: package, version and SHA-256 still to approve; NuGet was not reachable from the sandbox).
- [CONFIRMED] Catalog authority long term is DEFERRED; in V1 the owner may edit the catalog by hand and re-seal it with a seal tool (ADR-0007, proposed in PR #11).

## 5. State of every PR (as of this note)

| PR | Branch | What | State |
|---|---|---|---|
| #9 | (merged) | roadmap | merged |
| #10 | `phase2/repository-foundation` | Task 1: repository foundation (README, AGENTS, CLAUDE, Copilot instructions, CONTRIBUTING, SECURITY, CHANGELOG, templates, 5 skill skeletons, `vendor/manifest.json`, `.gitignore`, `tests/`, CI) | open, mergeable. Started by the previous assistant; this session added 2 commits: `SECURITY.md` signing-identity wording, and `.gitattributes`. CI: all earlier runs FAILED; cause [CONFIRMED by the fix, logs not readable]: the Windows runner checked out CRLF so the ASCII/LF step failed; `.gitattributes` (`* text=auto eol=lf`) fixed it and run on `ef42a49` is green. Hashes in `vendor/manifest.json` match `spikes/phase1A/Test-Phase1A.ps1` [CONFIRMED] |
| #11 | `docs/adr-0007-embedded-catalog` | ADR-0007 embedded read-only catalog, no runtime sync, text logs | open, status Proposed; the owner must accept it |
| #12 | `phase1/iis-reconcile-mwa-equivalence` | Task 2: `docs/phase1/iis-reconcile-mwa-equivalence.md` | open, complete (draft for review) |
| #13 | `phase2/contracts-draft` | Task 3: `contracts/` (README, `package-manifest.schema.json`, `catalog-schema.md`, `engine-result.schema.json`, `credential-package.md`, `api/openapi.yaml`) | open, complete (draft, all PROPOSED) |
| #14 | `docs/catalog-conversion-plan` | Task 4 step A: `docs/migration/catalog-conversion-plan.md` | open, complete; waits for owner approval before step B |
| #15 | `docs/handoff-2026-10-05` | this file | open |
| #16 | `tools/export-management-engines` | Step B1: `tools/Export-ManagementEngines.ps1`, unit tests, `tools-tests.yml` workflow, `tools/README.md` | open; CI green on windows-2022 |
| #18 | `spike/sqlclient-pin` | SQL client pin spike: workflow `sqlclient-pin.yml`, script, evidence `docs/phase1/evidence/sqlclient-pin-37314406178/`, `docs/phase1/sqlclient-pin.md` | open; run PASS. Temporary branch `results/sqlclient-pin-37314406178` can be deleted after review |
| #17 | `tools/convert-management-db` | Step B2: `tools/Convert-ManagementDb.ps1` (new-machine mode), unit tests, pinned `sqlite3` download in CI | open, STACKED on #16 (base branch is #16's); CI green. Merge #16 first |

No PR of this session has CI yet except #10, because `ci.yml` lives only on #10's branch until it is merged. After #10 merges, re-run or rebase the others to get CI.

## 6. What each piece says (so you do not have to re-derive it)

### 6.1 PR #12 - IIS_RECONCILE to MWA matrix

- Source: `ops.Engine` row `IIS_RECONCILE` v16.3 in `database/sync/ManagementSync.sql` (starts at line 34948). `ScriptText` 91,834 chars, 2,373 lines, CRLF. The stored `ScriptSha256` equals the SHA-256 of the UTF-16LE text after unescaping `''` (proof that the extraction is exact) [CONFIRMED]. `ops.Engine_BackupIisFix` holds a different, older text; use `ops.Engine`.
- 32 operations: 25 Direct, 4 Needs work (IIS-18 folder/vdir existence, IIS-20 convert to application, IIS-29 central certificate store bindings, IIS-32 local accounts), 3 No equivalent (IIS-01 Windows features, IIS-28 http.sys via `netsh`, IIS-30 backup via `appcmd`).
- v16.3 already mixes WebAdministration, MWA and `netsh`/`appcmd`. Test list T-01..T-11 and 7 open decisions are in the document.
- [NOT DONE] The four plan procedures `cfg.GetIis*` were not analysed.

### 6.2 PR #13 - contracts

- `package-manifest.schema.json` replaces the planned sync manifest. `catalog-schema.md` is a frame (metadata table, conventions); its table list comes from the conversion plan.
- `engine-result.schema.json` is aligned with the old `SISQUAL_JOB_RESULT_V1` and the `Add-Result` rows.
- `credential-package.md`: machine-bound text envelope, validation order, negative tests, open questions Q1 to Q8 (trust bootstrap, algorithms, import destination, replay storage, key loss, kinds, lifetime, granularity). No algorithm is chosen (AGENTS.md requires approval).
- `api/openapi.yaml`: skeleton, no sync endpoints. Validated with `openapi-spec-validator`; one wrong relative `$ref` was fixed.
- Datetime convention corrected: source times are `SYSDATETIME()` local time without a zone, not UTC.

### 6.3 PR #14 - conversion plan (the most important findings)

- Source file: 29,516,382 bytes, blob `9401e2c3cb2517ca88848f902ff4d3786583e888`, reference head `9756ba956842884fabcf25b82c4fbf1d11cf56bd`. 117 tables (51 global, 7 cut by `ServerCode`, 4 cut by `InstanceCode`, 55 excluded), 31,959 rows, 6 views, 200 procedures, 5 functions, 5 triggers.
- The file has PRIMARY KEYs only (no foreign keys, checks, defaults, indexes). 5 orphan rows in `cfg.LinksProfileInstance`.
- **16 literal secrets in `cfg.ConfigRule.ExpectedTemplate`** (12 client secrets, 1 API key, 1 access token, 2 Keycloak passwords), in plain text in the reference repository. Never print them; rotate after the cutover.
- The 191 credentials in `sec.ManagedCredential` are ciphertext tied to a SQL Server certificate in the live database; they cannot be decrypted from the file, so the vault import must run against the live database before it is retired.
- PRESALES and TENDERS have no rows in the four server policy tables; the pilot server is not in `dbo.ManagedServer`, so the new-machine mode of the converter is built first.
- Instances per server: BR_DEMO 21, ES_DEMO 19, PT_DEMO 16, PRESALES 8, SANDBOX_HUB 6, TENDERS 6.

## 7. Open decisions (consolidated)

1. ADR-0007 acceptance (PR #11). Until then `SECURITY.md`, `README.md`, `AGENTS.md` and `CLAUDE.md` of PR #10 may still describe a central authority and snapshot sync [NOT DONE: those four files were not audited against ADR-0007 in this session].
2. Conversion plan section 8: 14 decisions, of which 3 are now decided (binary as BLOB, no template server, PowerShell 7 tools). Still open: classification and redaction of the 16 secrets, source of policy defaults, cross-machine instance directory, `COLLATE NOCASE`, views, engine export location and the ASCII/LF exception, SQL client package and CI parsing of `tools/`, vault format, credential contract Q1..Q8, seal tool, CI SQL Server, machines without a database, rotation and freeze.
3. IIS matrix section 7: Windows features mechanism, vdir conversion policy, central certificate store scope, swallowed errors, backup mechanism, pool-password interface.
4. Credential contract Q1..Q8, especially Q3 (text package or `credentials.db`) and Q4 (where the replay `sequence` is stored while the application writes no database).
5. ADR-0006 conditions 2 to 4 are still open; condition 1 (the matrix) is addressed by PR #12 once reviewed.
6. Roadmap items 3 and 4 (credential packages, real-topology IIS run) are superseded or reshaped by the owner decisions above; the reviewer updates the roadmap.

## 8. What was NOT done

- `docs/decisions-log.md` and `docs/roadmap.md` were not changed (by instruction).
- Step B of task 4 (the tools) was not started; it needs plan approval.
- No product code exists anywhere; `tools/` does not exist yet.
- `AGENTS.md`, `README.md`, `CLAUDE.md` of PR #10 were not re-read after the owner updates.
- The original ChatGPT conversation behind the first request (a claude.ai share link) could not be read; the previous assistant's work was reconstructed from git (branches and PRs).
- CI logs cannot be read from the sandbox (egress to `productionresultssa1.blob.core.windows.net` is blocked); the CI cause on PR #10 was inferred and confirmed by the green run after the fix.

## 9. Security notes

- A GitHub token (full access to four private repositories) was pasted into a chat. Revoke it and create a narrower one. It was used through an HTTP header and, inside the temporary sandbox only, written to two small helper scripts that were deleted at the end of the session; it was never written to any repository. Revoke it anyway.
- The reference repository contains 16 literal secrets (6.3). Treat `ManagementSync.sql` as sensitive: do not copy it into this repository or into CI.
- Before pushing anything, run the ASCII/LF check and a secret scan on the changed files.

## 10. Method notes (how the work was done, so it can be redone)

Sandbox: a Linux container; `/home/claude` is lost between sessions; the shell is `/bin/sh`, so use `bash -c` for `source`. Network allows `github.com`, `api.github.com`, `pypi.org` only.

- Git: use `git -c http.extraheader="Authorization: Basic <base64 of x-access-token:TOKEN>"` for clone, fetch and push, so the token is not stored in the remote URL. Configure a user name and email in the clone.
- GitHub API: `Authorization: Bearer TOKEN`. Create PRs with `POST /repos/<repo>/pulls` (JSON body built by a script; avoids quoting problems). Listing workflow runs works; reading job logs and annotations does not.
- Reading `ManagementSync.sql` (29.5 MB): download with the contents API and header `Accept: application/vnd.github.raw`, check the size. Do not read it with line tools (a 268 KB line exists). Parse it in Python: tables from the `EXEC('CREATE TABLE ...')` blocks, rows from `INSERT INTO [schema].[table] (...) VALUES (...);`, with a quote-aware splitter. The first line of the file is a UTF-8 BOM, open with `utf-8-sig` and `newline=''`.
- Extracting an engine: find `INSERT INTO [ops].[Engine] ([EngineCode]...` for the code, take the `N'...'` literal of `ScriptText`, replace `''` by `'`, verify SHA-256 over UTF-16LE equals `ScriptSha256`.
- Validation tools installed with `pip install --break-system-packages jsonschema pyyaml openapi-spec-validator`. For OpenAPI with an external `$ref`, pass `base_uri='file://<abs path>'`.
- Checks used before every commit: ASCII (no byte over 127) and no CR byte in each changed text file; JSON Schema `check_schema`, examples validated and bad inputs rejected.
- Work in parts: write one section, check, commit, push; repeat. This avoids losing work to timeouts.

## 11. Suggested next steps

1. The owner revokes the old token and gives a new one.
2. The reviewer looks at #10 (CI is green), #12, #13, #14 and decides on ADR-0007 (#11).
3. After ADR-0007 and the conversion plan are approved: audit `AGENTS.md`, `README.md`, `CLAUDE.md`, `SECURITY.md` against ADR-0007 and fix them in a small PR.
4. Step B in the order of the plan (5.5): B1 engine export, B2 converter in new-machine mode, B3 cut mode, B4 test tool, B5 seal tool, B6 vault import and credential issue.
5. Answer the credential contract questions (Phase 1B machine-key ADR) before B6.

## 12. Step B progress (added later the same day)

State: B1 (PR #16) and B2 (PR #17) are done and green in CI. B3 to B6 are not started.

What exists:
- `tools/Export-ManagementEngines.ps1`: exports the 19 engines of `ops.Engine` to files plus `engines-export-manifest.json`. [CONFIRMED] on the real sync file: 19 engines, 0 hash mismatches (stored hash = SHA-256 of the UTF-16LE text), 0 secret-pattern hits, about 6 s.
- `tools/Convert-ManagementDb.ps1`: new-machine mode only. [CONFIRMED] on the real sync file: a catalog for a new machine in about 27 s, 6.85 MB, 63 STRICT tables, 16 rule templates redacted, none of the original secret values anywhere in the file, 45 of 45 image BLOBs match their stored SHA-256, read-only open refuses writes.
- Tests in `tests/Unit/` (21 and 41 checks), plain PowerShell, no Pester. The converter tests need `SQLITE3_PATH`. Workflow `.github/workflows/tools-tests.yml` parses `tools/` and `tests/` with the PowerShell 7 parser, checks ASCII/LF, downloads the pinned sqlite3 3.53.4 (SHA-256 verified) and runs the tests.

Known gaps:
- [V] The SQL Server source path (`-SqlInstance`) of both tools is written but untested: no SQL Server was available.
- [PENDING] `Microsoft.Data.SqlClient` is approved but not pinned (version, SHA-256, licence) in `vendor/manifest.json`; NuGet is not reachable from the sandbox, get the hash on a Windows runner.
- [PENDING] `ManagementDatabaseName` (NOT NULL, meaningless after the cutover) is written as an empty string for a new machine; decide whether to drop the column.
- [PENDING] `COLLATE NOCASE` on `*Code` columns is on by default; confirm against the live collation [V].
- B3 (cut mode for the six existing machines), B4 (`Test-CatalogConversion.ps1`), B5 (seal tool) and B6 (vault import and credential issue) are next, in that order, one PR each. B6 needs the credential contract questions answered first.
- PR #10 CI (`ci.yml`) has a simple secret scan that flags any `Pwd = '...'` style line of 8 or more characters; keep variable names in tools free of that shape.

Lessons that cost time (do not repeat):
- In PowerShell an `if` expression (`$x = if (...) { $bytes } else { ... }`) unrolls a `byte[]` into an `object[]`. Assign inside the branches. The STRICT SQLite table caught it; the converter now throws if a binary column does not receive bytes.
- The safety-net scan must ignore `{{...}}` reference tokens, otherwise it flags the redaction output.
- The hashes file of a PowerShell release is UTF-16; decode it before comparing.

How to get a test environment in a fresh sandbox (no root needed):
- PowerShell 7.6.6: download `powershell-7.6.6-linux-x64.tar.gz` and `hashes.sha256` from the PowerShell GitHub release `v7.6.6`, verify the SHA-256 (the hashes file is UTF-16), extract and run `pwsh`.
- sqlite3 CLI: download `sqlite3_3.45.1-1ubuntu2_amd64.deb` from `http://archive.ubuntu.com/ubuntu/pool/main/s/sqlite3/`, `dpkg -x` it, set `SQLITE3_PATH` to the extracted `usr/bin/sqlite3`. This is 3.45.1, not the pinned 3.53.4; CI uses the pinned one.
- Run: `pwsh -NoProfile -File tests/Unit/Test-ExportManagementEngines.ps1` and `pwsh -NoProfile -File tests/Unit/Test-ConvertManagementDb.ps1`.
- To redo the real runs, download `ManagementSync.sql` as described in section 10 and run each tool with the output folder OUTSIDE the repository.

## 13. Second round of owner answers and the SQL client pin (added later the same day)

Owner answers ([CONFIRMED]):
- Yes to pinning the SQL client with a Windows-runner workflow, and to documenting it (PR #18, `docs/phase1/sqlclient-pin.md`).
- `dbo.ManagedServer.ManagementDatabaseName` is dropped (done in PR #17, commit 95ea485).
- Every database uses the collation `Latin1_General_CI_AS`. Code columns stay `COLLATE NOCASE` (ASCII-only folding); in the snapshot all 10,165 code values are ASCII; the converter reports any non-ASCII code value as a finding. Other text columns are case-sensitive in SQLite, so the engine ports must not rely on SQL Server's case-insensitive comparison for them.
- The owner asked why SQL Server appears at all, since the product uses SQLite. Answer given and recorded in the plan (section 5): SQL Server is ONLY the source of the one-off conversion and of the one-time credential import; the catalogs, the application and the tests use SQLite only; the same conversion also works offline from `ManagementSync.sql`.

SQL client pin ([CONFIRMED] by run 37314406178):
- `Microsoft.Data.SqlClient` 7.1.1, nupkg SHA-256 `1da22a633fb44406d9a9400b00471039e8895ac3e717afe2e3beedba2f049e37`, signed by Microsoft, MIT, closure of 25 files, loads in the pinned PowerShell 7.6.6 on .NET 10.0.12.
- The `windows-2022` runner carries SQL Server LocalDB (15.0.4382.1, default collation `SQL_Latin1_General_CP1_CI_AS`). A read-only query through the pinned client worked with data source `(localdb)\MSSQLLocalDB`; `.\SQLEXPRESS` and `localhost,1433` did not answer. This means the SQL Server path of both tools CAN be tested in CI.

Suggested next steps (in this order):
1. Integration test on LocalDB: create a database with `Latin1_General_CI_AS`, create the table shapes (generated from the sync file; the real file must not enter the repository, it holds the 16 literal secrets), insert synthetic rows, and run `Export-ManagementEngines.ps1` and `Convert-ManagementDb.ps1` with `-SqlInstance`. Compare the catalog with the one built offline from the same fixture: they must be identical.
2. B3: cut mode for the six existing machines.
3. B4: `Test-CatalogConversion.ps1`. B5: seal tool. B6: vault import and credential issue (needs the credential contract questions answered).
4. Decide how the 25 closure files reach the operator machine, and the connection encryption defaults for the real servers [V].

Reminder: the GitHub token pasted in the first message was still valid at the end of this session and was used throughout. It must be revoked.
