# DATABASE_COPY port brief

**Status:** [PROPOSED]
**Task:** T15 / M3.9
**Date:** 2026-10-10

This brief defines the safety and implementation gate for `DATABASE_COPY`. It is documentation only.

## 1. Sources and evidence boundary

[CONFIRMED] Checked now against `main`:

- `docs/engines/DATABASE_COPY.md` documents source-era `Invoke-DatabaseCopy.ps1`, `cfg.GetDatabaseCopyPlan`, seven database definitions and the machine-scoped copy policy.
- The engine is explicitly destructive: it overwrites destination application databases and cuts sessions.
- `docs/handoff/remaining-work-plan.md` M3.9 calls out two required safety properties for this port: destination allowlist and a safety backup that is never deleted by the operation.
- Post-copy settings reconciliation is now `DATABASE_CONTENT_SYNC`; the retired standalone `DATABASE_SETTINGS` engine does not return.
- IIS stop/start must use MWA under ADR-0006.

[NOT VERIFIED] This brief did not perform a real backup/restore. Large database timing, SQL service-account folder rights, antivirus effects, disk layout and operator permissions remain `[V]`.

## 2. Purpose and class

[CONFIRMED] `DATABASE_COPY` is `MUTATING` and destructive. It copies a selected source instance's approved databases over selected destination instances on the same machine, with source backup, destination safety backup, restore, verification and post-copy reconciliation.

It has no credential-package references; SQL access uses the operator/runtime Windows identity and local SQL permissions.

## 3. Target model

[CONFIRMED] The reference model has seven required application-database definitions and a machine copy policy. Code consumes enabled catalog definitions/policy rather than hard-coding snapshot counts.

[PROPOSED] Only databases with `CopyEnabled` are eligible. Source, destinations and database subset must resolve entirely from enabled local catalog instances/definitions. Caller text cannot introduce another SQL instance/database.

Keycloak database is not implicitly copied merely because it exists; scope follows approved database definitions and post-copy Keycloak handling remains an explicit decision.

## 4. Destination allowlist is mandatory

[PROPOSED, M3.9 gate] APPLY is impossible unless every source→destination pair is explicitly authorized by catalog policy. “Same machine”, “enabled”, or “not the source” is necessary but not sufficient because a copy moves customer data and destroys destination state.

The allowlist model must support at least:

- exact source and destination identities (or an equivalently restrictive approved rule);
- destination marked overwrite-eligible;
- optional database subset constraints;
- disabled/expired rule rejection if lifecycle fields exist.

Preview explains which allowlist rule authorized each destination. Missing authorization is a blocking error, never an interactive override.

[PENDING] Exact catalog schema for the allowlist requires its own approved contract/tooling change if not already represented. Do not encode a hidden allowlist in code or UI configuration.

## 5. Deterministic preview and confirmation

[PROPOSED] Preview lists per source/destination/database:

- exact SQL/database identities;
- current existence/state and source sizes;
- source backup target;
- destination safety-backup target;
- default data/log restore folders and MOVE mapping;
- required free space/margin on each affected volume;
- IIS site/pools that will be stopped and prior states;
- physical-check policy;
- post-copy settings sync and any explicit skip;
- allowlist evidence;
- plan creation/expiry time.

APPLY requires the exact preview fingerprint, a non-expired plan and explicit destructive confirmation (source spec used typed `COPY`). Any catalog/live-state/size/path/allowlist drift requires a fresh preview.

## 6. Backup sequence and invariants

[CONFIRMED] Source behavior creates one compressed copy-only/checksum source backup per selected database and verifies it before destination work. Each existing destination database receives its own verified copy-only safety backup before overwrite.

[PROPOSED] Hard gates:

1. source backup verified before any destination outage/mutation;
2. every destination can read the source backup before its IIS/database state changes;
3. existing destination safety backup completes and verifies before destructive restore;
4. run manifest records source/safety backup file, database, sizes and verification state;
5. a failed backup/verify prevents the corresponding restore.

**The operation never deletes its safety backup.** Retention/cleanup belongs to a separately approved housekeeping process and may not be invoked from the copy run. In particular, failure cleanup cannot remove the newest safety backup.

## 7. Filesystem and permission safety

[PROPOSED] Backup/data/log folders are resolved from local SQL metadata/catalog policy and must be local approved paths. Reject caller-provided arbitrary paths, UNC/device paths not explicitly supported, traversal and reparse-point escapes where paths are under engine-controlled roots.

Temporary grants to destination SQL service accounts are least-privilege/read-only where feasible, recorded, and removed in `finally` after no destination still needs the shared source backup. Existing ACLs are preserved/restored rather than replaced wholesale.

[V] Real SQL service identities/ACL behavior require pilot proof.

## 8. Destination outage and restore

[CONFIRMED] For each destination, remember which IIS site/pools were started, stop them before destructive database work, and restore their prior started state in `finally`.

