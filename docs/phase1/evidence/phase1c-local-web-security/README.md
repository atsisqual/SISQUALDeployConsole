# Phase 1C local web security evidence ledger

**Branch:** `spike/phase1c-local-web-security`
**Base main:** `ad598215fe3ab0bc715a797a37e2bcf9331eaa56`
**Workflow:** `phase1c-local-web-security`
**Workflow ID:** `375855729`
**Status:** [CONFIRMED] accepted technical run `37381402897` / attempt `1` / commit `9c27190bc1616278e59de5391425f66ea72fa747` passed on Windows 2022 and 2025.

## Evidence rule

Every execution record preserves workflow/run/attempt/commit, job and runner identifiers, UTC timestamps, artifacts and hashes, and a classification as infrastructure, harness or technical result. A technical result is accepted only when both Windows jobs execute every required security gate.

## Run history

### Run `37381249793` - superseded before probe execution

- run number `1`, attempt `1`;
- commit `454f12f680a86036f2296ce785ed3f2cd1eff98c`;
- created `2026-10-05T22:15:13Z`, completed/cancelled `2026-10-05T22:16:26Z`;
- windows-2025 job `112003514220`, runner `1000000554`;
- windows-2022 job `112003514640`, runner `1000000555`.

[CONFIRMED] Both jobs were cancelled during the pinned-runtime download when a later branch push activated the workflow concurrency policy. The security probe step was skipped. Artifact/summary failures are consequences of cancellation and missing reports, not web-security failures.

### Run `37381372562` - superseded before probe execution

- run number `2`, attempt `1`;
- commit `75e5a6e6d672320f391bca99bba60ae77c9a5b42`;
- created `2026-10-05T22:16:16Z`, completed/cancelled `2026-10-05T22:16:44Z`;
- windows-2025 job `112003982101`, runner `1000000556`;
- windows-2022 job `112003982569`, runner `1000000557`.

[CONFIRMED] Both jobs were cancelled during checkout by the next branch push. Runtime download and security probe were skipped. This is supersession evidence only.

### Run `37381402897` - accepted

- run number `3`, attempt `1`;
- commit `9c27190bc1616278e59de5391425f66ea72fa747`;
- event `push`;
- created `2026-10-05T22:16:32Z`, completed `2026-10-05T22:19:51Z`;
- conclusion `success`.

Windows 2022:

- job `112004092392`;
- runner `GitHub Actions 1000000558`, runner ID `1000000558`;
- artifact `phase1c-local-web-security-windows-2022`, ID `11374356055`;
- size `1859` bytes;
- digest `sha256:12ea9164fb9a66d4c4d04ce0bc5be090bb6b0450db308b8a27b02957d70b4fe8`;
- artifact expires `2027-01-03T22:16:33Z`.

Windows 2025:

- job `112004092351`;
- runner `GitHub Actions 1000000559`, runner ID `1000000559`;
- artifact `phase1c-local-web-security-windows-2025`, ID `11375770246`;
- size `1860` bytes;
- digest `sha256:1b61967c89885f88817f902b1faa15748c25de60d9f8501cd41bc42b41ac964a`;
- artifact expires `2027-01-03T22:16:33Z`.

Full run record and the exact secret-safe reports are under `docs/phase1/evidence/phase1c-local-web-security-37381402897/`.

## Accepted gates

[CONFIRMED] Each accepted report has schema `SISQUAL_PHASE1C_LOCAL_WEB_SECURITY_V1`, PowerShell `7.6.6`, `PassCount=27`, `FailCount=0`, `Fatal=null`.

Both systems passed:

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
- CSP, nosniff, referrer, no-store, COOP and CORP header checks;
- `SERVER_STOPPED`;
- `SERVER_RESTARTED`;
- `SESSION_INVALID_AFTER_RESTART`;
- `LOGOUT_INVALIDATES`;
- `SESSION_INVALID_AFTER_LOGOUT`;
- `NO_TOKEN_LOG_LEAK`.

## Historical-source evidence

Reference web behavior was inspected read-only at `atsisqual/SISQUALManagementConsole` commit `9756ba956842884fabcf25b82c4fbf1d11cf56bd`, including `src/SISQUAL.Management.Web/Program.cs`, `appsettings.json`, IIS authentication setup in `Install.ps1`, and `tests/Test-WebProject.Static.ps1`.

No source text or secret value from the reference repository is copied into this evidence directory.

## Pode evidence

Pode 2.14.1 upstream tag resolves to commit `42faafcbd0edf2ffcabd5011a1b03dfbc00c28c4`.

[CONFIRMED] The inspected 2.14.1 public session/cookie API has no browser SameSite option. The candidate therefore emits `SameSite=Strict` explicitly rather than confusing it with Pode's unrelated `Strict` signing option.

## Acceptance boundary

[CONFIRMED] The tested HTTP/browser boundary is technically viable on the two GitHub-hosted Windows images.

[PROPOSED] Product adoption of the bootstrap/session design still requires reviewer/owner acceptance.

[PENDING] The real browser URL-fragment bootstrap and fragment clearing are not exercised by this backend spike.

[PENDING] Final session lifetime/idle-extension policy remains open.

[PENDING] Operation idempotency and controlled shutdown with active operations are a separate Phase 1C task. The accepted `SERVER_STOPPED` gate is not evidence of graceful shutdown.
