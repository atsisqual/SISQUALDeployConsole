# DEPLOYMENT_PREFLIGHT predicates: Links page model

**Status:** [PROPOSED]
**Procedure:** `cfg.ReviewLinksPageModel`
**Verification base:** `main@a32141cbec584d349f1591a4aa5a801137463278`

## Evidence boundary

Predicates are copied from `docs/handoff/preflight-legacy-procedures.sql.txt`. The requested seven-code set is the subset still listed by `docs/handoff/preflight-port-gap.md` on read-only PR #69 head `80240090ba5dc37e13a64d359f9378a1c033fcc4`; `LINKS_PAGE_POLICY_MISSING` is intentionally not repeated because the gap counts it as already ported.

SQLite tables and columns below were checked against `tests/Fixtures/carried-schema.json` at the verification base. SQL Server names map to SQLite with `_` between schema and object name. The requested `tests/Fixtures/preflight-legacy-codes.json` is not present in this `main` tree, so severities are verified from the literal T-SQL and the port-gap table.

### Shared setup in the source procedure

The two predicates that use `@ServerCode` depend on this exact source assignment:

```sql
SELECT @ServerCode = S.ServerCode
FROM dbo.ManagedServer AS S
WHERE S.MachineName = @MachineName
  AND S.IsEnabled = 1;
```

`MachineName` is a Windows name and is compared without case in the portable behavior. `ServerCode`, `InstanceCode`, `TemplateCode`, `AssetCode`, and `ApplicationCode` are catalog codes and remain exact. Trim/empty checks do not depend on collation.

The source assignment has no `TOP` or `ORDER BY`. If more than one enabled `ManagedServer` row has the same machine name, the chosen `@ServerCode` is not deterministic in T-SQL. Where that matters below, it is marked `[PENDING]` rather than given an invented tie-breaker.

## `MANAGED_SERVER_NOT_FOUND`

**Verbatim T-SQL predicate:**

```sql
IF @ServerCode IS NULL
```

with `@ServerCode` populated by the shared source query above.

**SQLite inputs:** `dbo_ManagedServer(ServerCode, MachineName, IsEnabled)`, confirmed in `carried-schema.json`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison. If the machine cannot resolve to an enabled server, report the error on the selected instance requested by the preflight, while retaining the machine name in details.

**Rule 7:** No filesystem path is used.

**Text comparison:** `MachineName` is a Windows name, so portable matching is case-insensitive. `ServerCode` is only assigned, not compared here.

**Tests:** Trigger: no enabled server matches the machine. Non-trigger: one enabled server matches. Boundary: case-only machine-name difference must still match; multiple enabled rows with the same machine name still make this particular predicate non-null and therefore non-triggering.

**Ambiguity:** No ambiguity for the null/not-null predicate itself. Duplicate server rows become material for `MANAGED_INSTANCE_NOT_ACTIONABLE` below because the chosen code is unspecified.

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

**SQLite inputs:** `cfg_LinksPageTemplate(TemplateCode, IsEnabled)`, confirmed in `carried-schema.json`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison. The template is global; report its absence on the selected instance whose Links page requires it.

**Rule 7:** No filesystem path is used.

**Text comparison:** `TemplateCode` is a catalog code, so portable behavior uses exact comparison. This deliberately does not emulate an unknown case-insensitive legacy collation for a case-only variant.

**Tests:** Trigger: exact enabled `LINKS_INDEX_HTML` row is absent or disabled. Non-trigger: exact enabled row exists. Boundary: only `links_index_html` exists; exact portable code comparison must still fire.

**Ambiguity:** None after applying the explicit exact-code rule.

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

**SQLite inputs:** `cfg_LinksPageTemplate(TemplateCode, IsEnabled)`, confirmed in `carried-schema.json`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison. Report the global template defect on the selected instance.

**Rule 7:** No filesystem path is used.

**Text comparison:** `TemplateCode` is an exact catalog code.

**Tests:** Trigger: exact enabled `LINKS_WEB_CONFIG` is absent/disabled. Non-trigger: exact enabled row exists. Boundary: case-only code variant does not satisfy the portable exact-code check.

**Ambiguity:** None.

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

**SQLite inputs:** `cfg_LinksPageAsset(AssetCode, IsEnabled, Content)`, all confirmed in `carried-schema.json`; `Content` is the carried BLOB field.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison. The asset is global and the failure is reported on the selected instance whose page requires it.

