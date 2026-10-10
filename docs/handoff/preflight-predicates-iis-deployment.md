# DEPLOYMENT_PREFLIGHT predicates: IIS deployment

**Status:** [PROPOSED]
**Procedure:** `cfg.ReviewIisDeploymentModel`
**Verification base:** `main@f7989a6b9043b9b16300404eb7e1dd27ca06a2aa`

## Evidence boundary

Predicates are copied from `docs/handoff/preflight-legacy-procedures.sql.txt`. The seven requested unported codes and rules 6/7 come from `docs/handoff/preflight-port-gap.md` on read-only PR #69. `SERVER_POLICY_MISSING` and `IIS_IDENTITY_PASSWORD_PENDING` are outside this D13b set because the regenerated gap counts them as already ported.

SQLite table/column names were checked against `tests/Fixtures/carried-schema.json`. `cfg.ManagedInstanceRuntime` is a legacy view, not a carried table; its verbatim definition is in the evidence file. Metadata comes from carried `dbo_ManagedInstance`; portable secrets come from the request credential package.

The source database uses `Latin1_General_CI_AS`: comparisons without explicit `COLLATE` are case-insensitive and accent-sensitive. SQL Server equality pads ordinary spaces; `NULLIF(x,'')` therefore treats ordinary-spaces-only text as empty. Catalog codes compare exactly in the new system by the 2026-10-05 owner decision. Portable credential secrets are not catalog text: `contracts/credential-package.md` defines them as encrypted opaque values and the vault fingerprint is computed from the exact secret bytes. Therefore secret equality in the portable port is exact-byte equality, deliberately not CI_AS.

### Complete text-operator matrix

Line numbers are relative to the first `CREATE OR ALTER PROCEDURE` line of `cfg.ReviewIisDeploymentModel` in the evidence file.

| Procedure line | Operator / expression | Legacy T-SQL behavior | Portable behavior |
|---|---|---|---|
| 9 | `COALESCE(NULLIF(@MachineName,N''), ...)` | `NULLIF` uses padded equality: empty or ordinary-spaces-only input becomes NULL | [PROPOSED] Preserve the empty/spaces boundary; do not use all-whitespace trimming |
| 24 | `MachineName = @ResolvedMachineName` | CI_AS plus space padding | [PROPOSED] Windows machine names compare without case; preserve accent sensitivity. [PENDING] Whether trailing-space padding is intentionally retained for Windows names |
| 41 | `P.ServerCode = S.ServerCode` text join | CI_AS plus padding | [PROPOSED] Catalog code comparison is exact in the new system, intentionally different from legacy case/padding behavior |
| 44 | `S.MachineName = @ResolvedMachineName` | CI_AS plus padding | [PROPOSED]/[PENDING] Same Windows-name rule as line 24 |
| 64 | `PoolNameTemplate <> N'{HOST_NAME}'` | CI_AS plus padding: case-only and trailing-space-only variants compare equal | [PROPOSED] Preserve CI_AS+padding for this non-code template unless a later owner decision changes it |
| 72 | `GROUP BY PoolNameTemplate` | Grouping uses CI_AS text equality and SQL padding | [PROPOSED] Preserve case-insensitive, accent-sensitive, padded grouping for this non-code template |
| 100 | `NULLIF(CertificateSubjectTemplate,N'')` | Empty or ordinary-spaces-only becomes NULL; tab-only does not | [PROPOSED] Preserve exactly |
| 101 | `NULLIF(CertificateStoreName,'')` | Same padded-empty behavior | [PROPOSED] Preserve exactly |
| 111 | `I.ServerCode = S.ServerCode` join | CI_AS plus padding | [PROPOSED] Exact catalog-code comparison in the portable model |
| 114 | `S.MachineName = @ResolvedMachineName` | CI_AS plus padding | [PROPOSED]/[PENDING] Same Windows-name rule as line 24 |
| 115 | `NULLIF(I.IisIdentityPassword,N'')` | Legacy `nvarchar` empty test uses space padding | [PROPOSED] Credential package secret is opaque bytes; absence is determined by credential presence/empty-byte contract, not database collation |
| 122 | `LOWER(COALESCE(NULLIF(I.IisIdentityUserName,N''), P.PoolIdentityTemplate))` | `NULLIF` treats spaces-only username as empty; `LOWER` plus CI_AS makes account grouping case-insensitive | [PROPOSED] Windows account names compare without case. Preserve ordinary-space empty fallback. [PENDING] Accent/trailing-space normalization for account names beyond the explicit no-case rule |
| 126 | `I.ServerCode = S.ServerCode` join | CI_AS plus padding | [PROPOSED] Exact catalog code |
| 129 | `P.ServerCode = I.ServerCode` join | CI_AS plus padding | [PROPOSED] Exact catalog code |
| 132 | `S.MachineName = @ResolvedMachineName` | CI_AS plus padding | [PROPOSED]/[PENDING] Same Windows-name rule as line 24 |
| 133 | `NULLIF(I.IisIdentityPassword,N'') IS NOT NULL` | Legacy presence uses padded string equality | [PROPOSED] Portable presence is credential-package presence; do not reinterpret opaque secret bytes under CI_AS |
| 140 | `GROUP BY ServerCode, IdentityName` | `ServerCode` and identity text group under CI_AS/padding | [PROPOSED] ServerCode exact; Windows identity no-case. [PENDING] Accent/trailing-space dimension for Windows identity |
| 141 | `COUNT(DISTINCT IisIdentityPassword) > 1` | Legacy password `nvarchar` distinctness inherits CI_AS/padding, so case-only values can collapse | [PROPOSED] Intentionally change to exact secret-byte/fingerprint comparison because portable credentials are opaque bytes; `Secret` and `secret` are distinct secrets |

