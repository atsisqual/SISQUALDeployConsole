# DEPLOYMENT_PREFLIGHT audit: Links QR codes

**Status:** [PROPOSED]
**Original:** `cfg.ReviewLinksPageQrCodes`
**Engine:** QR portion of `Invoke-ReviewLinksPresentation`
**Evidence:** original procedure at `main@f7989a6b9043b9b16300404eb7e1dd27ca06a2aa`; audited engine implementation at PR #67 final head `d4cf6fe974030a39d3ffe852d2809ce9009fe73b`, integrated by merge `41d09f38e5aedc4f9b62656870d0b999ca661205`.

`Tipo` classifies every observable difference: `ARQUITECTURAL` is an approved portable-system difference that E0h must preserve; `DIVERGENCIA` is parity work for E0h. If a row contains both, it is classified `DIVERGENCIA` and the approved sub-difference is called out explicitly.

## Original predicate text

The following block is copied verbatim from `docs/handoff/preflight-legacy-procedures-implemented.sql.txt` on `main`.

```sql
CREATE OR ALTER PROCEDURE cfg.ReviewLinksPageQrCodes
    @MachineName sysname = NULL,
    @InstanceCode varchar(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Issues TABLE
    (
        IssueCode varchar(100) NOT NULL,
        Severity varchar(10) NOT NULL,
        ObjectName nvarchar(300) NOT NULL,
        Details nvarchar(2000) NOT NULL
    );

    INSERT @Issues
    SELECT
        'QR_CONTENT_HASH_MISMATCH',
        'ERROR',
        A.AssetCode,
        N'The stored QR binary does not match ContentSha256.'
    FROM cfg.LinksPageAsset AS A
    WHERE A.IsEnabled = 1
      AND A.AssetCode LIKE 'QR_CHANNEL[_]%'
      AND LOWER
          (
              CONVERT
              (
                  char(64),
                  HASHBYTES('SHA2_256', A.Content),
                  2
              )
          ) <> A.ContentSha256;

    INSERT @Issues
    SELECT
        'QR_ASSET_MISSING',
        'WARNING',
        CONCAT(I.InstanceCode, N' / ', I.CustomerCode),
        N'No QR asset is configured for this enabled PT/ES environment.'
    FROM dbo.ManagedInstance AS I
    INNER JOIN dbo.ManagedServer AS S
        ON S.ServerCode = I.ServerCode
       AND S.IsEnabled = 1
    WHERE I.IsEnabled = 1
      AND I.CountryCode IN ('PT','ES')
      AND I.CustomerCode IS NOT NULL
      AND (@MachineName IS NULL OR S.MachineName = @MachineName)
      AND (@InstanceCode IS NULL OR I.InstanceCode = @InstanceCode)
      AND NOT EXISTS
      (
          SELECT 1
          FROM cfg.LinksPageAsset AS A
          WHERE A.AssetCode =
                'QR_CHANNEL_' + CONVERT(varchar(20), I.CustomerCode)
            AND A.IsEnabled = 1
      );

    INSERT @Issues
    SELECT
        'QR_ASSET_UNASSIGNED',
        'INFO',
        A.AssetCode,
        N'The QR asset is currently not assigned to an enabled ManagedInstance.'
    FROM cfg.LinksPageAsset AS A
    WHERE A.IsEnabled = 1
      AND A.AssetCode LIKE 'QR_CHANNEL[_]%'
      AND NOT EXISTS
      (
          SELECT 1
          FROM dbo.ManagedInstance AS I
          WHERE I.IsEnabled = 1
            AND A.AssetCode =
                'QR_CHANNEL_' + CONVERT(varchar(20), I.CustomerCode)
      );

    SELECT
        IssueCode,
        Severity,
        ObjectName,
        Details
    FROM @Issues
    ORDER BY
        CASE Severity
            WHEN 'ERROR' THEN 1
            WHEN 'WARNING' THEN 2
            ELSE 3
        END,
        IssueCode,
        ObjectName;
END;
```

## Audit

