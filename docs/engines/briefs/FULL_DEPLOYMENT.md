# FULL_DEPLOYMENT orchestration brief

**Status:** [PROPOSED]
**Task:** T16 / M3.10
**Date:** 2026-10-10

This brief defines the orchestration contract that must be settled before `FULL_DEPLOYMENT` product code. It complements `docs/engines/FULL_DEPLOYMENT.md`; `FULL_DEPLOYMENT` remains a `COMPOSITE` action, not an engine.

## 1. Sources and evidence boundary

[CONFIRMED] Checked now against `main`:

- `docs/engines/FULL_DEPLOYMENT.md` records 13 source-era `ops.ActionStep` rows, 12 enabled, and no engine script of its own.
- `docs/engines/README.md` confirms the engine host refuses non-`ENGINE` actions; `FULL_DEPLOYMENT` therefore runs in the application/orchestration layer.
- Child-engine specifications define their own credentials, preview/apply, backup and result semantics. The orchestrator must not acquire broader credential access than the union explicitly delegated to each child invocation.
- Owner decisions retire standalone `V8_KEYCLOAK_CONFIG` and `DATABASE_SETTINGS` engines; disabled step 63 does not return as an executable child, while action `DATABASE_SETTINGS` resolves to `DATABASE_CONTENT_SYNC`.

[NOT VERIFIED] A clean-server end-to-end sequence is not yet proven. The ordering contradictions around account creation, Keycloak files/database initialization and client secrets remain genuine gates, not documentation gaps to hide.

## 2. Source step inventory

| Order | Action/step | Scope | Portable child |
|---:|---|---|---|
| 10 | `DEPLOYMENT_PREFLIGHT` | per selected instance / all selected first | `DEPLOYMENT_PREFLIGHT` |
| 12 | `V8_KEYCLOAK_PREREQUISITES` | machine | `V8_KEYCLOAK_PREREQUISITES` |
| 20 | `CONFIG_REPAIR` | per instance | `CONFIG_REPAIR` |
| 30 | `DATABASE_SETTINGS` | per instance | `DATABASE_CONTENT_SYNC` |
| 40 | `MANAGED_ASSETS` | per instance | `MANAGED_ASSETS` |
| 50 | `IIS_RECONCILE` | per instance | `IIS_RECONCILE` |
| 60 | `WINDOWS_SERVICES` | per instance | `WINDOWS_SERVICES` |
| 63 | `V8_KEYCLOAK_CONFIG` | per instance | **disabled/retired; no child invocation** |
| 64 | `KEYCLOAK_CLIENT_SECRETS` | per instance | `KEYCLOAK_CLIENT_SECRETS` |
| 65 | `V8_KEYCLOAK_SERVICE` | per instance | `V8_KEYCLOAK_SERVICE` |
| 70 | `WEB_ACCESS` | per instance | `WEB_ACCESS` |
| 75 | `PULSE_STATUS` | machine | `PULSE_STATUS` |
| 80 | `LINKS_PAGES` | per instance | `LINKS_PAGES` |

[CONFIRMED] Every source step was stop-on-error. Historical jobs were APPLY-only and mostly failed before completion; the portable design must require a trustworthy preview rather than repeat that operating pattern.

## 3. Orchestrator invariants

[PROPOSED] The orchestrator:

- reads only verified local catalog action/step/instance metadata;
- resolves each enabled step through an exact allowlist/registry, never executable catalog text;
- uses one operation id and one machine-level operation lock;
- obtains per-instance locks before any child APPLY that touches that instance;
- passes child-specific approved references/inputs and never reads secret values itself;
- records child result/manifests without rewriting their semantic content;
- never invents a successful child result when a child was skipped/blocked/not run;
- treats disabled/retired step 63 as structurally absent from execution while retaining audit visibility that the source row exists disabled.

## 4. Preview is a composite plan, not child APPLY simulation

[PROPOSED] `FULL_DEPLOYMENT PREVIEW` invokes child preview/read-only paths only. A child whose prerequisites are not yet present in current state may return `BLOCKED_BY` with the prerequisite/action code rather than guessing the post-APPLY world.

The composite preview records for every selected target/step:

