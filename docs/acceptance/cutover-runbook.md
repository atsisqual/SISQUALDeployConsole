# Production acceptance checklist and cutover runbook

**Status:** [PROPOSED]
**Task:** T19 / M5.1
**Date:** 2026-10-10

This document defines the acceptance evidence and operator sequence for the first production deployment and later cutovers. The first acceptance target is deliberately a Windows server that **never had the current Deploy Console**. Existing production servers move only after that clean-server proof and a separate owner cutover decision.

## 1. Evidence boundary

[CONFIRMED] Checked now against `main`:

- `docs/handoff/remaining-work-plan.md` M5 defines production acceptance/handover and explicitly puts the first deployment on a server without the current system; existing servers come later.
- M5 also requires ADR-0006 conditions 2 to 4, backup/restore verification, final threat-model review, signed package/handover, and owner `[V]` validation of real SQL/credential/engine behavior.
- Phase 1B/1C runner evidence proves technical viability of machine identity, local browser security and operation coordination, but product adoption/integration and target-server proof are separate gates.
- `FULL_DEPLOYMENT` remains incomplete until child engines and clean-server dependency/order are resolved.

[NOT VERIFIED] No production or pilot server was accessed for this document. Every target-machine action below marked `[V]` must be executed and recorded by the owner/reviewer before acceptance can be claimed.

## 2. Acceptance principle

Production acceptance is evidence-based and fail-closed. A green runner, merged document, successful package build or successful preview is necessary evidence where applicable but is not by itself production acceptance.

[PROPOSED] The release is accepted only when every required gate below is one of:

- `PASS` with an evidence reference;
- `NOT_APPLICABLE` with the approving decision/evidence;
- an explicitly owner-accepted deviation recorded as a decision.

`PENDING`, `UNKNOWN`, `SKIPPED`, “worked on another server”, or “can be fixed after cutover” do not count as PASS.

## 3. Acceptance record

Create one immutable/text acceptance record for the release containing:

- product/package version and Git commit;
- package-manifest/signature identity and hashes;
- catalog SHA-256/schema/cut-rule/build provenance;
- target machine/server code and non-secret instance list;
- credential-package identity/version/reference counts, never values;
- Windows/PowerShell/runtime versions relevant to support;
- date/operator/reviewer/owner approvals;
- each checklist item status plus log/artifact/run reference;
- every known accepted deviation and `[V]` limitation;
- final GO/NO-GO decision and time.

Do not copy secrets, database contents, protected backup contents or session tokens into the record.

## 4. Product-completeness gate before any production pilot

The following must be integrated in the candidate release, not merely open in PRs:

- package assembly and startup integrity verification;
- approved verified-package-state/rollback protection required by the final trust model;
- non-exportable machine identity in product startup;
- per-machine credential-package issue/load/verification;
- runtime engine/action registry, coordinator, locks and controlled shutdown;
- operator command/UI path required for preview/result inspection;
- `DEPLOYMENT_PREFLIGHT` coverage/parity state accepted for production (normally M2 complete at 66/66 by name plus E0h parity decisions);
- every child engine used by `FULL_DEPLOYMENT` integrated with its tests and backup/restore declaration;
- clean-server `FULL_DEPLOYMENT` dependency/order resolved;
- Phase 1C browser-security/operation-coordinator model adopted in the product UI if the browser UI is in the release.

If the first production slice intentionally contains only preflight/read-only capability, acceptance scope must say so and no APPLY capability is treated as accepted.

## 5. Security/trust gate

Before pilot GO:

- package signature verifies against the pinned/approved issuer key;
- every shipped runtime/engine/provider file is covered by integrity verification as required by the final manifest contract;
- rollback/equal-counter/concurrent-start semantics of the accepted verified-state design are tested;
- copied package cannot impersonate another machine; machine identity is non-exportable;
- catalog opens read-only/immutable and sidecar/tamper cases fail closed;
- credentials are outside catalog/Git and only approved child references are delegated;
- marker secrets are absent from logs/results/transcripts/process command lines for every engine path;
- local UI binds loopback only and passes final Host/Origin/session/CSRF/CSP/no-storage tests;
- final threat-model review (M5.5) has no unresolved production-blocking finding.

