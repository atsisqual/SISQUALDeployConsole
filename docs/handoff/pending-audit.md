# Audit of `[PENDING]` markers in `docs/`

**Date:** 2026-10-09
**Audited tree:** `main@68713f6a2df9c2df2c83066cfb77bd8fae060683`.
**Scope:** every grep hit containing literal `[PENDING]` under `docs/`, excluding `docs/handoff/work-queue.md`. This PR changes no source specification.

## Canonical census

Canonical command recorded by the reviewer:

```text
grep -RIn --include='*.md' --fixed-strings '[PENDING]' docs --exclude='work-queue.md'
```

The reviewer ran that command over `main@68713f6a2df9c2df2c83066cfb77bd8fae060683` and stored the raw `file:line:text` output in `docs/handoff/pending-grep-68713f6.txt` on branch `docs/work-queue`. The raw file records **305 grep hits in 66 files**. I did not rerun the grep; every source line cited below is transcribed from that reviewer artifact.

A grep hit is counted once per output line. A source line that discusses more than one pending concept is still one raw grep hit. Only three recommendation values are used: `remove`, `keep`, and `owner question`.

Live documents are line-audited below. Historical handoffs (`docs/handoff/2026-*`) and evidence (`docs/*/evidence/*`) are grouped by file and hit count as `historico, nao auditado`.

## Live documents: line audit

### Engine specifications

| File:line | Hits | Short text | Decision evidence | Recommendation |
|---|---:|---|---|---|
| `docs/engines/CONFIG_REPAIR.md:6,62,82-86` | 7 | vocabulary, retention and open repair behaviors | Q1 delegated E3/K11/K12; multi-match still needs source evidence | keep |
| `docs/engines/DATABASE_CONTENT_SYNC.md:7,39,74-76` | 5 | vocabulary, SQL trust, filters, Keycloak path and timing | Q1 delegated K9/C7; real Keycloak path remains evidence | keep |
| `docs/engines/DATABASE_COPY.md:6,56,76-81` | 8 | vocabulary plus copy safety/open questions | Q5 closes allowlist/archive/retention/settings-sync; Keycloak/permissions still need evidence | keep |
| `docs/engines/DEPLOYMENT_PREFLIGHT.md:6` | 1 | tag vocabulary | metadata only | keep |
| `docs/engines/ENVIRONMENT_STATE_PROBE.md:6,74-76` | 4 | vocabulary and probe policy questions | Q1 delegated E15 | remove |
| `docs/engines/FULL_DEPLOYMENT.md:6,68,72,93-98` | 9 | vocabulary plus resume/failure/order/preflight/Pulse/fingerprint/update questions | Q2/Q4 and Pulse owner decisions close substantive questions | remove |
| `docs/engines/IIS_RECONCILE.md:6,58,75-79` | 7 | vocabulary, backup, certificate/unmanaged/IIS mechanism/account questions | Q8 closes store/no-delete; several mechanisms remain evidence | keep |
| `docs/engines/KEYCLOAK_CLIENT_SECRETS.md:6,35,71-74` | 6 | vocabulary, SQL security/order/cache/cardinality | Q1/Q2 close several; Keycloak caching remains real-system evidence | keep |
| `docs/engines/LINKS_PAGES.md:6,73-76` | 5 | vocabulary and page-generation questions | Q1/Q9 close the substantive choices | remove |
| `docs/engines/LINKS_VISIBILITY.md:6,78-80` | 4 | vocabulary plus option/V1/second-reader questions | Q9 and Q6 close the substantive choices | remove |
| `docs/engines/MANAGED_ASSETS.md:6,76-79` | 5 | vocabulary and asset policy questions | Q1 delegated E4 | remove |
| `docs/engines/MODEL_REVIEW.md:6,62-63` | 3 | vocabulary and report-surface questions | Q1 delegated E17 | remove |
| `docs/engines/PULSE_STATUS.md:6` | 1 | tag vocabulary | metadata only | keep |
| `docs/engines/PULSE_STATUS.md:34` | 1 | `ScheduledTasks` compatibility test | owner chose COM fallback if module is unavailable, but this marker is the still-required compatibility test | keep |
| `docs/engines/README.md:44` | 1 | classification fallback uses `[PENDING]` | status vocabulary/rule | keep |
| `docs/engines/STORAGE_SIZE_SCAN.md:6,78-80` | 4 | vocabulary and scan policy questions | Q1 delegated E16 | remove |
| `docs/engines/V8_KEYCLOAK_CONFIG.md:7,56-57` | 3 | vocabulary and retired autonomous-engine questions | Q3 retires the autonomous engine | remove |
| `docs/engines/V8_KEYCLOAK_PREREQUISITES.md:6,67-69` | 4 | vocabulary, installer/JDK/system-directory questions | Q10 closes installer/JDK; system-directory behavior remains evidence | keep |
| `docs/engines/V8_KEYCLOAK_SERVICE.md:6,72-75` | 5 | vocabulary and delivery/order/TLS/log questions | Q1/Q4 close policy choices; implementation evidence remains | keep |
| `docs/engines/WEB_ACCESS.md:6,72-74` | 4 | vocabulary and reset/restart/protection questions | Q1 delegated corresponding E/K decisions | remove |
| `docs/engines/WINDOWS_SERVICES.md:6,38,74-77` | 6 | vocabulary, PS7 compatibility and identity/restart/helper questions | Q1/Q2 close policy choices; compatibility evidence remains | keep |
| **Engine subtotal** | **93** |  |  |  |

