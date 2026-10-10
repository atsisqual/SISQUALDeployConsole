# Production handover package

**Status:** [PROPOSED]
**Task:** T20 / M5.2
**Date:** 2026-10-10

This document defines the minimum material handed from the implementation/review team to the production owner/operators for SISQUAL Deploy Console V1. It is a handover checklist/template, not proof that the referenced artifacts already exist.

## 1. Handover objective

A new operator must be able to answer, without reading source code or relying on chat history:

- what exact release/package is approved;
- which machine/catalog/credential package it belongs to;
- how to start and stop the console safely;
- which operations are supported and which remain `[V]`/unsupported;
- what preview/confirmation/recovery rules apply;
- where logs/manifests/backups are stored;
- how to recover from each supported mutating operation;
- how to rotate/reissue credentials/package/catalog safely;
- how to diagnose a blocked startup or failed operation;
- when to escalate rather than improvise;
- how existing-server cutover differs from the first clean-server deployment.

## 2. Handover bundle index

[PROPOSED] Deliver one versioned read-only handover bundle containing or referencing:

1. release summary and exact Git commit;
2. signed package/manifest verification information;
3. catalog identity/provenance/schema/cut-rule information per production machine;
4. supported-machine/instance inventory (non-secret);
5. credential-package operating guide (references/process only, never values);
6. operator quick-start/runbook;
7. action/engine support matrix;
8. backup/restore verification procedure and evidence index;
9. production acceptance/cutover record;
10. troubleshooting/escalation guide;
11. known limitations/open `[V]` items and accepted deviations;
12. security operating requirements;
13. retention/cleanup responsibilities;
14. old-system decommission/ownership-transfer record for migrated existing servers;
15. final threat-model review and security sign-off reference;
16. support ownership/contact/escalation roles, expressed as roles if personal contact details are maintained elsewhere.

Secret-bearing artifacts are referenced by protected location/identifier, not embedded in the handover bundle.

## 3. Release summary template

Record:

```text
Product: SISQUAL Deploy Console
Release/version:
Git commit:
Build/package date:
Package manifest schema/version:
Catalog schema/cut-rule versions:
Credential package contract/version:
Supported Windows Server versions:
Portable PowerShell version:
SQLite provider/tooling versions:
Pinned SQL client version:
Approved engines/actions in this release:
Composite FULL_DEPLOYMENT supported: Yes/No + scope
First accepted environment:
Threat-model review reference:
Acceptance record reference:
Known accepted deviations:
Owner approval:
```

Do not label an engine/action “supported” merely because its documentation PR exists; support requires integrated implementation and required runner/`[V]` evidence.

## 4. Per-machine deployment record

For every production machine, maintain a non-secret deployment record:

```text
ServerCode:
Expected MachineName:
Package release/hash:
Catalog SHA-256:
Catalog build/source provenance:
Catalog schema/cut-rule:
Credential package identity/recipient:
Enabled local instances:
General links-directory scope if applicable:
Package installation root:
Logs root:
Backup/recovery roots:
First startup acceptance date:
Last accepted preflight result:
Last accepted FULL_DEPLOYMENT preview/apply (if supported):
Open deviations/maintenance notes:
```

Remote rows in a Links directory are not executable local instances and must not be listed as local deployment targets.

## 5. Operator quick start

The final handover replaces placeholders below with the actual merged product commands/UI labels:

1. verify the folder/package is the approved sealed release for this machine;
2. launch only through the supported `Start.cmd`/entry point;
3. allow startup to complete package, machine identity, catalog and credential-package verification;
4. if startup is blocked, stop and follow the documented trust/machine/catalog/credential failure path; never edit the signed package in place;
5. open the local loopback UI/CLI through the supported launch path;
6. review catalog/package provenance and target machine before running an action;
7. run PREVIEW before any mutating/composite APPLY;
8. resolve blocking findings and review backup/restore availability;
9. confirm only the exact fingerprinted plan/targets;
10. monitor structured operation status; do not infer success from HTTP/process exit alone;
11. preserve logs/manifests/backups after failure;
12. use controlled shutdown; do not force-close while an unsafe active operation remains.

## 6. Startup blocked — first-line triage

Classify before taking action:

