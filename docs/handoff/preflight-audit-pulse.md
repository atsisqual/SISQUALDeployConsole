# DEPLOYMENT_PREFLIGHT audit: Pulse model

**Status:** [PROPOSED]
**Original:** `cfg.ReviewPulseModel`
**Engine:** `Invoke-ReviewPulseModel`
**Evidence:** original procedure at `main@f7989a6b9043b9b16300404eb7e1dd27ca06a2aa`; audited engine implementation at PR #67 final head `d4cf6fe974030a39d3ffe852d2809ce9009fe73b`, integrated by merge `41d09f38e5aedc4f9b62656870d0b999ca661205`.

The original procedure accepts `@MachineName` but does not use it in these predicates. The portable engine always sees the machine-local catalog/context, so machine scope itself is an observable approved architectural difference.

`Tipo` classifies every observable difference: `ARQUITECTURAL` is an approved portable-system difference that E0h must preserve; `DIVERGENCIA` is parity work for E0h. If a row contains both, it is classified `DIVERGENCIA` and the approved sub-difference is called out explicitly. A broader behavior than the recorded owner decision is `[PENDING]`, not architectural.

## Original predicate text

The following block is copied verbatim from `docs/handoff/preflight-legacy-procedures-implemented.sql.txt` on `main`.

```sql
CREATE OR ALTER PROCEDURE [cfg].[ReviewPulseModel]
    @MachineName sysname,
    @HubInstanceCode varchar(20)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Issues TABLE(IssueCode varchar(100),Severity varchar(10),ObjectCode nvarchar(255),Details nvarchar(2000));

    IF NOT EXISTS(
        SELECT 1
        FROM cfg.PulseProfile P
        INNER JOIN cfg.ManagedInstanceRuntime I ON I.InstanceCode=P.HubInstanceCode AND I.IsEnabled=1
        INNER JOIN dbo.ManagedServer S ON S.ServerCode=I.ServerCode AND S.IsEnabled=1
        WHERE P.HubInstanceCode=@HubInstanceCode AND P.IsEnabled=1
    )
        INSERT @Issues VALUES('PULSE_HUB_NOT_FOUND','ERROR',@HubInstanceCode,N'Enabled pulse hub is not registered on any managed server.');

    IF EXISTS(
        SELECT 1 FROM cfg.PulseProfile P
        INNER JOIN cfg.ManagedInstanceRuntime I ON I.InstanceCode=P.HubInstanceCode
        WHERE P.HubInstanceCode=@HubInstanceCode
          AND (NULLIF(I.IisIdentityUserName,N'') IS NULL OR NULLIF(I.IisIdentityPassword,N'') IS NULL)
    )
        INSERT @Issues VALUES('PULSE_TASK_CREDENTIAL_MISSING','ERROR',@HubInstanceCode,N'DEMOPT IIS identity username/password are required to register the collector task.');

    INSERT @Issues
    SELECT 'PULSE_RESOURCE_HASH_MISMATCH','ERROR',ResourceCode,N'Pulse resource hash does not match content.'
    FROM cfg.PulseResource
    WHERE IsEnabled=1 AND ContentSha256<>LOWER(CONVERT(char(64),HASHBYTES('SHA2_256',CASE WHEN TextContent IS NOT NULL THEN CONVERT(varbinary(max),TextContent) ELSE BinaryContent END),2));

    INSERT @Issues
    SELECT 'PULSE_HTTP_APPLICATION_MISSING','ERROR',P.ApplicationCode,N'HTTP policy references a missing or disabled application.'
    FROM cfg.PulseHttpPolicy P
    LEFT JOIN cfg.Application A ON A.ApplicationCode=P.ApplicationCode AND A.IsEnabled=1
    WHERE P.IsEnabled=1 AND A.ApplicationCode IS NULL;

    IF NOT EXISTS(SELECT 1 FROM cfg.PulseResource WHERE ResourceCode='PULSE_INDEX_HTML' AND IsEnabled=1)
        INSERT @Issues VALUES('PULSE_PAGE_TEMPLATE_MISSING','ERROR','PULSE_INDEX_HTML',N'Pulse page template is missing.');

    IF NOT EXISTS(SELECT 1 FROM cfg.PulseResource WHERE ResourceCode='PULSE_LOGO' AND IsEnabled=1)
        INSERT @Issues VALUES('PULSE_LOGO_MISSING','ERROR','PULSE_LOGO',N'Pulse logo asset is missing.');

    SELECT * FROM @Issues ORDER BY CASE Severity WHEN 'ERROR' THEN 1 ELSE 2 END,IssueCode,ObjectCode;
END;
```

## Audit

