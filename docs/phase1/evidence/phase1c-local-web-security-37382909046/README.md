# Phase 1C local web security - accepted run 37382909046

**Workflow:** `phase1c-local-web-security`
**Workflow ID:** `375855729`
**Run ID:** `37382909046`
**Run number:** `8`
**Attempt:** `1`
**Event:** `push`
**Tested commit:** `bee976eebf98257d39005020c264db769c7ba68c`
**Conclusion:** [CONFIRMED] `success`
**Created:** `2026-10-05T22:30:26Z`
**Completed:** `2026-10-05T22:34:25Z`

This is the accepted technical-evidence run for the corrected Phase 1C local browser/HTTP boundary. It replaces the cookie-session model that was superseded after security review.

## Security-review fixes exercised by this run

[CONFIRMED] PR review comment `4189467569` identified the cross-port cookie problem. The accepted design emits no session cookie. Bootstrap returns a random session credential that the UI must attach explicitly as `X-SISQUAL-Session`; the server keeps only its SHA-256 hash and expiry.

[CONFIRMED] PR review comment `4189467573` identified incomplete output-capture assurance. The accepted harness requires `OUTPUT_CAPTURE_COMPLETE` before `NO_TOKEN_LOG_LEAK` can pass.

## Windows Server 2022

- job ID: `112009129958`
- runner label: `windows-2022`
- runner: `GitHub Actions 1000000576`
- runner ID: `1000000576`
- job created: `2026-10-05T22:30:38Z`
- job started: `2026-10-05T22:30:40Z`
- job completed: `2026-10-05T22:33:19Z`
- security probe: `2026-10-05T22:33:02Z` to `2026-10-05T22:33:14Z`, success
- artifact: `phase1c-local-web-security-windows-2022`
- artifact ID: `11375417797`
- artifact size: `1925` bytes
- artifact digest: `sha256:46731edd4c774cd38a65ce9d9141943870e21afc7ab15f601484309d78b022f4`
- artifact created: `2026-10-05T22:33:15Z`
- artifact expires: `2027-01-03T22:30:27Z`
- report: `report-windows-2022.json`

[CONFIRMED] Report schema `SISQUAL_PHASE1C_LOCAL_WEB_SECURITY_V2`, PowerShell `7.6.6`, `PassCount=27`, `FailCount=0`, `Fatal=null`.

## Windows Server 2025

- job ID: `112009129747`
- runner label: `windows-2025`
- runner: `GitHub Actions 1000000577`
- runner ID: `1000000577`
- job created: `2026-10-05T22:30:38Z`
- job started: `2026-10-05T22:30:40Z`
- job completed: `2026-10-05T22:34:24Z`
- security probe: `2026-10-05T22:33:53Z` to `2026-10-05T22:34:18Z`, success
- artifact: `phase1c-local-web-security-windows-2025`
- artifact ID: `11376252062`
- artifact size: `1919` bytes
- artifact digest: `sha256:bd8560ff446a621bd1bb7451ecad76718516c60f35e03d70ae214354461c85fe`
- artifact created: `2026-10-05T22:34:19Z`
- artifact expires: `2027-01-03T22:30:27Z`
- report: `report-windows-2025.json`

[CONFIRMED] Report schema `SISQUAL_PHASE1C_LOCAL_WEB_SECURITY_V2`, PowerShell `7.6.6`, `PassCount=27`, `FailCount=0`, `Fatal=null`.

## Accepted gates

Both systems passed all 27 gates:

- `SERVER_READY`;
- `LOOPBACK_ONLY`;
- `SESSION_REQUIRED`;
- `HOST_REJECTED`;
- `BOOTSTRAP_ACCEPTED`;
- `NO_SESSION_COOKIE`;
- `BOOTSTRAP_SINGLE_USE`;
- `WRONG_SESSION_REJECTED`;
- `SESSION_ACCEPTED`;
- `ORIGIN_REJECTED`;
- `CSRF_REQUIRED`;
- `CSRF_WRONG_REJECTED`;
- `MUTATION_ACCEPTED`;
- `CORS_PREFLIGHT_DENIED`;
- CSP, nosniff, no-referrer, no-store, COOP and CORP header checks;
- `SERVER_STOPPED`;
- `SERVER_RESTARTED`;
- `SESSION_INVALID_AFTER_RESTART`;
- `LOGOUT_INVALIDATES`;
- `SESSION_INVALID_AFTER_LOGOUT`;
- `OUTPUT_CAPTURE_COMPLETE` with four captured stdout/stderr files and zero capture errors;
- `NO_TOKEN_LOG_LEAK`.

## Acceptance boundary

[CONFIRMED] The corrected non-ambient session-header boundary is technically viable on the tested GitHub-hosted Windows Server 2022 and Windows Server 2025 images.

[PROPOSED] This does not itself approve the V1 browser/session contract.

[PENDING] The actual vanilla-JS bootstrap flow must keep session/CSRF values only in JavaScript memory, attach the session header explicitly, post the fragment bootstrap value and remove the fragment.

[PENDING] Session lifetime/idle extension remains a product decision.

[PENDING] Operation idempotency and controlled shutdown with active operations remain the next separate Phase 1C task. `SERVER_STOPPED` is not graceful-shutdown evidence.
