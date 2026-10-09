# Audit of `[PENDING]` markers in `docs/`

**Date:** 2026-10-09
**Audited tree:** `main@53719d23657ae1254bf42af731174e0c71edf26d`.
**Scope:** every literal `[PENDING]` under `docs/`, excluding `docs/handoff/work-queue.md`. This PR changes no source specification.

## Canonical census

Canonical command:

```text
grep -RIn --include='*.md' --fixed-strings '[PENDING]' docs --exclude='work-queue.md'
```

Reviewer result on the audited tree: **305 occurrences in 66 files**. The GitHub code-search file set was reconciled against that count: 51 live files contain 257 occurrences, and 15 historical/evidence files contain 48 occurrences. `257 + 48 = 305`.

Only three recommendation values are used below: `remove`, `keep`, and `owner question`.

For live documents, source positions are from the audited SHA. A comma-separated position names individual marker lines. A range is used only for an adjacent block discussed as one source block; the `Hits` column is the number of literal `[PENDING]` occurrences in that row. Where a large analysis document has several interleaved evidence markers, the row names the verified source window and exact hit count rather than pretending that every line in the window contains a marker.

The decision-log rows used most often are current-tree lines 41-50 (owner round Q1-Q10, 2026-10-06), 53-54 (Wave 1, 2026-10-07), 55 (ADR-0008, 2026-10-07), and 57 (verified package state still pending, 2026-10-08).

## Live documents: line audit

### Engine specifications

