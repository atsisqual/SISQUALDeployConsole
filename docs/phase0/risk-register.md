# Phase 0 — Risk Register

**Scope:** risks identified before SISQUALDeployConsole product implementation.  
**Scale:** Severity and likelihood are qualitative: Low / Medium / High / Critical where applicable.

## Status vocabulary

- **[CONFIRMED]** risk is evidenced by production experience, current code or full sync snapshot.
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
| R-005 | Credential ciphertext/key material is copied to another server and becomes unusable or unsafe | [CONFIRMED] current SQL certificate model is machine/server-bound; sync contains 191 encrypted credential rows | Critical | High | New asymmetric machine identity; private key never leaves machine; offline encrypted+signed envelope; old vault ciphertext is not local credential authority |
| R-006 | Credential package is encrypted for the right key but forged by an attacker | Cryptographic design risk | Critical | Low/Medium | Envelope must also be signed by trusted central signing identity; validate target/fingerprint/version/expiry/replay before decrypt |
| R-007 | Private machine key is exportable/copyable with portable folder | Portable-folder threat model | Critical | Medium | Prefer non-exportable CNG machine key; DPAPI alternative only if Phase 1 proves better; [PENDING][V] |
| R-008 | Secrets leak through logs, REST responses, SQLite, transcripts or exceptions | Current system manages high-value credentials | Critical | Medium | Explicit secret redaction; secret-safe structured logging; no secret echo; tests scan artifacts/logs; local credential audit stores metadata only |
| R-009 | Localhost REST API is reachable by another local process/user/browser attack | Localhost is not an authentication boundary | Critical | Medium | Loopback only, one-time bootstrap session, CSRF, Host/Origin validation, deny CORS, SameSite/HttpOnly session, strict CSP |
| R-010 | Pode dependency becomes abandoned/vulnerable | Community-maintained framework | High | Medium | Isolate Pode behind API adapter; pin/version/vendor package; security review; architecture exit criteria allow replacement by ASP.NET Core |
| R-011 | Long-running engine blocks web request/server thread | Current operations can run minutes | High | High | In-process operation coordinator; REST creates operation and returns ID; progress polled separately |
| R-012 | Two operators/actions mutate same instance concurrently | Real operations touch shared IIS/files/services/DB | Critical | Medium | Per-instance destructive lock + global server/shared-resource locks where needed; V1 constrained concurrency |
| R-013 | SQLite write contention causes operational failures | SQLite single-writer model | Medium/High | Medium | Serialize writes through local coordinator; WAL subject to Phase 1 validation; keep operations independent of DB transaction duration |
| R-014 | Process exits while destructive operation is running | Pode is intentionally transient | Critical | Medium | Controlled shutdown, active-operation guard, explicit cancellation semantics, durable operation state |
| R-015 | PowerShell 7 cannot execute required IIS/Windows behavior | Snapshot confirms every core engine currently targets minimum PS 5.1 | Critical | Medium | Phase 1 compatibility spike before porting; no version freeze until proven [V] |
| R-016 | SQLite provider cannot be shipped cleanly in portable PowerShell | Provider undecided | High | Medium | Phase 1 provider spike; require no external installation |
| R-017 | Exact-string configuration replacement silently changes nothing | [CONFIRMED] production lesson | High | High | Normalized plan, precondition match counts, parser/semantic validation, post-apply verification; fail if expected mutation did not occur |
| R-018 | Hash mismatch blocks execution after harmless encoding/newline changes | [CONFIRMED] current engine hash encoding contract | High | Medium | Canonical release manifest/hash rules; tests for encoding/newlines; do not reuse SQL UTF-16 hash semantics blindly |
| R-019 | Arbitrary SQL reaches application databases via DB setting engine | DATABASE_CONTENT_SYNC is powerful | Critical | Medium | Structured trusted predicates only, identifier validation, parameterization, no raw REST/UI SQL |
| R-020 | Linked-server fragility creates cross-instance failures | [CONFIRMED] production lesson; current DB-content engine uses direct SqlConnection | High | Medium | Direct SqlConnection to intended target; linked server not execution transport |
| R-021 | Instance rename leaves dependent rows/orphans | [CONFIRMED] credentials, links, pulse and newer tables reference InstanceCode | Critical | Medium | Dedicated skill with dependency discovery/preview; V1 central read-only means no silent central rename |
| R-022 | Cloned Keycloak retains source URLs/secrets | [CONFIRMED] production lesson | Critical | High | Keycloak post-clone validation must compare every target-specific URL/client/secret; clone not healthy until verified |
| R-023 | IIS reconciliation damages unrelated sites/pools | Current engine is admin-required and mutates IIS | Critical | Medium | Machine/instance ownership checks, desired-vs-actual preview, allowlisted paths/site names, backups where applicable, post-apply verification |
| R-024 | Windows service reconciliation touches management/control-plane service | Current engine is admin-required and service-capable | Critical | Low/Medium | Explicit protected-service denylist plus environment ownership proof |
| R-025 | TSplus/Web Access shared controller operation affects other environments | Existing runtime uses shared-resource semantics | Critical | Medium | Local shared-resource lock and impact preview; never assume per-instance isolation |
| R-026 | Central snapshot exposes current credential material | Current sync contains encrypted ManagedCredential rows and ManagedInstanceRuntime can decrypt inside central SQL | Critical | Medium | Explicit safe-field snapshot contract; exclude old vault ciphertext from local credential authority; never mirror decrypted runtime view |
| R-027 | Central `ops.Engine.ScriptText` mutates local executable code | Current snapshot contains full executable scripts | Critical | Medium | V1 local versioned modules are executable authority; central ScriptText is migration/reference evidence only |
| R-028 | Nightly snapshot and live central DB can differ by time/version | Sync payload is real and versioned, but it is generated periodically | High | Medium | Pin source commit/blob/generation time in evidence; contract versioning; do not silently conflate snapshot with instantaneous live DB |
| R-029 | Scope creep from newer Management Console features | Snapshot contains many features beyond handoff | Medium | High | Inventory them but do not include in V1 without explicit decision |
| R-030 | Browser input controls filesystem paths | Engines manipulate privileged paths | Critical | Medium | Paths resolved from trusted synchronized config; canonicalize; enforce allowed roots; reject traversal/out-of-root |
| R-031 | REST request replay/duplicate clicks execute action twice | Browser/network retries happen | Critical | Medium | Idempotency token + OperationId + coordinator deduplication |
| R-032 | Preview differs materially from Apply | Common orchestration failure mode | Critical | Medium | Apply consumes same normalized plan/fingerprint where possible; invalidate stale preview when inputs/state change |
| R-033 | Backup exists but cannot restore | Backups can provide false confidence | High | Medium | Backup artifact metadata/hash + restore strategy tests for each destructive engine |
| R-034 | Administrator privilege turns UI/API bug into full server compromise | Most core current engines require administrator | Critical | Medium | Minimize API surface, validate all inputs, loopback/session controls, module allowlists, no Invoke-Expression, no raw command construction |
| R-035 | Vendored runtime/dependencies are tampered | Portable package carries executable dependencies | Critical | Low/Medium | Version lock + SHA-256 manifest; CI/package verification; future signing decision |
| R-036 | Old/foreign snapshot is accepted | Portable folder can be moved/copied | Critical | Medium | Snapshot includes source/server identity, contract version and hashes; local activation checks current machine identity |
| R-037 | Clock/time assumptions break expiry/replay checks | Offline credential envelope uses time metadata | Medium | Low/Medium | Sequence/package ID + replay store; expiry policy tolerant but explicit; diagnostics for clock skew |
| R-038 | Operation history grows without bound | Local console persists logs/history | Medium | Medium | Local retention policy; never delete active/recovery evidence; exact policy later |
| R-039 | Current central approval/schedule model is accidentally recreated despite transient V1 design | Snapshot contains governance/scheduling | Medium | Medium | V1 is operator-started/transient; no persistent Windows task/service; scheduling remains out of scope |
| R-040 | V1 UI becomes coupled to Pode and blocks future framework replacement | Architectural maintainability risk | High | Medium | Vanilla HTML/CSS/JS + REST contract; engines/application services have no Pode dependency |
| R-041 | Large-file connector/tool response is mistaken for repository truth | Phase 0 incident: fetch_file returned empty content for a ~29.5 MB non-empty blob | High | Medium | Verify Git tree blob SHA/size; use contents/blob or segmented parser; never infer “empty file” from empty large-file tool response alone |
| R-042 | Stale catalogue metadata points to nonexistent action codes | Snapshot: adapters reference SETTINGS_SYNC and SERVICE_RECONCILE, absent from ops.Action/ops.Engine | High | Medium | Validate all cross-catalogue references; operational mapping comes from validated ops.Action/ops.Engine; fail closed on dangling references |

