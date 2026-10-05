# Phase 0 - Risk Register

**Scope:** risks identified before SISQUALDeployConsole product implementation, kept up to date as the project moves.  
**Updated:** 2026-10-05 (task 2). Basis: ADR-0001, ADR-0006, ADR-0007, `contracts/credential-package.md` (section 8), the conversion tools B1 to B5, the credential module B6.1a and `docs/decisions-log.md`.  
**Scale:** Severity and likelihood are qualitative: Low / Medium / High / Critical where applicable. They are the original (inherent) assessments and were not changed; the status column says what has happened since.

The register had **43 risks (R-001 to R-043)**, not 40. All 43 are updated and their IDs are kept; six risks are new (R-044 to R-049). A risk is not marked closed because code was written (see the acceptance policy at the end).

## Status vocabulary

- **[CONFIRMED]** risk is evidenced by production experience or current code.
- **[PROPOSED CONTROL]** mitigation approved architecturally but not implemented.
- **[PENDING]** requires Phase 1 or later proof, or a decision.
- **[V]** requires validation on a real Windows/SISQUAL environment.

Status of a risk, in the status column:

- **Open** - no control is implemented yet, or the control is still [PROPOSED].
- **Reduced** - a control is implemented and has test or spike evidence for part of the scope; a residual remains and is named.
- **Reduced (closure proposed)** - the evidence is deterministic; the reviewer decides whether to close.
- **Closed (architecture)** - an accepted architecture decision eliminates the risk as worded; successor risks are named.
- **Accepted (owner)** - the project owner accepted the risk explicitly.

## Risk register

