# Roadmap to completion

**Date:** 2026-10-05
**Status:** [PROPOSED] - needs project owner approval. Section 4 records the owner's answers of 2026-10-05; items 3 and 4 are still open.
Based on: the approved architecture plan, the Phase 0 documents, ADR-0001 (approved), ADR-0006 (accepted with conditions, owner confirmation requested) and the Phase 1A/1A-2 results.

## 1. Where we are

Done: Phase 0 (inventory), Phase 1A (portable runtime) and Phase 1A-2 (IIS write path). Phase 1 still needs 1B and 1C. The repository has no product code yet; `README.md` is empty.

## 2. Phases

| Phase | Goal | Verified on | Size | Depends on |
|---|---|---|---|---|
| 1B | Machine identity and portable state | GitHub runners (two VMs) | S-M | - |
| 1C | Local web security and lifecycle | GitHub runners | S-M | - |
| 2 | Repository foundation (README, AGENTS.md, CLAUDE.md, ADR index, contracts, test and CI skeleton) | Review only | S | can start now |
| 3 | Local runtime (host, sessions, SQLite, logging, operation coordinator) | Runners | M | 1B, 1C, 2 |
| 4 | Central snapshot sync (read-only) | Runners plus central DB access | M | 3 |
| 5 | Credential packages (signed and encrypted) | Runners (two VMs) | M | 1B, 4 |
| 6 | Engine ports, in waves | Runners, sandbox, real servers | XL | 3, 4, 5 |
| 7 | Operational skills and the new-server wizard | Runners | M | 6 (partly) |
| 8 | Production acceptance and handover | Sandbox, then real servers | L | all |

## 3. Phase details

**1B - machine identity and portable state.** Non-exportable CNG machine key (or machine-scope DPAPI as the fallback); prove that copying the folder to another machine does not carry a usable identity (two runner jobs, folder passed as an artifact); choose the SQLite managed provider that loads in portable PowerShell with no installation; WAL, reopen and first-run state. Risks: R-005, R-007, R-016, R-036. Output: ADR for the provider and ADR for the machine key.

**1C - local web security and lifecycle.** One-time bootstrap token exchanged for an HttpOnly SameSite session; CSRF on every mutating route; Host and Origin validation; CORS denied by default; strict CSP; idempotency token; clean shutdown and behaviour with an active operation. Risks: R-009, R-011, R-014, R-031.

**2 - repository foundation.** `README.md`, `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`, ADR index (ADR-0001 and ADR-0006 exist; the provider, sync, machine-key and concurrency ADRs follow 1B and 1C), contracts (REST, sync manifest, credential envelope, engine result), `tests/` and CI skeleton, `vendor/manifest.json`, packaging skeleton. Acceptance: a new agent can answer from the repository alone what it may change, what needs approval, what is production and how to test.

**3 - local runtime.** Bootstrap, Pode host as an adapter only, session security, SQLite migrations, logging without secrets, operation coordinator (per-instance locks, server-wide locks for destructive work), controlled shutdown. Acceptance: loopback only, CSRF tests, duplicate POST does not duplicate an operation, no secret in any log, SQLite recovery.

**4 - central snapshot sync.** Stage, validate, atomic swap; manifest with hashes and schema version; INITIAL SETUP state when no valid snapshot exists; secret-bearing surfaces (for example `cfg.ManagedInstanceRuntime`) never enter the snapshot (R-026). Failure cases (central down, corrupt, incompatible schema, partial transfer, duplicate, older snapshot) keep the last valid cache usable. Transport (direct read-only SQL versus exported snapshot) is [PENDING].

**5 - credential packages.** Envelope encrypted for the machine key and signed by the central side; target server, key fingerprint, expiry and sequence are validated before decryption. Acceptance: a package for SERVER-A fails on SERVER-B even with the folder copied; tampered, expired, replayed and wrong-fingerprint packages fail. The central side must be able to produce packages; where that tool lives is [PENDING] (see section 4).

**6 - engine ports.** Each engine needs preview, apply, idempotency, structured result, backup and restore strategy, a secret-safety test, a Windows PowerShell 5.1 parser check, and a Windows CI run before review. Waves, following the Phase 0 matrix and the plan:
1. `DEPLOYMENT_PREFLIGHT`, `PULSE_STATUS`;
2. `CONFIG_REPAIR` (preview, then apply), `MANAGED_ASSETS`;
3. `IIS_RECONCILE` on Microsoft.Web.Administration, after the ADR-0006 conditions;
4. `WINDOWS_SERVICES`, `V8_KEYCLOAK_PREREQUISITES`, `V8_KEYCLOAK_SERVICE`, `KEYCLOAK_CLIENT_SECRETS`;
5. `WEB_ACCESS`, `LINKS_PAGES`, `DATABASE_CONTENT_SYNC`;
6. `FULL_DEPLOYMENT` last, as orchestration of validated engines (13 steps, 12 enabled; `V8_KEYCLOAK_CONFIG` stays disabled).
Not testable on a runner: TSplus and Web Access (`WEB_ACCESS`), a real Keycloak topology, real SQL data. Whether the runner images can host SQL Server is [PENDING].

**7 - skills and wizard.** `bootstrap-new-server`, `rename-instance`, `keycloak-client-provisioning`, `config-repair-rule-authoring`, `credential-portability`, each calling the same modules as the application. A new-server wizard that computes Keycloak ports and customer codes, lists every physical prerequisite, warns when not run from the sync origin and generates the SQL for the central database without writing to it (V1 never writes back).

**8 - production acceptance.** ADR-0006 conditions closed; unit and static tests; disposable VM; SISQUAL sandbox; one controlled real server; then the rest. Includes backup and restore verification (R-033), a threat-model review, signed release package with hashes, handover documentation and the coexistence plan with the current Management Console.

## 4. Decisions and access needed from the project owner

1. [DECIDED 2026-10-05] ADR-0006 confirmed by the project owner (IIS through Microsoft.Web.Administration, four conditions).
2. [DECIDED 2026-10-05] Central sync transport: direct read-only SQL connection.
3. [OPEN] Credential packages. Proposal: a script in this repository that runs on the central server, only reads the central database and produces one package per target machine; the signing key stays on the central server; the current Management Console is not changed. Needs owner agreement.
4. [OPEN] Real-topology IIS run (ADR-0006 condition 2). Question: which machine may be used to run the write test, which creates and removes prefixed test sites, a local user and a certificate? Alternative: a read-only topology probe on a real server plus the runner results.
5. [DECIDED 2026-10-05] V1 scope: all engines.

## 5. Parallelism and cadence

- Phase 2 starts now, in parallel with 1B and 1C.
- After the Phase 3 engine contract exists, engines in the same wave can be ported in parallel.
- One branch and one PR per piece of work; every merge records its evidence under `docs/`.

## 6. Definition of done

Copy a folder to a SISQUAL Windows Server that never had the Deploy Console, run `Start.cmd`, install nothing; the console identifies the machine, validates its identity, syncs central configuration, shows exactly what it will change, executes only after confirmation, keeps local evidence, never reveals credentials, and leaves nothing behind when the process ends.
