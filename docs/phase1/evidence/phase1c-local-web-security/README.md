# Phase 1C local web security evidence ledger

**Branch:** `spike/phase1c-local-web-security`
**Base main:** `ad598215fe3ab0bc715a797a37e2bcf9331eaa56`
**Workflow:** `phase1c-local-web-security`
**Workflow ID:** `375855729`
**Status:** [CONFIRMED] corrected technical run `37382909046` / attempt `1` / commit `bee976eebf98257d39005020c264db769c7ba68c` passed all V2 gates on Windows 2022 and 2025.

## Evidence rule

Every execution preserves run/attempt/commit, job and runner identifiers, UTC timestamps, artifacts/hashes and a classification. A run is security-accepted only when both Windows jobs execute the current gate set and the reports are inspected. GitHub `success` alone is not enough.

## Run history

### Run 1 - `37381249793`

- attempt `1`, commit `454f12f680a86036f2296ce785ed3f2cd1eff98c`;
- windows-2025 job `112003514220`, runner ID `1000000554`;
- windows-2022 job `112003514640`, runner ID `1000000555`;
- cancelled by concurrency during runtime download; probe skipped.

Classification: [CONFIRMED] superseded/infrastructure orchestration, not a security result.

### Run 2 - `37381372562`

- attempt `1`, commit `75e5a6e6d672320f391bca99bba60ae77c9a5b42`;
- windows-2025 job `112003982101`, runner ID `1000000556`;
- windows-2022 job `112003982569`, runner ID `1000000557`;
- cancelled by the next branch push during checkout; probe skipped.

Classification: [CONFIRMED] superseded/infrastructure orchestration.

### Run 3 - `37381402897`

- attempt `1`, commit `9c27190bc1616278e59de5391425f66ea72fa747`;
- GitHub conclusion `success`;
- windows-2022 job `112004092392`, runner `1000000558`, artifact `11374356055`, digest `sha256:12ea9164fb9a66d4c4d04ce0bc5be090bb6b0450db308b8a27b02957d70b4fe8`;
- windows-2025 job `112004092351`, runner `1000000559`, artifact `11375770246`, digest `sha256:1b61967c89885f88817f902b1faa15748c25de60d9f8501cd41bc42b41ac964a`;
- both V1 reports had `27 PASS / 0 FAIL`.

Classification: [CONFIRMED] executed but **superseded security design**. PR review comment `4189467569` proved the session cookie was ambient across loopback ports; comment `4189467573` proved log-capture completeness was not fail-closed. Full historical evidence remains under `docs/phase1/evidence/phase1c-local-web-security-37381402897/`.

### Run 4 - `37382249228`

- attempt `1`, commit `cc90e1267bf6eed8794c4ed3aa3427cc26ed19ce`;
- windows-2022 job `112006871227`, runner `1000000564`;
- windows-2025 job `112006871484`, runner `1000000565`;
- both cancelled during runtime download by a later documentation-triggered run; probe skipped.

Classification: [CONFIRMED] superseded orchestration only.

### Run 5 - `37382333185`

- attempt `1`, commit `5da98c6a81fa8afb798a50d1eedf6e2fb0de6b2f`;
- windows-2025 job `112007216565`, runner `1000000568`;
- windows-2022 job `112007217043`, runner `1000000569`;
- both cancelled during runtime download; probe skipped.

Classification: [CONFIRMED] superseded orchestration only.

### Run 6 - `37382459339`

- attempt `1`, commit `8176e5cdbbee5a63a5043edf5d5aed0a9e420fdf`;
- windows-2022 job `112007610957`, runner `1000000570`: runtime verified, probe began then was cancelled by the next code push; partial artifact/summary existed;
- windows-2025 job `112007611113`, runner `1000000571`: cancelled during runtime download, probe skipped.

Classification: [CONFIRMED] incomplete/superseded. No partial report is acceptance evidence.

[CONFIRMED] Commit `8176e5c...` also narrowed the functional workflow trigger to spike-code/workflow paths, so later documentation-only commits no longer create redundant functional runs.

### Run 7 - `37382675122`

