# DEPLOYMENT_PREFLIGHT audit: Repair model

**Status:** [PROPOSED]
**Original:** `cfg.ReviewRepairModel`
**Engine:** `Invoke-ReviewRepairModel`
**Evidence:** `main@f7989a6b9043b9b16300404eb7e1dd27ca06a2aa` and PR #67 branch `engine/deployment-preflight-v1`.

The original procedure reports free-text findings and no issue-code column. The engine codes below are therefore engine-owned names.

`Tipo` classifies every observable difference: `ARQUITECTURAL` is an approved portable-system difference that E0h must preserve; `DIVERGENCIA` is parity work for E0h. If a row contains both, it is classified `DIVERGENCIA` and the approved sub-difference is called out explicitly.

## Original predicate text

The following block is copied verbatim from `docs/handoff/preflight-legacy-procedures-implemented.sql.txt` on `main`.

```sql
CREATE OR ALTER PROCEDURE [cfg].[ReviewRepairModel]
(
    @RepairGroup varchar(30) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        Severity = CONVERT(varchar(10), 'ERROR'),
        ObjectType = CONVERT(varchar(30), 'CONFIG_RULE'),
        ObjectCode = R.RuleCode,
        Issue = CONVERT(nvarchar(1000), N'JSON repair rule has no RepairValueType.')
    FROM cfg.ConfigRule AS R
    WHERE R.IsEnabled = 1
      AND R.SelectorType = 'JSON_VALUE'
      AND R.RepairValueType IS NULL
      AND (@RepairGroup IS NULL OR R.RepairGroup = @RepairGroup)

    UNION ALL

    SELECT
        'ERROR',
        'FILE_POLICY',
        CONVERT(varchar(150), P.FileID),
        N'REPLACE policy has no ExpectedContentTemplate.'
    FROM cfg.ConfigFileRepairPolicy AS P
    WHERE P.IsEnabled = 1
      AND P.RepairMode = 'REPLACE'
      AND NULLIF(P.ExpectedContentTemplate, N'') IS NULL
      AND (@RepairGroup IS NULL OR P.RepairGroup = @RepairGroup)

    UNION ALL

    SELECT
        'ERROR',
        'CONFIG_RULE',
        R.RuleCode,
        N'XML rule allows creation but has neither an existing-node strategy nor a missing-node template.'
    FROM cfg.ConfigRule AS R
    WHERE R.IsEnabled = 1
      AND R.SelectorType = 'XML_TEXT'
      AND R.CreateIfMissing = 1
      AND
      (
          NULLIF(R.MissingParentSelector, N'') IS NULL
          OR NULLIF(R.MissingNodeTemplate, N'') IS NULL
      )
      AND (@RepairGroup IS NULL OR R.RepairGroup = @RepairGroup);
END;
```

## Original findings versus engine

| Original finding / engine check | Original predicate, textual | Engine behavior | Coincidem? | Tipo | T-SQL semantics that decide |
|---|---|---|---|---|---|
| `JSON repair rule has no RepairValueType.` | `FROM cfg.ConfigRule AS R WHERE R.IsEnabled = 1 AND R.SelectorType = 'JSON_VALUE' AND R.RepairValueType IS NULL AND (@RepairGroup IS NULL OR R.RepairGroup = @RepairGroup)` | No equivalent. Engine instead checks whether each enabled rule has a nonblank `FileID` that exists in enabled `cfg_ConfigFile`; otherwise `CONFIG_RULE_FILE_MISSING`. | **No.** | **DIVERGENCIA** - E0h must port the original JSON/`RepairValueType` predicate. Exact portable catalog-code comparison, where used by the implementation, remains architectural. | `SelectorType='JSON_VALUE'` and optional `RepairGroup` equality use CI_AS with SQL padding. Engine does neither comparison. |
| `REPLACE policy has no ExpectedContentTemplate.` | `FROM cfg.ConfigFileRepairPolicy AS P WHERE P.IsEnabled = 1 AND P.RepairMode = 'REPLACE' AND NULLIF(P.ExpectedContentTemplate,N'') IS NULL AND (@RepairGroup IS NULL OR P.RepairGroup = @RepairGroup)` | Engine checks missing referenced file (`CONFIG_REPAIR_FILE_MISSING`) and whether `RepairMode` is exactly one of PowerShell literals `PATCH`/`REPLACE` (`CONFIG_REPAIR_MODE_INVALID`); it does not test `ExpectedContentTemplate`. | **No.** | **DIVERGENCIA** - E0h must port the original REPLACE/template predicate and its repair-group filter. | Original `RepairMode='REPLACE'` is CI_AS/padded. `NULLIF` treats empty and ordinary-spaces-only template as missing, not tab-only. Engine exact `-notin` changes case behavior and lacks this template predicate. |
| `XML rule allows creation but has neither an existing-node strategy nor a missing-node template.` | `FROM cfg.ConfigRule AS R WHERE R.IsEnabled = 1 AND R.SelectorType = 'XML_TEXT' AND R.CreateIfMissing = 1 AND (NULLIF(R.MissingParentSelector,N'') IS NULL OR NULLIF(R.MissingNodeTemplate,N'') IS NULL) AND (@RepairGroup IS NULL OR R.RepairGroup = @RepairGroup)` | No equivalent. | **No.** | **DIVERGENCIA** - E0h must port this original predicate and its repair-group filter. | `SelectorType` and `RepairGroup` are CI_AS/padded; the two `NULLIF` checks treat ordinary-spaces-only as empty and tabs as nonempty. |

## Engine-owned checks without original equivalents

| Engine check | Tipo | E0h disposition |
|---|---|---|
| `CONFIG_RULE_FILE_MISSING` | **DIVERGENCIA** | No original predicate validates `FileID` membership. E0h must reconcile/remove or separately justify it; it must not count as a ported original review finding. |
| `CONFIG_REPAIR_FILE_MISSING` | **DIVERGENCIA** | No original equivalent. E0h must reconcile it separately from the original REPLACE/template finding. |
| `CONFIG_REPAIR_MODE_INVALID` | **DIVERGENCIA** | The original does not declare non-`PATCH`/`REPLACE` modes invalid; E0h must reconcile this extra predicate. |
| Missing `@RepairGroup` filtering in the portable review | **DIVERGENCIA** | E0h must provide equivalent filtering semantics or an explicitly approved replacement; this is not one of the approved package/machine-local/exact-code architectural differences. |

## Result

The three original repair-model findings and the three engine checks are different sets. None of the original predicates is implemented by this engine review, and the portable function also omits the original optional repair-group filter. All such mismatches are marked `DIVERGENCIA` for E0h; approved exact-code behavior must be preserved when those predicates are ported. This audit is text only and does not authorize changes to PR #67.
