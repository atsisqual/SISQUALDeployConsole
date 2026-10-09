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

For this correction every one of the **255 live grep lines** was re-reviewed individually. A vocabulary definition, tag legend, documentary mention, evidence gate, validation or still-unresolved implementation item is `keep`. A substantive question whose decision is already closed in `docs/decisions-log.md` or `docs/handoff/pending-decisions-register.md` is `remove`; when the accepted answer is to derive or validate behavior in a test, the stale decision marker is still `remove` while the validation itself remains. A question that still requires an owner decision is `owner question`.

Relative to the previous audit head `f67dcbdda8984f60edcab560cb57324f013cd0a3`, **81 live grep lines changed recommendation**: 43 engine-specification lines and 38 other live-document lines. The census does not change.

Historical handoffs (`docs/handoff/2026-*`) and evidence (`docs/*/evidence/*`) are grouped by file and hit count as `historico, nao auditado`.

## Live documents: line audit

### Engine specifications

| File:line | Hits | Short text | Decision/evidence status | Recommendation |
|---|---:|---|---|---|
| `docs/engines/CONFIG_REPAIR.md:6` | 1 | tag vocabulary | vocabulary only | keep |
| `docs/engines/CONFIG_REPAIR.md:62,82-86` | 6 | retention, selector/restart/backup/secret/retry questions | Q1 closes E3/K11/K12; E3's accepted answer for selector behavior is to derive it by differential test | remove |
| `docs/engines/DATABASE_CONTENT_SYNC.md:7` | 1 | tag vocabulary | vocabulary only | keep |
| `docs/engines/DATABASE_CONTENT_SYNC.md:39,74-76` | 4 | SQL trust, filters, Keycloak path and missing-database timing | Q1 closes K9/C7/E11; E11 keeps the real Keycloak behavior as a `[V]` validation, not an owner decision | remove |
| `docs/engines/DATABASE_COPY.md:6` | 1 | tag vocabulary | vocabulary only | keep |
| `docs/engines/DATABASE_COPY.md:56,76-79` | 5 | retention, allowed pairs, archive/restore and settings sync | Q5 closes S11-S14 for these points | remove |
| `docs/engines/DATABASE_COPY.md:80-81` | 2 | destination Keycloak handling and real SQL permissions | S14 explicitly leaves the Keycloak case to its design; permissions need real-system evidence | keep |
| `docs/engines/DEPLOYMENT_PREFLIGHT.md:6` | 1 | tag vocabulary | vocabulary only | keep |
| `docs/engines/ENVIRONMENT_STATE_PROBE.md:6` | 1 | tag vocabulary (`[PENDING] needs a decision`) | vocabulary only, not an open question | keep |
| `docs/engines/ENVIRONMENT_STATE_PROBE.md:74-76` | 3 | persistence, probe route and shared classifier questions | Q1 closes E15 with the recommendation as written | remove |
| `docs/engines/FULL_DEPLOYMENT.md:6` | 1 | tag vocabulary | vocabulary only | keep |
| `docs/engines/FULL_DEPLOYMENT.md:68,72,93-98` | 8 | resume/failure/order/preflight/Pulse/fingerprint/update questions | Q1/Q2/Q4 and the Pulse owner decisions close these choices | remove |
| `docs/engines/IIS_RECONCILE.md:6,58,77-78` | 4 | vocabulary plus backup/IIS-29/mechanism evidence | Q8 does not close the backup/IIS-29/mechanism evidence in these lines | keep |
| `docs/engines/IIS_RECONCILE.md:75-76,79` | 3 | certificate store, unmanaged deletion and shared-account order | Q8 closes the first two; Q2/E7 closes the account-order point | remove |
| `docs/engines/KEYCLOAK_CLIENT_SECRETS.md:6` | 1 | tag vocabulary | vocabulary only | keep |
| `docs/engines/KEYCLOAK_CLIENT_SECRETS.md:35,71-74` | 5 | SQL trust, clean-server order, cache path, secret cardinality and SQL security | Q1 closes K9/K12/E11 and records testing as the accepted resolution where real Keycloak evidence is needed | remove |
| `docs/engines/LINKS_PAGES.md:6` | 1 | tag vocabulary | vocabulary only | keep |
| `docs/engines/LINKS_PAGES.md:73-76` | 4 | generation/policy/user/obsolete-row questions | Q1/Q9 and the 2026-10-05 obsolete-row decision close them | remove |
| `docs/engines/LINKS_VISIBILITY.md:6` | 1 | tag vocabulary | vocabulary only | keep |
| `docs/engines/LINKS_VISIBILITY.md:78-80` | 3 | option A, V1 need and second-reader questions | Q9 and Q6 close these choices | remove |
| `docs/engines/MANAGED_ASSETS.md:6` | 1 | tag vocabulary | vocabulary only | keep |
| `docs/engines/MANAGED_ASSETS.md:76-79` | 4 | missing-logo/PNG/ACL/deletion questions | Q1 closes E4 | remove |
| `docs/engines/MODEL_REVIEW.md:6` | 1 | tag vocabulary | vocabulary only | keep |
| `docs/engines/MODEL_REVIEW.md:62-63` | 2 | action surface and catalog-status questions | Q1 closes E17 | remove |
| `docs/engines/PULSE_STATUS.md:6,34` | 2 | vocabulary and `ScheduledTasks` compatibility test | line 34 remains a technical compatibility test even though the COM fallback is decided | keep |
| `docs/engines/README.md:44` | 1 | classification fallback uses `[PENDING]` | status vocabulary/rule | keep |
| `docs/engines/STORAGE_SIZE_SCAN.md:6` | 1 | tag vocabulary | vocabulary only | keep |
| `docs/engines/STORAGE_SIZE_SCAN.md:78-80` | 3 | history, time-budget and unit questions | Q1 closes E16 | remove |
| `docs/engines/V8_KEYCLOAK_CONFIG.md:7` | 1 | tag vocabulary | vocabulary only | keep |
| `docs/engines/V8_KEYCLOAK_CONFIG.md:56-57` | 2 | autonomous-engine configuration questions | Q3 retires the autonomous engine | remove |
| `docs/engines/V8_KEYCLOAK_PREREQUISITES.md:6` | 1 | tag vocabulary | vocabulary only | keep |
| `docs/engines/V8_KEYCLOAK_PREREQUISITES.md:67-69` | 3 | installer/JDK/system-library questions | Q10 closes installer/JDK; Q1 closes E9 by choosing the stated validation path | remove |
| `docs/engines/V8_KEYCLOAK_SERVICE.md:6` | 1 | tag vocabulary | vocabulary only | keep |
| `docs/engines/V8_KEYCLOAK_SERVICE.md:72-75` | 4 | delivery/order/TLS/log questions | Q1/Q2/Q4 close E10/K10 and the clean-server/update choices | remove |
| `docs/engines/WEB_ACCESS.md:6` | 1 | tag vocabulary | vocabulary only | keep |
| `docs/engines/WEB_ACCESS.md:72-74` | 3 | password reset, restart and credential-file protection questions | Q1 closes E12/K13 | remove |
| `docs/engines/WINDOWS_SERVICES.md:6,38` | 2 | vocabulary and PowerShell 7 compatibility evidence | line 38 is still a compatibility test, not an owner question | keep |
| `docs/engines/WINDOWS_SERVICES.md:74-77` | 4 | account order/sharing/restart/helper questions | Q2 and Q1 close E7/E8 | remove |
| **Engine subtotal** | **93** |  |  |  |

