# DEPLOYMENT_PREFLIGHT audit: Managed assets

**Status:** [PROPOSED]
**Original:** `cfg.ReviewManagedAssets`
**Engine:** `Invoke-ReviewManagedAssets`
**Evidence:** `main@f7989a6b9043b9b16300404eb7e1dd27ca06a2aa` and PR #67 branch `engine/deployment-preflight-v1`.

The original procedure states no severity. The engine's `ERROR` values are engine-owned, not original severities.

## Audit

| Check | Original predicate, textual | Engine behavior | Coincidem? | T-SQL semantics that decide |
|---|---|---|---|---|
| `ENABLED_INSTANCE_LOGO_MISSING` | `FROM dbo.ManagedServer AS S INNER JOIN dbo.ManagedInstance AS I ON I.ServerCode=S.ServerCode WHERE S.IsEnabled=1 AND I.IsEnabled=1 AND S.MachineName=@MachineName AND I.CustomerLogo IS NULL` | For each selected instance, engine emits when `CustomerLogo` is null **or** a zero-length byte array. | **No.** The original fires only for SQL NULL and covers every enabled instance on the selected machine; the engine selected-instance check also treats zero bytes as missing. | `ServerCode`/`MachineName` source joins/equality are CI_AS/padded. Portable codes are exact and machine names no-case. Binary NULL is distinct from zero-length BLOB. |
| `ENABLED_INSTANCE_LOGO_HASH_MISSING` | Same local enabled-instance scope, plus `I.CustomerLogo IS NOT NULL AND NULLIF(I.CustomerLogoSha256,'') IS NULL` | When engine sees non-missing logo, it emits if `CustomerLogoSha256` is `IsNullOrWhiteSpace`. | **No.** Legacy `NULLIF` treats empty and ordinary-spaces-only as empty through SQL padding, but not tabs/other whitespace; engine folds all whitespace. Engine also uses selected-instance scope. | SQL equality padding is decisive; there is no trim in the original. Tab-only hash is a legacy non-trigger but an engine trigger. |
| `ASSET_DESTINATION_MISSING` | `WHERE NOT EXISTS (SELECT 1 FROM cfg.ManagedAssetDestination WHERE AssetType='CUSTOMER_LOGO' AND IsEnabled=1)` | Engine emits only when there are zero enabled destination rows of **any** asset type. | **No.** An unrelated enabled destination suppresses the engine issue even when `CUSTOMER_LOGO` has none. | Original `AssetType='CUSTOMER_LOGO'` is CI_AS/padded. The engine does not perform this text comparison at all. |

## Engine behavior with no original equivalent

There are no additional issue-code names in `Invoke-ReviewManagedAssets`; the divergence is in the predicates and scope of the same three names. In particular, the engine-added zero-length-logo rule and all-whitespace hash rule have no textual equivalent in `cfg.ReviewManagedAssets`.

## Result

None of the three engine predicates is textually equivalent to its original predicate. The differences are observable: selected-instance scope, zero-length BLOB handling, broad whitespace handling, and destination filtering by asset type. This audit is text only and does not authorize engine changes.
