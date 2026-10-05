# Phase 1C - Local web security spike

**Date:** 2026-10-05
**Status:** [PROPOSED] corrected non-ambient session candidate under two-OS validation. The earlier cookie model is superseded.
**Branch:** `spike/phase1c-local-web-security`
**Base:** `main` at `ad598215fe3ab0bc715a797a37e2bcf9331eaa56`.

Tags: `[CONFIRMED]` verified source or execution evidence; `[PROPOSED]` candidate design; `[PENDING]` decision/evidence still required; `[V]` target/sandbox validation.

## 1. Scope

This spike covers the browser/HTTP part of Phase 1C:

- loopback-only listener;
- one-time bootstrap and in-memory session;
- CSRF protection;
- exact Host and Origin allowlists;
- CORS denial;
- browser security headers and CSP;
- logout and process-restart session invalidation;
- fail-closed token-log observation.

[PENDING] Operation idempotency, active-operation shutdown and cancellation semantics are a separate Phase 1C task. Listener removal after forced process termination is not graceful-shutdown evidence.

## 2. Historical web interface baseline

Reference repository: `atsisqual/SISQUALManagementConsole`, read-only snapshot `9756ba956842884fabcf25b82c4fbf1d11cf56bd`.

[CONFIRMED] `src/SISQUAL.Management.Web/Program.cs` is ASP.NET Core/Blazor with Negotiate authentication and explicit `Management.View`, `Management.Operate` and `Management.Administer` policies.

[CONFIRMED] The old pipeline uses authentication, authorization and ASP.NET antiforgery. Non-development mode enables HSTS. HTML responses use no-store/no-cache behavior.

[CONFIRMED] `Install.ps1` disables anonymous IIS authentication and enables Windows Authentication. The old boundary is IIS + Windows/Negotiate, not a portable loopback process.

[CONFIRMED] The old application also has deliberately anonymous deployment/public-links endpoints. Its `/links` builder encodes output and uses `rel="noopener"`; those output-safety principles remain relevant, but the public links page is not the new admin-session model.

[CONFIRMED] `appsettings.json` sets `AllowedHosts` to `*`. No explicit CSP, application Host allowlist or CORS policy was found in the inspected startup/configuration and targeted security search. This is historical evidence, not a claim about every ASP.NET/IIS default.

[CONFIRMED] `tests/Test-WebProject.Static.ps1` is mainly UI/static regression and explicitly keeps HTTPS redirection IIS-owned; it is not a Host/Origin/session/CSP security suite.

| Old behavior | Phase 1C treatment |
|---|---|
| Explicit auth/authz boundary | Retain the principle with a local bootstrap/session candidate |
| ASP.NET antiforgery | Retain objective with exact Origin + CSRF checks |
| HTML no-cache | Retain as `Cache-Control: no-store` and `Pragma: no-cache` |
| IIS Windows Authentication | Do not port by default; ADR-0001 treats mandatory integrated auth as a reopen condition |
| HSTS behind IIS | Do not assume for plain HTTP loopback |
| `AllowedHosts=*` | Replace with exact loopback host + port allowlist |
| Output encoding / `noopener` | Retain as UI implementation requirements |

## 3. Pode 2.14.1 findings

[CONFIRMED] ADR-0001 pins Pode 2.14.1; upstream tag v2.14.1 resolves to `42faafcbd0edf2ffcabd5011a1b03dfbc00c28c4`.

[CONFIRMED] Pode has session/CSRF primitives, but this spike keeps Pode as the HTTP adapter and defines application session semantics explicitly.

[CONFIRMED] The inspected 2.14.1 cookie API has no browser SameSite option. More importantly, PR security review showed that even `HttpOnly; SameSite=Strict` does not solve the explicit local-process threat because cookies are scoped by host/path, not TCP port.

## 4. Security-review correction

[CONFIRMED] Codex P1 comment `4189467569` invalidated the original cookie-session acceptance. A cookie issued by `127.0.0.1:<product-port>` can be sent automatically to another service on `127.0.0.1:<different-port>`. A malicious local listener could receive the ambient credential and replay it against the product port.

[CONFIRMED] Run `37381402897` was green for the checks it contained, but it is now classified as a superseded design, not accepted security evidence. Its reports remain preserved for audit history.

[CONFIRMED] Codex P2 comment `4189467573` found that output-capture exceptions were swallowed, so `NO_TOKEN_LOG_LEAK` could pass on incomplete observation.

[CONFIRMED by code review] The corrected harness removes both weaknesses:

- no session cookie is emitted;
- bootstrap returns a random session credential that the UI must attach explicitly as `X-SISQUAL-Session`;
- the product UI must keep session and CSRF values in JavaScript memory only, not cookies, localStorage or sessionStorage;
- server stores only SHA-256 token hashes and expiry;
- output capture has an explicit `OUTPUT_CAPTURE_COMPLETE` gate;
- `NO_TOKEN_LOG_LEAK` cannot pass unless all four stdout/stderr capture files from the two server processes are complete/readable.

## 5. Corrected bootstrap/session flow

[PROPOSED] On process start, generate a 256-bit random one-time bootstrap token. Browser launch should carry it in a URL fragment, for example `http://127.0.0.1:<port>/#bootstrap=<token>`, not a query string. Same-origin JavaScript posts it in `X-SISQUAL-Bootstrap` then clears the fragment with `history.replaceState`.

