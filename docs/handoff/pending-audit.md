# Audit of `[PENDING]` markers in `docs/`

**Date:** 2026-10-09
**Repository state audited:** `main@57310b0996d8c6e8ea008af7f131bec4c65efccc`.
**Scope:** every literal `[PENDING]` marker under `docs/`, excluding `docs/handoff/work-queue.md`. This PR changes no source specification.

## Generation and verification

Canonical generation command from a repository checkout:

```text
grep -RIn --include='*.md' --fixed-strings '[PENDING]' docs --exclude='work-queue.md'
```

The inventory below was cross-checked at the exact `main` SHA with GitHub code search and direct line-window reads. The connector environment used for this audit could not materialize the private repository as a local checkout, so the command above is recorded for the reviewer to rerun verbatim. Line references below are against the audited SHA. When several adjacent markers have the same disposition, one row uses a line range and accounts for every marker in that range.

Decision-log references use the current line numbers of `docs/decisions-log.md`. In particular, the 2026-10-06 grouped decisions are lines 40-50, the Wave 1 decisions are lines 53-54, ADR-0008 acceptance is line 55, and the still-open verified-package-state item is line 57.

## Decision-bearing markers

| File:line | Short text | Already decided in `docs/decisions-log.md`? | Recommended action |
|---|---|---|---|
| `docs/decisions-log.md:57` | Verified package state owned by bootstrap instead of caller-supplied manifest/hash expectations | **No.** Line 57, 2026-10-08, is itself explicitly pending. | **Question owner / keep.** D4 proposes ADR-0010; do not promote it without owner approval. |
| `docs/roadmap.md:62` | Exact columns / catalogs for the Links instance directory | **Yes.** Line 49, 2026-10-06 (Q9), plus the implemented `docs/migration/instance-directory-design.md`. | **Remove marker.** The seven-column directory and empty-table rule are now documented and implemented. |
| `docs/architecture/ADR-0007-embedded-readonly-catalog.md:42` | Vault format/protection and per-table slicing rules | **Mixed.** The conversion plan was approved on 2026-10-05; Q6/Q7 on lines 46-47 (2026-10-06) settle package/vault custody constraints, but the exact vault/product contract remains its own contract. | **Split when edited:** remove the stale slicing marker; keep any still-contract-specific vault marker until the credential contract is the explicit source of truth. |
| `docs/architecture/ADR-0008-engine-host-contract.md:67` | Host/catalog trust caller-supplied package expectations | **No.** Line 57, 2026-10-08, keeps it pending. | **Question owner / keep.** D4/ADR-0010 is the proposed decision vehicle. |
| `docs/engines/WEB_ACCESS.md:72-74` | Password reset policy, root-pool restart policy, credential-file protection | **Yes.** Line 41, 2026-10-06, closes E1-E4/E8-E17 by reviewer delegation; the accepted register records E12. | **Remove markers** when the spec is refreshed. |
| `docs/engines/LINKS_PAGES.md:73-76` | Generation time, missing-policy pilot behaviour, assigned user, obsolete profile-instance rows | **Yes.** Line 41 closes delegated E13; line 49 (Q9, 2026-10-06) decides `LinksAssignedUserName`; the owner had already classified the five legacy rows as obsolete. | **Remove markers** when the spec is refreshed. |
| `docs/engines/MODEL_REVIEW.md:62-63` | Separate model-review surface; show catalog status | **Yes.** Line 41, 2026-10-06, closes delegated E17. | **Remove markers.** |
| `docs/engines/CONFIG_REPAIR.md:62` | Backup retention is pending | **Yes.** Line 41, 2026-10-06, closes delegated K11. | **Remove marker.** |
| `docs/engines/CONFIG_REPAIR.md:82-86` | Multi-match selector behaviour; restart scope; backup ACL/retention; secret cardinality; retry | **Mixed.** Line 41 closes delegated E3/K11/K12 and confirms restart is outside this engine; multi-match behaviour is intentionally to be derived by differential evidence rather than invented. | **Remove** restart/backup/secret/retry markers; **keep** the multi-match evidence marker until the differential test records the old behaviour. |
| `docs/engines/DATABASE_COPY.md:76-81` | Destination allowlist, archive restore, retention, settings sync, Keycloak DB handling, SQL permissions | **Mostly yes.** Line 45, 2026-10-06 (Q5), decides the first four. Keycloak/direct-admin behaviour was delegated as a real-system validation; SQL permission evidence remains `[V]`. | **Remove** the first four; **keep/question** Keycloak/permission validation until the port brief or real-server evidence settles them. |
| `docs/engines/IIS_RECONCILE.md:39` | PowerShell 7 mechanism for Windows features | **No final mechanism.** Line 48, 2026-10-06 (Q8), decides store/no-delete policy, not this compatibility choice. | **Keep** until T-01 evidence selects a mechanism. |
| `docs/engines/IIS_RECONCILE.md:58` | IIS backup mechanism | **No.** | **Keep** until the IIS port proves `appcmd` vs direct-copy restore. |
| `docs/engines/IIS_RECONCILE.md:75-79` | Certificate store, unmanaged deletion, IIS-29 scope, remaining matrix choices, pool identity order | **Mixed.** Line 48 (Q8) decides store name and never-delete; line 42 (Q2) fixes clean-server identity order. IIS-29 and unproven matrix mechanisms remain evidence/scope questions. | **Remove** store/no-delete/order markers; **keep/question** IIS-29 and unproven mechanism/backup items. |
| `docs/engines/PULSE_STATUS.md:34` | `ScheduledTasks` availability / fallback | **Yes.** Line 54, 2026-10-07: use COM if `ScheduledTasks` does not load. | **Remove marker.** The runner test remains evidence, not an owner decision. |
| `docs/engines/MANAGED_ASSETS.md:76-79` | Missing-logo severity, PNG validation, ACL inheritance, deletion policy | **Yes.** Line 41, 2026-10-06, closes delegated E4. | **Remove markers.** |
| `docs/engines/FULL_DEPLOYMENT.md:68` | Resume from last successful step | **Yes as optional/later behaviour.** Line 41 closes delegated E14. | **Remove marker** and state the accepted optional/later rule. |
| `docs/engines/FULL_DEPLOYMENT.md:72` | Continue other instances after one fails | **Yes.** Line 42, 2026-10-06 (Q2): stop only the failed instance; fail the run at the end with counts. | **Remove marker.** |
| `docs/engines/FULL_DEPLOYMENT.md:93-98` | Clean-server order, preflight/install order, Pulse not-applicable, per-instance failure, preview fingerprint, update phase | **Yes.** Lines 42 and 44 (Q2/Q4, 2026-10-06), plus Pulse lines 36-39. | **Remove markers.** |
| `docs/engines/LINKS_VISIBILITY.md:78-80` | Option A, first port read-only, second-reader requirement | **Yes.** Line 49, 2026-10-06 (Q9), selects option A; line 46 (Q6) requires a second reader for production catalog edits. | **Remove markers.** |
| `docs/engines/WINDOWS_SERVICES.md:38` | PowerShell 7 support for service/local-account operations | **Partly evidence, not a fresh owner decision.** Line 41 closes delegated E8 but real/runner evidence remains relevant. | **Keep only as evidence marker** if the required test is still missing; do not present it as an owner question. |
| `docs/engines/WINDOWS_SERVICES.md:74-77` | Clean-server identity order, shared account credential, restart-only-on-change, native helper | **Yes.** Lines 41-42, 2026-10-06. | **Remove markers.** |
| `docs/engines/STORAGE_SIZE_SCAN.md:78-80` | scan scope, reparse points, inaccessible paths | **Yes.** Line 41 closes delegated E16. | **Remove markers.** |
| `docs/engines/V8_KEYCLOAK_CONFIG.md:56-57` | Repoint after machine move; host/port authority | **Mixed.** Line 43, 2026-10-06 (Q3), retires this autonomous engine and absorbs behaviour into `CONFIG_REPAIR`. | **Remove the autonomous-engine questions** when this retired spec is refreshed; preserve any still-relevant CONFIG_REPAIR authority question there instead. |
| `docs/engines/V8_KEYCLOAK_SERVICE.md:72-75` | file delivery, clean-server order, certificate validation, log rotation | **Yes.** Lines 41-44 and delegated E10/K10, 2026-10-06. | **Remove markers.** |
| `docs/engines/V8_KEYCLOAK_PREREQUISITES.md:67-69` | installer source/version, JDK choice, alternate system-directory behaviour | **First two yes.** Line 50, 2026-10-06 (Q10), fixes operator folder, SHA-256 and exactly JDK 23. Alternate system-directory behaviour remains a technical test. | **Remove** first two; **keep** the system-directory evidence marker. |
| `docs/engines/DATABASE_CONTENT_SYNC.md:39` | SQL encryption / certificate trust | **Yes.** Line 41 closes delegated K9. | **Remove marker.** |
| `docs/engines/DATABASE_CONTENT_SYNC.md:74-76` | structured filters; direct Keycloak DB/admin path; missing target DB timing | **Mixed.** Line 41 closes C7/E11 by delegation; C7 is implemented. The Keycloak direct/admin-interface item is still a real-system validation choice. | **Remove** structured-filter and missing-DB policy markers; **keep** the Keycloak validation marker until evidence exists. |
| `docs/engines/ENVIRONMENT_STATE_PROBE.md:74-76` | output shape / probe policy questions | **Yes.** Line 41 closes delegated E15. | **Remove markers.** |
| `docs/engines/KEYCLOAK_CLIENT_SECRETS.md:35` | SQL encryption/certificate trust | **Yes.** Line 41 closes K9. | **Remove marker.** |
| `docs/engines/KEYCLOAK_CLIENT_SECRETS.md:71-74` | clean-server order, Keycloak caching, secret cardinality, SQL encryption | **Mixed.** Lines 41-42 decide order, K12 and K9. Caching remains real-Keycloak evidence. | **Remove** decided markers; **keep** caching evidence. |
| `docs/phase1/sqlclient-pin.md:67,73-75` | native SNI payload, package delivery, connection security, update policy | **Mixed.** The package carries pinned files and Q10 requires fixed versions/hash verification; connection security is delegated K9. Semantic packaging/version updates remain package integration work. | **Remove** stale connection-security decision marker; **keep** concrete packaging/update evidence items until manifest/package work records them. |
| `docs/phase1/phase1a-results.md:57-58,76-79` | IIS equivalence matrix and ADR-0006 conditions | **Partly.** ADR-0006 was accepted but conditions 2-4 remain validation gates; Q8 later amends certificate-store/no-delete policy. | **Keep** genuine `[V]`/equivalence evidence gaps; remove only markers superseded by completed matrix evidence. |
| `docs/phase1/phase1b-machine-identity-cng.md:26,139,141` | DPAPI fallback; later ADR/contract update; final product CNG choice | **No explicit final CNG product decision in the decision log.** | **Question owner / keep** the final adoption/ACL identity items; remove DPAPI fallback only if the accepted CNG path is formally selected. |
| `docs/phase1/phase1b-sqlite-provider.md:90-170` | provider adoption/packaging/open items from the spike | **Provider choice yes.** Line 52, 2026-10-07 formalization in ADR-0009; `docs/phase3/sqlite-runtime-adoption.md` records owner approval. | **Remove** stale adoption markers; **keep** only manifest/package integration evidence that ADR-0009 still calls remaining work. |
| `docs/phase1/phase1c-local-web-security.md:23,79,104,180-183` | operation coordinator, fragment/bootstrap flow, CSP, browser persistence/lifetime, idempotency/shutdown integration | **Mixed.** The technical spikes exist; the decision log does not turn every browser/product integration choice into an owner decision. | **Remove** markers that merely point to the now-existing coordinator/CSP spike evidence; **keep/question owner** for browser persistence/lifetime if still product-visible choices. |
| `docs/phase1/phase1c-operation-coordinator.md:75,160-163` | exact shared lock keys, REST surface, cancellation, per-engine locks, UI shutdown | **No final per-engine/product surface decision in the decision log.** | **Keep**; resolve in the product/engine integration that owns each key/surface. |
| `docs/phase3/runtime-catalog.md:20,111,113,115` | semantic dependency manifest member; bootstrap wiring; provider payload; semantic SQLite roles | **Role decision yes.** ADR-0009 / line 52 settles role-specific versions. The remaining wiring/manifest work is implementation, not a new owner decision. | **Remove** the role-decision marker when integrated; **keep** wiring/package markers until implemented and evidenced. |
| `docs/phase3/runtime-bootstrap.md:116` | guarded creation / retention deferral / final-file hardening awaiting clean Windows run | **No; this is evidence, not an owner decision.** | **Keep** until a clean Windows 2022/2025 execution is recorded, or replace with `[V]` if that better matches the status vocabulary. |
| `docs/phase3/runtime-logging.md:77,79,81` | adapter integration, UI exposure, final lifecycle wiring | **No direct owner decision.** | **Keep** until product integration lands; these are implementation gaps rather than architecture choices. |
| `docs/phase3/runtime-logging-hardening.md:4,84` | fresh final Codex review | **No decision needed.** This is review evidence/status. | **Remove** if a later clean final-head review is already recorded; otherwise keep as review evidence. |
| `docs/security/threat-model.md:63-175` | remaining package, browser, catalog, credential and runtime controls | **Mixed.** Q6/Q7/Q10 and delegated K-controls decide several rows; the verified-package-state trust bootstrap remains explicitly pending at decision-log line 57. | **Split on refresh:** remove markers whose controls are now decided/implemented; keep evidence gaps and the verified-package-state owner question. |
| `docs/phase0/risk-register.md:1-125` | historical risks containing `[PENDING]`, including the Pulse scheduled-task exception | **Mixed.** Pulse scope/task decisions are lines 36-39 and 54; many risk entries are historical snapshots rather than current decision records. | **Keep historical status where it describes the dated risk snapshot;** update only the current-status column in a dedicated risk-register refresh. |
| `docs/phase0/engine-porting-matrix.md:13,80-260` | status vocabulary and Phase-0 engine evidence gaps | **Mixed / historical.** Later engine specs and decisions supersede many. | **Keep the vocabulary marker;** for substantive Phase-0 pending rows, prefer marking them superseded/closed in a dedicated historical refresh rather than silently deleting evidence. |
| `docs/phase1/iis-reconcile-mwa-equivalence.md:101-260` | detailed IIS PowerShell 7 equivalence tests and open mechanism/scope questions | **Mixed.** Q8 (line 48) settles store/no-delete; delegated E6 closes some policy choices, but multiple T-xx and real-topology gates remain unexecuted. | **Keep evidence gaps; remove only decided policy markers.** Do not infer unexecuted compatibility tests as complete. |
| `docs/migration/analysis-pulse.md:6,50-110` | tag vocabulary, stale ScopePolicy wording, portable runtime/task question | **Yes for the substantive questions.** Lines 36-39 and 54 decide same-server/same-country, portable `pwsh`, identity, no-profile, parallelism/cert/COM/branding. | **Keep tag vocabulary; remove stale substantive pending markers** when this analysis is refreshed. |
| `docs/migration/analysis-cross-machine-operations.md:65-95` | plan persistence plus scope/update/archive decisions | **Mixed.** Lines 44-45 (Q4/Q5, 2026-10-06) decide phase scope, update path timing and archive/restore scope. Plan persistence is an operation-coordinator integration detail. | **Remove** scope/update/archive markers; **keep** plan-persistence integration item until its owning contract is final. |
| `docs/migration/obsolete-catalog-metadata-cleanup.md:90-105` | real-snapshot proof still pending at the dated PR #59 snapshot | **No owner decision substitutes for execution evidence.** | **Keep as historical evidence marker** in this dated implementation note. |