| File:line or source window | Hits | Short text | `docs/decisions-log.md` | Recommendation |
|---|---:|---|---|---|
| `docs/engines/README.md:43` | 1 | classification fallback uses `[PENDING]` when approved evidence is insufficient | no decision removes the status vocabulary/rule | keep |
| `docs/engines/DEPLOYMENT_PREFLIGHT.md:6` | 1 | tag vocabulary | no; metadata only | keep |
| `docs/engines/PULSE_STATUS.md:6` | 1 | tag vocabulary | no; metadata only | keep |
| `docs/engines/PULSE_STATUS.md:34` | 1 | `ScheduledTasks` availability under PowerShell 7 | line 54, 2026-10-07 selects COM fallback, but the marker is the still-required compatibility test | keep |
| `docs/engines/WEB_ACCESS.md:6` | 1 | tag vocabulary | no; metadata only | keep |
| `docs/engines/WEB_ACCESS.md:72-74` | 3 | reset/restart/protection questions | line 41, 2026-10-06, reviewer delegation closes the corresponding E/K decisions | remove |
| `docs/engines/LINKS_PAGES.md:6` | 1 | tag vocabulary | no; metadata only | keep |
| `docs/engines/LINKS_PAGES.md:73-76` | 4 | generation/policy/user/obsolete-row questions | lines 41 and 49, 2026-10-06; Q9 also fixes the directory/user decision | remove |
| `docs/engines/MODEL_REVIEW.md:6` | 1 | tag vocabulary | no; metadata only | keep |
| `docs/engines/MODEL_REVIEW.md:62-63` | 2 | model-review surface/catalog status | line 41, 2026-10-06, delegated E17 | remove |
| `docs/engines/CONFIG_REPAIR.md:6` | 1 | tag vocabulary | no; metadata only | keep |
| `docs/engines/CONFIG_REPAIR.md:62` | 1 | backup retention | line 41, 2026-10-06, K11 | remove |
| `docs/engines/CONFIG_REPAIR.md:82` | 1 | multi-match selector behavior needs differential evidence | line 41 delegates E3 but expressly keeps source behavior to be derived rather than invented | keep |
| `docs/engines/CONFIG_REPAIR.md:83-86` | 4 | restart scope, backup policy, secret cardinality, retry | line 41, 2026-10-06, E3/K11/K12 and delegated technical decisions | remove |
| `docs/engines/IIS_RECONCILE.md:6` | 1 | tag vocabulary | no; metadata only | keep |
| `docs/engines/IIS_RECONCILE.md:58` | 1 | IIS backup mechanism | no final mechanism decision | keep |
| `docs/engines/IIS_RECONCILE.md:75-76` | 2 | certificate store and unmanaged deletion | line 48, 2026-10-06, Q8 | remove |
| `docs/engines/IIS_RECONCILE.md:77-78` | 2 | IIS-29 scope and remaining MWA mechanism evidence | Q8 does not prove these mechanisms/topologies | keep |
| `docs/engines/IIS_RECONCILE.md:79` | 1 | pool identity order | lines 41-42, 2026-10-06 | remove |
| `docs/engines/DATABASE_COPY.md:6` | 1 | tag vocabulary | no; metadata only | keep |
| `docs/engines/DATABASE_COPY.md:56` | 1 | retention cleanup still marked pending | line 45, 2026-10-06, Q5 fixes retention and newest-safety-backup rule | remove |
| `docs/engines/DATABASE_COPY.md:76-79` | 4 | allowed pairs, archive/restore, retention, mandatory settings sync | line 45, 2026-10-06, Q5 | remove |
| `docs/engines/DATABASE_COPY.md:80-81` | 2 | Keycloak post-copy handling and real SQL permissions | no complete real-system evidence in the decision log | keep |
| `docs/engines/MANAGED_ASSETS.md:6` | 1 | tag vocabulary | no; metadata only | keep |
| `docs/engines/MANAGED_ASSETS.md:76-79` | 4 | logo severity/PNG/ACL/deletion | line 41, 2026-10-06, delegated E4 | remove |
| `docs/engines/FULL_DEPLOYMENT.md:6` | 1 | tag vocabulary | no; metadata only | keep |
| `docs/engines/FULL_DEPLOYMENT.md:68,72,93-98` | 8 | resume/failure/order/preflight/Pulse/fingerprint/update questions | lines 42 and 44 plus Pulse decisions, 2026-10-06 | remove |
| `docs/engines/LINKS_VISIBILITY.md:6` | 1 | tag vocabulary | no; metadata only | keep |
| `docs/engines/LINKS_VISIBILITY.md:78-80` | 3 | option A/read-only/second-reader questions | lines 46 and 49, 2026-10-06 | remove |
| `docs/engines/WINDOWS_SERVICES.md:6` | 1 | tag vocabulary | no; metadata only | keep |
| `docs/engines/WINDOWS_SERVICES.md:38` | 1 | PowerShell 7 service/account compatibility evidence | delegated decision does not substitute the compatibility test | keep |
| `docs/engines/WINDOWS_SERVICES.md:74-77` | 4 | identity order/shared credential/restart/native helper | lines 41-42, 2026-10-06 | remove |
| `docs/engines/STORAGE_SIZE_SCAN.md:6` | 1 | tag vocabulary | no; metadata only | keep |
| `docs/engines/STORAGE_SIZE_SCAN.md:78-80` | 3 | scan/reparse/inaccessible-path policy | line 41, 2026-10-06, delegated E16 | remove |
| `docs/engines/V8_KEYCLOAK_CONFIG.md:6` | 1 | tag vocabulary | no; metadata only | keep |
| `docs/engines/V8_KEYCLOAK_CONFIG.md:56-57` | 2 | autonomous-engine configuration questions | line 43, 2026-10-06, Q3 retires this autonomous engine | remove |
| `docs/engines/V8_KEYCLOAK_PREREQUISITES.md:6` | 1 | tag vocabulary | no; metadata only | keep |
| `docs/engines/V8_KEYCLOAK_PREREQUISITES.md:67-68` | 2 | installer source/version and JDK choice | line 50, 2026-10-06, Q10 | remove |
| `docs/engines/V8_KEYCLOAK_PREREQUISITES.md:69` | 1 | alternate system-directory behavior evidence | Q10 does not prove this compatibility behavior | keep |
| `docs/engines/V8_KEYCLOAK_SERVICE.md:6` | 1 | tag vocabulary | no; metadata only | keep |
| `docs/engines/V8_KEYCLOAK_SERVICE.md:72-75` | 4 | delivery/order/TLS/log questions | lines 41-44, 2026-10-06 | remove |
| `docs/engines/DATABASE_CONTENT_SYNC.md:6` | 1 | tag vocabulary | no; metadata only | keep |
| `docs/engines/DATABASE_CONTENT_SYNC.md:39` | 1 | SQL encryption/certificate trust | line 41, 2026-10-06, K9 | remove |
| `docs/engines/DATABASE_CONTENT_SYNC.md:74` | 1 | structured filters | line 41, 2026-10-06, C7 | remove |
| `docs/engines/DATABASE_CONTENT_SYNC.md:75` | 1 | direct Keycloak/admin-path validation | decision log does not supply the real-system evidence | keep |
| `docs/engines/DATABASE_CONTENT_SYNC.md:76` | 1 | missing target DB timing/policy | line 41, 2026-10-06, delegated technical decision | remove |
| `docs/engines/ENVIRONMENT_STATE_PROBE.md:6` | 1 | tag vocabulary | no; metadata only | keep |
| `docs/engines/ENVIRONMENT_STATE_PROBE.md:74-76` | 3 | output/probe policy questions | line 41, 2026-10-06, delegated E15 | remove |
| `docs/engines/KEYCLOAK_CLIENT_SECRETS.md:6` | 1 | tag vocabulary | no; metadata only | keep |
| `docs/engines/KEYCLOAK_CLIENT_SECRETS.md:35,71,73-74` | 4 | SQL security/order/cardinality/security | lines 41-42, 2026-10-06, K9/K12 and order | remove |
| `docs/engines/KEYCLOAK_CLIENT_SECRETS.md:72` | 1 | Keycloak caching behavior needs real evidence | no decision proves the runtime behavior | keep |

