# Phase 1C - Local web security spike

**Date:** 2026-10-05
**Status:** [CONFIRMED] technical viability proven on Windows Server 2022 and 2025. Product adoption of the bootstrap/session design remains [PROPOSED].
**Branch:** `spike/phase1c-local-web-security`
**Base:** `main` at `ad598215fe3ab0bc715a797a37e2bcf9331eaa56`.

Tags: `[CONFIRMED]` verified source or execution evidence; `[PROPOSED]` candidate design; `[PENDING]` decision/evidence still required; `[V]` target/sandbox validation.

## 1. Scope

This spike covers the browser/HTTP part of Phase 1C:

- loopback-only listener;
- bootstrap and in-memory session;
- CSRF protection;
- exact Host and Origin allowlists;
- CORS denial;
- browser security headers and CSP;
- logout and process-restart session invalidation;
- token-safe server output.

[PENDING] Operation idempotency, active-operation shutdown and cancellation semantics are a separate Phase 1C task. `SERVER_STOPPED` in this spike proves listener removal after process termination; it is not graceful-shutdown evidence.

## 2. Historical web interface baseline

Reference repository: `atsisqual/SISQUALManagementConsole`, read-only snapshot `9756ba956842884fabcf25b82c4fbf1d11cf56bd`.

[CONFIRMED] `src/SISQUAL.Management.Web/Program.cs` is an ASP.NET Core/Blazor application. It uses Negotiate authentication and explicit `Management.View`, `Management.Operate` and `Management.Administer` policies.

[CONFIRMED] The old pipeline uses authentication, authorization and ASP.NET antiforgery middleware. In non-development mode it enables HSTS. HTML responses are marked `no-store, no-cache, must-revalidate`.

[CONFIRMED] `Install.ps1` disables anonymous IIS authentication and enables Windows Authentication. The old authentication boundary is therefore IIS + Windows/Negotiate, not a portable loopback process.

[CONFIRMED] The old application has deliberately anonymous deployment/public-links endpoints. The `/links` HTML builder encodes values before output and uses `rel="noopener"` for new-tab links. Those output-safety principles remain relevant, but the public links page is not the new local-admin session model.

[CONFIRMED] `src/SISQUAL.Management.Web/appsettings.json` sets `AllowedHosts` to `*`. No explicit CSP, application Host allowlist or CORS policy was found in the inspected startup/configuration and targeted security search. This is historical evidence, not a claim that ASP.NET/IIS supplied no other platform defaults.

[CONFIRMED] `tests/Test-WebProject.Static.ps1` is mainly a UI/compile regression test. It requires HTTPS redirection to remain IIS-owned; it is not a browser-session/Host/Origin/CSP security suite.

| Old web behavior | Phase 1C treatment |
|---|---|
| Explicit authentication/authorization boundary | Retain the principle; use a local bootstrap session candidate |
| ASP.NET antiforgery | Retain the protection objective; test exact Origin + CSRF token |
| HTML no-cache | Retain as `Cache-Control: no-store` and `Pragma: no-cache` |
| IIS Windows Authentication | Do not port by default; ADR-0001 treats mandatory integrated auth as a reopen condition |
| HSTS/HTTPS behind IIS | Do not assume it for plain HTTP loopback |
| `AllowedHosts=*` | Replace with exact loopback host + port allowlist |
| Output encoding / `noopener` | Retain as UI implementation requirements |

## 3. Pode 2.14.1 findings

[CONFIRMED] ADR-0001 pins Pode 2.14.1. Upstream tag v2.14.1 resolves to commit `42faafcbd0edf2ffcabd5011a1b03dfbc00c28c4`.

[CONFIRMED] Pode 2.14.1 has built-in in-memory session and CSRF middleware. Its public session/cookie APIs expose `HttpOnly`, `Secure` and Pode's signing `Strict` mode.

[CONFIRMED] The inspected 2.14.1 `Enable-PodeSessionMiddleware` / `Set-PodeCookie` APIs do not expose the browser SameSite attribute. Pode's `Strict` option is not `SameSite=Strict`.

[PROPOSED] Keep Pode as the HTTP adapter and make application-session semantics explicit. The tested candidate emits the session cookie itself with `HttpOnly; SameSite=Strict` and keeps only hashes of session/CSRF tokens in memory.

## 4. Candidate bootstrap/session flow

[PROPOSED] On process start, generate a 256-bit random one-time bootstrap token. The product browser-launch path should carry it in a URL fragment, for example `http://127.0.0.1:<port>/#bootstrap=<token>`, not in the query string. Client JavaScript should POST it in `X-SISQUAL-Bootstrap` and immediately clear the fragment with `history.replaceState`.

[PENDING] The fragment-to-header browser code is not part of this backend spike and must be proven with the actual vanilla-JS UI.

[PROPOSED] The server stores only SHA-256 of the bootstrap token. It expires quickly and is consumed once.

[PROPOSED] Successful bootstrap creates independent 256-bit session and CSRF values. The server stores only their hashes and expiry in memory. The browser receives:

- `SISQUAL-SESSION=<random>; Path=/; HttpOnly; SameSite=Strict; Max-Age=...`;
- the CSRF token in the same-origin bootstrap JSON response for `X-SISQUAL-CSRF` on mutations.

