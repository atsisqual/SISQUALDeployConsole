# Phase 1C local web security handover - 2026-10-05

**Purpose:** let another AI/reviewer or human continue PR #38 without chat history.
**Status:** [CONFIRMED] handover snapshot. This is not a decision record and does not approve the proposed browser/session contract.
**Repository:** `atsisqual/SISQUALDeployConsole`
**PR:** #38 `spike(phase1c): validate local web security boundary`
**Branch:** `spike/phase1c-local-web-security`
**Base:** `main` at `ad598215fe3ab0bc715a797a37e2bcf9331eaa56`

## 1. Resume rules

1. Read current `AGENTS.md`, `docs/decisions-log.md`, ADR-0001 and ADR-0007, then list open PRs.
2. `atsisqual/SISQUALManagementConsole` is read-only reference evidence. Never modify it.
3. Do not merge PR #38 unless the owner explicitly delegates merge authority.
4. Preserve `[CONFIRMED]`, `[PROPOSED]`, `[PENDING]`, `[V]` distinctions.
5. Never log/commit bootstrap, session, CSRF, credential or private-key values.
6. Do not cite a GitHub `success` as security acceptance unless the exact report gates have been inspected.

## 2. Why the old web interface was analysed

The owner explicitly asked to consider the pre-existing management web interface.

[CONFIRMED] Reference snapshot: `atsisqual/SISQUALManagementConsole` commit `9756ba956842884fabcf25b82c4fbf1d11cf56bd`.

Relevant evidence:

- `src/SISQUAL.Management.Web/Program.cs`: ASP.NET Core/Blazor, Negotiate auth, explicit view/operate/admin authorization policies, authentication/authorization/antiforgery middleware, production HSTS and no-cache HTML behavior;
- `Install.ps1`: IIS anonymous authentication disabled, Windows Authentication enabled;
- `src/SISQUAL.Management.Web/appsettings.json`: `AllowedHosts` is `*`;
- `tests/Test-WebProject.Static.ps1`: UI/static regression; HTTPS redirection intentionally IIS-owned, not a Host/Origin/session/CSP security suite.

[CONFIRMED] Useful principles retained: explicit authentication boundary, antiforgery objective, no-store/no-cache, output encoding and `noopener` patterns.

[PROPOSED] IIS/Negotiate is not ported merely for parity. ADR-0001 selects a portable loopback Pode architecture and treats mandatory integrated Windows auth as a reopen condition.

Do not copy source text from the reference web application into this repo.

## 3. Pode evidence

[CONFIRMED] Pode is pinned to 2.14.1. Upstream tag resolves to commit `42faafcbd0edf2ffcabd5011a1b03dfbc00c28c4`.

[CONFIRMED] The final candidate uses Pode as HTTP adapter; it does not use a browser session cookie as the authentication credential.

## 4. The important security-review correction

The first full two-OS run was green but **must not be accepted**.

### Superseded green run

- workflow ID `375855729`;
- run `37381402897`, run number `3`, attempt `1`;
- commit `9c27190bc1616278e59de5391425f66ea72fa747`;
- both Windows jobs returned success and V1 reports had `27 PASS / 0 FAIL`.

[CONFIRMED] Codex P1 review comment `4189467569` found a real threat: cookies are host/path scoped, not TCP-port scoped. A session cookie from the product on `127.0.0.1:<port>` can be sent automatically to another process listening on another `127.0.0.1` port. `HttpOnly` and `SameSite=Strict` do not provide port isolation.

[CONFIRMED] Codex P2 comment `4189467573` found that the V1 harness swallowed stdout/stderr capture errors, so `NO_TOKEN_LOG_LEAK` was not fail-closed.

The V1 run remains preserved under `docs/phase1/evidence/phase1c-local-web-security-37381402897/`, explicitly classified as superseded.

## 5. Corrected V2 model

[CONFIRMED] By implementation and executed evidence, no session cookie is emitted.

[PROPOSED] Product direction:

1. process generates a 256-bit one-time bootstrap token;
2. browser launch carries it in a URL fragment, not query string;
3. same-origin JS posts it as `X-SISQUAL-Bootstrap`, then removes the fragment;
4. bootstrap returns independent random `session` and `csrf` values;
5. JS keeps both only in memory, never cookie/localStorage/sessionStorage;
6. protected calls attach `X-SISQUAL-Session` explicitly;
7. mutations also attach `X-SISQUAL-CSRF` and must have exact local Origin;
8. server stores only SHA-256 hashes plus expiry in memory;
9. logout/process restart invalidates the in-memory session.

The backend spike proves steps 3-9 at HTTP level except the actual browser fragment/JS-storage behavior. Browser integration remains `[PENDING]`.

## 6. Accepted run

**Workflow:** `phase1c-local-web-security`
**Workflow ID:** `375855729`
**Run ID:** `37382909046`
**Run number:** `8`
**Attempt:** `1`
**Event:** `push`
**Commit:** `bee976eebf98257d39005020c264db769c7ba68c`
**Created:** `2026-10-05T22:30:26Z`
**Completed:** `2026-10-05T22:34:25Z`
**Conclusion:** [CONFIRMED] `success`

### Windows 2022

- job `112009129958`;
- runner `GitHub Actions 1000000576`, runner ID `1000000576`;
- started `2026-10-05T22:30:40Z`, completed `2026-10-05T22:33:19Z`;
- artifact ID `11375417797`, size `1925` bytes;
- digest `sha256:46731edd4c774cd38a65ce9d9141943870e21afc7ab15f601484309d78b022f4`;
- artifact expiry `2027-01-03T22:30:27Z`;
- report V2: `27 PASS / 0 FAIL / Fatal=null`.