### Migration, Phase 0, Phase 1, Phase 3, security, skills and roadmap

| File:line | Hits | Short text | Decision/evidence status | Recommendation |
|---|---:|---|---|---|
| `docs/migration/analysis-cross-machine-operations.md:6` | 1 | tag vocabulary | vocabulary only | keep |
| `docs/migration/analysis-cross-machine-operations.md:70,74,82` | 3 | plan location plus the owner-decision section/prefix | S4 and Q4/Q5 close all decisions referenced by these markers | remove |
| `docs/migration/analysis-pulse.md:6` | 1 | tag vocabulary | vocabulary only | keep |
| `docs/migration/analysis-pulse.md:61,83` | 2 | scope pointer and collector-runtime pointer | the 2026-10-06 owner decisions close both | remove |
| `docs/migration/catalog-conversion-plan.md:9,72,113,207,251,290,315,365,373,377` | 10 | vocabulary plus still-open/evidence/implementation items | no recorded decision closes every pending concept on these raw lines | keep |
| `docs/migration/catalog-conversion-plan.md:147,158,164,169,249-250,333,412,473` | 9 | BLOB, cross-machine links/Pulse, SQL-client/security, freeze and signing-approval markers | 2026-10-05 BLOB/credential decisions plus Q6/C10/K9 and the recorded credential-package Q1/Q2 answers close these markers | remove |
| `docs/migration/instance-directory-design.md:6` | 1 | tag definition says `[PENDING] later work` | vocabulary definition, not an open instance-directory question | keep |
| `docs/migration/obsolete-catalog-metadata-cleanup.md:84` | 1 | real-snapshot cleanup evidence | evidence gate | keep |
| `docs/phase0/central-schema-map.md:332` | 1 | text refers to an older pending item | documentary/historical wording inside a live map | keep |
| `docs/phase0/current-system-map.md:15,353` | 2 | vocabulary and acceptance summary | vocabulary/status references | keep |
| `docs/phase0/engine-porting-matrix.md:14,75,215,401,452` | 5 | vocabulary and Phase-0 evidence/status references | evidence map, not stale owner questions | keep |
| `docs/phase0/risk-register.md:13,34` | 2 | vocabulary and machine-key validation status | vocabulary/technical evidence remains live | keep |
| `docs/phase0/risk-register.md:41,66,71-74,76` | 7 | plan location, non-engine scope, change freeze, issuer/passphrase custody, catalog review and SQL-client delivery | S4, Q4, Q6, Q7 and C10 close these policy questions | remove |
| `docs/phase1/iis-reconcile-mwa-equivalence.md:7,30,80,87,94,101,111,115,118,127,141,151,163,165,178,191,199,208,212,214,218,222,227,237,240,246-249,252,254,260-266` | 38 | vocabulary, MWA/PS7 evidence and unexecuted gates | Q8 settles policy choices but these lines still carry validation/mechanism evidence not closed by that decision | keep |
| `docs/phase1/phase1a-results.md:5,58-59,77-80` | 7 | vocabulary and ADR-0006 validation gates | accepted ADR does not erase validation gates | keep |
| `docs/phase1/phase1b-machine-identity-cng.md:8,26` | 2 | vocabulary and conditional DPAPI fallback | vocabulary/technical gate, not owner questions | keep |
| `docs/phase1/phase1b-machine-identity-cng.md:139,141` | 2 | final CNG adoption/name/ACL boundary | still needs owner/product acceptance | owner question |
| `docs/phase1/phase1b-sqlite-provider.md:8` | 1 | tag vocabulary | vocabulary only | keep |
| `docs/phase1/phase1b-sqlite-provider.md:132,162` | 2 | version-role policy and runtime-dependency approval | ADR-0009 accepts the managed provider/version roles and records runtime adoption | remove |
| `docs/phase1/phase1c-local-web-security.md:8,23,80,104,180-183` | 8 | vocabulary and browser/coordinator/product-integration work | evidence/implementation or still-open product choices | keep |
| `docs/phase1/phase1c-operation-coordinator.md:8,75,161-164` | 6 | vocabulary and lock/REST/cancel/UI integration | no final per-engine/product-surface decision closes these lines | keep |
| `docs/phase1/sqlclient-pin.md:6,75` | 2 | vocabulary and future pin-update evidence | vocabulary/process evidence | keep |
| `docs/phase1/sqlclient-pin.md:73-74` | 2 | SQL-client delivery and connection-security decisions | Q1 closes C10/K9 | remove |
| `docs/phase3/runtime-bootstrap.md:116` | 1 | clean-Windows execution/hardening evidence | validation gate | keep |
| `docs/phase3/runtime-catalog.md:20,111,113,115` | 4 | manifest/bootstrap/provider/role integration | implementation work remains even though role policy is decided | keep |
| `docs/phase3/runtime-logging-hardening.md:4,84` | 2 | review/hardening status | review/evidence status | keep |
| `docs/phase3/runtime-logging.md:77,79,81` | 3 | runtime/engine/UI logging integration | product integration work | keep |
| `docs/roadmap.md:5` | 1 | tag vocabulary | vocabulary only | keep |
| `docs/roadmap.md:71` | 1 | Links instance-directory columns/catalogs | Q9 plus the implemented directory design supersede this pending wording | remove |
| `docs/security/threat-model.md:6,61,77,97,109,118,135,150,157,162,166,198` | 12 | vocabulary plus still-open implementation/evidence controls | no recorded owner decision fully closes the pending concept on these raw lines | keep |
| `docs/security/threat-model.md:71,83-84,86,88,94-95,137-138,148,158` | 11 | tamper log, package rollback/ACL/reverify/release flag, catalog review/freeze, custodian, SQL-client delivery and backup-policy decisions | Q1 closes K7/K11; Q6 closes K3-K5/C5-C6; Q7 closes K1-K2; C10 closes SQL-client delivery | remove |
| `docs/skills/bootstrap-new-server/SKILL.md:32` | 1 | workflow dependency | implementation dependency | keep |
| `docs/skills/config-repair-rule-authoring/SKILL.md:30,34` | 2 | output vocabulary and workflow dependency | vocabulary/implementation dependency | keep |
| `docs/skills/credential-portability/SKILL.md:34` | 1 | workflow dependency | implementation dependency | keep |
| `docs/skills/keycloak-client-provisioning/SKILL.md:33` | 1 | workflow dependency | implementation dependency | keep |
| `docs/skills/rename-instance/SKILL.md:33,37` | 2 | output vocabulary and workflow dependency | vocabulary/implementation dependency | keep |
| **Migration/phase/security/skill/roadmap subtotal** | **157** |  |  |  |

### Active architecture, decision and handoff-register markers

| File:line | Hits | Short text | Decision/evidence status | Recommendation |
|---|---:|---|---|---|
| `docs/architecture/ADR-0007-embedded-readonly-catalog.md:42` | 1 | one grep line contains both vault and slicing pending wording | at least the vault-format concept remains unresolved on the audited tree | keep |
| `docs/architecture/ADR-0008-engine-host-contract.md:67` | 1 | verified package state instead of caller-supplied expectations | decision log line 57 is explicitly pending on the audited tree | owner question |
| `docs/decisions-log.md:57` | 1 | verified package state | explicitly pending on the audited tree | owner question |
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