[PENDING] The real fragment-to-header JavaScript flow is not part of this backend spike and must be proven in the vanilla-JS shell.

[PROPOSED] The server stores only SHA-256 of bootstrap/session/CSRF values. Bootstrap is short-lived and single-use.

[PROPOSED] Successful bootstrap returns independent 256-bit `session` and `csrf` values in the same-origin JSON response. JavaScript holds them only in memory:

- every protected API call sends `X-SISQUAL-Session`;
- mutations additionally send `X-SISQUAL-CSRF` and an exact local `Origin`;
- no `Set-Cookie` session credential exists;
- no credential goes to localStorage/sessionStorage.

[PROPOSED] Logout clears the server-side session/CSRF hashes. Process restart clears all in-memory session state.

## 6. Request boundary

The corrected candidate:

- binds only to `127.0.0.1`;
- accepts only `127.0.0.1:<port>` and `localhost:<port>` Host values;
- requires explicit session header for protected API routes;
- requires exact local Origin + session + CSRF for mutations;
- emits no `Access-Control-Allow-Origin`; foreign preflight is rejected;
- emits `Cache-Control: no-store`, `Pragma: no-cache`, restrictive CSP, `nosniff`, `no-referrer`, restrictive `Permissions-Policy`, COOP and CORP.

[PENDING] Final UI assets may require a reviewed CSP adjustment. Do not add `unsafe-inline` without a reviewed reason.

## 7. Implementation and evidence

Files:

- `spikes/phase1C/local-web-security/LocalWebSecurityServer.ps1`;
- `spikes/phase1C/local-web-security/Test-LocalWebSecurity.ps1`;
- `.github/workflows/phase1c-local-web-security.yml`;
- `docs/phase1/evidence/phase1c-local-web-security/README.md`.

[CONFIRMED] The workflow verifies pinned PowerShell 7.6.6 and Pode 2.14.1 SHA-256 values before execution.

[CONFIRMED] Documentation-only commits no longer trigger the functional spike; the workflow runs on spike-code/workflow changes or explicit dispatch. This avoids misleading revalidation runs while preserving normal repository CI on PR changes.

## 8. Required corrected gates

The replacement report schema is `SISQUAL_PHASE1C_LOCAL_WEB_SECURITY_V2`.

Required gates on both Windows versions include:

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
- CSP/nosniff/referrer/no-store/COOP/CORP checks;
- `SERVER_STOPPED`;
- `SERVER_RESTARTED`;
- `SESSION_INVALID_AFTER_RESTART`;
- `LOGOUT_INVALIDATES`;
- `SESSION_INVALID_AFTER_LOGOUT`;
- `OUTPUT_CAPTURE_COMPLETE`;
- `NO_TOKEN_LOG_LEAK`.

[PENDING] Run `37382909046`, run number `8`, attempt `1`, commit `bee976eebf98257d39005020c264db769c7ba68c` is the current corrected two-OS candidate. Do not claim PASS until both reports are inspected.

## 9. Historical run classification

[CONFIRMED] Runs 1 and 2 were cancelled by concurrency before probe execution.

[CONFIRMED] Run 3 (`37381402897`) executed and was green, but is superseded because review exposed the cross-port cookie threat and incomplete capture assurance.

[CONFIRMED] Runs 4 and 5 were documentation-triggered revalidations and were cancelled by later commits. The workflow trigger was then narrowed so documentation changes no longer launch the functional matrix.

[CONFIRMED] Run 7 (`37382675122`) was superseded by the follow-up harness fix before it could become the accepted corrected run.

The live evidence ledger records exact IDs/classification; no superseded run is rewritten as a technical failure.

## 10. Security interpretation

A future corrected PASS will not mean localhost itself is an authentication boundary. It must prove that the local browser uses a non-ambient random credential plus CSRF/Host/Origin controls on top of loopback binding.

The model does not protect against a fully compromised local administrator, browser process/profile or kernel.

Engine/API parameters still have to come from trusted contracts/catalog data under `AGENTS.md`.

## 11. Remaining decisions and validation

1. [PENDING] Complete and inspect corrected run `37382909046` (or a later explicitly named accepted run).
2. [PROPOSED] Reviewer/owner accepts or rejects the corrected non-ambient session model as V1 direction.
3. [PENDING] Prove real browser URL-fragment bootstrap, explicit session-header attachment and fragment clearing in vanilla JS.
4. [PENDING] Decide final session lifetime and idle extension policy.
5. [PENDING] Implement/test operation idempotency and controlled shutdown with active operations as the next Phase 1C task.
6. [V] Validate final elevated-process/browser behavior on a SISQUAL sandbox if required.

## 12. Do not inherit blindly from the old UI

Do not add IIS or Windows/Negotiate authentication merely because the reference UI used it.

Do not copy `AllowedHosts=*`.

Do not use a host-scoped session cookie for this local-port threat model.

Do not persist session/CSRF credentials in browser storage.

Do not expose reference-console public endpoints as part of the local administrative surface by default.

Do not copy reference web source into this repository; use it only as historical behavior/evidence.
