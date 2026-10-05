# Phase 1C - Local web security spike

**Date:** 2026-10-05
**Status:** [PROPOSED] security candidate under Windows-runner validation. This document does not approve a final public REST/session contract.
**Branch:** `spike/phase1c-local-web-security`
**Base:** `main` at `ad598215fe3ab0bc715a797a37e2bcf9331eaa56`.

Tags: `[CONFIRMED]` verified source or execution evidence; `[PROPOSED]` candidate design; `[PENDING]` decision/evidence still required; `[V]` target/sandbox validation.

## 1. Scope

This spike addresses the browser/HTTP part of Phase 1C:

- loopback-only listener;
- bootstrap and in-memory session;
- CSRF protection;
- exact Host and Origin allowlists;
- CORS denial;
- browser security headers and CSP;
- logout and process-restart session invalidation;
- token-safe server output.

[PENDING] Operation idempotency, active-operation shutdown and cancellation semantics are a second Phase 1C task. They are intentionally not hidden inside this PR.

## 2. Historical web interface baseline

Reference repository: `atsisqual/SISQUALManagementConsole`, read-only snapshot `9756ba956842884fabcf25b82c4fbf1d11cf56bd`.

[CONFIRMED] `src/SISQUAL.Management.Web/Program.cs` is an ASP.NET Core/Blazor application. It uses Negotiate authentication and explicit `Management.View`, `Management.Operate` and `Management.Administer` policies. Operators, management administrators and built-in administrators are mapped to those policies.

[CONFIRMED] The old request pipeline calls authentication, authorization and ASP.NET antiforgery middleware. In non-development mode it also enables HSTS. HTML responses are marked `no-store, no-cache, must-revalidate`.

[CONFIRMED] The installed IIS site disables anonymous authentication and enables Windows Authentication (`Install.ps1`). Therefore the old authentication boundary is IIS + Windows/Negotiate, not a portable loopback process.

[CONFIRMED] The old application has deliberately anonymous deployment/public-links endpoints. The `/links` HTML builder encodes data before output and uses `rel="noopener"` on links opened in another tab. Those output-safety patterns remain relevant, but the public links page is not the Phase 1C local-admin session model.

[CONFIRMED] `src/SISQUAL.Management.Web/appsettings.json` sets `AllowedHosts` to `*`. No explicit CSP, CORS policy or application Host allowlist was found in the inspected `Program.cs`, appsettings or targeted security search. This is historical evidence, not a claim that ASP.NET/IIS provided no other platform defaults.

[CONFIRMED] `tests/Test-WebProject.Static.ps1` is primarily a UI/compile regression test. It explicitly requires HTTPS redirection to remain IIS-owned; it is not a browser-session/Host/Origin/CSP security test suite.

### What is retained versus replaced

| Old web behavior | Phase 1C treatment |
|---|---|
| Explicit authentication/authorization boundary | Retain the principle; replace IIS/Negotiate with a local bootstrap session candidate |
| ASP.NET antiforgery | Retain the protection objective; prove explicit Origin + CSRF token checks |
| HTML no-cache | Retain as `Cache-Control: no-store` and `Pragma: no-cache` |
| IIS Windows Authentication | Do not port by default; ADR-0001 treats mandatory integrated Windows auth as a reopen condition |
| HSTS/HTTPS behind IIS | Do not assume it for the portable loopback HTTP listener |
| `AllowedHosts=*` | Replace with exact loopback host + port allowlist |
| Output encoding / `noopener` | Retain as future UI implementation requirements |

## 3. Pode 2.14.1 findings

[CONFIRMED] ADR-0001 pins Pode 2.14.1. The exact upstream tag is commit `42faafcbd0edf2ffcabd5011a1b03dfbc00c28c4`.

[CONFIRMED] Pode 2.14.1 has built-in in-memory session and CSRF middleware. Its session/cookie APIs expose `HttpOnly`, `Secure` and Pode's `Strict` signing mode.

[CONFIRMED] The 2.14.1 `Enable-PodeSessionMiddleware` / `Set-PodeCookie` public APIs do not expose a SameSite cookie option. Pode's `Strict` flag is not the browser `SameSite=Strict` attribute.

[PROPOSED] For V1, keep Pode as the HTTP adapter and make the application session semantics explicit rather than silently losing the SameSite requirement. The spike emits the session cookie itself with `HttpOnly; SameSite=Strict` and keeps only hashes of the session/CSRF tokens in memory.

## 4. Candidate bootstrap/session flow

[PROPOSED] On process start, generate a 256-bit random one-time bootstrap token. The product browser-launch path should place it in a URL fragment, not the query string, for example `http://127.0.0.1:<port>/#bootstrap=<token>`. URL fragments are not sent as the HTTP request target. Client JavaScript should POST it in `X-SISQUAL-Bootstrap` and immediately remove the fragment with `history.replaceState`.

[PENDING] The fragment-to-header browser code is not part of this backend spike and must be proven with the real vanilla JS UI before product integration.

[PROPOSED] The server stores only SHA-256 of the bootstrap token. The token expires quickly and is consumed once.

[PROPOSED] Successful bootstrap generates independent 256-bit session and CSRF values. The server stores only their hashes and expiry in memory. The browser gets:

