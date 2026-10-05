# Decisions log

Newest last. Each entry names the decision, who took it and where the evidence is.

| Date | Decision | Decided by | Reference |
|---|---|---|---|
| 2026-10-03 | Independent repository; `SISQUALManagementConsole` is read-only reference. Pode only as HTTP adapter; SQLite only as cache and local state; central stays authoritative; atomic snapshot sync; V1 single operator; signed and encrypted credential packages; non-exportable machine key; dependencies pinned and vendored | Project owner | Architecture plan approved before Phase 0; superseded in part by ADR-0007 (2026-10-05) |
| 2026-10-03 | V1 reads central configuration and executes locally; it never writes configuration back to the central database | Project owner | Phase 0 documents; superseded in part by ADR-0007 (2026-10-05) |
| 2026-10-04 | Phase 0 corrected: `ManagementSync.sql` is 29.5 MB with the full payload (an earlier read returned empty); PR #2 merged | Reviewer, with the project owner | PR #2, `docs/phase0/` |
| 2026-10-04 | Working rule: one branch and one PR per piece of work, no direct push to `main`, list open PRs before creating a new one, resume the same branch after a timeout | Project owner | Process agreed during Phase 0 |
| 2026-10-05 | Spikes run on disposable GitHub-hosted Windows runners (windows-2022 and windows-2025), not on SISQUAL servers; reports are published to temporary branches and the decisive runs are kept under `docs/phase1/evidence/` | Project owner | PR #4, PR #5, PR #7 |
| 2026-10-05 | ADR-0001 accepted (portable PowerShell 7, Pode, SQLite) after spike 1A | Project owner | ADR-0001 |
| 2026-10-05 | IIS integration through `Microsoft.Web.Administration` (option A), accepted with four conditions | Project owner | ADR-0006 |
| 2026-10-05 | PR #6 closed as a duplicate of PR #5 | Reviewer | PR #6 |
| 2026-10-05 | ADR-0006 confirmed (IIS through Microsoft.Web.Administration, four conditions) | Project owner | ADR-0006 |
| 2026-10-05 | Central sync transport: direct read-only SQL connection | Project owner | docs/roadmap.md section 4; superseded in part by ADR-0007 (2026-10-05) |
| 2026-10-05 | V1 scope: all engines | Project owner | docs/roadmap.md section 4 |
| 2026-10-05 | ADR-0007 accepted: embedded read-only catalog, no runtime sync, `_sisqualMANAGEMENT` ceases to exist, text logs | Project owner ("Sim") | ADR-0007 |
| 2026-10-05 | Credentials come from a separate tool under `tools/` that issues a package valid for one machine; the application never contacts a server for this; no permanent master server | Project owner | contracts/credential-package.md |
| 2026-10-05 | One read-only SQLite catalog per existing machine (PT_DEMO, SANDBOX_HUB, ES_DEMO, BR_DEMO, PRESALES, TENDERS); the pilot is on a server without the current system | Project owner | ADR-0007, conversion plan |
| 2026-10-05 | Catalog conversion plan approved | Project owner ("Sim") | docs/migration/catalog-conversion-plan.md |
| 2026-10-05 | No template server for server policies; machines without policy rows are cut as they are | Project owner | conversion plan 2.6 |
| 2026-10-05 | Binary columns stay as BLOB; conversion tools use PowerShell 7 with Microsoft.Data.SqlClient; the engines also move to PowerShell 7 | Project owner | conversion plan section 8, AGENTS.md |
| 2026-10-05 | Column `ManagementDatabaseName` dropped; all databases are `Latin1_General_CI_AS`, nothing stored may change case, text is kept byte for byte and codes are compared exactly | Project owner | handoff note |
| 2026-10-05 | The five `SANDBOX_*_HUB` link rows are obsolete | Project owner | handoff note |
| 2026-10-05 | Credential package answers Q1 to Q10, option A each; Q2 includes the canonical form of the signed bytes and Q10 is a yes (both confirmed "Sim") | Project owner | contracts/credential-package.md section 8 |
| 2026-10-05 | The 16 exposed secrets are not rotated after the cutover (risk accepted) | Project owner | contracts/credential-package.md Q6 |
| 2026-10-05 | Package file name `credentials.pkg` | Project owner (name restated in the reply of 2026-10-05) | contracts/credential-package.md |
| 2026-10-05 | The seven engines outside the earlier plan enter V1; order chosen by the reviewer ("Tanto faz escolhe tu") | Reviewer, on the owner's delegation | docs/roadmap.md section 4 |
| 2026-10-05 | "Machines without a local database" closed as obsolete: every machine receives its catalog inside the portable | Reviewer, after the owner asked what was left to decide | ADR-0007 |
| 2026-10-05 | PRs #10 to #23 integrated into `main` in dependency order; temporary `results/*` branches removed (evidence kept under `docs/phase1/evidence/`) | Reviewer | PRs #10 to #23 |
