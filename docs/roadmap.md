# Roadmap to completion

**Date:** 2026-10-05 (updated after ADR-0007)
**Status:** accepted as the working plan (PR #9 was merged on the owner's instruction); updated by the reviewer for ADR-0007 and the owner decisions of 2026-10-05, which are in `docs/decisions-log.md`.
Tags: [CONFIRMED] demonstrated, [PROPOSED] recommended, [PENDING] undecided, [V] needs a real server.

## 1. Where we are

Integrated in `main`:
- Phase 0 inventory; Phase 1A (portable runtime) and 1A-2 (IIS write path); ADR-0001 accepted and ADR-0006 accepted with four conditions.
- Phase 2: README, AGENTS.md, CLAUDE.md, contracts (draft), skill skeletons, CI, and the audit of the guidance against ADR-0007.
- ADR-0007 accepted: no central database, no runtime sync, one read-only SQLite catalog per machine, signed manifest, credentials outside the portable, text logs.
- Conversion chain B1 to B5: `Export-ManagementEngines`, `Convert-ManagementDb` (new-machine and cut modes), a LocalDB integration test, `Test-CatalogConversion` and `Seal-Package`; `Microsoft.Data.SqlClient` 7.1.1 pinned.

Not started: the portable application itself, the credential tool, machine identity, local web security and the engines.

## 2. Remaining phases

| Phase | Goal | Verified on | PRs (estimate) |
|---|---|---|---|
| B6 | Credential tool: vault, one-time import from the live database, per-machine package, real signer and verifier, application-side validation | Runners and LocalDB; [V] live database | 4-6 |
| 1B | Machine identity: non-exportable key, copying the folder does not carry the identity (two VMs), read-only SQLite open, ADR for the key | Runners (two VMs) | 2-3 |
| 1C | Local web security: session, CSRF, Host and Origin, CSP, idempotency, clean shutdown | Runners | about 2 |
| 3 | Local runtime: startup, manifest and catalog verification, credentials import route, logs, locks, shutdown | Runners | 6-8 |
| 6 | Engine ports: 19 engines plus the `FULL_DEPLOYMENT` orchestration | Runners, sandbox, real servers | 30-45 |
| 7 | Skills and the new-server wizard | Runners | 6-8 |
| 8 | Production acceptance and handover | Sandbox, then one real server | 8-10 |

About 60 to 90 PRs in total, half of them engines. These are estimates, not commitments.

## 3. Phase notes

- **B6.** The existing 191 credentials are encrypted with a key protected by a certificate of the live database, so the one-time import must run where that database is reachable [V]. Vault: one encrypted file outside Git and outside the portable (contracts/credential-package.md, Q9).
- **1B and 1C.** Both can run on GitHub runners; copying the folder between machines is tested with two runner jobs and an artifact.
- **3.** Packaging includes the SQL client files (see section 5).
- **7.** The new-server wizard generates scripts and checklists; it never writes to a database.
- **8.** Includes the ADR-0006 conditions 2 to 4, backup and restore verification, a threat-model review, a signed package, handover documents, and the cutover: the first deployment is on a server without the current system; existing servers are switched when the owner decides.

## 4. Engine waves (all 19 engines are in V1)

The order of the seven engines that were outside the earlier plan was chosen by the reviewer on the owner's delegation (2026-10-05): safest first, destructive last. Each engine needs preview, apply, idempotency, a structured result, a backup and restore strategy, a secret-safety test and a Windows CI run before review.

1. `DEPLOYMENT_PREFLIGHT`, `PULSE_STATUS`
2. `CONFIG_REPAIR` (preview, then apply), `MANAGED_ASSETS`
3. `IIS_RECONCILE` on Microsoft.Web.Administration, after the ADR-0006 conditions
4. `WINDOWS_SERVICES`, `V8_KEYCLOAK_PREREQUISITES`, `V8_KEYCLOAK_SERVICE`, `KEYCLOAK_CLIENT_SECRETS`
5. `WEB_ACCESS`, `LINKS_PAGES`, `DATABASE_CONTENT_SYNC`
6. `FULL_DEPLOYMENT` as orchestration of the validated engines (13 steps, 12 enabled)
7. Read-only diagnostics: `ENVIRONMENT_STATE_PROBE`, `STORAGE_SIZE_SCAN`, `MODEL_REVIEW`
8. `LINKS_VISIBILITY`, and `V8_KEYCLOAK_CONFIG` (disabled in `FULL_DEPLOYMENT`)
9. `DATABASE_COPY` (destructive; only after the backup and restore strategy is proven)

[PROPOSED] `DATABASE_SETTINGS` is the old engine that its action no longer uses (the action points to `DATABASE_CONTENT_SYNC`); its behaviour is covered by wave 5, so it is not ported separately. Not testable on a runner: TSplus and Web Access, a real Keycloak topology, real SQL data.

## 5. Open items

- [PENDING] Whether a catalog needs a directory of the instances of other machines (hub link pages). Today nothing is carried from another machine. Decide before wave 5 (`LINKS_PAGES`).
- [PENDING] How the 25 `Microsoft.Data.SqlClient` files reach the operator. [PROPOSED] they are vendored inside the portable and covered by the manifest; decide in Phase 3.
- [PENDING] SQLite managed provider (Phase 1B, read-only open only).
- [PENDING] Whether `DATABASE_SETTINGS` needs a separate port (proposed: no).
- [CLOSED 2026-10-05] Machines without a local database: obsolete under ADR-0007.

## 6. Validations that need a real server [V]

Counts and orphan rows in the live database; the real collation of `_sisqualMANAGEMENT`; SQL connection encryption and certificate rules; reading the credentials through the old route and the one-time import; engine behaviour on real topologies; ADR-0006 conditions 2 to 4.

## 7. Cadence

One branch and one PR per piece of work; stacked PRs name their order of integration; every merge records its evidence under `docs/`. Engines of the same wave can be ported in parallel once the engine contract exists.

## 8. Definition of done

Copy a folder to a SISQUAL Windows Server that never had the Deploy Console, run `Start.cmd`, install nothing; the console identifies the machine, verifies its package and catalog, shows exactly what it will change, executes only after confirmation, keeps local text logs, never reveals credentials, and leaves nothing behind when the process ends.
