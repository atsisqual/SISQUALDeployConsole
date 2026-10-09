# DEPLOYMENT_PREFLIGHT audit: Operations framework

**Status:** [PROPOSED]
**Original:** `ops.ReviewOperationsFramework`
**Engine:** `Invoke-ReviewOperationsFramework`
**Evidence:** `main@f7989a6b9043b9b16300404eb7e1dd27ca06a2aa` and PR #67 branch `engine/deployment-preflight-v1`.

`Tipo` classifies every observable difference: `ARQUITECTURAL` is an approved portable-system difference that E0h must preserve; `DIVERGENCIA` is parity work for E0h. If a row contains both, it is classified `DIVERGENCIA` and the approved sub-difference is called out explicitly.

## Original predicate text

The following block is copied verbatim from `docs/handoff/preflight-legacy-procedures-implemented.sql.txt` on `main`.

```sql
CREATE OR ALTER PROCEDURE ops.ReviewOperationsFramework
    @MachineName sysname
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        IssueCode,
        Severity,
        ObjectCode,
        Details
    FROM
    (
        SELECT
            IssueCode = CONVERT(varchar(100),'OPS_PROFILE_MISSING'),
            Severity = CONVERT(varchar(10),'ERROR'),
            ObjectCode = CONVERT(nvarchar(300),'DEFAULT'),
            Details = CONVERT(nvarchar(2000),N'The enabled DEFAULT console profile is missing.')
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM ops.ConsoleProfile
            WHERE ProfileCode = 'DEFAULT'
              AND IsEnabled = 1
        )

        UNION ALL

        SELECT
            'OPS_ACTION_WITHOUT_ENGINE',
            'ERROR',
            A.ActionCode,
            N'Enabled ENGINE action has no enabled engine.'
        FROM ops.Action AS A
        LEFT JOIN ops.Engine AS E
            ON E.EngineCode = A.EngineCode
           AND E.IsEnabled = 1
        WHERE A.IsEnabled = 1
          AND A.ActionType = 'ENGINE'
          AND E.EngineCode IS NULL

        UNION ALL

        SELECT
            'OPS_ENGINE_HASH_MISMATCH',
            'ERROR',
            E.EngineCode,
            N'Engine ScriptSha256 does not match ScriptText.'
        FROM ops.Engine AS E
        WHERE E.IsEnabled = 1
          AND E.ScriptSha256 <>
              LOWER
              (
                  CONVERT
                  (
                      char(64),
                      HASHBYTES('SHA2_256',CONVERT(varbinary(max),E.ScriptText)),
                      2
                  )
              )

        UNION ALL

        SELECT
            'OPS_REQUIRED_OBJECT_MISSING',
            'ERROR',
            R.ActionCode + N'/' + R.RequirementCode,
            N'Missing required ' + R.RequirementType + N': ' + R.ObjectName
        FROM ops.ActionRequirement AS R
        WHERE R.IsEnabled = 1
          AND R.IsRequired = 1
          AND
          (
              (R.RequirementType = 'OBJECT' AND OBJECT_ID(R.ObjectName) IS NULL)
              OR
              (
                  R.RequirementType = 'COLUMN'
                  AND COL_LENGTH
                      (
                          PARSENAME(R.ObjectName,3) + N'.' + PARSENAME(R.ObjectName,2),
                          PARSENAME(R.ObjectName,1)
                      ) IS NULL
              )
          )

        UNION ALL

        SELECT
            'OPS_LOCAL_SERVER_MISSING',
            'ERROR',
            @MachineName,
            N'No enabled ManagedServer exists for the current machine.'
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dbo.ManagedServer
            WHERE MachineName = @MachineName
              AND IsEnabled = 1
        )
    ) AS Issues
    ORDER BY Severity,IssueCode,ObjectCode;
END;
```

## Audit

