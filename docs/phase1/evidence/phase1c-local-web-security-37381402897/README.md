# Phase 1C local web security - superseded run 37381402897

**Workflow:** `phase1c-local-web-security`
**Workflow ID:** `375855729`
**Run ID:** `37381402897`
**Run number:** `3`
**Attempt:** `1`
**Tested commit:** `9c27190bc1616278e59de5391425f66ea72fa747`
**GitHub conclusion:** [CONFIRMED] `success`
**Security classification:** [CONFIRMED] superseded design; not accepted evidence after PR review.

Both Windows jobs executed the original cookie-based probe and each report records `27 PASS / 0 FAIL`. Those execution facts remain valid and are preserved. The product-security conclusion is not valid because the test model omitted a cross-port cookie threat identified during review.

## Original execution identifiers

Windows 2022:

- job `112004092392`;
- runner `GitHub Actions 1000000558`, runner ID `1000000558`;
- artifact ID `11374356055`, size `1859` bytes;
- digest `sha256:12ea9164fb9a66d4c4d04ce0bc5be090bb6b0450db308b8a27b02957d70b4fe8`;
- artifact expires `2027-01-03T22:16:33Z`;
- exact report: `report-windows-2022.json`.

Windows 2025:

- job `112004092351`;
- runner `GitHub Actions 1000000559`, runner ID `1000000559`;
- artifact ID `11375770246`, size `1860` bytes;
- digest `sha256:1b61967c89885f88817f902b1faa15748c25de60d9f8501cd41bc42b41ac964a`;
- artifact expires `2027-01-03T22:16:33Z`;
- exact report: `report-windows-2025.json`.

## Why the green result was superseded

[CONFIRMED] Codex review comment `4189467569` identified that browser cookies are scoped by host/path, not TCP port. A `SISQUAL-SESSION` cookie received from `127.0.0.1:<product-port>` (or `localhost:<product-port>`) can therefore be sent automatically to an unrelated loopback service on another port. A malicious local listener could receive that ambient credential and replay it against the product port.

[CONFIRMED] `HttpOnly` and `SameSite=Strict` do not create port isolation, so the original cookie gates did not test the relevant local-process threat.

[CONFIRMED] The fix removes the session cookie entirely. The replacement candidate returns a random session credential at bootstrap and requires the UI to attach it explicitly as `X-SISQUAL-Session`; it must live only in JavaScript memory, not cookies, localStorage or sessionStorage.

## Second review finding

[CONFIRMED] Review comment `4189467573` found that stdout/stderr capture errors were swallowed, so `NO_TOKEN_LOG_LEAK` could pass without complete observation.

[CONFIRMED] The replacement harness makes output capture fail-closed and adds `OUTPUT_CAPTURE_COMPLETE`; `NO_TOKEN_LOG_LEAK` cannot pass when capture is incomplete.

## Historical value

The original reports remain useful evidence that the first harness executed correctly for the checks it contained. They must not be cited as acceptance of the Phase 1C security boundary.

The next accepted run must use report schema `SISQUAL_PHASE1C_LOCAL_WEB_SECURITY_V2` and prove the non-ambient session-header model plus fail-closed output capture on both Windows runner versions.
