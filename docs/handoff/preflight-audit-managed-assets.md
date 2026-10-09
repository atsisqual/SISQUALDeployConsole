# DEPLOYMENT_PREFLIGHT audit: Managed assets

**Status:** [PROPOSED]
**Original:** `cfg.ReviewManagedAssets`
**Engine:** `Invoke-ReviewManagedAssets`
**Evidence:** `main@f7989a6b9043b9b16300404eb7e1dd27ca06a2aa` and PR #67 branch `engine/deployment-preflight-v1`.

The original procedure states no severity. The engine's `ERROR` values are engine-owned, not original severities.

`Tipo` classifies every observable difference: `ARQUITECTURAL` is an approved portable-system difference that E0h must preserve; `DIVERGENCIA` is parity work for E0h. If a row contains both, it is classified `DIVERGENCIA` and the approved sub-difference is called out explicitly.

## Original predicate text

The following block is copied verbatim from `docs/handoff/preflight-legacy-procedures-implemented.sql.txt` on `main`.

```sql
CREATE OR ALTER PROCEDURE [cfg].[ReviewManagedAssets]
    @MachineName sysname = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @MachineName=COALESCE(NULLIF(@MachineName,N''),CONVERT(sysname,SERVERPROPERTY('MachineName')));

    SELECT IssueCode,InstanceCode,Details
    FROM
    (
        SELECT
            IssueCode=CONVERT(varchar(80),'ENABLED_INSTANCE_LOGO_MISSING'),
            I.InstanceCode,
            Details=CONVERT(nvarchar(1000),N'Enabled managed instance has no CustomerLogo binary content.')
        FROM dbo.ManagedServer AS S
        INNER JOIN dbo.ManagedInstance AS I ON I.ServerCode=S.ServerCode
        WHERE S.IsEnabled=1 AND I.IsEnabled=1
          AND S.MachineName=@MachineName
          AND I.CustomerLogo IS NULL

        UNION ALL

        SELECT
            'ENABLED_INSTANCE_LOGO_HASH_MISSING',
            I.InstanceCode,
            N'Enabled managed instance has logo content but no SHA-256.'
        FROM dbo.ManagedServer AS S
        INNER JOIN dbo.ManagedInstance AS I ON I.ServerCode=S.ServerCode
        WHERE S.IsEnabled=1 AND I.IsEnabled=1
          AND S.MachineName=@MachineName
          AND I.CustomerLogo IS NOT NULL
          AND NULLIF(I.CustomerLogoSha256,'') IS NULL

        UNION ALL

        SELECT
            'ASSET_DESTINATION_MISSING',
            CONVERT(varchar(20),NULL),
            N'No enabled CUSTOMER_LOGO destinations are configured.'
        WHERE NOT EXISTS
        (
            SELECT 1 FROM cfg.ManagedAssetDestination
            WHERE AssetType='CUSTOMER_LOGO' AND IsEnabled=1
        )
    ) AS X
    ORDER BY IssueCode,InstanceCode;
END;
```

## Audit

| Check | Original predicate, textual | Engine behavior | Coincidem? | Tipo | T-SQL semantics that decide |
|---|---|---|---|---|---|
| `ENABLED_INSTANCE_LOGO_MISSING` | `FROM dbo.ManagedServer AS S INNER JOIN dbo.ManagedInstance AS I ON I.ServerCode=S.ServerCode WHERE S.IsEnabled=1 AND I.IsEnabled=1 AND S.MachineName=@MachineName AND I.CustomerLogo IS NULL` | For each selected instance, engine emits when `CustomerLogo` is null **or** a zero-length byte array. | **No.** The original fires only for SQL NULL and covers every enabled instance on the selected machine; the engine selected-instance check also treats zero bytes as missing. Machine-local catalog scope and exact catalog-code handling are approved architecture. | **DIVERGENCIA** - E0h must restore SQL-NULL-only logo semantics and the original review cardinality while preserving the approved machine-local architecture. | `ServerCode`/`MachineName` source joins/equality are CI_AS/padded. Portable codes are exact and machine names no-case. Binary NULL is distinct from zero-length BLOB. |
| `ENABLED_INSTANCE_LOGO_HASH_MISSING` | Same local enabled-instance scope, plus `I.CustomerLogo IS NOT NULL AND NULLIF(I.CustomerLogoSha256,'') IS NULL` | When engine sees non-missing logo, it emits if `CustomerLogoSha256` is `IsNullOrWhiteSpace`. | **No.** Legacy `NULLIF` treats empty and ordinary-spaces-only as empty through SQL padding, but not tabs/other whitespace; engine folds all whitespace. Engine also uses selected-instance scope. | **DIVERGENCIA** - E0h must reproduce the original NULL/ordinary-space boundary and review cardinality; machine-local scope remains architectural. | SQL equality padding is decisive; there is no trim in the original. Tab-only hash is a legacy non-trigger but an engine trigger. |
| `ASSET_DESTINATION_MISSING` | `WHERE NOT EXISTS (SELECT 1 FROM cfg.ManagedAssetDestination WHERE AssetType='CUSTOMER_LOGO' AND IsEnabled=1)` | Engine emits only when there are zero enabled destination rows of **any** asset type. | **No.** An unrelated enabled destination suppresses the engine issue even when `CUSTOMER_LOGO` has none. | **DIVERGENCIA** - E0h must restore the `AssetType='CUSTOMER_LOGO'` filter. Exact portable code/value policy, where applicable, must remain approved architecture. | Original `AssetType='CUSTOMER_LOGO'` is CI_AS/padded. The engine does not perform this text comparison at all. |

## Engine behavior with no original equivalent

There are no additional issue-code names in `Invoke-ReviewManagedAssets`; the divergence is in the predicates and scope of the same three names. In particular, the engine-added zero-length-logo rule and all-whitespace hash rule have no textual equivalent in `cfg.ReviewManagedAssets` and are `DIVERGENCIA` work for E0h.

## Result

None of the three engine predicates is textually equivalent to its original predicate. The differences are observable: selected-instance review cardinality, zero-length BLOB handling, broad whitespace handling, and destination filtering by asset type. Approved machine-local/exact-code architecture is not an E0h rollback; the rows marked `DIVERGENCIA` identify the parity changes E0h must make. This audit is text only and does not authorize engine changes.