| Code | Original predicate, textual | Engine behavior | Coincidem? | Tipo | T-SQL semantics / port rule |
|---|---|---|---|---|---|
| `OPS_PROFILE_MISSING` | `WHERE NOT EXISTS (SELECT 1 FROM ops.ConsoleProfile WHERE ProfileCode='DEFAULT' AND IsEnabled=1)` | No equivalent check in `Invoke-ReviewOperationsFramework`; `ops_ConsoleProfile` is not read by this function. | **No; original code remains without an engine equivalent.** | **DIVERGENCIA** - E0h must port this predicate, using exact portable `ProfileCode` semantics if `ProfileCode` is governed as a catalog code. | Original `ProfileCode='DEFAULT'` is CI_AS/padded. Exact portable catalog-code behavior is approved and must not be mistaken for the missing predicate itself. |
| `OPS_ACTION_WITHOUT_ENGINE` | Enabled `ops.Action A LEFT JOIN enabled ops.Engine E ON E.EngineCode=A.EngineCode WHERE A.IsEnabled=1 AND A.ActionType='ENGINE' AND E.EngineCode IS NULL`. | Engine builds exact map of enabled engines; for enabled actions whose `ActionType -cne 'ENGINE'` it skips; for exact `ENGINE`, blank/missing exact engine code emits same `ERROR`. | **Same structural intent, but not full text parity.** Exact `EngineCode` is approved architecture; exact `ActionType` comparison is not established by that code rule. | **DIVERGENCIA** - E0h must preserve exact `EngineCode` but reproduce the original `ActionType='ENGINE'` comparison semantics unless a separate owner decision makes that enum exact. | Original `EngineCode` join and `ActionType='ENGINE'` use CI_AS/padding. Engine uses exact ordinal comparisons. |
| `OPS_ENGINE_HASH_MISMATCH` | Enabled engine where `E.ScriptSha256 <> LOWER(CONVERT(char(64),HASHBYTES('SHA2_256',CONVERT(varbinary(max),E.ScriptText)),2))`. | Engine ignores `ScriptText`/`ScriptSha256` for this check. It resolves `SourceFileName`, requires one manifest entry and physical engine file, hashes that file and compares manifest SHA to actual file SHA; mismatch emits the same code. | **No. Same code, different object and predicate.** | **DIVERGENCIA** - E0h must restore the original catalog `ScriptText`/`ScriptSha256` integrity predicate under this issue code. Package file/manifest integrity may remain as a separate portable check/code. | Original hashes SQL `nvarchar` bytes (UTF-16LE) and compares hash text under CI_AS. Engine currently compares package-file hash strings exactly. |
| `OPS_REQUIRED_OBJECT_MISSING` | Enabled required `ops.ActionRequirement R` where required `OBJECT` has `OBJECT_ID(R.ObjectName) IS NULL`, or required `COLUMN` has `COL_LENGTH(database.schema, column) IS NULL` using `PARSENAME`. | Engine does not read `ops_ActionRequirement`. It emits this code for unsafe `SourceFileName`, missing/non-unique manifest entry, or missing physical engine script file. | **No. Same code is repurposed for unrelated package-file requirements.** | **DIVERGENCIA** - E0h must restore the original `ops.ActionRequirement` OBJECT/COLUMN predicate under this code. Package-file requirements may remain only as separately identified portable checks. | Original `RequirementType`, names and concatenations live under SQL semantics; `OBJECT_ID`/`COL_LENGTH` are SQL Server schema probes. Engine performs path/manifest checks instead. |
| `OPS_LOCAL_SERVER_MISSING` | `WHERE NOT EXISTS (SELECT 1 FROM dbo.ManagedServer WHERE MachineName=@MachineName AND IsEnabled=1)`. | Engine emits when enabled `Context.Servers` count is not exactly one. In normal execution the runtime already throws before reviews unless exactly one enabled local server exists and its machine name matches the host. | **No literal parity; normally pre-empted by runtime boundary.** | **ARQUITECTURAL** - machine-local runtime resolution/validation is approved; E0h must not restore a central server lookup only to recreate this row. | Original only tests absence for matching machine and uses CI_AS/padded MachineName equality. Engine condition also covers multiple rows, but runtime guards that state before this function. |

## Engine checks with no original predicate under the same meaning

| Current engine meaning | Tipo | E0h disposition |
|---|---|---|
| `OPS_ENGINE_HASH_MISMATCH` = package engine file hash versus manifest | **DIVERGENCIA** | Keep the package integrity protection only under a separate portable meaning/code; restore the original catalog script-text hash predicate to the legacy code. |
| `OPS_REQUIRED_OBJECT_MISSING` = unsafe/missing package engine file or manifest requirement | **DIVERGENCIA** | Keep package path/manifest validation only as a separate portable meaning/code; restore the original SQL object/column requirement predicate to the legacy code. |

## Result

`OPS_LOCAL_SERVER_MISSING` is replaced by approved machine-local runtime validation. `OPS_ACTION_WITHOUT_ENGINE` retains the original structure but has an unapproved `ActionType` text-semantic difference. `OPS_PROFILE_MISSING` is absent, and the two remaining legacy code names are repurposed for unrelated package checks. Those rows are `DIVERGENCIA` for E0h; exact catalog-code behavior and machine-local runtime scope must remain architectural. This audit is text only and does not authorize changes to PR #67.
