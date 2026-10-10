# V8_KEYCLOAK_SERVICE port brief

**Status:** [PROPOSED]
**Task:** T6 / M3.5
**Date:** 2026-10-10

This brief defines the implementation gate for the `V8_KEYCLOAK_SERVICE` port. It is documentation only.

## 1. Sources and evidence boundary

[CONFIRMED] Checked now against `main`:

- `docs/engines/V8_KEYCLOAK_SERVICE.md` documents source-era `V8_KEYCLOAK_SERVICE.ps1`, action `V8_KEYCLOAK_SERVICE` and step 65 of `FULL_DEPLOYMENT`.
- `tests/Fixtures/carried-schema.json` confirms the per-instance Keycloak port fields and the managed-server service root used by the specification.
- The current specification identifies two unsafe source-era behaviors that must not port unchanged: passing the service-account password to NSSM on a command line, and disabling TLS certificate validation process-wide during the OpenID health request.
- PR #69 rules 6 and 7 apply to machine-wide service names/ports and to all catalog-derived local paths.

[NOT VERIFIED] The old Keycloak service script was not re-extracted or run for this brief. Real Keycloak startup, NSSM behavior, certificate topology, memory/log growth and production health timing remain `[V]` evidence.

## 2. Purpose and class

[CONFIRMED] `V8_KEYCLOAK_SERVICE` is `MUTATING`. It manages one NSSM-backed Keycloak Windows service for each enabled instance that has Keycloak deployed, then verifies the service and its endpoints.

[CONFIRMED] The action supports all enabled instances or one selected instance and is step 65 of `FULL_DEPLOYMENT`.

[CONFIRMED from the existing specification] The reference snapshot has Keycloak HTTP, HTTPS and management ports for all enabled instances and no duplicate port on a machine. That is evidence about the snapshot, not a runtime assumption: the portable engine must validate machine-wide uniqueness from the catalog it receives.

## 3. Catalog and prerequisite inputs

| Source | Use |
|---|---|
| `dbo.ManagedInstance` | `InstanceCode`, `HostName`, `KeycloakHttpPort`, `KeycloakHttpsPort`, `KeycloakManagementPort`, enabled state and IIS-identity data needed by the service account |
| `dbo.ManagedServer` | `ServicesRoot` and local-machine identity/root data |
| credential package | `IIS_IDENTITY.<InstanceCode>` for the service account/password |
| prerequisite state | verified NSSM and exact JDK 23 supplied by the prerequisite engine |
| instance file tree | the Keycloak start script/files under the approved V8 instance root |

[PROPOSED] The engine consumes prerequisite state; it does not install JDK/NSSM and does not copy the Keycloak application files. If the application files are not physically deployed, preserve the documented `SKIPPED` behavior unless the owner changes the clean-server sequence.

## 4. Credentials

[CONFIRMED] Credentials are `IIS_IDENTITY.<InstanceCode>`.

[DECIDED 2026-10-09] `IIS_IDENTITY.*` may be declared as an instance-family reference and expands only to enabled instances of the verified catalog.

[PROPOSED] The password must never be passed to `nssm.exe` or any other process on a command line. Install/configure non-secret NSSM settings first, then set the Windows service logon account/password through the service-manager API. The marker-secret test must inspect result/log text and process-creation command lines.

## 5. Machine-wide names and ports

[PROPOSED] Before planning a selected instance, evaluate every enabled instance on the machine:

- generated Keycloak service names must be unique, compared case-insensitively;
- HTTP, HTTPS and management ports must not collide with any Keycloak port of another enabled instance, including an unselected instance;
- report a conflict on the selected participant rather than silently excluding the unselected peer.

A single-instance `FULL_DEPLOYMENT` call therefore cannot create a service whose name or port conflicts with another enabled instance.

## 6. Path containment and deployment eligibility

[PROPOSED] Resolve the Keycloak application/start-script path from `ServicesRoot`, host/instance data and approved fixed relative layout. Before any probe or process start:

- reject UNC/device and other non-local paths;
- require lexical containment below the approved instance V8 root;
- resolve junctions/symbolic links and require real-path containment;
- report access denied as an item error rather than falling through to an external process.

If the approved Keycloak start script is simply absent, the documented source behavior is `SKIPPED` / not physically deployed. A path escape, unreadable target or ambiguous deployment is an error, not `SKIPPED`.

## 7. Desired-state preview

[CONFIRMED, source-era defect] The old preview checked essentially only whether the service existed and did not calculate configuration drift.

[PROPOSED] Preview is a real desired-versus-actual comparison and performs no managed write. Compare at least:

- service existence/name/display name;
- service account name (never password value);
- NSSM application executable and working directory;
- Keycloak arguments (`start --verbose --optimized` as recorded by the existing specification);
- stdout/stderr log destinations;
- restart/recovery/throttle/delay settings;
- delayed automatic start;
- failure-action policy;
- current service state.

