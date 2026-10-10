# WINDOWS_SERVICES port brief

**Status:** [PROPOSED]
**Task:** T4 / M3.5
**Date:** 2026-10-10

This brief defines the evidence and safety gates for the `WINDOWS_SERVICES` port. It is documentation only.

## 1. Sources and evidence boundary

[CONFIRMED] Checked now against `main`:

- `docs/engines/WINDOWS_SERVICES.md` documents source-era `Invoke-WindowsServiceReconciliation.ps1`, `cfg.GetWindowsServiceDeploymentPlan` and `cfg.ReviewWindowsServiceModel`.
- `tests/Fixtures/carried-schema.json` confirms `cfg.WindowsServiceDefinition` and the carried managed-server/instance model.
- The current specification lists six model-review codes: `DUPLICATE_SERVICE_NAME`, `SERVICE_NAME_TOO_LONG`, `SERVICE_ACCOUNT_USERNAME_MISSING`, `SERVICE_ACCOUNT_PASSWORD_MISSING`, `SERVICE_IDENTITY_PASSWORD_CONFLICT`, `WINDOWS_SERVICE_DEFINITION_MISSING`.
- PR #69 rule 6 explicitly names service names and shared accounts/passwords as machine-wide comparisons: a run for one selected instance must compare against every enabled instance on the machine. Rule 7 governs executable paths and other catalog-derived local paths.

[NOT VERIFIED] The old service engine and procedures were not re-extracted or executed for this brief. Win32/ADSI/logon-right behavior under PowerShell 7 remains implementation evidence to produce.

## 2. Purpose and class

[CONFIRMED] `WINDOWS_SERVICES` is `MUTATING`. It creates or corrects catalog-defined Windows services, runs them under the instance IIS identity, and starts/verifies them.

[CONFIRMED] The action supports preview/apply, all enabled instances or one selected instance, and is step 60 of `FULL_DEPLOYMENT`.

[CONFIRMED from the existing specification] The reference catalog currently has one service definition (`WFM_MOBILE_APP`), yielding one service per enabled instance. Code must still iterate enabled definitions rather than hard-code a single service.

## 3. Catalog inputs

| Source | Required model |
|---|---|
| `cfg.WindowsServiceDefinition` | service code; service/display/description templates; executable and argument templates; startup type; delayed-start/start/restart flags; account source; account-creation/password policy; required/enabled flags |
| `dbo.ManagedInstance` | instance identity, host/root data and `IisIdentityUserName` |
| `dbo.ManagedServer` | local machine/root data and backup root |

[CONFIRMED] The carried schema contains `cfg.WindowsServiceDefinition`; implementation may use only fields present in `tests/Fixtures/carried-schema.json`.

## 4. Credentials and shared-account invariant

[CONFIRMED] Credentials are `IIS_IDENTITY.<InstanceCode>` and the account source for the current definition is `IIS_IDENTITY`.

[DECIDED 2026-10-09] `IIS_IDENTITY.*` is an allowed per-instance family and expands only to enabled instances of the verified catalog.

[PROPOSED] Before any mutation, group **all enabled instances of the machine** by Windows identity name using case-insensitive comparison. For a selected instance whose account is shared:

- every enabled peer using that account participates in the password-consistency check;
- peer credentials come from the request, never from the catalog;
- missing peer credentials are an `ERROR`, not a skipped comparison;
- differing credential hashes produce `SERVICE_IDENTITY_PASSWORD_CONFLICT` on the selected participant.

This prevents a single-instance run from resetting a shared account to a password that breaks IIS pools or another service.

## 5. Name and executable safety

[PROPOSED] Expanded service names are compared case-insensitively across every enabled instance and definition. `DUPLICATE_SERVICE_NAME` is reported on every selected holder of a duplicated name. Name-length validation runs before any SCM call.

[PROPOSED] `ExecutablePathTemplate` and any catalog-derived working/local path must be local and contained under the approved instance root after resolving junctions/symlinks. UNC/device paths and lexical/root escapes are rejected before probing. Access denied is an item error.

## 6. Old behavior, step by step

The existing specification records this flow:

