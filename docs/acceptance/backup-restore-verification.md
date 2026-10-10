# Backup and restore verification procedure

**Status:** [PROPOSED]
**Task:** T20 / M5.2
**Date:** 2026-10-10

This procedure defines the evidence required before a mutating SISQUAL Deploy Console operation is accepted for production. A backup is not considered valid merely because a file or manifest exists: the corresponding restore/recovery path must be exercised and its postconditions verified on representative topology before production enablement.

## 1. Evidence boundary

[CONFIRMED] Checked against `main` on 2026-10-10:

- mutating engine specifications consistently require preview/apply separation, a run/backup manifest and restore/recovery evidence where the old system lacked it;
- `CONFIG_REPAIR` explicitly proposes per-file before/after SHA-256 and a tested restore before enablement;
- `WINDOWS_SERVICES` records readable service state and notes that account passwords cannot be read back, so restore may need the credential package again;
- `PULSE_STATUS` defines file/ACL/task backup and restore and says restore must be tested before enablement;
- `DATABASE_COPY` defines the destination safety backup as the undo path and requires a tested restore-from-safety-backup function before destructive use;
- `FULL_DEPLOYMENT` is a composite/orchestrator and therefore indexes child backup/restore evidence rather than inventing a transactional global rollback;
- observational/read-only engines have no managed-target restore requirement unless they create optional disposable report/history artifacts.

[NOT VERIFIED] This document itself does not prove that any engine implementation has completed these tests. Every item marked `[V]` or requiring real target state must be executed and attached to the final acceptance record.

## 2. Core rule

A mutating engine is production-ready only when its recovery model is one of the following and is explicitly tested:

1. **RESTORE** - capture the pre-change state and restore it, then prove the target is equal to the recorded before-state;
2. **SAFETY BACKUP RESTORE** - restore a verified database/system backup and prove database/application health;
3. **FORWARD FIX** - the effect cannot be safely reversed from readable state, so a documented, bounded forward-fix procedure is tested instead;
4. **IRREVERSIBLE / OWNER PROCEDURE** - system-wide prerequisite/install effects are intentionally outside automatic rollback; the acceptance record states that limitation and contains the approved operator recovery/uninstall procedure.

“Rerun the engine” is not a backup/restore strategy unless the documented failure mode is proven to converge safely without losing the prior state.

## 3. General requirements for every mutating operation

Before APPLY:

- preview/fingerprint identifies exactly the target and intended changes;
- backup/recovery capability for every planned mutation is known;
- backup root is an approved local path and is not derived from untrusted request text;
- sufficient disk space exists for the backup plus operation working space;
- backup destination access is restricted to the identities that require it;
- secret-bearing/customer-data backups are identified as protected content and are never copied into ordinary logs/reports;
- if the operation cannot be reversed, that fact appears before confirmation.

During APPLY:

- backup is taken **before** the first destructive write to each managed object;
- a backup failure blocks the corresponding mutation;
- original and backup object identities are recorded unambiguously;
- backup verification happens before destructive mutation where the medium supports verification;
- run/backup manifest is written incrementally/atomically enough to survive later operation failure;
- cancellation or failure never deletes the only valid recovery artifact.

After APPLY:

- post-change state is verified;
- backup/manifest remains accessible for the approved retention window;
- restore eligibility/limitations are reported without exposing protected content.

## 4. Standard backup manifest fields

[PROPOSED] Every child engine that supports restore exposes a machine-readable manifest containing only non-secret metadata:

- schema/version;
- operation id;
- action/engine code and version;
- machine/server code;
- instance code where applicable;
- object type and stable object identity;
- UTC creation time;
- backup artifact reference/path;
- pre-change SHA-256 or equivalent stable before-state fingerprint where meaningful;
- post-change SHA-256/fingerprint where meaningful;
- backup verification status;
- restore method identifier;
- restore prerequisites;
- `containsSensitiveData` boolean/classification, never the sensitive value;
- retention classification;
- whether automatic restore is supported;
- whether current credential material is required to restore;
- final restore-test evidence reference when produced.

Do not put plaintext passwords, tokens, database row values or protected credential-file plaintext in the ordinary manifest.

## 5. Backup integrity checks

For file backups:

- compute SHA-256 of source bytes before change;
- copy/write backup;
- compute SHA-256 of backup bytes and require equality;
- after restore, recompute target SHA-256 and require equality with the original before hash.

For SQL native backups:

- require successful BACKUP with checksum where supported/approved;
- run the configured verification (`RESTORE VERIFYONLY`/equivalent source-engine contract);
- record backup set/database identity and backup file path;
- for acceptance, execute a real restore on a disposable/representative destination and verify database state, not only `VERIFYONLY`.

