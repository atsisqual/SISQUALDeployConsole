# ADR-0006: IIS integration through Microsoft.Web.Administration

**Status:** Accepted with conditions (2026-10-05, approved by the project owner as "option A").
**Amends:** ADR-0001 (IIS integration layer only; the runtime decision stands).
**Evidence:** `docs/phase1/phase1a-results.md`, `docs/phase1/evidence/`.

## Context

The current engines manage IIS with WebAdministration cmdlets, the `IIS:\` provider and `Microsoft.Web.Administration` (MWA). Spike 1A showed that under PowerShell 7 the WebAdministration cmdlets and the `IIS:\` provider fail on Windows Server 2022 and 2025 (`The data is invalid`, `0x8007000D`, native and forced compatibility), while the same reads work in Windows PowerShell 5.1 on the same machine. MWA and the `IISAdministration` module read correctly in PowerShell 7. Spike 1A-2 then tested the write path.

## Decision

IIS is managed through `Microsoft.Web.Administration` directly, from PowerShell 7. The WebAdministration cmdlets and the `IIS:\` provider are not used under PowerShell 7.

Evidence for the write path (run 37290642287, 22 of 22 checks, windows-2022 and windows-2025): creation and modification of pools, a site with http and https bindings (certificate registered in http.sys), applications, virtual directories and per-location settings; HTTP 200 served; stop, start and recycle; drift correction; idempotent re-apply; 0 configuration differences against the current approach over 233-242 properties; the 5.1 cmdlets read what MWA wrote.

## Alternatives considered

| Option | Verdict |
|---|---|
| B. PowerShell 7 orchestrates and IIS engines run in a Windows PowerShell 5.1 child process | Kept as a fallback for any rule MWA cannot cover; not the default because it keeps the legacy dependency and needs an extra process boundary |
| C. Everything in Windows PowerShell 5.1 | Rejected: gives up the portable runtime of ADR-0001 |
| `IISAdministration` module | Informational only: works in PowerShell 7 but covers less than MWA |

## Conditions (all PENDING)

1. Equivalence matrix between every `IIS_RECONCILE` rule (about 11 distinct cmdlets plus the `IIS:\` provider) and its MWA counterpart, reviewed before the engine is ported.
2. A run of the write spike on a sandbox with a real topology (hundreds of pools, existing drift, locked sections) [V].
3. A test of application pool identity with real credentials, SNI and central certificate store bindings, and handler and module sections.
4. Changes are committed in batches and the certificate store name is standardised as `MY`.

## Consequences

- The write paths of `IIS_RECONCILE` are rewritten on MWA; reads keep working in 5.1 during the transition because both sides use the same IIS configuration.
- Speed is not a reason for this decision: the large gain seen in the spike comes from batching, which is also possible with MWA in 5.1.
- The spike scripts create and remove IIS objects, a local user and a certificate, so they run only on disposable machines (GitHub-hosted runners).

## Reopen conditions

MWA cannot cover a required rule and the 5.1 fallback would be needed for more than a few rules; MWA behaves differently on a real server in a way that breaks equivalence.