- **Package signature/integrity** - replace with the approved sealed package; do not bypass verification.
- **Rollback/verified-state** - investigate release counter/state and approved upgrade path; do not lower/erase state casually.
- **Machine identity mismatch** - verify the package/catalog is intended for this machine; never copy/export another machine identity as a fix.
- **Catalog invalid/foreign/tampered** - regenerate/revalidate/reseal through owner tools; do not edit runtime SQLite in place.
- **Credential package invalid/missing** - reissue/import through approved B6 tooling for this machine; do not paste secrets into catalog/config.
- **Runtime dependency missing/corrupt** - replace the sealed package from the approved source; do not download `latest` dependencies on the server.

Any trust failure remains fail-closed.

## 7. Action support matrix

The final bundle includes a table generated/reviewed from the release registry:

| Action/engine | Class | Preview | Apply | Scope | Credentials | Backup/restore | `[V]` evidence | Production status |
|---|---|---|---|---|---|---|---|---|
| `DEPLOYMENT_PREFLIGHT` | read-only | yes | n/a | instance/all | approved refs | n/a | pilot model | ... |
| `CONFIG_REPAIR` | mutating | yes | yes | instance/all | exact rule refs | file restore | real app tree | ... |
| `MANAGED_ASSETS` | mutating | yes | yes | instance/all | none | file restore | real roots/ACLs | ... |
| `IIS_RECONCILE` | mutating | yes | yes | instance/all | IIS identity family | IIS recovery | ADR-0006 | ... |
| `WINDOWS_SERVICES` | mutating | yes | yes | instance/all | IIS identity family | partial/credential-assisted | real services/accounts | ... |
| `V8_KEYCLOAK_PREREQUISITES` | mutating | yes | yes | machine | none | partial/operator | real installers | ... |
| `V8_KEYCLOAK_SERVICE` | mutating | yes | yes | instance/all | IIS identity family | service restore | real Keycloak | ... |
| `KEYCLOAK_CLIENT_SECRETS` | mutating | yes | yes | instance/all | exact rule secrets | protected/forward fix | real Keycloak DB/cache | ... |
| `WEB_ACCESS` | mutating | yes | yes | instance/all | Web Access family | partial restore | TSplus `[V]` | ... |
| `DATABASE_CONTENT_SYNC` | mutating | yes | yes | instance/all | mobile token family | protected DB recovery | real DBs | ... |
| `PULSE_STATUS` | mutating | yes | yes | machine | IIS identity family | file/ACL/task restore | real hub/cadence | ... |
| `LINKS_PAGES` | mutating | yes | yes | instance/all | none | file restore | browser/sites | ... |
| `ENVIRONMENT_STATE_PROBE` | observational | single probe | n/a | instance/all | none | n/a | real network | ... |
| `STORAGE_SIZE_SCAN` | observational | single scan | n/a | machine | none | n/a | large roots | ... |
| `MODEL_REVIEW` | read-only | single run | n/a | instance/all | as final contract | n/a | pilot parity | ... |
| `LINKS_VISIBILITY` | observational proposal | yes | proposal only | machine | none | catalog baseline outside engine | pilot page | ... |
| `DATABASE_COPY` | destructive mutating | yes | yes | machine/local instances | none | safety backup restore | real SQL `[V]` | ... |
| `FULL_DEPLOYMENT` | composite | yes | yes | selected instances/machine | child-specific only | child manifest index | clean-server pilot | ... |

Rows not accepted for production are shown as unavailable/unsupported in operator documentation and product surface.

## 8. Preview and confirmation operating rule

Handover must make these rules explicit:

- never APPLY from memory or screenshots of an earlier preview;
- use the exact current preview/fingerprint generated by the product;
- stale package/catalog/live-state/plan means re-preview;
- destructive/disruptive actions require the action-specific confirmation text where defined;
- warnings are reviewed, not automatically ignored;
- `SKIPPED` or `NOT_APPLICABLE` is acceptable only when that engine/orchestrator contract says so;
- missing required backup/restore readiness blocks APPLY.

## 9. Backup/recovery operator guide

Operators receive the T20 backup/restore verification procedure plus a release-specific table:

```text
Engine/action | Backup root/type | Restore command/UI | Requires credential? | Outage? | Automatic/Manual | Last tested evidence
```

Rules:

- do not delete a backup referenced by a failed/incomplete operation;
- do not copy customer/database/secret-bearing backups into tickets/chat/email;
- do not use an old manifest against a different machine/instance/object;
- do not restore over post-operation drift without the restore tool's current-state checks;
- for DATABASE_COPY, preserve the safety backup until external retention policy explicitly expires it; the copy engine itself never deletes it;
- irreversible/system prerequisite changes use the approved operator recovery procedure, not a fake “rollback successful” status.

