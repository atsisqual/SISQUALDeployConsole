# DEPLOYMENT_PREFLIGHT predicates: Extended applications

**Status:** [PROPOSED]
**Procedure:** `cfg.ReviewExtendedApplicationModel`
**Verification base:** `main@28d4dc52c2d02bdce2add2101a306845041690b3`

## Evidence boundary

The predicate source is `docs/handoff/preflight-legacy-procedures.sql.txt` at the verification base. Its header records the exact T-SQL comparison semantics and includes the verbatim `cfg.IisServiceAutoStartProviderCatalog` view used by this procedure. The requested port set and rules 6 and 7 come from `docs/handoff/preflight-port-gap.md` on read-only PR #69.

SQLite table/column names below were checked against `tests/Fixtures/carried-schema.json`. SQL Server table names map to SQLite by replacing the schema separator with `_`, for example `cfg.IisApplicationDefinition` -> `cfg_IisApplicationDefinition`.

`docs/decisions-log.md` records the 2026-10-05 owner decision that every source database uses `Latin1_General_CI_AS`, that stored text is not case-normalized, and that catalog codes in the new system compare exactly. Therefore the legacy source behavior is known: case-insensitive and accent-sensitive. For non-code provider names, enum/template values, and Windows-name accent handling, the portable behavior is still `[PENDING]` unless an owner rule below fixes it. Catalog codes are exact by decision even where this intentionally differs from legacy CI_AS equality.

The T-SQL header also fixes these boundaries: equality pads ordinary spaces; `NULLIF(x,'')` therefore treats a spaces-only value as empty; `LEN` ignores trailing ordinary spaces; one-argument `LTRIM`/`RTRIM` remove ordinary spaces only, not tabs or other whitespace.

The legacy `cfg.IisServiceAutoStartProviderCatalog` is not a carried table, but it is no longer a blocker. Its exact view definition derives from carried `dbo.ManagedServer`, `dbo.ManagedInstance`, `cfg.IisApplicationAutoStartDefinition`, and `cfg.IisServiceAutoStartProviderDefinition`. It exposes `ProviderCode = P.ProviderName` and derives `ProviderName` by replacing `{INSTANCE_CODE}`, `{HOST_NAME}`, and `{HOST_NAME_SAFE}` in `ProviderNameTemplate`, with `{HOST_NAME_SAFE}` equal to `HostName` with `.` replaced by `_`.

## `AUTO_START_PROVIDER_TYPE_MISSING`

**Verbatim T-SQL predicate:**

```sql
FROM cfg.IisServiceAutoStartProviderDefinition
WHERE IsEnabled = 1
  AND NULLIF(LTRIM(RTRIM(ProviderType)), N'') IS NULL;
```

**SQLite inputs:** `cfg_IisServiceAutoStartProviderDefinition(ProviderName, ProviderType, IsEnabled)`. All exist.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison. This is a global definition check; report it for the selected instance whose deployment consumes the definition.

**Rule 7:** No catalog filesystem path.

**Text comparison:** The source trigger is ordinary-spaces trim plus SQL padded `NULLIF`. No collation decision is needed for this emptiness predicate.

**Tests:** Trigger: enabled row with `ProviderType = '   '`. Non-trigger: enabled nonblank value. Boundary: enabled `ProviderType` containing only a tab does **not** trigger; disabled spaces-only row does not trigger.

**Ambiguity:** None in the predicate.

## `AUTO_START_PROVIDER_TEMPLATE_MISSING`

**Verbatim T-SQL predicate:**

```sql
FROM cfg.IisServiceAutoStartProviderDefinition
WHERE IsEnabled = 1
  AND NULLIF(LTRIM(RTRIM(ProviderNameTemplate)), N'') IS NULL;
```

**SQLite inputs:** `cfg_IisServiceAutoStartProviderDefinition(ProviderName, ProviderNameTemplate, IsEnabled)`. All exist.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison.

**Rule 7:** No catalog filesystem path.

**Text comparison:** Ordinary spaces only. `.Trim()`-style all-whitespace semantics would be wrong.

**Tests:** Trigger: enabled row whose template contains only ordinary spaces. Non-trigger: enabled nonblank template. Boundary: a template containing only a tab does **not** trigger; a disabled spaces-only row does not trigger.

**Ambiguity:** None in the predicate.

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

**SQLite inputs:** `cfg_IisApplicationAutoStartDefinition(IisApplicationCode, ServiceAutoStartProvider, ServiceAutoStartEnabled, IsEnabled)` and `cfg_IisServiceAutoStartProviderDefinition(ProviderName, IsEnabled)`. All exist.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison.

