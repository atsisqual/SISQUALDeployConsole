# Engine port specification: MODEL_REVIEW

**Status:** [PROPOSED] specification for review (task 3, wave 7). No product code.
**Date:** 2026-10-05
**Sources (read only):** `ops.Engine` row `MODEL_REVIEW` of `database/sync/ManagementSync.sql` of `atsisqual/SISQUALManagementConsole` (file `Invoke-ModelReview.ps1`, version `1.0`, Windows PowerShell 5.1, administrator not required, stored `ScriptSha256` `CC4D8B92...`; reference head `9756ba956842884fabcf25b82c4fbf1d11cf56bd`); the action `MODEL_REVIEW` and the table `ops.ReviewDefinition` (12 rows). Script text is not copied and no secret value appears here.
Tags: [CONFIRMED] read in the source; [PROPOSED] recommendation; [PENDING] needs a decision; [V] needs a real server.

## 1. Purpose

Run every model review of the machine and report the issues, as a standalone check. [CONFIRMED] Action: group `HEALTH`, **no preview or apply** (mode `NONE`), all enabled instances or one, hidden from the menu. It reads and writes nothing on the machine.

## 2. Inputs

`ops_ReviewDefinition` (12 rows, all enabled and all marked for the deployment preflight): `MANAGEMENT_MODEL`, `APPLICATION_CATALOG`, `MANAGED_ASSETS`, `REPAIR_MODEL`, `IIS_MODEL`, `EXTENDED_APPLICATIONS`, `WINDOWS_SERVICES`, `WEB_ACCESS`, `LINKS_MODEL`, `LINKS_PRESENTATION`, `PULSE_MODEL`, `OPERATIONS_FRAMEWORK`. The catalog of the machine and the instance filter. [CONFIRMED] In the source each definition holds the SQL text of its review (`CommandText`).

## 3. Steps

1. Resolve the machine; read the review list (an empty list is an error).
2. Run each review for the machine and optional instance. No rows is `OK`; rows are shown and written to one report file per review.
3. List the enabled local instances.
4. [CONFIRMED] Issues, whatever their severity, do not fail the run. Only a review that cannot be executed does: such reviews are collected in an errors file and the run fails with their number at the end.

## 4. Side effects

None on the machine; report files only.

## 5. External dependencies

None beyond the catalog.

## 6. Preview and apply

Single mode, read-only. [PROPOSED] The result follows the engine contract: one row per issue (review, severity, object, message), `succeeded` true when every review ran, plus the counts per severity.

## 7. Idempotency

Pure: the same catalog gives the same list in the same order.

## 8. Failures

A review that throws is reported with its code and does not stop the others. An empty review list or a catalog for another machine stops before any review.

## 9. Backup and restore

Not applicable.

## 10. Secret risks

None expected: reviews report codes, object names and counts. [PROPOSED] A marker-credential test over the report, since the reviews of services and Web Access look at account and password presence (presence only, never a value).

## 11. What does not port as it is

[CONFIRMED] The old engine executes SQL text stored in the data, which AGENTS.md forbids. The reviews become the same local functions as in `DEPLOYMENT_PREFLIGHT` (wave 1, PR #31): one function per review code, shared by both engines; `CommandText` stays in the catalog as data and is ignored. The report folder under the backup root and the SQL context procedure go.

## 12. Test plan

- Runner: the shared review fixtures (one per issue code); a throwing review that does not stop the others; issues that do not fail the run; the instance filter; an empty list; a foreign catalog; no secret in the report (marker).
- [V] The real model of a pilot machine; counts compared with the old engine's output where it still exists.

## 13. Open questions

1. [PENDING] Keep a separate action, or make it the preview of the preflight. Recommendation: keep a read-only "check the model" screen that calls the shared reviews, and let the preflight call the same code and block on errors.
2. [PENDING] Add the catalog status to the report (build time, source, manifest verified), which is the visible control for the stale-catalog risk (R-044). Recommendation: yes, as information rows.