| Code | Original predicate, textual | Engine behavior | Coincidem? | Tipo | T-SQL semantics / port rule |
|---|---|---|---|---|---|
| `PULSE_HUB_NOT_FOUND` | `NOT EXISTS` enabled `cfg.PulseProfile P` joined to enabled `cfg.ManagedInstanceRuntime I` on `I.InstanceCode=P.HubInstanceCode` and enabled `dbo.ManagedServer S` on `S.ServerCode=I.ServerCode`, with `P.HubInstanceCode=@HubInstanceCode AND P.IsEnabled=1`. | For every enabled profile in the local catalog, engine requires exactly one enabled `Context.Instances` row whose `InstanceCode` is exact-equal to the profile hub. If there are no enabled profiles, it returns `PULSE_NOT_APPLICABLE` before this check. | **Same local intent for enabled profiles, different scope/comparison, plus one unresolved disabled-only boundary.** Original can see a hub on any managed server because `@MachineName` is unused; engine is machine-local and uses exact code comparison. If profile rows exist but all are disabled, the engine returns INFO while the original, when invoked for that hub, emits `PULSE_HUB_NOT_FOUND`. | **DIVERGENCIA only for the disabled-only boundary; machine-local/exact-code deltas are ARQUITECTURAL.** The disabled-only ERROR-to-INFO change is `[PENDING]` because no owner decision approves it. | Original joins/code equality are CI_AS/padded. Portable codes are exact by owner decision. Machine-local catalog scope is approved. |
| `PULSE_TASK_CREDENTIAL_MISSING` | `EXISTS` profile joined to runtime instance for the requested hub where `NULLIF(I.IisIdentityUserName,N'') IS NULL OR NULLIF(I.IisIdentityPassword,N'') IS NULL`. | For each enabled profile with a resolved hub, engine checks only request secret `IIS_IDENTITY.<HubInstanceCode>`; it does **not** validate `IisIdentityUserName`. | **No.** Password source intentionally moved to credential package, but username half of the original predicate is absent. The original query also does not require `P.IsEnabled` or `I.IsEnabled` in this second check. | **DIVERGENCIA** - E0h must add the original username half and reconcile the original enabled-row scope, while preserving package-secret password sourcing and exact code semantics. | Legacy `NULLIF` treats empty/ordinary-spaces-only as empty; tab-only is nonempty. Portable secret presence is not CI_AS text. InstanceCode join is exact in portable. |
| `PULSE_RESOURCE_HASH_MISMATCH` | Enabled resource where `ContentSha256 <> LOWER(CONVERT(char(64),HASHBYTES('SHA2_256', CASE WHEN TextContent IS NOT NULL THEN CONVERT(varbinary(max),TextContent) ELSE BinaryContent END),2))`. | Engine uses UTF-16LE (`Encoding.Unicode`) bytes for nonnull text, otherwise binary bytes, hashes SHA-256, lowercases both sides, but skips rows whose stored hash is `IsNullOrWhiteSpace`. | **Matches normal hash cases; not all boundaries.** SQL `nvarchar` byte representation is preserved. Empty/spaces stored hash is flagged by original but skipped by engine; NULL yields SQL UNKNOWN/no original issue and is also skipped. | **DIVERGENCIA** - E0h must stop skipping non-NULL empty/ordinary-spaces hash values while keeping the correct UTF-16LE text hashing and case-normalized digest comparison. | Stored hash comparison is CI_AS; uppercase same digest is accepted. Engine lowercasing preserves that. Broad whitespace skip is the deviation. |
| `PULSE_HTTP_APPLICATION_MISSING` | Enabled `cfg.PulseHttpPolicy P LEFT JOIN cfg.Application A ON A.ApplicationCode=P.ApplicationCode AND A.IsEnabled=1 WHERE P.IsEnabled=1 AND A.ApplicationCode IS NULL`. | Engine builds exact-code map of enabled applications and emits same code for enabled policies whose application code is absent. | **Predicate intent matches with intentional code-comparison change.** | **ARQUITECTURAL** - exact portable application codes are approved; no E0h predicate change is required. | Original join is CI_AS/padded; portable catalog codes exact. |
| `PULSE_PAGE_TEMPLATE_MISSING` | `NOT EXISTS` enabled `cfg.PulseResource` where `ResourceCode='PULSE_INDEX_HTML'`. | Engine searches enabled resources for exact `PULSE_INDEX_HTML`. | **Yes except intentional exact-code semantics.** | **ARQUITECTURAL** - exact portable resource code is approved. | Original equality CI_AS/padded; portable code exact. |
| `PULSE_LOGO_MISSING` | `NOT EXISTS` enabled `cfg.PulseResource` where `ResourceCode='PULSE_LOGO'`. | Engine searches enabled resources for exact `PULSE_LOGO`. | **Yes except intentional exact-code semantics.** | **ARQUITECTURAL** - exact portable resource code is approved. | Original equality CI_AS/padded; portable code exact. |

## Engine-owned behavior without an original code

| Engine behavior | Tipo | E0h disposition |
|---|---|---|
| `PULSE_NOT_APPLICABLE` (`INFO`) when there are **no Pulse profile rows for the machine** | **ARQUITECTURAL** | Preserve. This is the recorded owner decision of 2026-10-06: a machine without a Pulse profile is not applicable and does not fail. |
| `PULSE_NOT_APPLICABLE` (`INFO`) when profile rows exist but all are disabled | **DIVERGENCIA / [PENDING]** | The current `Get-EnabledRows` early return also covers this case, but the owner decision does not. The original review invoked for such a hub produces `PULSE_HUB_NOT_FOUND`. E0h must not preserve the ERROR-to-INFO change unless the owner approves it. |

## Result

Machine-local scope, exact catalog codes, package-secret password sourcing and the **no-profile-row** `PULSE_NOT_APPLICABLE` case are approved architecture. E0h work includes the username/enabled-row semantics of `PULSE_TASK_CREDENTIAL_MISSING`, the non-NULL blank-hash behavior of `PULSE_RESOURCE_HASH_MISMATCH`, and the disabled-only-profile boundary unless the owner separately approves it. The current INFO outcome for disabled-only profiles is `[PENDING]`, not architectural. This audit is text only and does not authorize changes to PR #67.
