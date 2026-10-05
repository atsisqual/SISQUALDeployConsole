# Phase 1C local web security evidence ledger

**Branch:** `spike/phase1c-local-web-security`
**Base main:** `ad598215fe3ab0bc715a797a37e2bcf9331eaa56`
**Workflow:** `phase1c-local-web-security`
**Status:** [PENDING] waiting for an executed two-OS Windows run.

## Evidence rule

Every execution record must preserve:

- workflow ID;
- run ID and run number;
- every `run_attempt`;
- exact head commit SHA and event;
- every job ID;
- runner label, runner ID and runner name;
- created, started and completed UTC timestamps;
- conclusion of every job and relevant step;
- artifact name, artifact ID, size, expiry and SHA-256 digest;
- reason for retry, cancellation or supersession;
- classification as infrastructure, harness or technical result.

A result is accepted only by the exact tuple `run ID + attempt + commit SHA` and only when both Windows jobs execute every required security gate.

## Required reports

The workflow must produce one JSON report for each runner:

- `report-windows-2022.json`;
- `report-windows-2025.json`.

Reports use schema `SISQUAL_PHASE1C_LOCAL_WEB_SECURITY_V1` and must contain no bootstrap/session/CSRF token values.

## Required gates

- `SERVER_READY`;
- `LOOPBACK_ONLY`;
- `SESSION_REQUIRED`;
- `HOST_REJECTED`;
- `BOOTSTRAP_ACCEPTED`;
- `COOKIE_HTTPONLY`;
- `COOKIE_SAMESITE_STRICT`;
- `COOKIE_PATH_ROOT`;
- `BOOTSTRAP_SINGLE_USE`;
- `SESSION_ACCEPTED`;
- `ORIGIN_REJECTED`;
- `CSRF_REQUIRED`;
- `CSRF_WRONG_REJECTED`;
- `MUTATION_ACCEPTED`;
- `CORS_PREFLIGHT_DENIED`;
- security-header gates for CSP, nosniff, referrer policy, no-store and cross-origin isolation headers;
- `SERVER_STOPPED`;
- `SERVER_RESTARTED`;
- `SESSION_INVALID_AFTER_RESTART`;
- `LOGOUT_INVALIDATES`;
- `SESSION_INVALID_AFTER_LOGOUT`;
- `NO_TOKEN_LOG_LEAK`.

## Historical-source evidence

Reference web behavior was inspected at `atsisqual/SISQUALManagementConsole` commit `9756ba956842884fabcf25b82c4fbf1d11cf56bd`:

- `src/SISQUAL.Management.Web/Program.cs`;
- `src/SISQUAL.Management.Web/appsettings.json`;
- `Install.ps1` Windows/anonymous authentication configuration;
- `tests/Test-WebProject.Static.ps1`.

No source text or secret value from the reference repository is copied into this evidence directory.

## Pode evidence

Pode 2.14.1 upstream tag resolves to commit `42faafcbd0edf2ffcabd5011a1b03dfbc00c28c4`.

The exact 2.14.1 public session/cookie API was inspected before the spike. SameSite is not exposed by the built-in session/cookie parameters, so the candidate emits an explicit application session cookie with `SameSite=Strict` rather than treating Pode's unrelated `Strict` signing option as SameSite.

## Acceptance

[PENDING] No technical PASS or FAIL is recorded until the workflow actually executes the probes. A queued/cancelled job with no runner or zero security steps is infrastructure evidence only.

After an executed run, create:

`docs/phase1/evidence/phase1c-local-web-security-<run-id>/`

with a run README plus the exact secret-safe JSON reports, and update `docs/phase1/phase1c-local-web-security.md`.
