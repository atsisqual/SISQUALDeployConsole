# Phase 3 - Runtime logging foundation

**Date:** 2026-10-06
**Status:** [CONFIRMED] implementation validated on Windows Server 2022 and 2025 under portable PowerShell 7.6.6. PR #49 remains unmerged.

## Scope

This is the first product-runtime slice of Phase 3. It implements only local text logging and retention. It does not implement startup, package signature verification, SQLite access, credentials, Pode, REST routes or engines.

## Accepted requirements

[CONFIRMED] ADR-0007 requires:

- plain text logs;
- configurable log directory;
- default `C:\SISQUALWFM\WFM.Logs\SISQUALDeployManagement\`;
- one log file per day;
- retention of 30 days by default;
- configurable retention;
- no secrets or tokens in logs;
- operation history is eventually written to these text logs.

## Implementation

[CONFIRMED] `runtime/Sisqual.Runtime.Logging.psm1` provides four runtime functions:

- `Get-SisqualRuntimeLogDefaults`;
- `Initialize-SisqualRuntimeLog`;
- `Invoke-SisqualRuntimeLogRetention`;
- `Write-SisqualRuntimeLog`.

[CONFIRMED] The logger writes one UTF-8 file without BOM per UTC day using the stable name `<prefix>-yyyy-MM-dd.log`.

[CONFIRMED] Retention is based only on files that match the configured logger prefix and date pattern. It does not delete unrelated files from the configured directory.

[CONFIRMED] Writes are protected by an in-process monitor so concurrent runtime callers do not interleave one record. This does not change the V1 single-operator contract.

## Secret safety

[CONFIRMED] The implementation applies defence in depth instead of treating redaction as permission to pass secrets to it:

1. callers must not pass decrypted secrets or secret-bearing objects;
2. common secret-bearing property names such as password, token, cookie, authorization, credential, private key and connection string are replaced with `[REDACTED]`;
3. common inline assignments such as token and password assignments are redacted;
4. bearer tokens are redacted;
5. embedded newlines are normalized so one call produces one physical log record.

[CONFIRMED] The accepted unit run verifies that the supplied test secret values are absent from the resulting log record.

This does not make arbitrary secret text safe to log. The primary rule remains that callers never supply secrets to the logger.

## Accepted validation

[CONFIRMED] Dedicated workflow `phase3-runtime-logging`, workflow ID `375929890`, run `37395610886`, run number `2`, attempt `1`, commit `013bbca2abba690f1f1aef226d1231bc67c75a54`, completed successfully on both Windows images.

| OS | Job ID | Runner ID | Result | Unit checks |
|---|---:|---:|---|---:|
| windows-2022 | `112050726055` | `1000000675` | success | 20/20 PASS |
| windows-2025 | `112050726205` | `1000000676` | success | 20/20 PASS |

[CONFIRMED] Each job downloaded the pinned PowerShell 7.6.6 archive, verified SHA-256 `02FE458BE20493FBDF43F61EA20610B811EE6C738AB1676C61B9CFCD1A33C860`, and executed the tests with that portable `pwsh.exe`.

[CONFIRMED] Repository CI run `37395616846`, CI number `133`, job `112050743640`, passed PowerShell parsing, ASCII/LF policy and the secret scan on the corrected head.

The dedicated workflow intentionally produces no artifact; its evidence is the immutable workflow/job log plus the run ledger under `docs/phase3/evidence/`.

## Historical first run

[CONFIRMED] Dedicated run `37395436558` on initial commit `fb23127738d22c087bf8560ba6329f82e89e7b43` also passed the runtime logging tests on both Windows images.

[CONFIRMED] The normal repository CI run `37395461841`, job `112050250528`, then rejected the test source because a deliberately literal password-shaped fixture matched the repository secret scanner. Parser and ASCII/LF checks passed. The scanner was not weakened.

[CONFIRMED] Commit `013bbca2abba690f1f1aef226d1231bc67c75a54` constructs that synthetic fixture at runtime instead, preserving the redaction test while satisfying the repository rule that secret-shaped literals must not be committed.

## Follow-up

[PENDING] Integrate this logger with the real Phase 3 bootstrap/runtime after this slice is reviewed and integrated.

[PENDING] The future engine adapter must write normalized operation lifecycle/result events without passing decrypted secret values to this API.

[PENDING] Final REST/UI exposure of log information is outside this PR.
