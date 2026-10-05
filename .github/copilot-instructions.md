# GitHub Copilot instructions

Follow `AGENTS.md` as the normative project policy.

Before proposing code or documentation changes, read `docs/decisions-log.md`, the relevant ADR, the relevant contract, and any related `docs/skills/*/SKILL.md`.

Project rules:

- Use `[CONFIRMED]`, `[PROPOSED]`, `[PENDING]`, `[V]`.
- Central `_sisqualMANAGEMENT` configuration is authoritative and read-only from V1.
- Pode is only the HTTP adapter; engine modules must not depend on Pode.
- SQLite is local mirror/state, never central authority.
- IIS code targets `Microsoft.Web.Administration`, not WebAdministration cmdlets under PowerShell 7.
- `atsisqual/SISQUALManagementConsole` is read-only reference material.
- Never suggest or insert real credentials, tokens, keys, or production secret values.
- Never use `Invoke-Expression` with external input.
- Never construct arbitrary SQL from browser input.
- Validate filesystem paths against approved roots.
- Bind local HTTP to loopback only by default.
- PowerShell must parse with Windows PowerShell 5.1 until that requirement is explicitly changed.
- Prefer small, deterministic, testable functions and structured results.
- For mutable engines, preserve preview/apply, target validation, idempotency, backup evidence, and secret-safe logs.

Repository workflow:

- one branch and one PR per task;
- no direct push to `main`;
- resume the same branch after timeout;
- ASCII and LF for changed text files unless approved evidence requires otherwise.

Do not turn a `[PENDING]` decision into implementation policy without explicit approval.
