# SISQUALDeployConsole

[CONFIRMED] SISQUALDeployConsole is a Windows-only, portable administration console for SISQUAL WFM environments. V1 reads a read-only configuration catalog shipped inside the portable package, verifies the package against a signed manifest, and executes approved operations on the local server. There is no central configuration database and no master server (owner decision of 2026-10-05, recorded in ADR-0007, accepted by the owner on 2026-10-05).

## Status

- [CONFIRMED] Phase 0 inventory is complete.
- [CONFIRMED] ADR-0001 accepts portable PowerShell 7 + Pode + SQLite.
- [CONFIRMED] ADR-0006 selects `Microsoft.Web.Administration` for IIS integration, subject to its remaining conditions.
- [CONFIRMED] Owner decisions of 2026-10-05 (ADR-0007, accepted 2026-10-05): the central `_sisqualMANAGEMENT` database ceases to exist and is replaced by per-machine read-only SQLite catalogs; the one-off conversion, verification, seal and credential tools live under `tools/` and use PowerShell 7.
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

Portable package (the whole folder is replaced to update)
  +--> package-manifest.json   SHA-256 of every file, signed, verified at startup
  +--> catalog-<ServerCode>.db  SQLite, read-only, one per machine

Credentials: outside the package, issued for this machine by the credential tool
Operation evidence: plain text logs, one file per day, configurable folder
```

Architectural rules:

- [CONFIRMED] Pode is an HTTP adapter only. Engines do not depend on Pode.
- [CONFIRMED] SQLite holds the read-only catalog inside the package. The application writes no database: locks and idempotency tokens are kept in memory and history goes to the text logs.
- [CONFIRMED] Credentials are never in the catalog or in the package; a separate credential tool issues a package bound to one machine (no master server).
- [PENDING] The long-term authority of the catalog (deferred by the owner), the signature algorithm and the trust bootstrap.
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
- `tools/` - separate tools run on demand by a person, not part of the portable application: engine export, conversion, verification and seal (PowerShell 7); added by the tool PRs.
- `docs/migration/` - the plan for converting `_sisqualMANAGEMENT` into per-machine catalogs.
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