### Windows 2025

- job `112009129747`;
- runner `GitHub Actions 1000000577`, runner ID `1000000577`;
- started `2026-10-05T22:30:40Z`, completed `2026-10-05T22:34:24Z`;
- artifact ID `11376252062`, size `1919` bytes;
- digest `sha256:bd8560ff446a621bd1bb7451ecad76718516c60f35e03d70ae214354461c85fe`;
- artifact expiry `2027-01-03T22:30:27Z`;
- report V2: `27 PASS / 0 FAIL / Fatal=null`.

[CONFIRMED] Both exact artifacts were downloaded and the JSON reports inspected before acceptance.

## 7. What the accepted run proves

Both Windows versions passed:

- loopback-only reachability;
- protected API requires explicit session header;
- forged Host rejected;
- one-time bootstrap accepted and replay rejected;
- `NO_SESSION_COOKIE`;
- wrong session rejected, valid explicit session accepted;
- foreign Origin rejected;
- missing/wrong CSRF rejected, valid mutation accepted;
- foreign CORS preflight rejected with no ACAO;
- restrictive CSP, nosniff, no-referrer, no-store, COOP and CORP;
- previous session rejected after process restart;
- logout invalidates session;
- `OUTPUT_CAPTURE_COMPLETE`: four stdout/stderr streams, zero capture errors;
- `NO_TOKEN_LOG_LEAK` only after complete observation.

[CONFIRMED] The corrected non-ambient local HTTP/browser boundary is technically viable on the tested Windows images.

## 8. Complete functional-run lineage

All runs are attempt `1`:

- run 1 `37381249793`, commit `454f12f680a86036f2296ce785ed3f2cd1eff98c`: jobs `112003514220` / `112003514640`; cancelled during runtime download; probe skipped.
- run 2 `37381372562`, commit `75e5a6e6d672320f391bca99bba60ae77c9a5b42`: jobs `112003982101` / `112003982569`; cancelled during checkout; probe skipped.
- run 3 `37381402897`, commit `9c27190bc1616278e59de5391425f66ea72fa747`: full V1 green but security-design superseded by review.
- run 4 `37382249228`, commit `cc90e1267bf6eed8794c4ed3aa3427cc26ed19ce`: jobs `112006871227` runner `1000000564`, `112006871484` runner `1000000565`; cancelled during runtime download.
- run 5 `37382333185`, commit `5da98c6a81fa8afb798a50d1eedf6e2fb0de6b2f`: jobs `112007216565` runner `1000000568`, `112007217043` runner `1000000569`; cancelled during runtime download.
- run 6 `37382459339`, commit `8176e5cdbbee5a63a5043edf5d5aed0a9e420fdf`: jobs `112007610957` runner `1000000570` (probe began then cancelled) and `112007611113` runner `1000000571` (probe skipped); incomplete.
- run 7 `37382675122`, commit `a4f600765196be27c68c18f6785666fe554d0b7a`: jobs `112008579361` runner `1000000573`, `112008579686` runner `1000000574`; superseded before complete corrected probe.
- run 8 `37382909046`, commit `bee976eebf98257d39005020c264db769c7ba68c`: accepted V2 two-OS PASS.

The canonical full ledger is `docs/phase1/evidence/phase1c-local-web-security/README.md`.

## 9. Evidence paths

- design/status: `docs/phase1/phase1c-local-web-security.md`;
- live ledger: `docs/phase1/evidence/phase1c-local-web-security/README.md`;
- accepted V2: `docs/phase1/evidence/phase1c-local-web-security-37382909046/`;
- superseded V1: `docs/phase1/evidence/phase1c-local-web-security-37381402897/`;
- spike: `spikes/phase1C/local-web-security/`;
- workflow: `.github/workflows/phase1c-local-web-security.yml`.

[CONFIRMED] Functional workflow push triggers were narrowed to spike-code/workflow paths, so documentation-only evidence/handover commits do not generate redundant functional runs.

## 10. Remaining work

1. [PROPOSED] Reviewer/owner accepts or rejects the non-ambient V2 session model as V1 product direction.
2. [PENDING] Browser-level vanilla-JS spike: URL fragment -> bootstrap header -> immediate fragment removal -> session/CSRF only in JS memory -> explicit session header on protected requests.
3. [PENDING] Browser regression proving no session/CSRF credential appears in cookie, localStorage or sessionStorage.
4. [PENDING] Decide session lifetime and idle-extension behavior.
5. [PENDING] Separate Phase 1C task for operation idempotency, active-operation tracking, controlled shutdown and cancellation semantics.
6. [V] If reviewer requires it, exercise final elevated process + browser behavior on SISQUAL sandbox Windows.

## 11. What not to do

- Do not cite run 3 as accepted simply because GitHub marked it green.
- Do not restore session cookies for the loopback-port model without a new threat analysis.
- Do not persist session/CSRF in localStorage/sessionStorage.
- Do not add IIS/Windows Negotiate merely because the old UI used it.
- Do not copy old `AllowedHosts=*`.
- Do not copy reference web code; it is evidence only.
- Do not claim `SERVER_STOPPED` proves graceful shutdown.
- Do not merge PR #38 without explicit owner delegation.

## 12. Next-session checklist

1. Read current repo instructions and list open PRs.
2. Read latest PR #38 review threads; confirm comments `4189467569` and `4189467573` are addressed and check for later findings.
3. Read accepted V2 evidence before changing the session model.
4. Check standard CI on the final documentation/handover head.
5. If continuing Phase 1C, create a new independent branch/PR from then-current `main` for operation idempotency + controlled shutdown; do not mix it into #38.
