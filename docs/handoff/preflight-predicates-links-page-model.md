# DEPLOYMENT_PREFLIGHT predicates: Links page model

**Status:** [PROPOSED]
**Procedure:** `cfg.ReviewLinksPageModel`
**Verification base:** `main@f7989a6b9043b9b16300404eb7e1dd27ca06a2aa`

## Evidence boundary

Predicates are copied from `docs/handoff/preflight-legacy-procedures.sql.txt`. The requested seven-code subset and rules 6/7 come from the regenerated `docs/handoff/preflight-port-gap.md` on read-only PR #69; `LINKS_PAGE_POLICY_MISSING` is already ported and is mentioned only where the shared source setup affects it.

SQLite tables/columns were checked against `tests/Fixtures/carried-schema.json`. Source text comparison is `Latin1_General_CI_AS`: case-insensitive, accent-sensitive, with SQL Server equality padding ordinary spaces. Catalog codes compare exactly in the new system by owner decision.

### Shared legacy server selection and portable boundary

The original procedure assigns:

```sql
SELECT @ServerCode = S.ServerCode
FROM dbo.ManagedServer AS S
WHERE S.MachineName = @MachineName
  AND S.IsEnabled = 1;
```

With duplicate enabled rows for the same machine this legacy assignment has no `TOP`/`ORDER BY` and is nondeterministic. That historical ambiguity affects both `MANAGED_INSTANCE_NOT_ACTIONABLE` and the already-ported `LINKS_PAGE_POLICY_MISSING` because both consume the chosen `@ServerCode`.

It is **not** a portable `[PENDING]` branch. `tools/Convert-ManagementDb.Core.ps1` refuses duplicate `MachineName` ownership during conversion, and `Get-SisqualRuntimeCatalogMachineName` requires exactly one `dbo_ManagedServer` row before model review runs. The portable review therefore receives one server row; a malformed multi-row catalog fails at the conversion/runtime boundary instead of choosing a tie-breaker.

### Complete text-operator matrix

Line numbers are relative to the first `CREATE OR ALTER PROCEDURE` line of `cfg.ReviewLinksPageModel` in the evidence file.

| Procedure line | Operator / expression | Legacy T-SQL behavior | Portable behavior |
|---|---|---|---|
| 12 | `S.MachineName = @MachineName` | CI_AS plus equality padding; duplicate matches leave assignment order unspecified | [PROPOSED] Windows machine name compares without case and accent-sensitively; duplicate server state is rejected before review, not resolved here. [PENDING] Whether Windows-name trailing-space padding is intentionally preserved |
| 39 | `ServerCode = @ServerCode` | CI_AS plus padding | [PROPOSED] Exact catalog-code comparison in the new system |
| 56 | `TemplateCode = 'LINKS_INDEX_HTML'` | CI_AS plus padding | [PROPOSED] Exact catalog code; case/trailing-space variants intentionally do not satisfy the portable check |
| 65 | `TemplateCode = 'LINKS_WEB_CONFIG'` | CI_AS plus padding | [PROPOSED] Exact catalog code |
| 74 | `AssetCode = 'SISQUAL_LOGO'` | CI_AS plus padding | [PROPOSED] Exact catalog code |
| 104 | `NULLIF(A.LinksUrlTemplate,N'')` | SQL equality padding: NULL, empty and ordinary-spaces-only become NULL; tab-only does not | [PROPOSED] Preserve exactly; no all-whitespace trim |
| 105 | `NULLIF(A.IisPath,N'')` | Same padded-empty behavior | [PROPOSED] Preserve exactly |
| 113 | `ServerCode = @ServerCode` | CI_AS plus padding | [PROPOSED] Exact catalog code |
| 114 | `InstanceCode = @InstanceCode` | CI_AS plus padding | [PROPOSED] Exact catalog code |

There is no `<>`, `LIKE`, `IN`, `REPLACE`, `LTRIM/RTRIM`, `LEN`, `GROUP BY`, `DISTINCT`, or text-to-text JOIN in this procedure beyond the equality expressions listed above. The matrix therefore covers every requested text operator that actually occurs.

## `MANAGED_SERVER_NOT_FOUND`

**Verbatim T-SQL predicate:**

```sql
IF @ServerCode IS NULL
```

with `@ServerCode` populated by the shared assignment above.

**SQLite inputs:** `dbo_ManagedServer(ServerCode, MachineName, IsEnabled)`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison. Report the machine-registration failure in the selected run.

**Rule 7:** No filesystem path.

**Text comparison:** Matrix line 12.

**Tests:** Trigger: no enabled server matches. Non-trigger: sole enabled server matches. Boundary: case-only machine-name difference matches; accent-only does not. A duplicate-server catalog is rejected before this portable review.

**Ambiguity:** No portable ambiguity. The source's duplicate-row assignment remains documented historical behavior only.

## `LINKS_INDEX_TEMPLATE_MISSING`

**Verbatim T-SQL predicate:**

```sql
IF NOT EXISTS
(
    SELECT 1
    FROM cfg.LinksPageTemplate
    WHERE TemplateCode = 'LINKS_INDEX_HTML'
      AND IsEnabled = 1
)
```