## Highest-priority risks before engine porting

The following must be resolved or materially reduced before mutable engines are enabled:

1. **R-005/R-006/R-007/R-008/R-026 — credential model and secret handling.**
2. **R-009/R-034 — localhost API security under administrator privilege.**
3. **R-012/R-014/R-031/R-032 — operation coordination, shutdown and idempotency.**
4. **R-015/R-016 — portable PowerShell/IIS/SQLite technical viability.**
5. **R-002/R-036 — trusted snapshot activation.**
6. **R-017/R-019/R-023 — mutation safety for config, SQL and IIS.**
7. **R-041/R-042 — evidence/catalogue validation; no silent assumptions from tooling or stale metadata.**

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

## Evidence handling rule

Repository/snapshot claims must be pinned to a concrete commit/blob where practical.

For oversized files, an empty high-level read is not accepted as evidence of an empty file until Git metadata confirms a zero-byte blob.

Generated snapshot evidence is distinguished from live-environment validation; neither is silently substituted for the other.

## Risk acceptance policy for later agents

A risk may not be marked closed merely because code was written.

Closure requires one of:
- deterministic automated test evidence;
- architecture change eliminating the risk;
- explicit human acceptance;
- **[V]** evidence from the required real Windows/SISQUAL environment.

## Phase 0 acceptance

- Full sync snapshot is now part of the evidence base.
- Production lessons have corresponding risks/controls.
- Pode, SQLite, concurrency and localhost API risks are explicit.
- Security impact of administrator execution is explicit.
- Current snapshot/live-production temporal distinction is explicit.
- Large-file evidence failure mode is explicit.
- Stale adapter/action catalogue references are explicit.
- Phase 1 technical spikes remain identified without prematurely deciding their outcomes.