**Rule 7:** No catalog filesystem path is used; the predicate checks BLOB presence/length only.

**Text comparison:** `AssetCode` is an exact catalog code. `DATALENGTH(Content) > 0` is binary/length semantics, not collation-dependent.

**Tests:** Trigger: exact asset is absent, disabled, null, or zero bytes. Non-trigger: enabled exact asset with at least one byte. Boundary: a one-byte BLOB is sufficient; a case-only `sisqual_logo` code is not.

**Ambiguity:** None.

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

**SQLite inputs:** `cfg_Application(IsEnabled, PublishInLinks)`, confirmed in `carried-schema.json`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison; this is a global application-definition existence check. Report on the selected instance.

**Rule 7:** No filesystem path is used.

**Text comparison:** None.

**Tests:** Trigger: no application is both enabled and published. Non-trigger: at least one row has both flags set. Boundary: a published but disabled application does not satisfy the predicate.

**Ambiguity:** None.

## `PUBLISHED_APPLICATION_URL_UNRESOLVED`

**Verbatim T-SQL predicate:**

```sql
FROM cfg.Application AS A
WHERE A.IsEnabled = 1
  AND A.PublishInLinks = 1
  AND NULLIF(A.LinksUrlTemplate, N'') IS NULL
  AND NULLIF(A.IisPath, N'') IS NULL;
```

**SQLite inputs:** `cfg_Application(ApplicationCode, IsEnabled, PublishInLinks, LinksUrlTemplate, IisPath)`, confirmed in `carried-schema.json`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison. This validates each published application definition; when surfaced through a selected-instance preflight, report it on the selected instance and retain `ApplicationCode` in the issue details/object.

**Rule 7:** `IisPath` is an IIS/application path field, but this predicate only tests whether it is an empty string and performs no filesystem probe. Rule 7 real-path resolution/confinement is therefore not invoked by this check. A later filesystem consumer must apply rule 7 separately.

**Text comparison:** `NULLIF(..., N'')` tests exact empty string only; the source does not trim. Whitespace-only `LinksUrlTemplate` or `IisPath` is therefore non-empty and prevents this issue. `ApplicationCode` is only used to construct details and remains an exact code elsewhere.

**Tests:** Trigger: enabled published application has both URL template and IIS path null/empty. Non-trigger: either field is non-empty. Boundary: both fields are whitespace-only; source semantics say this issue does not fire because there is no trim.

**Ambiguity:** None. Do not add whitespace normalization absent from the T-SQL.

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

`@ServerCode` is populated by the shared source query above.

**SQLite inputs:** `dbo_ManagedServer(ServerCode, MachineName, IsEnabled)` for the shared assignment and `dbo_ManagedInstance(ServerCode, InstanceCode, IsEnabled)` for the existence check. All columns are confirmed in `carried-schema.json`.

**Original severity:** `ERROR`.

**Rule 6:** This is not a value conflict between instances. It validates the selected/requested instance against the resolved local server. Report the error on `@InstanceCode` itself. Do not make another enabled instance actionable as a substitute and do not limit any future cross-instance conflict check to selected rows.

**Rule 7:** No filesystem path is used.

**Text comparison:** `MachineName` is case-insensitive as a Windows name. `ServerCode` and `InstanceCode` are exact catalog codes. A case-only instance-code variant therefore does not match the portable catalog row.

**Tests:** Trigger: requested code is absent, disabled, or belongs to another server. Non-trigger: exact requested enabled instance belongs to the resolved server. Boundary: requested instance differs only by code case; portable exact-code behavior must fire.

**Ambiguity:** **[PENDING]** If more than one enabled `dbo.ManagedServer` row has the same `MachineName`, the source `SELECT @ServerCode = ...` has no ordering and the server chosen for this predicate is unspecified. Do not invent a first/lowest-code rule. Required question: should the port treat duplicate enabled server rows for one Windows machine as a model error, and if so under which existing/new issue code?

## Implementation stop points

All seven requested predicates are directly specified. The only unresolved source behavior in this procedure is the duplicate-enabled-server tie case for `@ServerCode`; it affects `MANAGED_INSTANCE_NOT_ACTIONABLE` and is explicitly `[PENDING]`. This document does not change or duplicate `LINKS_PAGE_POLICY_MISSING`, which the supplied gap says is already ported.