### Migration, Phase 0, Phase 1, Phase 3, security, skills and roadmap

| File:line | Hits | Short text | Decision/evidence status | Recommendation |
|---|---:|---|---|---|
| `docs/migration/analysis-cross-machine-operations.md:6,70,74,82` | 4 | vocabulary, plan state and pending recommendations | Q4/Q5 close scope/update/archive; plan persistence remains integration work | keep |
| `docs/migration/analysis-pulse.md:6,61,83` | 3 | vocabulary, ScopePolicy wording and collector/runtime question | substantive scope/task choices are decided; evidence wording remains | keep |
| `docs/migration/catalog-conversion-plan.md:9,72,113,147,158,164,169,207,249-251,290,315,333,365,373,377,412,473` | 19 | all conversion-plan grep hits, including the post-220 markers | plan approved; later decisions close some items but this document also carries implementation/evidence notes | keep |
| `docs/migration/instance-directory-design.md:6` | 1 | tag definition says `[PENDING] later work` | this is the vocabulary definition, not an open instance-directory question | keep |
| `docs/migration/obsolete-catalog-metadata-cleanup.md:84` | 1 | real-snapshot execution evidence gate | evidence, not an owner decision | keep |
| `docs/phase0/central-schema-map.md:332` | 1 | text says an older pending item was replaced | historical/evidence wording inside live map | keep |
| `docs/phase0/current-system-map.md:15,353` | 2 | vocabulary and acceptance summary | evidence vocabulary/status | keep |
| `docs/phase0/engine-porting-matrix.md:14,75,215,401,452` | 5 | vocabulary and Phase-0 evidence/status references | later specs supersede some content, but this remains an evidence map | keep |
| `docs/phase0/risk-register.md:13,34,41,66,71-74,76` | 9 | vocabulary and risk evidence/mitigations | later decisions close some mitigations, not the dated risk evidence | keep |
| `docs/phase1/iis-reconcile-mwa-equivalence.md:7,30,80,87,94,101,111,115,118,127,141,151,163,165,178,191,199,208,212,214,218,222,227,237,240,246-249,252,254,260-266` | 38 | MWA/PS7 equivalence evidence and unexecuted gates | Q8 settles policy, not unexecuted compatibility/topology evidence | keep |
| `docs/phase1/phase1a-results.md:5,58-59,77-80` | 7 | vocabulary and ADR-0006 validation gates | accepted ADR does not erase validation gates | keep |
| `docs/phase1/phase1b-machine-identity-cng.md:8,26,139,141` | 4 | vocabulary, fallback, adoption/ACL boundary | final CNG product identity/ACL decision is not recorded | owner question |
| `docs/phase1/phase1b-sqlite-provider.md:8,132,162` | 3 | vocabulary, packaging and adoption marker | ADR-0009 closes version roles; integration/adoption wording remains evidence | keep |
| `docs/phase1/phase1c-local-web-security.md:8,23,80,104,180-183` | 8 | vocabulary and browser/coordinator/product-integration points | not every product-visible choice is an owner decision | keep |
| `docs/phase1/phase1c-operation-coordinator.md:8,75,161-164` | 6 | vocabulary and lock/REST/cancel/UI integration | no final per-engine/product surface decision | keep |
| `docs/phase1/sqlclient-pin.md:6,73-75` | 4 | vocabulary, delivery/security/update evidence | C10/K9 close policy; update evidence remains | keep |
| `docs/phase3/runtime-bootstrap.md:116` | 1 | clean-Windows execution/hardening gate | validation evidence | keep |
| `docs/phase3/runtime-catalog.md:20,111,113,115` | 4 | manifest/bootstrap/provider/role integration | ADR-0009 settles roles, not all wiring/package work | keep |
| `docs/phase3/runtime-logging-hardening.md:4,84` | 2 | review/hardening status | review evidence | keep |
| `docs/phase3/runtime-logging.md:77,79,81` | 3 | runtime/engine/UI logging integration | product integration not yet landed | keep |
| `docs/roadmap.md:5` | 1 | tag vocabulary | metadata only | keep |
| `docs/roadmap.md:71` | 1 | Links instance-directory exact columns/catalogs | Q9 plus implemented directory design supersede this pending wording | remove |
| `docs/security/threat-model.md:6,61,71,77,83-84,86,88,94-95,97,109,118,135,137-138,148,150,157-158,162,166,198` | 23 | package/browser/catalog/credential/runtime controls and gaps | some controls are decided; package-state trust and implementation evidence remain | keep |
| `docs/skills/bootstrap-new-server/SKILL.md:32` | 1 | workflow dependency | implementation dependency | keep |
| `docs/skills/config-repair-rule-authoring/SKILL.md:30,34` | 2 | output vocabulary and workflow dependency | implementation dependency | keep |
| `docs/skills/credential-portability/SKILL.md:34` | 1 | workflow dependency | implementation dependency | keep |
| `docs/skills/keycloak-client-provisioning/SKILL.md:33` | 1 | workflow dependency | implementation dependency | keep |
| `docs/skills/rename-instance/SKILL.md:33,37` | 2 | output vocabulary and workflow dependency | skill remains a skeleton | keep |
| **Migration/phase/security/skill/roadmap subtotal** | **157** |  |  |  |