| ID | Risk | Evidence | Severity | Likelihood | Status (2026-10-05) | V1 control / disposition (updated) |
|---|---|---|---|---|---|---|
| R-001 | Local cache accidentally becomes a second source of truth | Approved architecture specifically rejects this | Critical | Medium | Closed (architecture) | ADR-0007 removes the central database and the local cache, so there is no second source of truth. The catalog is read-only for the application and is edited only by the owner, then sealed. Successor risks: R-044 (stale catalog), R-047 (manual edit). (Was: central read-only authoritative; SQLite separates mirror from local state.) |
| R-002 | Partial/corrupt sync replaces a valid cache | Distributed snapshot failure is structurally possible | High | Medium | Reduced | No runtime sync (ADR-0007): a package is replaced as a whole folder. The manifest lists the SHA-256 of every file and is signed; the application refuses a mismatch except with a logged development flag [PROPOSED]. Implemented and tested in the tools: `Seal-Package` (71 unit checks, verify mode) and `Test-CatalogConversion`, both green on windows-2022. Open until the application verifies at start-up (Phase 3). |
| R-003 | First run with empty DB is mistaken for "zero environments" | Explicit product requirement | High | Medium | Open | State `INITIAL_SETUP` or `INTEGRITY_ERROR` in the API skeleton (`contracts/api/openapi.yaml`): operational routes answer 409 until the manifest and the catalog verify [PROPOSED, Phase 3]. (Was: blocked until a trusted first snapshot.) |
| R-004 | Wrong/golden-source synchronization direction causes lost changes | [CONFIRMED] production: non-PT_DEMO edits are overwritten | High | Medium | Closed (architecture) | No synchronisation and no central database, so nothing is overwritten by a sync. What remains are two other forms: a hand edit lost when the folder is replaced (R-047) and a catalog made from an old conversion (R-044). |
| R-005 | Credential ciphertext/key material is copied to another server and becomes unusable or unsafe | [CONFIRMED] current SQL certificate model is machine/server-bound | Critical | High | Reduced | Decided 2026-10-05 (`contracts/credential-package.md` section 8): credentials are never in the catalog or the portable; one package per machine; per-entry ECDH P-256 and AES-256-GCM to the machine key. The existing ciphertext is not mirrored: the 191 credentials are read once from the live database into an encrypted vault [V]. `modules/Sisqual.Credentials` (B6.1a) implements the cryptography (74 unit checks). Open: machine key (Phase 1B), vault and issue tool (B6), the real import [V]. |
| R-006 | Credential package is encrypted for the right key but forged by an attacker | Cryptographic design risk | Critical | Low/Medium | Reduced | Packages are signed by the issuer key of the credential tool (ECDSA P-256 with SHA-256); the application pins the issuer public key on the machine after the operator confirms its fingerprint out of band (Q1); the validation order of the contract (section 6) runs before any decryption. The module tests cover signature, tampering, wrong key and entry failures. Open: the application-side import and its negative tests (Phase 3). (Was: signed by a trusted central signing identity.) |
| R-007 | Private machine key is exportable/copyable with portable folder | Portable-folder threat model | Critical | Medium | Open | Unchanged [PENDING][V]. Phase 1B: non-exportable key, and a test with two runner VMs that copying the folder carries no usable identity; DPAPI only as a fallback. An ADR follows. |
| R-008 | Secrets leak through logs, REST responses, SQLite, transcripts or exceptions | Current system manages high-value credentials | Critical | Medium | Reduced | Tools: no secret is printed or logged (counts, names and keys only); every tool has marker-secret tests; the converter stops before writing a catalog if a secret-like literal remains; the seal tool scans the catalog and refuses credential files; the six real catalogs contain none of the 16 literal secrets (independent check). Modules write nothing. Open: the application logs, REST responses and each engine (secret-safety test per engine). |
| R-009 | Localhost REST API is reachable by another local process/user/browser attack | Localhost is not an authentication boundary | Critical | Medium | Reduced (partly) | Loopback-only listening is proven on two runner images (Phase 1A: listener only on 127.0.0.1, the non-loopback address is refused). Open: one-time bootstrap session, CSRF, Host/Origin, CORS, CSP (Phase 1C); the route that imports a credential package needs the session and the token. |
| R-010 | Pode dependency becomes abandoned/vulnerable | Community-maintained framework | High | Medium | Reduced | ADR-0001 accepted. Pode 2.14.1 is pinned and hash-checked in `vendor/manifest.json`; Pode stays behind the API adapter; the exit criteria for replacing it are kept. |
| R-011 | Long-running engine blocks web request/server thread | Current operations can run minutes | High | High | Open | Unchanged (Phase 3). |
| R-012 | Two operators/actions mutate same instance concurrently | Real operations touch shared IIS/files/services/DB | Critical | Medium | Open | Per-instance destructive locks and server-wide locks, held in memory because the application writes no database (ADR-0007). Phase 3. |
| R-013 | SQLite write contention causes operational failures | SQLite single-writer model | Medium/High | Medium | Closed (architecture) | The application writes no database (ADR-0007): locks and idempotency tokens live in memory and history goes to text logs, so there is no SQLite write contention. (Was: serialise writes, WAL under Phase 1 validation.) |
| R-014 | Process exits while destructive operation is running | Pode is intentionally transient | Critical | Medium | Open | Controlled shutdown and an active-operation guard (Phase 1C and 3). Durable operation state is now a text log per operation, plus the plan file; [PENDING] where a plan lives between preview and apply. Recovery evidence is never deleted. (Was: durable operation state in SQLite.) |
| R-015 | PowerShell 7 cannot execute required IIS/Windows behavior | Current scripts declare PS 5.1; WebAdministration usage confirmed | Critical | Medium | Reduced | ADR-0006 accepted: `Microsoft.Web.Administration` in PowerShell 7 passed 22 of 22 write-path checks on two runner images; the WebAdministration provider does not work in PowerShell 7 (expected, documented). The equivalence matrix (`docs/phase1/iis-reconcile-mwa-equivalence.md`) lists 32 operations: 25 direct, 4 needing work, 3 without equivalent. The owner decided the engines move to PowerShell 7. Open: ADR-0006 conditions 2 to 4 [V]. |
| R-016 | SQLite provider cannot be shipped cleanly in portable PowerShell | Provider undecided | High | Medium | Open | The SQLite engine 3.53.4 is pinned and hash-checked and the tools use that executable. The managed provider is chosen in Phase 1B and only has to open a file read-only (owner, 2026-10-05). |
| R-017 | Exact-string configuration replacement silently changes nothing | [CONFIRMED] production lesson | High | High | Open | Unchanged (engine ports, `CONFIG_REPAIR`). Lesson from the conversion tools: a successful run proves nothing, values are verified independently (`Test-CatalogConversion`). |
| R-018 | Hash mismatch blocks execution after harmless encoding/newline changes | [CONFIRMED] current engine hash encoding contract | High | Medium | Reduced | The stored engine hash is the SHA-256 of the UTF-16LE text (confirmed for all 19 engines by `Export-ManagementEngines`). The package manifest hashes the raw bytes of each shipped file; repository text is ASCII and LF (`.gitattributes`, CI); the converter keeps text byte for byte (a CR loss was found and fixed, with a test that fails if the fix is removed). Open: start-up verification (Phase 3). |
| R-019 | Arbitrary SQL reaches application databases via DB setting engine | Database-content sync is powerful | Critical | Medium | Open | Unchanged (engine port `DATABASE_CONTENT_SYNC`). SQL text stored in the catalog (`ops.Action.SqlCommand`, `ops.ReviewDefinition.CommandText`) is data and is never executed (AGENTS.md). |
| R-020 | Linked-server fragility creates cross-instance failures | [CONFIRMED] production lesson | High | Medium | Reduced | The export and conversion tools use a direct read-only connection (Microsoft.Data.SqlClient, read-intent, integrated security), tested against SQL Server LocalDB; no linked server. The engines follow the same rule. |
| R-021 | Instance rename leaves dependent rows/orphans | [CONFIRMED] FKs/dependencies in credentials, links, pulse state | Critical | Medium | Open | The catalog is read-only for the application: a rename is planned by the skill and applied by the owner to the catalog, which is then sealed. An instance belongs to exactly one machine, but a rename can also change the instance-directory rows other catalogs carry (R-044). |
| R-022 | Cloned Keycloak retains source URLs/secrets | [CONFIRMED] production lesson | Critical | High | Open | Unchanged (engine ports). |
| R-023 | IIS reconciliation damages unrelated sites/pools | Engine runs as administrator and mutates IIS | Critical | Medium | Reduced | ADR-0006 and the equivalence matrix specify the operations and the missing tests (T-01 to T-11). Ownership checks, preview, allowlists, backup (`appcmd`) and post-apply verification stay per-engine controls. Conditions 2 to 4 of ADR-0006 are open [V]. |
| R-024 | Windows service reconciliation touches management/control-plane service | Current runtime explicitly excludes Management Worker | Critical | Low/Medium | Open | Unchanged (engine ports). |
| R-025 | TSplus/Web Access shared controller operation affects other environments | [CONFIRMED-CODE] current shared-resource locking | Critical | Medium | Open | Unchanged (engine ports). |
| R-026 | Central snapshot/cache ingests secret-bearing credential surfaces | [CONFIRMED] current model exposes decrypted values through `cfg.ManagedInstanceRuntime`; analysed sync also exports 191 `sec.ManagedCredential` ciphertext rows | Critical | Medium | Reduced (closure proposed) | Implemented and tested: a whitelist of 62 tables; `sec.*`, secret columns, `cfg.ManagedInstanceRuntime` and `ScriptText` not carried; the 16 literal secrets in rule templates replaced by `{{secret:RULE:<RuleCode>}}`; a safety-net scan before a catalog is written; the secrets group of `Test-CatalogConversion`; the seal tool refuses secret tables, columns and credential files. An independent check found 0 of the 16 values in any of the six catalogs. For the reviewer to confirm closure. Residual: a hand edit could add a secret (R-047) and the old repository still holds the literals (R-048). |
| R-027 | Central `ops.Engine.ScriptText` can mutate local executable code | Current system stores executable code in SQL | Critical | Medium | Closed (architecture) | ADR-0007: engines are local versioned files. `ScriptText` is never carried (the converter, the seal tool and the verifier refuse the column). The engine text exported by `Export-ManagementEngines` is only a base for ports, kept outside Git. |
| R-028 | Oversized repository artefact is misclassified because a reader returns empty/truncated content | [CONFIRMED] `fetch_file` returned an empty content string for the ~29.5 MB `ManagementSync.sql` even though Git tree metadata and an alternate contents path proved the blob was populated | High | Medium | Reduced | Practice adopted and recorded in every evidence document: size, blob SHA and SHA-256 are checked, the file is read through the raw contents API, and the tools parse it by statement. |
| R-029 | Scope creep from newer Management Console features | Current master includes many features beyond initial handoff | Medium | High | Open | V1 scope is all 19 engines (owner, 2026-10-05). Features of the old console that are not engines stay outside until the owner decides [PENDING; analysis of the copy and clone operations, task 1b]. |
| R-030 | Browser input controls filesystem paths | Engines manipulate privileged paths | Critical | Medium | Open | Paths come from the verified catalog, are canonicalised and checked against allowed roots. (Was: from trusted synchronised config.) |
| R-031 | REST request replay/duplicate clicks execute action twice | Browser/network retries happen | Critical | Medium | Open | Unchanged (Phase 1C). |
| R-032 | Preview differs materially from Apply | Common orchestration failure mode | Critical | Medium | Open | Unchanged. The draft `contracts/engine-result.schema.json` carries a plan fingerprint for the apply. |
| R-033 | Backup exists but cannot restore | Backups can provide false confidence | High | Medium | Open | Unchanged (engine ports). |
| R-034 | Administrator privilege turns UI/API bug into full server compromise | Current Worker requires local admin | Critical | Medium | Open | Unchanged (Phase 1C and 3). |
| R-035 | Vendored runtime/dependencies are tampered | Portable package carries executable dependencies | Critical | Low/Medium | Reduced | `vendor/manifest.json` pins PowerShell 7.6.6, Pode 2.14.1 and SQLite 3.53.4 by SHA-256, verified in CI. `Microsoft.Data.SqlClient` 7.1.1 is pinned per file (`vendor/sqlclient-pin.json`, 25 files, Microsoft signature checked when pinned). The SQL client files go inside the portable and the signed manifest covers them (owner, 2026-10-05). Open: signature implementation, start-up verification, and delivery of the client files (R-049). |
| R-036 | Old/foreign snapshot is accepted | Portable folder can be moved/copied | Critical | Medium | Reduced | A catalog carries its `server_code`; the signed manifest repeats it and the application compares it with the machine identity [PROPOSED, Phase 1B and 3]; the seal tool already checks it against the manifest. (Was: snapshot with source identity.) |
| R-037 | Clock/time assumptions break expiry/replay checks | Offline credential envelope uses time metadata | Medium | Low/Medium | Reduced | Decided: a package lives at most 1 year with 15 minutes of clock tolerance, and the replay reference is the sequence of the package already installed, so no separate replay store (Q4, Q7). |
| R-038 | Operation history grows without bound | Local console persists logs/history | Medium | Medium | Open | Plain text logs, one file per day, in a configurable folder (ADR-0007). Retention policy later; active and recovery evidence is never deleted. |
| R-039 | Current central action approval/schedule model is accidentally recreated despite transient V1 design | Current repo includes governance/scheduling | Medium | Medium | Open | V1 stays operator-started and transient. [PENDING] exception: the Pulse engine registers a collector scheduled task on the hub machine, as the old engine did (analysis of Pulse, task 1a). |
| R-040 | V1 UI becomes coupled to Pode and blocks future framework replacement | Architectural maintainability risk | High | Medium | Open | Unchanged. |
| R-041 | Nightly reference `master` moves while analysis is in progress | [CONFIRMED] the reference repo advanced from `1050fbbc...` to `1e38c8ed...` during Phase 0 correction | Medium | High | Reduced | Every evidence document and every tool manifest records the reference head (`9756ba95...`), the blob SHA and the SHA-256 of the sync file; moving to a newer snapshot is a deliberate re-run. |
| R-042 | Large repository file is silently elided by tooling and incorrectly classified as empty | [CONFIRMED] occurred during Phase 0 with the ~29.5 MB `ManagementSync.sql` blob | High | Medium | Reduced | Same practice as R-028. |
| R-043 | Stale catalogue metadata points to nonexistent execution identifiers | [CONFIRMED-SYNC] `cfg.ConfigurationAdapterDefinition` references `SETTINGS_SYNC` and `SERVICE_RECONCILE`, while current execution uses `DATABASE_SETTINGS -> DATABASE_CONTENT_SYNC` and `WINDOWS_SERVICES -> WINDOWS_SERVICES` | High | Medium | Open | Not covered by the conversion tools: add a cross-reference check (adapter action codes against `ops_Action` and the effective engine mapping) to `Test-CatalogConversion` [PROPOSED]. `DATABASE_SETTINGS` is covered by `DATABASE_CONTENT_SYNC` (roadmap). |
| R-044 | Stale catalog: the catalog no longer matches the real servers, or the instance directory in another machine's catalog is out of date | [CONFIRMED] a catalog is a copy made from a snapshot; the old system keeps changing until each server is switched; a rename or move on one machine changes rows that other catalogs carry (instance directory, `docs/roadmap.md` section 5) | High | High | Open | The UI shows the catalog build time and source (`catalog_meta`, manifest); the conversion is repeated for all machines before each cutover and the catalogs are sealed again; a change freeze is agreed while both systems run [PENDING]; the preview of the links engine lists the directory rows and the catalog date; live counts compared with the snapshot [V]. |
| R-045 | Loss or compromise of the issuer key (credential tool signing key) | [CONFIRMED] one issuer key signs the manifests and the credential packages; every machine pins its fingerprint (Q1) | Critical | Low/Medium | Open | Loss: no new package or manifest can be signed; recovery is a new key, a new pin on each of the six machines and new packages (Q5, manual). Compromise: forged packages and manifests are accepted until machines pin a new key. [PENDING] where the private key is stored and backed up (not covered by Q9), who holds it, and how a compromise is declared. Machines refuse an unknown issuer key (tested in `Sisqual.Credentials`). |
| R-046 | Loss of the vault passphrase or of the vault file | [CONFIRMED] after `_sisqualMANAGEMENT` is retired the vault is the only copy of the 191 credentials (and the 16 rule secrets); the owner decided on a passphrase-protected file (Q9) | Critical | Low/Medium | Open | One encrypted file outside Git and outside the portable, two encrypted backups in two places, restore tested (Q9). The import into the vault is verified (counts and salted fingerprints) before the old database is retired. [PENDING] a second custodian or a sealed offline copy of the passphrase; the fallback is to reset every credential at its service (costly). |
| R-047 | Manual edit of the catalog bypasses review: a mistake, an invalid catalog or an added secret | [CONFIRMED] the owner may edit the catalog by hand and seal it (ADR-0007 item 7); the long-term authority of the catalog is deferred | High | Medium | Reduced | `Seal-Package` validates before sealing (integrity, foreign keys, one `catalog_meta` row, forbidden tables and columns, secret scan), shows which files and tables changed with a baseline, asks for confirmation, records `manual-edit-sealed` in `catalog_meta` and appends to a seal log outside the package; a failure restores the original. `Test-CatalogConversion` cannot judge edited values. [PENDING] who may edit, a review step, and keeping the baseline and the seal log. |
| R-048 | 16 literal secrets in the history of the reference repository | [CONFIRMED] 16 rows of `cfg.ConfigRule` (`IsSensitive` = 1) hold a literal value in `ExpectedTemplate`, readable in `ManagementSync.sql` of `atsisqual/SISQUALManagementConsole`; the rows are identified by rule code in the redaction list of the conversion manifest, not here | High | High | Accepted (owner) | The owner decided on 2026-10-05 not to rotate them after the cutover and accepted the risk. Controls that stay: the file is never copied into this repository or CI; the converter replaces the literals by references; every tool and test scans for them; access to the reference repository stays limited. Residual: anyone who can read that repository and its history can read them. |
| R-049 | Delivery and integrity of the SQL client files (25 files) that go inside the portable | [CONFIRMED] each file is pinned by SHA-256 (`vendor/sqlclient-pin.json`); `tools/Initialize-SqlClient.ps1` restores them with `dotnet publish`, which needs the .NET SDK and nuget.org; the native SNI library is the win-x64 build | Medium | Medium | Open | Every file is verified against the pin before use; the package signature was checked when the version was pinned; the signed manifest covers the files in the portable (owner, 2026-10-05). [PENDING] how the files reach the portable build (a verified CI artifact is recommended), what happens on an x86 or arm64 operator machine, and how a new client version is pinned and reviewed. |

