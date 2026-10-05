# ADR-0001: Portable runtime - PowerShell 7, Pode and SQLite

**Status:** Accepted (2026-10-05). The runtime gates were validated by spike 1A (`docs/phase1/phase1a-results.md`). The IIS integration layer is decided separately in ADR-0006.
**Deciders:** project owner.
**Related:** ADR-0006. Open items are listed at the end.

## Context

SISQUALDeployConsole must be an administration tool for SISQUAL WFM environments that is Windows-only, portable (copy a folder, run `Start.cmd`), installs nothing, does not run as a service, is operated through a browser, reuses the PowerShell engines of the current Management Console, keeps a local cache and is normally used by one administrator at a time. The central `_sisqualMANAGEMENT` database stays authoritative; the tool only reads central configuration and executes locally (V1).

## Decision

Portable PowerShell 7 + Pode (HTTP adapter only) + SQLite (local cache and state) + vanilla HTML/CSS/JS, vendored in the release ZIP and pinned:

- PowerShell 7.6.6 (win-x64 ZIP), Pode 2.14.1, SQLite 3.53.4 engine. The SQLite managed provider is decided in Phase 1B.
- Pode is a transport adapter. Engines never reference Pode, so the HTTP layer can be replaced without touching engines, cache, sync or UI.
- SQLite is a local mirror and local state, never the authority.
- The process is alive only while the operator uses it. No Windows service, no scheduled task.
- The PowerShell 7 runtime comes from the ZIP, not from a machine installation.

## Evidence

Spike 1A on windows-2022 and windows-2025 (reports in `docs/phase1/evidence/phase1a-run37284187896/`):

- Pinned artifacts verified by SHA-256; portable `pwsh` 7.6.6 starts from the extracted ZIP (.NET 10.0.12).
- Pode imports, answers `/health` on 127.0.0.1, listens only on loopback and refuses a connection through the non-loopback IP.
- SQLite portable: version, WAL, create/insert, reopen and rollback.
- Cleanup leaves no port, process or temporary directory behind.

## Alternatives considered

| Option | Verdict |
|---|---|
| ASP.NET Core self-contained + SQLite | Official fallback if the reopen conditions below occur: stronger maturity, authentication and concurrency, but a large .NET code base and a bridge to PowerShell engines |
| PowerShell + own `HttpListener` | Rejected: would reimplement routing, sessions, CSRF, security headers and static files |
| WPF/WinUI desktop | Not preferred: mixes UI and engines and closes the web evolution path |

## Consequences

- Pode is a community project: version pinned, vendored and hash-verified, and replaceable behind the adapter.
- SQLite allows one writer at a time: writes go through a single coordinator, and V1 is single-operator with per-instance locking.
- The first run has no central snapshot and must stay in an initial-setup state.

## Reopen conditions

Remote API exposure; more than one simultaneous operator as a formal requirement; mandatory integrated Windows authentication; an always-on process; high write concurrency; Pode left without maintenance; PowerShell 7 incompatibilities that cannot be solved.

## Open items

SQLite managed provider and machine private-key storage (CNG versus machine-scope DPAPI), both Phase 1B. Local web security (session, CSRF, Host/Origin, CSP) and shutdown lifecycle, Phase 1C.
