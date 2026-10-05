# Analysis: Pulse (`PULSE_STATUS` and the Pulse profile)

**Status:** [PROPOSED] analysis, with the owner answers of 2026-10-05 recorded in section 9. It closes the open item "does a machine's Pulse need the hub or the instances of other machines" (conversion plan 2.4, roadmap section 5). No product code.
**Date:** 2026-10-05
**Sources (read only):** `database/sync/ManagementSync.sql` of `atsisqual/SISQUALManagementConsole` (29,516,382 bytes, blob `9401e2c3cb2517ca88848f902ff4d3786583e888`, reference head `9756ba956842884fabcf25b82c4fbf1d11cf56bd`), and the `PULSE_STATUS` engine exported from it (`ops.Engine`: file `Invoke-SISQUALPulseStatus.ps1`, version `v2`, Windows PowerShell 5.1, requires administrator, stored `ScriptSha256` `60917424...`). Script text is not copied here; objects are cited by name.
Tags: [CONFIRMED] read in the source; [PROPOSED] recommendation; [PENDING] needs a decision; [V] needs a real server.

## 1. Answer in four lines

1. [CONFIRMED] `PULSE_STATUS` needs nothing from another machine. A hub checks only the instances of its own `ServerCode` that are in its own country, writes its page and status file on its own server, and registers a scheduled task there.
2. [CONFIRMED] No catalog needs the hub of another machine for Pulse itself. The 4 `cfg.PulseProfile` rows are cut to the machine of their hub (already so in the conversion plan); PRESALES and TENDERS have none.
3. [CONFIRMED] The only cross-machine reference around Pulse is a links-page card: the application row `PULSE_STATUS` in `cfg.Application` carries `LinksHubInstanceCode` = `DEMOPT` and a URL template with the host name placeholder. That is a links-page matter, handled in `instance-directory-design.md` (task 1c), not by the Pulse engine.
4. [PROPOSED] Three parts of the old design cannot be ported as they are, because they used `_sisqualMANAGEMENT` while the collector runs (record of each run, state between runs, plan and snapshot reads). Section 6 proposes replacements that need no database.

## 2. What Pulse is

A status page ("System Pulse") per hub instance, published inside the hub's IIS site under a relative directory, that shows the HTTPS health of the applications of every enabled instance of the same machine and country. Pieces:

- the page (`index.html` expanded from a template, plus `web.config` and a logo asset), all stored as rows in `cfg.PulseResource` (3 rows: `PULSE_INDEX_HTML`, `PULSE_WEB_CONFIG`, `PULSE_LOGO`; text or binary with a stored `ContentSha256`);
- a collector: the engine itself, copied to `CollectorScriptPath` and started by a Windows scheduled task (`ScheduledTaskName`) every `CollectionIntervalMinutes` (1 minute in all 4 rows) with `-CollectOnly`;
- a status file (`StatusFileName`) written next to the page, which the page reads every `RefreshSeconds` (30) and treats as stale after `StaleAfterSeconds` (300);
- global website branding assets (favicons) written into the hub's website root (`cfg.WebsiteBrandingProfile`, `cfg.WebsiteBrandingAsset`, both global tables).

## 3. Objects

| Kind | Name | Role |
|---|---|---|
| Table | `cfg.PulseProfile` (4 rows, PK `HubInstanceCode`) | per hub: titles, `RelativeDirectory`, `PublicUrlTemplate`, `StatusFileName`, `CollectorScriptPath`, `ScheduledTaskName`, interval, refresh, `YellowFailureCount` (1), `RedFailureCount` (3), `StaleAfterSeconds`, `ScopePolicy`, `IsEnabled` |
| Table | `cfg.PulseHttpPolicy` (12 rows, PK `ApplicationCode`; 11 enabled, `ROOT` disabled) | per application: `UrlTemplate`, `HttpMethod`, healthy and responding status codes, redirects, timeout, `RequiredForOverallOverride`, order |
| Table | `cfg.PulseResource` (3 rows) | page template, web config template, logo |
| Table | `ops.PulseCheckState` (132 rows, PK hub + instance + check) | last result and failure counter per check; written by every run |
| Table | `ops.PulseRun` (10 rows) | one row per run: collector machine, times, overall status |
| Procedure | `cfg.ReviewPulseModel` | model review: hub registered, hub IIS identity present, resource hashes, HTTP policy applications exist, page template and logo present |
| Procedure | `cfg.GetPulseDeploymentPlan` | one hub row: server, host name, directories, public URL, task identity (the hub instance IIS identity) |
| Procedure | `cfg.GetPulseCheckPlan` | the checks to run: instances x enabled HTTP policies |
| Procedure | `cfg.GetPulseResourcePlan` | the enabled resources, fails when the profile is missing |
| Procedure | `ops.RecordPulseRun` | merges the run into `ops.PulseCheckState`, computes statuses and the overall result, writes `ops.PulseRun` |
| Procedure | `ops.GetPulseStatusSnapshot` | reads the state back for the page, marks rows stale |
| Action | `PULSE_STATUS` (`HEALTH`, preview and apply, no instance selection, 900 s timeout, hidden from the menu) | calls the engine; `FULL_DEPLOYMENT` step 75 |

