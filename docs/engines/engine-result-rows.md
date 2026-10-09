# Engine result rows

**Status:** [PROPOSED]
**Verification base:** `main@41d09f38e5aedc4f9b62656870d0b999ca661205`
**Executable reference:** `engines/Invoke-DeploymentPreflight.ps1`
**Schema reference:** `contracts/engine-result.schema.json`

This document defines the row contract demonstrated by the integrated `DEPLOYMENT_PREFLIGHT` engine and reconciles it with the shared result schema. It is documentation only; it does not change the schema or engine.

## 1. Result envelope

The engine writes one JSON object with the fields required by `contracts/engine-result.schema.json`: `contractVersion`, `operationId`, `engineCode`, `engineVersion`, `mode`, `startedAt`, `completedAt`, `succeeded`, `exitCode`, `summary`, and `results`. `errorMessage` is also emitted by `DEPLOYMENT_PREFLIGHT`.

For the integrated preflight:

- `contractVersion` is `0.1-proposed`.
- `engineCode` is `DEPLOYMENT_PREFLIGHT` and `engineVersion` is `1.0.0`.
- `mode` is always `PREVIEW`.
- `succeeded` is true only when there is no `ERROR` row and the run was not cancelled.
- `exitCode` is `0` when succeeded and `1` otherwise.
- `errorMessage` is `CANCELLED` for cancellation, `PREFLIGHT_ERRORS` when at least one error exists, and empty otherwise.
- `summary` contains `targetCount`, `succeededTargets`, `failedTargets`, `warningCount`, and `errorCount`, all non-negative integers as required by the schema.

## 2. Result-row shape

Every preflight issue becomes one object in `results` with this shape:

| Field | Contract | Current `DEPLOYMENT_PREFLIGHT` behavior |
|---|---|---|
| `timestamp` | UTC `yyyy-MM-ddTHH:mm:ssZ` | The completion timestamp used by `Write-EngineResult`; all rows in one result currently receive the same timestamp. |
| `instanceCode` | string, empty for machine-wide rows | The issue target instance. An empty string means the issue is catalog-, machine-, or run-wide. |
| `operationType` | uppercase engine-specific code | The issue `Area`. `Add-Issue` replaces an invalid area with `MODEL_REVIEW`. |
| `object` | string, max 400 | The issue code when no object is supplied; otherwise `<IssueCode>:<Object>`. `Add-Issue` truncates this composite value to 400 characters. |
| `status` | schema accepts a shaped string | Preflight restricts it to `ERROR`, `WARNING`, or `INFO`. |
| `details` | redacted free text, schema max 2000 | Preflight always emits it and truncates source details to 1800 characters before result serialization. It must not contain secrets. |

The issue code therefore has no separate JSON property in the shared row schema. In the integrated preflight it is encoded at the start of `object`: exactly the code for a code-only row, or the prefix before the first engine-added `:` when a separate object identifier exists.

## 3. Ordering

`DEPLOYMENT_PREFLIGHT` does not preserve discovery order. Before serialization it sorts issues by:

1. severity: `ERROR`, then `WARNING`, then `INFO`;
2. `Area`;
3. `InstanceCode`;
4. `Object`.

The generic schema currently describes `results` as rows in execution order. [PROPOSED] Consumers must not rely on generic execution ordering for preflight; the integrated engine's deterministic severity/area/instance/object order is the executable behavior until the shared schema is tightened.

## 4. Target counts

When the catalog is open, `targetCount` is recalculated from `Get-SelectedInstances`, and the real count is retained even when it is zero.

For an ordinary completed review:

- an instance with at least one `ERROR` contributes once to `failedTargets`, regardless of how many error rows it has;
- a machine-wide/global error contributes one failed target only when no instance-specific error is already being counted;
- `succeededTargets` is `targetCount - failedTargets`, bounded at zero.

When `Write-EngineResult` is called with `AllTargetsFailed = true`, `failedTargets` becomes `targetCount` and `succeededTargets` becomes zero. This is the contract for an abort that prevented the selected targets from being reviewed.

## 5. Early termination and special rows

### Catalog never opened: `PREFLIGHT_TARGETS_UNKNOWN`

If no catalog connection was established, the engine cannot derive the selected-instance count without trusting the catalog path that failed to open. It adds:

