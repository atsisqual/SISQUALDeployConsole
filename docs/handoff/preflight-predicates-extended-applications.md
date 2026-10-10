# DEPLOYMENT_PREFLIGHT predicates: Extended applications

**Status:** [PROPOSED]
**Procedure:** `cfg.ReviewExtendedApplicationModel`
**Verification base:** procedure/view evidence from current `main`; port-gap evidence copied from read-only PR #69 head `bcd9a1d8ff71afbb9804dd042c7407b75e4a7b69`.

## Evidence boundary

The predicate source is `docs/handoff/preflight-legacy-procedures.sql.txt`. Its header records the T-SQL comparison rules used below and current `main` contains the verbatim `cfg.IisServiceAutoStartProviderCatalog` view consumed by this procedure. The requested port set and rules 6 and 7 come from `docs/handoff/preflight-port-gap.md` on read-only PR #69; because #69 is still open, the exact rule text needed by this specification is reproduced below instead of requiring an unavailable file in this branch.

SQLite table/column names were checked against `tests/Fixtures/carried-schema.json`. SQL Server table names map to SQLite by replacing the schema separator with `_`.

`docs/decisions-log.md` records the 2026-10-05 owner decision that every source database uses `Latin1_General_CI_AS`, that stored text is not case-normalized, and that catalog codes in the new system compare exactly. Legacy text comparison is therefore case-insensitive and accent-sensitive. SQL Server equality also pads ordinary spaces; `LEN` ignores trailing ordinary spaces; one-argument `LTRIM`/`RTRIM` remove ordinary spaces only; and `NULLIF(x,'')` therefore returns NULL for ordinary-spaces-only values.

### Exact dependent view evidence

Current `main` appends this verbatim view to `docs/handoff/preflight-legacy-procedures.sql.txt`:

```sql
CREATE OR ALTER VIEW cfg.IisServiceAutoStartProviderCatalog
AS
SELECT DISTINCT
    S.ServerCode,
    S.MachineName,
    I.InstanceCode,
    SiteName = I.HostName,
    ProviderCode = P.ProviderName,
    ProviderName =
        CONVERT
        (
            nvarchar(255),
            REPLACE
            (
                REPLACE
                (
                    REPLACE
                    (
                        P.ProviderNameTemplate,
                        N'{INSTANCE_CODE}',
                        I.InstanceCode
                    ),
                    N'{HOST_NAME}',
                    I.HostName
                ),
                N'{HOST_NAME_SAFE}',
                REPLACE(I.HostName, N'.', N'_')
            )
        ),
    P.ProviderType,
    P.IsRequired,
    P.SortOrder,
    P.IsEnabled
FROM dbo.ManagedServer AS S
INNER JOIN dbo.ManagedInstance AS I
    ON I.ServerCode = S.ServerCode
   AND I.IsEnabled = 1
INNER JOIN cfg.IisApplicationAutoStartDefinition AS D
    ON D.IsEnabled = 1
   AND D.ServiceAutoStartEnabled = 1
INNER JOIN cfg.IisServiceAutoStartProviderDefinition AS P
    ON P.ProviderName = D.ServiceAutoStartProvider
   AND P.IsEnabled = 1
WHERE S.IsEnabled = 1;
```

The view is derived only from carried `dbo.ManagedServer`, `dbo.ManagedInstance`, `cfg.IisApplicationAutoStartDefinition`, and `cfg.IisServiceAutoStartProviderDefinition`. `ProviderCode = P.ProviderName`; `ProviderName` is produced by the nested `REPLACE` calls above.

### Rules 6 and 7 copied from PR #69

The following is the implementation guidance this document consumed from PR #69 head `bcd9a1d8ff71afbb9804dd042c7407b75e4a7b69`:

- **Rule 6 / cross-instance:** when a check requires two things to differ, compare against every enabled instance of the machine and report on the selected participant; credentials of other instances come from the request and missing required credentials are an error. **[PENDING]** This scope expansion is recorded porting guidance, not an owner-approved decision; where it changes an original selected-instance predicate, the final scope remains pending owner decision.
- **Rule 7 / containment:** resolve catalog-derived paths through junctions/symbolic links and require the resolved path to remain under its approved root before probing it; unreadable paths are item errors, Windows names compare without case, catalog codes exactly.

No write is made to PR #69 by this specification.

### Complete text-operator matrix