## 10. Logs and evidence

Document exact release-specific locations/naming for:

- runtime text logs;
- engine structured results;
- operation/composite results;
- backup/run manifests;
- optional observational status/history files;
- acceptance evidence.

Log handling rules:

- do not enable PowerShell transcript/debug modes that expose secret-bearing command data unless separately reviewed;
- ordinary logs/results must remain marker-secret clean;
- retain operation id when escalating;
- capture bounded redacted diagnostics, not whole database/config files;
- operator may copy hashes/codes/statuses, not credential values or protected artifacts.

## 11. Credential operations

Handover explains credential lifecycle without distributing values:

- credential values live outside Git/catalog;
- one-time legacy import occurs only in the approved owner-controlled environment;
- per-machine package is issued to the intended non-exportable machine identity;
- runtime gives children only approved exact/family references;
- rotation/reissue generates a new package/version through approved tooling;
- service/task/account engines may need current credential again during restore;
- deleting/replacing a credential package during an active operation is prohibited;
- a leaked credential is rotated/reissued; do not “mask it in logs” and leave the value active.

The handover bundle records reference/kind names, never secrets.

## 12. Catalog change operations

Operators must distinguish runtime operations from owner catalog changes:

- runtime opens catalog read-only;
- visibility/config model edits occur through approved offline structured tools/workflow;
- catalog changes require validation and reseal before runtime use;
- stale derived Links directory is corrected by reconvert/reseal, not cross-machine runtime sync;
- production catalog edits follow second-reader/baseline/seal requirements;
- never use sqlite CLI/manual UPDATE on the production runtime catalog as an operational shortcut.

## 13. Package update procedure

Final handover includes the exact supported update sequence. Minimum safety shape:

1. ensure no active operation or use controlled shutdown/drain;
2. retain current accepted package/catalog/credential/recovery evidence according to policy;
3. verify new sealed package before activation;
4. enforce accepted rollback/monotonic state rules;
5. preserve machine identity outside the copied portable content as designed;
6. start and verify package/catalog/credentials;
7. run preflight/required preview before mutating operations;
8. if update fails trust/startup checks, reactivate only through the approved rollback procedure; never mix files from two sealed releases.

[PENDING] Replace this outline with exact product commands once final packaging/update code is integrated.

## 14. Controlled shutdown

Operator guidance:

- browser close is not process shutdown;
- use the supported Exit/Shutdown command;
- new operation admission stops first;
- cooperative operations may be asked to cancel only at engine-defined safe points;
- non-cancellable active work can block exit;
- do not kill the console/service/PowerShell process during a mutable child merely because the UI appears idle;
- after a forced OS/process termination, treat the last operation as interrupted and inspect its manifest/target before rerun.

## 15. Failure and escalation categories

Escalation guide groups incidents:

1. trust/package/manifest/rollback state;
2. machine identity/catalog ownership;
3. credential package/reference;
4. preflight/model parity/readiness;
5. path/ACL/filesystem;
6. IIS/MWA/certificate/binding;
7. Windows service/account/logon rights;
8. Keycloak/service/database/cache/TLS;
9. Web Access/TSplus;
10. SQL/database content/copy/recovery;
11. lock/idempotency/cancellation/shutdown;
12. Links/Pulse generated files/tasks;
13. unexpected secret exposure;
14. suspected product defect/internal exception.

For escalation provide operation id, package/catalog hashes, engine/action code, target instance and redacted structured error. Do not send password/token/config/database dump by default.

## 16. Immediate stop/escalate conditions

Operators do not improvise when:

- package/catalog signature/integrity verification fails;
- machine identity does not match expected server;
- a marker/real secret appears in an ordinary log/result;
- database restore leaves `RESTORING`, `SUSPECT`, inaccessible or unknown state;
- safety backup is missing/corrupt before a destructive restore/copy;
- IIS restore would overwrite unrelated production changes outside reviewed blast radius;
- unexpected duplicate/shared account password conflict appears;
- operation is non-cancellable and shutdown is blocked during a maintenance deadline;
- a target differs from the exact preview/fingerprint in a way the product refuses;
- existing old-console worker appears to keep mutating after ownership handoff.

Preserve evidence and escalate; do not bypass safety checks.

## 17. Known limitations register

Every release handover has a table:

| ID | Area | Limitation | Status | Workaround/operation rule | Owner/evidence |
|---|---|---|---|---|---|

At minimum include unresolved `[V]` items, accepted architectural deviations, unsupported engines/features and restore limitations.

