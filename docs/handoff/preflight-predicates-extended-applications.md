# DEPLOYMENT_PREFLIGHT predicates: Extended applications

**Status:** [PROPOSED]
**Procedure:** `cfg.ReviewExtendedApplicationModel`
**Verification base:** `main@a32141cbec584d349f1591a4aa5a801137463278`

## Evidence boundary

The predicate source is `docs/handoff/preflight-legacy-procedures.sql.txt` at the verification base. Its header says the five procedures were extracted verbatim from the reviewer-verified Management Console snapshot. The requested port set and rules 6 and 7 come from `docs/handoff/preflight-port-gap.md` on read-only PR #69 head `80240090ba5dc37e13a64d359f9378a1c033fcc4`.

SQLite table/column names below were checked against `tests/Fixtures/carried-schema.json` at the verification base. SQL Server names map by replacing the schema separator with `_`, for example `cfg.IisApplicationDefinition` -> `cfg_IisApplicationDefinition`.

The requested `tests/Fixtures/preflight-legacy-codes.json` is not present in `main@a32141cbec584d349f1591a4aa5a801137463278`. For this text-only specification, every severity is therefore checked against the literal severity in the extracted T-SQL and against the 10-code table in `preflight-port-gap.md`. No severity is inferred from a code name.

Two legacy read surfaces are relevant to this review. `cfg.IisServiceAutoStartProviderCatalog` is a SQL Server view and has no `cfg_IisServiceAutoStartProviderCatalog` table in `carried-schema.json`; the conversion plan says this pure-read view must be recreated as a portable query. This document does not invent that query.

### Text comparison policy

The extracted procedure has no `COLLATE`, so legacy text equality/grouping follows the source database default collation, which the snapshot does not state. The port-gap rule says Windows names are compared without case and catalog codes exactly. This document applies those explicit portable rules where the field is clearly in one of those classes. Trim/empty and length tests are collation-independent. For provider names/templates and IIS enum/template text, where neither rule fixes case semantics, the case-only boundary is marked `[PENDING]` rather than guessed.

## `AUTO_START_PROVIDER_TYPE_MISSING`

**Verbatim T-SQL predicate:**

```sql
FROM cfg.IisServiceAutoStartProviderDefinition
WHERE IsEnabled = 1
  AND NULLIF(LTRIM(RTRIM(ProviderType)), N'') IS NULL;
```

**SQLite inputs:** `cfg_IisServiceAutoStartProviderDefinition(ProviderName, ProviderType, IsEnabled)`. All three columns exist in `carried-schema.json`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison. The definition is global. If this review is run for one selected instance, report the issue on that selected instance because the invalid global definition affects its deployment; do not manufacture a conflict with another instance.

**Rule 7:** No catalog filesystem path is used.

**Text comparison:** `LTRIM`/`RTRIM` plus empty-string detection is collation-independent. Keep that behavior exactly.

**Tests:** Trigger: enabled row with `ProviderType = '   '`. Non-trigger: enabled row with a nonblank `ProviderType`. Boundary: disabled row with blank `ProviderType` must not fire.

**Ambiguity:** None in the predicate.

## `AUTO_START_PROVIDER_TEMPLATE_MISSING`

**Verbatim T-SQL predicate:**

```sql
FROM cfg.IisServiceAutoStartProviderDefinition
WHERE IsEnabled = 1
  AND NULLIF(LTRIM(RTRIM(ProviderNameTemplate)), N'') IS NULL;
```

**SQLite inputs:** `cfg_IisServiceAutoStartProviderDefinition(ProviderName, ProviderNameTemplate, IsEnabled)`. All exist in `carried-schema.json`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison. Report on the selected instance when the global definition is relevant to that preflight run.

**Rule 7:** No catalog filesystem path is used.

**Text comparison:** Trim/empty only; collation-independent.

**Tests:** Trigger: enabled row with whitespace-only `ProviderNameTemplate`. Non-trigger: enabled row with a nonblank template. Boundary: disabled blank-template row must not fire.

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

**SQLite inputs:** `cfg_IisApplicationAutoStartDefinition(IisApplicationCode, ServiceAutoStartProvider, ServiceAutoStartEnabled, IsEnabled)` and `cfg_IisServiceAutoStartProviderDefinition(ProviderName, IsEnabled)`. These columns exist in `carried-schema.json`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison; both inputs are definitions. Report the failure on the selected instance whose preflight consumes the definition.

**Rule 7:** No catalog filesystem path is used.