Line numbers below are relative to the first `CREATE OR ALTER PROCEDURE` line of `cfg.ReviewExtendedApplicationModel`; rows prefixed `view` are relative to the first line of the verbatim `cfg.IisServiceAutoStartProviderCatalog` view. This matrix is the comparison contract for the later port: an implementation must not fall back to SQLite/.NET defaults silently.

| Source line | Operator / expression | Legacy T-SQL behavior | Portable behavior |
|---|---|---|---|
| proc 23 | `NULLIF(LTRIM(RTRIM(ProviderType)), N'')` | `LTRIM`/`RTRIM` remove ordinary spaces only; padded equality makes ordinary-spaces-only equal to empty; tabs are not trimmed | [PROPOSED] Preserve exactly; do not use all-whitespace `.Trim()` |
| proc 33 | `NULLIF(LTRIM(RTRIM(ProviderNameTemplate)), N'')` | Same ordinary-space trim and padded-empty behavior | [PROPOSED] Preserve exactly; tab-only template is non-empty |
| proc 43 | `P.ProviderName = D.ServiceAutoStartProvider` | CI_AS plus SQL equality padding: case-only and trailing-space-only variants compare equal; accent variants do not | [PENDING] Decide whether this non-code provider identifier keeps CI_AS+padding or deliberately becomes exact; tests cover case, accent and trailing-space variants |
| proc 56 | `C.MachineName = @MachineName` | CI_AS plus equality padding | [PENDING] Rule 7 fixes case-insensitive Windows-name comparison; decide whether accent sensitivity and trailing-space padding are also preserved |
| proc 59 | `NULLIF(LTRIM(RTRIM(C.ProviderName)), N'')` | Ordinary-space trim, then padded empty comparison | [PROPOSED] Preserve exactly; tab-only name is not empty |
| proc 60 | `LEN(C.ProviderName) > 80` | `LEN` ignores trailing ordinary spaces | [PROPOSED] Preserve SQL `LEN`; 80 non-space chars plus trailing spaces remain length 80 |
| proc 70 | `C.MachineName = @MachineName` | CI_AS plus equality padding | [PENDING] Same Windows-name decision as proc 56 |
| proc 71 | `GROUP BY C.ProviderName` | Text grouping follows CI_AS; case-only and trailing-space-only variants group together; accent variants remain distinct | [PENDING] Decide whether portable non-code provider grouping preserves CI_AS+padding or becomes exact |
| proc 82 | `A.IisApplicationCode = D.IisApplicationCode` join | Legacy CI_AS plus equality padding | [PROPOSED] Apply the recorded new-system rule: catalog codes compare exact, intentionally differing from legacy case/padding behavior |
| proc 85 | `A.PoolStartMode <> 'AlwaysRunning'` | CI_AS and padded comparison; `alwaysrunning` and `AlwaysRunning ` compare equal to the literal | [PENDING] Decide whether this non-code enum preserves CI_AS+padding or becomes exact |
| proc 95 | `S.ServerCode = I.ServerCode` join | Legacy CI_AS plus padding | [PROPOSED] Catalog code is exact in the new system |
| proc 101 | `C.InstanceCode = I.InstanceCode` join | Legacy CI_AS plus padding | [PROPOSED] Catalog code is exact in the new system |
| proc 102 | `C.ProviderCode = D.ServiceAutoStartProvider` join | `ProviderCode` is `P.ProviderName`; CI_AS plus padding | [PENDING] Same non-code provider-identifier decision as proc 43 |
| proc 104 | `S.MachineName = @MachineName` | CI_AS plus padding | [PENDING] Same Windows-name decision as proc 56 |
| proc 114 | `C.MachineName = @MachineName` | CI_AS plus padding | [PENDING] Same Windows-name decision as proc 56 |
| proc 120 | `RuleCode = 'WFM_PROCESS_USE_HANGFIRE'` | Legacy CI_AS plus padding | [PROPOSED] Catalog code is exact in the new system; case/trailing-space variants do not satisfy the portable check |
| proc 136 | `RuleCode = 'WFM_PROCESS_OWIN_AUTOSTART'` | Legacy CI_AS plus padding | [PROPOSED] Catalog code is exact in the new system |
| view 3 | `SELECT DISTINCT ...` | DISTINCT uses the source collation for text columns and SQL string equality semantics | [PENDING] Exact catalog-code columns stay exact; non-code provider/name fields need the same approved CI_AS+padding policy as the comparisons above before portable de-duplication is defined |
| view 13-27 | nested `REPLACE` for `{INSTANCE_CODE}`, `{HOST_NAME}`, `{HOST_NAME_SAFE}` and `REPLACE(HostName,'.','_')` | `REPLACE` matches text under `Latin1_General_CI_AS`: token case is ignored, accents remain significant | [PENDING] Portable replacement semantics must be chosen explicitly; ordinary .NET/SQLite case-sensitive replacement is not source-equivalent. Boundary: `{instance_code}` is replaced by the legacy view |
| view 36 | `I.ServerCode = S.ServerCode` join | Legacy CI_AS plus padding | [PROPOSED] Catalog code exact in portable model |
| view 42 | `P.ProviderName = D.ServiceAutoStartProvider` join | CI_AS plus padding | [PENDING] Same non-code provider-identifier decision as proc 43 |

