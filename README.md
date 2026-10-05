# SISQUALDeployConsole

[CONFIRMED] SISQUALDeployConsole is a Windows-only, portable administration console for SISQUAL WFM environments. V1 reads central configuration, caches it locally, and executes approved operations on the local server. It never writes configuration back to the central `_sisqualMANAGEMENT` database.

## Status

- [CONFIRMED] Phase 0 inventory is complete.
- [CONFIRMED] ADR-0001 accepts portable PowerShell 7 + Pode + SQLite.
- [CONFIRMED] ADR-0006 selects `Microsoft.Web.Administration` for IIS integration, subject to its remaining conditions.
- [PROPOSED] Product runtime and contracts are still under construction; no production deployment is supported yet.

## Quickstart for contributors

1. Read `AGENTS.md`.
2. Read `docs/decisions-log.md` and the relevant ADRs under `docs/architecture/`.
3. Check `docs/roadmap.md` when it exists on the branch you are working from.
4. List open pull requests before starting work.
5. Create one branch and one pull request per piece of work from `main`.
6. Do not push directly to `main` and do not merge your own PR.
7. Run or review the Windows CI checks before requesting review.

The release target is a folder copied to a Windows server and started with `Start.cmd`. No installer, Windows service, or scheduled task is part of V1.

## Architecture in one page

```text
Browser
  |
  | loopback HTTP only
  v
Pode HTTP adapter
  |
  v
Application services / operation coordinator
  |                         \
  |                          +--> local security / machine identity
  v
Versioned PowerShell engines
  |
  +--> Windows / IIS via Microsoft.Web.Administration
  +--> Windows services
  +--> local and target SQL connections
  +--> files and other approved local resources

Central _sisqualMANAGEMENT --read only--> validated snapshot --> local SQLite
                                                        |
                                                        +--> central mirror
                                                        +--> local state
                                                        +--> operation evidence
```

Architectural rules:

- [CONFIRMED] Pode is an HTTP adapter only. Engines do not depend on Pode.
- [CONFIRMED] SQLite is cache/local state, never central authority.
- [CONFIRMED] V1 is single-operator and uses constrained operation locking.
- [CONFIRMED] IIS uses `Microsoft.Web.Administration` under PowerShell 7; WebAdministration cmdlets are not the V1 IIS implementation.
- [CONFIRMED] Dependencies are pinned and vendored in release packaging.
- [PROPOSED] Mutating engines expose preview/apply semantics and structured results.
- [PENDING] Phase 1B decides the managed SQLite provider and machine private-key storage.
- [PENDING] Phase 1C closes local web session, CSRF, Host/Origin, CSP, and shutdown lifecycle controls.

## Repository map

- `docs/architecture/` - architecture decision records.
- `docs/phase0/` - current-system inventory and risks.
- `docs/phase1/` - spike results and evidence.
- `docs/skills/` - operational skill specifications; implementation scripts arrive after engine ports mature.
- `spikes/` - disposable architecture validation scripts, not product runtime.
- `contracts/` - versioned external/internal contracts as they are approved.
- `tests/` - unit, contract, integration, static, security, and fixture assets.
- `vendor/manifest.json` - pinned portable dependency inventory.

## Source of truth

Use this order when evidence conflicts:

1. validated real-server or recorded spike evidence;
2. approved ADRs and explicit project-owner decisions;
3. versioned contracts;
4. current code in this repository;
5. `atsisqual/SISQUALManagementConsole` as read-only historical/reference evidence;
6. agent inference, always labelled.

## Safety boundary

This repository must never contain real credentials, private keys, tokens, production connection strings, or copied secret values. Destructive server operations require explicit human approval and validation evidence before production use.
