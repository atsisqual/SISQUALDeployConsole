# Phase 1 - Results of spikes 1A and 1A-2

**Date:** 2026-10-05
**Status:** results recorded. The decision in section 6 is **[PROPOSED]** and needs human approval.
Vocabulary: [CONFIRMED] demonstrated by a run, [PROPOSED] recommended, not approved, [PENDING] still unknown, [V] needs validation on a real SISQUAL server.

## 1. Scope and environment

- Executed on GitHub-hosted ephemeral runners: `windows-2022` (build 20348) and `windows-2025`, elevated, with Windows PowerShell 5.1 as launcher. Nothing ran on a SISQUAL server.
- Pinned artifacts, SHA-256 verified on the runner by the script: PowerShell 7.6.6 (win-x64 ZIP), Pode 2.14.1, SQLite tools 3.53.4. Observed runtime: .NET 10.0.12.
- Scripts: `spikes/phase1A/Test-Phase1A.ps1` (PR #4) and `spikes/phase1A-iis/Test-IisWrite.ps1` (PR #5). The reports were published by the workflows to temporary `results/*` branches; the two final runs are kept under `docs/phase1/evidence/` and the temporary branches were removed.

## 2. Phase 1A - portable runtime (run 37284187896, commit 463c8e786b)

The script's own verdict is FAIL, only because its critical list still includes the WebAdministration checks (see finding 1).

| Area | windows-2022 | windows-2025 |
|---|---|---|
| SHA-256 of the three artifacts | PASS | PASS |
| Portable pwsh 7.6.6 starts from the extracted ZIP | PASS | PASS |
| SQLite SHA3-256 against the sqlite.org value | WARN (SHA3 not supported by this OS/.NET) | PASS |
| Pode: import, `/health` on 127.0.0.1, listener only on loopback, connection through the non-loopback IP refused | PASS | PASS |
| SQLite portable: version, WAL, create/insert, reopen, rollback | PASS | PASS |
| Cleanup: port, processes, temporary directory | PASS | PASS |
| IIS reads with WebAdministration in Windows PowerShell 5.1 (control) | PASS | PASS |
| WebAdministration under PowerShell 7 (native and forced compatibility) | FAIL `0x8007000D` | FAIL `0x8007000D` |
| `IIS:\` provider under PowerShell 7 | FAIL | FAIL |
| Microsoft.Web.Administration loaded directly in PowerShell 7 (read) | PASS | PASS |
| IISAdministration 1.1.0.0 in PowerShell 7 (read, no compatibility session) | PASS | PASS |
| Mutating WebAdministration cmdlets resolved with `Get-Command` in compatibility mode (not executed) | PASS | PASS |

## 3. Phase 1A-2 - IIS write path (run 37290642287, commit 4909851b73)

22 of 22 checks PASS on both runners. The scenario creates pools, a site with http and https bindings (self-signed certificate), applications, virtual directories and per-location settings, first with the current approach (Windows PowerShell 5.1 with cmdlets and MWA, as `IIS_RECONCILE` does) and then with PowerShell 7 and `Microsoft.Web.Administration` only.

- PowerShell 7 + MWA creates and modifies the full scenario; the site answers HTTP 200 through the primary and the extra binding; the https binding registers the certificate in http.sys.
- Stop, start and recycle of a pool and a site work, and the 5.1 cmdlets confirm the states.
- Drift correction works. Applying the same scenario twice changes nothing (239 properties compared on 2022, 242 on 2025).
- Equivalence with the current approach: 0 configuration differences over 233-242 properties. Runtime state of `w3wp` worker processes is excluded.
- Windows PowerShell 5.1 cmdlets read everything that MWA wrote, so a gradual migration is possible.

| Measure (8 sites, 200 applications, 208 pools) | Current approach 2022 / 2025 | MWA in PowerShell 7 2022 / 2025 |
|---|---|---|
| Apply the create scenario | 31.4 s / 39.4 s | 0.33 s / 0.39 s |
| Create the scale topology | 25.5 s / 38.5 s | 0.15 s / 0.15 s |
| Enumerate pools | 597 ms / 588 ms | 10 ms / 9 ms |

## 4. Findings

1. [CONFIRMED] The WebAdministration cmdlets and the `IIS:\` provider are not usable under PowerShell 7 on either Windows Server generation (`The data is invalid`, `0x8007000D`), while the same reads work in Windows PowerShell 5.1 on the same machine. The root cause was not identified.
2. [CONFIRMED] `Microsoft.Web.Administration` works in PowerShell 7 for the complete write path tested.
3. [CONFIRMED] One cosmetic difference: the certificate store name is stored as `MY` by the current approach and as `My` when MWA is given `My`. It is the same store; use `MY` to avoid false drift.
4. [CONFIRMED] The speed difference is mostly one batched commit versus one commit per object. The same batching is possible with MWA in Windows PowerShell 5.1, so speed alone does not justify PowerShell 7.
5. [CONFIRMED] Process lessons for future scripts: the syntax check must use the Windows PowerShell 5.1 parser (the PowerShell 7 parser accepts `break` inside `finally`, 5.1 does not); a `[pscustomobject]` cast over an ordered dictionary raised `ArgumentException` in 5.1; variable names are case-insensitive (a local `$sites` collided with `[int]$Sites`); `Import-Module` has no `-LiteralPath`; `$PSScriptRoot` arrived empty in a parameter default under 5.1; `Locales\*\Pode.psd1` are message tables, not the module manifest; SHA3 is unavailable on Windows Server 2019/2022.

## 5. Not covered

- [PENDING] An equivalence matrix between every `IIS_RECONCILE` rule (about 11 distinct cmdlets plus the `IIS:\` provider) and its MWA counterpart.
- [PENDING] Application pool identity with real credentials, SNI and central certificate store bindings, handler and module sections.
- [V] A real topology (hundreds of pools, years of drift, locked sections). The runners had a fresh IIS.
- [V] Windows Server 2019 and any machine that is not a GitHub-hosted runner.
- The spike scripts create and remove sites, a local user and a certificate. They must run only on disposable machines.

## 6. Proposed decision [PROPOSED]

Keep ADR-0001 (portable PowerShell 7 runtime, Pode, SQLite) and amend the IIS integration layer:

1. IIS is managed through `Microsoft.Web.Administration` directly (option A). The WebAdministration cmdlets and the `IIS:\` provider are not used under PowerShell 7.
2. Accepted only after: the equivalence matrix (section 5), a run of the write spike on a sandbox with a real topology, and a test of pool identity with credentials.
3. Commit in batches, and standardise the certificate store name as `MY`.
4. Keep Windows PowerShell 5.1 available as a fallback child process for any rule MWA cannot cover.

## 7. Recommended integration order [PROPOSED]

1. This documentation PR.
2. PR #4, after moving `IIS_WEBADMIN_COMPAT` and `IIS_PROVIDER` out of the critical list (they are an expected limitation, not a gate) and re-running.
3. PR #5.

Merging the workflows also enables `workflow_dispatch`, so the spikes can be re-run on future runner images.

## 8. Run history

| Run | Commit | Outcome and what it revealed |
|---|---|---|
| 37247895632, 37248360996 | efe6a9f, e2284eb | Spike failed at start: parse error in Windows PowerShell 5.1 (`break` inside `finally`) |
| 37248735271 | e62cc3b | `$PSScriptRoot` empty in a parameter default |
| 37249280237 | e96336a | `ArgumentException` while building the report; no report |
| 37249885817 | 9750c97 | Diagnostics added; Pode import failed (`Import-Module -LiteralPath` does not exist) |
| 37250658176 | 87f3717 | Pode, SQLite and MWA pass; WebAdministration fails under PowerShell 7; report cast still failing |
| 37284187896 | 463c8e7 | Phase 1A final: full report, 5.1 control passes, MWA and IISAdministration pass |
| 37286541200 | cf4b8cb | Phase 1A-2: harness bugs only (volatile keys, variable collision, wrong threshold) |
| 37289281915 | 64aa35f | Duplicate PR #6, stopped at the first write step; closed in favour of PR #5 |
| 37290642287 | 4909851 | Phase 1A-2 final: 22/22 PASS on both runners |

## 9. Evidence

- `docs/phase1/evidence/phase1a-run37284187896/` report and console of windows-2022 and windows-2025.
- `docs/phase1/evidence/phase1a2-run37290642287/` report and console of windows-2022 and windows-2025.