## Summary of the status

| Status | Risks |
|---|---:|
| Open | 26 (R-003, R-007, R-011, R-012, R-014, R-016, R-017, R-019, R-021, R-022, R-024, R-025, R-029, R-030, R-031, R-032, R-033, R-034, R-038, R-039, R-040, R-043, R-044, R-045, R-046, R-049) |
| Reduced | 16 (R-002, R-005, R-006, R-008, R-010, R-015, R-018, R-020, R-023, R-028, R-035, R-036, R-037, R-041, R-042, R-047) |
| Reduced (partly) | 1 (R-009) |
| Reduced (closure proposed) | 1 (R-026) |
| Closed (architecture) | 4 (R-001, R-004, R-013, R-027) |
| Accepted (owner) | 1 (R-048) |

## Highest-priority risks before engine porting

The following must be resolved or materially reduced before mutable engines are enabled. Status as of 2026-10-05:

1. **R-005/R-006/R-007/R-008 - credential model and secret handling.** Reduced: contract decided, cryptography module tested; open: machine key, vault and issue tool, application import, the real import [V].
2. **R-009/R-034 - localhost API security under administrator privilege.** Reduced for loopback binding only; session, CSRF, Host/Origin, CORS and CSP are Phase 1C.
3. **R-012/R-014/R-031/R-032 - operation coordination, shutdown and idempotency.** Open (Phase 1C and 3).
4. **R-015/R-016 - portable PowerShell/IIS/SQLite technical viability.** R-015 reduced (ADR-0006, matrix); conditions 2 to 4 [V]. R-016 open until the Phase 1B provider.
5. **R-002/R-026/R-036 - trusted catalog activation and secret exclusion.** Tools and seal verified; application-side start-up verification and identity check are open.
6. **R-017/R-019/R-023 - mutation safety for config, SQL and IIS.** Open or reduced per engine port.
7. **R-042/R-043 - large-file evidence and catalogue-reference validation.** R-042 reduced; R-043 open.
8. **R-044 to R-049 - new risks of the catalog and credential design.** Stale catalog, issuer key, vault passphrase, manual edits, secrets in the old repository history (accepted), delivery of the SQL client files.

