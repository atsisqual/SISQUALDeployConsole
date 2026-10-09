# DEPLOYMENT_PREFLIGHT audit: Management model

**Status:** [PROPOSED]
**Original:** `cfg.ReviewManagementModel`
**Engine:** `Invoke-ReviewManagementModel`
**Evidence:** `main@f7989a6b9043b9b16300404eb7e1dd27ca06a2aa` and PR #67 branch `engine/deployment-preflight-v1`.

The original procedure reports free-text findings and has no issue-code column. `LOCAL_SERVER_MISSING`, `LOCAL_SERVER_MULTIPLE`, and `INSTANCE_SERVER_MISMATCH` are engine-owned names.

## Original checks versus engine

| Original finding / engine check | Original predicate, textual | Engine behavior | Coincidem? | T-SQL semantics that decide |
|---|---|---|---|---|
| `No enabled ManagedServer exists for the current machine.` / `LOCAL_SERVER_MISSING` | `WHERE NOT EXISTS (SELECT 1 FROM dbo.ManagedServer WHERE IsEnabled = 1 AND MachineName = @MachineName)` | Engine filters enabled `Context.Servers` and emits `LOCAL_SERVER_MISSING` when count is zero. Runtime construction already machine-scopes the catalog and requires one enabled local server before reviews. | **Nearest equivalent, not literal.** Engine does not repeat `MachineName = @MachineName`; it consumes the runtime-scoped server set. | Original machine equality is CI_AS with space padding. Runtime matching is case-insensitive Windows-name logic; duplicate/missing server states are also guarded before this review. |
| `ConfigBackupRoot is empty.` | `FROM dbo.ManagedServer AS S WHERE S.IsEnabled=1 AND S.MachineName=@MachineName AND NULLIF(LTRIM(RTRIM(S.ConfigBackupRoot)),N'') IS NULL` | No check in `Invoke-ReviewManagementModel`. | **No; original finding has no engine equivalent.** | Ordinary-space `LTRIM/RTRIM`; spaces-only becomes empty through `NULLIF`; tabs are not trimmed. |
| `No enabled database-copy policy exists.` | Local enabled server plus `NOT EXISTS (SELECT 1 FROM cfg.DatabaseCopyPolicy AS P WHERE P.ServerCode = S.ServerCode AND P.IsEnabled = 1)` | No check in this engine review. | **No; original finding has no engine equivalent.** | `MachineName` and `ServerCode` source equality is CI_AS/padded; new catalog codes are exact. |
| `No enabled copyable databases are registered.` | `WHERE NOT EXISTS (SELECT 1 FROM cfg.DatabaseDefinition WHERE IsEnabled=1 AND CopyEnabled=1)` | No check in this review. | **No; original finding has no engine equivalent.** | No text comparison in the predicate. |

## Engine-owned checks without an original equivalent

- `LOCAL_SERVER_MULTIPLE`: enabled `Context.Servers` count greater than one. The original only tests absence for the current machine; it does not emit a separate multiple-server finding.
- `INSTANCE_SERVER_MISMATCH`: with exactly one enabled server, every enabled instance whose nonempty `ServerCode` differs by exact comparison from the server code emits this `ERROR`. The original `ReviewManagementModel` contains no instance/server consistency predicate.

## Result

Only the first original finding has a nearby engine equivalent, and even that is evaluated through the portable runtime boundary instead of the original `MachineName` predicate. Three original management checks are absent, while the engine adds two own checks. This audit records parity only; it does not authorize changes to PR #67.