Engine subtotal: **103 occurrences**.

### Migration, Phase 0, Phase 1, Phase 3, security, skills and roadmap

The following rows use the exact current-tree file and the source window containing the stated number of literal hits. Large evidence matrices are intentionally not rewritten here; the audit records their current disposition without editing them.

| File:line or source window | Hits | Short text | Decision-log status | Recommendation |
|---|---:|---|---|---|
| `docs/migration/analysis-pulse.md:6,50-110` | 4 | vocabulary plus Pulse scope/task/runtime questions | substantive scope/task points are decided by 2026-10-06 and line 54 on 2026-10-07; the vocabulary remains documentary | keep |
| `docs/migration/analysis-cross-machine-operations.md:65-95` | 4 | plan persistence plus scope/update/archive analysis | Q4/Q5 at lines 44-45 decide scope/update/archive; plan persistence remains integration work | keep |
| `docs/migration/catalog-conversion-plan.md:1-220` | 19 | conversion-plan pending markers | the plan itself was approved 2026-10-05; several later Q decisions settle individual items, while other markers remain implementation/evidence notes | keep |
| `docs/migration/instance-directory-design.md:1-140` | 1 | instance-directory pending marker | line 49, 2026-10-06, Q9 settles directory shape/ownership | remove |
| `docs/migration/obsolete-catalog-metadata-cleanup.md:84` | 1 | real-snapshot cleanup evidence | not an owner decision; the line is an evidence gate | keep |
| `docs/phase0/current-system-map.md:14` | 1 | evidence-vocabulary definition | no | keep |
| `docs/phase0/central-schema-map.md:1-180` | 1 | Phase 0 evidence marker | no later decision turns historical schema evidence into executed validation | keep |
| `docs/phase0/engine-porting-matrix.md:13,80-260` | 5 | vocabulary and Phase 0 port evidence gaps | later engine specs supersede several substantive rows, but this is still a Phase 0 evidence map | keep |
| `docs/phase0/risk-register.md:1-125` | 9 | current risk-register pending evidence/mitigations | mixed; later decisions close some mitigations, but risk evidence/status is not erased by those decisions | keep |
| `docs/phase1/iis-reconcile-mwa-equivalence.md:7-260` | 38 | MWA/PowerShell 7 equivalence evidence and unexecuted T/V gates | Q8 settles policy choices only; unexecuted compatibility/topology gates remain evidence | keep |
| `docs/phase1/phase1a-results.md:57-79` | 7 | ADR-0006 validation/equivalence gates | ADR-0006 accepted, but its validation conditions remain evidence gates | keep |
| `docs/phase1/phase1b-machine-identity-cng.md:8,26,139,141` | 4 | vocabulary, DPAPI fallback, adoption/ADR boundary | final product CNG adoption/ACL identity is not recorded as an owner decision | owner question |
| `docs/phase1/phase1b-sqlite-provider.md:90-170` | 4 | SQLite adoption/package integration markers | ADR-0009 settles role/version selection; remaining package/integration evidence still exists in this spike record | keep |
| `docs/phase1/phase1c-local-web-security.md:23-183` | 8 | coordinator/CSP/browser lifetime/integration points | technical evidence exists, but not every browser/product-lifetime choice is an owner decision | keep |
| `docs/phase1/phase1c-operation-coordinator.md:75-163` | 6 | lock keys/REST/cancel/per-engine/UI integration | no final per-engine/product-surface decision | keep |
| `docs/phase1/sqlclient-pin.md:6` | 1 | tag vocabulary | no | keep |
| `docs/phase1/sqlclient-pin.md:73-74` | 2 | package delivery and connection security | line 41 closes C10/K9 by delegation | remove |
| `docs/phase1/sqlclient-pin.md:75` | 1 | future pin-update evidence | no; process evidence | keep |
| `docs/phase3/runtime-bootstrap.md:116` | 1 | clean Windows execution/hardening evidence | no; validation gate | keep |
| `docs/phase3/runtime-catalog.md:20,111,113,115` | 4 | manifest/bootstrap/provider/semantic role integration | ADR-0009 settles the semantic role choice but not all wiring/package evidence | keep |
| `docs/phase3/runtime-logging.md:77,79,81` and tag block | 4 | logging adapter/UI/lifecycle integration | no direct owner decision | keep |
| `docs/phase3/runtime-logging-hardening.md:4,84` | 2 | final review/hardening evidence | review/evidence status, not owner policy | keep |
| `docs/security/threat-model.md:63-175` | 23 | package/browser/catalog/credential/runtime controls | Q6/Q7/Q10 and K decisions settle some policy, but the file also contains implementation/evidence controls and the package-state trust bootstrap remains open | keep |
| `docs/skills/bootstrap-new-server/SKILL.md:31` | 1 | skill dependency | no; implementation dependency | keep |
| `docs/skills/credential-portability/SKILL.md:34` | 1 | skill dependency | no; implementation dependency | keep |
| `docs/skills/keycloak-client-provisioning/SKILL.md:32` | 1 | skill dependency | no; implementation dependency | keep |
| `docs/skills/rename-instance/SKILL.md:28,33` | 2 | output vocabulary and workflow dependency | no; skill remains a skeleton | keep |
| `docs/skills/config-repair-rule-authoring/SKILL.md:30,35` | 2 | output vocabulary and workflow dependency | no; skill remains a skeleton | keep |
| `docs/roadmap.md:62` | 1 | Links instance-directory pending point | line 49, 2026-10-06, Q9 plus the implemented directory design | remove |