**SQLite inputs:** `cfg_LinksPageTemplate(TemplateCode, IsEnabled)`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison.

**Rule 7:** No filesystem path.

**Text comparison:** Matrix line 56: exact portable catalog code.

**Tests:** Trigger: exact enabled code absent/disabled. Non-trigger: exact enabled row. Boundary: case-only/trailing-space variant does not satisfy the portable exact-code check.

## `LINKS_WEB_CONFIG_TEMPLATE_MISSING`

**Verbatim T-SQL predicate:**

```sql
IF NOT EXISTS
(
    SELECT 1
    FROM cfg.LinksPageTemplate
    WHERE TemplateCode = 'LINKS_WEB_CONFIG'
      AND IsEnabled = 1
)
```

**SQLite inputs:** `cfg_LinksPageTemplate(TemplateCode, IsEnabled)`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison.

**Rule 7:** No filesystem path.

**Text comparison:** Matrix line 65.

**Tests:** Trigger: exact enabled row absent. Non-trigger: exact enabled row exists. Boundary: case-only/trailing-space variant does not match portable exact code.

## `LINKS_BRAND_LOGO_MISSING`

**Verbatim T-SQL predicate:**

```sql
IF NOT EXISTS
(
    SELECT 1
    FROM cfg.LinksPageAsset
    WHERE AssetCode = 'SISQUAL_LOGO'
      AND IsEnabled = 1
      AND DATALENGTH(Content) > 0
)
```

**SQLite inputs:** `cfg_LinksPageAsset(AssetCode, IsEnabled, Content)`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison.

**Rule 7:** No filesystem path; BLOB length only.

**Text comparison:** Matrix line 74. `DATALENGTH(Content)` is binary length, not collation.

**Tests:** Trigger: exact asset absent, disabled, null or zero bytes. Non-trigger: enabled exact asset with at least one byte. Boundary: one byte is enough; case-only asset-code variant is not.

## `NO_PUBLISHED_LINK_APPLICATIONS`

**Verbatim T-SQL predicate:**

```sql
IF NOT EXISTS
(
    SELECT 1
    FROM cfg.Application
    WHERE IsEnabled = 1
      AND PublishInLinks = 1
)
```

**SQLite inputs:** `cfg_Application(IsEnabled, PublishInLinks)`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison.

**Rule 7:** No filesystem path.

**Text comparison:** None.

**Tests:** Trigger: no enabled published app. Non-trigger: at least one enabled published row. Boundary: published but disabled does not count.

## `PUBLISHED_APPLICATION_URL_UNRESOLVED`

**Verbatim T-SQL predicate:**

```sql
FROM cfg.Application AS A
WHERE A.IsEnabled = 1
  AND A.PublishInLinks = 1
  AND NULLIF(A.LinksUrlTemplate, N'') IS NULL
  AND NULLIF(A.IisPath, N'') IS NULL;
```

**SQLite inputs:** `cfg_Application(ApplicationCode, IsEnabled, PublishInLinks, LinksUrlTemplate, IisPath)`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison.

**Rule 7:** `IisPath` is not probed by this predicate; later filesystem consumers still apply resolved-path confinement.

**Text comparison:** Matrix lines 104-105.

**Tests:** Trigger: both fields null/empty/ordinary-spaces-only. Non-trigger: either has substantive text. Boundary: a tab-only field is non-empty for this source predicate.

## `MANAGED_INSTANCE_NOT_ACTIONABLE`

**Verbatim T-SQL predicate:**

```sql
IF @ServerCode IS NOT NULL
   AND @InstanceCode IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM dbo.ManagedInstance
       WHERE ServerCode = @ServerCode
         AND InstanceCode = @InstanceCode
         AND IsEnabled = 1
   )
```

**SQLite inputs:** `dbo_ManagedServer(ServerCode, MachineName, IsEnabled)` and `dbo_ManagedInstance(ServerCode, InstanceCode, IsEnabled)`.

**Original severity:** `ERROR`.

**Rule 6:** Not a cross-instance value conflict. Validate the requested instance against the sole portable local server and report on that requested code.

**Rule 7:** No filesystem path.

**Text comparison:** Matrix lines 113-114. Both codes are exact in the portable catalog.

**Tests:** Trigger: requested exact code absent/disabled/owned by another server. Non-trigger: exact enabled instance belongs to local server. Boundary: case-only code variant does not match. A duplicate-server catalog cannot reach this review.

## Already-ported `LINKS_PAGE_POLICY_MISSING` and the historical tie

The original policy predicate consumes the same `@ServerCode` assignment. In the legacy central database a duplicate enabled machine row could therefore alter the result. In the portable system there is no tie to resolve: conversion/runtime require the single server row before the engine runs. The existing port does not need a new duplicate-server issue or tie-breaker for this reason.

## Implementation stop points

The duplicate-server behavior is historical evidence, not a portable blocker. The only comparison dimension still `[PENDING]` here is whether Windows machine-name trailing-space padding should be preserved in addition to the permanent no-case rule and confirmed accent sensitivity. Catalog codes are exact by owner decision. No predicate is inferred from its code name.
