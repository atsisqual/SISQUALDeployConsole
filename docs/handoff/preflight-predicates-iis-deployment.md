# DEPLOYMENT_PREFLIGHT predicates: IIS deployment

**Status:** [PROPOSED]
**Procedure:** `cfg.ReviewIisDeploymentModel`
**Verification base:** `main@a32141cbec584d349f1591a4aa5a801137463278`

## Evidence boundary

Predicates are copied from `docs/handoff/preflight-legacy-procedures.sql.txt`. The seven requested codes are the `cfg.ReviewIisDeploymentModel` rows still listed by `docs/handoff/preflight-port-gap.md` on read-only PR #69 head `80240090ba5dc37e13a64d359f9378a1c033fcc4`; `SERVER_POLICY_MISSING` and `IIS_IDENTITY_PASSWORD_PENDING` are outside this D13b set because that gap says they are already ported.

SQLite table/column names were checked against `tests/Fixtures/carried-schema.json` at the verification base. SQL Server table names map to SQLite with `_` between schema and object name. `cfg.ManagedInstanceRuntime` is not a carried table; the portable catalog carries `dbo_ManagedInstance.IisIdentityUserName`, while passwords are external credentials.

`tests/Fixtures/preflight-legacy-codes.json` is not present in this `main` tree. Each severity below is the literal severity emitted by the extracted procedure and agrees with the seven-code table in `preflight-port-gap.md`.

### Text comparison policy

The legacy procedure has no `COLLATE`; source database collation is not stated. Portable rule 7 makes catalog codes exact and Windows names case-insensitive. Empty-string tests are collation-independent. Template and non-code text comparisons whose case behavior is not fixed by those rules are marked `[PENDING]`. Secret comparison is called out separately under the conflict predicate.

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

**SQLite inputs:** `dbo_ManagedServer(MachineName, IsEnabled)`, confirmed in `carried-schema.json`.

**Original severity:** `ERROR`.

**Rule 6:** No instance-to-instance comparison. When a preflight request is for one selected instance, report this machine-registration failure on the selected instance and retain the machine name in details/object data.

**Rule 7:** No filesystem path is used.

**Text comparison:** `MachineName` is a Windows machine name, so portable behavior is case-insensitive as required by rule 7.

**Tests:** Trigger: no enabled server row matches the local machine. Non-trigger: enabled matching row exists. Boundary: a matching machine name with different letter case still counts as registered.

**Ambiguity:** None after applying the explicit Windows-name rule.

## `ROOT_DEFINITION_COUNT`

**Verbatim T-SQL predicate:**

```sql
IF (SELECT COUNT(*) FROM cfg.IisApplicationDefinition WHERE IsEnabled = 1 AND IsSiteRoot = 1) <> 1
```

**SQLite inputs:** `cfg_IisApplicationDefinition(IsEnabled, IsSiteRoot)`, confirmed in `carried-schema.json`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison; this is a global definition cardinality check. Report on the selected instance because its IIS layout depends on the definition set.

**Rule 7:** No filesystem path is used.

**Text comparison:** None.

**Tests:** Trigger: zero enabled roots. Non-trigger: exactly one enabled root. Boundary: two enabled roots must fire; disabled root rows do not affect the count.

**Ambiguity:** None.

## `ROOT_POOL_NAME_INVALID`

**Verbatim T-SQL predicate:**

```sql
FROM cfg.IisApplicationDefinition
WHERE IsEnabled = 1
  AND IsSiteRoot = 1
  AND PoolNameTemplate <> N'{HOST_NAME}';
```

**SQLite inputs:** `cfg_IisApplicationDefinition(IisApplicationCode, IsEnabled, IsSiteRoot, PoolNameTemplate)`, confirmed in `carried-schema.json`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison. Report on the selected instance when its root definition violates the required template.

**Rule 7:** `PoolNameTemplate` is an IIS pool-name template, not a filesystem path.

**Text comparison:** The legacy `<> N'{HOST_NAME}'` comparison follows unknown database collation. `PoolNameTemplate` is not a catalog code. **[PENDING]** Decide whether a case-only token such as `{host_name}` is accepted. Do not infer case sensitivity from the issue-code name.

**Tests:** Trigger: enabled root with `{HOST_NAME}_ROOT`. Non-trigger: exact `{HOST_NAME}`. Boundary: `{host_name}`; expected result remains **[PENDING]** the template-case decision.

**Ambiguity:** Case-only template behavior.

## `DUPLICATE_POOL_TEMPLATE`

**Verbatim T-SQL predicate:**

```sql
FROM cfg.IisApplicationDefinition
WHERE IsEnabled = 1
GROUP BY PoolNameTemplate
HAVING COUNT(*) > 1;
```

**SQLite inputs:** `cfg_IisApplicationDefinition(PoolNameTemplate, IsEnabled)`, confirmed in `carried-schema.json`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison. This checks definition templates, not expanded per-instance pool names. Report the global definition defect on the selected instance whose deployment uses the duplicated template.