1. Require administrator rights and resolve local machine/selection.
2. Run the six-code Windows-service model review and stop before changes on review errors.
3. Build the Cartesian plan of selected enabled instances × enabled service definitions.
4. Expand service name, executable, arguments and account; verify executable and credential readiness.
5. Compare live service binary path, account, display name, startup mode, delayed-start flag and running state.
6. Preview with documented states such as `MATCHED`, `WOULD_UPDATE` and `NOT_READY`; write nothing.
7. APPLY ensures/creates the local account when policy allows, sets the credential, grants log-on-as-a-service, stops an existing service only when needed, creates/changes service configuration, writes delayed-start/description values, starts when policy requires, and waits for the expected state.
8. Re-read and verify the service after mutation.
9. Emit one structured row per service; fail the overall run if a required row is not ready or errors.

## 7. Deliberate portable-system deviation

[CONFIRMED, source-era defect] The existing specification records that the old APPLY repeated mutations for `MATCHED` rows, including password reset and restart.

[PROPOSED] V1 portable semantics are idempotent:

- skip a fully `MATCHED` row;
- do not restart a matched service;
- restart a changed service only when its policy/change requires restart;
- never reset a shared account merely to prove the password; set it only for a new account or an approved password-change operation.

This is an intentional behavior correction and must be explicit in review evidence, not hidden as an implementation optimization.

## 8. Side effects

[CONFIRMED] APPLY can create/update local accounts, change an existing account password, grant log-on-as-a-service, create/change/stop/start services, and write service registry values. It can cause temporary connector downtime.

[PROPOSED] Do not mutate an account or service for an optional `NOT_READY` row. Required/optional behavior follows catalog policy and source evidence.

## 9. Backup and restore

[CONFIRMED] The old engine made no service-configuration backup.

[PROPOSED] Before the first service mutation, record the readable service state: binary path, arguments, account name, display name, description, startup type, delayed-start flag and prior running state. Restore re-applies those readable fields. Password rollback is not reconstructible from SCM and therefore requires the credential package; the run manifest must say so explicitly.

Account-creation rollback must not delete a pre-existing account. A newly created account may be removed only if the restore design can prove ownership and the owner approves that behavior.

## 10. Failure and result semantics

[CONFIRMED] Win32 create/change return failures, start timeout and post-apply mismatch are errors. Missing executable/user/password fail required rows. The source specification records a 60-second start wait.

[PROPOSED] One result row per instance/service contains no password and no credential-derived hash. It may report service name, account name, desired startup/running state and non-secret failure code.

The exact six review-code severities must be taken from original evidence. This brief preserves names but does not invent severity where the specification does not state it.

## 11. Required tests

The code PR must cover:

- all six model-review codes with positive and negative fixtures;
- duplicate name against an enabled **unselected** instance;
- shared account with same password, conflicting password and missing peer credential;
- Windows account-name case insensitivity and exact catalog-code comparison;
- executable missing, access denied and executable path escaping through `..`, UNC/device syntax and reparse point;
- missing/optional service readiness;
- create service, each live-property difference, update and matched no-op;
- account creation allowed/disallowed;
- existing-account password-change safety;
- log-on-as-a-service grant under PowerShell 7;
- delayed-start and description registry behavior;
- restart-only-when-changed and no restart on second apply;
- start success and timeout;
- post-apply verification mismatch;
- preview/apply fingerprint drift;
- readable-state backup and restore;
- marker password absent from every artifact.

[V] Pilot with the real connector and shared IIS identity, including observed impact of an intentional service restart.

## 12. Open questions

1. [PENDING] Clean-server ordering: IIS step 50 can need the identity before WINDOWS_SERVICES step 60 creates it. Account provisioning must be resolved before code is production-ready.
2. [PENDING] Confirm whether one machine-level account/password is intentionally shared across its instances; current review semantics assume consistency.
3. [PENDING] Exact changes that require service restart.
4. [PENDING] Final PowerShell 7 implementation for log-on-as-a-service and local-account operations.
5. [PENDING] Restore policy for an account created by this engine.

## 13. Entry gate for the code PR

The code PR may start when:

- six source review predicates and severities are attached to tests;
- all used columns are confirmed in `carried-schema.json`;
- shared-account and duplicate-name checks are specified across every enabled instance;
- account-provisioning order with IIS is decided;
- service-state backup/restore scope is explicit;
- PowerShell 7 runner probes cover SCM, local account and logon-right operations;
- no test or result requires exposing a password.
