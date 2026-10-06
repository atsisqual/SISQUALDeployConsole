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
- fixed bootstrap event IDs and fixed messages, rather than arbitrary payload logging.

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

`Start.cmd` performs no network access, package installation or fallback to a machine-installed PowerShell.

## Tests

The dedicated workflow `phase3-runtime-bootstrap` runs on `windows-2022` and `windows-2025` and:

1. downloads the exact PowerShell 7.6.6 win-x64 ZIP used by Phase 1A;
2. verifies SHA-256 `02FE458BE20493FBDF43F61EA20610B811EE6C738AB1676C61B9CFCD1A33C860` before use;
3. materializes it under `runtime\pwsh\` in the runner workspace;
4. tests the bootstrap helpers and retention policy;
5. proves that `Start.cmd` returns 20 with no manifest;
6. adds a disposable dummy manifest and proves that `Start.cmd` returns 21 rather than progressing without a verifier;
7. uploads a JSON test report and secret-free bootstrap log as evidence.

## Not in this PR

- manifest canonicalization/signature/hash verification - B6.2 / subsequent Phase 3 integration;
- rollback counter - decision/integration work after the manifest contract is finalized;
- managed SQLite provider and read-only catalog factory - PR #36 then Phase 3;
- machine-key use or credential import;
- Pode/local web adapter;
- operation coordinator production port;
- engines.

## Follow-up order

1. integrate the approved B6.2 verifier into the startup gate;
2. integrate the approved SQLite provider and open only the verified per-machine catalog read-only;
3. wire machine identity and credential-package validation;
4. promote the already validated Phase 1C web-security and operation-coordinator behavior into production runtime code;
5. start engine wave 1.
