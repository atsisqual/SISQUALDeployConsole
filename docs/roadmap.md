# Roadmap to completion

**Date:** 2026-10-10
**Status:** accepted as the working plan (PR #9 was merged on the owner's instruction); updated by the reviewer for ADR-0007 and the owner decisions recorded in `docs/decisions-log.md`. Repository status below is refreshed against `main@a1f84e0a5322f58ff03a67671a7376fe30ae03d5` and current pull-request metadata.
Tags: [CONFIRMED] demonstrated, [PROPOSED] recommended, [PENDING] undecided, [DECIDED] owner decision, [CLOSED] explicitly closed, [V] needs a real server.

## 1. Where we are

Integrated in `main`:

- Phase 0 inventory; Phase 1A (portable runtime) and 1A-2 (IIS write path); ADR-0001 accepted and ADR-0006 accepted with four conditions.
- Phase 1B evidence for the non-exportable machine identity and the managed SQLite provider; the product runtime catalog uses the accepted `Microsoft.Data.Sqlite` provider.
- Phase 1C local web-security and operation-coordinator spikes, validated on disposable Windows runners.
- Phase 2: README, AGENTS.md, CLAUDE.md, contracts (draft), skill skeletons, CI, and the audit of the guidance against ADR-0007.
- ADR-0007 accepted: no central database, no runtime sync, one read-only SQLite catalog per machine, signed manifest, credentials outside the portable, text logs.
- Conversion chain B1 to B5: `Export-ManagementEngines`, `Convert-ManagementDb` (new-machine and cut modes), a LocalDB integration test, `Test-CatalogConversion` and `Seal-Package`; `Microsoft.Data.SqlClient` 7.1.1 pinned.
- Credential tooling B6.1 through B6.3b: package crypto/contract implementation, encrypted vault and issuer signing, vault secret model, and the one-time credential importer with DryRun/Import/Verify and LocalDB integration coverage.
- Phase 3 runtime foundations: bootstrap, read-only runtime catalog factory and hardened text logging.
- ADR-0008 engine host runtime, integrated by PR #66.
- `DEPLOYMENT_PREFLIGHT`, the first real engine, integrated by PR #67. Its source declares `CoverageImplemented = 31` and `CoverageTotal = 66`: this is coverage **by original issue-code name**, not proof that the implemented predicates are one-to-one copies of the original reviews.
- Engine-host contract documentation, integrated by PR #68.
- D2 action cross-reference and D3 SQL-action decision briefs, integrated by PR #70 and PR #71.
- The date-dependent logging rollover test correction, integrated by PR #72.
- `runtime/` source tracking and the `[DECIDED]`/`[CLOSED]` status vocabulary, integrated by PR #73.
- ADR-0010 verified-package-state proposal, integrated as documentation by PR #75. Its trust-bootstrap changes remain subject to the approval state recorded in the ADR/decisions log.
- Pending-marker audit, integrated by PR #77.
- D6/D7/D8/D11 specification corrections, integrated by PR #79, PR #80, PR #81 and PR #82.
- The original preflight-procedure evidence used for the predicate work, integrated by PR #83, PR #89 and PR #90.

Current coordination/documentation branches outside `main` are not described as product changes "in review":

- PR #69 remains open as the reviewer-owned porting-guide/work-queue coordination branch. It is deliberately not treated as integrated product state.
- PR #78 is the text-only `PULSE_STATUS` port brief and remains separate from `main` while its documented dependency on the work-queue material is unresolved.
- PRs #84-#88 are the D13 predicate specifications for the original preflight checks that were outside the first engine slice.
- PRs #91-#99 are the D14 parity audits of the nine original review procedures already represented by the integrated engine.
- PR #101 is the D12 documentation correction for secret-reference family semantics; PR #102 is the D1 engine-result-row contract. Neither is part of `main` until the reviewer integrates it.

### DEPLOYMENT_PREFLIGHT coverage and parity

[CONFIRMED] The integrated engine reports **31 of 66 original issue-code names**. The remaining name coverage is therefore 35 codes. This number is an inventory count only.

[PROPOSED] **E0h is the parity pass.** The D14 audits compare the original predicates with the integrated engine and classify differences as `ARQUITECTURAL` (approved portable-system behavior to preserve) or `DIVERGENCIA` (predicate/name/edge behavior for E0h to correct). E0h must not turn the 31/66 name count into a claim of semantic parity; it closes the documented `DIVERGENCIA` rows while preserving approved architecture such as credential-package use, machine-local scope and exact catalog codes.

The complete portable application is not finished: machine identity and Phase 1C controls are validated but still need final product integration, B6.4 per-machine credential-package issue remains, most production engine ports and `FULL_DEPLOYMENT` orchestration remain, E0h parity remains, and production acceptance is still [V].

## 2. Progress estimate and remaining phases

[PROPOSED] Completion is reported with three measures from `docs/handoff/remaining-work-plan.md` section 1. They answer different questions and none is a commitment, acceptance criterion or earned-value calculation.

| Measure | What it counts | Estimate |
|---|---|---:|
| Share of the roadmap's remaining phases done | Only the work represented by the roadmap's remaining phases, using planned pull-request counts as weights. It excludes Phase 0 to 2, conversion B1 to B5 and other work completed before that roadmap. | about 17% (13 of 70) |
| Whole project by pull requests | Work completed before the roadmap plus work completed since, divided by the whole project including the 19 pull requests added by the parity/audit work (`E0h` and `E0b` to `E0g`). | about 36 to 45% |
| Area-weighted whole project | Work areas weighted by estimated effort; the engine work is treated as roughly half of the project and remains the largest and least advanced area. | about 33 to 35% |

Central planning estimate: **about 35%**, with a broad **30 to 45%** range. The largest uncertainty is the weight of the engine work, which is both the largest and least advanced area. Nothing is validated on a real server [V]. Recompute at the end of each milestone and state which measure is being used.

The older PR-count ranges below are also planning estimates, not commitments:

| Phase | Goal | Verified on | PRs (estimate) |
|---|---|---|---|
| B6 | Credential tool: vault, one-time import from the live database, per-machine package, real signer and verifier, application-side validation | Runners and LocalDB; [V] live database | 4-6 |
| 1B | Machine identity: non-exportable key, copying the folder does not carry the identity (two VMs), read-only SQLite open, ADR for the key | Runners (two VMs) | 2-3 |
| 1C | Local web security: session, CSRF, Host and Origin, CSP, idempotency, clean shutdown | Runners | about 2 |
| 3 | Local runtime: startup, manifest and catalog verification, credentials import route, logs, locks, shutdown | Runners | 6-8 |
| E0h | `DEPLOYMENT_PREFLIGHT` semantic parity: apply D14 `DIVERGENCIA` findings while preserving `ARQUITECTURAL` differences | Windows runners; then [V] comparison on a real server | [PROPOSED] follow-up parity work, size determined by the audits |
| 6 | Engine ports: 17 portable engines in total; `DEPLOYMENT_PREFLIGHT` is integrated, the remaining engines and `FULL_DEPLOYMENT` orchestration still follow the wave plan | Runners, sandbox, real servers | 30-45 for the original engine-wave estimate |
| 7 | Skills and the new-server wizard | Runners | 6-8 |
| 8 | Production acceptance and handover | Sandbox, then one real server | 8-10 |

The earlier overall estimate of about 60 to 90 PRs, roughly half engines, remains an estimate rather than a delivery commitment.

## 3. Phase notes

- **B6.** The existing credentials are encrypted with a key protected by a certificate of the live database, so the one-time import must run where that database is reachable [V]. Vault: one encrypted file outside Git and outside the portable (`contracts/credential-package.md`, Q9).
- **1B and 1C.** Both can run on GitHub runners; copying the folder between machines is tested with two runner jobs and an artifact.
- **3.** Packaging includes the SQL client files (see section 5).
- **E0h.** The input is the D14 audit set. A row marked `ARQUITECTURAL` documents an intentional approved difference and is not reverted for legacy parity. A row marked `DIVERGENCIA` is the correction list. The integrated engine's 31/66 count remains a by-name coverage metric until this parity work is complete.
- **Before wave 5.** Extend `Convert-ManagementDb` (cut and new-machine modes) and `Test-CatalogConversion` with the instance directory, and update `contracts/catalog-schema.md`.
- **7.** The new-server wizard generates scripts and checklists; it never writes to a database.
- **8.** Includes the ADR-0006 conditions 2 to 4, backup and restore verification, a threat-model review, a signed package, handover documents, and the cutover: the first deployment is on a server without the current system; existing servers are switched when the owner decides.

## 4. Engine waves (all 19 source-era engines are covered: 17 portable engines, 2 absorbed)

The order of the seven engines that were outside the earlier plan was chosen by the reviewer on the owner's delegation (2026-10-05): safest first, destructive last. Each mutating engine needs preview, apply, idempotency, a structured result, a backup and restore strategy, a secret-safety test and a Windows CI run before review; read-only/observational engines follow their approved host class rather than inventing apply semantics.

1. `DEPLOYMENT_PREFLIGHT` (integrated by PR #67; incomplete by-name coverage and E0h parity remain), `PULSE_STATUS`
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
- [DECIDED 2026-10-06] Pulse keeps today's scope: same server and same country. The collector runs from the portable `pwsh.exe` at its current path and apply re-registers the task; the task keeps the hub instance's IIS identity in V1 and apply is run again after a new `IIS_IDENTITY` credential; a machine without a Pulse profile reports `not applicable` and does not fail. See `docs/migration/analysis-pulse.md` section 9 and the owner decisions in `docs/decisions-log.md`.
- [DECIDED 2026-10-05] The 25 `Microsoft.Data.SqlClient` files go inside the portable and are covered by the manifest.
- [CONFIRMED] 2026-10-06 `Microsoft.Data.Sqlite` 10.0.12 is adopted by the runtime catalog. The managed provider/runtime uses native SQLite 3.53.3 and the separate CLI/tooling uses SQLite 3.53.4. Phase 1B provider evidence is run 37392036026; product integration and accepted runtime evidence are recorded in `docs/phase3/sqlite-runtime-adoption.md` and `docs/phase3/runtime-catalog.md`. The remaining package-manifest work is to record the two SQLite roles semantically in addition to hashing the shipped provider files.
- [CLOSED 2026-10-06] `DATABASE_SETTINGS` has no separate port (see section 4).
- [DECIDED 2026-10-06] Installers come from an operator-provided folder with fixed versions, and every artifact is verified by SHA-256 before use. Keycloak requires exactly JDK 23, pinned and verified by SHA-256: no LTS substitution, no dynamic selection, no `latest`.
- [CLOSED 2026-10-05] Machines without a local database: obsolete under ADR-0007.

## 6. Validations that need a real server [V]

Counts and orphan rows in the live database; the real collation of `_sisqualMANAGEMENT`; SQL connection encryption and certificate rules; reading the credentials through the old route and the one-time import; engine behaviour on real topologies; ADR-0006 conditions 2 to 4.

## 7. Cadence

One branch and one PR per piece of work; stacked PRs name their order of integration; every merge records its evidence under `docs/`. Engines of the same wave can be ported in parallel once the engine contract exists.

## 8. Definition of done

Copy a folder to a SISQUAL Windows Server that never had the Deploy Console, run `Start.cmd`, install nothing; the console identifies the machine, verifies its package and catalog, shows exactly what it will change, executes only after confirmation, keeps local text logs, never reveals credentials, and leaves nothing behind when the process ends.

## 9. Follow-up changes decided on 2026-10-06

No decision is needed to start them; each is a small PR: the manifest counter against rollback (a contract change, K3); the structured database filters in the conversion tool and the catalog contract (C7); the action-code cross-reference check in `Test-CatalogConversion` (C8); the instance directory in the conversion tool (C1, C2); the catalog-change function in the tools after option A for link visibility (C9); the removal of the `V8_KEYCLOAK_CONFIG` action, its engine row and step 63 and of the legacy `DATABASE_SETTINGS` engine row and `cfg.DatabaseSettingRule` from the catalog.
