# Phase 1C local web security - accepted run 37381402897

**Workflow:** `phase1c-local-web-security`
**Workflow ID:** `375855729`
**Run ID:** `37381402897`
**Run number:** `3`
**Attempt:** `1`
**Event:** `push`
**Tested commit:** `9c27190bc1616278e59de5391425f66ea72fa747`
**Conclusion:** [CONFIRMED] `success`
**Created:** `2026-10-05T22:16:32Z`
**Completed:** `2026-10-05T22:19:51Z`

This is the accepted technical-evidence run for the Phase 1C local browser/HTTP boundary. Both Windows jobs executed the full probe. Each secret-safe report records `PassCount=27`, `FailCount=0`, `Fatal=null`.

## Windows Server 2022

- job ID: `112004092392`
- runner label: `windows-2022`
- runner: `GitHub Actions 1000000558`
- runner ID: `1000000558`
- job created: `2026-10-05T22:16:44Z`
- job started: `2026-10-05T22:16:46Z`
- job completed: `2026-10-05T22:19:33Z`
- runtime verification completed: `2026-10-05T22:19:15Z`
- security probe: `2026-10-05T22:19:15Z` to `2026-10-05T22:19:28Z`, success
- artifact name: `phase1c-local-web-security-windows-2022`
- artifact ID: `11374356055`
- artifact size: `1859` bytes
- artifact digest: `sha256:12ea9164fb9a66d4c4d04ce0bc5be090bb6b0450db308b8a27b02957d70b4fe8`
- artifact created: `2026-10-05T22:19:29Z`
- artifact expires: `2027-01-03T22:16:33Z`
- report: `report-windows-2022.json`

[CONFIRMED] The report used PowerShell `7.6.6`; all 27 gates passed. The non-loopback reachability negative test used runner address `10.1.1.55`; this is ephemeral GitHub-runner evidence, not SISQUAL network data.

## Windows Server 2025

- job ID: `112004092351`
- runner label: `windows-2025`
- runner: `GitHub Actions 1000000559`
- runner ID: `1000000559`
- job created: `2026-10-05T22:16:44Z`
- job started: `2026-10-05T22:16:52Z`
- job completed: `2026-10-05T22:19:50Z`
- runtime verification completed: `2026-10-05T22:19:20Z`
- security probe: `2026-10-05T22:19:20Z` to `2026-10-05T22:19:43Z`, success
- artifact name: `phase1c-local-web-security-windows-2025`
- artifact ID: `11375770246`
- artifact size: `1860` bytes
- artifact digest: `sha256:1b61967c89885f88817f902b1faa15748c25de60d9f8501cd41bc42b41ac964a`
- artifact created: `2026-10-05T22:19:44Z`
- artifact expires: `2027-01-03T22:16:33Z`
- report: `report-windows-2025.json`

[CONFIRMED] The report used PowerShell `7.6.6`; all 27 gates passed. The non-loopback reachability negative test used runner address `10.1.0.204`; this is ephemeral GitHub-runner evidence, not SISQUAL network data.

## Gate result

[CONFIRMED] Both runners passed:

- loopback-only listener reachability;
- protected route requires a session (`401` without it);
- forged Host rejected (`400`);
- valid bootstrap accepted (`200`);
- session cookie is `HttpOnly`, `SameSite=Strict`, `Path=/`;
- bootstrap is single-use (`403` on replay);
- valid session accepted (`200`);
- foreign Origin rejected (`403`);
- missing/wrong CSRF rejected (`403`);
- valid same-origin mutation accepted (`200`);
- foreign CORS preflight rejected (`403`) with no `Access-Control-Allow-Origin`;
- CSP, `nosniff`, `no-referrer`, `no-store`, COOP and CORP headers;
- listener disappears when the probe process is stopped;
- old in-memory session rejected after process restart (`401`);
- logout returns `204`, expires the cookie and invalidates the session;
- bootstrap/session/CSRF raw values absent from captured server stdout/stderr.

The reports contain no token values or production credentials.

## Interpretation boundary

[CONFIRMED] This run proves technical viability of the tested local HTTP/browser boundary on the two GitHub-hosted Windows images.

[PROPOSED] It does not by itself approve the bootstrap/session model as the product contract.

[PENDING] The real vanilla-JS browser flow that receives a bootstrap value through a URL fragment, posts it to the bootstrap endpoint and clears the fragment is not exercised by this backend probe.

[PENDING] Session lifetime/idle-extension policy is not decided by this run.

[PENDING] Controlled shutdown with active operations and operation idempotency are a separate Phase 1C task. `SERVER_STOPPED` proves only that the listener disappears after the probe process is terminated; it is not evidence of graceful shutdown.
