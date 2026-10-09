# DEPLOYMENT_PREFLIGHT audit: Application catalog

**Status:** [PROPOSED]
**Original:** `cfg.ReviewApplicationCatalog`
**Engine:** `Invoke-ReviewApplicationCatalog` plus the related `IIS_APPLICATION_MISSING` check in `Invoke-ReviewIisModel`
**Evidence:** `main@f7989a6b9043b9b16300404eb7e1dd27ca06a2aa` and PR #67 branch `engine/deployment-preflight-v1`.

The original procedure states no severity. Any engine severity below is therefore engine-owned and must not be described as an original severity.

`Tipo` classifies every observable difference: `ARQUITECTURAL` is an approved portable-system difference that E0h must preserve; `DIVERGENCIA` is parity work for E0h. If a row contains both, it is classified `DIVERGENCIA` and the approved sub-difference is called out explicitly.

## Original predicate text

The following block is copied verbatim from `docs/handoff/preflight-legacy-procedures-implemented.sql.txt` on `main`.

```sql
CREATE OR ALTER PROCEDURE [cfg].[ReviewApplicationCatalog]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        IssueCode,
        ApplicationCode,
        Details
    FROM
    (
        SELECT
            IssueCode = CONVERT(varchar(80), 'IIS_APPLICATION_NOT_IN_CATALOG'),
            ApplicationCode = I.IisApplicationCode,
            Details = CONVERT(nvarchar(1000), N'IIS application definition has no cfg.Application row.')
        FROM cfg.IisApplicationDefinition AS I
        LEFT JOIN cfg.Application AS A
            ON A.ApplicationCode = I.IisApplicationCode
        WHERE I.IsEnabled = 1
          AND A.ApplicationCode IS NULL

        UNION ALL

        SELECT
            IssueCode = CONVERT(varchar(80), 'CONFIG_FILE_WITHOUT_APPLICATION'),
            ApplicationCode = CONVERT(varchar(80), NULL),
            Details = CONVERT(nvarchar(1000), N'FileID=' + CONVERT(nvarchar(20), F.FileID) + N'; RelativePath=' + F.RelativePath)
        FROM cfg.ConfigFile AS F
        WHERE F.IsEnabled = 1
          AND F.ApplicationCode IS NULL

        UNION ALL

        SELECT
            IssueCode = CONVERT(varchar(80), 'DUPLICATE_IIS_PATH'),
            ApplicationCode = MIN(A.ApplicationCode),
            Details = CONVERT(nvarchar(1000), N'IIS path is used by more than one enabled catalogue entry: ' + A.IisPath)
        FROM cfg.Application AS A
        WHERE A.IsEnabled = 1
          AND A.IisPath IS NOT NULL
        GROUP BY A.IisPath
        HAVING COUNT(*) > 1

        UNION ALL

        SELECT
            IssueCode = CONVERT(varchar(80), 'NON_IIS_COMPONENT_HAS_IIS_PATH'),
            ApplicationCode = A.ApplicationCode,
            Details = CONVERT(nvarchar(1000), N'Component is not in cfg.IisApplicationDefinition but has IisPath=' + A.IisPath)
        FROM cfg.Application AS A
        LEFT JOIN cfg.IisApplicationDefinition AS I
            ON I.IisApplicationCode = A.ApplicationCode
           AND I.IsEnabled = 1
        WHERE A.IsEnabled = 1
          AND I.IisApplicationCode IS NULL
          AND A.IisPath IS NOT NULL
    ) AS Issues
    ORDER BY IssueCode, ApplicationCode;
END;
```

## Audit