## Phase 1 risk gates

Phase 1 must provide evidence for at least the following. Status as of 2026-10-05:

| Gate | Status |
|---|---|
| portable PowerShell version and execution | Done (Phase 1A, 7.6.6 from the extracted ZIP, two runner images) |
| Pode pinned version/package behavior | Done (2.14.1, pinned, `/health` on loopback) |
| SQLite provider loading with zero installation | Engine pinned (3.53.4); managed provider is a Phase 1B decision (read-only open only) |
| WAL/concurrency behavior appropriate to the coordinator | Not needed: the application writes no database (ADR-0007) |
| WebAdministration/IIS behavior under PowerShell 7 | Done for `Microsoft.Web.Administration` (22 of 22); the provider does not work in PowerShell 7 (ADR-0006) |
| local asymmetric key creation and non-exportability strategy | Open (Phase 1B) |
| package/folder copy behavior across machines | Open (Phase 1B, two runner jobs) |
| loopback-only binding | Done (Phase 1A) |
| browser session/bootstrap/CSRF/Host-Origin controls | Open (Phase 1C) |
| clean process shutdown and active-operation behavior | Open (Phase 1C) |

If PowerShell 7/IIS or the local web/security model fails these gates, ADR-0001 must be reopened before product code proceeds.

## Risk acceptance policy for later agents

A risk may not be marked closed merely because code was written.

Closure requires one of:
- deterministic automated test evidence;
- architecture change eliminating the risk;
- explicit human acceptance;
- **[V]** evidence from the required real Windows/SISQUAL environment.

Production-only assumptions remain open until they are represented by a stable contract or validated evidence.

## Phase 0 acceptance

- Production lessons have corresponding risks/controls.
- Pode, SQLite, concurrency and localhost API risks are explicit.
- Security impact of local-admin execution is explicit.
- Large-file evidence handling and moving nightly reference commits are explicit.
- Phase 1 technical spikes are identified without prematurely deciding their outcomes.
- No product code or reference-repository modification was made.