| Code | Original predicate, textual | Engine behavior | Coincidem? | Tipo | T-SQL semantics / port rule |
|---|---|---|---|---|---|
| `QR_CONTENT_HASH_MISMATCH` | Enabled `cfg.LinksPageAsset` rows where `AssetCode LIKE 'QR_CHANNEL[_]%'` and `LOWER(CONVERT(char(64),HASHBYTES('SHA2_256',A.Content),2)) <> A.ContentSha256`. | Engine selects enabled assets whose `AssetCode` starts with exact ordinal `QR_CHANNEL_`; if binary content exists **and hash is not `IsNullOrWhiteSpace`**, computes SHA-256 and compares lower-case forms exactly. | **Not fully.** Normal binary/hash mismatch and uppercase-hex cases coincide, but prefix and missing/whitespace-hash boundaries differ. Exact asset-code case is approved architecture. | **DIVERGENCIA** - E0h must preserve exact portable asset-code comparison but stop skipping non-NULL empty/ordinary-spaces hash values that the original flags. | Legacy `LIKE` runs under CI_AS, so prefix case is ignored; portable asset codes are exact by owner decision. Original NULL hash makes `<>` UNKNOWN/no issue, but empty/spaces hash is non-NULL and fires. |
| `QR_ASSET_MISSING` | Enabled instance + enabled server, `CountryCode IN ('PT','ES')`, nonnull `CustomerCode`, optional machine/instance filters, and no enabled asset whose `AssetCode='QR_CHANNEL_'+CustomerCode`. | For selected instances, engine requires exact `PT`/`ES`, a nonblank string representation of `CustomerCode`, and exact asset-code map membership; emits same `WARNING`. `CustomerCode` is a nullable integer in the carried schema, so every valid non-NULL value converts to a substantive numeric string. | **Same predicate intent modulo approved portable scope/code comparison.** `IsNullOrWhiteSpace` does not create an extra valid-data boundary for integer `CustomerCode`; it is equivalent to the original `IS NOT NULL` over the carried schema domain. | **ARQUITECTURAL** - preserve machine-local selection and exact portable code comparison; there is no CustomerCode parity task for E0h. | Original country/asset-code text comparisons are CI_AS/padded; portable codes are exact. `CustomerCode` is integer, so empty/whitespace text is not a representable non-NULL catalog value. |
| `QR_ASSET_UNASSIGNED` | Enabled QR asset and `NOT EXISTS` any enabled `dbo.ManagedInstance` whose computed QR code equals that asset. No machine filter exists in this subquery. | Engine creates assigned codes only from enabled `Context.Instances` in the current machine catalog; exact prefix/code matching; emits same `INFO`. | **No for central scope, intentionally.** The portable catalog is machine-local, so cross-machine assignments are outside this engine's data boundary. | **ARQUITECTURAL** - preserve machine-local catalog scope and exact asset-code comparison; E0h must not restore a central all-server query merely for textual parity. | Original asset-code `LIKE`/equality is CI_AS/padded. Portable codes are exact. The larger difference is approved catalog scope. |

## Additional boundaries

- Original hash comparison accepts uppercase/lowercase hexadecimal for the same digest under CI_AS; engine lowercases both and therefore preserves that outcome.
- `LIKE 'QR_CHANNEL[_]%'` uses `[_]` for a literal underscore. The engine `StartsWith('QR_CHANNEL_', Ordinal)` preserves the literal prefix shape while intentionally applying exact code case.
- Original severities are explicit and match the engine names: mismatch `ERROR`, missing asset `WARNING`, unassigned asset `INFO`.
- `CustomerCode` is a nullable integer in the carried schema. Therefore the original `CustomerCode IS NOT NULL` and the engine's nonblank numeric-string condition select the same valid catalog rows; there is no empty/whitespace CustomerCode case to port.

## Result

The three issue-code names and severities are preserved. `QR_ASSET_MISSING` and `QR_ASSET_UNASSIGNED` differ only through approved machine-local/exact-code architecture on valid carried data. The previously claimed CustomerCode divergence is removed because the schema makes it impossible. `QR_CONTENT_HASH_MISMATCH` retains the real blank-hash parity bug and is the `DIVERGENCIA` work for E0h. This audit is text only and does not authorize changes to PR #67.
