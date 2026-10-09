# DEPLOYMENT_PREFLIGHT audit: Links QR codes

**Status:** [PROPOSED]
**Original:** `cfg.ReviewLinksPageQrCodes`
**Engine:** QR portion of `Invoke-ReviewLinksPresentation`
**Evidence:** `main@f7989a6b9043b9b16300404eb7e1dd27ca06a2aa` and PR #67 branch `engine/deployment-preflight-v1`.

## Audit

| Code | Original predicate, textual | Engine behavior | Coincidem? | T-SQL semantics / port rule |
|---|---|---|---|---|
| `QR_CONTENT_HASH_MISMATCH` | Enabled `cfg.LinksPageAsset` rows where `AssetCode LIKE 'QR_CHANNEL[_]%'` and `LOWER(CONVERT(char(64),HASHBYTES('SHA2_256',A.Content),2)) <> A.ContentSha256`. | Engine selects enabled assets whose `AssetCode` starts with exact ordinal `QR_CHANNEL_`; if binary content exists **and hash is not `IsNullOrWhiteSpace`**, computes SHA-256 and compares lower-case forms exactly. | **Not fully.** Normal binary/hash mismatch and uppercase-hex cases coincide, but prefix and missing/whitespace-hash boundaries differ. | Legacy `LIKE` runs under CI_AS, so prefix case is ignored; portable asset codes are exact by owner decision. Original NULL hash makes `<>` UNKNOWN/no issue, but empty/spaces hash is non-NULL and does not equal a 64-digit digest, so it fires. Engine skips empty/spaces hash. |
| `QR_ASSET_MISSING` | Enabled instance + enabled server, `CountryCode IN ('PT','ES')`, nonnull `CustomerCode`, optional machine/instance filters, and no enabled asset whose `AssetCode='QR_CHANNEL_'+CustomerCode`. | For selected instances, engine requires exact `PT`/`ES`, substantive customer value and exact asset-code map membership; emits same `WARNING`. | **Same intent with portable exact-code and scope changes.** | Original `IN` and asset-code equality are CI_AS/padded; new catalog codes are exact. Original `CustomerCode IS NOT NULL`; engine string `IsNullOrWhiteSpace` also excludes empty-like values after conversion. Runtime catalog already machine-scopes instances. |
| `QR_ASSET_UNASSIGNED` | Enabled QR asset and `NOT EXISTS` any enabled `dbo.ManagedInstance` whose computed QR code equals that asset. No machine filter exists in this subquery. | Engine creates assigned codes only from enabled `Context.Instances` in the current machine catalog; exact prefix/code matching; emits same `INFO`. | **No for cross-machine central scope.** A QR asset assigned only to an enabled instance on another machine is assigned in the original central review but can appear unassigned in this machine-local catalog. | Original asset-code `LIKE`/equality is CI_AS/padded. Portable codes are exact. The larger difference is catalog scope, not collation. |

## Additional boundaries

- Original hash comparison accepts uppercase/lowercase hexadecimal for the same digest under CI_AS; engine lowercases both and therefore preserves that outcome.
- `LIKE 'QR_CHANNEL[_]%'` uses `[_]` for a literal underscore. The engine `StartsWith('QR_CHANNEL_', Ordinal)` preserves the literal prefix shape but intentionally applies exact code case.
- Original severities are explicit and match the engine names: mismatch `ERROR`, missing asset `WARNING`, unassigned asset `INFO`.

## Result

The three issue-code names and severities are preserved, but predicate parity is not exact. The hash check skips blank/whitespace hashes that the original would flag when non-NULL; missing-asset uses portable exact-code/machine scope; and unassigned-asset loses the original central all-instance scope. This audit is text only and does not authorize changes to PR #67.