[CONFIRMED] No view, function or trigger mentions Pulse, and no procedure outside this list reads these tables.

## 4. How the engine works

Parameters: the management SQL instance and database (to disappear), an optional hub code, `-Apply`, `-CollectOnly`.

**Preview and apply (run by the operator):**
1. If no hub is given, it picks the first enabled Pulse profile whose hub instance is on this machine, and stops with an error when there is none.
2. It runs the model review and stops on any error; then it reads the deployment plan (exactly one row), the website branding model and plan, the branding assets and the Pulse resources.
3. It expands the page template; any unresolved token is an error.
4. Preview prints the hub, URL, directory, collector path, task name, interval and the number of HTTPS endpoints, and writes nothing.
5. Apply backs up the existing page, config, logo and collector to `ConfigBackupRoot` under `Pulse\<timestamp>`, writes the branding assets (hash-verified), the page, the web config, the logo and the collector atomically, grants modify rights on the page directory and the collector directory to the task identity, registers the scheduled task with that identity and its password, and runs one collection.

**Collection (run by the scheduled task):** reads the check plan for this machine, performs one HTTPS check per row (only the HTTP check type is accepted), posts the result to `ops.RecordPulseRun`, reads the snapshot and writes the status file.

## 5. Where other machines or instances could matter

| Question | Finding |
|---|---|
| Which instances does a hub check? | [CONFIRMED] `cfg.GetPulseCheckPlan` takes the hub's `ServerCode` and `CountryCode` and selects enabled instances with the same `ServerCode` and the same `CountryCode`. Same server, same country only. |
| Does the profile say something different? | [CONFIRMED] `ScopePolicy` is `SAME_COUNTRY_ALL_ENABLED` in all 4 rows, which reads as "all enabled instances of the country", but the procedure also restricts to the hub's server. See the data below. [PENDING] below. |
| Where do page and files live? | [CONFIRMED] On the hub's server: directory = `ServicesRoot` of that server + host name + `RelativeDirectory`. |
| Does the state or snapshot cross machines? | [CONFIRMED] The state is keyed by hub; it contained only the hub's own instances. |
| Does the task need anything remote? | [CONFIRMED] Only the hub instance's IIS identity (user and password) of the hub's own machine. |
| Cross-machine references in the data? | [CONFIRMED] One: `cfg.Application` row `PULSE_STATUS` (display name "System Pulse") has `LinksHubInstanceCode` = `DEMOPT` and a links URL template with the host name placeholder; 17 `cfg.LinksProfileApplication` rows put this card on links pages of profiles such as `ADMIN_BR`, `COMM_ES`, `SANDBOX_MAIN`. So every machine's links pages point to the PT hub's Pulse page. |

**The four hubs** (counts of enabled instances; checked = same server and same country):

| Hub instance | Machine | Country | Checked | Same server, other country (not checked) | Same country on other machines (not checked) |
|---|---|---|---:|---:|---:|
| DEMOBR | BR_DEMO | BR | 21 | 0 | 1 |
| DEMOES | ES_DEMO | ES | 16 | 3 | 1 |
| DEMOPT | PT_DEMO | PT | 16 | 0 | 9 |
| SANDBOXMAIN | SANDBOX_HUB | US | 2 | 4 | 6 |

PRESALES and TENDERS have no Pulse profile: the engine would stop with "no Pulse hub registered" there.

## 6. What does not port as it is

1. **Recording each run in the central database.** `ops.RecordPulseRun` and `ops.PulseRun` go away with `_sisqualMANAGEMENT`. [PROPOSED] each run appends one line to the text log (time, hub, counts, overall status) and rewrites the status file; no database.
2. **State between runs.** The statuses depend on consecutive failures (yellow at 1, red at 3) and the time of the last success, kept in `ops.PulseCheckState`. The scheduled task starts a new process every minute, so memory is not enough. [CONFIRMED] the status file (a JSON document, schema version 1.0) already carries, for every check, the raw and display status, the consecutive failure count, the last checked time and the last success time. [PROPOSED] the collector reads the previous status file at start, continues the counters and writes the new one atomically. If the file is missing or unreadable the counters restart at zero and the log says so.
3. **Plan and snapshot reads at every run.** Both read the central database every minute. [PROPOSED] Apply writes the resolved check plan (instances, URLs, methods, status codes, timeouts, thresholds) next to the status file; the collector reads that plan and needs neither the catalog nor any database. A catalog edit takes effect when the operator applies again.
4. **The collector is the engine copied elsewhere.** The task action points to a script and a runtime. With whole-folder updates and no installed PowerShell 7, the action must reach the portable `pwsh.exe` or another runtime. See [PENDING] 2.
5. **Hard-coded names.** The model review message and the action text name `DEMOPT`; the new messages must use the hub code.
6. **Credentials.** The task identity and password are the hub instance's IIS identity: one `IIS_IDENTITY` credential entry (`credentialRef` of the hub instance). It is passed once to the scheduler at apply time and must never reach the log, the result or the status file.

