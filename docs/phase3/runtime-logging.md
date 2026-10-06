# Phase 3 - Runtime logging foundation

**Date:** 2026-10-06
**Status:** [PROPOSED] implementation of the accepted ADR-0007 logging contract, pending CI evidence.

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

`runtime/Sisqual.Runtime.Logging.psm1` provides four runtime functions:

- `Get-SisqualRuntimeLogDefaults`;
- `Initialize-SisqualRuntimeLog`;
- `Invoke-SisqualRuntimeLogRetention`;
- `Write-SisqualRuntimeLog`.

The logger writes one UTF-8 file without BOM per UTC day using the stable name `<prefix>-yyyy-MM-dd.log`.

Retention is based only on files that match the configured logger prefix and date pattern. It never deletes unrelated files from the configured directory.

Writes are protected by an in-process monitor to prevent two runtime callers from interleaving one record. This is an internal implementation detail and does not change the V1 single-operator contract.

## Secret safety

[PROPOSED] The logger applies defence in depth instead of treating redaction as permission to pass secrets to it:

1. callers must not pass decrypted secrets or secret-bearing objects;
2. common secret-bearing property names such as password, token, cookie, authorization, credential, private key and connection string are replaced with `[REDACTED]`;
3. common inline assignments such as `token=...` and `password=...` are redacted;
4. bearer tokens are redacted;
5. embedded newlines are normalized so one call produces one physical log record.

This does not make arbitrary secret text safe to log. The primary rule remains that callers never supply secrets to the logger.

## Validation

`tests/Unit/Test-RuntimeLogging.ps1` covers every exported function and checks:

- exact ADR defaults;
- directory creation;
- configurable retention and boundary handling;
- unrelated files are preserved;
- daily file naming and rotation;
- sensitive field and inline token redaction;
- no supplied test secret appears in the file;
- one physical record per write;
- UTF-8 without BOM;
- invalid event codes and unsafe property names fail closed.

`.github/workflows/phase3-runtime-logging.yml` runs the test on `windows-2022` and `windows-2025` using the pinned portable PowerShell 7.6.6 archive and verifies its repository-approved SHA-256 before execution.

## Follow-up

[PENDING] Integrate this logger into the Phase 3 startup/bootstrap runtime after this slice is accepted.

[PENDING] The future engine adapter must write normalized operation lifecycle/result events without passing decrypted secret values to this API.

This PR deliberately does not decide the final REST API or UI representation of logs.