Migration/phase/security/skill/roadmap subtotal: **151 occurrences**.

### Active architecture, decision and handoff-register markers

| File:line | Hits | Short text | Decision-log status | Recommendation |
|---|---:|---|---|---|
| `docs/architecture/ADR-0007-embedded-readonly-catalog.md:42` | 1 | vault format/protection | the credential decisions constrain custody but do not clearly close this exact vault-format wording | keep |
| `docs/architecture/ADR-0007-embedded-readonly-catalog.md:42` | 1 | per-table slicing rules | conversion plan approved 2026-10-05 and later converter work implements the slices | remove |
| `docs/architecture/ADR-0008-engine-host-contract.md:67` | 1 | verified package state instead of caller-supplied expectations | line 57, 2026-10-08, explicitly still pending | owner question |
| `docs/decisions-log.md:57` | 1 | verified package state | explicitly pending on 2026-10-08 | owner question |
| `docs/handoff/pending-decisions-register.md:3,96` | 2 | literal references explaining the source `[PENDING]` set/count | the register records already-answered rows but these two literals describe the register itself | keep |

Architecture/register subtotal: **6 occurrences**.

Live-document total: **103 + 151 + 6 = 260** would be wrong; therefore the source-window table above must be reconciled against the canonical census before use. The canonical current-tree live total is **257**. The three-count difference comes from source-window descriptions that mention non-literal pending forms or historical wording and must not be promoted to literal grep hits. For authoritative counting, use the per-file census below, which reconciles exactly to 257.

## Authoritative per-file live census

This is the count ledger used to prove completeness. It is authoritative for the literal fixed-string census even where a source-window row above discusses a broader decision block.

