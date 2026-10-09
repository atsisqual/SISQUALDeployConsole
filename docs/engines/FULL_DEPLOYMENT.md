# Engine port specification: FULL_DEPLOYMENT

**Status:** [PROPOSED] specification for review (task 3, wave 6). No product code.
**Date:** 2026-10-05
**Sources (read only):** `ops.Action` row `FULL_DEPLOYMENT` and its 13 rows of `ops.ActionStep` in `database/sync/ManagementSync.sql` of `atsisqual/SISQUALManagementConsole` (reference head `9756ba956842884fabcf25b82c4fbf1d11cf56bd`); the procedure `ops.GetActionPlan`; the job history tables (`app.Job`, `app.JobStep`, 16 jobs). It has **no engine script of its own**: it is a composite of the other engines, whose specifications are in waves 1 to 5 (PRs #31, #32, #34, #35, #39). Script text is not copied.
Tags: [CONFIRMED] read in the source; [PROPOSED] recommendation; [PENDING] needs a decision; [V] needs a real server.

## 1. Purpose

Bring a machine to its defined state in one operation: preflight for every selected instance, then configuration, database content, assets, IIS, services, Keycloak, Web Access, Pulse and links pages. [CONFIRMED] Action: type `COMPOSITE`, group `ORCHESTRATION`, preview and apply, all enabled instances or one, confirmation text `DEPLOY`, stop on error, shown in the menu.

## 2. Steps

| Order | Step | Phase | Scope | Notes from the other specifications |
|---:|---|---|---|---|
| 10 | `DEPLOYMENT_PREFLIGHT` | preflight | per instance | read-only (wave 1) |
| 12 | `V8_KEYCLOAK_PREREQUISITES` | preflight | machine | **installs software even in preview** (wave 4) |
| 20 | `CONFIG_REPAIR` | execution | per instance | wave 2 |
| 30 | `DATABASE_SETTINGS` (engine `DATABASE_CONTENT_SYNC`) | execution | per instance | its Keycloak rules need a populated database (wave 5) |
| 40 | `MANAGED_ASSETS` | execution | per instance | wave 2 |
| 50 | `IIS_RECONCILE` | execution | per instance | wave 3; pool identity must exist |
| 60 | `WINDOWS_SERVICES` | execution | per instance | creates the shared account too late for step 50 (wave 4) |
| 63 | `V8_KEYCLOAK_CONFIG` | execution | per instance | **disabled** (wave 8) |
| 64 | `KEYCLOAK_CLIENT_SECRETS` | execution | per instance | runs before the service first starts (wave 4) |
| 65 | `V8_KEYCLOAK_SERVICE` | execution | per instance | wave 4 |
| 70 | `WEB_ACCESS` | execution | per instance | wave 5 |
| 75 | `PULSE_STATUS` | execution | machine | wave 1 |
| 80 | `LINKS_PAGES` | execution | per instance | wave 5 |

Every step has stop-on-error set. 12 steps are enabled.

## 3. How the old console ran it, and what the history shows

[CONFIRMED] The worker ran the preflight steps for all selected instances first, then, instance by instance, the execution steps in order; machine-scope steps (Pulse) ran once, at the end, with no instance. Jobs had 1 instance (9 jobs), 2 (6 jobs) or 6 (1 job).

[CONFIRMED] History (2026-08 to 2026-09, three machines): **16 jobs, all `APPLY`; no preview job exists.** 2 completed and 14 stopped on a failed step (3 in preflight, 11 in execution). Failed steps and the reason:

| Step | Failed | Reason (generic) |
|---|---:|---|
| `PULSE_STATUS` | 5 | the plan "must return exactly one hub row" (a machine without exactly one hub) |
| `CONFIG_REPAIR` | 4 | "1 file(s) failed" |
| `DEPLOYMENT_PREFLIGHT` | 3 | 12 and 5 blocking issues; one path error |
| `WEB_ACCESS` | 1 | setting the local user's password failed |
| `IIS_RECONCILE` | 1 | a null reference inside a configuration call |

The Keycloak steps do not appear in the history (they were added later). Reading: the operation is rarely successful on the first run, nobody previewed it, and the Pulse step blocks machines without a hub.

## 4. Port design [PROPOSED]

An orchestrator in the application core, not an engine script:

1. Build the plan from the catalog rows of `ops_Action` and `ops_ActionStep` (global tables) and the instances of this machine; steps are looked up by code in an allowlist of engine modules (no step runs data as code).
2. **Preview** runs each enabled step's preview in order and returns one plan with one fingerprint covering all steps. A later step's preview may depend on an earlier one's effect (the IIS site must exist for Web Access, the Keycloak files for the service): such a step reports `BLOCKED_BY <step>` instead of guessing.
3. **Apply** requires the confirmation word and the plan fingerprint; takes the machine lock and per-instance locks; runs the preflight phase for all instances, then the execution steps in order, per instance, machine-scope steps once; stops at the first failed step (stop on error) and reports completed, failed and not-run steps.
4. One operation id and one text log per run; each step writes its own result and run manifest; the orchestrator keeps the list of manifests for restore.
5. Cancel takes effect between steps, never inside a write.

## 5. Inputs

The two catalog tables above, the instance list, the credential package (presence checked by the preflight, never read by the orchestrator), and each step's own inputs.

## 6. Side effects

The union of all steps: files, ACLs, database rows, local accounts, services, IIS objects, pool restarts, scheduled tasks. A maintenance window is needed; the preview lists the disruptive steps (service and pool restarts).

## 7. Idempotency and resume

The composite is repeatable only if every step is. [PROPOSED] After a failure, fix the cause and run again: steps that already match report no change (this requires the idempotency fixes of waves 2 to 5). [PENDING] a "resume from step" option.

## 8. Failures

A failed step stops that run; the others are not started. A failed step of one instance stops the whole run (stop on error) unless the owner chooses per-instance continuation [PENDING]. The result states which instances were done.

## 9. Backup and restore

No automatic rollback. [PROPOSED] A combined manifest that lists each step's backup and restore function, and a `restore` that runs them in reverse order, stopping on the first failure. Database and account changes are not fully reversible; the manifest says which.

## 10. Secret risks

The orchestrator passes only `credentialRef` values; each step reads the package in memory. The aggregate result and the log contain statuses, codes and counts only. Marker credential test over the combined result and every step's artifacts.

## 11. What does not port as it is

The job queue and its tables (`app.Job`, `JobStep`, `JobLog`, `JobTarget`, claim and lease) are history and a worker protocol; they are replaced by one in-process operation with a text log. The machine-scope step runs with no instance, as before. The SQL plan procedure goes.

## 12. Test plan

- Runner: the orchestrator with fake engines that succeed, fail, skip or report `BLOCKED_BY`; order (preflight for all, then execution per instance, machine steps once), stop on error, the disabled step, confirmation word, fingerprint change refused, locks (a second run refused), cancel between steps, the combined result and manifest, restore order, marker credential.
- [V] A full run on a sandbox and on the pilot (a clean server) and on an existing server, with a preview first.

## 13. Open questions

1. [PENDING] **Order on a clean server** (the findings of waves 3 to 5): the shared account before IIS; the Keycloak database before `DATABASE_SETTINGS`; secrets after the service first starts; Keycloak files present. Recommendation: reorder or split into phases and prove it on the pilot.
2. [PENDING] `V8_KEYCLOAK_PREREQUISITES` belongs to the preflight phase but installs software. Recommendation: preflight phase read-only; installation as the first execution step, with a real preview.
3. [PENDING] Pulse on a machine without exactly one hub: "not applicable" (decided in the Pulse analysis) so that the step no longer blocks.
4. [PENDING] Stop the whole run or only that instance when one instance fails. Recommendation: stop the instance, continue the others, and fail at the end with the counts.
5. [PENDING] Whether to require a successful preview before apply (none was ever run). Recommendation: yes, via the fingerprint.
6. [PENDING] The Keycloak and software update path (Keycloak files, application files) is not a step: it belongs to the update operation outside the 19 engines (analysis of copy operations, PR #28).

## Host contract

- Engine class: `N/A - COMPOSITE / orchestrator`.
- `FULL_DEPLOYMENT` is not an engine and has no engine script. Engine-host class gates do not apply to this action; its side effects are the union of the enabled child-engine side effects and are orchestrator semantics.
- Credential references: none at the orchestrator level. Each child engine declares and receives its own approved credential references; the orchestrator passes only `credentialRef` values and does not consume child credentials itself.