Per database:

1. verify destination eligibility/live preconditions;
2. take/verify safety backup if destination exists;
3. acquire exclusive/single-user state with bounded rollback of sessions;
4. restore with `REPLACE` only for the exact allowlisted destination;
5. MOVE files only to approved destination default folders;
6. restore multi-user state;
7. run configured physical check;
8. report exact final DB state.

A failure on one destination stops later work for that destination but must not prevent safe restoration of its IIS state or reporting of other destinations where independence is proven.

## 9. Failure recovery

[PROPOSED] Result/run manifest must distinguish states such as:

- no destination mutation started;
- destination safety backup verified, restore not started;
- restore in progress/failed;
- destination online/multi-user after restore;
- destination requires manual recovery;
- safety backup path/identity to use for recovery.

A tested **restore-from-safety-backup** path is a prerequisite to enabling destructive APPLY. It follows the same allowlist/confirmation/single-user/MOVE/verify rules and never deletes the safety backup after use.

## 10. Post-copy settings and customer-data risk

[CONFIRMED] Copied WFM settings can retain source host/token/URL values. `DATABASE_CONTENT_SYNC` is the portable reconciliation path.

[PROPOSED] Settings sync is mandatory by default and part of the confirmed plan. If owner policy permits skip, the plan/result displays a high-visibility warning that destination settings can still point to the source. Skip cannot be implicit.

[PENDING] Whether destination Keycloak must be reset/refreshed after copy remains separate and must be decided before production use.

## 11. Disk-space and plan-expiry gates

[PROPOSED] Before APPLY compute free-space requirements using actual backup/data/log estimates plus an approved safety multiplier (studio reference was 1.25). Refuse when any affected volume lacks margin.

Re-check free space immediately before each large operation. Do not rely on preview-only free-space state for a long multi-destination run.

Plan validity is bounded (source studio reference 60 minutes); exact V1 value is policy/contract data, not a magic fallback silently chosen by code.

## 12. SQL command safety

[PROPOSED] SQL instance/database identities come from verified allowlists and are safely quoted; data values use parameters. Backup/restore commands use exact local files produced/verified by the operation. No arbitrary SQL or path text from UI enters a command.

Connection encryption/certificate policy and permissions are `[V]`/common SQL runtime gates.

## 13. Backup/restore relationship to housekeeping

Source-copy backup and destination safety backup are evidence/recovery artifacts, not scratch files.

[PENDING] Long-term retention may be seven days or another approved value, but deletion is performed by a separate retention mechanism that understands recovery invariants. `DATABASE_COPY` itself never cleans its safety backup, including on success.

## 14. Result and secret/data handling

Results contain instance/database identifiers, stage/status, counts/sizes and backup file identities only. No table contents, connection strings containing secrets, copied values or customer rows.

Backups themselves contain customer/secret-bearing data and must be ACL-protected. They never leave the machine through this engine.

## 15. Required tests

Runner/integration coverage must include:

- source=destination refused;
- disabled/foreign-machine instance refused;
- destination without explicit allowlist refused;
- allowlisted pair accepted and evidence shown in plan;
- database subset outside allowlist refused;
- source backup create/checksum/verify and one-backup-per-source-database behavior;
- destination readability check before outage;
- safety backup required/verified before overwrite;
- injected failure proves safety backup remains and is never deleted;
- low disk margin refusal and recheck;
- restore with multi data/log files and approved MOVE paths;
- single-user/multi-user transitions and recovery after injected failure;
- physical check policy;
- MWA stop/start preserving prior site/pool state;
- settings sync default/explicit skip warning;
- per-destination continuation isolation;
- plan expiry and fingerprint/live-state drift refusal;
- restore-from-safety-backup end to end;
- temporary ACL/grant cleanup without deleting backup;
- no customer data/secret in result/log.

[V] Real large databases, service-account permissions, antivirus, storage throughput, backup compression/checksum and recovery timing.

## 16. Open questions

1. [PENDING] Exact destination-allowlist schema and ownership.
2. [PENDING] Cross-machine archive/copy is not this local engine until separately approved.
3. [PENDING] External safety-backup retention policy; engine deletion remains prohibited.
4. [PENDING] Whether settings-sync skip is permitted in production.
5. [PENDING] Destination Keycloak treatment.
6. [V] Required operator/runtime SQL permissions and production encryption/certificates.

## 17. Entry gate for the code PR

The code PR may start when:

- destination allowlist has an approved catalog contract and tests;
- safety-backup non-deletion is enforced mechanically;
- restore-from-safety-backup is designed and testable before destructive APPLY is enabled;
- all used database/policy columns are verified;
- disk/expiry/confirmation gates are explicit;
- post-copy settings behavior is explicit;
- real-server permissions/scale remain `[V]`, not inferred from LocalDB.