**Text comparison:** `P.ProviderName = D.ServiceAutoStartProvider` depends on the unknown legacy collation. These are provider identifiers but are not named as catalog `...Code` fields and rule 7 does not explicitly classify them. **[PENDING]** Decide whether a case-only difference is a match in the portable port. Until decided, do not silently choose ordinal or case-insensitive comparison.

**Tests:** Trigger: enabled auto-start definition points to a missing or disabled provider. Non-trigger: matching enabled provider exists. Boundary: provider differs only by case; expected result is **[PENDING]** the comparison decision above.

**Ambiguity:** The case-only provider-name behavior is unresolved; predicate shape is otherwise exact.

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

**SQLite inputs:** There is no carried `cfg_IisServiceAutoStartProviderCatalog` table. The legacy view exposes at least `InstanceCode`, `MachineName`, and `ProviderName` to this statement. The portable query that reproduces those fields is not present in `carried-schema.json`; its base-table derivation must be supplied before implementation.

**Original severity:** `ERROR`.

**Rule 6:** This is a per-row validation, not a comparison between instances. A one-instance preflight must report it on the selected instance only when the selected instance owns the derived provider row; invalid rows belonging only to other instances must not be relabeled as the selected instance's issue.

**Rule 7:** No filesystem path is used.

**Text comparison:** Machine name is a Windows name, so portable filtering is case-insensitive. Blank and `LEN > 80` are collation-independent.

**Tests:** Trigger: selected instance has a derived provider name that is blank or 81 characters. Non-trigger: selected instance has a nonblank provider name of at most 80 characters. Boundary: exactly 80 characters must not fire.

**Ambiguity:** **[PENDING]** What exact portable query recreates `cfg.IisServiceAutoStartProviderCatalog` and its `InstanceCode`, `MachineName`, and `ProviderName` values? Stop implementation of this code until that derivation is defined from carried tables.

## `AUTO_START_PROVIDER_EXPANDED_NAME_DUPLICATE`

**Verbatim T-SQL predicate:**

```sql
FROM cfg.IisServiceAutoStartProviderCatalog AS C
WHERE (@MachineName IS NULL OR C.MachineName = @MachineName)
GROUP BY C.ProviderName
HAVING COUNT(*) > 1;
```

**SQLite inputs:** No carried `cfg_IisServiceAutoStartProviderCatalog` table exists. Required derived fields are `InstanceCode`, `MachineName`, and `ProviderName`; their portable derivation is **[PENDING]**.

**Original severity:** `ERROR`.

**Rule 6:** Yes. The duplicate set must be calculated across provider rows for **every enabled instance of the local machine**, not only selected instances. Report the issue on the selected instance only if one of that instance's derived provider rows has a name in a duplicate group. A conflict with an unselected enabled instance must still fire for the selected participant.

**Rule 7:** No filesystem path is used.

**Text comparison:** Machine name is case-insensitive. `GROUP BY C.ProviderName` inherits the unknown legacy collation. Provider-name case semantics are not fixed by the portable rules. **[PENDING]** Decide whether `ProviderA` and `providera` are one duplicate group.

**Tests:** Trigger: selected instance and another enabled unselected instance derive the same provider name. Non-trigger: all derived provider names on the machine are unique. Boundary: names differ only by case; expected result is **[PENDING]** the provider-name comparison decision.

**Ambiguity:** Two blockers: the exact portable recreation of the legacy view, and case-only provider-name grouping.

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

**SQLite inputs:** `cfg_IisApplicationAutoStartDefinition(IisApplicationCode, ServiceAutoStartEnabled, IsEnabled)` and `cfg_IisApplicationDefinition(IisApplicationCode, PoolStartMode)`. All exist in `carried-schema.json`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison. This is a definition-to-definition join. Report on the selected instance whose IIS deployment consumes the invalid definition.

**Rule 7:** No filesystem path is used.

**Text comparison:** `IisApplicationCode` is a catalog code and is compared exactly in the portable engine. `PoolStartMode <> 'AlwaysRunning'` is not a catalog-code comparison and the legacy collation is unknown. **[PENDING]** Decide whether a case-only value such as `alwaysrunning` is accepted or rejected; do not infer that from the code name.

**Tests:** Trigger: enabled auto-start application whose joined definition has `PoolStartMode = 'OnDemand'`. Non-trigger: exact `AlwaysRunning`. Boundary: `alwaysrunning`; expected result is **[PENDING]** the enum-case decision.

**Ambiguity:** Case-only `PoolStartMode` behavior only.

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