- `SISQUAL-SESSION=<random>; Path=/; HttpOnly; SameSite=Strict; Max-Age=...`;
- the CSRF token in the same-origin bootstrap JSON response, for JavaScript to send as `X-SISQUAL-CSRF` on mutations.

[PROPOSED] `Secure` is not asserted for the V1 cookie while the accepted architecture uses plain HTTP on loopback. If local HTTPS is introduced, `Secure` becomes mandatory. No session token is placed in localStorage/sessionStorage.

[PROPOSED] V1 has in-memory session state only. Logout clears it. Process restart clears it. This aligns with ADR-0007, which allows locks/idempotency state in memory and no runtime state database.

## 5. Request boundary

[PROPOSED] Pode binds only to `127.0.0.1`.

[PROPOSED] Accept only exact `Host` values `127.0.0.1:<port>` and `localhost:<port>`. This permits the two intended local names but rejects arbitrary DNS-rebinding Host values.

[PROPOSED] Mutating browser requests require an exact Origin of `http://127.0.0.1:<port>` or `http://localhost:<port>`, a valid session cookie and a valid CSRF header.

[PROPOSED] Do not emit `Access-Control-Allow-Origin`. Foreign preflight requests are rejected.

[PROPOSED] Every response gets at least:

- `Cache-Control: no-store`;
- `Pragma: no-cache`;
- `Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'`;
- `X-Content-Type-Options: nosniff`;
- `Referrer-Policy: no-referrer`;
- restrictive camera/microphone/geolocation `Permissions-Policy`;
- `Cross-Origin-Opener-Policy: same-origin`;
- `Cross-Origin-Resource-Policy: same-origin`.

[PENDING] The final UI may require a narrower/adjusted CSP source list for specific vendored assets. It must not weaken CSP by adding `unsafe-inline` without a reviewed reason.

## 6. Spike implementation

Files:

- `spikes/phase1C/local-web-security/LocalWebSecurityServer.ps1`;
- `spikes/phase1C/local-web-security/Test-LocalWebSecurity.ps1`;
- `.github/workflows/phase1c-local-web-security.yml`;
- `docs/phase1/evidence/phase1c-local-web-security/README.md`.

[CONFIRMED by code review] The probe passes only the bootstrap **hash** into the server child process environment. Raw bootstrap/session/CSRF values are generated for the disposable test, never committed, and the reports contain statuses/metadata rather than token values.

[CONFIRMED by code review] The probe uses the pinned portable PowerShell 7.6.6 and Pode 2.14.1 downloads after SHA-256 verification.

## 7. Required test gates

The accepted run must pass on both `windows-2022` and `windows-2025`:

| Gate | Expected |
|---|---|
| Server ready | canonical `127.0.0.1` URL answers |
| Loopback only | host non-loopback IPv4 cannot connect |
| Session required | protected route without cookie => 401 |
| Host rejected | forged Host => 400 |
| Bootstrap accepted | valid one-time token creates session + CSRF |
| Cookie flags | HttpOnly + SameSite=Strict + Path=/ |
| Bootstrap replay | consumed token => 403 |
| Valid session | protected GET => 200 |
| Foreign Origin | mutation => 403 |
| Missing/wrong CSRF | mutation => 403 |
| Valid mutation | session + exact Origin + CSRF => 200 |
| CORS preflight | foreign OPTIONS => 403 and no ACAO |
| Security headers | CSP/nosniff/referrer/cache/cross-origin headers present |
| Stop | listener disappears when process is stopped |
| Restart | old in-memory session => 401 |
| Logout | session cleared and cookie expired |
| Token logs | raw bootstrap/session/CSRF absent from captured server output |

The report schema is `SISQUAL_PHASE1C_LOCAL_WEB_SECURITY_V1`.

## 8. Security interpretation

A PASS does **not** mean localhost is an authentication boundary. It proves that a random session and CSRF state are required on top of loopback binding, directly reducing R-009/R-034.

A PASS does not protect against a fully compromised administrator account, browser profile or kernel. Those are outside this local HTTP boundary.

A PASS does not approve arbitrary REST input. Engine parameters still have to come from trusted contracts/catalog data under `AGENTS.md`.

## 9. Acceptance rule

Phase 1C web-boundary viability is `[CONFIRMED]` only after one named `run ID + attempt + commit SHA` executes every required gate on both Windows runner versions and preserves artifact IDs/digests.

Older failed attempts stay in the ledger and keep their real classification (harness, infrastructure or technical failure).

Even after a green run:

- `[PROPOSED]` bootstrap/session design remains subject to reviewer/owner acceptance before it becomes a product contract;
- `[PENDING]` real browser fragment bootstrap integration;
- `[PENDING]` final session lifetime and whether idle extension is wanted;
- `[PENDING]` Phase 1C operation idempotency and controlled-shutdown task;
- `[V]` final elevated-process/browser behavior on a SISQUAL sandbox if the reviewer requires it.

## 10. Do not inherit blindly from the old UI

Do not add IIS or Windows/Negotiate authentication merely because the reference UI used it. That would change ADR-0001's portable local architecture and is a reopen condition.

Do not copy the old `AllowedHosts=*` behavior.

Do not expose public reference-console endpoints as part of the local administrative surface by default.

Do not copy reference web source code into this repository; use it only as historical behavior/evidence.
