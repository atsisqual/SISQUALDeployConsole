# DEPLOYMENT_PREFLIGHT predicates: IIS deployment

**Status:** [PROPOSED]
**Procedure:** `cfg.ReviewIisDeploymentModel`
**Verification base:** `main@28d4dc52c2d02bdce2add2101a306845041690b3`

## Evidence boundary

Predicates are copied from `docs/handoff/preflight-legacy-procedures.sql.txt`. The seven requested codes are the `cfg.ReviewIisDeploymentModel` rows still listed by `docs/handoff/preflight-port-gap.md` on read-only PR #69; `SERVER_POLICY_MISSING` and `IIS_IDENTITY_PASSWORD_PENDING` are outside this D13b set because the gap counts them as already ported.

SQLite table/column names were checked against `tests/Fixtures/carried-schema.json`. `cfg.ManagedInstanceRuntime` is a legacy view, not a carried table; its verbatim definition is now included in the evidence file. It projects carried `dbo.ManagedInstance` columns and decrypts `IIS_IDENTITY`, `WEB_ACCESS`, and `MOBILE_APP_TOKEN` credentials. In the portable system, the same metadata comes from `dbo_ManagedInstance` and secrets come from the request credential package, never from the catalog.

`docs/decisions-log.md` records that all source databases use `Latin1_General_CI_AS`: legacy comparisons without explicit `COLLATE` are case-insensitive and accent-sensitive. The same 2026-10-05 owner decision makes catalog codes exact in the new system. Non-code template comparisons below preserve the legacy CI_AS semantics unless another recorded owner rule overrides them.

The T-SQL evidence header also fixes ordinary-space behavior: equality pads strings with spaces, so `NULLIF(x,'')` returns `NULL` for a value made only of ordinary spaces. Tabs or other whitespace do not become empty merely because of this rule.

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

**Rule 6:** No instance-to-instance comparison. Report this machine-level registration failure in the selected run while retaining the machine name as the object/detail.

**Rule 7:** No filesystem path.

**Text comparison:** Legacy is CI_AS. Portable Windows machine-name comparison is case-insensitive by rule 7; preserve accent sensitivity to match the confirmed source semantics.

**Tests:** Trigger: no enabled server row matches. Non-trigger: enabled matching row. Boundary: case-only machine-name difference still matches; accent-only difference does not.

**Ambiguity:** None.

## `ROOT_DEFINITION_COUNT`

**Verbatim T-SQL predicate:**

```sql
IF (SELECT COUNT(*) FROM cfg.IisApplicationDefinition WHERE IsEnabled = 1 AND IsSiteRoot = 1) <> 1
```

**SQLite inputs:** `cfg_IisApplicationDefinition(IsEnabled, IsSiteRoot)`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison; global definition cardinality.

**Rule 7:** No filesystem path.

**Text comparison:** None.

**Tests:** Trigger: zero enabled roots. Non-trigger: exactly one. Boundary: two enabled roots fire; disabled roots do not count.

**Ambiguity:** None.

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

**Rule 7:** `PoolNameTemplate` is not a filesystem path.

**Text comparison:** `PoolNameTemplate` is non-code text. The original comparison is confirmed `Latin1_General_CI_AS`, so the port preserves CI_AS semantics here: case-insensitive and accent-sensitive. The owner exact-code decision does not apply to this template field.

**Tests:** Trigger: `{HOST_NAME}_ROOT`. Non-trigger: `{HOST_NAME}`. Boundary: `{host_name}` is also a non-trigger under CI_AS; an accent-altered token is not equal and fires.

**Ambiguity:** None after the recorded source-collation evidence.

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

**Rule 6:** No cross-instance comparison. This checks definition templates, not expanded per-instance pool names.

**Rule 7:** No filesystem path.

**Text comparison:** Legacy grouping is confirmed CI_AS. The port therefore groups `PoolNameTemplate` case-insensitively and accent-sensitively. A case-only pair is one duplicate group; an accent-only pair is distinct.

**Tests:** Trigger: two enabled rows with the same template. Non-trigger: unique templates. Boundaries: `{HOST_NAME}` plus `{host_name}` fires as a duplicate; accent-only difference does not group.

**Ambiguity:** None after the source-collation evidence.

## `PRIMARY_BINDING_COUNT`