## `AUTO_START_PROVIDER_TYPE_MISSING`

**Verbatim T-SQL predicate:**

```sql
FROM cfg.IisServiceAutoStartProviderDefinition
WHERE IsEnabled = 1
  AND NULLIF(LTRIM(RTRIM(ProviderType)), N'') IS NULL;
```

**SQLite inputs:** `cfg_IisServiceAutoStartProviderDefinition(ProviderName, ProviderType, IsEnabled)`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison. This is a global definition check; report it for the selected instance whose deployment consumes the definition.

**Rule 7:** No catalog filesystem path.

**Text comparison:** See proc 23 in the matrix.

**Tests:** Trigger: enabled row with `ProviderType = '   '`. Non-trigger: enabled nonblank value. Boundary: enabled tab-only `ProviderType` does not trigger; disabled spaces-only row does not trigger.

**Ambiguity:** None in the predicate.

## `AUTO_START_PROVIDER_TEMPLATE_MISSING`

**Verbatim T-SQL predicate:**

```sql
FROM cfg.IisServiceAutoStartProviderDefinition
WHERE IsEnabled = 1
  AND NULLIF(LTRIM(RTRIM(ProviderNameTemplate)), N'') IS NULL;
```

**SQLite inputs:** `cfg_IisServiceAutoStartProviderDefinition(ProviderName, ProviderNameTemplate, IsEnabled)`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison.

**Rule 7:** No catalog filesystem path.

**Text comparison:** See proc 33.

**Tests:** Trigger: enabled row whose template contains only ordinary spaces. Non-trigger: enabled nonblank template. Boundary: tab-only template does not trigger.

**Ambiguity:** None.

## `AUTO_START_PROVIDER_NOT_ENABLED`

**Verbatim T-SQL predicate:**

```sql
FROM cfg.IisApplicationAutoStartDefinition AS D
LEFT JOIN cfg.IisServiceAutoStartProviderDefinition AS P
    ON P.ProviderName = D.ServiceAutoStartProvider
   AND P.IsEnabled = 1
WHERE D.IsEnabled = 1
  AND D.ServiceAutoStartEnabled = 1
  AND P.ProviderName IS NULL;
```

**SQLite inputs:** `cfg_IisApplicationAutoStartDefinition(IisApplicationCode, ServiceAutoStartProvider, ServiceAutoStartEnabled, IsEnabled)` and `cfg_IisServiceAutoStartProviderDefinition(ProviderName, IsEnabled)`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison.

**Rule 7:** No catalog filesystem path.

**Text comparison:** See proc 43. The portable policy for this non-code identifier remains `[PENDING]`; it must cover case, accents and SQL trailing-space padding together.

**Tests:** Trigger: enabled definition references a missing/disabled provider. Non-trigger: matching enabled provider. Boundaries: `ProviderA` vs `providera`, `ProviderA` vs an accent-altered spelling, and `ProviderA` vs `ProviderA `.

**Ambiguity:** Portable provider-identifier comparison policy only.

## `AUTO_START_PROVIDER_EXPANDED_NAME_INVALID`

**Verbatim T-SQL predicate:**

```sql
FROM cfg.IisServiceAutoStartProviderCatalog AS C
WHERE (@MachineName IS NULL OR C.MachineName = @MachineName)
  AND
  (
      NULLIF(LTRIM(RTRIM(C.ProviderName)), N'') IS NULL
      OR LEN(C.ProviderName) > 80
  );
```

