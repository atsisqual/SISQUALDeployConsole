# DEPLOYMENT_PREFLIGHT predicates: Website branding

**Status:** [PROPOSED]
**Procedure:** `cfg.ReviewWebsiteBrandingModel`
**Verification base:** `main@a32141cbec584d349f1591a4aa5a801137463278`

## Evidence boundary

Predicates are copied from `docs/handoff/preflight-legacy-procedures.sql.txt`. The five requested codes and rules 6/7 come from `docs/handoff/preflight-port-gap.md` on read-only PR #69 head `80240090ba5dc37e13a64d359f9378a1c033fcc4`.

SQLite table/column names were checked against `tests/Fixtures/carried-schema.json` at the verification base. `cfg.WebsiteBrandingProfile` becomes `cfg_WebsiteBrandingProfile`; `cfg.WebsiteBrandingAsset` becomes `cfg_WebsiteBrandingAsset`.

The requested `tests/Fixtures/preflight-legacy-codes.json` is not present in this `main` tree. Every severity below is taken from the literal extracted procedure and agrees with the five-code port-gap table.

This document resolves ambiguity **A1** in `docs/handoff/pulse-status-port-brief.md` at the source-predicate level. The reviewer-extracted procedure proves that the five issue codes emitted by this review are:

- `WEBSITE_BRANDING_PROFILE_MISSING`;
- `WEBSITE_BRANDING_ASSET_HASH_MISMATCH`;
- `WEBSITE_BRANDING_REQUIRED_ASSET_MISSING`;
- `WEBSITE_BRANDING_TITLE_INVALID`;
- `WEBSITE_BRANDING_ROOT_MISSING`.

It does not edit the paused Pulse brief. It also does not resolve the separate branding destination/plan derivation question: two predicates consume rows returned by `cfg.GetWebsiteBrandingPlan`, whose definition is not part of the supplied five-procedure source file.

### Text comparison policy

The procedure has no `COLLATE`, so legacy text equality follows the source database default collation, which is not stated. Portable rule 7 keeps catalog codes exact and Windows names case-insensitive. Trim/empty and brace-token checks below are independent of letter case. The hexadecimal hash comparison has a case-only ambiguity because the source lowercases the computed hash but does not normalize the stored value; that boundary is `[PENDING]` rather than guessed.

## `WEBSITE_BRANDING_PROFILE_MISSING`

**Verbatim T-SQL predicate:**

```sql
IF NOT EXISTS
(
    SELECT 1
    FROM cfg.WebsiteBrandingProfile
    WHERE ProfileCode = 'DEFAULT'
      AND IsEnabled = 1
)
```

**SQLite inputs:** `cfg_WebsiteBrandingProfile(ProfileCode, IsEnabled)`, confirmed in `carried-schema.json`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison. The profile is global; when the preflight is run for one selected instance, report the missing global prerequisite on that selected instance.

**Rule 7:** No filesystem path is used.

**Text comparison:** `ProfileCode` is a catalog code and remains exact in the portable engine. A case-only `default` row does not satisfy the exact portable code match.

**Tests:** Trigger: exact enabled `DEFAULT` profile is absent/disabled. Non-trigger: exact enabled row exists. Boundary: only enabled `default` exists; portable exact-code behavior still fires.

**Ambiguity:** None after applying the exact-code rule.

## `WEBSITE_BRANDING_ASSET_HASH_MISMATCH`

**Verbatim T-SQL predicate:**

```sql
FROM cfg.WebsiteBrandingAsset
WHERE IsEnabled = 1
  AND LOWER
      (
          CONVERT
          (
              char(64),
              HASHBYTES('SHA2_256', BinaryContent),
              2
          )
      ) <> ContentSha256;
```

**SQLite inputs:** `cfg_WebsiteBrandingAsset(AssetCode, BinaryContent, ContentSha256, IsEnabled)`, all confirmed in `carried-schema.json`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison; this validates each enabled global branding asset. Report an asset failure on the selected instance and retain `AssetCode` in object/details data.