**SQLite inputs:** `dbo_ManagedInstance(InstanceCode, ServerCode, IsEnabled)`, `dbo_ManagedServer(ServerCode, MachineName, IsEnabled)`, and `cfg_IisApplicationAutoStartDefinition(IisApplicationCode, ServiceAutoStartProvider, ServiceAutoStartEnabled, IsEnabled)` exist. `cfg_IisServiceAutoStartProviderCatalog` is not carried; the required derived `InstanceCode`, `ProviderCode`, and `ProviderName` mapping is **[PENDING]**.

**Original severity:** `ERROR`.

**Rule 6:** The legacy query enumerates all enabled instances on the machine, but it does not compare one instance's value to another. In a selected-instance preflight, evaluate the selected instance's provider expansion; do not report another instance's missing expansion as the selected instance's issue. The full enabled set may still be needed to recreate the legacy view, but that does not turn this predicate into a conflict check.

**Rule 7:** No filesystem path is used.

**Text comparison:** `ServerCode` and `InstanceCode` are catalog codes and remain exact; `MachineName` is case-insensitive. `C.ProviderCode = D.ServiceAutoStartProvider` cannot have its portable case semantics fixed until the missing view derivation defines what `ProviderCode` represents. **[PENDING]** for a case-only provider identifier.

**Tests:** Trigger: selected enabled instance plus enabled auto-start definition has no matching derived provider row. Non-trigger: the derived row exists and has non-null `ProviderName`. Boundary: only another enabled instance lacks the row; selected instance must not receive that issue.

**Ambiguity:** Exact recreation of `cfg.IisServiceAutoStartProviderCatalog`, including `ProviderCode`, is required before implementation.

## `AUTO_START_ASSEMBLY_LOADABILITY`

**Verbatim T-SQL predicate:**

```sql
FROM cfg.IisServiceAutoStartProviderCatalog AS C
WHERE (@MachineName IS NULL OR C.MachineName = @MachineName);
```

**SQLite inputs:** No carried `cfg_IisServiceAutoStartProviderCatalog` table exists. The statement needs derived `InstanceCode`, `MachineName`, and `ProviderName`.

**Original severity:** `WARNING`.

**Rule 6:** No cross-instance comparison. The source emits one warning for every provider-catalog row in scope. In a selected-instance preflight, report the warning only for the selected instance's derived row(s); do not reinterpret the warning as an actual assembly probe.

**Rule 7:** No filesystem path is used by this predicate.

**Text comparison:** Only the machine filter compares text. `MachineName` is a Windows name and is case-insensitive in the portable behavior.

**Tests:** Trigger: selected instance has one derived provider-catalog row; the warning fires. Non-trigger: selected instance has no derived provider row. Boundary: provider rows exist only for another enabled instance; selected instance must not receive their warning.

**Ambiguity:** **[PENDING]** The portable derivation of the legacy provider-catalog view is required. The T-SQL itself performs no loadability test; a port must not invent one under this issue code.

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

**SQLite inputs:** `cfg_ConfigRule(RuleCode, IsEnabled)`, confirmed in `carried-schema.json`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison; this is a global rule-definition check. Report on the selected instance because its Process configuration depends on the rule.

**Rule 7:** No filesystem path is used.

**Text comparison:** `RuleCode` is a catalog code. Portable behavior keeps exact code comparison as required by rule 7, even though an unknown case-insensitive legacy collation might have matched a case-only variant.

**Tests:** Trigger: no exact enabled `WFM_PROCESS_USE_HANGFIRE` row. Non-trigger: exact enabled row exists. Boundary: enabled `wfm_process_use_hangfire` only; portable exact-code behavior must still fire.

**Ambiguity:** None after applying the explicit exact-code rule.

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

**SQLite inputs:** `cfg_ConfigRule(RuleCode, IsEnabled)`, confirmed in `carried-schema.json`.

**Original severity:** `ERROR`.

**Rule 6:** No cross-instance comparison. Report on the selected instance whose Process configuration depends on the rule.

**Rule 7:** No filesystem path is used.

**Text comparison:** `RuleCode` is a catalog code and remains exact per rule 7.

**Tests:** Trigger: exact enabled rule is absent or disabled. Non-trigger: exact enabled `WFM_PROCESS_OWIN_AUTOSTART` exists. Boundary: case-only variant must not satisfy the portable exact-code check.

**Ambiguity:** None after applying the explicit exact-code rule.

## Implementation stop points

This document specifies the ten requested legacy predicates; it does not authorize code. Before any later engine PR implements the four codes that depend on `cfg.IisServiceAutoStartProviderCatalog`, the project needs the exact portable query that recreates that legacy view. Provider-name and `PoolStartMode` case-only semantics also remain `[PENDING]` where called out above. No predicate may be reconstructed from the issue-code name.
