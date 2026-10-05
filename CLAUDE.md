# CLAUDE.md

Read `AGENTS.md` first. It is the normative operating policy for AI agents in this repository.

## Project purpose

SISQUALDeployConsole is a portable Windows administration console for SISQUAL WFM. V1 reads central configuration, caches validated state locally, and executes approved operations on the local machine. It does not write configuration back to the central database.

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
- One branch and one PR per task, from current `main`.
- After a timeout, resume the same branch and PR.
- Never push directly to `main`.
- Never merge unless explicitly delegated by the project owner.
- Keep commits small and reviewable.
- Use ASCII and LF for changed text files unless approved evidence requires otherwise.

## Safety

- Never commit real credentials, keys, tokens, or production secrets.
- Never modify `atsisqual/SISQUALManagementConsole`; it is read-only reference evidence.
- Do not execute destructive operations without explicit human approval and the required validation environment.
- Do not trust central executable `ScriptText` as V1 runtime authority; local versioned modules are the executable authority.
- Do not expose Pode outside loopback by default.

## Architecture summary

- [CONFIRMED] PowerShell 7.6.6 portable runtime.
- [CONFIRMED] Pode 2.14.1 as HTTP adapter only.
- [CONFIRMED] SQLite 3.53.4 engine for local cache/state; managed provider remains Phase 1B until approved.
- [CONFIRMED] IIS integration through `Microsoft.Web.Administration`, subject to ADR-0006 conditions.
- [CONFIRMED] central configuration is read-only in V1.

When unsure whether a change is local implementation detail or an architectural decision, stop at `[PROPOSED]` and request review instead of silently deciding it.