**SQLite inputs:** Recreate the legacy view from carried `dbo_ManagedServer(ServerCode, MachineName, IsEnabled)`, `dbo_ManagedInstance(InstanceCode, ServerCode, HostName, IsEnabled)`, `cfg_IisApplicationAutoStartDefinition(ServiceAutoStartProvider, ServiceAutoStartEnabled, IsEnabled)`, and `cfg_IisServiceAutoStartProviderDefinition(ProviderName, ProviderNameTemplate, ProviderType, IsRequired, SortOrder, IsEnabled)`.

**Original severity:** `ERROR`.

**Rule 6:** Per-row validation, not a conflict check. Report on the selected instance only when its derived provider row is invalid.

**Rule 7:** No filesystem path.

**Text comparison:** See proc 56, 59 and 60 plus view 13-27. The view token replacement itself is `[PENDING]` and must not silently use case-sensitive `.Replace`/SQLite `replace()`.

**Tests:** Trigger: selected instance derives spaces-only provider name or SQL `LEN` 81. Non-trigger: substantive name with SQL `LEN <= 80`. Boundaries: tab-only name is non-empty; 80 non-space characters plus trailing spaces do not trigger; `{instance_code}` in the template is replaced by the legacy view and is a required boundary for the portable replacement decision.

**Ambiguity:** Portable Windows-name accent/padding behavior and view replacement behavior are `[PENDING]`.

## `AUTO_START_PROVIDER_EXPANDED_NAME_DUPLICATE`

**Verbatim T-SQL predicate:**

```sql
FROM cfg.IisServiceAutoStartProviderCatalog AS C
WHERE (@MachineName IS NULL OR C.MachineName = @MachineName)
GROUP BY C.ProviderName
HAVING COUNT(*) > 1;
```

**SQLite inputs:** Same exact carried-table recreation of `cfg.IisServiceAutoStartProviderCatalog`.

**Original severity:** `ERROR`.

**Rule 6:** **[PENDING]** PR #69 proposes comparing duplicates across every enabled instance of the local machine and reporting on the selected participant, including a conflict with an unselected enabled instance. The source procedure itself is machine-filtered but not selected-instance-filtered; the portable reporting/scope rule is not an owner-approved decision and must remain pending until the owner decides it.

**Rule 7:** No filesystem path.

**Text comparison:** See proc 70-71. Legacy duplicate groups are CI_AS and use SQL text equality semantics, including trailing-space equivalence. Portable non-code grouping is `[PENDING]`.

**Tests:** Trigger: two enabled local-machine rows derive the same group. Non-trigger: unique groups. Boundary for the pending reporting rule: run for one selected instance when its duplicate is unselected; do not freeze the expected reporting outcome until Rule 6 is approved or rejected. Case-only and trailing-space-only names group in legacy; accent-only names do not.

**Ambiguity:** Portable provider-name grouping policy and Rule-6 reporting/scope policy.

## `AUTO_START_POOL_NOT_ALWAYS_RUNNING`

**Verbatim T-SQL predicate:**

```sql
FROM cfg.IisApplicationAutoStartDefinition AS D
INNER JOIN cfg.IisApplicationDefinition AS A
    ON A.IisApplicationCode = D.IisApplicationCode
WHERE D.IsEnabled = 1
  AND D.ServiceAutoStartEnabled = 1
  AND A.PoolStartMode <> 'AlwaysRunning';
```

**SQLite inputs:** `cfg_IisApplicationAutoStartDefinition(IisApplicationCode, ServiceAutoStartEnabled, IsEnabled)` and `cfg_IisApplicationDefinition(IisApplicationCode, PoolStartMode)`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison.

**Rule 7:** No filesystem path.

**Text comparison:** See proc 82 and 85. Application codes are exact by owner decision; non-code `PoolStartMode` CI_AS+padding behavior remains `[PENDING]` for the portable port.

**Tests:** Trigger: `OnDemand`. Non-trigger: `AlwaysRunning`. Boundaries: `alwaysrunning` and `AlwaysRunning ` are legacy non-triggers; portable expectation waits for the enum policy.

**Ambiguity:** Portable enum comparison policy only.

## `AUTO_START_APPLICATION_PROVIDER_NOT_EXPANDED`

**Verbatim T-SQL predicate:**