- `status`: `INFO`;
- `operationType`: `PREFLIGHT`;
- `object`: `PREFLIGHT_TARGETS_UNKNOWN`;
- empty `instanceCode`;
- details stating that `targetCount = 1` is only a placeholder and the run failed as a whole.

In this state `targetCount = 1` MUST NOT be interpreted as a measured instance count. The 2026-10-09 owner decision keeps the engine input contract free of a caller-supplied selected-instance count; the orchestrator knows what it requested, while the engine explicitly marks its own target count as unknown.

An outer preflight failure also contributes an `ERROR` row such as `PREFLIGHT_INTERNAL_ERROR`, so `succeeded` is false. `PREFLIGHT_COVERAGE_INCOMPLETE` is still added before the result is written.

### Missing required catalog table: `CATALOG_TABLE_MISSING`

For every missing required table the engine emits an `ERROR` row in area `CATALOG` with an object of the form:

```text
CATALOG_TABLE_MISSING:<TableName>
```

The engine exits before the model reviews and calls `Write-EngineResult` with `AllTargetsFailed = true`. Therefore every target represented by `targetCount` fails; no unreviewed target may be reported as succeeded. If target enumeration itself cannot be completed because the required instance table is part of the structural failure, the writer falls back to its failure-path count rather than claiming a verified instance count.

### Cancellation: `CANCELLED`

Cancellation emits a machine-wide `ERROR` row:

- `operationType`: `PREFLIGHT`;
- `object`: `CANCELLED`;
- empty `instanceCode`.

The cancellation handler calls the writer with both `Cancelled = true` and `AllTargetsFailed = true`. All selected targets therefore fail, `succeededTargets` is zero, `succeeded` is false, `exitCode` is `1`, and `errorMessage` is `CANCELLED`.

The cancellation probe is deliberately performed after the catalog has opened so that a valid catalog can provide the real selected-target count before the all-target failure is calculated.

### Zero active instances

Once the catalog is open, zero is a valid selected-target count. The engine does not clamp it to one:

```text
targetCount = 0
failedTargets = 0
succeededTargets = 0
```

If there is no `ERROR`, the run can still have `succeeded = true`; the result means that there were no selected targets to fail. Informational rows such as the coverage marker do not create a target.

### `PREFLIGHT_COVERAGE_INCOMPLETE`

Every structured preflight result carries this `INFO` row unless it is already present:

- `operationType`: `PREFLIGHT`;
- `object`: `PREFLIGHT_COVERAGE_INCOMPLETE`;
- empty `instanceCode`.

At the verification base the engine declares `CoverageImplemented = 31` and `CoverageTotal = 66`. The details explicitly say that coverage is counted **by issue-code name**, that the implemented predicates are not all one-to-one copies of the original reviews, and that a clean result is not a complete readiness assessment. The D14 audits are the parity evidence for those predicate differences.

This marker is added inside `Write-EngineResult`, so it is present on normal results and on structured early-failure results, including manifest/catalog/machine failures, missing-table aborts, and cancellation.

## 6. Summary/status relationship

For the integrated preflight:

- `errorCount` is the number of `ERROR` rows.
- `warningCount` is the number of `WARNING` rows.
- `INFO` rows do not increment either count.
- `succeeded = true` requires `errorCount = 0` and no cancellation.
- `failedTargets` and `succeededTargets` describe targets, not issue rows; multiple errors on one instance do not multiply the failed-target count.
- a global error can make the run fail even when no concrete `instanceCode` exists.

The shared schema separately proposes the invariant `targetCount = succeededTargets + failedTargets`. `DEPLOYMENT_PREFLIGHT` writes its summary to satisfy that shape, including the zero-target case and `AllTargetsFailed` early-abort cases.

## 7. Secret safety

The row schema allows free text only in `object` and `details`; the engine constructs these from issue codes/object identifiers and redacted diagnostic text. Credential values, tokens, private keys, connection strings, and secret package contents must never appear in a result row. This is a contract requirement, not merely a presentation rule.

## 8. Scope

[PROPOSED] This document is the baseline for result-row producers and consumers because it is grounded in the first integrated engine plus `contracts/engine-result.schema.json`. Engine-specific operation types and statuses may differ. Any future attempt to make issue code a first-class field, change row ordering, or alter summary accounting requires an explicit contract change rather than inference from a different engine.
