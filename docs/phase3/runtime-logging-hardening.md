# Phase 3 - Runtime logging hardening

**Date:** 2026-10-06
**Status:** [PROPOSED] follow-up to the merged runtime logging foundation, pending CI evidence and review.

## Reason for this follow-up

PR #49 was merged before its final Codex review findings were addressed. The review identified six effective issues in the merged logger:

1. a complete `Authorization: Basic <credential>` value was not fully consumed by redaction;
2. quoted sensitive keys in serialized text such as JSON could bypass assignment redaction;
3. a configurable log path was canonicalized but not constrained to an approved local root;
4. retention ran only during initialization, so a long-running process could exceed the configured window after daily rollover;
5. retention date parsing used UTC assumptions in a way that could shift the parsed calendar day on hosts west of UTC;
6. the dedicated logging workflow did not run on future pull requests or `main` changes.

These are fixes to an accepted contract and security rules; they do not change the operational scope.

## Changes

[PROPOSED] `runtime/Sisqual.Runtime.Logging.psm1` now:

- redacts complete Authorization/Cookie header-shaped values through the end of the logical source line;
- redacts both Bearer and Basic scheme credentials;
- accepts quoted sensitive assignment keys so common serialized JSON forms are redacted;
- constrains `LogRoot` to an explicitly approved absolute local root and rejects UNC/device roots;
- defaults the approved root to `C:\SISQUALWFM\WFM.Logs` while keeping the ADR-0007 log folder default below it;
- compares retention filenames as `DateOnly`, removing local timezone conversion from the decision;
- reruns retention automatically when a write crosses into a later UTC day;
- serializes retention and append operations with the existing in-process monitor.

The primary security rule is unchanged: callers must never intentionally pass decrypted secrets to the logger. Redaction remains defence in depth.

## Validation

`tests/Unit/Test-RuntimeLogging.ps1` adds checks for:

- an out-of-root local path being rejected;
- a UNC root being rejected;
- complete Basic Authorization header redaction;
- quoted JSON sensitive-key redaction;
- no supplied marker surviving the log write;
- automatic retention on UTC daily rollover.

`.github/workflows/phase3-runtime-logging.yml` is changed so the tests run for matching pull requests and matching changes on `main`, not only on the original feature branch.

The workflow also reruns the same unit suite after moving the disposable Windows runner to `SA Eastern Standard Time` (UTC-3), specifically to validate that date-based retention is independent of the host local timezone.

## Boundaries

This PR does not change the Phase 3 bootstrap, manifest verification, SQLite provider, credential package, Pode adapter or any engine.

[PENDING] Windows 2022/2025 workflow evidence on the corrected implementation.
[PENDING] Codex review of the corrected implementation.
