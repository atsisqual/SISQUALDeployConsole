# Work queue

One writer: the reviewer updates the status column when a PR is merged, so nobody edits this file in a feature PR. Read `docs/engines/porting-guide.md` first. A task is only "done" when the PR is merged by the reviewer.

Who: **GPT** = the ChatGPT agent, **Claude** = the reviewer and integrator, **Owner** = decisions only the project owner can make.

## 1. Documentation tasks for GPT (small; independent unless the task names a dependency)

| ID | Task | Files allowed | Done when |
|---|---|---|---|
| D1 | **Needs E0 merged (PR #67).** Propose the shape of a `results` row and its status vocabulary, derived from what `engines/Invoke-DeploymentPreflight.ps1` emits, as `[PROPOSED]` text for the owner | `contracts/engine-result-rows.md` (new) | A table of fields, an allowed status list with one-line meanings, 3 examples taken from the preflight tests, and the questions the owner must answer. The schema file is not changed. |
| D2 | Decision brief on the six `action-xref` failures (adapter action codes `DATABASE_SETTING`, `HOUSEKEEPING`, `WINDOWS_SERVICE` that no `ops_Action` row resolves) | `docs/handoff/decision-brief-action-xref.md` (new) | Facts from the converted real catalog (which adapter rows, which action codes exist), 2 or 3 options with the effect of each on the verifier and the engines, one recommendation. |
| D3 | Decision brief on the three `SQL`-type actions the host refuses (`EXECUTION_HISTORY`, `LINKS_VISIBILITY_MATRIX`, `OBJECT_AUDIT`) | `docs/handoff/decision-brief-sql-actions.md` (new) | For each: what it does today, what replaces it, the wave that would own it, and a recommendation (engine, read-only report, or retire). |
| D4 | Design proposal for a verified package state held by the bootstrap and read by the host and the runtime catalog (ADR-0008 "Trust boundary of the host") | `docs/architecture/ADR-0010-verified-package-state.md` (new, status Proposed) | Problem, the data held, how it is set once and read, how the manifest counter fits, effect on the catalog opener and the host, alternatives, and the approvals needed (`AGENTS.md`: trust bootstrap, package integrity). No code. |
| D5 | Refresh `docs/roadmap.md` after each merge of this queue | `docs/roadmap.md` | Statuses match `main`; only verifiable statements. |

## 2. Engine ports for GPT (sequential: start the next only when the previous is merged)

Each port is one PR: the engine, its tests (conformance, mutation, one per issue code), its entry in `contracts/engine-secret-references.json`, and the test steps in `.github/workflows/engine-host.yml`. Specification: `docs/engines/<ENGINE>.md`. Follow the porting guide. The reviewer runs the engine on the real converted catalogs before merging.

| ID | Engine | Wave | Needs | Notes |
|---|---|---|---|---|
| E0 | `DEPLOYMENT_PREFLIGHT` | 1 | PR #67 | Reviewer is finishing it. |
| E1 | `PULSE_STATUS` | 1 | E0 merged | Decisions of 2026-10-07 apply (bounded parallelism, certificate validation on by default). |
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
| C1 | Finish `DEPLOYMENT_PREFLIGHT` (#67): the unspecified `WEB_ACCESS` credential check is removed and the engine reads the real catalog schema; behavioural tests for four review fixes, Codex review, run on the real converted catalogs, merge | [PENDING] in progress |
| C2 | Merge #68 (engine host contract per specification) after CI and review | [PENDING] waiting for CI and review |
| C3 | Host: verified package state (D4) after the owner approves the design | [PENDING] blocked on Owner O3 |
| C4 | B6.4: issue the credential package per machine | [PENDING] not started |
| C5 | Runtime wiring: manifest verification with the counter (K3), operation coordinator, the engine registry that builds the host call | [PENDING] not started |
| C6 | Real-snapshot proof (conversion, verifier, engines) for every PR that touches them | [PROPOSED] every PR that touches them |
| C7 | Clean the branches that nobody needs (`proof/*`, `results/*`) | [PENDING] after C1 |

## 4. Owner decisions

| ID | Decision | Recommendation |
|---|---|---|
| O1 | Stop ignoring `runtime/` in `.gitignore` (it is production code now) | Yes: ignore only the local state folders |
| O2 | Add `[DECIDED]` and `[CLOSED]` to the status tokens of `AGENTS.md` (the repository already uses them 65 times) | Yes |
| O3 | Approve the verified package state design once D4 exists | Decide after reading D4 |
| O4 | Mapping of the three stale adapter codes, once D2 exists | Decide after reading D2 |
| O5 | Fate of `OBJECT_AUDIT`, `EXECUTION_HISTORY`, `LINKS_VISIBILITY_MATRIX`, once D3 exists | Decide after reading D3 |
| O6 | Revoke the old GitHub token (full access to four repositories) and issue a narrow one | Now |
