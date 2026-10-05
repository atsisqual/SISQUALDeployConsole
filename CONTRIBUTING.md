# Contributing

## Workflow

1. Read `AGENTS.md`, `docs/decisions-log.md`, and the relevant ADRs/contracts.
2. List open pull requests before starting.
3. Create one branch from current `main` for one task.
4. Keep commits small and focused.
5. Open a PR; do not push directly to `main` and do not merge your own PR unless explicitly delegated.
6. After a timeout or interrupted session, resume the same branch and PR.

## Evidence labels

Use:

- `[CONFIRMED]` for demonstrated facts;
- `[PROPOSED]` for recommendations not yet approved;
- `[PENDING]` for unresolved decisions or missing evidence;
- `[V]` for work that still needs the specified real Windows/SISQUAL validation.

## Text and PowerShell requirements

- New or changed text files use ASCII and LF unless approved evidence requires otherwise.
- All changed `.ps1` files must parse with Windows PowerShell 5.1.
- Do not add real secrets, private keys, tokens, or production connection strings.
- Keep generated evidence separate from product code.

## Architecture and safety

- V1 never writes central configuration back to `_sisqualMANAGEMENT`.
- `atsisqual/SISQUALManagementConsole` is read-only reference material.
- Pode is an adapter only; engines must not depend on it.
- IIS implementation uses `Microsoft.Web.Administration` according to ADR-0006.
- Destructive operations require explicit human approval and the right validation environment.

## Pull request content

Every PR should state:

- scope and non-goals;
- evidence used;
- tests performed;
- security impact;
- remaining `[PENDING]` and `[V]` items;
- whether any contract or ADR is changed.