**Rule 7:** No catalog filesystem path.

**Text comparison:** Legacy `ProviderName = ServiceAutoStartProvider` is confirmed CI_AS: case-insensitive, accent-sensitive. These are provider identifiers, not catalog `...Code` fields. **[PENDING]** Decide whether the portable port preserves CI_AS semantics for this non-code identifier or deliberately uses exact comparison. That decision covers both case-only and accent-only differences.

**Tests:** Trigger: enabled auto-start definition references a missing/disabled provider. Non-trigger: matching enabled provider. Boundaries: case-only provider difference and accent-only provider difference, expected result `[PENDING]` the portable comparison decision.

**Ambiguity:** Portable comparison policy for this non-code provider identifier only.

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

**SQLite inputs:** Recreate the legacy view from carried `dbo_ManagedServer(ServerCode, MachineName, IsEnabled)`, `dbo_ManagedInstance(InstanceCode, ServerCode, HostName, IsEnabled)`, `cfg_IisApplicationAutoStartDefinition(ServiceAutoStartProvider, ServiceAutoStartEnabled, IsEnabled)`, and `cfg_IisServiceAutoStartProviderDefinition(ProviderName, ProviderNameTemplate, ProviderType, IsRequired, SortOrder, IsEnabled)`. Derived `ProviderName` uses the exact nested `REPLACE` sequence in the view.

**Original severity:** `ERROR`.

**Rule 6:** Per-row validation, not a conflict check. Report on the selected instance only when its derived provider row is invalid.

**Rule 7:** No filesystem path.

**Text comparison:** The machine filter was legacy CI_AS. Portable Windows-name comparison is case-insensitive by rule 7; **[PENDING]** accent behavior for Windows names is not otherwise specified. Empty-name behavior uses ordinary-space `LTRIM/RTRIM` plus padded `NULLIF`. `LEN` ignores trailing ordinary spaces.

**Tests:** Trigger: selected instance derives an empty/spaces-only provider name or a name whose SQL `LEN` is 81. Non-trigger: nonblank name with SQL `LEN <= 80`. Boundaries: tab-only provider name does not count as empty; 80 non-space characters plus one trailing space does **not** trigger because SQL `LEN` is 80; 81 non-space characters does trigger.

**Ambiguity:** Only the portable accent rule for Windows `MachineName` remains `[PENDING]`.

## `AUTO_START_PROVIDER_EXPANDED_NAME_DUPLICATE`

**Verbatim T-SQL predicate:**

```sql
FROM cfg.IisServiceAutoStartProviderCatalog AS C
WHERE (@MachineName IS NULL OR C.MachineName = @MachineName)
GROUP BY C.ProviderName
HAVING COUNT(*) > 1;
```

**SQLite inputs:** Same exact carried-table recreation of `cfg.IisServiceAutoStartProviderCatalog` described above. `ProviderCode = P.ProviderName`; `ProviderName` is the expanded template result.

**Original severity:** `ERROR`.

**Rule 6:** Yes. Build provider rows for every enabled instance of the local machine. Report the duplicate on the selected instance when it participates; a conflict with an unselected enabled instance must still fire for the selected participant.

**Rule 7:** No filesystem path.

**Text comparison:** Legacy grouping is confirmed CI_AS: `ProviderA` and `providera` are one group; accent-distinct names remain different. **[PENDING]** Decide whether portable grouping preserves CI_AS for this non-code provider name or deliberately uses exact comparison. Test both case-only and accent-only boundaries.

**Tests:** Trigger: selected and unselected enabled instances derive the same provider name. Non-trigger: all machine provider names unique. Boundaries: case-only names group under legacy CI_AS; accent-only names do not. Portable expected behavior remains `[PENDING]` until the non-code provider-name policy is approved.

**Ambiguity:** Portable non-code provider-name collation policy only.

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

**SQLite inputs:** `cfg_IisApplicationAutoStartDefinition(IisApplicationCode, ServiceAutoStartEnabled, IsEnabled)` and `cfg_IisApplicationDefinition(IisApplicationCode, PoolStartMode)`. All exist.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison.

**Rule 7:** No filesystem path.

**Text comparison:** `IisApplicationCode` is exact in the new system by owner decision. Legacy `PoolStartMode <> 'AlwaysRunning'` is CI_AS. `alwaysrunning` therefore did not trigger in the source; accent sensitivity is also defined by CI_AS even though it is not meaningful for this literal. **[PENDING]** Decide whether the portable non-code enum preserves CI_AS or uses exact comparison.