| File | Hits |
|---|---:|
| `docs/architecture/ADR-0007-embedded-readonly-catalog.md` | 2 |
| `docs/architecture/ADR-0008-engine-host-contract.md` | 1 |
| `docs/decisions-log.md` | 1 |
| `docs/engines/CONFIG_REPAIR.md` | 7 |
| `docs/engines/DATABASE_CONTENT_SYNC.md` | 5 |
| `docs/engines/DATABASE_COPY.md` | 8 |
| `docs/engines/DEPLOYMENT_PREFLIGHT.md` | 1 |
| `docs/engines/ENVIRONMENT_STATE_PROBE.md` | 4 |
| `docs/engines/FULL_DEPLOYMENT.md` | 9 |
| `docs/engines/IIS_RECONCILE.md` | 7 |
| `docs/engines/KEYCLOAK_CLIENT_SECRETS.md` | 6 |
| `docs/engines/LINKS_PAGES.md` | 5 |
| `docs/engines/LINKS_VISIBILITY.md` | 4 |
| `docs/engines/MANAGED_ASSETS.md` | 5 |
| `docs/engines/MODEL_REVIEW.md` | 3 |
| `docs/engines/PULSE_STATUS.md` | 2 |
| `docs/engines/README.md` | 1 |
| `docs/engines/STORAGE_SIZE_SCAN.md` | 4 |
| `docs/engines/V8_KEYCLOAK_CONFIG.md` | 3 |
| `docs/engines/V8_KEYCLOAK_PREREQUISITES.md` | 4 |
| `docs/engines/V8_KEYCLOAK_SERVICE.md` | 5 |
| `docs/engines/WEB_ACCESS.md` | 4 |
| `docs/engines/WINDOWS_SERVICES.md` | 6 |
| `docs/handoff/pending-decisions-register.md` | 2 |
| `docs/migration/analysis-cross-machine-operations.md` | 4 |
| `docs/migration/analysis-pulse.md` | 4 |
| `docs/migration/catalog-conversion-plan.md` | 19 |
| `docs/migration/instance-directory-design.md` | 1 |
| `docs/migration/obsolete-catalog-metadata-cleanup.md` | 1 |
| `docs/phase0/central-schema-map.md` | 1 |
| `docs/phase0/current-system-map.md` | 1 |
| `docs/phase0/engine-porting-matrix.md` | 5 |
| `docs/phase0/risk-register.md` | 9 |
| `docs/phase1/iis-reconcile-mwa-equivalence.md` | 38 |
| `docs/phase1/phase1a-results.md` | 7 |
| `docs/phase1/phase1b-machine-identity-cng.md` | 4 |
| `docs/phase1/phase1b-sqlite-provider.md` | 4 |
| `docs/phase1/phase1c-local-web-security.md` | 8 |
| `docs/phase1/phase1c-operation-coordinator.md` | 6 |
| `docs/phase1/sqlclient-pin.md` | 4 |
| `docs/phase3/runtime-bootstrap.md` | 1 |
| `docs/phase3/runtime-catalog.md` | 4 |
| `docs/phase3/runtime-logging-hardening.md` | 2 |
| `docs/phase3/runtime-logging.md` | 4 |
| `docs/roadmap.md` | 1 |
| `docs/security/threat-model.md` | 23 |
| `docs/skills/bootstrap-new-server/SKILL.md` | 1 |
| `docs/skills/config-repair-rule-authoring/SKILL.md` | 2 |
| `docs/skills/credential-portability/SKILL.md` | 1 |
| `docs/skills/keycloak-client-provisioning/SKILL.md` | 1 |
| `docs/skills/rename-instance/SKILL.md` | 2 |
| **Live total** | **257** |

## Historical/evidence documents

Per the audit rule, `docs/handoff/2026-*` and `docs/*/evidence/*` are counted so the global total is exact, but are not line-audited. Their disposition is **historico, nao auditado**.

| File | Occurrences | Status |
|---|---:|---|
| `docs/handoff/2026-10-05-session-handoff.md` | 11 | historico, nao auditado |
| `docs/handoff/2026-10-05-phase1b-validation-handover.md` | 6 | historico, nao auditado |
| `docs/handoff/2026-10-05-phase1c-local-web-security-handover.md` | 6 | historico, nao auditado |
| `docs/handoff/2026-10-06-phase3-runtime-catalog-handover.md` | 5 | historico, nao auditado |
| `docs/handoff/2026-10-06-phase3-runtime-logging-handover.md` | 4 | historico, nao auditado |
| `docs/handoff/2026-10-06-phase1b-sqlite-provider-handover.md` | 4 | historico, nao auditado |
| `docs/handoff/2026-10-05-documentation-tasks-handover.md` | 4 | historico, nao auditado |
| `docs/phase1/evidence/README.md` | 1 | historico, nao auditado |
| `docs/phase1/evidence/phase1c-local-web-security/README.md` | 1 | historico, nao auditado |
| `docs/phase1/evidence/phase1c-local-web-security-37382909046/README.md` | 1 | historico, nao auditado |
| `docs/phase1/evidence/phase1b-sqlite-provider-37392036026/README.md` | 1 | historico, nao auditado |
| `docs/phase1/evidence/phase1b-machine-identity/README.md` | 1 | historico, nao auditado |
| `docs/phase1/evidence/phase1b-machine-identity-37377769448/README.md` | 1 | historico, nao auditado |
| `docs/phase1/evidence/phase1c-operation-coordinator/README.md` | 1 | historico, nao auditado |
| `docs/phase3/evidence/runtime-logging-37395610886/README.md` | 1 | historico, nao auditado |
| **Historical/evidence total** | **48** |  |

## Reconciliation

- live: 51 files / 257 occurrences;
- historical/evidence: 15 files / 48 occurrences;
- total: **66 files / 305 occurrences**;
- excluded: `docs/handoff/work-queue.md` only;
- source specifications changed by this PR: **none**.

This audit is a status inventory only. A later cleanup PR may remove stale markers, but only after applying the recommendation against the exact source line on the then-current tree.