## 7. What the catalog must carry for this engine

| Table | Class | Columns used | Note |
|---|---|---|---|
| `cfg_PulseProfile` | cut by the hub's machine | all except `ModifiedAt` | 1 row on BR_DEMO, ES_DEMO, PT_DEMO, SANDBOX_HUB; none on PRESALES, TENDERS |
| `cfg_PulseHttpPolicy` | global | all | 12 rows |
| `cfg_PulseResource` | global | all (text and BLOB, `ContentSha256`) | 3 rows; verify the hash on load |
| `cfg_WebsiteBrandingProfile`, `cfg_WebsiteBrandingAsset` | global | as used by the branding plan | favicons, hash-verified |
| `cfg_Application` | global | `ApplicationCode`, applicability flags used by the check plan | already carried |
| `dbo_ManagedServer`, `dbo_ManagedInstance` | cut | `ServicesRoot`, `ConfigBackupRoot`, `MachineName`; per instance `HostName`, `CountryCode`, `CustomerCode`, `CustomerName`, `IsEnabled` | of the hub's own machine only |
| Credential package | outside | `IIS_IDENTITY` of the hub instance | `credentialRef` |

Not carried (already excluded by the plan): `ops_PulseCheckState`, `ops_PulseRun`. No instance or hub of another machine is needed.

## 8. Recommendation

1. [PROPOSED] Close the Pulse item of the conversion plan 2.4 as "no" (the owner accepted the scope in section 9): a machine's Pulse does not need the hub or the instances of other machines. The catalog cut for `cfg_PulseProfile` stays as it is.
2. [PROPOSED] Port `PULSE_STATUS` with the three replacements of section 6 and keep the same checks, thresholds and page.
3. [PROPOSED] On a machine without a Pulse profile, the engine reports "not applicable" and does not fail, so `FULL_DEPLOYMENT` can run on PRESALES and TENDERS.
4. [PROPOSED] Treat the Pulse card on other machines' links pages as part of the links-page design (task 1c): the card needs the hub's public URL, not the Pulse engine.

## 9. Decisions

Owner answers of 2026-10-05 to the four points listed in PR #27 (each is traceable to the reply "1. Aceito, 2. Pode ser, 3. Pode ser, e como faria refresh?, 4. Ok"):

1. [DECIDED, "Aceito"] Keep today's scope (same server and same country). The profile value `SAME_COUNTRY_ALL_ENABLED` says something else, so [PROPOSED] the owner changes it to a name that says what it does (for example `SAME_SERVER_SAME_COUNTRY`) with a manual catalog edit and a seal; the converter keeps text byte for byte and does not rename it.
2. [DECIDED, "Pode ser"] The collector runs from the portable `pwsh.exe` at its current path. Apply re-registers the task, and preview shows a changed action path, so replacing the folder is followed by an Apply.
3. [DECIDED, "Pode ser"] The task keeps running as the hub instance's IIS identity in V1. The owner asked how a refresh would work: see 9a.
4. [DECIDED, "Ok"] A machine without a Pulse profile reports "not applicable" and does not fail.

### 9a. How a refresh works

There are three different refreshes; the second is the one the identity choice affects.

- **The page.** [CONFIRMED] The page re-reads the status file every `RefreshSeconds` (30) and shows a check as unknown once the file is older than `StaleAfterSeconds` (300). The collector writes it every minute. Nothing for the operator to do.
- **The task credentials.** [CONFIRMED] The scheduler keeps the identity's password when the task is registered and does not return it, so the engine cannot compare it with the credential package. [PROPOSED] After a new `IIS_IDENTITY` credential is imported for the hub, the operator runs `PULSE_STATUS` apply again: it re-registers the task with the current credential (idempotent). To notice a stale password without waiting for the page to go stale, preview reads the task and reports: registered or not, action path, user, last run time and last run result; a logon failure result, or no run for more than two intervals, is a finding ("task not running, credential may be stale").
- **The plan.** [PROPOSED] The collector uses the check plan written at apply time (section 6.3). After a catalog edit (new instance, new application, new policy) the operator runs apply again; preview stores and compares a hash of the plan, so a plan that no longer matches the catalog shows as "plan out of date" instead of being silent.

## 10. Test plan for the engine port

- Runner: model review and plan building from a synthetic catalog; page expansion and unresolved-token error; resource hash check; backup, atomic writes and restore; collector against a local test web server (healthy, degraded, failed, timeout, redirect, thresholds 1 and 3, stale file); state continuation from the previous status file; no secret in log, result or status file (marker password); scheduled task registration on the runner with a throw-away local user.
- [V] A real hub with the real IIS identity and applications; ACL grants on real directories; behaviour at 1-minute cadence over days.
