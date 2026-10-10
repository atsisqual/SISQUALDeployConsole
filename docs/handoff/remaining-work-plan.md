# Remaining work plan

**Status:** [PROPOSED] The order below is the reviewer's recommendation. The owner has not approved it; the decisions that change it are in section 6.
**Date:** 2026-10-10. **Base:** `main@41d09f3` (after PR #67).
**What this is:** the one list of everything that is left, in order, with who does each step, what it needs first and how we know it is done. `docs/handoff/work-queue.md` keeps the detail of the engine and documentation tasks; this file is the order and the gates. Tags: [CONFIRMED] checked against the repository, [PROPOSED] recommended, [PENDING] undecided, [DECIDED] owner decision, [CLOSED] nothing left, [V] needs a real server.

## 0. Rules for every agent

1. One task is one pull request. One commit and one push per correction. Authors never merge: the reviewer merges, after checking the pull request against the rules below.
2. **Evidence rule.** A predicate, a column or a number comes from an evidence file or from `tests/Fixtures/carried-schema.json`, never from a name or from memory. The evidence files are `docs/handoff/preflight-legacy-procedures.sql.txt` and `docs/handoff/preflight-legacy-procedures-implemented.sql.txt`. Say what you did not verify.
3. **Who does what.** The reviewer (Claude) writes and tests code and runs CI. GPT writes documents (briefs, audits, specifications, runbooks) and cannot run code or read the 29 MB snapshot, so it receives evidence files instead. The owner decides, holds the secrets and runs anything on a real server. GPT does not open code pull requests unless the owner says so.
4. Never edit another author's comment (a Codex comment included); reply in the thread. Do not touch a pull request that is not yours.
5. Status tokens only: `[CONFIRMED]`, `[PROPOSED]`, `[PENDING]`, `[DECIDED]`, `[CLOSED]`, `[V]`. No secret, no path to a secret, no real customer data in the repository.
6. **Review gate** [PROPOSED]. A pull request is merged when CI is green and (a) the Codex cloud review of the exact head has no P1, or (b) the API reviewer (PR #100, once the owner adds the key) has no P1, or (c) for text whose facts the reviewer re-checked mechanically, the owner agrees in writing. **Round cap for code** [PENDING, owner]: after three review rounds only P1 findings block; the rest become registered tasks.
7. Cross-instance rule and containment rule for engines: `docs/handoff/preflight-port-gap.md`, rules 6 and 7 (in PR #69 until it is merged).

## 1. Where we are [CONFIRMED on 2026-10-10]

- **The console does not start yet.** `runtime/Start-SisqualDeployConsole.ps1` ends with `exit 21` and the message "package integrity verifier is not integrated yet. Startup is blocked" (Phase 3A stops on purpose before the verifier of B6.2). `Start.cmd` also needs `runtime\pwsh\pwsh.exe`, which is not in the repository.
- **One engine file.** `engines/Invoke-DeploymentPreflight.ps1`: 31 of the 66 original issue codes by name, and the nine reviews it implements were audited against the original (PRs #91 to #99): many predicates are the engine's own, not the original's. Its result says so (`PREFLIGHT_COVERAGE_INCOMPLETE`). 0 of the 17 engines are complete.
- **Done and tested on Windows runners:** conversion chain B1 to B5 (the six real catalogs convert), credential tooling B6.1 to B6.3b (vault, signer, verifier, one-time importer), read-only catalog, hardened logging, engine host with its contract (PR #66), the first preflight slice (PR #67).
- **Open pull requests** (all documents except #100): #69 queue and porting guide, #78 Pulse brief, #84 to #88 predicate specifications, #91 to #99 audits, #100 second reviewer (inert without the key), #101 to #103 contract text, result rows, roadmap. The Codex cloud review has no quota.
- **Pace.** 79 pull requests merged between 4 and 9 October, 56% of them documents. Engine code is slower: PR #67 took twelve review rounds.
- **Completion** [PROPOSED estimates, three measures that answer different questions; none is a commitment]. (1) **Share of the roadmap's remaining phases done: about 17%** (planned pull requests as weights: B6 70%, 1B 60%, 1C 60%, 3 55%, engines 7%, skills 5%, acceptance 0%; 13 of 70). It does not count what was already done before that roadmap (Phase 0 to 2, the conversion chain B1 to B5, about 30 to 50 pull requests). (2) **Whole project, by pull requests** (done before the roadmap plus done since, over everything including the 19 pull requests that this week's audits added: E0h and E0b to E0g): **about 36 to 45%**. (3) The status of 2026-10-07 used weights by area of work (architecture 10%, catalog and conversion 15%, credentials and security 15%, runtime 20%, engines 25%, skills 5%, production 10%) and gave **48%**; with the engines at the half of the work that the roadmap says they are (weight 45 to 50%) and 7% done, the same table gives **33 to 35%**. Central estimate: **about 35%** (range 30 to 45%). Nothing is validated on a real server [V]. The weakest part of every measure is the weight of the engines, which is the largest and least advanced area. Recompute at the end of each milestone, stating which measure is used.

## 2. Milestones

| Milestone | Goal | Done when (verifiable) | Pull requests |
|---|---|---|---|
| M0 | Unblock the review and integrate what is verified | the pending document pull requests are merged or answered; decisions of section 6 taken | 0 new |
| M1 | **First executable slice** | on a clean Windows runner and on one owner machine: copy the sealed folder, run `Start.cmd preflight`; it identifies the machine, verifies the package, opens the catalog read-only, runs `DEPLOYMENT_PREFLIGHT` in preview with the machine's credentials and prints the result; a CI job proves it on a synthetic package; the owner run on a real catalog is recorded | 10 to 12 |
| M2 | Engine fidelity and the rest of the preflight | the nine reviews at parity or with owner-approved deviations; the 35 missing codes ported; coverage 66 of 66 and the incomplete notice removed; the preflight run on the six real catalogs | 15 |
| M3 | Engine waves 1 to 9 and `FULL_DEPLOYMENT` | each engine: brief, port, tests, proof on a runner; real-server proof [V] where the engine needs it | 30 to 40 |
| M4 | Operator surface and skills | local web UI with the Phase 1C controls; skills; new-server wizard (generates scripts and checklists, never writes a database) | 10 to 14 |
| M5 | Acceptance and handover [V] | ADR-0006 conditions 2 to 4, backup and restore verification, threat-model review, signed package, handover documents, first deployment on a server without the current system | 8 to 10 |

M1 comes first because it is the only milestone that shows a working console. If the owner prefers fidelity first, M2 goes before M1 and no task below changes.

## 3. Tasks

### M0 Unblock
| ID | Who | Task | Needs |
|---|---|---|---|
| M0.1 | owner | Add the secret `OPENAI_API_KEY` (Settings, Secrets, Actions), or decline | nothing |
| M0.2 | reviewer | Merge PR #100 (second reviewer) | M0.1 |
| M0.3 | reviewer | Merge the document pull requests whose review gate is met, in this order: #69, #78, #84 to #88, #91 to #99, #101 to #103 | rule 6 |
| M0.4 | owner | Section 6 decisions D-A to D-F | nothing |

### M1 First executable slice
| ID | Who | Task | Needs | Done when |
|---|---|---|---|---|
| M1.1 | reviewer | Package assembly: `tools/Build-Package.ps1` assembles the portable folder (portable `pwsh`, SqlClient files, SQLite provider, runtime, engines, contracts, catalog, manifest) and a workflow uploads it | none | the artifact contains everything `Start.cmd` needs and `Seal-Package` seals it |
| M1.2 | reviewer | Startup integrity, part a: replace the `exit 21` stop with the pinned issuer key, the signature and the file hashes (`Verify-PackageSignature`), failing closed with a logged event | M1.1 | a tampered file, a wrong key and a missing manifest each stop startup with a distinct code, each tested |
| M1.2b | reviewer | Part b: the K3 counter and the immutable verified state of ADR-0010 | D-C (owner approves ADR-0010) | the equal-counter, rollback and concurrent-start cases of the ADR are tested |
| M1.3 | reviewer | Machine identity at startup (Phase 1B in the product): non-exportable key; a copied folder does not carry the identity | M1.2 | two-runner test: copy refused on the second machine |
| M1.4 | reviewer | B6.4: issue the credential package for one machine from the vault, and load, verify and decrypt it at startup | M1.2, M1.3 | the preflight receives `IIS_IDENTITY.*` of every instance that shares an account (queue C11) |
| M1.5 | reviewer | Engine registry: build the host call from `ops_Action` and `ops_Engine` of the catalog; operation coordinator and lock (queue C5) | M1.2 | a preview of `DEPLOYMENT_PREFLIGHT` runs through the host from the registry |
| M1.6 | reviewer | Operator surface v0: `Start.cmd preflight [-Instance X] [-Json]`, exit codes, a readable table | M1.5 | output and exit codes documented and tested |
| M1.7 | reviewer | End-to-end CI: assemble, copy to a clean folder, run, assert the result rows | M1.1 to M1.6 | green on windows-2022 and windows-2025, evidence under `docs/phase3/evidence/` |
| M1.8 | GPT | Operator quick start, exit-code and troubleshooting table, M1 acceptance checklist (text only, from the code as merged) | M1.6 merged | every command in the text was run in M1.7 |
| M1.9 | owner | Run the M1 build on one Windows machine with a real catalog and send the output (queue O7, option a), or approve a CI read key (option b) | M1.7 | result recorded in `docs/` |

### M2 Fidelity and the rest of the preflight
| ID | Who | Task | Needs |
|---|---|---|---|
| M2.1 | reviewer | E0h: nine pull requests, one per review, in the order `REPAIR_MODEL`, `MANAGED_ASSETS`, `MANAGEMENT_MODEL`, `APPLICATION_CATALOG`, `WINDOWS_SERVICES`, `WEB_ACCESS`, `LINKS` (QR), `PULSE_MODEL`, `OPERATIONS_FRAMEWORK`. Source: the audits #91 to #99 (the column "Tipo": ARQUITECTURAL stays, DIVERGENCIA is fixed) | audits merged |
| M2.2 | owner | Decide the divergences that are not architectural (batch) | M2.1 started |
| M2.3 | reviewer | E0b to E0g: the 35 codes not ported (10 + 7 + 7 + 5 + 1, then 5), one review per pull request; coverage closes with E0g | M2.1; briefs #84 to #88 merged |
| M2.4 | reviewer | Run the preflight on the six real converted catalogs (queue C8) | M2.3 |

### M3 Engine waves
Per engine, in this order: **brief (GPT) then port (reviewer) then proof.** The brief follows the template of PR #78 (sources and evidence boundary; old behaviour step by step; tables and columns confirmed in `carried-schema.json`; credentials; network; original codes and severities; rules 6 and 7; owner decisions; ambiguities as questions; tests per code; entry gate). The reviewer extracts the original engine text as an evidence file when the owner allows it (D-E).
| ID | Engine | Wave | Needs |
|---|---|---|---|
| M3.1 | `PULSE_STATUS` (brief: PR #78) | 1 | M2.1 |
| M3.2 | `CONFIG_REPAIR` (14 legacy rules including `KEYCLOAK_DB_URL`) | 2 | M3.1 |
| M3.3 | `MANAGED_ASSETS` | 2 | M3.2 |
| M3.4 | `IIS_RECONCILE` on Microsoft.Web.Administration | 3 | M3.3, ADR-0006 conditions 2 to 4 [V] |
| M3.5 | `WINDOWS_SERVICES`, `V8_KEYCLOAK_PREREQUISITES`, `V8_KEYCLOAK_SERVICE`, `KEYCLOAK_CLIENT_SECRETS` (one pull request each) | 4 | M3.4, M1.4 |
| M3.6 | `WEB_ACCESS`, `LINKS_PAGES`, `DATABASE_CONTENT_SYNC` | 5 | M3.5 |
| M3.7 | `ENVIRONMENT_STATE_PROBE`, `STORAGE_SIZE_SCAN`, `MODEL_REVIEW` (free of credentials; may go earlier) | 7 | M3.1 |
| M3.8 | `LINKS_VISIBILITY` (read-only matrix first) | 8 | M3.6 |
| M3.9 | `DATABASE_COPY` (destructive: destination allowlist, safety backup never deleted) | 9 | M3.8, backup and restore proven |
| M3.10 | `FULL_DEPLOYMENT`: host orchestration of the validated engines (13 steps, 12 enabled); design by the reviewer, specification text by GPT | 6 | M3.1 to M3.9 |

### M4 Operator surface and skills
| ID | Who | Task | Needs |
|---|---|---|---|
| M4.1 | GPT | Operator interface specification: screens, flows, confirmations before apply, error messages (text only) | M1.6 |
| M4.2 | reviewer | Local web UI with the Phase 1C controls (session, CSRF, Host and Origin, CSP, idempotency, clean shutdown) | M4.1, M1.5 |
| M4.3 | GPT | Complete the skills in `docs/skills/` from the merged engines | M3.x |
| M4.4 | GPT then reviewer | New-server wizard: specification, then a generator of scripts and checklists that never writes a database | M4.1 |

### M5 Acceptance and handover [V]
| ID | Who | Task |
|---|---|---|
| M5.1 | GPT | Acceptance checklist and cutover runbook (first deployment on a server without the current system; existing servers later) |
| M5.2 | GPT | Backup and restore verification procedure; handover documents |
| M5.3 | reviewer | ADR-0006 conditions 2 to 4; signed package; reconvert and reseal every catalog with changes frozen (decision Q6) |
| M5.4 | owner | The [V] validations: the real collation of `_sisqualMANAGEMENT`, SQL connection encryption and certificates, the one-time import of the 191 credentials, engine behaviour on real topologies |
| M5.5 | reviewer | Threat-model review against the final code |
| M5.6 | owner | Revoke the old GitHub token and issue a narrow one (O6) |

## 4. Tasks GPT can do now (no code, no waiting on code)

Each is one pull request and one new file. Order of value: (1) answer the review threads of the open pull requests when a review arrives; (2) the briefs of M3.2 to M3.9 in wave order, `docs/engines/briefs/<ENGINE>.md`; (3) the specification of `FULL_DEPLOYMENT` (M3.10): its 13 steps, its gates, what each step needs from the engine result; (4) M4.1 and M4.4 specifications; (5) M5.1 and M5.2 documents. A brief or a specification is never merged on the word of its author: the reviewer re-checks the facts mechanically first.

## 5. Dependencies in one line
M0 and M1.1 to M1.2 start now. M1.2b waits for D-C. M1.4 waits for M1.2 and M1.3. M2 waits for the audits to be merged. M3.4 waits for the ADR-0006 conditions. M3.5 waits for M1.4. M5 waits for everything else.

## 6. Owner decisions
| ID | Decision | Recommended | Blocks |
|---|---|---|---|
| D-A | Add `OPENAI_API_KEY` for the second reviewer (PR #100) | yes, if the cost is acceptable; one run per push | M0.2 and every review while the Codex plan has no quota |
| D-B | Reorder: M1 before M2 | yes | the order of this file |
| D-C | Approve ADR-0010 (verified package state) after reading its plain summary | yes, with the equal-counter and lock semantics of the ADR | M1.2b |
| D-D | Review rounds: after three, only P1 blocks | yes | the pace of every code pull request |
| D-E | **Visibility of the repository.** It is public and now holds the verbatim text of original procedures from the private Management Console (PRs #83, #89, #90, and the audits #91 to #99 once merged). Keep it public, make it private, or move the evidence to a private repository | make it private or move the evidence; at least confirm | the extraction of original engine text (M3) |
| D-F | The queue decisions O4 (three stale adapter codes), O5 (three SQL actions), O7 (how the engine runs on real catalogs), O8 (weekly cleanup of `results/*`) | as recommended in the queue | M1.9, M3 |