**Rule 7:** No filesystem path is used.

**Text comparison:** `GROUP BY PoolNameTemplate` inherits unknown legacy collation. The field is template text, not a catalog code. **[PENDING]** Decide whether templates differing only by case are one duplicate group.

**Tests:** Trigger: two enabled application definitions with exactly the same `PoolNameTemplate`. Non-trigger: unique templates. Boundary: two templates differ only by case; expected result is **[PENDING]** the template-case decision.

**Ambiguity:** Case-only grouping only.

## `PRIMARY_BINDING_COUNT`

**Verbatim T-SQL predicate:**

```sql
IF (SELECT COUNT(*) FROM cfg.IisBindingDefinition WHERE IsEnabled = 1 AND IsPrimary = 1) <> 1
```

**SQLite inputs:** `cfg_IisBindingDefinition(IsEnabled, IsPrimary)`, confirmed in `carried-schema.json`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison; global binding-definition cardinality. Report on the selected instance whose site would consume the definition.

**Rule 7:** No filesystem path is used.

**Text comparison:** None.

**Tests:** Trigger: no enabled primary binding. Non-trigger: exactly one. Boundary: two enabled primary bindings fire; disabled primaries do not count.

**Ambiguity:** None.

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

**SQLite inputs:** `cfg_IisServerPolicy(ServerCode, IsEnabled, CertificateSubjectTemplate, CertificateStoreName)` and `cfg_IisBindingDefinition(IsEnabled, UseCertificate)`, all confirmed in `carried-schema.json`.

**Original severity:** `ERROR`.

**Rule 6:** No instance-to-instance comparison. The legacy statement evaluates enabled server policies when any enabled certificate binding exists. The portable machine catalog is already server-scoped; if the local policy fires, report it on the selected instance while retaining `ServerCode` in details.

**Rule 7:** Certificate subject/store values are not filesystem paths.

**Text comparison:** The only text operation is `NULLIF(..., '')`; it tests empty versus non-empty and does not depend on letter case. Preserve it exactly: whitespace-only is not the same as empty because the source does not trim these two fields.

**Tests:** Trigger: certificate binding enabled and local enabled policy has empty subject or store. Non-trigger: certificate binding enabled and both are non-empty. Boundary: whitespace-only subject/store is non-empty in the original predicate and must not fire solely for whitespace.

**Ambiguity:** None in the predicate. Do not add trimming that the source does not contain.

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

**SQLite inputs:** `dbo_ManagedServer(ServerCode, MachineName, IsEnabled)`, `dbo_ManagedInstance(ServerCode, InstanceCode, IisIdentityUserName, IsEnabled)`, and `cfg_IisServerPolicy(ServerCode, PoolIdentityTemplate, IsEnabled)` exist in `carried-schema.json`. There is no carried `cfg_ManagedInstanceRuntime` and no carried `IisIdentityPassword`; portable passwords must come from the request credential package as `IIS_IDENTITY.<InstanceCode>` rather than from the catalog.

**Original severity:** `ERROR`.

**Rule 6:** Yes, explicitly. Build `IdentityRows` from **every enabled instance of the local machine**, including unselected instances. Resolve each effective identity from `IisIdentityUserName` or the server policy template, and obtain every required instance password from the request credential package. If another enabled instance needed for the comparison has no credential, rule 6 says return an `ERROR`, not silence. Report `IIS_IDENTITY_PASSWORD_CONFLICT` on the selected instance when that selected instance participates in an identity group containing more than one distinct password.

**Rule 7:** No filesystem path is used.

**Text comparison:** `LOWER(...)` makes the legacy identity grouping explicitly case-insensitive; portable behavior also compares Windows account names without case, so preserve that. `ServerCode` and `InstanceCode` are catalog codes and remain exact. Passwords are authentication secrets: portable comparison should be exact secret-value comparison so credentials that differ only by case are still different passwords. This follows the rule-6 intent of one account having one password and avoids applying catalog collation semantics to an external secret.

**Tests:** Trigger: selected instance and an enabled unselected instance use the same identity name (including a case-only name variation) but different exact password values. Non-trigger: same identity and same exact password across all enabled instances. Boundary: passwords differ only by letter case; portable behavior treats them as distinct and fires. Also include the required rule-6 case where the conflicting instance is not selected.

**Ambiguity:** The legacy `COUNT(DISTINCT nvarchar-password)` technically follows the unknown source collation, so a case-insensitive database may have collapsed case-only password differences. The portable choice above preserves authentication semantics and the explicit rule-6 wording rather than the unknown database collation. If the owner requires byte-for-byte legacy collation behavior for secrets, that would need an explicit override; no such decision is present in the supplied sources.

## Implementation stop points

This document specifies only the seven codes listed by the port gap. It deliberately does not redefine the two IIS review codes already counted as ported. `cfg.ManagedInstanceRuntime` must not be recreated as a secret-bearing catalog surface; the password-conflict check uses carried identity metadata plus request credentials for all enabled instances.