**Tests:** Trigger: `PoolStartMode = 'OnDemand'`. Non-trigger: `AlwaysRunning`. Boundary: `alwaysrunning` is a legacy non-trigger; portable expected result is `[PENDING]` the enum comparison decision.

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

**SQLite inputs:** `dbo_ManagedInstance(InstanceCode, ServerCode, HostName, IsEnabled)`, `dbo_ManagedServer(ServerCode, MachineName, IsEnabled)`, `cfg_IisApplicationAutoStartDefinition(IisApplicationCode, ServiceAutoStartProvider, ServiceAutoStartEnabled, IsEnabled)`, and the exact derived view from those tables plus `cfg_IisServiceAutoStartProviderDefinition`. In the view, `ProviderCode = P.ProviderName` and `ProviderName` is the expanded template.

**Original severity:** `ERROR`.

**Rule 6:** The source enumerates all enabled instances on the machine but does not compare one instance value against another. In a selected-instance run, evaluate/report the selected instance row. The full enabled set is still used to reproduce the legacy view.

**Rule 7:** No filesystem path.

**Text comparison:** `ServerCode`, `InstanceCode`, and application codes are exact in the new system. Legacy provider-code equality is CI_AS because `ProviderCode` is the legacy view's `P.ProviderName`; **[PENDING]** decide whether that non-code provider identifier remains CI_AS or becomes exact. Machine-name case is insensitive by rule 7; accent behavior remains `[PENDING]`.

**Tests:** Trigger: selected enabled instance plus enabled auto-start definition has no matching derived provider row. Non-trigger: matching row has non-null `ProviderName`. Boundaries: only another instance missing the row must not relabel the selected instance; case-only and accent-only provider identifier differences exercise the `[PENDING]` provider comparison policy.

**Ambiguity:** Portable non-code provider and Windows-name accent policies only; the view derivation is now confirmed.

## `AUTO_START_ASSEMBLY_LOADABILITY`

**Verbatim T-SQL predicate:**

```sql
FROM cfg.IisServiceAutoStartProviderCatalog AS C
WHERE (@MachineName IS NULL OR C.MachineName = @MachineName);
```

**SQLite inputs:** Exact recreation of the legacy view from the four carried tables above, using derived `InstanceCode`, `MachineName`, and `ProviderName`.

**Original severity:** `WARNING`.

**Rule 6:** No cross-instance comparison. The source emits one warning for every provider-catalog row in scope; in a selected-instance run, report only selected-instance rows and do not invent an assembly probe.

**Rule 7:** No filesystem path.

**Text comparison:** Only `MachineName` is compared. Case-insensitive Windows-name behavior is fixed by rule 7; Windows-name accent behavior remains `[PENDING]`.

**Tests:** Trigger: selected instance has one derived provider row. Non-trigger: selected instance has none. Boundary: only another enabled instance has provider rows; selected instance gets no warning.

**Ambiguity:** Windows-name accent behavior only. The T-SQL performs no loadability probe.

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

**SQLite inputs:** `cfg_ConfigRule(RuleCode, IsEnabled)`. Both exist.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison.

**Rule 7:** No filesystem path.

**Text comparison:** Legacy equality was CI_AS, but `RuleCode` is a catalog code. The 2026-10-05 owner decision makes codes exact in the new system, including case and accents. This is decided, not `[PENDING]`.

**Tests:** Trigger: exact enabled `WFM_PROCESS_USE_HANGFIRE` absent. Non-trigger: exact enabled row exists. Boundary: case-only variant does not satisfy the portable exact-code check even though legacy CI_AS would have matched it.

**Ambiguity:** None after the recorded exact-code decision.

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

**SQLite inputs:** `cfg_ConfigRule(RuleCode, IsEnabled)`. Both exist.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison.

**Rule 7:** No filesystem path.

**Text comparison:** Same recorded exact-code decision as above. Portable comparison is exact for case and accents.

**Tests:** Trigger: exact enabled rule absent/disabled. Non-trigger: exact enabled row exists. Boundary: case-only variant must not satisfy the portable exact-code check.

**Ambiguity:** None after the recorded exact-code decision.

## Implementation stop points

The legacy provider-catalog view is now fully specified by the evidence file and is not a blocker. Remaining `[PENDING]` items are portable comparison-policy decisions only: non-code provider identifiers/names, `PoolStartMode`, and accent behavior for Windows machine names. Source behavior for each is known as Latin1_General_CI_AS; catalog codes are already decided exact. No predicate may be reconstructed from the issue-code name.
