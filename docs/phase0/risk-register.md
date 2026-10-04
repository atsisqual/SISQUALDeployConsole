# Phase 0 — Risk Register

**Scope:** risks identified before SISQUALDeployConsole product implementation.  
**Scale:** Severity and likelihood are qualitative: Low / Medium / High / Critical where applicable.

## Status vocabulary

- **[CONFIRMED]** risk is evidenced by production experience or current code.
- **[PROPOSED CONTROL]** mitigation approved architecturally but not implemented.
- **[PENDING]** requires Phase 1 or later proof.
- **[V]** requires validation on a real Windows/SISQUAL environment.

## Risk register

| ID | Risk | Evidence | Severity | Likelihood | V1 control / disposition |
|---|---|---|---|---|---|
| R-001 | Local cache accidentally becomes a second source of truth | Approved architecture specifically rejects this | Critical | Medium | Central config is read-only authoritative; SQLite separates central mirror from local state; no V1 authoring back to central |
| R-002 | Partial/corrupt sync replaces a valid cache | Distributed snapshot failure is structurally possible | High | Medium | Stage -> validate -> atomic activate; retain last-known-good snapshot |
| R-003 | First run with empty DB is mistaken for “zero environments” | Explicit product requirement | High | Medium | INITIAL SETUP state; operational routes blocked until trusted first snapshot |
| R-004 | Wrong/golden-source synchronization direction causes lost changes | [CONFIRMED] production: non-PT_DEMO edits are overwritten | High | Medium | V1 never writes central config; sync direction is central -> local only |
| R-005 | Credential ciphertext/key material is copied to another server and becomes unusable or unsafe | [CONFIRMED] current SQL certificate model is machine/server-bound | Critical | High | New asymmetric machine identity; private key never leaves machine; offline encrypted+signed envelope; do not mirror current credential ciphertext |
| R-006 | Credential package is encrypted for the right key but forged by an attacker | Cryptographic design risk | Critical | Low/Medium | Envelope must also be signed by trusted central signing identity; validate target/fingerprint/version/expiry/replay before decrypt |
| R-007 | Private machine key is exportable/copyable with portable folder | Portable-folder threat model | Critical | Medium | Prefer non-exportable CNG machine key; DPAPI alternative only if Phase 1 proves better; [PENDING][V] |
| R-008 | Secrets leak through logs, REST responses, SQLite, transcripts or exceptions | Current system manages high-value credentials | Critical | Medium | Explicit secret redaction; secret-safe structured logging; no secret echo; tests scan artifacts/logs; local credential audit stores metadata only |
| R-009 | Localhost REST API is reachable by another local process/user/browser attack | Localhost is not an authentication boundary | Critical | Medium | Loopback only, one-time bootstrap session, CSRF, Host/Origin validation, deny CORS, SameSite/HttpOnly session, strict CSP |
| R-010 | Pode dependency becomes abandoned/vulnerable | Community-maintained framework | High | Medium | Isolate Pode behind API adapter; pin/version/vendor package; security review; architecture exit criteria allow replacement by ASP.NET Core |
| R-011 | Long-running engine blocks web request/server thread | Current operations can run minutes | High | High | In-process operation coordinator; REST creates operation and returns ID; progress polled separately |
| R-012 | Two operators/actions mutate same instance concurrently | Real operations touch shared IIS/files/services/DB | Critical | Medium | Per-instance destructive lock + global server/shared-resource locks where needed; V1 constrained concurrency |
| R-013 | SQLite write contention causes operational failures | SQLite single-writer model | Medium/High | Medium | Serialize writes through local coordinator; WAL subject to Phase 1 validation; keep operations independent of DB transaction duration |
| R-014 | Process exits while destructive operation is running | Pode is intentionally transient | Critical | Medium | Controlled shutdown, active-operation guard, explicit cancellation semantics, durable operation state |
| R-015 | PowerShell 7 cannot execute required IIS/Windows behavior | Current scripts declare PS 5.1; WebAdministration usage confirmed | Critical | Medium | Phase 1 compatibility spike before porting; no version freeze until proven [V] |
| R-016 | SQLite provider cannot be shipped cleanly in portable PowerShell | Provider undecided | High | Medium | Phase 1 provider spike; require no external installation |
| R-017 | Exact-string configuration replacement silently changes nothing | [CONFIRMED] production lesson | High | High | Normalized plan, precondition match counts, parser/semantic validation, post-apply verification; fail if expected mutation did not occur |
| R-018 | Hash mismatch blocks execution after harmless encoding/newline changes | [CONFIRMED] current engine hash encoding contract | High | Medium | Canonical release manifest/hash rules; tests for encoding/newlines; do not reuse SQL UTF-16 hash semantics blindly |
| R-019 | Arbitrary SQL reaches application databases via DB setting engine | Database-content sync is powerful | Critical | Medium | Structured predicates only, allowlisted table/column model, parameterization, no raw REST/UI SQL |
| R-020 | Linked-server fragility creates cross-instance failures | [CONFIRMED] production lesson | High | Medium | Direct SqlConnection to intended target; linked server not execution transport |
| R-021 | Instance rename leaves dependent rows/orphans | [CONFIRMED] FKs/dependencies in credentials, links, pulse state | Critical | Medium | Dedicated skill with dependency discovery/preview; V1 central read-only means no silent central rename |
| R-022 | Cloned Keycloak retains source URLs/secrets | [CONFIRMED] production lesson | Critical | High | Keycloak post-clone validation must compare every target-specific URL/client/secret; clone not healthy until verified |
| R-023 | IIS reconciliation damages unrelated sites/pools | Engine runs as administrator and mutates IIS | Critical | Medium | Machine/instance ownership checks, desired-vs-actual preview, allowlisted paths/site names, backups where applicable, post-apply verification |
| R-024 | Windows service reconciliation touches management/control-plane service | Current runtime explicitly excludes Management Worker | Critical | Low/Medium | Explicit protected-service denylist plus environment ownership proof |
| R-025 | TSplus/Web Access shared controller operation affects other environments | [CONFIRMED-CODE] current shared-resource locking | Critical | Medium | Local shared-resource lock and impact preview; never assume per-instance isolation |
| R-026 | Central snapshot/cache ingests secret-bearing credential surfaces | [CONFIRMED] current model exposes decrypted values through `cfg.ManagedInstanceRuntime`; analysed sync also exports 191 `sec.ManagedCredential` ciphertext rows | Critical | Medium | Explicit entity/column allowlist; never SELECT *; exclude decrypted views and `SecretCipher` from general V1 mirror; credentials use separate envelope flow |
| R-027 | Central `ops.Engine.ScriptText` can mutate local executable code | Current system stores executable code in SQL | Critical | Medium | V1 local versioned modules are executable authority; central engine script is migration/reference data only |
| R-028 | Oversized repository artefact is misclassified because a reader returns empty/truncated content | [CONFIRMED] `fetch_file` returned an empty content string for the ~29.5 MB `ManagementSync.sql` even though Git tree metadata and an alternate contents path proved the blob was populated | High | Medium | For large files verify tree `size`/SHA, use an alternate content path, record the exact commit, and never treat an empty reader result alone as evidence of an empty file |
| R-029 | Scope creep from newer Management Console features | Current master includes many features beyond initial handoff | Medium | High | Inventory them but do not include in V1 without explicit decision |
| R-030 | Browser input controls filesystem paths | Engines manipulate privileged paths | Critical | Medium | Paths resolved from trusted synchronized config; canonicalize; enforce allowed roots; reject traversal/out-of-root |
| R-031 | REST request replay/duplicate clicks execute action twice | Browser/network retries happen | Critical | Medium | Idempotency token + OperationId + coordinator deduplication |
| R-032 | Preview differs materially from Apply | Common orchestration failure mode | Critical | Medium | Apply consumes same normalized plan/fingerprint where possible; invalidate stale preview when inputs/state change |
| R-033 | Backup exists but cannot restore | Backups can provide false confidence | High | Medium | Backup artifact metadata/hash + restore strategy tests for each destructive engine |
| R-034 | Administrator privilege turns UI/API bug into full server compromise | Current Worker requires local admin | Critical | Medium | Minimize API surface, validate all inputs, loopback/session controls, module allowlists, no Invoke-Expression, no raw command construction |
| R-035 | Vendored runtime/dependencies are tampered | Portable package carries executable dependencies | Critical | Low/Medium | Version lock + SHA-256 manifest; CI/package verification; future signing decision |
| R-036 | Old/foreign snapshot is accepted | Portable folder can be moved/copied | Critical | Medium | Snapshot includes source/server identity, contract version and hashes; local activation checks current machine identity |
| R-037 | Clock/time assumptions break expiry/replay checks | Offline credential envelope uses time metadata | Medium | Low/Medium | Sequence/package ID + replay store; expiry policy tolerant but explicit; diagnostics for clock skew |
| R-038 | Operation history grows without bound | Local console persists logs/history | Medium | Medium | Local retention policy; never delete active/recovery evidence; exact policy later |
| R-039 | Current central action approval/schedule model is accidentally recreated despite transient V1 design | Current repo includes governance/scheduling | Medium | Medium | V1 is operator-started/transient; no persistent Windows task/service; scheduling remains out of scope |
| R-040 | V1 UI becomes coupled to Pode and blocks future framework replacement | Architectural maintainability risk | High | Medium | Vanilla HTML/CSS/JS + REST contract; engines/application services have no Pode dependency |
| R-041 | Nightly reference `master` moves while analysis is in progress | [CONFIRMED] the reference repo advanced from `1050fbbc...` to `1e38c8ed...` during Phase 0 correction | Medium | High | Freeze and record commit SHA for every evidence pass; use moving `master` only to deliberately select a newer snapshot and document the transition |
| R-042 | Large repository file is silently elided by tooling and incorrectly classified as empty | [CONFIRMED] occurred during Phase 0 with the ~29.5 MB `ManagementSync.sql` blob | High | Medium | Never infer emptiness from wrapper content alone; verify Git blob SHA/size and use an alternate/targeted content path before drawing repository conclusions |
| R-043 | Stale catalogue metadata points to nonexistent execution identifiers | [CONFIRMED-SYNC] `cfg.ConfigurationAdapterDefinition` references `SETTINGS_SYNC` and `SERVICE_RECONCILE`, while current execution uses `DATABASE_SETTINGS -> DATABASE_CONTENT_SYNC` and `WINDOWS_SERVICES -> WINDOWS_SERVICES` | High | Medium | Validate cross-catalogue references; effective execution mapping comes from validated `ops.Action` + `ops.Engine`; fail closed on dangling/stale adapter ActionCode values |

## Highest-priority risks before engine porting

The following must be resolved or materially reduced before mutable engines are enabled:

1. **R-005/R-006/R-007/R-008 — credential model and secret handling.**
2. **R-009/R-034 — localhost API security under administrator privilege.**
3. **R-012/R-014/R-031/R-032 — operation coordination, shutdown and idempotency.**
4. **R-015/R-016 — portable PowerShell/IIS/SQLite technical viability.**
5. **R-002/R-026/R-036 — trusted snapshot activation and secret exclusion.**
6. **R-017/R-019/R-023 — mutation safety for config, SQL and IIS.**
7. **R-042/R-043 — large-file evidence and catalogue-reference validation.**

## Phase 1 risk gates

Phase 1 must provide evidence for at least:

- portable PowerShell version and execution;
- Pode pinned version/package behavior;
- SQLite provider loading with zero installation;
- WAL/concurrency behavior appropriate to the coordinator;
- WebAdministration/IIS behavior under PowerShell 7;
- local asymmetric key creation and non-exportability strategy;
- package/folder copy behavior across machines;
- loopback-only binding;
- browser session/bootstrap/CSRF/Host-Origin controls;
- clean process shutdown and active-operation behavior.

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