Any trust/integrity failure is automatic NO-GO; there is no operator bypass.

## 6. ADR-0006 IIS gate [V]

For IIS-capable production release, close/record ADR-0006 conditions on target-like topology:

1. equivalence matrix remains the reviewed operation basis;
2. `[V]` exercise the MWA write path on a sandbox with realistic scale, existing drift and locked sections;
3. `[V]` prove real pool identities, SNI, certificate-store bindings and handler/module sections;
4. prove batched commits, policy-driven certificate store behavior and V1 no-deletion of unmanaged IIS objects.

Record before/after IIS evidence without dumping secrets. A failure of conditions 2/3 blocks IIS APPLY production acceptance.

## 7. SQL/database gate [V]

On target-like/real infrastructure, record:

- actual SQL instance discovery and local target ownership;
- connection encryption and certificate behavior for every engine that uses SQL;
- required permissions are least sufficient and failures are clear;
- `_sisqualMANAGEMENT` source collation/legacy reads relevant to one-time conversion/import are understood where still required;
- `DATABASE_CONTENT_SYNC` structured predicates/row counts match real target shapes;
- direct Keycloak database changes, if retained, have proven runtime/cache semantics;
- database copy, if enabled, has destination allowlist, free-space gates, verified safety backup and tested safety-backup restore on representative SQL topology.

A test against disposable/local runner databases is not a substitute for these `[V]` items.

## 8. Credential gate [V]

Before any mutating pilot:

- one-time import of legacy credentials has been performed/verified in the approved owner-controlled environment where applicable;
- per-machine credential package is issued to the intended machine identity;
- expected exact/family references match enabled engines/instances;
- decryption works only on the intended machine under the accepted identity design;
- shared IIS account/password invariants are proven for enabled instances;
- no credential value appears in catalog, repository, acceptance evidence or ordinary backup manifest;
- credential rotation/reissue procedure is available and tested at least on a non-production target.

Do not mark a credential missing warning as acceptable where the child engine/preflight defines it as blocking.

## 9. Backup/restore gate

T20 defines the detailed verification procedure. Before first mutating pilot, acceptance record must reference successful restore tests for every mutating child that claims rollback/recovery.

At minimum record:

- what is backed up before each managed mutation;
- backup identity/hash/location and access controls;
- restore preconditions and blast radius;
- successful restore verification on representative target;
- explicitly irreversible/forward-fix effects;
- database-copy safety backup restoration if DATABASE_COPY is enabled;
- proof that destructive operations do not delete their recovery backup.

“No automatic rollback” is acceptable only when recovery/manual-forward-fix behavior is explicit and accepted.

## 10. Clean-server pilot prerequisites [V]

Select a server that has never hosted the current Deploy Console. Before copying the package, record:

- Windows Server version/support state;
- expected exact machine name/server code;
- local disk space and approved roots;
- IIS/SQL/application prerequisites that are pre-existing versus installed by product engines;
- network/DNS/firewall conditions required for application/public probes;
- operator/admin account and approved SQL/IIS permissions;
- maintenance/customer-data status appropriate for the pilot;
- source package/catalog/credential artifacts finalized and hashes recorded.

The pilot must not rely on hidden files/settings left by an earlier Deploy Console installation.

## 11. Clean-server cutover — preparation