**Rule 7:** No filesystem path is used; the predicate hashes a carried BLOB.

**Text comparison:** The computed SHA-256 is converted to lowercase hexadecimal, then compared to stored `ContentSha256` under the unknown legacy collation. **[PENDING]** Decide whether a stored uppercase representation of the same hash is accepted. The cryptographic bytes are unambiguous; only textual hex case is unresolved.

**Tests:** Trigger: enabled asset has content whose computed SHA-256 differs from stored hash. Non-trigger: stored lowercase hash equals computed lowercase hash. Boundary: stored uppercase hex represents the same bytes; expected result remains **[PENDING]** the hash-text case decision.

**Ambiguity:** Case-only hexadecimal comparison only.

## `WEBSITE_BRANDING_REQUIRED_ASSET_MISSING`

**Verbatim T-SQL predicate:**

```sql
FROM
(
    VALUES
        ('WEBSITE_FAVICON_ICO'),
        ('WEBSITE_FAVICON_PNG'),
        ('WEBSITE_APPLE_TOUCH_ICON')
) AS V(AssetCode)
WHERE NOT EXISTS
(
    SELECT 1
    FROM cfg.WebsiteBrandingAsset AS A
    WHERE A.AssetCode = V.AssetCode
      AND A.IsEnabled = 1
);
```

**SQLite inputs:** `cfg_WebsiteBrandingAsset(AssetCode, IsEnabled)`, confirmed in `carried-schema.json`. The three required codes are constants from the source predicate, not catalog rows.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison. Required branding assets are global; report each missing code on the selected instance.

**Rule 7:** No filesystem path is used.

**Text comparison:** `AssetCode` is a catalog code and is compared exactly in the portable engine. Case-only variants do not satisfy a required code.

**Tests:** Trigger: one of the three exact required asset codes is missing or disabled. Non-trigger: all three exact codes are enabled. Boundary: `website_favicon_ico` exists but exact `WEBSITE_FAVICON_ICO` does not; portable exact-code behavior fires for the required code.

**Ambiguity:** None.

## Shared plan gate for the last two predicates

The source wraps both remaining checks in this exact gate and plan population:

```sql
IF @MachineName IS NOT NULL
BEGIN
    DECLARE @Plan TABLE
    (
        ServerCode varchar(30),
        MachineName sysname,
        InstanceCode varchar(20),
        CountryCode char(2),
        CustomerCode int,
        CustomerName nvarchar(200),
        HostName sysname,
        WebsiteRoot nvarchar(2000),
        DocumentTitle nvarchar(300),
        PulseDocumentTitle nvarchar(300),
        ThemeColor char(7)
    );

    INSERT @Plan
    EXEC cfg.GetWebsiteBrandingPlan
        @MachineName = @MachineName,
        @InstanceCode = @InstanceCode;
```

`@Plan` is an in-procedure table variable, not a carried SQLite table. `InstanceCode`, `MachineName`, `HostName`, and other base facts exist in carried tables, and `cfg_WebsiteBrandingProfile` carries `DocumentTitleTemplate`, `PulseDocumentTitleTemplate`, and `ThemeColor`, but the supplied predicate source does not contain `cfg.GetWebsiteBrandingPlan`. Therefore this D13d document does not invent the exact portable derivation of `WebsiteRoot`, `DocumentTitle`, or `PulseDocumentTitle`.

## `WEBSITE_BRANDING_TITLE_INVALID`

**Verbatim T-SQL predicate:**

```sql
FROM @Plan
WHERE NULLIF(LTRIM(RTRIM(DocumentTitle)), N'') IS NULL
   OR NULLIF(LTRIM(RTRIM(PulseDocumentTitle)), N'') IS NULL
   OR DocumentTitle LIKE N'%{%}%'
   OR PulseDocumentTitle LIKE N'%{%}%';
```

This predicate is executed only inside the `IF @MachineName IS NOT NULL` gate above.

