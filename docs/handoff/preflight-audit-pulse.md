# DEPLOYMENT_PREFLIGHT audit: Pulse model

**Status:** [PROPOSED]
**Original:** `cfg.ReviewPulseModel`
**Engine:** `Invoke-ReviewPulseModel`
**Evidence:** `main@f7989a6b9043b9b16300404eb7e1dd27ca06a2aa` and PR #67 branch `engine/deployment-preflight-v1`.

The original procedure accepts `@MachineName` but does not use it in these predicates. The portable engine always sees the machine-local catalog/context, so machine scope itself is an observable architectural difference.

## Audit

| Code | Original predicate, textual | Engine behavior | Coincidem? | T-SQL semantics / port rule |
|---|---|---|---|---|
| `PULSE_HUB_NOT_FOUND` | `NOT EXISTS` enabled `cfg.PulseProfile P` joined to enabled `cfg.ManagedInstanceRuntime I` on `I.InstanceCode=P.HubInstanceCode` and enabled `dbo.ManagedServer S` on `S.ServerCode=I.ServerCode`, with `P.HubInstanceCode=@HubInstanceCode AND P.IsEnabled=1`. | For every enabled profile in the local catalog, engine requires exactly one enabled `Context.Instances` row whose `InstanceCode` is exact-equal to the profile hub. | **Same local intent, different scope/comparison.** Original can see a hub on any managed server because `@MachineName` is unused; engine is machine-local and uses exact code comparison. | Original joins/code equality are CI_AS/padded. Portable codes are exact by owner decision. |
| `PULSE_TASK_CREDENTIAL_MISSING` | `EXISTS` profile joined to runtime instance for the requested hub where `NULLIF(I.IisIdentityUserName,N'') IS NULL OR NULLIF(I.IisIdentityPassword,N'') IS NULL`. | For each enabled profile with a resolved hub, engine checks only request secret `IIS_IDENTITY.<HubInstanceCode>`; it does **not** validate `IisIdentityUserName`. | **No.** Password source intentionally moved to credential package, but username half of the original predicate is absent. The original query also does not require `P.IsEnabled` or `I.IsEnabled` in this second check. | Legacy `NULLIF` treats empty/ordinary-spaces-only as empty; tab-only is nonempty. Portable secret presence is not CI_AS text. InstanceCode join is exact in portable. |
| `PULSE_RESOURCE_HASH_MISMATCH` | Enabled resource where `ContentSha256 <> LOWER(CONVERT(char(64),HASHBYTES('SHA2_256', CASE WHEN TextContent IS NOT NULL THEN CONVERT(varbinary(max),TextContent) ELSE BinaryContent END),2))`. | Engine uses UTF-16LE (`Encoding.Unicode`) bytes for nonnull text, otherwise binary bytes, hashes SHA-256, lowercases both sides, but skips rows whose stored hash is `IsNullOrWhiteSpace`. | **Matches normal hash cases; not all boundaries.** SQL `nvarchar` byte representation is preserved. Empty/spaces stored hash is flagged by original but skipped by engine; NULL yields SQL UNKNOWN/no original issue and is also skipped. | Stored hash comparison is CI_AS; uppercase same digest is accepted. Engine lowercasing preserves that. Broad whitespace skip is an engine deviation. |
| `PULSE_HTTP_APPLICATION_MISSING` | Enabled `cfg.PulseHttpPolicy P LEFT JOIN cfg.Application A ON A.ApplicationCode=P.ApplicationCode AND A.IsEnabled=1 WHERE P.IsEnabled=1 AND A.ApplicationCode IS NULL`. | Engine builds exact-code map of enabled applications and emits same code for enabled policies whose application code is absent. | **Predicate intent matches with intentional code-comparison change.** | Original join is CI_AS/padded; portable catalog codes exact. |
| `PULSE_PAGE_TEMPLATE_MISSING` | `NOT EXISTS` enabled `cfg.PulseResource` where `ResourceCode='PULSE_INDEX_HTML'`. | Engine searches enabled resources for exact `PULSE_INDEX_HTML`. | **Yes except intentional exact-code semantics.** | Original equality CI_AS/padded; portable code exact. |
| `PULSE_LOGO_MISSING` | `NOT EXISTS` enabled `cfg.PulseResource` where `ResourceCode='PULSE_LOGO'`. | Engine searches enabled resources for exact `PULSE_LOGO`. | **Yes except intentional exact-code semantics.** | Same as page template. |

## Engine-owned behavior without an original code

`PULSE_NOT_APPLICABLE` (`INFO`) is emitted when the local machine has no enabled Pulse profile. This is not an original `ReviewPulseModel` issue code; it implements the owner decision of 2026-10-06 that a machine with no Pulse profile is not applicable and does not fail.

## Result

Three resource/application predicates preserve the original intent modulo the approved exact-code change; the hash check differs for blank/whitespace stored hashes; hub resolution is machine-local rather than central; and `PULSE_TASK_CREDENTIAL_MISSING` omits the original username condition while moving the password to the credential package. `PULSE_NOT_APPLICABLE` is portable-only owner-approved behavior. This audit is text only and does not authorize changes to PR #67.
