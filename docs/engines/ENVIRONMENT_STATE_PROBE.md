# Engine port specification: ENVIRONMENT_STATE_PROBE

**Status:** [PROPOSED] specification for review (task 3, wave 7). No product code.
**Date:** 2026-10-05
**Sources (read only):** `ops.Engine` row `ENVIRONMENT_STATE_PROBE` of `database/sync/ManagementSync.sql` of `atsisqual/SISQUALManagementConsole` (file `Invoke-EnvironmentStateProbe.ps1`, version `1.0.0`, Windows PowerShell 5.1, requires administrator, stored `ScriptSha256` `67D5DC60...`; reference head `9756ba956842884fabcf25b82c4fbf1d11cf56bd`); the action `ENVIRONMENT_STATE_PROBE`. Script text is not copied and no secret value appears here.
Tags: [CONFIRMED] read in the source; [PROPOSED] recommendation; [PENDING] needs a decision; [V] needs a real server.

## 1. Purpose

Measure how healthy each managed environment is right now: the database, the IIS site, the applications over HTTPS and the Web Access root, and combine them into one state. [CONFIRMED] Action: group `HEALTH`, preview and apply, all enabled instances (batch), shown in the menu. Preview probes and prints; apply also stores the state for the console.

## 2. Inputs

| Source (catalog) | Content |
|---|---|
| `dbo_ManagedInstance`, `dbo_ManagedServer` | `InstanceCode`, `HostName`, `DatabaseName`, `SqlInstanceName`, `MachineName` (instances of this machine, enabled) |
| `cfg_Application` | the applications with `PublishInLinks` = 1 and a non-empty `IisPath` (12 published; the root path is skipped), in `LinksSortOrder` |

Parameters: instance, apply.

## 3. Steps

For each instance:
1. **Database:** open a connection to the instance database with a 5 s timeout: `ONLINE` or `OFFLINE`.
2. **IIS:** the site named like the host: started is `ONLINE`, stopped `OFFLINE`, absent or unreadable `UNKNOWN`.
3. **Applications:** request each application URL on the public host name; follow up to 10 redirects by hand (8 s per request); `ONLINE` if the final address is a login page of the identity server, the Web Access page, a login page, or on the same host; otherwise `OFFLINE`. Combine: all online is `ONLINE`, none `OFFLINE`, else `PARTIALLY_ONLINE`, none checked `UNKNOWN`.
4. **Web Access:** the same request on the root.
5. **Overall:** `OFFLINE` if the database or IIS is offline; `ONLINE` if the database, IIS and applications are online; `UNKNOWN` if both database and IIS are unknown; otherwise `PARTIALLY_ONLINE`.
6. Apply: write the state of the instance (overall, database, IIS, applications, Web Access, maintenance flag, no error) into the console's state table.

## 4. Side effects

Probing only: connections and HTTP requests. [CONFIRMED] Apply writes one row per instance in the central state table; the port has no such table.

## 5. External dependencies

The local SQL Server, IIS (site state), DNS and the network path to the public host name, the applications' login redirects.

## 6. Preview and apply

[PROPOSED] A single probe that returns the result. Persistence is a separate decision (13.1). Where apply remains, it records to the log and to a status file, not a database.

## 7. Idempotency

Read-only apart from persistence; repeating it gives the current state.

## 8. Failures

A probe that cannot run gives `UNKNOWN` or `OFFLINE` for that part and never stops the others. [CONFIRMED] With no instance code the old query matches nothing; it works only when run per instance by the batch action. The port takes all enabled instances of the machine.

## 9. Backup and restore

Not applicable.

## 10. Secret risks

None: requests are unauthenticated and results hold states and URLs. [CONFIRMED, defect] The old script turns off TLS certificate validation for the whole process. [PROPOSED] Validate by default, with a catalog setting for an exception.

## 11. What does not port as it is

- [CONFIRMED, defect] The application check treats **any** response on the same host as online: it follows redirects and judges the final address, never the status code, so a 404 or 500 page counts as `ONLINE`. [PROPOSED] Use the same classification as the Pulse engine (healthy 200 to 399; 401 and 403 responding) from one shared module.
- [CONFIRMED, defect] The Web Access state is measured but is not part of the overall state.
- The IIS state uses the WebAdministration provider, which does not work under PowerShell 7 (ADR-0006): use `Microsoft.Web.Administration`.
- Sequential checks have no overall limit: 12 addresses, up to 10 redirects, 8 s each, is up to 16 minutes for one instance in the worst case. [PROPOSED] Bounded parallelism and an overall deadline.
- The console state table and its procedure go.

## 12. Test plan

- Runner: a local HTTP and HTTPS test server (redirect chains, 200, 401, 403, 404, 500, timeout, refused, invalid certificate); SQL Server LocalDB online and offline; IIS site started, stopped and absent through MWA; the overall-state matrix; parallelism and the deadline; the shared classifier against the Pulse cases; the instance filter.
- [V] Real servers: probing the public host from the server itself (name resolution, hairpin, firewall), timing at 21 instances.

## 13. Open questions

1. [PENDING] Persist the state? Recommendation: no database; keep the latest probe in a status file per instance in the log folder, plus one log line per probe, and let the screen run a probe on demand.
2. [PENDING] Probe through the public name (what a user sees, but exposed to hairpin and DNS issues) or through loopback with the host header. Recommendation: public name by default, loopback as an option.
3. [PENDING] One shared HTTP check module for this engine and `PULSE_STATUS`. Recommendation: yes.

## Host contract

- Engine class: `OBSERVATIONAL`.
- Credential references: none.