Return deterministic `MATCHED`, `WOULD_CREATE`, `WOULD_UPDATE`, `SKIPPED` or blocking/error states with a preview fingerprint.

## 8. Apply and idempotency

[CONFIRMED, source-era defect] The old APPLY rewrote NSSM settings on every run and could leave changed parameters ineffective because a running service was not restarted.

[PROPOSED] APPLY consumes the confirmed preview fingerprint, revalidates catalog/live state, changes only differing settings, and restarts only when a changed setting requires a restart. A second APPLY after convergence changes nothing and does not restart the service.

After mutation, re-read the Windows service/NSSM state and fail the item if it does not match the previewed target.

## 9. Health verification and TLS

[CONFIRMED] The existing specification records waits of up to 90 seconds for the service state and for each of the three ports, followed by an OpenID configuration request for the master realm over HTTPS.

[PROPOSED] Health verification is staged:

1. expected Windows service state;
2. HTTP/HTTPS/management ports listening as expected;
3. scoped HTTPS OpenID request.

TLS certificate validation is enabled by default and must never be disabled process-wide. There is no confirmed carried-schema field in this brief that authorizes a TLS-validation exception. Therefore V1 has **no exception** unless an explicit owner-approved policy/schema is added; do not invent a flag in engine code.

[PENDING] The existing specification says endpoint failure was not blocking and recommends a warning. The owner/reviewer must confirm final severity before implementation.

## 10. Side effects and service logs

[CONFIRMED] APPLY creates/changes/starts a Windows service, writes NSSM settings and causes Keycloak to write service output/error logs.

[PROPOSED] Log paths stay under the approved instance/log root and obey containment. The engine does not dump Keycloak output into its own result. Only bounded diagnostics are reported.

[PENDING] Service-log rotation/retention remains unresolved. Do not claim unlimited source-era logging is an accepted portable policy.

## 11. Backup and restore

[PROPOSED] Before mutation, record all readable service/NSSM settings and prior running state in the run backup manifest. Do not record passwords. Restore reapplies those readable settings and uses the credential package again if restoring the service account requires a password.

If the service did not exist before the run, rollback/removal of a newly created service must be explicit and must prove the service is the one created by this operation before deleting it.

## 12. Dependencies and ordering

[CONFIRMED] This engine depends on:

- `V8_KEYCLOAK_PREREQUISITES` having established NSSM/JDK;
- Keycloak application files already existing on the instance;
- `CONFIG_REPAIR` having produced the Keycloak configuration, including the `sisqualKeycloak` database URL rule.

[PENDING] The current `FULL_DEPLOYMENT` order configures Keycloak before this service exists, and no engine in the 19-engine set owns copying the application files. The clean-server software-update/copy path must be settled before this engine can be considered deployable from an empty server.

## 13. Required tests

Runner coverage must include:

- no Keycloak files -> documented `SKIPPED` with no service mutation;
- path escape/access-denied cases are errors, not skipped;
- create service and full desired-state diff;
- each non-secret NSSM setting differing individually;
- account name difference with password set through service API, not command line;
- marker password absent from artifacts and captured process command lines;
- duplicate service name against enabled unselected instance;
- port collision against enabled unselected instance, including cross-kind collision (one instance HTTPS versus another's management port);
- parameter change requiring restart and matched no-restart second apply;
- service-state timeout and each port timeout;
- valid local HTTPS OpenID endpoint;
- invalid certificate proves validation stays enabled;
- unreachable/invalid OpenID response with final approved warning/error semantics;
- no process-global certificate-validation override;
- preview is no-write and deterministic; fingerprint drift blocks APPLY;
- backup/restore of readable NSSM/service settings;
- log-path containment.

[V] Real Keycloak pilot: actual startup time, real certificate, all three ports, memory behavior, recovery settings and log growth/rotation decision.

## 14. Open questions

1. [PENDING] Which software-update/copy operation owns placing Keycloak files on a clean instance, and how `FULL_DEPLOYMENT` gates on it.
2. [PENDING] Final severity of a failed HTTPS/OpenID health check after the service and ports are healthy.
3. [PENDING] Whether any TLS-validation exception is needed for approved self-signed deployments; none exists until explicitly modelled and approved.
4. [PENDING] Service log rotation/retention policy.
5. [PENDING] Exact set of service/NSSM changes that require restart versus live update.
6. [PENDING] Restore semantics for a service newly created by the operation.

## 15. Entry gate for the code PR

The code PR may start when:

- every used port/root/identity field is confirmed in `carried-schema.json`;
- service-name and all-three-port uniqueness are specified machine-wide;
- the password-setting path is proven not to expose the password on a process command line;
- the Keycloak-file provisioning dependency is explicit in the orchestration plan;
- final HTTPS health severity/TLS policy is decided or conservatively blocks exceptions;
- backup/restore and restart-required fields are enumerated;
- runner fixtures cover create, drift, health, idempotency, containment and cross-instance conflicts.