For IIS/application configuration backups:

- capture the exact configuration scope claimed by the child engine;
- prove the backup can recreate that scope on the representative topology;
- verify expected sites/pools/apps/bindings/settings after restore.

For service/task/account metadata:

- record only readable configuration;
- explicitly mark non-readable password state;
- restore uses the current approved credential package again if needed;
- do not imply that a service/task export contains its password.

## 6. Restore precondition checks

A restore must fail closed if:

- manifest schema/engine/object identity is unsupported;
- backup artifact is missing or hash/verification fails;
- manifest target does not match the current verified machine/instance;
- current target changed since the failed operation in a way that makes blind overwrite unsafe;
- required credential reference is absent;
- the operator selected a different object/path/database than the manifest identifies;
- a destructive database restore lacks sufficient disk/permissions or the required safety confirmation;
- restore would follow an unsafe path/UNC/device/reparse escape outside the approved root.

A “force restore” path is not part of V1 unless an engine has a separately reviewed owner-approved procedure.

## 7. Restore test pattern

Every restore-capable mutating engine must have an automated/disposable test with this shape where technically possible:

1. create representative initial state A;
2. run PREVIEW and capture fingerprint;
3. APPLY state B;
4. verify B and verify backup/manifest exists;
5. invoke restore using that exact manifest;
6. verify restored state equals A using stable object/hash/property comparisons;
7. rerun PREVIEW and confirm expected state after restore is represented correctly;
8. inject at least one restore failure and prove the target/backup remains diagnosable and the recovery artifact is retained;
9. inspect every ordinary artifact for marker credentials/secrets.

For `[V]` topology, repeat the same logic on the sandbox/pilot with the real subsystem and retain redacted evidence.

## 8. Engine recovery matrix

The matrix below is the required acceptance shape. It does not assert implementation completion.

| Engine | Managed changes | Required recovery model | Minimum verification |
|---|---|---|---|
| `CONFIG_REPAIR` | JSON/XML/text configuration files | RESTORE | changed file backed up once; before/backup/restore hashes equal; encoding/BOM preserved |
| `MANAGED_ASSETS` | asset files/directories | RESTORE | replaced bytes restored by hash; newly-created file removal only when operation ownership is proven |
| `IIS_RECONCILE` | IIS config, directories/ACLs, bindings/pools/sites/apps | RESTORE / operator IIS backup | selected backup mechanism restored on representative IIS topology; blast radius documented; ADR-0006 `[V]` conditions retained |
| `WINDOWS_SERVICES` | local account/logon-right/service config/state | PARTIAL RESTORE + credential-assisted restore | readable service state restored; account/password limitation explicit; service reaches prior running state where appropriate |
| `V8_KEYCLOAK_PREREQUISITES` | NSSM/JDK/JDBC prerequisites/system files | IRREVERSIBLE / OWNER PROCEDURE; file restore where replaced | replaced NSSM/JDBC file restored by hash; JDK install/uninstall/recovery procedure exercised on disposable target; no fake transactional rollback claim |
| `V8_KEYCLOAK_SERVICE` | Windows/NSSM service settings/state | RESTORE / credential-assisted | readable NSSM/service configuration restored; newly-created service removal only with proven ownership; password re-supplied through approved path |
| `KEYCLOAK_CLIENT_SECRETS` | Keycloak DB secret rows | PROTECTED RESTORE or FORWARD FIX | no plaintext before-image in ordinary artifacts; if rollback artifact is allowed it is machine-protected and round-trip tested; otherwise rotation/forward-fix tested |
| `WEB_ACCESS` | local user/group state, protected credential file, page, IIS default docs, pool restart | PARTIAL RESTORE / credential-assisted | page + protected file bytes/ACL + default-document list restored; created-user deletion policy explicit; no plaintext credential backup |
| `LINKS_PAGES` | generated page/resource files | RESTORE | replaced file hashes restored; newly-created file ownership/removal proven; shared branding consistency checked |
| `DATABASE_CONTENT_SYNC` | application DB rows | PROTECTED ROW RESTORE or FORWARD FIX | transaction failure rollback; if before-images retained they are machine-protected; parameterized restore tested; real DB backup remains operator procedure `[V]` |
| `PULSE_STATUS` | page/config/resources/plan/status, ACLs, scheduled task | RESTORE / credential-assisted | files/ACL/task definition restored; task account password supplied from current credential; marker-secret check |
| `DATABASE_COPY` | destination databases, ACL grants, IIS outage/state | SAFETY BACKUP RESTORE | verified safety backup before overwrite; end-to-end restore from safety backup; backup never deleted by the copy operation |
| `FULL_DEPLOYMENT` | union of enabled children | COMPOSITE RECOVERY INDEX | combined manifest references child manifests; reverse recovery only where each child supports it; no claim of global transaction |

