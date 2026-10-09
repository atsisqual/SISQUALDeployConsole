# DEPLOYMENT_PREFLIGHT predicates: Links page model

**Status:** [PROPOSED]
**Procedure:** `cfg.ReviewLinksPageModel`
**Verification base:** `main@28d4dc52c2d02bdce2add2101a306845041690b3`

## Evidence boundary

Predicates are copied from `docs/handoff/preflight-legacy-procedures.sql.txt`. The requested seven-code set is the subset still listed by `docs/handoff/preflight-port-gap.md` on read-only PR #69; `LINKS_PAGE_POLICY_MISSING` is intentionally not repeated because the gap counts it as already ported.

SQLite tables/columns were checked against `tests/Fixtures/carried-schema.json`. The evidence header and `docs/decisions-log.md` record the source database collation as `Latin1_General_CI_AS`: source comparisons without explicit `COLLATE` are case-insensitive and accent-sensitive. The same 2026-10-05 owner decision makes catalog codes exact in the new system.

The evidence header also fixes SQL Server string boundaries used below: equality pads ordinary spaces, so `NULLIF(x,'')` returns `NULL` for spaces-only values; tabs or other whitespace are not empty under that rule.

### Shared setup in the source procedure

The predicates that use `@ServerCode` depend on this exact source assignment:

```sql
SELECT @ServerCode = S.ServerCode
FROM dbo.ManagedServer AS S
WHERE S.MachineName = @MachineName
  AND S.IsEnabled = 1;
```

Legacy `MachineName` equality is CI_AS. Portable Windows-name matching remains case-insensitive and accent-sensitive to preserve that source behavior. `ServerCode`, `InstanceCode`, `TemplateCode`, `AssetCode`, and `ApplicationCode` are catalog codes and remain exact by the owner decision.

The assignment has no `TOP` or `ORDER BY`. If more than one enabled `ManagedServer` row has the same machine name under CI_AS, the chosen `@ServerCode` is nondeterministic. **[PENDING]** Do not invent a tie-breaker. This ambiguity affects both `MANAGED_INSTANCE_NOT_ACTIONABLE` below **and the already-ported `LINKS_PAGE_POLICY_MISSING`**, because that legacy check queries `cfg.LinksPagePolicy` with the selected `@ServerCode`.

## `MANAGED_SERVER_NOT_FOUND`

**Verbatim T-SQL predicate:**

```sql
IF @ServerCode IS NULL
```

with `@ServerCode` populated by the shared query above.

**SQLite inputs:** `dbo_ManagedServer(ServerCode, MachineName, IsEnabled)`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison. Report a machine-registration failure in the selected run while retaining the machine name.

**Rule 7:** No filesystem path.

**Text comparison:** Source is CI_AS; portable Windows-machine comparison preserves case-insensitive/accent-sensitive behavior.

**Tests:** Trigger: no enabled server matches. Non-trigger: one enabled server matches. Boundaries: case-only difference still matches; accent-only difference does not. Multiple matching server rows keep `@ServerCode` non-null, so this particular predicate itself does not fire.

**Ambiguity:** The null/not-null predicate is clear. Duplicate matching servers are a shared setup ambiguity described above.

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

**Text comparison:** Legacy source would compare the literal under CI_AS, but `TemplateCode` is a catalog code. The owner decision makes portable code comparison exact, including case and accents.

**Tests:** Trigger: exact enabled `LINKS_INDEX_HTML` absent/disabled. Non-trigger: exact enabled row. Boundary: only `links_index_html` exists -> portable exact-code check still fires.

**Ambiguity:** None after the exact-code decision.

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

**Text comparison:** `TemplateCode` is exact in the portable catalog by owner decision.

**Tests:** Trigger: exact enabled row absent/disabled. Non-trigger: exact enabled row exists. Boundary: case-only code variant does not satisfy the portable exact-code check.

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

**SQLite inputs:** `cfg_LinksPageAsset(AssetCode, IsEnabled, Content)`; `Content` is the carried BLOB.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison.

**Rule 7:** No filesystem path; BLOB presence/length only.

**Text comparison:** `AssetCode` is an exact portable catalog code. `DATALENGTH(Content) > 0` is binary length semantics.

**Tests:** Trigger: exact asset absent, disabled, null, or zero bytes. Non-trigger: enabled exact asset with at least one byte. Boundary: one-byte BLOB is sufficient; case-only code variant is not.

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

**SQLite inputs:** `cfg_Application(IsEnabled, PublishInLinks)`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison.

**Rule 7:** No filesystem path.

**Text comparison:** None.

**Tests:** Trigger: no application is both enabled and published. Non-trigger: at least one has both flags. Boundary: published but disabled does not satisfy the predicate.

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

**SQLite inputs:** `cfg_Application(ApplicationCode, IsEnabled, PublishInLinks, LinksUrlTemplate, IisPath)`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison. Report the definition problem in the selected run and retain `ApplicationCode` in details.

**Rule 7:** `IisPath` is an IIS/application path field, but this predicate only tests emptiness and performs no filesystem probe. Any later filesystem consumer must apply real-path rule 7 separately.

**Text comparison:** SQL Server padded equality controls `NULLIF`. Null, empty, or **ordinary-spaces-only** `LinksUrlTemplate`/`IisPath` each become null for this test. Therefore the issue fires when both fields are null/empty/spaces-only. A tab-only value is non-empty under this rule because there is no trim and the padding rule is about ordinary spaces.

**Tests:** Trigger: enabled published application has both fields null/empty/spaces-only. Non-trigger: either has substantive text. Boundaries: both fields ordinary-spaces-only -> fires; one field tab-only -> does not fire solely as empty.

**Ambiguity:** None. Do not copy SQLite raw equality behavior and do not add all-whitespace trimming.

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

`@ServerCode` is populated by the shared query above.

**SQLite inputs:** `dbo_ManagedServer(ServerCode, MachineName, IsEnabled)` and `dbo_ManagedInstance(ServerCode, InstanceCode, IsEnabled)`.

**Original severity:** `ERROR`.

**Rule 6:** Not a value conflict between instances. Validate the requested instance against the resolved local server and report on `@InstanceCode` itself.

**Rule 7:** No filesystem path.

**Text comparison:** `MachineName` preserves CI_AS behavior; `ServerCode` and `InstanceCode` are exact portable catalog codes.

**Tests:** Trigger: requested code absent, disabled, or attached to another server. Non-trigger: exact requested enabled instance belongs to resolved server. Boundary: case-only instance-code variant does not match portable exact code.

**Ambiguity:** **[PENDING]** Duplicate enabled server rows matching one `MachineName` make `@ServerCode` nondeterministic. Required owner/source-model question: should the port reject that model state, and under which issue code? This ambiguity also affects the already-ported `LINKS_PAGE_POLICY_MISSING`: when only one matching server has an enabled policy, the legacy result depends on which `@ServerCode` assignment wins.

## Implementation stop points

All seven requested predicates are specified. The remaining source/model ambiguity is the duplicate-enabled-server tie for `@ServerCode`; it affects `MANAGED_INSTANCE_NOT_ACTIONABLE` and the already-ported `LINKS_PAGE_POLICY_MISSING`. This D13c PR does not modify the engine; it records that the existing policy check must be revisited when the `[PENDING]` tie behavior is decided. Source collation is confirmed CI_AS, while portable catalog codes remain exact by owner decision.