- attempt `1`, commit `a4f600765196be27c68c18f6785666fe554d0b7a`;
- windows-2025 job `112008579361`, runner `1000000573`;
- windows-2022 job `112008579686`, runner `1000000574`;
- both cancelled during runtime download by the harness follow-up commit; probe skipped.

Classification: [CONFIRMED] superseded before testing the complete corrected model.

### Run 8 - `37382909046` - accepted

- run number `8`, attempt `1`, event `push`;
- commit `bee976eebf98257d39005020c264db769c7ba68c`;
- created `2026-10-05T22:30:26Z`, completed `2026-10-05T22:34:25Z`;
- conclusion `success`.

Windows 2022:

- job `112009129958`;
- runner `GitHub Actions 1000000576`, runner ID `1000000576`;
- started `2026-10-05T22:30:40Z`, completed `2026-10-05T22:33:19Z`;
- artifact ID `11375417797`, size `1925` bytes;
- digest `sha256:46731edd4c774cd38a65ce9d9141943870e21afc7ab15f601484309d78b022f4`;
- artifact expires `2027-01-03T22:30:27Z`.

Windows 2025:

- job `112009129747`;
- runner `GitHub Actions 1000000577`, runner ID `1000000577`;
- started `2026-10-05T22:30:40Z`, completed `2026-10-05T22:34:24Z`;
- artifact ID `11376252062`, size `1919` bytes;
- digest `sha256:bd8560ff446a621bd1bb7451ecad76718516c60f35e03d70ae214354461c85fe`;
- artifact expires `2027-01-03T22:30:27Z`.

[CONFIRMED] Both inspected V2 reports contain `PassCount=27`, `FailCount=0`, `Fatal=null`. Exact reports and run metadata are under `docs/phase1/evidence/phase1c-local-web-security-37382909046/`.

## Accepted V2 gates

Both systems passed:

- loopback-only listener and forged-Host rejection;
- one-time bootstrap;
- **no ambient session cookie** (`NO_SESSION_COOKIE`);
- explicit session header required, wrong session rejected and valid session accepted;
- exact Origin enforcement;
- CSRF missing/wrong rejection and valid mutation;
- foreign CORS preflight rejection with no ACAO;
- restrictive CSP, nosniff, no-referrer, no-store, COOP and CORP;
- process-restart session invalidation;
- logout invalidation;
- **complete four-stream stdout/stderr capture** (`OUTPUT_CAPTURE_COMPLETE`);
- no raw bootstrap/session/CSRF values in the completely captured output (`NO_TOKEN_LOG_LEAK`).

## Historical-source evidence

The reference web UI was inspected read-only at `atsisqual/SISQUALManagementConsole` commit `9756ba956842884fabcf25b82c4fbf1d11cf56bd`: `Program.cs`, `appsettings.json`, IIS auth setup in `Install.ps1` and `tests/Test-WebProject.Static.ps1`.

[CONFIRMED] The old UI used IIS Windows Authentication/Negotiate + authorization policies + ASP.NET antiforgery; `AllowedHosts` was `*`. Useful security principles are retained, but that IIS/Negotiate architecture is not copied into the portable Pode design.

## Pode evidence

Pode 2.14.1 tag resolves to `42faafcbd0edf2ffcabd5011a1b03dfbc00c28c4`.

[CONFIRMED] The final accepted candidate does not rely on a Pode/browser session cookie for authentication; Pode remains the HTTP adapter.

## Acceptance boundary

[CONFIRMED] The corrected non-ambient local HTTP/browser boundary is technically viable on the two tested Windows images.

[PROPOSED] Product adoption still needs reviewer/owner acceptance.

[PENDING] Prove real vanilla-JS URL-fragment bootstrap, explicit `X-SISQUAL-Session` attachment and immediate fragment clearing. Session/CSRF values must remain in JavaScript memory only.

[PENDING] Final session lifetime/idle-extension policy.

[PENDING] Operation idempotency and controlled shutdown with active operations are the next separate Phase 1C task. `SERVER_STOPPED` is not graceful-shutdown evidence.