`DEPLOYMENT_PREFLIGHT`, `ENVIRONMENT_STATE_PROBE`, `STORAGE_SIZE_SCAN`, `MODEL_REVIEW` and portable `LINKS_VISIBILITY` do not mutate managed targets and therefore require no managed-target restore procedure.

## 9. CONFIG_REPAIR verification

Required test evidence:

- at least JSON, XML and text files;
- UTF-8 with/without BOM and UTF-16 cases supported by implementation;
- backup once per changed file, not once per rule;
- atomic write followed by post-write validation;
- restore recreates exact original bytes/hash;
- secret-bearing source file remains protected in backup location;
- marker secret absent from ordinary run/restore logs.

[V] Repeat on a representative real application tree/ACL layout.

## 10. MANAGED_ASSETS and LINKS_PAGES verification

For generated/copied assets:

- distinguish `created` from `replaced`;
- replaced target has byte-for-byte recovery evidence;
- created target is deleted during restore only when manifest proves it was absent before and still matches the operation-created hash;
- do not delete a file that drifted after the operation;
- shared branding file restore cannot undo a later valid change made by another engine/operation without an explicit stale-state refusal.

## 11. IIS_RECONCILE verification [V]

Before production enablement:

1. create representative IIS drift on sandbox/pilot;
2. take the selected IIS backup before mutation;
3. APPLY a known reconciliation set covering pool/site/app/binding/settings cases within acceptance scope;
4. verify the resulting IIS state through MWA and, where relevant, real requests;
5. restore the backup/recovery scope;
6. recreate a fresh `ServerManager` and verify original configuration;
7. verify pool/site runtime state and certificates/bindings after restore;
8. document blast radius: a whole-IIS backup restore can affect unrelated objects, so the operator procedure must state when it is safe.

Do not mark IIS restore accepted solely because `appcmd add backup` or a configuration copy succeeded.

## 12. WINDOWS_SERVICES / V8_KEYCLOAK_SERVICE verification

Record before-state:

- service exists/absent;
- executable/binary path and arguments;
- account name;
- display name/description;
- startup type/delayed start;
- recovery/restart settings where managed;
- prior running state;
- relevant readable NSSM settings.

Restore proves these readable properties. Password cannot be recovered from service configuration: the restore procedure requests the same approved credential reference again and never exposes its value.

If the operation created the service, remove it on restore only when the manifest proves ownership and current service identity/settings have not drifted unexpectedly.

## 13. WEB_ACCESS verification

Backup/restore test covers:

- existing `Default.aspx` bytes/hash;
- protected credential-file encrypted bytes and ACL;
- IIS default-document list;
- readable local-user/group/flag state;
- root-pool prior state where restoration needs it.

The protected credential file remains encrypted at rest in both live and backup locations. A backup test must not decrypt it into the manifest/log.

Created-user removal remains an explicit policy decision; absence of that decision means restore leaves the account and reports the manual/forward-fix requirement rather than deleting it unsafely.

## 14. PULSE_STATUS verification

Backup/restore includes the page/config/logo/collector/plan files required by the implementation plus previous ACL/task definition where managed.

Test:

- restore file hashes;
- reapply ACLs;
- register task definition with current credential package;
- confirm task action/user/interval and one safe run;
- prove task password never appears in export/result/log.

## 15. DATABASE_CONTENT_SYNC verification

Rule-level writes should be transactional. Two separate recovery layers are required:

- immediate SQL transaction rollback for a failed rule before commit;
- production recovery strategy for an already committed wrong value.

If row before-images are retained, store them only in a machine-protected artifact because values may include tokens/connection data. Ordinary manifest records target identities/counts only.

[V] Before first production use, execute a database-level backup/restore procedure on representative WFM/View/Keycloak data according to the operational backup policy; engine-local row restore does not replace a real database recovery plan.

## 16. KEYCLOAK_CLIENT_SECRETS verification

Old secret values are credentials. Therefore:

- ordinary backup manifests never contain them;
- if rollback is supported, before-images live only in an approved encrypted/machine-bound recovery artifact with strict ACL/retention;
- otherwise the accepted recovery is forward rotation/rewrite of the intended secret through the credential package;
- whichever model is selected must be exercised against representative Keycloak DB state;
- `[V]` verify whether runtime cache/service restart is required after recovery.

## 17. V8_KEYCLOAK_PREREQUISITES verification

System-wide installation is not represented as magically reversible.

