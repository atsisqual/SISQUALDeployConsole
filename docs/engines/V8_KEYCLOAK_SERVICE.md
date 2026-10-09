# Engine port specification: V8_KEYCLOAK_SERVICE

**Status:** [PROPOSED] specification for review (task 3, wave 4). No product code.
**Date:** 2026-10-05
**Sources (read only):** `ops.Engine` row `V8_KEYCLOAK_SERVICE` of `database/sync/ManagementSync.sql` of `atsisqual/SISQUALManagementConsole` (file `V8_KEYCLOAK_SERVICE.ps1`, version `v5`, Windows PowerShell 5.1, requires administrator, stored `ScriptSha256` `28F8278A...`; reference head `9756ba956842884fabcf25b82c4fbf1d11cf56bd`); the action `V8_KEYCLOAK_SERVICE`; step 65 of `FULL_DEPLOYMENT`. Script text is not copied and no secret value appears here.
Tags: [CONFIRMED] read in the source; [PROPOSED] recommendation; [PENDING] needs a decision; [V] needs a real server.

## 1. Purpose

Install and start one Windows service per instance that runs the V8 Keycloak server under NSSM, and check that it is serving. [CONFIRMED] Action: group `INFRASTRUCTURE`, preview and apply, all enabled instances or one, step 65 of `FULL_DEPLOYMENT` (stop on error). All 76 enabled instances have Keycloak ports (8180 and neighbours, no duplicate on any machine).

## 2. Inputs

| Source | Content |
|---|---|
| `dbo_ManagedInstance` | `InstanceCode`, `HostName`, `KeycloakHttpPort`, `KeycloakHttpsPort`, `KeycloakManagementPort` |
| `dbo_ManagedServer` | `ServicesRoot` (see 11) |
| credential package | `IIS_IDENTITY` of the instance (`credentialRef`): the service account name and password |
| prerequisites | the NSSM executable, JDK, the Keycloak files at the instance (put there by another step) |

Parameters: instance (optional), apply; rule, group and backup root are accepted and ignored.

## 3. Steps

1. For each instance with Keycloak ports: if the Keycloak start script is not deployed under the instance's V8 folder, `SKIPPED` ("not physically deployed yet").
2. Preview: only whether the service `SISQUALWFM_Keycloak_<host>` exists: `WOULD_CREATE` or `WOULD_UPDATE`, with the three ports. **No difference is computed.**
3. Apply: read the instance's account; install the service with NSSM if absent; set the logon account; set display name, working directory, parameters (`start --verbose --optimized`), output and error log file, restart on exit, throttle 1.5 s, restart delay 60 s; delayed automatic start; a failure-actions registry flag; start the service.
4. Wait up to 90 s for `Running`; wait up to 90 s for each of the three ports to be in use; request the OpenID configuration of the master realm over HTTPS.
5. Report per instance: `SKIPPED`, `WOULD_CREATE`, `WOULD_UPDATE`, `OK` (with the state and the endpoint check) or `ERROR`; fail at the end if any error.

## 4. Side effects

Creates or changes a service, writes NSSM parameters, starts the service, writes a growing log file in the Keycloak folder, briefly binds each port to test it.

## 5. External dependencies

NSSM, JDK, the Keycloak files, the service manager, three local ports, the HTTPS endpoint of the host, and (for Keycloak to work) the `sisqualKeycloak` database and the configuration written by `CONFIG_REPAIR`.

## 6. Preview and apply

[PROPOSED] A real preview: desired against actual for the account name, NSSM settings, start mode and state, per instance. Apply consumes the fingerprint of that preview.

## 7. Idempotency

[CONFIRMED, defect] Apply rewrites every NSSM setting and starts the service on every run, without comparing; a running service is not restarted, so a changed parameter does not take effect. [PROPOSED] Compare, change only what differs, and restart only if a setting that needs it changed.

## 8. Failures

Not deployed: `SKIPPED`, not an error. Service not running in 90 s, a port not listening in 90 s, or a failed NSSM or service call: `ERROR` for that instance, the others continue. The endpoint check reports reachable or not and is not an error by itself [CONFIRMED]; [PROPOSED] make it a warning with the reason.

## 9. Backup and restore

[PROPOSED] Record the previous NSSM and service settings (not the password) in a run manifest and restore them on request. Log rotation for the service log is a separate point (13.4).

## 10. Secret risks

- [CONFIRMED] The account password is passed to NSSM **on a command line**, which other local users and logs of process creation can see. [PROPOSED] Install with NSSM without the account, then set the account and password through the service-manager change call, which does not use a command line; never log or return the password.
- [CONFIRMED] The check disables TLS certificate validation for the whole process during the OpenID request. [PROPOSED] Validate by default; an exception is an explicit catalog setting scoped to that request.
- The instance code is concatenated into SQL in the old script: the port has no SQL and takes ids only from the catalog allowlist. Marker password test over every artifact.

## 11. What does not port as it is

The fixed Keycloak folder (`C:\SISQUALWFM\WFM.Services\<host>\V8\sisqualKeycloak`) and the fixed NSSM path become the machine's `ServicesRoot` and the prerequisite location. The credential read from the database (a procedure returning the secret) becomes the package. The SQL context goes.

## 12. Test plan

- Runner: a fake NSSM and a dummy long-running executable standing in for Keycloak; not deployed, create, update, no change on a second apply, parameter change causing a restart, each timeout, ports listening and not, a local HTTPS test server for the endpoint check (valid, invalid certificate, unreachable), the account set without a command line (checked through process creation logging in the test), marker password in every artifact, the instance filter.
- [V] A real Keycloak on a pilot server: start time, memory, log growth, the endpoint check against the real certificate.

## 13. Open questions

1. [PENDING] Who puts the Keycloak files on the instance? No engine does (it is a clone or update operation, outside the 19 engines; see the analysis of copy operations). Recommendation: decide with the software update path.
2. [PENDING] `FULL_DEPLOYMENT` configures Keycloak (`CONFIG_REPAIR`, step 20) before the service exists; confirm that the files exist at step 20 on a clean server.
3. [PENDING] Certificate validation exception for self-signed certificates. Recommendation: validate by default.
4. [PENDING] Service log rotation (the log has no limit today). Recommendation: size-based rotation or a separate log folder with retention.

## Host contract

- Engine class: `MUTATING`.
- Credential references: `IIS_IDENTITY.*`.
