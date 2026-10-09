# Roadmap to completion

**Date:** 2026-10-09
**Status:** accepted as the working plan (PR #9 was merged on the owner's instruction); updated by the reviewer for ADR-0007 and the owner decisions recorded in `docs/decisions-log.md`. Repository status below is refreshed from `main` and the named pull requests on 2026-10-09.
Tags: [CONFIRMED] demonstrated, [PROPOSED] recommended, [PENDING] undecided, [V] needs a real server.

## 1. Where we are

Integrated in `main`:
- Phase 0 inventory; Phase 1A (portable runtime) and 1A-2 (IIS write path); ADR-0001 accepted and ADR-0006 accepted with four conditions.
- Phase 1B evidence for the non-exportable machine identity and the managed SQLite provider; the product runtime catalog now uses the accepted `Microsoft.Data.Sqlite` provider.
- Phase 1C local web-security and operation-coordinator spikes, validated on disposable Windows runners.
- Phase 2: README, AGENTS.md, CLAUDE.md, contracts (draft), skill skeletons, CI, and the audit of the guidance against ADR-0007.
- ADR-0007 accepted: no central database, no runtime sync, one read-only SQLite catalog per machine, signed manifest, credentials outside the portable, text logs.
- Conversion chain B1 to B5: `Export-ManagementEngines`, `Convert-ManagementDb` (new-machine and cut modes), a LocalDB integration test, `Test-CatalogConversion` and `Seal-Package`; `Microsoft.Data.SqlClient` 7.1.1 pinned.
- Credential tooling B6.1 through B6.3b: package crypto/contract implementation, encrypted vault and issuer signing, vault secret model, and the one-time credential importer with DryRun/Import/Verify and LocalDB integration coverage.
- Phase 3 runtime foundations: bootstrap, read-only runtime catalog factory and hardened text logging.
- ADR-0008 engine host runtime, integrated by PR #66.
- D2 action cross-reference decision brief, integrated by PR #70; D3 SQL-action replacement decision brief, integrated by PR #71.
- The date-dependent logging rollover test correction, integrated by PR #72.
- `runtime/` source tracking and the `[DECIDED]`/`[CLOSED]` status vocabulary, integrated by PR #73.

In review, not integrated in `main`:
- PR #67 is a draft `DEPLOYMENT_PREFLIGHT` port. Its current source declares incomplete coverage of 29 of the 59 original review issue codes; the PR discussion records owner decision A for this explicitly incomplete first slice.
- PR #68 documents engine host contracts.
- PR #69 carries the engine porting guide and work queue.

The complete portable application is not finished: machine identity and Phase 1C controls are validated but still need final product integration, B6.4 per-machine credential-package issue remains, and the production engine ports plus `FULL_DEPLOYMENT` orchestration remain to be implemented.

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
- **Before wave 5.** Extend `Convert-ManagementDb` (cut and new-machine modes) and `Test-CatalogConversion` with the instance directory, and update `contracts/catalog-schema.md`.
- **7.** The new-server wizard generates scripts and checklists; it never writes to a database.
- **8.** Includes the ADR-0006 conditions 2 to 4, backup and restore verification, a threat-model review, a signed package, handover documents, and the cutover: the first deployment is on a server without the current system; existing servers are switched when the owner decides.

## 4. Engine waves (all 19 engines are covered: 17 are ported as engines, 2 are absorbed)

The order of the seven engines that were outside the earlier plan was chosen by the reviewer on the owner's delegation (2026-10-05): safest first, destructive last. Each engine needs preview, apply, idempotency, a structured result, a backup and restore strategy, a secret-safety test and a Windows CI run before review.

1. `DEPLOYMENT_PREFLIGHT`, `PULSE_STATUS`
2. `CONFIG_REPAIR` (preview, then apply), `MANAGED_ASSETS`
3. `IIS_RECONCILE` on Microsoft.Web.Administration, after the ADR-0006 conditions
4. `WINDOWS_SERVICES`, `V8_KEYCLOAK_PREREQUISITES`, `V8_KEYCLOAK_SERVICE`, `KEYCLOAK_CLIENT_SECRETS`
5. `WEB_ACCESS`, `LINKS_PAGES`, `DATABASE_CONTENT_SYNC`
6. `FULL_DEPLOYMENT` as orchestration of the validated engines (13 steps, 12 enabled)
7. Read-only diagnostics: `ENVIRONMENT_STATE_PROBE`, `STORAGE_SIZE_SCAN`, `MODEL_REVIEW`
8. `LINKS_VISIBILITY` (a read-only matrix first; a change is an owner edit of the catalog followed by a seal)
9. `DATABASE_COPY` (destructive; only after the backup and restore strategy is proven)

[DECIDED 2026-10-06, owner Q3] `DATABASE_SETTINGS` and `V8_KEYCLOAK_CONFIG` are not ported as autonomous engines: their behaviour is absorbed by `DATABASE_CONTENT_SYNC` (14 of 14 rules present, same template and flags) and by the `CONFIG_REPAIR` rule `KEYCLOAK_DB_URL`. There is no functional loss; the evidence is in their specifications. Not testable on a runner: TSplus and Web Access, a real Keycloak topology, real SQL data.

## 5. Open items

- [DECIDED 2026-10-05] Links pages stay as today: the general page on the main instance, an individual page in each IIS site under `links`. From the source, the general page lists every enabled instance of the same country across all machines, so a catalog that hosts a general page carries a read-only instance directory. [PENDING] Exact columns and which catalogs carry it; [PROPOSED] only catalogs of machines with an instance whose `LinksIncludeAllInstances` is 1, public columns only (codes, names, host name), in a table separate from the instance rows. Tool change needed before wave 5.
- [DECIDED 2026-10-06] Pulse keeps today's scope: same server and same country. The collector runs from the portable `pwsh.exe` at its current path and apply re-registers the task; the task keeps the hub instance's IIS identity in V1 and apply is run again after a new `IIS_IDENTITY` credential; a machine without a Pulse profile reports "not applicable" and does not fail. See `docs/migration/analysis-pulse.md` section 9 and the four owner decisions in `docs/decisions-log.md`.
- [DECIDED 2026-10-05] The 25 `Microsoft.Data.SqlClient` files go inside the portable and are covered by the manifest.
- [CONFIRMED] 2026-10-06 `Microsoft.Data.Sqlite` 10.0.12 is adopted by the runtime catalog. The managed provider/runtime uses native SQLite 3.53.3 and the separate CLI/tooling uses SQLite 3.53.4. Phase 1B provider evidence is run 37392036026; product integration and accepted runtime evidence are recorded in `docs/phase3/sqlite-runtime-adoption.md` and `docs/phase3/runtime-catalog.md`. The remaining package-manifest work is to record the two SQLite roles semantically in addition to hashing the shipped provider files.
- [CLOSED 2026-10-06] `DATABASE_SETTINGS` has no separate port (see section 4).
- [DECIDED 2026-10-06] Installers come from an operator-provided folder with fixed versions, and every artifact is verified by SHA-256 before use. Keycloak requires exactly JDK 23, pinned and verified by SHA-256: no LTS substitution, no dynamic selection, no "latest".
- [CLOSED 2026-10-05] Machines without a local database: obsolete under ADR-0007.

## 6. Validations that need a real server [V]

Counts and orphan rows in the live database; the real collation of `_sisqualMANAGEMENT`; SQL connection encryption and certificate rules; reading the credentials through the old route and the one-time import; engine behaviour on real topologies; ADR-0006 conditions 2 to 4.

## 7. Cadence

One branch and one PR per piece of work; stacked PRs name their order of integration; every merge records its evidence under `docs/`. Engines of the same wave can be ported in parallel once the engine contract exists.

## 8. Definition of done

Copy a folder to a SISQUAL Windows Server that never had the Deploy Console, run `Start.cmd`, install nothing; the console identifies the machine, verifies its package and catalog, shows exactly what it will change, executes only after confirmation, keeps local text logs, never reveals credentials, and leaves nothing behind when the process ends.

## 9. Follow-up changes decided on 2026-10-06

No decision is needed to start them; each is a small PR: the manifest counter against rollback (a contract change, K3); the structured database filters in the conversion tool and the catalog contract (C7); the action-code cross-reference check in `Test-CatalogConversion` (C8); the instance directory in the conversion tool (C1, C2); the catalog-change function in the tools after option A for link visibility (C9); the removal of the `V8_KEYCLOAK_CONFIG` action, its engine row and step 63 and of the legacy `DATABASE_SETTINGS` engine row and `cfg.DatabaseSettingRule` from the catalog.