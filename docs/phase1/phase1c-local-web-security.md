# Phase 1C - Local web security spike

**Date:** 2026-10-05
**Status:** [CONFIRMED] corrected non-ambient local web boundary technically viable on Windows Server 2022 and 2025. Product adoption remains [PROPOSED].
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

[CONFIRMED] Pode has session/CSRF primitives, but the accepted spike keeps Pode as HTTP adapter and defines application session semantics explicitly.

[CONFIRMED] The inspected 2.14.1 cookie API has no browser SameSite option. More importantly, security review showed that even `HttpOnly; SameSite=Strict` does not solve the local-process threat because cookies are scoped by host/path, not TCP port.

## 4. Security-review correction

[CONFIRMED] Codex P1 comment `4189467569` invalidated the original cookie-session acceptance. A cookie issued by `127.0.0.1:<product-port>` can be sent automatically to another service on `127.0.0.1:<different-port>`. A malicious local listener could receive the ambient credential and replay it against the product port.

[CONFIRMED] Run `37381402897` was green for its V1 checks, but is classified as a superseded design, not accepted security evidence. Its reports remain preserved for audit history.

[CONFIRMED] Codex P2 comment `4189467573` found that output-capture exceptions were swallowed, so `NO_TOKEN_LOG_LEAK` could pass on incomplete observation.

[CONFIRMED] The corrected V2 model removes both weaknesses:

- no session cookie is emitted;
- bootstrap returns a random session credential that the UI must attach explicitly as `X-SISQUAL-Session`;
- session and CSRF values are intended for JavaScript memory only, not cookies, localStorage or sessionStorage;
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

[PROPOSED] Logout clears server-side session/CSRF hashes. Process restart clears all in-memory session state.

## 6. Request boundary

The accepted V2 candidate:

- binds only to `127.0.0.1`;
- accepts only `127.0.0.1:<port>` and `localhost:<port>` Host values;
- requires explicit session header for protected API routes;
- requires exact local Origin + session + CSRF for mutations;
- emits no `Access-Control-Allow-Origin`; foreign preflight is rejected;
- emits `Cache-Control: no-store`, `Pragma: no-cache`, restrictive CSP, `nosniff`, `no-referrer`, restrictive `Permissions-Policy`, COOP and CORP.

[PENDING] Final UI assets may require a reviewed CSP adjustment. Do not add `unsafe-inline` without a reviewed reason.

## 7. Accepted technical evidence

**Workflow:** `phase1c-local-web-security`
**Workflow ID:** `375855729`
**Run:** `37382909046`
**Run number:** `8`
**Attempt:** `1`
**Commit:** `bee976eebf98257d39005020c264db769c7ba68c`
**Conclusion:** [CONFIRMED] `success`

Windows 2022:

- job `112009129958`;
- runner `GitHub Actions 1000000576`, runner ID `1000000576`;
- artifact `11375417797`, size `1925` bytes;
- digest `sha256:46731edd4c774cd38a65ce9d9141943870e21afc7ab15f601484309d78b022f4`;
- V2 report: `27 PASS / 0 FAIL / Fatal=null`.

Windows 2025:

- job `112009129747`;
- runner `GitHub Actions 1000000577`, runner ID `1000000577`;
- artifact `11376252062`, size `1919` bytes;
- digest `sha256:bd8560ff446a621bd1bb7451ecad76718516c60f35e03d70ae214354461c85fe`;
- V2 report: `27 PASS / 0 FAIL / Fatal=null`.

[CONFIRMED] Exact secret-safe reports and run metadata are under `docs/phase1/evidence/phase1c-local-web-security-37382909046/`.

## 8. What V2 proved

[CONFIRMED] Both systems passed:

- loopback-only reachability;
- protected route rejection without explicit session header;
- forged Host rejection;
- valid one-time bootstrap;
- **no session cookie**;
- bootstrap replay rejection;
- wrong session rejection and valid explicit session acceptance;
- foreign Origin rejection;
- missing/wrong CSRF rejection and valid mutation;
- foreign CORS preflight rejection with no ACAO;
- CSP/nosniff/referrer/no-store/COOP/CORP headers;
- restart invalidation and logout invalidation;
- **complete capture of four stdout/stderr streams** with zero capture errors;
- no raw bootstrap/session/CSRF values in the completely captured output.

[CONFIRMED] The corrected non-ambient local HTTP/browser boundary is technically viable on GitHub-hosted Windows Server 2022 and 2025.

## 9. Run history

[CONFIRMED] Runs 1 and 2 were cancelled by concurrency before probe execution.

[CONFIRMED] Run 3 executed successfully but is superseded by security review because it used an ambient cookie and did not fail closed on output capture.

[CONFIRMED] Runs 4 and 5 were documentation-triggered/cancelled revalidations. The workflow trigger was then narrowed so documentation-only changes no longer launch the functional matrix.

[CONFIRMED] Run 6 was incomplete: Windows 2022 began a probe before cancellation and Windows 2025 never reached it. It is not acceptance evidence.

[CONFIRMED] Run 7 was superseded by the harness fix before the corrected model executed.

[CONFIRMED] Run 8 is the first accepted corrected V2 run. Exact IDs and classifications for every run are in `docs/phase1/evidence/phase1c-local-web-security/README.md`.

## 10. Security interpretation

A PASS does not mean localhost itself is an authentication boundary. It proves a non-ambient random session credential plus CSRF/Host/Origin controls can be enforced on top of loopback binding, reducing the exposure behind R-009/R-034.

The model does not protect against a fully compromised local administrator, browser process/profile or kernel.

Engine/API parameters still have to come from trusted contracts/catalog data under `AGENTS.md`.

## 11. Remaining decisions and validation

1. [PROPOSED] Reviewer/owner accepts or rejects the corrected non-ambient session model as V1 direction.
2. [PENDING] Prove real browser URL-fragment bootstrap, explicit `X-SISQUAL-Session` attachment and fragment clearing in vanilla JS.
3. [PENDING] Keep session/CSRF credentials only in JS memory in the real UI; add a browser-level regression proving no cookie/localStorage/sessionStorage persistence.
4. [PENDING] Decide final session lifetime and idle-extension policy.
5. [PENDING] Implement/test operation idempotency and controlled shutdown with active operations as the next Phase 1C task.
6. [V] Validate final elevated-process/browser behavior on a SISQUAL sandbox if required.

## 12. Do not inherit blindly from the old UI

Do not add IIS or Windows/Negotiate authentication merely because the reference UI used it.

Do not copy `AllowedHosts=*`.

Do not use a host-scoped session cookie for this local-port threat model.

Do not persist session/CSRF credentials in browser storage.

Do not expose reference-console public endpoints as part of the local administrative surface by default.

Do not copy reference web source into this repository; use it only as historical behavior/evidence.