An item disappears only when the release containing its verified fix is accepted; do not silently remove it because a code PR was opened.

## 18. First clean-server versus existing-server ownership

Handover states explicitly:

- first production acceptance is on a server without the current Deploy Console;
- success there does not automatically authorize migration of existing servers;
- existing servers require per-server freeze/reconversion/reseal, preflight/preview/recovery evidence and owner cutover decision;
- old and new mutation paths must not operate concurrently on the same managed targets;
- old worker/tasks/services are disabled only at the approved handoff point and their final state is recorded;
- re-enabling the old system after new APPLY requires a deliberate rollback/reconciliation decision, not a reflex restart.

## 19. Retention responsibilities

The handover assigns named roles (not necessarily personal names) for:

- signed release/package retention;
- catalog source/baseline/change/seal evidence;
- credential package rotation/revocation;
- engine backup retention/cleanup;
- database-copy source/safety backup retention;
- text log/result retention;
- acceptance/threat-model/handover evidence;
- old-system decommission evidence.

Retention tooling may clean expired artifacts only under the approved rules; it does not infer that an artifact is safe to delete merely from age when an incomplete operation/recovery manifest still references it.

## 20. Security handover checklist

Before production ownership transfer:

- [ ] final threat-model review complete with no blocking issue;
- [ ] package trust/rollback state procedure documented;
- [ ] machine identity recovery/re-enrollment process documented;
- [ ] credential import/issue/rotate/revoke process documented;
- [ ] UI session/CSRF/Host/Origin boundary documented and tested;
- [ ] no remote-bind support introduced;
- [ ] secrets absent from ordinary logs/results/process arguments;
- [ ] protected backup/customer data handling documented;
- [ ] incident path for suspected secret exposure documented;
- [ ] old broad/development GitHub or deployment tokens revoked/replaced where M5 owner tasks require it;
- [ ] production operator permissions reviewed.

## 21. Backup/restore handover checklist

- [ ] every production-enabled mutating engine has a recovery classification;
- [ ] every claimed restore function has runner/disposable evidence;
- [ ] required `[V]` restore tests completed on pilot/representative topology;
- [ ] backup roots/ACLs/retention ownership documented;
- [ ] secret-bearing recovery artifacts protected;
- [ ] irreversible effects listed clearly;
- [ ] DATABASE_COPY safety backup restore tested if engine enabled;
- [ ] FULL_DEPLOYMENT combined child-manifest/recovery limitations understood;
- [ ] restore failure escalation procedure documented.

## 22. Operational handover session

[PROPOSED] Conduct one recorded/checklisted walkthrough with the receiving operator using the accepted package or a production-equivalent sandbox:

1. start console and inspect verified package/catalog/machine state;
2. run read-only preflight/model/health operation;
3. run one safe mutating preview and explain fingerprint/confirmation;
4. perform an approved disposable mutation and its restore/recovery;
5. show logs/result/manifest and secret-safety boundaries;
6. demonstrate lock/idempotency behavior;
7. demonstrate controlled shutdown with and without active work;
8. demonstrate catalog-change/reseal distinction;
9. walk through a failed-startup scenario;
10. walk through escalation evidence collection without copying secrets.

Operator signs that the process was demonstrated; this is training evidence, not a substitute for engine acceptance tests.

## 23. Handover sign-off template

```text
Release/version:
Git commit:
Signed package identity:
First accepted production machine:
Production machines in current scope:
Enabled/supported actions:
Unsupported/PENDING/[V] actions:
Backup/restore evidence index:
Threat-model reference:
Acceptance/cutover reference:
Known limitations register:
Credential owner role:
Package/catalog owner role:
Operations owner role:
Support/escalation owner role:
Handover walkthrough date:
Receiving operator/reviewer:
Open blocking items:
Ownership transferred: YES / NO
Owner approval:
```

Ownership is not transferred while a production-blocking item remains open.

## 24. Final handover gate

M5.2 handover is ready to close only when:

- the release-specific values replace placeholders/templates;
- all production-enabled mutating engines have referenced backup/restore evidence;
- M5.1 production acceptance/cutover evidence exists for the first clean server;
- M5.3/M5.4/M5.5 required reviewer/owner/real-topology/threat-model gates are complete;
- the receiving operator has the quick-start, recovery, credential, update, shutdown and escalation procedures;
- secret-bearing operational artifacts remain outside the document bundle;
- owner explicitly accepts the handover.