```sql
FROM dbo.ManagedInstance AS I
INNER JOIN dbo.ManagedServer AS S
    ON S.ServerCode = I.ServerCode
   AND S.IsEnabled = 1
INNER JOIN cfg.IisApplicationAutoStartDefinition AS D
    ON D.IsEnabled = 1
   AND D.ServiceAutoStartEnabled = 1
LEFT JOIN cfg.IisServiceAutoStartProviderCatalog AS C
    ON C.InstanceCode = I.InstanceCode
   AND C.ProviderCode = D.ServiceAutoStartProvider
WHERE I.IsEnabled = 1
  AND (@MachineName IS NULL OR S.MachineName = @MachineName)
  AND C.ProviderName IS NULL;
```

**SQLite inputs:** `dbo_ManagedInstance`, `dbo_ManagedServer`, `cfg_IisApplicationAutoStartDefinition`, plus the exact derived provider-catalog view.

**Original severity:** `ERROR`.

**Rule 6:** The source enumerates all enabled instances but does not compare instance values. In a selected-instance run, evaluate/report the selected instance row; the full enabled set is still used to recreate the view.

**Rule 7:** No filesystem path.

**Text comparison:** See proc 95, 101, 102, 104 and view 13-27/42. Catalog codes are exact by owner decision; provider identifiers and replacement behavior remain `[PENDING]`; Windows-name case is insensitive and accent/padding dimensions remain `[PENDING]`.

**Tests:** Trigger: selected instance plus enabled auto-start definition has no matching derived provider row. Non-trigger: matching row exists. Boundaries include provider case/accent/trailing-space variants and case-variant view tokens.

**Ambiguity:** Portable provider/replacement and Windows-name accent/padding policies only.

## `AUTO_START_ASSEMBLY_LOADABILITY`

**Verbatim T-SQL predicate:**

```sql
FROM cfg.IisServiceAutoStartProviderCatalog AS C
WHERE (@MachineName IS NULL OR C.MachineName = @MachineName);
```

**SQLite inputs:** Exact recreation of the legacy provider-catalog view.

**Original severity:** `WARNING`.

**Rule 6:** No cross-instance comparison. Report only selected-instance view rows; do not invent an assembly probe.

**Rule 7:** No filesystem path.

**Text comparison:** See proc 114 and the view rows in the matrix.

**Tests:** Trigger: selected instance has a derived provider row. Non-trigger: it has none. Boundary: only another enabled instance has rows; selected instance receives no warning.

**Ambiguity:** Windows-name accent/padding and view replacement policy only. The T-SQL performs no loadability test.

## `PROCESS_HANGFIRE_RULE_MISSING`

**Verbatim T-SQL predicate:**

```sql
IF NOT EXISTS
(
    SELECT 1
    FROM cfg.ConfigRule
    WHERE RuleCode = 'WFM_PROCESS_USE_HANGFIRE'
      AND IsEnabled = 1
)
```

**SQLite inputs:** `cfg_ConfigRule(RuleCode, IsEnabled)`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison.

**Rule 7:** No filesystem path.

**Text comparison:** See proc 120. Portable catalog-code comparison is exact by the recorded owner decision.

**Tests:** Trigger: exact enabled row absent. Non-trigger: exact enabled row exists. Boundary: case-only or trailing-space code variant does not satisfy the portable exact-code check even though legacy CI_AS/padding could have matched.

**Ambiguity:** None after the exact-code decision.

## `PROCESS_OWIN_RULE_MISSING`

**Verbatim T-SQL predicate:**

```sql
IF NOT EXISTS
(
    SELECT 1
    FROM cfg.ConfigRule
    WHERE RuleCode = 'WFM_PROCESS_OWIN_AUTOSTART'
      AND IsEnabled = 1
)
```

**SQLite inputs:** `cfg_ConfigRule(RuleCode, IsEnabled)`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison.

**Rule 7:** No filesystem path.

**Text comparison:** See proc 136. Portable catalog-code comparison is exact.

**Tests:** Trigger: exact enabled row absent. Non-trigger: exact enabled row exists. Boundary: case-only/trailing-space variant does not satisfy portable exact code.

**Ambiguity:** None after the exact-code decision.

## Implementation stop points

The provider-catalog view definition and T-SQL semantics are now self-contained in this specification from current `main`. The exact Rule 6/7 guidance consumed from PR #69 is also reproduced above so implementation does not depend on an unavailable file in this branch. Remaining `[PENDING]` items are portable comparison-policy decisions plus the owner decision on Rule 6 scope/reporting. Catalog codes are already exact by owner decision. No predicate may be reconstructed from the issue-code name.