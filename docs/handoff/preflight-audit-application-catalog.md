# DEPLOYMENT_PREFLIGHT audit: Application catalog

**Status:** [PROPOSED]
**Original:** `cfg.ReviewApplicationCatalog`
**Engine:** `Invoke-ReviewApplicationCatalog` plus the related `IIS_APPLICATION_MISSING` check in `Invoke-ReviewIisModel`
**Evidence:** `main@f7989a6b9043b9b16300404eb7e1dd27ca06a2aa` and PR #67 branch `engine/deployment-preflight-v1`.

The original procedure states no severity. Any engine severity below is therefore engine-owned and must not be described as an original severity.

## Audit

| Original / engine check | Original predicate, textual | Engine behavior | Coincidem? | T-SQL semantics that decide |
|---|---|---|---|---|
| `IIS_APPLICATION_NOT_IN_CATALOG` vs engine `IIS_APPLICATION_MISSING` | `FROM cfg.IisApplicationDefinition AS I LEFT JOIN cfg.Application AS A ON A.ApplicationCode = I.IisApplicationCode WHERE I.IsEnabled = 1 AND A.ApplicationCode IS NULL` | `Invoke-ReviewIisModel` builds an exact-code map of enabled `cfg_Application`; every enabled IIS definition whose `IisApplicationCode` is absent emits `IIS_APPLICATION_MISSING` `ERROR`. | **Predicate intent matches, code name does not.** The engine also requires the application row to be enabled, while the original join did not filter `A.IsEnabled`; an existing disabled application suppresses the original issue but triggers the engine. | Original join is `Latin1_General_CI_AS` with SQL space padding. The portable code map is ordinal/exact by owner decision. Both the enabled-row difference and the exact-code difference are deliberate observable differences that must be kept visible. |
| `CONFIG_FILE_WITHOUT_APPLICATION` | `FROM cfg.ConfigFile AS F WHERE F.IsEnabled = 1 AND F.ApplicationCode IS NULL` | Engine `CONFIG_FILE_APPLICATION_MISSING` skips blank/whitespace `ApplicationCode`; it emits only when a nonblank code is not in the enabled application map. | **No.** It checks the inverse failure class and does not emit the original code. | Original predicate is `IS NULL`, not trim/empty. Empty string is not NULL. Engine `IsNullOrWhiteSpace` also folds empty/spaces/tabs, so it must not be presented as equivalent. |
| `DUPLICATE_IIS_PATH` | `FROM cfg.Application AS A WHERE A.IsEnabled = 1 AND A.IisPath IS NOT NULL GROUP BY A.IisPath HAVING COUNT(*) > 1` | No equivalent check in `Invoke-ReviewApplicationCatalog` or `Invoke-ReviewIisModel`. | **No; original code has no engine equivalent.** | `GROUP BY A.IisPath` is CI_AS and uses SQL text equality semantics, including case-insensitive/accent-sensitive grouping and space-padding equality. A later port cannot use ordinal grouping silently. |
| `NON_IIS_COMPONENT_HAS_IIS_PATH` | `FROM cfg.Application AS A LEFT JOIN cfg.IisApplicationDefinition AS I ON I.IisApplicationCode = A.ApplicationCode AND I.IsEnabled = 1 WHERE A.IsEnabled = 1 AND I.IisApplicationCode IS NULL AND A.IisPath IS NOT NULL` | No equivalent. The engine check `IIS_APPLICATION_MISSING` validates the opposite direction: IIS definition -> application. | **No; original code has no engine equivalent.** | Original application-code join is CI_AS/padded; the new system's catalog-code policy is exact. `IisPath IS NOT NULL` does not reject empty text. |

## Engine-owned checks without an original equivalent in this procedure

- `APPLICATION_CODE_MISSING`: enabled `cfg_Application` with empty/whitespace `ApplicationCode` -> engine `ERROR`; no such predicate exists in `cfg.ReviewApplicationCatalog`.
- `APPLICATION_CODE_DUPLICATE`: exact duplicate enabled application code -> engine `ERROR`; no original equivalent in this procedure. The original source collation would have grouped case-only/padded variants together if it had such a check, while the engine map is exact.
- `CONFIG_FILE_APPLICATION_MISSING`: nonblank config-file application code absent from the enabled app map -> engine `ERROR`; this is not `CONFIG_FILE_WITHOUT_APPLICATION`.
- `IIS_APPLICATION_MISSING`: engine-owned name for the nearest equivalent to original `IIS_APPLICATION_NOT_IN_CATALOG`; see the first row.

## Result

The engine does **not** reproduce `cfg.ReviewApplicationCatalog` one-for-one. One predicate has a renamed near-equivalent with an additional enabled-row condition, three original codes are not emitted with their original semantics, and the engine adds three application-catalog checks of its own. This audit is text only and does not authorize engine changes.
