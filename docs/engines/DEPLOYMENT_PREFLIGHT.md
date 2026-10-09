# Engine port specification: DEPLOYMENT_PREFLIGHT

**Status:** [PROPOSED] specification for review (task 3, wave 1). No product code.
**Date:** 2026-10-05
**Sources (read only):** `ops.Engine` row `DEPLOYMENT_PREFLIGHT` of `database/sync/ManagementSync.sql` of `atsisqual/SISQUALManagementConsole` (file `Invoke-DeploymentPreflight.ps1`, version `1.0`, Windows PowerShell 5.1, administrator not required, stored `ScriptSha256` `5014058D...`; reference head `9756ba956842884fabcf25b82c4fbf1d11cf56bd`); the action `DEPLOYMENT_PREFLIGHT`; the procedures it calls. Script text is not copied.
Tags: [CONFIRMED] read in the source; [PROPOSED] recommendation; [PENDING] needs a decision; [V] needs a real server.

## 1. Purpose

A read-only check that everything a complete deployment needs is present and consistent, run before any change. It is step 10 of `FULL_DEPLOYMENT` (stop on error) and can be run alone for all enabled instances of the machine or for one. It changes nothing.

[CONFIRMED] Action: type `ENGINE`, group `ORCHESTRATION`, mode policy `NONE` (there is no apply), instance selection all enabled, optional single instance, 0 s timeout, hidden from the menu.

## 2. Inputs

From the machine's catalog (the local machine only; `dbo_ManagedServer` has exactly one row and its `MachineName` must equal the local computer name, ignoring case):

| Source | Columns | Use |
|---|---|---|
| `dbo_ManagedServer` | `MachineName`, `ServicesRoot`, `IsEnabled` | resolves the machine |
| `dbo_ManagedInstance` | `InstanceCode`, `IsEnabled`, `HostName`, `IisIdentityUserName`, and the columns the reviews use | instances to check |
| expected files (the old view `cfg.ExpectedValue`) | `InstanceCode`, `ApplicationCode`, `InstanceRoot`, `FullPath` | files that must exist; built from `cfg_ConfigRule`, `cfg_ConfigFile` and the instance roots |
| `cfg_ConfigFileRepairPolicy` | `RepairMode` (`PATCH` 7 rows, `REPLACE` 1 row; default `PATCH`) | whether the file itself or only its folder must exist |
| `cfg_WindowsServiceDefinition` | `ServiceCode`, `ExecutablePathTemplate`, `AccountSource` (1 row) | service executables to check |
| the review list | one entry per review code (section 3.4) | model reviews |
| credential package | per-instance `IIS_IDENTITY` and `WEB_ACCESS` credential references | presence only for the reviews that require them |

Parameters [PROPOSED]: `InstanceCode` (optional, must be an instance of this machine). No SQL instance or database parameter any more.

## 3. Steps

1. **Resolve.** Verify the catalog belongs to this machine; stop with a clear error if not (the old plan procedures raised 51010 and 51011 for an unregistered machine or foreign instance).
2. **Required files.** For every expected file: an empty path is an error; a missing instance root is an error ("not deployed"); in `REPLACE` mode the parent folder must exist; otherwise the file must exist. Each failure becomes an issue with area `APPLICATION_TREE`.
3. **Services.** For every enabled instance and service definition: the expanded executable must exist; the service account user name must be present in the catalog; the matching `IIS_IDENTITY` credential must exist in the package (presence, never printed). Area `WINDOWS_SERVICE`.
4. **Model reviews.** Run each review as local code over the catalog. [CONFIRMED] 12 reviews are marked for the preflight: `MANAGEMENT_MODEL`, `APPLICATION_CATALOG`, `MANAGED_ASSETS`, `REPAIR_MODEL`, `IIS_MODEL`, `EXTENDED_APPLICATIONS`, `WINDOWS_SERVICES`, `WEB_ACCESS`, `LINKS_MODEL`, `LINKS_PRESENTATION`, `PULSE_MODEL`, `OPERATIONS_FRAMEWORK`. In the source, 8 of the reviews raise 51 distinct issue codes (for example `SERVER_POLICY_MISSING`, `IIS_IDENTITY_PASSWORD_PENDING`, `WEB_ACCESS_POLICY_MISSING`, `LINKS_PAGE_POLICY_MISSING`, `PULSE_HUB_NOT_FOUND`, `OPS_ENGINE_HASH_MISMATCH`); the other 4 use a different form and their codes are collected when the review is ported.
5. **Report.** Print and return the issues sorted by severity, area, instance. Any `ERROR` blocks: the result is failed with the number of blocking issues. `WARNING` and `INFO` never block. With no error the result is READY with the counts of file and service definitions.

