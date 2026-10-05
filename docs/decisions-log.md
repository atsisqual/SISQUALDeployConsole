# Decisions log

Newest last. Each entry names the decision, who took it and where the evidence is.

| Date | Decision | Decided by | Reference |
|---|---|---|---|
| 2026-10-03 | Independent repository; `SISQUALManagementConsole` is read-only reference. Pode only as HTTP adapter; SQLite only as cache and local state; central stays authoritative; atomic snapshot sync; V1 single operator; signed and encrypted credential packages; non-exportable machine key; dependencies pinned and vendored | Project owner | Architecture plan approved before Phase 0 |
| 2026-10-03 | V1 reads central configuration and executes locally; it never writes configuration back to the central database | Project owner | Phase 0 documents |
| 2026-10-04 | Phase 0 corrected: `ManagementSync.sql` is 29.5 MB with the full payload (an earlier read returned empty); PR #2 merged | Reviewer, with the project owner | PR #2, `docs/phase0/` |
| 2026-10-04 | Working rule: one branch and one PR per piece of work, no direct push to `main`, list open PRs before creating a new one, resume the same branch after a timeout | Project owner | Process agreed during Phase 0 |
| 2026-10-05 | Spikes run on disposable GitHub-hosted Windows runners (windows-2022 and windows-2025), not on SISQUAL servers; reports are published to temporary branches and the decisive runs are kept under `docs/phase1/evidence/` | Project owner | PR #4, PR #5, PR #7 |
| 2026-10-05 | ADR-0001 accepted (portable PowerShell 7, Pode, SQLite) after spike 1A | Project owner | ADR-0001 |
| 2026-10-05 | IIS integration through `Microsoft.Web.Administration` (option A), accepted with four conditions | Project owner | ADR-0006 |
| 2026-10-05 | PR #6 closed as a duplicate of PR #5 | Reviewer | PR #6 |
| 2026-10-05 | ADR-0006 confirmed (IIS through Microsoft.Web.Administration, four conditions) | Project owner | ADR-0006 |
| 2026-10-05 | Central sync transport: direct read-only SQL connection | Project owner | docs/roadmap.md section 4 |
| 2026-10-05 | V1 scope: all engines | Project owner | docs/roadmap.md section 4 |