**SQLite inputs:** No carried table has the derived `@Plan.DocumentTitle` or `@Plan.PulseDocumentTitle` columns. `cfg_WebsiteBrandingProfile(DocumentTitleTemplate, PulseDocumentTitleTemplate, IsEnabled)` exists in `carried-schema.json`, as do instance/server metadata, but the exact expansion performed by `cfg.GetWebsiteBrandingPlan` is **[PENDING]** source evidence rather than inferred here. `@Plan.InstanceCode` is the report target and maps conceptually to carried `dbo_ManagedInstance.InstanceCode`, but exact plan-row selection must come from the plan procedure.

**Original severity:** `ERROR`.

**Rule 6:** No instance-to-instance comparison. The plan may contain rows for multiple instances when no `@InstanceCode` is supplied, but one selected-instance preflight must evaluate/report only the selected instance's plan row; another instance's invalid title is not relabeled as the selected instance's issue.

**Rule 7:** No filesystem path is read by this title predicate.

**Text comparison:** Blank detection uses trim and is collation-independent. `LIKE N'%{%}%'` looks for an opening brace followed later by a closing brace; letter case is irrelevant. Preserve those exact structural semantics.

**Tests:** Trigger: selected plan row has blank `DocumentTitle`, blank `PulseDocumentTitle`, or a remaining `{TOKEN}`-style brace pair in either title. Non-trigger: both titles are nonblank and contain no `{...}` pair. Boundary: a title containing a lone `{` with no later `}` does not match `%{%}%` and must not fire on that reason alone.

**Ambiguity:** **[PENDING]** Extract `cfg.GetWebsiteBrandingPlan` before implementation so the portable engine knows exactly how carried templates/instance metadata become the two derived title strings. The predicate itself is no longer ambiguous; this is the plan-input mapping question.

## `WEBSITE_BRANDING_ROOT_MISSING`

**Verbatim T-SQL predicate:**

```sql
FROM @Plan
WHERE NULLIF(LTRIM(RTRIM(WebsiteRoot)), N'') IS NULL;
```

This predicate is executed only inside the same `IF @MachineName IS NOT NULL` gate and after `cfg.GetWebsiteBrandingPlan` populates `@Plan`.

**SQLite inputs:** `@Plan.WebsiteRoot` is derived output, not a carried column. `dbo_ManagedServer.ServicesRoot` and `dbo_ManagedInstance.HostName` are carried inputs that may participate in the legacy plan, but the supplied source does not prove the exact derivation. Do not infer it from naming or from another document.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison. Evaluate/report the selected instance's derived plan row only.

**Rule 7:** Yes. `WebsiteRoot` is a filesystem path. The source predicate itself only detects null/blank. Once a nonblank portable root is derived, any existence/read/write probe must first resolve symlinks/junctions and prove confinement under its approved root using rule 7. The approved-root derivation is part of the missing plan evidence and must not be guessed.

**Text comparison:** Trim/blank detection is collation-independent.

**Tests:** Trigger: selected plan row has null, empty, or whitespace-only `WebsiteRoot`. Non-trigger: nonblank derived root. Boundary: nonblank path that lexically appears contained but resolves through a junction outside the approved root must pass this *missing* predicate but be rejected by the separate rule-7 containment validation before any probe.

**Ambiguity:** **[PENDING]** Extract `cfg.GetWebsiteBrandingPlan` to define the exact carried inputs and approved root used to derive `WebsiteRoot`. Do not implement a guessed `ServicesRoot + HostName` expression under this issue code without source evidence.

## A1 resolution and remaining stop points

D13d resolves the Pulse brief's A1 question because the exact reviewer-extracted `cfg.ReviewWebsiteBrandingModel` now provides the five actual issue-code predicates and severities. It does **not** resolve branding destination mapping, the exact `cfg.GetWebsiteBrandingPlan` projection, or the approved filesystem root. Those remain `[PENDING]` source questions and must be answered before the corresponding portable implementation/path probes are written.
