# Work queue

One writer: the reviewer updates the status column when a PR is merged, so nobody edits this file in a feature PR. Read `docs/engines/porting-guide.md` first. A task is only "done" when the PR is merged by the reviewer.

Who: **GPT** = the ChatGPT agent, **Claude** = the reviewer and integrator, **Owner** = decisions only the project owner can make.

## 1. Documentation tasks for GPT (small; independent unless the task names a dependency)

| ID | Task | Files allowed | Done when |
|---|---|---|---|
| D1 | **Needs E0 merged (PR #67).** Propose the shape of a `results` row and its status vocabulary, derived from what `engines/Invoke-DeploymentPreflight.ps1` emits, as `[PROPOSED]` text for the owner | `contracts/engine-result-rows.md` (new) | A table of fields, an allowed status list with one-line meanings, 3 examples taken from the preflight tests, and the questions the owner must answer. The schema file is not changed. |
| D2 | [CLOSED] merged in PR #70: facts checked by the reviewer against the six real converted catalogs on 2026-10-09 (the three stale adapter rows, the existing actions, 17 engines) Decision brief on the six `action-xref` failures (adapter action codes `DATABASE_SETTING`, `HOUSEKEEPING`, `WINDOWS_SERVICE` that no `ops_Action` row resolves) | `docs/handoff/decision-brief-action-xref.md` (new) | Facts from the converted real catalog (which adapter rows, which action codes exist), 2 or 3 options with the effect of each on the verifier and the engines, one recommendation. |
| D3 | [CLOSED] merged in PR #71: facts checked by the reviewer on 2026-10-09 (exactly three SQL actions in the six catalogs, their mode policy, flags and SQL text; the audit procedure is read-only) Decision brief on the three `SQL`-type actions the host refuses (`EXECUTION_HISTORY`, `LINKS_VISIBILITY_MATRIX`, `OBJECT_AUDIT`) | `docs/handoff/decision-brief-sql-actions.md` (new) | For each: what it does today, what replaces it, the wave that would own it, and a recommendation (engine, read-only report, or retire). |
| D4 | [CLOSED] merged in PR #75 as `[PROPOSED]` (the owner's approval of the design is O3): the Codex review found three design gaps to fix before the owner is asked (what happens when the counter is equal on a restart, how the catalog's expected values reach the engine child process, and the optional catalog origin reference). Design proposal for a verified package state held by the bootstrap and read by the host and the runtime catalog (ADR-0008 "Trust boundary of the host") | `docs/architecture/ADR-0010-verified-package-state.md` (new, status Proposed) | Problem, the data held, how it is set once and read, how the manifest counter fits, effect on the catalog opener and the host, alternatives, and the approvals needed (`AGENTS.md`: trust bootstrap, package integrity). No code. |
| D5 | [CLOSED] merged in PR #76. Refresh `docs/roadmap.md` after each merge of this queue | `docs/roadmap.md` | Statuses match `main`; only verifiable statements. |
| D6 | [CLOSED] merged in PR #79. Fix the credential table of `docs/engines/DEPLOYMENT_PREFLIGHT.md`: it lists only `IIS_IDENTITY`, but the original Web Access review has `WEB_ACCESS_PASSWORD_MISSING` (ERROR: the per-instance password is empty) and the owner decided on 2026-10-07 to port all twelve reviews with all codes, so the engine also reads `WEB_ACCESS.<instance>` | `docs/engines/DEPLOYMENT_PREFLIGHT.md` | The table and the secrets paragraph name both references, cite the original code and the owner decision, and nothing else in the specification changes. |
| D7 | [CLOSED] merged in PR #80. Remove two stale statements from specifications: `LINKS_VISIBILITY.md` still lists option A as `[PENDING]` although the owner chose it on 2026-10-06 (Q9, decisions log); `STORAGE_SIZE_SCAN.md` says `outside the 19 engines` while the portable catalog has 17 engines (state the count with its source) | `docs/engines/LINKS_VISIBILITY.md`, `docs/engines/STORAGE_SIZE_SCAN.md` | Each statement matches the decisions log or a query on the converted catalog that you quote; nothing else changes. |
| D8 | [CLOSED] merged in PR #81. Add the retired `DATABASE_SETTINGS` engine as a `RETIRED` row of `docs/engines/README.md`, as `V8_KEYCLOAK_CONFIG` already is (owner decision Q3, 2026-10-06) | `docs/engines/README.md`, `docs/engines/DATABASE_SETTINGS.md` | The matrix lists the 17 engines of the catalog, the composite action and both retired engines, and says which is which. |
| D9 | [CLOSED] merged in PR #77 (the counts and the 80 citations were recomputed from the raw grep by the reviewer; the recommendations are advice, not edits): audit of every `[PENDING]` marker in `docs/` against the decisions log. The Codex review found the inventory incomplete (several documents missing), some line references wrong, one recommendation that should be `keep`, and recommendations outside the three allowed | `docs/handoff/pending-audit.md` | Complete against the exact grep of the audited tree, every line reference true at that tree, only `remove`, `keep` or `owner question`. |
| D11 | [CLOSED] merged in PR #82. `docs/engines/DEPLOYMENT_PREFLIGHT.md` line 59 says that a missing server policy, Pulse among them, is an `ERROR`; the owner decided on 2026-10-06 that a machine without a Pulse profile reports `not applicable` and does not fail (PULSE_STATUS.md, decisions log). Exempt Pulse in that sentence and cite the decision | `docs/engines/DEPLOYMENT_PREFLIGHT.md` | After #79 is merged (same file). The sentence names the exemption and the decision; the other policies stay an `ERROR`. |
| D12 | After PR #67 is merged: correct `docs/engines/README.md` and the `Host contract` of `docs/engines/DEPLOYMENT_PREFLIGHT.md`, which (merged in #68) say the per-kind form exists for four kinds including `RULE_SECRET`. The decision of 2026-10-09 (O9) is three instance-scoped kinds and rule secrets exact | `docs/engines/README.md`, `docs/engines/DEPLOYMENT_PREFLIGHT.md` | Both texts name the three kinds and say rule secrets are exact references; nothing else changes. |
| D14 | Audit of the engine against the original for the nine reviews it already implements (`MANAGEMENT_MODEL`, `APPLICATION_CATALOG`, `MANAGED_ASSETS`, `REPAIR_MODEL`, `WINDOWS_SERVICES`, `WEB_ACCESS`, `LINKS_PRESENTATION` (QR part), `PULSE_MODEL`, `OPERATIONS_FRAMEWORK`). The first comparison only looked at code names and severities; the QR and Pulse checks were found to differ in predicate | `docs/handoff/preflight-audit-<review>.md` (new, one pull request per review) | For each check of the engine: the original predicate (verbatim from `docs/handoff/preflight-legacy-procedures-implemented.sql.txt`), what the engine does, whether they agree, and the T-SQL semantics that decide it (collation, space padding, LEN, trim). Text only; the engine is not changed. |
| D10 | [PENDING] PR #78: brief for the port of `PULSE_STATUS` (E1). The Codex review found catalog column names that do not match the carried schema, a check plan described as a full cross product, and a state-file design called approved that the owner has not approved | `docs/handoff/pulse-status-port-brief.md` | Every table and column is in `tests/Fixtures/carried-schema.json`; ambiguities are listed as questions, not resolved; the persistence design stays `[PROPOSED]`. |

## 2. Engine ports for GPT (sequential: start the next only when the previous is merged)

Each port is one PR: the engine, its tests (conformance, mutation, one per issue code), its entry in `contracts/engine-secret-references.json`, and the test steps in `.github/workflows/engine-host.yml`. Specification: `docs/engines/<ENGINE>.md`. Follow the porting guide. The reviewer runs the engine on the real converted catalogs before merging.

| ID | Engine | Wave | Needs | Notes |
|---|---|---|---|---|
| E0 | `DEPLOYMENT_PREFLIGHT` | 1 | PR #67 | [PENDING] Integrated as an explicitly incomplete first slice (owner decision A, 2026-10-09): 31 of the 66 issue codes of the original reviews, every result carries `PREFLIGHT_COVERAGE_INCOMPLETE`. The reviewer is finishing it. |
| E0b | `DEPLOYMENT_PREFLIGHT`: port `cfg.ReviewExtendedApplicationModel` (10 codes) | 1 | E0 merged | Codes and severities: `docs/handoff/preflight-port-gap.md`. Same engine file, so one at a time. |
| E0c | `DEPLOYMENT_PREFLIGHT`: port `cfg.ReviewIisDeploymentModel` (7 codes) | 1 | E0b merged | As E0b. |
| E0d | `DEPLOYMENT_PREFLIGHT`: port `cfg.ReviewLinksPageModel` (7 codes) | 1 | E0c merged | As E0b. |
| E0e | `DEPLOYMENT_PREFLIGHT`: port `cfg.ReviewWebsiteBrandingModel` (5 codes) | 1 | E0d merged | As E0b. |
| E0f | `DEPLOYMENT_PREFLIGHT`: port `cfg.ReviewLinksPagePresentationResources` (1 code) and close the coverage | 1 | E0e merged | With 66 of 66 the engine no longer emits `PREFLIGHT_COVERAGE_INCOMPLETE`, and the test requires that it does not. |
| E0g | `DEPLOYMENT_PREFLIGHT`: port the 5 codes of the original that the first inventory missed: `IIS_APPLICATION_NOT_IN_CATALOG`, `CONFIG_FILE_WITHOUT_APPLICATION`, `DUPLICATE_IIS_PATH`, `NON_IIS_COMPONENT_HAS_IIS_PATH` (`cfg.ReviewApplicationCatalog`) and `OPS_PROFILE_MISSING` (`ops.ReviewOperationsFramework`), using the original names | 1 | D14 merged | The engine has its own names for some of them: rename, do not add a second code. |
| E1 | `PULSE_STATUS` | 1 | E0 merged (it does not wait for E0b to E0f: a different engine file) | Decisions of 2026-10-07 apply (bounded parallelism, certificate validation on by default). |
| E2 | `CONFIG_REPAIR` | 2 | E1 | The 14 legacy rules including `KEYCLOAK_DB_URL` must stay present. |
| E3 | `MANAGED_ASSETS` | 2 | E2 | |
| E4 | `IIS_RECONCILE` | 3 | E3, ADR-0006 conditions 2 to 4 | Needs a real server to prove; GPT writes it, the owner validates. |
| E5 | `WINDOWS_SERVICES`, `V8_KEYCLOAK_PREREQUISITES`, `V8_KEYCLOAK_SERVICE`, `KEYCLOAK_CLIENT_SECRETS` | 4 | E4, B6.4 | One PR per engine. Credentials and installers: exact versions, SHA-256 verified, JDK 23 only. |
| E6 | `WEB_ACCESS`, `LINKS_PAGES`, `DATABASE_CONTENT_SYNC` | 5 | E5 | One PR per engine. |
| E7 | `ENVIRONMENT_STATE_PROBE`, `STORAGE_SIZE_SCAN`, `MODEL_REVIEW` | 7 | E1 | Can go before waves 3 to 5 if they are free of credentials. |
| E8 | `LINKS_VISIBILITY` | 8 | E6 | |
| E9 | `DATABASE_COPY` | 9 | E8 | Destination allowlist, safety backup never deleted. |
| E10 | `FULL_DEPLOYMENT` | 6 | Host composite support | Composite action: it is host orchestration, not an engine. The reviewer designs it. |

## 3. Reviewer tasks (Claude)

| ID | Task | Status |
|---|---|---|
| C1 | Finish `DEPLOYMENT_PREFLIGHT` (#67). Done and tested on Windows: real schema, restored Web Access check, declared coverage (31 of 66), root confinement (lexical and resolved), executables, accounts, names and users compared against every enabled instance, links resolved, wildcard limited to catalog instances, every selected holder of a duplicate named, a machine without a Pulse profile `not applicable` (owner decision of 2026-10-06). Open on purpose: only the manifest authenticity thread (Owner O3, pending). The wildcard scope (O9) and the instance count (O10) are decided. Then Codex review and merge | [PENDING] in progress; Codex review requested at 05d38f8 |
| C2 | Merge #68 (engine host contract per specification): the classes and references were checked against the data and the host of #67 on 2026-10-09 | [CLOSED] merged 2026-10-09 (PR #68) |
| C3 | Host: verified package state (D4) after the owner approves the design | [PENDING] blocked on Owner O3 |
| C4 | B6.4: issue the credential package per machine | [PENDING] not started |
| C5 | Runtime wiring: manifest verification with the counter (K3), operation coordinator, the engine registry that builds the host call | [PENDING] not started |
| C6 | Real-snapshot proof (conversion, verifier, engines) for every PR that touches them | [PROPOSED] every PR that touches them |
| C7 | Clean the branches that nobody needs (`proof/*`, `results/*`) | [CLOSED] done 2026-10-09: 144 branches deleted (issue #74); a few `results/*` of the current runs are kept |
| C8 | Run `DEPLOYMENT_PREFLIGHT` on the real converted catalogs (the engine has only been compared with them, never run on them) | [PENDING] needs Owner O7 |
| C9 | Automatic weekly removal of `results/*` log branches older than three days (153 branches had accumulated; 144 were deleted on 2026-10-09, tips recorded in issue #74) | [PENDING] needs Owner O8 |
| C10 | Review the work of GPT before each merge: facts against the converted catalogs, classes against the fixed rule, no claim without a query | [PROPOSED] every PR |
| C12 | After PR #67 is merged: update section 4 of `docs/engines/porting-guide.md` so a port may declare the per-kind form for `IIS_IDENTITY`, `WEB_ACCESS` and `MOBILE_APP_TOKEN` (never `RULE_SECRET`) | [PENDING] after C1 |
| C11 | The orchestrator (`FULL_DEPLOYMENT`, the engine registry) passes to the preflight the credentials of EVERY enabled instance that shares an IIS account (6 to 21 instances in each real catalog), not only the selected one; otherwise the preflight reports `SERVICE_IDENTITY_PASSWORD_UNVERIFIED` as an ERROR | [PENDING] part of C5 |

## 4. Owner decisions

These are proposals. None is approved until the owner answers and `docs/decisions-log.md` records it.

| ID | Decision | Recommendation |
|---|---|---|
| O1 | Stop ignoring `runtime/` in `.gitignore` (it is production code now) | [DECIDED 2026-10-09] Yes ("1. Sim"); only `runtime/sqlite-provider/` stays ignored. PR #73 |
| O2 | Add `[DECIDED]` and `[CLOSED]` to the status tokens of `AGENTS.md` (`[DECIDED]` is used 51 times in 11 files, `[CLOSED]` twice in one) | [DECIDED 2026-10-09] Yes ("2. Sim"). PR #73 |
| O3 | Approve the verified package state design once D4 exists | [PENDING] Decide after reading D4 The owner delegated the choice to the reviewer on 2026-10-09, but the design changes the trust bootstrap, which `AGENTS.md` reserves to the owner: it stays `[PENDING]` until the owner reads a plain summary and says yes. |
| O4 | Mapping of the three stale adapter codes, once D2 exists | [PENDING] Decide after reading D2 |
| O5 | Fate of `OBJECT_AUDIT`, `EXECUTION_HISTORY`, `LINKS_VISIBILITY_MATRIX`, once D3 exists | [PENDING] Decide after reading D3 |
| O6 | Revoke the old GitHub token (full access to four repositories) and issue a narrow one | [DECIDED 2026-10-09] The owner revokes it at the end of the project; until then it stays in use |
| O7 | How the engine is run on real catalogs: (a) the owner runs it on a Windows machine and sends the result, (b) a CI read key for the private snapshot repository, (c) a copy of the converted catalogs without customer data in this repository | [PENDING] The owner said "depois" (2026-10-09); recommendation (a) now, (c) later |
| O8 | A weekly workflow that deletes `results/*` log branches older than three days and touches nothing else | [PENDING] Recommended |
| O9 | Does the secret contract keep the per-kind form or must the orchestrator list every exact reference? | [DECIDED 2026-10-09] Keep it, for the instance-scoped kinds only (`IIS_IDENTITY`, `WEB_ACCESS`, `MOBILE_APP_TOKEN`) and only for enabled instances of the verified catalog; `RULE_SECRET` is always exact. Owner: "Faz o que achares melhor" (delegated to the reviewer's recommendation). In PR #67 |
| O10 | Does the engine input contract carry the number of selected instances? | [DECIDED 2026-10-09] No: a run that never opened the catalog reports `PREFLIGHT_TARGETS_UNKNOWN` (INFO) and fails as a whole. Owner: "Faz o que achares melhor" (delegated to the reviewer's recommendation). In PR #67 |