No `LIKE`, `IN`, `REPLACE`, `LTRIM/RTRIM`, or `LEN` operator occurs in this procedure. The matrix lists every text equality/inequality, text JOIN, `NULLIF`, `LOWER`, `GROUP BY` and `DISTINCT` operation that affects these predicates.

## `SERVER_NOT_REGISTERED`

**Verbatim T-SQL predicate:**

```sql
IF NOT EXISTS
(
    SELECT 1
    FROM dbo.ManagedServer
    WHERE IsEnabled = 1
      AND MachineName = @ResolvedMachineName
)
```

**SQLite inputs:** `dbo_ManagedServer(MachineName, IsEnabled)`.

**Original severity:** `ERROR`.

**Rule 6:** No instance-to-instance comparison. Report this machine-level error in the selected run and retain the machine name.

**Rule 7:** No filesystem path.

**Text comparison:** Matrix line 24.

**Tests:** Trigger: no enabled server matches. Non-trigger: enabled matching row. Boundary: case-only difference matches; accent-only difference does not; trailing-space behavior follows the `[PENDING]` Windows-name dimension.

## `ROOT_DEFINITION_COUNT`

**Verbatim T-SQL predicate:**

```sql
IF (SELECT COUNT(*) FROM cfg.IisApplicationDefinition WHERE IsEnabled = 1 AND IsSiteRoot = 1) <> 1
```

**SQLite inputs:** `cfg_IisApplicationDefinition(IsEnabled, IsSiteRoot)`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison.

**Rule 7:** No filesystem path.

**Text comparison:** None.

**Tests:** Trigger: zero roots. Non-trigger: exactly one. Boundary: two enabled roots fire; disabled roots do not count.

## `ROOT_POOL_NAME_INVALID`

**Verbatim T-SQL predicate:**

```sql
FROM cfg.IisApplicationDefinition
WHERE IsEnabled = 1
  AND IsSiteRoot = 1
  AND PoolNameTemplate <> N'{HOST_NAME}';
```

**SQLite inputs:** `cfg_IisApplicationDefinition(IisApplicationCode, IsEnabled, IsSiteRoot, PoolNameTemplate)`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison.

**Rule 7:** No filesystem path.

**Text comparison:** Matrix line 64.

**Tests:** Trigger: `{HOST_NAME}_ROOT`. Non-trigger: `{HOST_NAME}`. Boundaries: `{host_name}` and `{HOST_NAME} ` are legacy non-triggers under CI_AS+padding; accent-altered token fires.

## `DUPLICATE_POOL_TEMPLATE`

**Verbatim T-SQL predicate:**

```sql
FROM cfg.IisApplicationDefinition
WHERE IsEnabled = 1
GROUP BY PoolNameTemplate
HAVING COUNT(*) > 1;
```

**SQLite inputs:** `cfg_IisApplicationDefinition(PoolNameTemplate, IsEnabled)`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison.

**Rule 7:** No filesystem path.

**Text comparison:** Matrix line 72.

**Tests:** Trigger: same template twice. Non-trigger: distinct templates. Boundaries: case-only and trailing-space-only variants group; accent-only variants do not.

## `PRIMARY_BINDING_COUNT`

**Verbatim T-SQL predicate:**

