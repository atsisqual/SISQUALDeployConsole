# DEPLOYMENT_PREFLIGHT audit: Operations framework

**Status:** [PROPOSED]
**Original:** `ops.ReviewOperationsFramework`
**Engine:** `Invoke-ReviewOperationsFramework`
**Evidence:** `main@f7989a6b9043b9b16300404eb7e1dd27ca06a2aa` and PR #67 branch `engine/deployment-preflight-v1`.

## Audit

| Code | Original predicate, textual | Engine behavior | Coincidem? | T-SQL semantics / port rule |
|---|---|---|---|---|
| `OPS_PROFILE_MISSING` | `WHERE NOT EXISTS (SELECT 1 FROM ops.ConsoleProfile WHERE ProfileCode='DEFAULT' AND IsEnabled=1)` | No equivalent check in `Invoke-ReviewOperationsFramework`; `ops_ConsoleProfile` is not read by this function. | **No; original code remains without an engine equivalent.** | Original `ProfileCode='DEFAULT'` is CI_AS/padded. A later portable code check must account for the exact-code owner decision rather than infer behavior from the code name. |
| `OPS_ACTION_WITHOUT_ENGINE` | Enabled `ops.Action A LEFT JOIN enabled ops.Engine E ON E.EngineCode=A.EngineCode WHERE A.IsEnabled=1 AND A.ActionType='ENGINE' AND E.EngineCode IS NULL`. | Engine builds exact map of enabled engines; for enabled actions whose `ActionType -cne 'ENGINE'` it skips; for exact `ENGINE`, blank/missing exact engine code emits same `ERROR`. | **Same structural intent, different text semantics.** | Original `EngineCode` join and `ActionType='ENGINE'` use CI_AS/padding. Engine uses exact ordinal comparisons. `EngineCode` exactness follows the new code policy; `ActionType` is enum-like text and the exact change is not proved by this original predicate alone. |
| `OPS_ENGINE_HASH_MISMATCH` | Enabled engine where `E.ScriptSha256 <> LOWER(CONVERT(char(64),HASHBYTES('SHA2_256',CONVERT(varbinary(max),E.ScriptText)),2))`. | Engine ignores `ScriptText`/`ScriptSha256` for this check. It resolves `SourceFileName`, requires one manifest entry and physical engine file, hashes that file and compares manifest SHA to actual file SHA; mismatch emits the same code. | **No. Same code, different object and predicate.** | Original hashes SQL `nvarchar` bytes (UTF-16LE) and compares hash text under CI_AS. Engine compares package-file hash strings exactly. This is a different integrity boundary, not a direct port. |
| `OPS_REQUIRED_OBJECT_MISSING` | Enabled required `ops.ActionRequirement R` where required `OBJECT` has `OBJECT_ID(R.ObjectName) IS NULL`, or required `COLUMN` has `COL_LENGTH(database.schema, column) IS NULL` using `PARSENAME`. | Engine does not read `ops_ActionRequirement`. It emits this code for unsafe `SourceFileName`, missing/non-unique manifest entry, or missing physical engine script file. | **No. Same code is repurposed for unrelated package-file requirements.** | Original text values `RequirementType`, names and concatenations live under SQL semantics; `OBJECT_ID`/`COL_LENGTH` are SQL Server schema probes. Engine performs path/manifest checks instead. |
| `OPS_LOCAL_SERVER_MISSING` | `WHERE NOT EXISTS (SELECT 1 FROM dbo.ManagedServer WHERE MachineName=@MachineName AND IsEnabled=1)`. | Engine emits when enabled `Context.Servers` count is not exactly one. In normal execution the runtime already throws before reviews unless exactly one enabled local server exists and its machine name matches the host. | **No literal parity; normally pre-empted by runtime boundary.** | Original only tests absence for matching machine and uses CI_AS/padded MachineName equality. Engine condition also covers multiple rows, but runtime guards that state before this function. |

## Engine checks with no original predicate under the same meaning

The engine has no additional issue-code names in this function, but two original names are materially repurposed:

- `OPS_ENGINE_HASH_MISMATCH` now means package engine-file hash versus manifest, not database `ScriptText` versus `ScriptSha256`.
- `OPS_REQUIRED_OBJECT_MISSING` now means package engine file/manifest requirement failure, not a missing SQL Server object or column declared in `ops.ActionRequirement`.

Those are not naming-only differences; consumers seeing the same issue code receive a different predicate and object boundary.

## Result

Only `OPS_ACTION_WITHOUT_ENGINE` retains the original structural predicate, with the portable exact-text differences noted above. `OPS_PROFILE_MISSING` is absent, `OPS_LOCAL_SERVER_MISSING` is effectively replaced/pre-empted by runtime validation, and two same-named engine checks are different predicates from the original. This audit is text only and does not authorize changes to PR #67.