| Original / engine check | Original predicate, textual | Engine behavior | Coincidem? | Tipo | T-SQL semantics that decide |
|---|---|---|---|---|---|
| `IIS_APPLICATION_NOT_IN_CATALOG` vs engine `IIS_APPLICATION_MISSING` | `FROM cfg.IisApplicationDefinition AS I LEFT JOIN cfg.Application AS A ON A.ApplicationCode = I.IisApplicationCode WHERE I.IsEnabled = 1 AND A.ApplicationCode IS NULL` | `Invoke-ReviewIisModel` builds an exact-code map of enabled `cfg_Application`; every enabled IIS definition whose `IisApplicationCode` is absent emits `IIS_APPLICATION_MISSING` `ERROR`. | **Predicate intent matches, code name does not.** The engine also requires the application row to be enabled, while the original join did not filter `A.IsEnabled`; an existing disabled application suppresses the original issue but triggers the engine. Exact catalog-code comparison is approved and must remain. | **DIVERGENCIA** - E0h must restore the original disabled-row behavior and original issue-code identity while preserving exact portable catalog-code comparison. | Original join is `Latin1_General_CI_AS` with SQL space padding. Portable catalog codes are exact by owner decision; that sub-difference is architectural, not E0h work. |
| `CONFIG_FILE_WITHOUT_APPLICATION` | `FROM cfg.ConfigFile AS F WHERE F.IsEnabled = 1 AND F.ApplicationCode IS NULL` | Engine `CONFIG_FILE_APPLICATION_MISSING` skips blank/whitespace `ApplicationCode`; it emits only when a nonblank code is not in the enabled application map. | **No.** It checks the inverse failure class and does not emit the original code. | **DIVERGENCIA** - E0h must add the original `IS NULL` predicate/code; it must not replace it with broad whitespace handling. | Original predicate is `IS NULL`, not trim/empty. Empty string is not NULL. Engine `IsNullOrWhiteSpace` also folds empty/spaces/tabs, so it must not be presented as equivalent. |
| `DUPLICATE_IIS_PATH` | `FROM cfg.Application AS A WHERE A.IsEnabled = 1 AND A.IisPath IS NOT NULL GROUP BY A.IisPath HAVING COUNT(*) > 1` | No equivalent check in `Invoke-ReviewApplicationCatalog` or `Invoke-ReviewIisModel`. | **No; original code has no engine equivalent.** | **DIVERGENCIA** - E0h must port this predicate. | `GROUP BY A.IisPath` is CI_AS and uses SQL text equality semantics, including case-insensitive/accent-sensitive grouping and space-padding equality. A later port cannot use ordinal grouping silently. |
| `NON_IIS_COMPONENT_HAS_IIS_PATH` | `FROM cfg.Application AS A LEFT JOIN cfg.IisApplicationDefinition AS I ON I.IisApplicationCode = A.ApplicationCode AND I.IsEnabled = 1 WHERE A.IsEnabled = 1 AND I.IisApplicationCode IS NULL AND A.IisPath IS NOT NULL` | No equivalent. The engine check `IIS_APPLICATION_MISSING` validates the opposite direction: IIS definition -> application. | **No; original code has no engine equivalent.** Exact portable application-code comparison is approved. | **DIVERGENCIA** - E0h must port this predicate while preserving exact portable catalog-code comparison. | Original application-code join is CI_AS/padded; the new system's catalog-code policy is exact. `IisPath IS NOT NULL` does not reject empty text. |

## Engine-owned checks without an original equivalent in this procedure

| Engine check | Tipo | E0h disposition |
|---|---|---|
| `APPLICATION_CODE_MISSING` | **DIVERGENCIA** | No original predicate exists. E0h must reconcile/remove or separately justify it; it must not count as a ported original check. |
| `APPLICATION_CODE_DUPLICATE` | **DIVERGENCIA** | No original predicate exists. E0h must reconcile/remove or separately justify it; exact catalog-code comparison itself remains architectural. |
| `CONFIG_FILE_APPLICATION_MISSING` | **DIVERGENCIA** | This is not `CONFIG_FILE_WITHOUT_APPLICATION`; E0h must restore the original NULL check separately. |
| `IIS_APPLICATION_MISSING` | **DIVERGENCIA** | Engine-owned name for the near-equivalent first row; E0h must restore the original code/predicate while retaining exact code semantics. |

## Result

The engine does **not** reproduce `cfg.ReviewApplicationCatalog` one-for-one. One predicate has a renamed near-equivalent with an additional enabled-row condition, three original codes are not emitted with their original semantics, and the engine adds application-catalog checks of its own. Exact catalog-code comparison remains approved architecture; the other mismatches marked `DIVERGENCIA` are the E0h correction set. This audit is text only and does not authorize engine changes.
