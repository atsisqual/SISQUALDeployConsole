# DEPLOYMENT_PREFLIGHT audit: Repair model

**Status:** [PROPOSED]
**Original:** `cfg.ReviewRepairModel`
**Engine:** `Invoke-ReviewRepairModel`
**Evidence:** `main@f7989a6b9043b9b16300404eb7e1dd27ca06a2aa` and PR #67 branch `engine/deployment-preflight-v1`.

The original procedure reports free-text findings and no issue-code column. The engine codes below are therefore engine-owned names.

## Original findings versus engine

| Original finding / engine check | Original predicate, textual | Engine behavior | Coincidem? | T-SQL semantics that decide |
|---|---|---|---|---|
| `JSON repair rule has no RepairValueType.` | `FROM cfg.ConfigRule AS R WHERE R.IsEnabled = 1 AND R.SelectorType = 'JSON_VALUE' AND R.RepairValueType IS NULL AND (@RepairGroup IS NULL OR R.RepairGroup = @RepairGroup)` | No equivalent. Engine instead checks whether each enabled rule has a nonblank `FileID` that exists in enabled `cfg_ConfigFile`; otherwise `CONFIG_RULE_FILE_MISSING`. | **No.** | `SelectorType='JSON_VALUE'` and optional `RepairGroup` equality use CI_AS with SQL padding. Engine does neither comparison. |
| `REPLACE policy has no ExpectedContentTemplate.` | `FROM cfg.ConfigFileRepairPolicy AS P WHERE P.IsEnabled = 1 AND P.RepairMode = 'REPLACE' AND NULLIF(P.ExpectedContentTemplate,N'') IS NULL AND (@RepairGroup IS NULL OR P.RepairGroup = @RepairGroup)` | Engine checks missing referenced file (`CONFIG_REPAIR_FILE_MISSING`) and whether `RepairMode` is exactly one of PowerShell literals `PATCH`/`REPLACE` (`CONFIG_REPAIR_MODE_INVALID`); it does not test `ExpectedContentTemplate`. | **No.** | Original `RepairMode='REPLACE'` is CI_AS/padded. `NULLIF` treats empty and ordinary-spaces-only template as missing, not tab-only. Engine exact `-notin` changes case behavior and lacks this template predicate. |
| `XML rule allows creation but has neither an existing-node strategy nor a missing-node template.` | `FROM cfg.ConfigRule AS R WHERE R.IsEnabled = 1 AND R.SelectorType = 'XML_TEXT' AND R.CreateIfMissing = 1 AND (NULLIF(R.MissingParentSelector,N'') IS NULL OR NULLIF(R.MissingNodeTemplate,N'') IS NULL) AND (@RepairGroup IS NULL OR R.RepairGroup = @RepairGroup)` | No equivalent. | **No.** | `SelectorType` and `RepairGroup` are CI_AS/padded; the two `NULLIF` checks treat ordinary-spaces-only as empty and tabs as nonempty. |

## Engine-owned checks without original equivalents

- `CONFIG_RULE_FILE_MISSING`: enabled rule has blank/whitespace `FileID` or references no enabled config file. The original review does not validate `FileID` membership.
- `CONFIG_REPAIR_FILE_MISSING`: enabled repair policy references no enabled config file. No original equivalent.
- `CONFIG_REPAIR_MODE_INVALID`: `RepairMode` is not exactly `PATCH` or `REPLACE`. The original only selects `REPLACE` rows for a missing-template check and does not declare other modes invalid.

The engine also ignores the original optional `@RepairGroup` filter because the portable review function receives no repair-group parameter.

## Result

The three original repair-model findings and the three engine checks are different sets. None of the original predicates is implemented by this engine review, and all three current issue-code names are engine-owned. This audit is text only and does not authorize changes to PR #67.
