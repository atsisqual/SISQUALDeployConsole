# STORAGE_SIZE_SCAN port brief

**Status:** [PROPOSED]
**Task:** T12 / M3.7
**Date:** 2026-10-10

This brief defines the implementation gate for `STORAGE_SIZE_SCAN`. It is documentation only.

## 1. Sources and evidence boundary

[CONFIRMED] Checked now against `main`:

- `docs/engines/STORAGE_SIZE_SCAN.md` documents source-era `STORAGE_SIZE_SCAN.ps1`, action `STORAGE_SIZE_SCAN` and eight `app.HousekeepingPolicy` rows.
- `app.HousekeepingPolicy` is a global carried table and is present in `tests/Fixtures/carried-schema.json`; historical snapshot/plan tables are excluded from the portable catalog.
- The host class is `OBSERVATIONAL`: scanning may read file-system/SQL metadata and emit result/history artifacts but must not clean, move or delete managed files.

[NOT VERIFIED] This brief did not scan production-sized roots. Hundreds-of-gigabytes/millions-of-files timing and real ACL/error distribution remain `[V]`.

## 2. Purpose and class

[CONFIRMED] The engine measures bytes and file counts for configured housekeeping storage roots so the operator can compare usage with policy ceilings. It does not perform housekeeping cleanup.

[CONFIRMED] No credential references; no instance selection in the source action; documented timeout is 300 seconds.

## 3. Policy model and source-era special cases

[CONFIRMED from the current specification] Reference policies include application logs, IIS logs, config backups, clone snapshots, database-copy artifacts, SQL native backup roots, worker temp and old storage snapshots.

[PROPOSED] Code consumes enabled `app_HousekeepingPolicy` rows rather than hard-coding the reference count/ceilings. Policy-specific semantics that truly cannot be represented by generic root/pattern fields must be explicit named handlers with tests, never inferred from English policy names without evidence.

[CONFIRMED] Two source-era concepts do not port as managed storage targets:

- the hard-coded old management-console pseudo-instance;
- `STORAGE_SNAPSHOTS`, which measured a central history table rather than files.

Report `NOT_APPLICABLE` for an explicitly obsolete policy where needed; do not fabricate a filesystem path.

## 4. Path expansion and containment

[PROPOSED] Expand root templates only with approved local machine/instance/temp tokens. Before enumeration:

- reject device/UNC/network paths unless a future owner decision explicitly allows remote storage;
- reject unresolved required tokens;
- canonicalize lexical roots;
- do not follow symbolic links/junctions outside the approved root;
- detect loops/repeated directory identities and never enumerate forever.

Wildcards expand only within an approved fixed parent root; a wildcard result cannot escape the parent through reparse points.

## 5. Streaming enumeration

[CONFIRMED, source-era defects] The old walk silently ignored errors and materialized every file object before summing.

[PROPOSED] Stream enumeration. Maintain only counters/aggregates:

- bytes successfully measured;
- file count successfully measured;
- unreadable directory/file count;
- skipped-reparse/loop count;
- elapsed time and completion/partial flag.

Do not retain all file paths in memory or return a file inventory. Individual inaccessible paths should not flood logs; emit bounded examples plus totals.

## 6. Application and IIS log split

[CONFIRMED] The reference model distinguishes application logs from the per-host `IIS` subfolder.

[PROPOSED] Tests define this split precisely: application-log measurement excludes the configured IIS subtree but counts other matching files/loose files according to policy; IIS measurement includes only its approved subtree. Exclusion is path-aware, not a substring match.

## 7. SQL native backup roots

[CONFIRMED] `SQL_NATIVE_DATABASE_COPY` resolves each local SQL instance's default backup folder.

[PROPOSED] Query only enabled local instance SQL targets derived from the verified catalog. Resolve each distinct physical backup root once for aggregate scanning, while result presentation may associate the measured root with each instance that shares it. Never double-count the same physical root in aggregate totals.

A SQL instance whose default backup path cannot be resolved yields a warning/unknown root, not a guessed path.

[PENDING] Production SQL connection encryption/certificate policy follows the common local SQL contract and must be fixed before `[V]` acceptance.

## 8. Time budget and partial results

[PROPOSED] Honor the engine deadline/time budget during traversal, not only between policies. On expiry/cancellation:

- stop scheduling/enumerating new work promptly;
- return measured bytes/files so far;
- mark the policy `PARTIAL` with elapsed time and skipped/unreadable counts;
- do not present partial bytes as a complete value for ceiling compliance.

[PENDING] A future explicit operator option may request an unbounded/full scan, but default execution remains bounded.

## 9. Ceiling units and evaluation

[PENDING] Existing specification recommends binary GiB for `MaximumTotalSizeGB`. Until decided, result must retain raw bytes and the configured numeric ceiling separately; UI/engine must not silently switch between decimal and binary interpretation.

[PROPOSED] Compliance (`WITHIN_LIMIT`, `OVER_LIMIT`, `UNKNOWN/PARTIAL`) is derived only for complete measurements under the approved unit definition.

## 10. Persistence/output

[CONFIRMED] The old APPLY wrote central snapshot rows; that table is excluded from the portable catalog.

[PROPOSED] Primary output is the structured engine result. If history is retained, append one bounded JSON record per policy/root measurement under the approved log/history root and maintain bounded retention/latest view. This is observation history, not a managed-target mutation.

[PENDING] Whether persistent history is required; no database persistence ports forward.

## 11. Side effects and backup

Managed side effects: none. Read-only directory/SQL metadata access plus ordinary engine result/log/history output.

Backup/restore: not applicable.

## 12. Required tests

Runner tests must cover:

- carried policy parsing and enabled filtering;
- missing root -> complete zero, where source semantics say so;
- large synthetic tree without materializing an in-memory file list;
- file pattern filtering;
- application-vs-IIS log subtree split;
- wildcard roots under a fixed parent;
- `..`, absolute/device/UNC injection and reparse escape;
- symbolic-link/junction loop;
- unreadable folder/file counted and reported, not silently ignored;
- deadline/cancellation -> `PARTIAL` with no false ceiling conclusion;
- distinct SQL backup roots scanned once and shared-root per-instance presentation;
- SQL backup-root resolution failure warning;
- obsolete management-console/storage-snapshot behavior omitted/not applicable;
- no cleanup/delete/move operation under preview or apply-like invocation;
- deterministic result ordering;
- optional history output atomic/bounded if implemented.

[V] Real huge roots, multi-volume behavior and completion time on supported servers.

## 13. Open questions

1. [PENDING] Persist bounded measurement history or result/log only.
2. [PENDING] Explicit full-scan option beyond default deadline.
3. [PENDING] Binary GiB versus decimal GB ceiling semantics.
4. [PENDING] Whether any legitimate policy root may be remote; default brief rejects network paths.

## 14. Entry gate for the code PR

The code PR may start when:

- exact carried policy columns/token grammar are bound to tests;
- policy-specific handlers are justified by source evidence;
- path/reparse/loop behavior is explicit;
- enumeration is streaming and deadline-aware;
- SQL backup-root deduplication is tested;
- ceiling units and optional history persistence are decided or left as raw-bytes-only output;
- no cleanup side effect exists in the engine path.