## 4. Side effects

None on the machine. It reads the file system (existence only) and the catalog. It writes the text log and the structured result. [CONFIRMED] The old engine wrote nothing to the database.

## 5. External dependencies

File system only. No IIS, SQL, service-manager, network or Keycloak call. The model reviews read the catalog, not live IIS.

## 6. Preview and apply

[PROPOSED] A single mode, run, with no apply, as in the source. The result follows `contracts/engine-result.schema.json`: one row per issue (operation type = the area, object = the object code, status `ERROR`, `WARNING` or `INFO`, details = the problem) and `succeeded` true only when there is no `ERROR`. The plan fingerprint is not needed.

## 7. Idempotency

Pure and repeatable: the same catalog and file tree give the same list in the same order (severity, area, instance, object).

## 8. Failures

- Catalog or manifest invalid, or machine mismatch: stop before any check.
- A file or folder that cannot be read (access denied) is an `ERROR` for that item, not a crash.
- A review that throws is reported as an `ERROR` with its review code and the other reviews still run.
- A missing server policy (IIS, Web Access, links, database copy, Pulse) is an `ERROR` so that `FULL_DEPLOYMENT` stops before an engine would stop on it (decision of 2026-10-05: engines stop without a policy row).

## 9. Backup and restore

Not applicable (read-only).

## 10. Secret risks

- The old plan rows carried the service account password in clear to the engine. [PROPOSED] The port never reads the value into the result: it only asks whether the credential entry exists (and, if the owner wants, whether it decrypts to a non-empty value in memory, discarding it).
- No path, user name or issue text may include a secret; reviews report names and codes only.
- A marker-secret test checks the log and the result.

## 11. What does not port as it is

1. [CONFIRMED] The old engine runs the SQL text stored in `ops.ReviewDefinition.CommandText`. AGENTS.md forbids executing text stored in the catalog. Each review becomes a local function named by its review code; the `CommandText` column is kept as data and ignored.
2. The 8 required objects of the action (procedures such as `ops.GetDeploymentPreflightFilePlan`, `cfg.GetRepairPlan`, `cfg.ReviewIisDeploymentModel`) disappear with the database.
3. `OPERATIONS_FRAMEWORK` (codes `OPS_ACTION_WITHOUT_ENGINE`, `OPS_ENGINE_HASH_MISMATCH`, `OPS_LOCAL_SERVER_MISSING`, `OPS_REQUIRED_OBJECT_MISSING`) checked the old framework. [PROPOSED] Replace it by: every enabled action has an engine module in the package, each module hash matches the signed manifest, the local server row exists, and the cross-reference between action and engine codes holds (risk R-043).

## 12. Test plan

- Runner (windows-2022, PowerShell 7): a synthetic catalog and a temporary folder tree. One test per issue code of every review; a missing root, a missing file, `REPLACE` with and without the parent folder, a missing executable, a missing user name, a missing credential entry, an instance filter, a foreign instance, a catalog for another machine, ordering and determinism, a throwing review that does not stop the others, no secret in log or result (marker credential).
- [V] A real pilot machine: the real expected-file list and the real service definition; counts compared with the old engine's output on a server that still has it.

## 13. Open questions

1. [DECIDED 2026-10-07] Does a missing credential package make the services check an `ERROR` or a `WARNING`? Recommendation: `ERROR`, because the services engine cannot run without it.
2. [DECIDED 2026-10-07] Should `FULL_DEPLOYMENT` also stop on `WARNING`? Recommendation: no, as today.
3. [DECIDED 2026-10-07] Are the four reviews whose codes were not extracted all needed? Recommendation: port all 12 and list their codes in the first port PR.
4. [DECIDED 2026-10-07] Add a check that the catalog build time is not older than a limit (risk R-044)? Recommendation: report it as `INFO` with the date, no limit.

The owner accepted the recommendation of all four ("Aceito as 8 sugestoes", 2026-10-07, covering this engine and the other wave 1 engine); see `docs/decisions-log.md`.

## Host contract

- Engine class: `READ_ONLY`.
- Intended credential references: `IIS_IDENTITY.*`, `WEB_ACCESS.*`.
- Executable host acceptance: in current `main`, none; the contract is empty and the host accepts exact references only. After PR #67 is integrated, `IIS_IDENTITY.*` and `WEB_ACCESS.*` are declared for `DEPLOYMENT_PREFLIGHT` and accepted by family for active catalog instances. PR #67 adds the `TYPE.*` family form only for `IIS_IDENTITY`, `WEB_ACCESS`, `MOBILE_APP_TOKEN`, and `RULE_SECRET`, limited to active catalog instances.