- NSSM/JDBC existing files that are replaced get byte/hash backups and restore tests;
- JDK 23 installation records package identity/hash/install result;
- accepted uninstall/recovery procedure is exercised on a disposable target;
- failure after JDK install but before later prerequisites is reported as a partial system state with clear next action;
- restore evidence never claims “original machine state” if the installer made system changes not captured by the engine.

## 18. DATABASE_COPY safety-backup verification [V]

This is the strongest recovery gate because the engine overwrites destination databases.

Before production enablement:

1. create representative destination DB A with multiple files/known marker rows;
2. obtain/verify source copy backup B;
3. take destination safety backup A-backup with checksum/verify;
4. overwrite destination with B using the engine path;
5. verify B and post-copy state;
6. invoke the dedicated safety-backup restore operation;
7. verify restored DB is online/multi-user and original marker/data/file layout expectations are satisfied;
8. run configured physical checks;
9. prove destination IIS runtime state is restored appropriately;
10. prove the A-backup file still exists after both copy and recovery;
11. inject restore failure and retain/report the backup/manual recovery state.

`DATABASE_COPY` must never delete the safety backup that is its only undo artifact. Retention belongs to a separate policy/process.

## 19. Composite FULL_DEPLOYMENT recovery

The composite manifest contains references to child manifests only. A recovery tool/runbook:

- determines which child operations actually mutated state;
- orders eligible restores in reverse dependency/execution order;
- stops if a child restore fails and reports remaining unrecovered children;
- skips children whose contract is forward-fix/irreversible and tells the operator exactly what remains;
- does not decrypt/repackage child secret backup contents;
- never describes the whole deployment as ACID/transactional.

For acceptance, use fake-child automated tests plus a sandbox composite run with at least two restore-capable child engines and one intentionally non-transactional child so the limitations are visible.

## 20. Backup ACL and retention verification

For every backup root on the pilot:

- inspect effective ACL before/after the run;
- prove unapproved broad principals (for example Everyone) do not gain read access;
- prove engine/service accounts get only the minimum access required;
- prove temporary grants are removed after use where specified;
- classify backup content as configuration, protected credential, or customer/database data;
- apply the approved retention policy outside the active restore operation;
- retention never deletes the newest required safety backup while a failed/incomplete operation still references it.

[PENDING] Exact retention durations remain engine/operations policy where not yet decided; lack of a final duration does not permit immediate cleanup of recovery evidence.

## 21. Restore authorization and confirmation

[PROPOSED] Restore is a distinct privileged operation, not a hidden automatic side effect of an APPLY failure.

The operator sees:

- source operation/engine/target;
- backup time/identity/hash verification status;
- current target state/drift check;
- objects that will be overwritten by restore;
- services/IIS/database outage caused by restore;
- parts that are not reversible;
- exact confirmation text for destructive database/IIS-wide restore where required.

The backend revalidates the manifest and current target after confirmation.

## 22. Failure injection matrix

Each mutating engine implementation must inject failures at meaningful boundaries, at minimum:

- before backup;
- during backup;
- after backup but before mutation;
- during mutation;
- after mutation before verification;
- during post-verification;
- during restore;
- after partial restore.

Expected evidence states must be documented. A test that only proves the happy-path restore is insufficient for production acceptance.

## 23. Secret/data leak inspection

For every backup/restore test with marker credentials/data:

Search ordinary artifacts for the raw marker:

- engine result JSON;
- text logs;
- composite result/log;
- manifests;
- error text/stack normalization;
- process command lines captured by tests;
- proposal/status/report files.

Protected backup/database/credential artifacts intentionally containing protected source data are excluded from plaintext scanning only when their encryption/access-control model is itself verified. Their metadata still must not expose values.

## 24. Evidence record for each verified restore

Retain a redacted text/JSON record:

```text
Engine/action:
Implementation commit/package:
Target type:
Machine/instance:
Initial-state fingerprint:
Preview fingerprint:
Backup artifact reference:
Backup verification:
Mutation result:
Restore method:
Restore result:
Post-restore fingerprint:
Failure-injection case(s):
Secret-leak scan:
Reviewer:
Date:
PASS / FAIL:
Notes / irreversible effects:
```

For production-like `[V]` tests, include environment/topology identifiers without copying customer data.

## 25. Production gate

A mutating engine cannot be marked production-accepted when:

- its specification says restore must be tested and no test evidence exists;
- the only recovery artifact is created after mutation;
- backup integrity is not verified;
- restore cannot prove target identity;
- secret-bearing before-images are written in plaintext ordinary artifacts;
- a destructive database operation can delete its safety backup;
- restore procedure depends on undocumented manual commands;
- `[V]` topology-specific recovery required by its contract has never been executed.

The acceptance checklist references these restore evidence records before GO.
