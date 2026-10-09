# DEPLOYMENT_PREFLIGHT audit: Management model

**Status:** [PROPOSED]
**Original:** `cfg.ReviewManagementModel`
**Engine:** `Invoke-ReviewManagementModel`
**Evidence:** `main@f7989a6b9043b9b16300404eb7e1dd27ca06a2aa` and PR #67 branch `engine/deployment-preflight-v1`.

The original procedure reports free-text findings and has no issue-code column. `LOCAL_SERVER_MISSING`, `LOCAL_SERVER_MULTIPLE`, and `INSTANCE_SERVER_MISMATCH` are engine-owned names.

`Tipo` classifies every observable difference: `ARQUITECTURAL` is an approved portable-system difference that E0h must preserve; `DIVERGENCIA` is parity work for E0h. If a row contains both, it is classified `DIVERGENCIA` and the approved sub-difference is called out explicitly.

## Original predicate text

The following block is copied verbatim from `docs/handoff/preflight-legacy-procedures-implemented.sql.txt` on `main`.

```sql
CREATE OR ALTER PROCEDURE [cfg].[ReviewManagementModel]
    @MachineName sysname = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @MachineName = COALESCE(NULLIF(@MachineName, N''),
        CONVERT(sysname, SERVERPROPERTY('MachineName')));

    SELECT
        Severity = 'ERROR',
        ObjectType = 'ManagedServer',
        ObjectCode = CONVERT(nvarchar(200), @MachineName),
        Issue = N'No enabled ManagedServer exists for the current machine.'
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM dbo.ManagedServer
        WHERE IsEnabled = 1
          AND MachineName = @MachineName
    )

    UNION ALL

    SELECT
        'ERROR',
        'ManagedServer',
        S.ServerCode,
        N'ConfigBackupRoot is empty.'
    FROM dbo.ManagedServer AS S
    WHERE S.IsEnabled = 1
      AND S.MachineName = @MachineName
      AND NULLIF(LTRIM(RTRIM(S.ConfigBackupRoot)), N'') IS NULL

    UNION ALL

    SELECT
        'ERROR',
        'DatabaseCopyPolicy',
        S.ServerCode,
        N'No enabled database-copy policy exists.'
    FROM dbo.ManagedServer AS S
    WHERE S.IsEnabled = 1
      AND S.MachineName = @MachineName
      AND NOT EXISTS
      (
          SELECT 1
          FROM cfg.DatabaseCopyPolicy AS P
          WHERE P.ServerCode = S.ServerCode
            AND P.IsEnabled = 1
      )

    UNION ALL

    SELECT
        'ERROR',
        'DatabaseDefinition',
        N'<catalogue>',
        N'No enabled copyable databases are registered.'
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM cfg.DatabaseDefinition
        WHERE IsEnabled = 1
          AND CopyEnabled = 1
    )
;
END;
```

## Original checks versus engine

| Original finding / engine check | Original predicate, textual | Engine behavior | Coincidem? | Tipo | T-SQL semantics that decide |
|---|---|---|---|---|---|
| `No enabled ManagedServer exists for the current machine.` / `LOCAL_SERVER_MISSING` | `WHERE NOT EXISTS (SELECT 1 FROM dbo.ManagedServer WHERE IsEnabled = 1 AND MachineName = @MachineName)` | Engine filters enabled `Context.Servers` and emits `LOCAL_SERVER_MISSING` when count is zero. Runtime construction already machine-scopes the catalog and requires one enabled local server before reviews. | **Nearest equivalent, not literal.** Engine does not repeat `MachineName = @MachineName`; it consumes the runtime-scoped server set. | **ARQUITECTURAL** - machine-local catalog/runtime scoping is approved; E0h must not reintroduce a central-machine lookup merely for textual parity. | Original machine equality is CI_AS with space padding. Runtime matching is case-insensitive Windows-name logic; duplicate/missing server states are also guarded before this review. |
| `ConfigBackupRoot is empty.` | `FROM dbo.ManagedServer AS S WHERE S.IsEnabled=1 AND S.MachineName=@MachineName AND NULLIF(LTRIM(RTRIM(S.ConfigBackupRoot)),N'') IS NULL` | No check in `Invoke-ReviewManagementModel`. | **No; original finding has no engine equivalent.** | **DIVERGENCIA** - E0h must port this original finding using the machine-local server already resolved by the runtime. | Ordinary-space `LTRIM/RTRIM`; spaces-only becomes empty through `NULLIF`; tabs are not trimmed. |
| `No enabled database-copy policy exists.` | Local enabled server plus `NOT EXISTS (SELECT 1 FROM cfg.DatabaseCopyPolicy AS P WHERE P.ServerCode = S.ServerCode AND P.IsEnabled = 1)` | No check in this engine review. | **No; original finding has no engine equivalent.** | **DIVERGENCIA** - E0h must port the policy-presence check; exact portable `ServerCode` comparison remains architectural. | `MachineName` and `ServerCode` source equality is CI_AS/padded; new catalog codes are exact. |
| `No enabled copyable databases are registered.` | `WHERE NOT EXISTS (SELECT 1 FROM cfg.DatabaseDefinition WHERE IsEnabled=1 AND CopyEnabled=1)` | No check in this review. | **No; original finding has no engine equivalent.** | **DIVERGENCIA** - E0h must port this predicate. | No text comparison in the predicate. |

## Engine-owned checks without an original equivalent

| Engine check | Tipo | E0h disposition |
|---|---|---|
| `LOCAL_SERVER_MULTIPLE` | **DIVERGENCIA** | The original review has no such finding. Runtime uniqueness remains an approved boundary, but this engine-owned review finding must not count as an original check; E0h must reconcile it explicitly. |
| `INSTANCE_SERVER_MISMATCH` | **DIVERGENCIA** | The original review contains no instance/server consistency finding. E0h must reconcile this extra check separately; exact portable code comparison itself remains architectural. |

## Result

Only the first original finding has a nearby engine equivalent, and its difference is architectural because the portable runtime supplies the machine-local server. Three original management checks are absent and are `DIVERGENCIA`; the two engine-owned findings are also not original parity and must be reconciled by E0h without undoing runtime machine-local scoping or exact catalog-code behavior. This audit records parity only; it does not authorize changes to PR #67.