1. Freeze the catalog/source configuration for the acceptance window according to the approved change-freeze rule.
2. Generate/convert the target catalog using approved tooling and target-machine cut.
3. Validate the catalog independently, including structured DB filters, action/engine cross-references and derived Links directory.
4. Assemble the portable package with pinned dependencies/providers/engines/contracts.
5. Issue the per-machine credential package through approved credential tooling.
6. Seal/sign the complete candidate package and record package/catalog/manifest hashes.
7. Run offline/static/package verification required by release tooling.
8. Obtain reviewer sign-off that the candidate contains no known unreviewed production-blocking code change after evidence was produced.

Any modification after sealing requires a new package identity/seal and invalidates prior package-specific GO evidence.

## 12. Clean-server cutover — first startup

1. Copy the sealed folder to the approved local destination; do not install a global runtime dependency as a shortcut.
2. Start through the supported `Start.cmd`/product entry point.
3. Verify package integrity/signature and verified-state checks complete before normal operation.
4. Verify machine identity resolves exactly to the intended server and a copied identity is not accepted.
5. Verify the catalog opens read-only for this machine and reports expected provenance/instance count.
6. Verify credential package signature/recipient and required reference availability without displaying values.
7. Record startup log/result identifiers.

If startup reports trust/machine/catalog/credential corruption, stop. Do not edit the package in place on the pilot to make startup pass.

## 13. Clean-server cutover — preflight/readiness

1. Run `DEPLOYMENT_PREFLIGHT` through the supported product path for all enabled target instances.
2. Record exact result and coverage/parity marker/state.
3. Resolve every blocking error before mutating deployment.
4. Review warnings/info, especially catalog provenance, not-applicable policies and real-server deviations.
5. Re-run until readiness criteria are satisfied without manual result editing.

If preflight implementation is intentionally incomplete under an owner decision, the acceptance record lists exactly what it does not prove and separate evidence closes those gaps before APPLY.

## 14. Clean-server cutover — composite preview

When `FULL_DEPLOYMENT` is in acceptance scope:

1. Run composite PREVIEW for exact selected instances.
2. Require all child plans/results to be valid and all required `BLOCKED_BY` dependencies resolved.
3. Review disruptive effects: installers, service/pool restarts, database writes, account/ACL changes and any outage.
4. Review child backup/restore readiness.
5. Record composite fingerprint/expiry/selection/package/catalog identities.
6. Verify no required child is merely `SKIPPED` because a clean-server prerequisite (Keycloak files/database etc.) is missing.
7. Obtain GO approval for that exact preview.

A new package/catalog/selection/plan after review requires a new preview and GO.

## 15. Clean-server cutover — APPLY

1. Enter the exact required confirmation for the approved composite/action.
2. Keep the operator console/process alive for the duration; do not close/kill it to “unstick” an operation.
3. Monitor structured operation/child status and keep original logs/manifests.
4. On blocking failure, follow child/composite failure semantics; do not manually run later dependent steps merely to complete the checklist.
5. Preserve every recovery backup/manifests produced before failure.
6. If operation can safely continue independent instances under approved policy, record all failed/not-run targets; overall acceptance remains failed until corrected/rerun.

Do not declare GO based on process exit alone; use the structured result and postconditions.

## 16. Post-APPLY validation [V]

For every target instance/service relevant to the release:

- rerun preflight/readiness and expect no new blocking drift;
- run idempotency preview/second apply as defined: no unexpected managed changes/restarts;
- verify IIS sites/pools/applications/bindings/certificates through real traffic/topology;
- verify Windows services identities/start/state;
- verify Keycloak service/ports/OpenID and client-secret behavior if in scope;
- verify Web Access through real TSplus topology if in scope;
- verify database setting/content state against approved rules;
- verify Pulse behavior including no-profile `NOT_APPLICABLE` case;
- verify Links pages/assets in a browser, including general/individual scope;
- verify logs/results contain no marker secret;
- verify controlled shutdown/refusal while active and clean exit after drain;
- restart the console and prove package/machine/catalog/session state behaves correctly after restart.

Record deviations, do not normalize them away as “environment differences” without disposition.

## 17. Clean-server GO decision

GO requires:

- structured APPLY success for required scope;
- post-APPLY checks pass;
- backup/recovery artifacts intact;
- no production-blocking security/threat-model issue;
- no unexplained drift or required manual hidden step;
- owner/reviewer sign-off recorded.

If clean-server pilot is NO-GO, preserve evidence, restore/recover according to T20, fix in code/catalog/tooling, rebuild/reseal and repeat. Do not patch the accepted package on the server.

## 18. Existing-server cutover is a later operation

After clean-server acceptance, existing production servers are **not** automatically approved. The owner decides when each moves.

For each existing server, add migration-specific evidence:

- inventory current old-console/runtime/database/IIS/services/tasks/files and active operations;
- reconcile catalog against frozen source immediately before cutover;
- choose a maintenance window and customer communication where required;
- prove old and new consoles cannot concurrently mutate the same managed targets;
- preserve old-system configuration/recovery artifacts as required by retention/security policy;
- stop/disable old mutation path only at the approved handoff point;
- copy/start the sealed new package and repeat startup/preflight/preview gates;
- only then run approved APPLY/cutover changes;
- verify no old worker/scheduled job continues to write after ownership transfer.

No server is migrated because “the clean pilot passed”; its own preflight/preview/rollback evidence is required.

## 19. Existing-server abort/rollback criteria

Abort before APPLY if:

- source/cut catalog changed after seal/preview;
- unexpected active old-system operation cannot be safely drained;
- package/machine/credential/catalog verification differs from accepted candidate;
- required safety backup/restore evidence is missing;
- preview shows unreviewed/destructive scope beyond the maintenance plan.

After APPLY starts, use child recovery/restore procedures rather than attempting to restart the old console blindly. Returning ownership to the old system requires a defined state reconciliation and owner decision.

## 20. Evidence retention

Retain according to final handover policy:

- signed package/manifest/catalog identity;
- acceptance checklist/GO record;
- preflight/composite preview/APPLY/post-validation structured results;
- redacted logs and child/composite manifests;
- backup verification/restore evidence (metadata only where content is sensitive);
- threat-model final report;
- deviations/owner decisions;
- existing-server migration record when applicable.

Secret-bearing backups/credential packages remain in their protected operational stores, not embedded in handover documentation.

## 21. Automatic NO-GO conditions

- package signature/integrity/verified-state failure;
- machine identity mismatch/copyable identity defect;
- catalog integrity/machine mismatch;
- required credential package/reference failure;
- unresolved blocking preflight result;
- APPLY without exact accepted preview/fingerprint;
- destructive child without required verified recovery backup/restore proof;
- unresolved production-blocking threat-model finding;
- unexpected secret exposure in ordinary artifacts;
- required `[V]` IIS/SQL/topology gate not executed for the production scope;
- clean-server flow needs an undocumented manual mutation to succeed.

## 22. Acceptance sign-off template

Record:

```text
Release/package:
Git commit:
Target machine/server:
Catalog SHA/schema/build:
Credential package identity:
Acceptance scope:
Clean server / Existing server:
Checklist PASS/NA/PENDING counts:
Blocking deviations:
Backup/restore evidence:
Threat-model evidence:
Preflight result:
Composite preview fingerprint:
APPLY result:
Post-validation result:
Reviewer:
Owner:
GO / NO-GO:
Decision time:
```

A GO line is meaningful only with the referenced evidence present and the package unchanged.

## 23. Open items before this runbook becomes executable

1. [PENDING] Exact final product commands/API/UI labels from M1/M4 merged code; replace descriptive commands with executed evidence, not guesses.
2. [PENDING] Final FULL_DEPLOYMENT clean-server ordering/dependencies.
3. [PENDING] Final accepted verified-package-state design/implementation where still awaiting owner approval.
4. [PENDING] T20 detailed backup/restore verification and handover package.
5. [V] Execute and record the first clean-server pilot; this document alone is not acceptance evidence.