### Active architecture, decision and handoff-register markers

| File:line | Hits | Short text | Decision/evidence status | Recommendation |
|---|---:|---|---|---|
| `docs/architecture/ADR-0007-embedded-readonly-catalog.md:42` | 1 | one grep line contains the remaining vault/slicing pending wording | conversion work supersedes part of the wording, but the vault-format boundary is not clearly closed | keep |
| `docs/architecture/ADR-0008-engine-host-contract.md:67` | 1 | verified package state instead of caller-supplied expectations | decision log line 57 explicitly remains pending | owner question |
| `docs/decisions-log.md:57` | 1 | verified package state | explicitly pending on 2026-10-08 | owner question |
| `docs/handoff/pending-decisions-register.md:3,98` | 2 | register text refers to the source `[PENDING]` set/count | documentary references in the answered register | keep |
| **Architecture/register subtotal** | **5** |  |  |  |

Live-document reconciliation from the displayed `Hits` column is **93 + 157 + 5 = 255 hits across 51 files**.

## Historical/evidence documents

These 15 files are part of the same reviewer grep, but per the audit rule they are grouped rather than line-audited.

| File | Hits | Status |
|---|---:|---|
| `docs/handoff/2026-10-05-documentation-tasks-handover.md` | 1 | historico, nao auditado |
| `docs/handoff/2026-10-05-phase1b-validation-handover.md` | 6 | historico, nao auditado |
| `docs/handoff/2026-10-05-phase1c-local-web-security-handover.md` | 6 | historico, nao auditado |
| `docs/handoff/2026-10-05-session-handoff.md` | 11 | historico, nao auditado |
| `docs/handoff/2026-10-06-phase1b-sqlite-provider-handover.md` | 3 | historico, nao auditado |
| `docs/handoff/2026-10-06-phase3-runtime-catalog-handover.md` | 5 | historico, nao auditado |
| `docs/handoff/2026-10-06-phase3-runtime-logging-handover.md` | 3 | historico, nao auditado |
| `docs/phase1/evidence/README.md` | 1 | historico, nao auditado |
| `docs/phase1/evidence/phase1b-machine-identity-37377769448/README.md` | 1 | historico, nao auditado |
| `docs/phase1/evidence/phase1b-machine-identity/README.md` | 1 | historico, nao auditado |
| `docs/phase1/evidence/phase1b-sqlite-provider-37392036026/README.md` | 3 | historico, nao auditado |
| `docs/phase1/evidence/phase1c-local-web-security-37382909046/README.md` | 3 | historico, nao auditado |
| `docs/phase1/evidence/phase1c-local-web-security/README.md` | 3 | historico, nao auditado |
| `docs/phase1/evidence/phase1c-operation-coordinator/README.md` | 1 | historico, nao auditado |
| `docs/phase3/evidence/runtime-logging-37395610886/README.md` | 2 | historico, nao auditado |
| **Historical/evidence subtotal** | **50** |  |

## Reconciliation

The arithmetic is taken directly from the displayed `Hits` rows:

- live engine specifications: **93**;
- other live migration/phase/security/skill/roadmap documents: **157**;
- active architecture/register documents: **5**;
- live subtotal: **255** across **51 files**;
- historical/evidence subtotal: **50** across **15 files**;
- grand total: **305 grep hits across 66 files**.

The only excluded path is `docs/handoff/work-queue.md`. This audit is a status inventory only; it changes no source specification.
