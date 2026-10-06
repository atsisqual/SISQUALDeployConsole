# Phase 3A - runtime bootstrap foundation

**Date:** 2026-10-06
**Status:** [PROPOSED] first product-runtime slice. This PR does not implement package signature verification, catalog access, credentials, Pode or engines.

## Scope

This slice starts the real portable application without crossing unresolved trust boundaries.

It adds:

- root `Start.cmd`;
- `runtime/Start-SisqualDeployConsole.ps1`;
- `runtime/RuntimeBootstrap.ps1`;
- Windows 2022/2025 integration tests using the exact portable PowerShell 7.6.6 ZIP and published SHA-256;
- daily plain-text bootstrap logging and deterministic retention.

## Startup boundary

[CONFIRMED] ADR-0007 requires the package manifest to be verified at startup before the application is allowed to use the catalog or execute operations.

[PROPOSED] Phase 3A therefore uses this order:

1. `Start.cmd` launches only `runtime\pwsh\pwsh.exe`; there is no system-PowerShell fallback.
2. The entry point requires PowerShell 7.6.6 Core x64.
3. The bootstrap log is initialized under the ADR-0007 log policy.
4. `package-manifest.json` must exist.
5. Startup stops fail-closed until the B6.2 package-signature/integrity verifier is integrated.
6. No catalog, credential package, Pode adapter, product module or engine is loaded before that gate.

This deliberately means that the Phase 3A launcher is not yet a usable console. A manifest-present run exits with code 21 until the integrity-verifier PR is integrated.

## Release layout introduced by this slice

```text
Start.cmd
package-manifest.json
runtime/
  Start-SisqualDeployConsole.ps1
  RuntimeBootstrap.ps1
  pwsh/
    pwsh.exe
    ... pinned PowerShell 7.6.6 payload ...
```

[PROPOSED] `runtime\pwsh\` is the V1 release location for the pinned portable PowerShell payload. It is an internal package-layout choice; the public operational contract remains "copy folder, run Start.cmd, install nothing".

## Logging

[CONFIRMED] ADR-0007 requires plain-text logs, default root `C:\SISQUALWFM\WFM.Logs\SISQUALDeployManagement\`, one file per day, retained for 30 days by default, with no secrets or tokens.

Phase 3A implements:

- `SISQUALDeployConsole-YYYY-MM-DD.log`, using the UTC day;
- configurable `-LogRoot` and `-RetentionDays` parameters;
- deletion only of files matching the SISQUAL daily-log naming convention;
- exactly 30 daily files including the current UTC day when the default is used;
- preservation of unrelated files in the log directory;
- fixed bootstrap event IDs and fixed messages, rather than arbitrary payload logging;
- a narrow temporary Win32 append primitive for bootstrap events that guards the directory tree while opening the final file, uses `FILE_FLAG_OPEN_REPARSE_POINT`, denies file sharing during the append, validates the handle-resolved final path, rejects final-file reparse points and rejects files with more than one hard link before any event bytes are written.

The bootstrap append primitive exists only to close the privileged final-file alias/race boundary in this narrow startup slice. It is not intended to replace the hardened runtime logger from PR #52; that logger remains the planned integration target.

The first event vocabulary is intentionally narrow:

- `BOOTSTRAP_STARTED`;
- `HOST_VALID`;
- `MANIFEST_MISSING`;
- `INTEGRITY_VERIFIER_UNAVAILABLE`;
- `BOOTSTRAP_FATAL` reserved for later bootstrap stages.

## Exit codes

| Code | Meaning |
|---:|---|
| 10 | portable PowerShell missing or host version/architecture rejected |
| 11 | text log initialization failed |
| 12 | runtime entry point missing |
| 13 | runtime bootstrap library missing |
| 20 | `package-manifest.json` missing |
| 21 | manifest exists but the B6.2 integrity verifier is not yet integrated |

## Security properties

[PROPOSED] This slice intentionally prefers an unusable fail-closed application over a temporary bypass.

It does not add a development flag and does not provide a route that skips manifest verification. Once B6.2 is integrated, exit 21 is replaced by real signature/hash verification before any further runtime component is loaded.

`-LogRoot` is constrained to the approved fixed-local SISQUAL log tree before create/enumerate/delete/write operations. Existing reparse/junction components are rejected. For each bootstrap event append, the current directory chain and final file are rebound to Win32 handles before the write; a planted daily-log symlink/reparse point, a hard-link alias, or a parent-path replacement cannot be used to redirect privileged event bytes to another file.

Terminal-event log failures do not replace the documented startup result: missing manifest remains exit 20 and verifier-not-integrated remains exit 21, with an additional stderr diagnostic when that final event cannot be recorded.

`Start.cmd` performs no network access, package installation or fallback to a machine-installed PowerShell.

## Tests

The dedicated workflow `phase3-runtime-bootstrap` runs on `windows-2022` and `windows-2025` and:

1. downloads the exact PowerShell 7.6.6 win-x64 ZIP used by Phase 1A;
2. verifies SHA-256 `02FE458BE20493FBDF43F61EA20610B811EE6C738AB1676C61B9CFCD1A33C860` before use;
3. materializes it under `runtime\pwsh\` in the runner workspace;
4. tests the bootstrap helpers and retention policy;
5. proves that an outside log root and a junction escape are rejected without filesystem side effects;
6. proves that predictable final daily-log symlink and hard-link aliases are rejected without modifying their targets;
7. proves that `Start.cmd` returns 20 with no manifest even if the terminal log event fails;
8. adds a disposable dummy manifest and proves that `Start.cmd` returns 21 rather than progressing without a verifier, including when the terminal log event fails;
9. uploads a JSON test report and secret-free bootstrap log as evidence.

[PENDING] The final-file hardening above requires a clean Windows 2022/2025 execution before it becomes accepted evidence. Current GitHub Actions attempts have been terminating before runner allocation, so a red run with zero executed steps is infrastructure evidence only and must not be treated as a product-test failure.

## Not in this PR

- manifest canonicalization/signature/hash verification - B6.2 / subsequent Phase 3 integration;
- rollback counter - decision/integration work after the manifest contract is finalized;
- managed SQLite provider and read-only catalog factory - PR #54 then Phase 3 integration;
- machine-key use or credential import;
- Pode/local web adapter;
- operation coordinator production port;
- engines.

## Follow-up order

1. integrate the approved B6.2 verifier into the startup gate;
2. replace/integrate the narrow bootstrap log writer with the hardened runtime logger from PR #52;
3. integrate the approved SQLite provider and open only the verified per-machine catalog read-only;
4. wire machine identity and credential-package validation;
5. promote the already validated Phase 1C web-security and operation-coordinator behavior into production runtime code;
6. start engine wave 1.