## Literal markers that are not open owner decisions

The grep also finds markers used as vocabulary, historical-state text, skill output placeholders, or handoff/evidence snapshots. They are still literal matches and are part of the audit, but removing them would change the meaning of those documents rather than close an open decision.

| File:line | Short text | Decision-log relation | Recommended action |
|---|---|---|---|
| `docs/handoff/pending-decisions-register.md:3` | States that the register lists every `[PENDING]` from its source PRs | Lines 40-50, 2026-10-06, later record the answers. | **Keep**; historical description of the register. |
| `docs/engines/DEPLOYMENT_PREFLIGHT.md:6` | Tag vocabulary: `[PENDING] needs a decision` | N/A | **Keep.** |
| `docs/engines/PULSE_STATUS.md:6` | Tag vocabulary | N/A | **Keep.** |
| `docs/migration/analysis-pulse.md:6` | Tag vocabulary | N/A | **Keep.** |
| `docs/migration/analysis-cross-machine-operations.md:6` | Tag vocabulary | N/A | **Keep.** |
| `docs/migration/instance-directory-design.md:6` | Tag vocabulary: `[PENDING] later work` | N/A | **Keep.** |
| `docs/phase1/evidence/README.md:45` | Defines `[PENDING]` as owner/reviewer decision or missing execution | N/A | **Keep.** |
| `docs/skills/rename-instance/SKILL.md:33,37` | Expected-output placeholder and dependency on future ports/contracts | No specific owner decision closes the skill workflow. | **Keep.** |
| `docs/skills/bootstrap-new-server/SKILL.md:32` | Final workflow depends on later components | No single decision closes implementation maturity. | **Keep.** |
| `docs/skills/credential-portability/SKILL.md:34` | Final workflow depends on machine-key/credential contract | Partly informed by credential decisions, but the skill is intentionally a skeleton. | **Keep.** |
| `docs/skills/config-repair-rule-authoring/SKILL.md:30,34` | Placeholder output plus dependency on ported engine/catalog contract | N/A | **Keep.** |
| `docs/skills/keycloak-client-provisioning/SKILL.md:33` | Dependency on credential package, Keycloak ports, coordinator | N/A | **Keep.** |
| `docs/phase3/sqlite-runtime-adoption.md:16` | Quotes the earlier `[PENDING formalisation]` state that ADR-0009 subsequently closed | Line 52 / ADR-0009, 2026-10-07. | **Keep** as historical explanation; it is not an active marker. |
| `docs/handoff/2026-10-05-phase1b-validation-handover.md:14,197-202` | Status vocabulary and dated remaining Phase-1B questions | Later evidence/ADR work supersedes some items, but this file is a dated handover snapshot. | **Keep historical text.** Use current design docs for active state. |
| `docs/handoff/2026-10-05-documentation-tasks-handover.md:1-40` | Tag vocabulary / dated pending-task handoff | Lines 40-50 later answer the grouped register. | **Keep historical text.** |
| `docs/handoff/2026-10-05-session-handoff.md:1-220` | Dated `[PENDING]` handoff statements | Later decisions exist for several. | **Keep historical text.** |
| `docs/handoff/2026-10-05-phase1c-local-web-security-handover.md:1-220` | Dated Phase-1C pending evidence/product integration notes | No reason to rewrite the snapshot. | **Keep historical text.** |
| `docs/handoff/2026-10-06-phase1b-sqlite-provider-handover.md:1-220` | Dated provider pending/formalisation notes | ADR-0009 later formalizes adoption. | **Keep historical text.** |
| `docs/handoff/2026-10-06-phase3-runtime-catalog-handover.md:1-220` | Dated runtime-catalog pending integration notes | Some later integrated; file is a snapshot. | **Keep historical text.** |
| `docs/handoff/2026-10-06-phase3-runtime-logging-handover.md:1-220` | Dated runtime-logging pending integration/review notes | Some later integrated; file is a snapshot. | **Keep historical text.** |
| `docs/phase1/evidence/phase1c-local-web-security/README.md:1-120` | Evidence-ledger pending statuses | Evidence snapshot, not a current decision record. | **Keep.** |
| `docs/phase1/evidence/phase1c-local-web-security-37382909046/README.md:1-160` | Run-specific pending/next-step text | Historical run evidence. | **Keep.** |
| `docs/phase1/evidence/phase1b-sqlite-provider-37392036026/README.md:1-180` | Run-specific pending adoption/integration wording | ADR-0009 later decides adoption, but the run record must stay immutable. | **Keep.** |
| `docs/phase1/evidence/phase1b-machine-identity/README.md:1-180` | Evidence-ledger pending product decisions | Historical/ledger state. | **Keep;** active unresolved CNG adoption remains separately visible above. |
| `docs/phase1/evidence/phase1b-machine-identity-37377769448/README.md:1-180` | Accepted-run pending product-decision wording | Run evidence. | **Keep.** |
| `docs/phase1/evidence/phase1c-operation-coordinator/README.md:1-180` | Evidence-ledger pending integration choices | Run/evidence record. | **Keep.** |

## Audit result

The dominant issue is stale status, not a shortage of decisions: many engine-spec `[PENDING]` markers were answered in the 2026-10-06 Q1-Q10 round or the 2026-10-07 Wave 1 round but were never rewritten to `[DECIDED]`/`[CLOSED]`. Those should be removed or replaced in their own specification PRs, not in this audit PR.

The material owner-level question that is still explicitly pending in the decision log is the verified package state / trust-bootstrap design (`docs/decisions-log.md:57`), for which D4/ADR-0010 is the proposed decision document. Several other remaining markers are execution evidence (`[V]`/CI/real topology) or per-engine implementation details; they should not be silently promoted to decisions.

This file is an audit only. It deliberately changes none of the source specifications listed above.