**Verbatim T-SQL predicate:**

```sql
IF (SELECT COUNT(*) FROM cfg.IisBindingDefinition WHERE IsEnabled = 1 AND IsPrimary = 1) <> 1
```

**SQLite inputs:** `cfg_IisBindingDefinition(IsEnabled, IsPrimary)`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison; global binding-definition cardinality.

**Rule 7:** No filesystem path.

**Text comparison:** None.

**Tests:** Trigger: zero enabled primary bindings. Non-trigger: exactly one. Boundary: two enabled primary bindings fire; disabled primaries do not count.

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

**SQLite inputs:** `cfg_IisServerPolicy(ServerCode, IsEnabled, CertificateSubjectTemplate, CertificateStoreName)` and `cfg_IisBindingDefinition(IsEnabled, UseCertificate)`.

**Original severity:** `ERROR`.

**Rule 6:** No instance-to-instance comparison. If the local policy fires, report it in the selected run and retain `ServerCode` in details.

**Rule 7:** Certificate subject/store values are not filesystem paths.

**Text comparison:** The relevant SQL operation is padded `NULLIF(...,'')`. Empty **or ordinary-spaces-only** subject/store fires because SQL Server pads the comparison with spaces. A tab-only value does not become empty under this rule. Do not implement SQLite/.NET raw equality here.

**Tests:** Trigger: enabled certificate binding plus empty subject or store. Non-trigger: both fields non-empty. Boundaries: ordinary-spaces-only subject/store fires; tab-only text does not fire solely as empty.

**Ambiguity:** None.

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

**SQLite/credential inputs:** Reproduce `cfg.ManagedInstanceRuntime` from carried `dbo_ManagedInstance(ServerCode, InstanceCode, IisIdentityUserName, IsEnabled)` plus `cfg_IisServerPolicy(ServerCode, PoolIdentityTemplate, IsEnabled)` and `dbo_ManagedServer(ServerCode, MachineName, IsEnabled)`. `IisIdentityPassword` comes from request credential `IIS_IDENTITY.<InstanceCode>` for each enabled instance, matching the legacy view's decrypted `IIS_IDENTITY` credential.

**Original severity:** `ERROR`.

**Rule 6:** Yes, and the legacy scope is the **entire enabled local server**, not only selected participants. Build `IdentityRows` for every enabled local-machine instance. Report **every** identity group with more than one distinct password. If the selected instance participates in that group, attach the issue to the selected instance. If a conflicting group contains only unselected enabled instances, the selected run still fails with a **global machine error** for that identity; do not suppress it. Missing credentials needed for the comparison remain an `ERROR`, not silence.

This reporting rule is source fidelity plus rule 6, not a new owner policy: the original procedure emits the server-wide group regardless of selection, and selection does not exist in this SQL predicate.

**Rule 7:** No filesystem path.

**Text comparison:** Effective identity is explicitly `LOWER(...)` and source collation is CI_AS, so Windows identity grouping is case-insensitive and accent-sensitive. `ServerCode`/`InstanceCode` are catalog codes and are exact in the new system. Legacy `COUNT(DISTINCT IisIdentityPassword)` also follows CI_AS; the predicate specification therefore preserves that legacy equality for deciding whether passwords are distinct unless the owner later records an explicit security override.

**Tests:** Trigger: two enabled local instances share the same identity under CI_AS and have passwords that are distinct under CI_AS. Non-trigger: same identity and same password under CI_AS. Boundaries: (1) selected instance participates in a conflict with an unselected instance -> selected-instance error; (2) two unselected instances conflict while selected instance uses another identity -> global machine error still emitted; (3) identity differs only by case -> same group; (4) passwords differing only by case are not distinct under legacy CI_AS; an accent-only password difference is distinct.

**Ambiguity:** None for legacy predicate/reporting. A future owner security override could intentionally make secret comparison byte-exact, but no such override is assumed here.

## Implementation stop points

This document specifies only the seven codes listed by the port gap. The newly supplied `cfg.ManagedInstanceRuntime` view removes the previous schema blocker: metadata comes from carried `dbo_ManagedInstance`, while `IIS_IDENTITY` passwords come from the request credential package. Source collation is confirmed CI_AS; catalog codes remain exact by owner decision, and non-code template comparisons preserve CI_AS in this specification.