- child action/engine/version;
- scope (`MACHINE`, `INSTANCE`);
- planned mode and child plan fingerprint where applicable;
- status (`READY`, `NO_CHANGE`, `BLOCKED_BY`, `NOT_APPLICABLE`, `ERROR` or approved equivalent);
- blocking dependency, if any;
- disruptive effects declared by the child (restart/outage/installer/database overwrite, etc.);
- backup/restore capability declared by the child;
- child credential-reference names only, never values.

A deterministic composite fingerprint covers catalog/package identity, selected instances, enabled step graph/order and every child preview fingerprint/status relevant to APPLY.

## 5. APPLY requires a successful confirmed preview

[PROPOSED] APPLY is refused unless:

- the exact composite preview fingerprint is supplied;
- preview is within its approved validity period;
- package/catalog/credentials-reference set/selected targets have not drifted;
- no required child remains `BLOCKED_BY` or `ERROR`;
- every destructive/disruptive child has its own entry gates satisfied;
- operator gives the exact confirmation text `DEPLOY` after the final summary of effects.

There is no “apply without preview” compatibility path.

## 6. Child-result gate contract

The orchestrator needs a mechanical answer from every child. [PROPOSED] For each child invocation it consumes:

1. valid engine-result contract/version and matching operation/action/target identity;
2. process/engine `succeeded` as child-execution status;
3. summary target counts consistent with the child contract;
4. blocking `ERROR`/failure semantics defined by that child;
5. child manifest/backup metadata where APPLY changed managed state;
6. explicit `NOT_APPLICABLE`/`SKIPPED` semantics, never inferred from missing rows;
7. `BLOCKED_BY` only during composite preview/planning, with an exact known dependency.

[PENDING] Standalone `MODEL_REVIEW` has a distinct “model findings vs execution succeeded” semantic issue, but it is not a FULL_DEPLOYMENT child. Full-deployment children must each document their own blocking interpretation before integration.

## 7. Required gates per enabled step

| Child | Orchestrator gate before APPLY |
|---|---|
| `DEPLOYMENT_PREFLIGHT` | all selected targets reviewed; no blocking preflight error; incomplete coverage marker cannot be treated as full readiness until M2 closes |
| `V8_KEYCLOAK_PREREQUISITES` | true no-write preview; exact approved installer hashes/JDK 23 sources available if installation needed |
| `CONFIG_REPAIR` | exact rule/secret contract; backup/restore policy sufficient; deterministic plan |
| `DATABASE_CONTENT_SYNC` | structured C7 predicates only; target DB readiness/missing-DB orchestration settled |
| `MANAGED_ASSETS` | paths contained; backup/restore available for replacements |
| `IIS_RECONCILE` | ADR-0006 code gates; production use still requires its `[V]` conditions; required identity exists before IIS APPLY |
| `WINDOWS_SERVICES` | shared identity/password invariant proven; service/account ordering settled |
| `KEYCLOAK_CLIENT_SECRETS` | Keycloak DB/client rows exist or a later rerun is scheduled as a required gate |
| `V8_KEYCLOAK_SERVICE` | files/config/prerequisites exist; service credential safe path; health policy decided |
| `WEB_ACCESS` | policy/template/credential/path ready; IIS root site/pool exists |
| `PULSE_STATUS` | machine with no Pulse profile is `NOT_APPLICABLE`, not failure, per owner decision |
| `LINKS_PAGES` | IIS/files roots exist; directory/model valid; deterministic file plan |

The orchestrator does not weaken a child gate to make the composite continue.

## 8. Clean-server dependency contradictions

[CONFIRMED] Current source order contains unresolved dependencies:

- IIS step 50 can require a pool identity that WINDOWS_SERVICES step 60 historically creates;
- database-content step 30 can target Keycloak before first Keycloak initialization;
- client-secret step 64 can run before service/database initialization at 65;
- Keycloak application files are supplied by the software update/copy path outside the 19 engines.

[PROPOSED] Represent orchestration as an explicit dependency graph plus stable display order. Do not “solve” dependencies by assuming current machine state. Before code, choose and test a clean-server sequence that either reorders/splits phases or introduces an approved identity/file/database bootstrap operation.

[PENDING] Exact corrected sequence requires reviewer/owner decision where behavior/scope changes. Until then `FULL_DEPLOYMENT APPLY` is not production-ready for a clean server.

## 9. Scope execution and failure policy

[CONFIRMED] Source worker ran preflight for all selected instances, then execution instance by instance, with machine steps once.

[PROPOSED] Portable policy:

- machine-scoped prerequisites execute once;
- preflight evaluates all selected instances before any managed mutation;
- per-instance execution keeps intra-instance dependency order;
- a failure stops later steps for that instance;
- independent selected instances may continue, and the composite fails at end with completed/failed/not-run counts;
- machine-scope child failure stops children that depend on it for every instance.

[PENDING] Continuing independent instances after one fails changes the source “stop whole run” behavior and requires explicit approval before implementation if not already delegated.

## 10. Cancellation

[PROPOSED] Cancellation is cooperative at child safe points. The orchestrator:

- stops scheduling new child invocations immediately;
- lets an already-running mutable child follow that child's host cancellation/timeout contract rather than killing it unsafely;
- marks never-started steps/targets `NOT_RUN_CANCELLED` (or approved equivalent);
- preserves all backup manifests produced before cancellation.

No automatic rollback is triggered solely by cancel.

## 11. Combined backup/restore manifest

[PROPOSED] The composite manifest is an index of child manifests, not a second copy of secret/sensitive before-images. It records child action, target, manifest identity/hash, change status and restore capability.

A restore workflow runs approved child restores in reverse dependency/order only where each child declares restoration safe. It stops on restore failure and reports manual-recovery requirements.

No claim of transactional all-or-nothing rollback is made: accounts, installers, external services and some database effects are inherently not fully reversible.

## 12. Credentials

The orchestrator declares no credential references. It asks the credential subsystem/host to provide each child only the references authorized by that child contract.

[PROPOSED] Composite preview may list missing reference **names** and affected children but never values. Aggregate log/result/manifest are marker-secret tested together with every child artifact.

## 13. Result model

[PROPOSED] Composite result contains:

- operation/package/catalog/selection/fingerprint identity;
- ordered child-step entries per machine/instance;
- child result reference/summary and status;
- completed, failed, blocked, not-applicable and not-run counts;
- first/primary failure plus all additional independent failures;
- disruptive operations actually performed;
- combined backup-manifest reference;
- explicit overall success only if every required selected target/step reached an accepted terminal state.

A child `SKIPPED` is success only if that exact child/orchestration contract says the condition is acceptable and no required follow-up remains.

## 14. Required orchestrator tests

Use fake child engines plus integrated child fixtures to prove:

- exact 13-row source inventory with step 63 disabled and 12 enabled children;
- non-engine COMPOSITE never sent to engine host as if it were an engine;
- all-target preflight before mutation;
- machine child once and per-instance children scoped correctly;
- deterministic composite preview/fingerprint;
- child preview `BLOCKED_BY` propagation;
- APPLY refused without confirmed successful preview;
- package/catalog/child-fingerprint/selection drift refusal;
- `DEPLOY` confirmation;
- stop later steps for a failed instance while approved independent continuation works;
- machine-scope failure blocks dependants globally;
- Pulse no-profile `NOT_APPLICABLE` does not fail;
- disabled retired step never executes;
- cancellation between/safe-within children;
- locks reject a second conflicting deployment;
- composite manifest indexes child backup manifests; reverse restore ordering;
- marker secrets absent from all aggregate artifacts;
- clean-server dependency fixture exposes the known identity/Keycloak-file/database contradictions until resolved.

[V] Full preview then APPLY on sandbox, clean pilot server, and later an existing server.

## 15. Open decisions

1. [PENDING] Correct clean-server dependency/order for identity, Keycloak files/database and client secrets.
2. [PENDING] Whole-run stop versus continue independent instances after one fails.
3. [PENDING] Exact preview validity period for the composite.
4. [PENDING] Resume-from-step; recommendation is rerun/idempotency first, resume later.
5. [PENDING] Software-update/copy operation that places Keycloak/application files and its relationship to FULL_DEPLOYMENT.

## 16. Entry gate for product code

`FULL_DEPLOYMENT` orchestration code may start when:

- required child engine contracts/result semantics are integrated and their code entry gates are satisfied;
- M2 closes preflight completeness/parity or the owner explicitly accepts an incomplete preflight gate;
- clean-server dependency graph/order is decided;
- child credential isolation is enforceable by the host;
- composite preview/fingerprint and failure/cancellation policies are explicit;
- every mutating child has a backup/restore declaration and any destructive child (especially DATABASE_COPY, if ever composed later) has its own safety gates;
- end-to-end runner tests can prove the orchestrator without weakening any child contract.