```sql
IF (SELECT COUNT(*) FROM cfg.IisBindingDefinition WHERE IsEnabled = 1 AND IsPrimary = 1) <> 1
```

**SQLite inputs:** `cfg_IisBindingDefinition(IsEnabled, IsPrimary)`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison.

**Rule 7:** No filesystem path.

**Text comparison:** None.

**Tests:** Trigger: zero primary bindings. Non-trigger: one. Boundary: two enabled primary bindings fire.

## `CERTIFICATE_POLICY_MISSING`

**Verbatim T-SQL predicate:**

```sql
FROM cfg.IisServerPolicy AS P
WHERE P.IsEnabled = 1
  AND EXISTS
  (
      SELECT 1
      FROM cfg.IisBindingDefinition AS B
      WHERE B.IsEnabled = 1
        AND B.UseCertificate = 1
  )
  AND
  (
      NULLIF(P.CertificateSubjectTemplate, N'') IS NULL
      OR NULLIF(P.CertificateStoreName, '') IS NULL
  );
```

**SQLite inputs:** `cfg_IisServerPolicy(ServerCode, IsEnabled, CertificateSubjectTemplate, CertificateStoreName)` and `cfg_IisBindingDefinition(IsEnabled, UseCertificate)`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison.

**Rule 7:** No filesystem path.

**Text comparison:** Matrix lines 100-101.

**Tests:** Trigger: enabled certificate binding plus empty/spaces-only subject or store. Non-trigger: both substantive. Boundary: tab-only value is not empty.

## `IIS_IDENTITY_PASSWORD_CONFLICT`

**Verbatim T-SQL predicate:**

```sql
;WITH IdentityRows AS
(
    SELECT
        I.ServerCode,
        I.InstanceCode,
        IdentityName = LOWER(COALESCE(NULLIF(I.IisIdentityUserName, N''), P.PoolIdentityTemplate)),
        I.IisIdentityPassword
    FROM dbo.ManagedServer AS S
    INNER JOIN cfg.ManagedInstanceRuntime AS I
        ON I.ServerCode = S.ServerCode
       AND I.IsEnabled = 1
    INNER JOIN cfg.IisServerPolicy AS P
        ON P.ServerCode = I.ServerCode
       AND P.IsEnabled = 1
    WHERE S.IsEnabled = 1
      AND S.MachineName = @ResolvedMachineName
      AND NULLIF(I.IisIdentityPassword, N'') IS NOT NULL
)
INSERT INTO @Issues
SELECT
    'IIS_IDENTITY_PASSWORD_CONFLICT', 'ERROR', IdentityName,
    N'The same local IIS identity has different passwords across enabled instances on this server.'
FROM IdentityRows
GROUP BY ServerCode, IdentityName
HAVING COUNT(DISTINCT IisIdentityPassword) > 1;
```

**SQLite/credential inputs:** carried `dbo_ManagedInstance(ServerCode, InstanceCode, IisIdentityUserName, IsEnabled)`, `cfg_IisServerPolicy(ServerCode, PoolIdentityTemplate, IsEnabled)`, `dbo_ManagedServer(ServerCode, MachineName, IsEnabled)`, plus request credential `IIS_IDENTITY.<InstanceCode>`.

**Original severity:** `ERROR`.

**Rule 6:** Evaluate every enabled local-machine instance. Emit every conflicting identity group. If the selected instance participates, attach the issue to it; if a conflicting group contains only unselected enabled instances, fail the selected run with a global machine error. Missing credentials required for the comparison are `ERROR`, not silence.

**Rule 7:** No filesystem path.

**Text comparison:** Identity grouping follows matrix lines 122/140. Password distinctness deliberately follows the portable secret contract, not legacy database collation: compare exact secret bytes/fingerprints. `Secret` and `secret` are distinct.

**Tests:** Trigger: same Windows identity has two distinct exact secret values. Non-trigger: exact same secret bytes. Boundaries: identity case-only variant is the same account; secret case-only variant is a conflict; two unselected instances conflicting still produce a global machine error.

**Ambiguity:** Windows-account accent/trailing-space normalization remains `[PENDING]`; secret equality does not.

## Implementation stop points

The source collation and legacy view are known. Remaining `[PENDING]` dimensions concern Windows-name/account accent or trailing-space normalization where the permanent rule only fixes no-case comparison. Catalog codes are exact by owner decision. Portable secret comparison is explicitly exact-byte/fingerprint comparison because credentials are opaque values, not catalog text.
