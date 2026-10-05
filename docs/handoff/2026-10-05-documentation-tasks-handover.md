# Handover: documentation tasks of 2026-10-05

**Status:** [PROPOSED] for the reviewer, the owner and the next agent. Documentation only. It changes no other document.
**Date:** 2026-10-05
**Companion:** `docs/handoff/pending-decisions-register.md` (all open decisions, with recommendations and a column for the owner's answer).
**Earlier handoff:** `docs/handoff/2026-10-05-session-handoff.md` (the conversion tools, B1 to B6.1a, the owner decisions of the same day).
Tags: [CONFIRMED] checked; [PROPOSED] recommendation; [PENDING] needs a decision; [V] needs a real server.

## 1. Is everything executed?

[CONFIRMED] Yes. Four tasks were requested; all are done, each as pull requests from `main` (two are stacked, see 3). Nothing was merged; every PR waits for the reviewer.

| Task | Request | PR | Lines added | Result |
|---|---|---|---:|---|
| 1a | Analysis of Pulse | #27 | 128 | done; owner answers recorded in it |
| 1b | Cross-machine operations | #28 | 92 | done |
| 1c | Instance directory design | #29 | 114 | done |
| 2 | Risk register update | #30 | 99 (68 removed) | done |
| 3, wave 1 | `DEPLOYMENT_PREFLIGHT`, `PULSE_STATUS` | #31 | 162 | done, stacked on #27 |
| 3, wave 2 | `CONFIG_REPAIR`, `MANAGED_ASSETS` | #32 | 165 | done |
| 3, wave 3 | `IIS_RECONCILE` | #34 | 79 | done |
| 3, wave 4 | `WINDOWS_SERVICES`, `V8_KEYCLOAK_PREREQUISITES`, `V8_KEYCLOAK_SERVICE`, `KEYCLOAK_CLIENT_SECRETS` | #35 | 295 | done |
| 3, wave 5 | `WEB_ACCESS`, `LINKS_PAGES`, `DATABASE_CONTENT_SYNC` | #39 | 225 | done |
| 3, wave 6 | `FULL_DEPLOYMENT` | #41 | 98 | done |
| 3, wave 7 | `ENVIRONMENT_STATE_PROBE`, `STORAGE_SIZE_SCAN`, `MODEL_REVIEW` | #42 | 219 | done |
| 3, wave 8 | `LINKS_VISIBILITY`, `V8_KEYCLOAK_CONFIG` | #43 | 136 | done |
| 3, wave 9 | `DATABASE_COPY` | #44 | 81 | done |
| 4 | Threat model | #33 | 210 | done, stacked on #30 |

Checks made before this note: all 14 PRs are open, none merged; every PR is under 400 lines; the 19 engine specifications have 56 to 98 lines each (the limit is 150); the CI of the head commit of every PR is green (two runs, of #34 and #35, were cancelled by GitHub and were run again); only files under `docs/` changed, so `modules/`, `tools/`, `tests/`, the workflows, `contracts/credential-package.md`, `docs/decisions-log.md` and `docs/roadmap.md` are untouched; every file is ASCII with LF and was scanned for secret patterns.

## 2. Coverage of the 19 engines

[CONFIRMED] `ops.Engine` has 19 engines. 18 have a specification file. The 19th, the legacy `DATABASE_SETTINGS`, has none on purpose: all 14 of its rules are in the newer table, so `DATABASE_CONTENT_SYNC` (#39) replaces it and the specification proposes retiring it. `FULL_DEPLOYMENT` is not an engine (a composite action) and has its own specification (#41).

## 3. Review order and dependencies

- Stacked: **#27 before #31** (the Pulse specification uses the owner answers recorded in #27) and **#30 before #33** (the threat model cites the new risks R-044 to R-049). GitHub retargets a stacked PR to `main` when its base is merged.
- Everything else is independent and has `main` as base; a few specifications cite another by PR number (#28, #29, #31, #32, #39) but no file link breaks.
- Suggested reading order: the analyses (#27, #28, #29), the register of decisions (this PR), then the specifications by wave, then #30 and #33.
- Not mine: #36 to #38 (Phase 1B and 1C spikes) and #40; they do not interact with these.

## 4. Deviations from the instructions, and caveats

1. **The register had 43 risks, not 40.** All 43 were updated; six were added (R-044 to R-049).
2. Two PRs are stacked, although the instruction said "from `main`": allowed by the stacked-PR rule the owner accepted on 2026-10-05.
3. [CONFIRMED] A mistake of mine was found and corrected during the work: the first version of the Pulse analysis said other machines' links pages show the Pulse card. `cfg.GetLinksPageItemPlan` shows an application with a hub code only on that hub's page. Corrected in #27 (document, description and a comment).
4. All findings come from reading the reference snapshot (`database/sync/ManagementSync.sql`, blob `9401e2c3cb2517ca88848f902ff4d3786583e888`, head `9756ba956842884fabcf25b82c4fbf1d11cf56bd`) and the engine texts exported from it. **No real server was touched.** Behaviour under PowerShell 7 and on Windows is described, not tested; every such point is a [V] item or a test in the specification.
5. Counts quoted in the documents (76 instances, 61 content rules, 12 published applications and so on) are from that snapshot and must be rechecked on the live database [V].

## 4a. Open owner reminders

- The GitHub access token pasted earlier in the conversation must be revoked and replaced by one limited to this repository (it was still valid at the last check).
- Two readings to confirm: "A" to credential question Q2 as also approving the canonical form of the signed bytes, and "A" to Q10 as "yes".

## 5. Main findings by theme

**Execution order on a clean server (the pilot)** (#34, #35, #39, #41): the shared account is created at step 60 but IIS runs at step 50 and no IIS policy may create it; the Keycloak rules of `DATABASE_SETTINGS` run at step 30 before the Keycloak database is populated at step 65; client secrets run before the service first starts.

**Defects in the old engines that the ports must not copy** ([CONFIRMED] in the source):
- `V8_KEYCLOAK_PREREQUISITES` ignores its apply switch and installs software during a preview; `V8_KEYCLOAK_SERVICE` passes a password on a command line and disables TLS validation.
- `WINDOWS_SERVICES` resets a password and restarts every service on every apply; `WEB_ACCESS` restarts every root pool on every apply; `LINKS_PAGES` writes a generation time so it is never "matched".
- `DATABASE_CONTENT_SYNC` joins raw SQL filter text from the catalog (risk R-019) and 3 of its rules have no filter; `DEPLOYMENT_PREFLIGHT` and `MODEL_REVIEW` execute SQL text stored in the data; `ENVIRONMENT_STATE_PROBE` counts a 404 or 500 as online.
- `DATABASE_COPY` overwrites 7 databases per destination and has no restore function.

**History evidence** (#41, #28): 16 `FULL_DEPLOYMENT` jobs, all apply, none previewed, 14 failed; all database copy, clone and folder-copy plans ran on one machine.

**Architecture** (#28, #29, #43): no operation reads another machine; the only cross-machine data is the public instance directory (36 rows over six catalogs); `LinksHubInstanceCode` is not a cross-machine reference; `V8_KEYCLOAK_CONFIG` is covered by a `CONFIG_REPAIR` rule; `LINKS_VISIBILITY` writes configuration and conflicts with ADR-0007; six old-console features (clone, file copy, archive restore, housekeeping, power, version inventory) are not engines.

**Conflicts and gaps found** (#34, #33): the ADR-0006 certificate-store condition (`MY`) against the data (`WebHosting`); no protection against rollback to an older signed folder; the portable folder runs elevated with no stated install location or ACL.

## 6. What is not done

- **No product code** was written in these tasks. The specifications are the input for the engine ports (roadmap phase 6), which also need Phase 1B and 1C (spikes exist, PRs #36 to #38), the runtime (phase 3) and the rest of the credential tool (B6).
- Follow-up PRs identified, each small, none started: the catalog contract and the two conversion tools for the instance directory and for structured filters (#29, #39); the action-code cross-reference check (R-043); a catalog-change function (#43); the owner's manual catalog edit that renames the Pulse scope value.
- `docs/decisions-log.md` and `docs/roadmap.md` were updated by the reviewer after PR #23 (PRs #24 and #25). They do not yet reflect the findings and proposals of these documents (for example the engine specifications, the order problems, the retirement proposals); the reviewer adds them when the owner answers the register.
- The decisions in the register: **55 decisions and 10 validations**, grouped S (scope and architecture), K (security), C (catalog and contracts), E (engines), V (real servers).

## 7. How the evidence was produced (to repeat it)

1. Read the sync file by part with the raw contents API (`Accept: application/vnd.github.raw`), check its size (29,516,382 bytes) and hash, and parse the `INSERT` statements and the procedure definitions by statement. Treat it as sensitive and never copy it into the repository, CI or a log.
2. Export the engine texts with `tools/Export-ManagementEngines.ps1` (outside Git) and read them for structure; cite objects by name, never paste text.
3. The tables, columns, row counts and distributions quoted in the documents come from the carried tables of the conversion plan (global tables and per-machine cuts); any figure can be recomputed from them or, better, from the six catalogs produced by `Convert-ManagementDb`.
4. Job and history figures (#41, #28) come from the excluded history tables of the same file; they are evidence only and are not carried.

## 8. First actions for the next agent

1. Revoke the old token and get a restricted one (4a); list the open PRs; do not start from scratch after a timeout, resume the branch.
2. Read this note, the register, then the PRs in the order of section 3.
3. Ask the owner to answer the register (S and K first, they block the pilot and the credential tool); then record answers as decisions through the reviewer.
4. Start the follow-up PRs of section 6 that do not need a decision, then the first engine ports in wave order (`DEPLOYMENT_PREFLIGHT` and the shared review and template functions first, since several engines need them).
