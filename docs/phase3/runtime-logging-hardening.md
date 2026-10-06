# Phase 3 - Runtime logging hardening

**Date:** 2026-10-06
**Status:** [CONFIRMED] technical hardening validated on Windows Server 2022/2025; fresh Codex review remains [PENDING].

## Reason for this follow-up

PR #49 was merged before its final Codex review findings were addressed. This follow-up keeps the accepted logging contract but closes the security/correctness gaps identified during successive reviews.

The effective findings covered:

1. complete Basic Authorization values and folded header continuations;
2. quoted, escaped, composite and multiline sensitive JSON values;
3. configurable log roots outside an approved local root;
4. reparse/junction traversal at initialization and after initialization;
5. final daily log-file symlinks and stale retention symlinks;
6. hard-linked daily/retention files;
7. check/use races around log-file append and retention deletion;
8. directory-creation races while building a missing log-root tree;
9. retention rollover/date behavior, including hosts west of UTC and future event timestamps;
10. dedicated workflow coverage for future matching PR/main changes and PowerShell 7 use.

These are hardening changes to accepted requirements; they do not add product scope.

## Current implementation

[CONFIRMED] `runtime/Sisqual.Runtime.Logging.psm1` now:

- keeps the ADR-0007 default `C:\SISQUALWFM\WFM.Logs\SISQUALDeployManagement` below the approved default root `C:\SISQUALWFM\WFM.Logs`;
- rejects log roots outside the approved absolute local tree and rejects UNC/device roots;
- rejects reparse points/junctions in approved/log-root components;
- creates missing log-root components root-to-leaf while already validated ancestor directory handles remain open without delete sharing;
- opens final append/delete targets with Win32 handles and `FILE_FLAG_OPEN_REPARSE_POINT`;
- validates the handle-resolved final path rather than trusting only pathname checks;
- refuses daily/retention files whose opened handle reports `NumberOfLinks != 1`, rejecting NTFS hard-link aliases;
- performs the short append/delete operation without file sharing so the validated target cannot acquire/reuse an alternate link during that operation;
- redacts Basic/Bearer credentials, Authorization/Cookie headers and sensitive assignment fields;
- conservatively redacts the remainder of a field after a sensitive serialized JSON key, covering scalar, escaped, composite and multiline values;
- normalizes embedded CR/LF so one event remains one physical log record;
- writes UTF-8 without BOM;
- compares retention filenames as `DateOnly`;
- bases automatic retention on wall-clock UTC, never on a caller-supplied event timestamp;
- reruns retention on a later wall-clock UTC day under the existing in-process monitor;
- only removes files that match the logger-owned prefix/date naming rule.

The primary security rule is unchanged: callers must never intentionally pass decrypted secrets to the logger. Redaction remains defence in depth.

## Accepted functional evidence

Exact tested functional commit: `5124d632f4c3beb7c861fceefc04d07aaa288a2d`.

Dedicated workflow: `phase3-runtime-logging`

- workflow id: `375929890`;
- run: `37428570341`;
- run number: `17`;
- conclusion: SUCCESS.

Windows Server 2022:

- job `112153789674`;
- normal suite: 47/47 PASS;
- UTC-3 rerun (`SA Eastern Standard Time`): 47/47 PASS.

Windows Server 2025:

- job `112153789424`;
- normal suite: PASS;
- UTC-3 rerun: PASS.

The 47 checks include the hard-link append/retention cases and guarded nested-directory creation added for the last two Codex findings.

[CONFIRMED] CI on the same functional commit:

- run `37428570416`;
- CI #166;
- job `112153789118`;
- PowerShell 7 parser PASS;
- ASCII/LF PASS;
- secret scan PASS.

[CONFIRMED] repository-wide `tools-tests` run `37428570421` (#66) also completed SUCCESS on the same functional commit.

[PENDING] fresh Codex security review of the final corrected head. Earlier findings remain preserved as history but are superseded by the current implementation where their lines are outdated.

## Historical evidence that must remain preserved

[CONFIRMED] Earlier green runs are not promoted over this final functional commit because later security review added stronger requirements.

[CONFIRMED] Run `37428133265` (#16) failed before the security cases because the first guarded-directory implementation attempted `CreateDirectoryW` on the existing drive root (`C:\`). The strategy was retained; the implementation was corrected to create only missing components and immediately open/validate every component while ancestor guards remain held.

## Workflow

`.github/workflows/phase3-runtime-logging.yml` runs for matching pull requests and matching changes on `main`.

The same suite is rerun after moving the disposable Windows runner to `SA Eastern Standard Time` (UTC-3), with the wrapper and test process both using PowerShell 7.

## Boundaries

This PR does not change the Phase 3 bootstrap, manifest verification, SQLite provider/catalog factory, credential package, Pode adapter or any engine.

No merge is requested by this document.