[PROPOSED] `Secure` is not asserted while V1 uses plain HTTP loopback. If local HTTPS is introduced, `Secure` becomes mandatory. No session token is placed in localStorage/sessionStorage.

[PROPOSED] Session state is in memory only. Logout clears it; process restart clears it.

## 5. Request boundary

The tested candidate:

- binds Pode only to `127.0.0.1`;
- accepts only `127.0.0.1:<port>` and `localhost:<port>` Host values;
- requires exact local Origin + valid session + CSRF for mutations;
- emits no `Access-Control-Allow-Origin` and rejects foreign preflight;
- emits `Cache-Control: no-store` and `Pragma: no-cache`;
- emits a restrictive CSP with `frame-ancestors 'none'`, `object-src 'none'` and `base-uri 'none'`;
- emits `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, restrictive `Permissions-Policy`, COOP and CORP.

[PENDING] The final UI may require a reviewed CSP adjustment for specific vendored assets. Do not add `unsafe-inline` without a reviewed reason.

## 6. Implementation and evidence

Files:

- `spikes/phase1C/local-web-security/LocalWebSecurityServer.ps1`;
- `spikes/phase1C/local-web-security/Test-LocalWebSecurity.ps1`;
- `.github/workflows/phase1c-local-web-security.yml`;
- `docs/phase1/evidence/phase1c-local-web-security/README.md`;
- `docs/phase1/evidence/phase1c-local-web-security-37381402897/`.

[CONFIRMED by code review] Only the bootstrap hash is passed into the server child-process environment. Raw bootstrap/session/CSRF values are generated for the disposable test and are not committed or included in reports.

[CONFIRMED] The workflow downloads pinned PowerShell 7.6.6 and Pode 2.14.1 and verifies their SHA-256 values before execution.

## 7. Accepted run

**Workflow ID:** `375855729`
**Run:** `37381402897`
**Run number:** `3`
**Attempt:** `1`
**Commit:** `9c27190bc1616278e59de5391425f66ea72fa747`
**Conclusion:** [CONFIRMED] `success`

Windows 2022:

- job `112004092392`;
- runner `GitHub Actions 1000000558` / runner ID `1000000558`;
- artifact `11374356055`;
- digest `sha256:12ea9164fb9a66d4c4d04ce0bc5be090bb6b0450db308b8a27b02957d70b4fe8`;
- report `27 PASS / 0 FAIL / Fatal=null`.

Windows 2025:

- job `112004092351`;
- runner `GitHub Actions 1000000559` / runner ID `1000000559`;
- artifact `11375770246`;
- digest `sha256:1b61967c89885f88817f902b1faa15748c25de60d9f8501cd41bc42b41ac964a`;
- report `27 PASS / 0 FAIL / Fatal=null`.

[CONFIRMED] Both systems passed loopback-only reachability, session enforcement, forged-Host rejection, one-time bootstrap, `HttpOnly`/`SameSite=Strict`, bootstrap replay rejection, exact-Origin enforcement, CSRF negative and positive paths, CORS-preflight denial, security headers, restart invalidation, logout invalidation and raw-token log leakage checks.

[CONFIRMED] Exact secret-safe reports are versioned under `docs/phase1/evidence/phase1c-local-web-security-37381402897/` and the original GitHub artifacts are identified by ID and digest.

## 8. Superseded runs

[CONFIRMED] Run `37381249793` (run 1, commit `454f12f...`) was cancelled by workflow concurrency during runtime download after a later branch push. Jobs `112003514220` and `112003514640`; the security probe was skipped.

[CONFIRMED] Run `37381372562` (run 2, commit `75e5a6e...`) was cancelled by workflow concurrency during checkout after the next branch push. Jobs `112003982101` and `112003982569`; the security probe was skipped.

Neither superseded run is a technical security failure.

## 9. Security interpretation

[CONFIRMED] The tested boundary is technically viable on the GitHub-hosted Windows Server 2022 and 2025 images.

A PASS does not mean localhost itself is an authentication boundary. It proves random session/CSRF state and Host/Origin controls can be enforced on top of loopback binding, reducing the exposure behind R-009/R-034.

A PASS does not protect against a fully compromised local administrator, browser profile or kernel.

A PASS does not approve arbitrary REST input. Engine parameters still have to come from trusted contracts/catalog data under `AGENTS.md`.

## 10. Remaining decisions and validation

1. [PROPOSED] Reviewer/owner accepts or rejects this bootstrap/session design as the V1 product direction.
2. [PENDING] Prove the actual browser URL-fragment bootstrap, POST and fragment clearing in the vanilla-JS shell.
3. [PENDING] Decide final session lifetime and whether idle extension is needed.
4. [PENDING] Implement/test operation idempotency and controlled shutdown with active operations as the next Phase 1C task.
5. [V] Validate final elevated-process/browser behavior on a SISQUAL sandbox if required by the reviewer.

## 11. Do not inherit blindly from the old UI

Do not add IIS or Windows/Negotiate authentication merely because the reference UI used it. That would change ADR-0001's portable local architecture and is a reopen condition.

Do not copy the old `AllowedHosts=*` behavior.

Do not expose the reference console's public endpoints as part of the local administrative surface by default.

Do not copy reference web source into this repository; use it only as historical behavior/evidence.
