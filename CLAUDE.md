# CLAUDE.md

Read `AGENTS.md` first. It is the normative operating policy for AI agents in this repository.

## Project purpose

SISQUALDeployConsole is a portable Windows administration console for SISQUAL WFM. V1 reads a read-only configuration catalog (SQLite, one per machine, inside the signed portable package) and executes approved operations on the local machine. There is no central database and no master server (owner decision of 2026-10-05, ADR-0007, Proposed). It writes no configuration and no database.

## Required context before changes

1. `AGENTS.md`
2. `docs/decisions-log.md`
3. relevant ADRs under `docs/architecture/`
4. relevant contract under `contracts/`
5. relevant `docs/skills/*/SKILL.md`
6. `docs/roadmap.md` when present on the working branch

Use `[CONFIRMED]`, `[PROPOSED]`, `[PENDING]`, and `[V]` exactly as defined in `AGENTS.md`.

## Repository process

- List open PRs before starting a task.
- One branch and one PR per task, from current `main`; if the task depends on an open PR, branch from that PR and use it as the base, and say so in the PR ([PROPOSED]).
- Record an owner decision only when it can be traced to a message or an approved document; otherwise write `[PENDING]` and ask.
- After a timeout, resume the same branch and PR.
- Never push directly to `main`.
- Never merge unless explicitly delegated by the project owner.
- Keep commits small and reviewable.
- Use ASCII and LF for changed text files unless approved evidence requires otherwise.

## Safety

- Never commit real credentials, keys, tokens, or production secrets.
- Never modify `atsisqual/SISQUALManagementConsole`; it is read-only reference evidence.
- Do not execute destructive operations without explicit human approval and the required validation environment.
- Never execute text stored in the catalog or in any data (for example `ScriptText`, `SqlCommand`, `CommandText`); local versioned modules are the executable authority.
- Do not expose Pode outside loopback by default.

## Architecture summary

- [CONFIRMED] PowerShell 7.6.6 portable runtime.
- [CONFIRMED] Pode 2.14.1 as HTTP adapter only.
- [CONFIRMED] SQLite 3.53.4 engine for the read-only catalog; the managed provider (read-only open only) remains Phase 1B until approved.
- [CONFIRMED] IIS integration through `Microsoft.Web.Administration`, subject to ADR-0006 conditions.
- [CONFIRMED] Owner decision of 2026-10-05 (ADR-0007, Proposed until formally accepted): no central database, no runtime sync, no master server; a read-only catalog per machine; a signed manifest verified at startup; credentials from a separate credential tool.
- [CONFIRMED] The conversion, verification, seal and credential tools are under `tools/`, outside the portable application, and use PowerShell 7.

When unsure whether a change is local implementation detail or an architectural decision, stop at `[PROPOSED]` and request review instead of silently deciding it.
