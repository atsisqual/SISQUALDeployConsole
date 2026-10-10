# IIS_RECONCILE port brief

**Status:** [PROPOSED]
**Task:** T3 / M3.4
**Date:** 2026-10-10

This brief is the implementation gate for the `IIS_RECONCILE` port. It does not reopen ADR-0006 and it does not make the pending real-server conditions disappear.

## 1. Sources and evidence boundary

[CONFIRMED] Checked now against `main`:

- `docs/engines/IIS_RECONCILE.md` describes the source-era `Invoke-IISReconciliation.ps1`, the four IIS plan/review procedures and the 32-operation equivalence map.
- `docs/architecture/ADR-0006-iis-integration-via-microsoft-web-administration.md` is accepted with conditions: PowerShell 7 uses `Microsoft.Web.Administration` directly; WebAdministration cmdlets and the `IIS:\` provider are not the V1 write path.
- `docs/phase1/iis-reconcile-mwa-equivalence.md` is the operation-level MWA evidence referenced by the specification.
- `tests/Fixtures/carried-schema.json` confirms carried IIS model tables including `cfg.IisServerPolicy`, `cfg.IisApplicationDefinition`, `cfg.IisBindingDefinition`, `cfg.IisDirectoryDefinition`, `cfg.IisPrerequisiteDefinition`, the auto-start definitions and the managed server/instance data.
- PR #69 rules 6 and 7 remain applicable: cross-instance uniqueness uses every enabled instance on the machine; catalog-derived paths are contained after resolving reparse points.

[NOT VERIFIED] This brief did not run IIS, re-extract the 91k-character legacy engine, or satisfy ADR-0006 conditions 2 and 3 on a real topology. Those remain `[V]` gates.

## 2. Purpose and class

[CONFIRMED] `IIS_RECONCILE` is `MUTATING`. It reconciles prerequisites, directories/ACLs, application pools, one site per enabled instance, IIS applications, bindings/certificates, auto-start settings, and final start/verification.

[CONFIRMED] Preview is the default; APPLY changes IIS only from the confirmed preview fingerprint. The action can target all enabled instances or one selected instance and is step 50 of `FULL_DEPLOYMENT`.

## 3. Catalog model

[CONFIRMED] The port consumes policy/model rows rather than embedded IIS configuration text. Main table families are:

| Catalog source | Role |
|---|---|
| `cfg.IisServerPolicy` | machine policy: reconcile mode, deletion policy, pool identity template, certificate/store policy, logging and start policy |
| `cfg.IisApplicationDefinition` | application/root/pool/runtime/pipeline/authentication/preload definitions |
| `cfg.IisBindingDefinition` | HTTP/HTTPS/net.tcp binding definitions and SSL flags |
| `cfg.IisDirectoryDefinition` | local path creation and ACL requirements |
| `cfg.IisPrerequisiteDefinition` | Windows features and IIS modules |
| `cfg.IisServiceAutoStartProviderDefinition` | service auto-start provider model |
| `cfg.IisApplicationAutoStartDefinition` | application auto-start model |
| `dbo.ManagedServer`, `dbo.ManagedInstance` | machine/instance roots, host names, ports, identity user names and template inputs |

[CONFIRMED from the existing specification] Snapshot counts are policy 4 machine rows, 30 application definitions, three binding definitions, 21 directory definitions, eight prerequisites and one row in each auto-start definition family. These are evidence counts, not runtime constants.

## 4. Credentials

[CONFIRMED] Pool identity credentials are `IIS_IDENTITY.<InstanceCode>`.

[DECIDED 2026-10-09] `IIS_IDENTITY.*` is one of the three allowed instance-family reference forms. The host admits a concrete member only when the suffix is an enabled instance of the verified catalog.

[PROPOSED] A single-instance reconciliation must still receive the credentials required to prove machine-wide account invariants against enabled unselected instances. Missing required peer credentials are an error, not a reason to skip the check.

Passwords never appear in command lines, MWA diagnostic dumps, plan rows, result details, logs or backup metadata. Marker-secret coverage spans every artifact.

## 5. Ordered reconciliation phases

[CONFIRMED] Keep the source-era order recorded in the specification:

1. prerequisites;
2. service auto-start providers;
3. server/site policy;
4. local pool identities;
5. IIS configuration backup;
6. directories and ACLs;
7. application pools;
8. sites;
9. applications/virtual directories;
10. application auto-start;
11. bindings and certificates;
12. start and verify.

[DECIDED] IIS reads/writes in these phases use MWA. `netsh.exe` remains for http.sys certificate registration where required; `appcmd.exe` remains an allowed backup mechanism pending the backup decision. External changes require a fresh `ServerManager` before subsequent reads.

## 6. ADR-0006 gates

ADR-0006 has four conditions. The code PR must not describe them as already closed:

1. [CONFIRMED] The equivalence matrix exists and is the review basis for every legacy IIS operation.
2. [V] Run the write path on a sandbox with real topology: hundreds of pools, existing drift and locked sections.
3. [V] Test real pool identities, SNI, central certificate-store bindings, and handler/module sections.
4. [DECIDED] Commit in batches. The certificate store name is policy data (the policies use `WebHosting`) and is compared case-insensitively; V1 never deletes unmanaged IIS objects.

Entry to production acceptance requires conditions 2 and 3, even if runner CI is green.

## 7. Cross-instance and path safety

[PROPOSED] Uniqueness checks for pool names, site names, binding endpoints/ports, service names, identity/account constraints or other machine-global IIS identifiers compare the selected instance with **every enabled instance on the machine**. Report the problem on each selected participant. A single-instance `FULL_DEPLOYMENT` call must not miss a conflict with an unselected instance.

[PROPOSED] All catalog-derived physical/log paths are rejected before probe/write if non-local, lexically outside the approved root, or resolved through a junction/symlink outside it. Windows account/service names compare ignoring case; catalog codes compare exactly.

## 8. Side effects

[CONFIRMED] APPLY may create/change IIS pools, sites, applications, virtual directories, bindings, per-location settings, auto-start providers, local directories/ACLs and permitted prerequisites; register certificates in http.sys; stop/start/recycle pools/services as required; and create the IIS configuration backup.

[DECIDED] V1 does not delete unmanaged IIS objects even though a model field exists for deletion policy.

[PROPOSED] A failure in one selected instance stops that instance's later phases, allows independent instances to continue where safe, and makes the overall run fail. No later phase may execute for an instance whose prerequisite phase failed.

## 9. Backup and restore

[CONFIRMED] The source behavior takes an IIS configuration backup before the first mutation.

[PENDING] The final V1 backup mechanism is still `appcmd` backup versus direct configuration-file copy. Whichever is chosen must record backup identity/scope and be restore-tested. A whole-IIS restore is broader than a per-instance rollback and that blast radius must be explicit in the result/runbook.

[PROPOSED] APPLY refuses to mutate until the required backup succeeds. The backup is retained on any subsequent failure.

## 10. Original codes and failure semantics

[CONFIRMED from the existing specification] The IIS model review has nine issue codes and the extended-application review ten. Examples already recorded include `SERVER_POLICY_MISSING`, `IIS_IDENTITY_PASSWORD_PENDING` and `AUTO_START_POOL_NOT_ALWAYS_RUNNING`.

[PENDING] The code PR must carry the complete original list, exact predicates and severities from the approved procedure evidence. Names are not predicates.

[PROPOSED] Locked/inherited configuration that cannot be corrected is never silently swallowed. The exact severity of each source case follows source/owner evidence; unexpected write/commit failures are blocking errors.

## 11. Tests required before code review

Runner coverage on both windows-2022 and windows-2025 must include:

- all operation-equivalence cases IIS-01 through IIS-32 that are runner-safe;
- prerequisites and missing non-installable modules;
- pool identity family authorization and marker password safety;
- pool create/update/start/stop/recycle and no-op second run;
- site create/update and physical-path containment;
- folder, virtual-directory and conversion-to-application cases;
- application settings, authentication/preload/protocol settings;
- HTTP/HTTPS/net.tcp bindings, SNI and certificate re-assignment;
- a `WebHosting` store HTTPS binding;
- auto-start provider/application paths;
- duplicate identifiers against an enabled **unselected** instance;
- transient WAS/W3SVC retry boundaries;
- batched commit behavior and fresh `ServerManager` after external changes;
- preview determinism and APPLY fingerprint mismatch;
- backup failure blocks mutation and restore is verified;
- catalog for another machine refused;
- V1 never deletes an unmanaged IIS object.

[V] Real topology, locked sections, real identities, central certificate-store topology, hundreds-of-pools batching and production-size backup/restore remain outside runner proof.

## 12. Open questions

1. [PENDING] Final mechanism for IIS-01 Windows features under PowerShell 7.
2. [PENDING] Exact policy for converting a virtual directory with children/settings into an application.
3. [PENDING] Final backup mechanism and restore granularity.
4. [PENDING] Exact source severities for locked/inherited-section findings.
5. [PENDING] Who provisions pool-identity accounts when `CreatePoolIdentityIfMissing` is false; current recommendation is preflight failure if absent.
6. [PENDING] Central certificate store is outside V1 unless real-server evidence requires it.

## 13. Entry gate for the code PR

The `IIS_RECONCILE` code PR may start when:

- the 32-operation equivalence matrix has reviewer sign-off against the source behavior;
- all catalog columns used by the implementation are present in `carried-schema.json`;
- the full original review-code/severity inventory is attached to tests;
- cross-instance and containment classifications exist for every machine-global name and physical path;
- batch boundaries are explicit;
- backup/restore mechanism is decided or the first slice is explicitly prevented from APPLY;
- runner tests map every supported IIS operation to preview, apply and idempotency evidence.

[V] Merge of a runner-complete implementation does not itself close ADR-0006 real-server conditions 2 and 3.
