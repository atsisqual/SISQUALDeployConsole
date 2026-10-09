# Decision brief: SQL-type actions refused by the host

**Status:** [PROPOSED] for owner decision O5. Documentation only; no catalog, host, engine, runtime or workflow change is made here.
**Date:** 2026-10-09

## Scope

ADR-0008 makes `ActionType = SQL` non-executable by the portable host: the host refuses it with `ACTION_TYPE_NOT_SUPPORTED` and never executes catalog text. The source snapshot still contains three enabled SQL-type actions:

- `EXECUTION_HISTORY`
- `LINKS_VISIBILITY_MATRIX`
- `OBJECT_AUDIT`

This brief records what each action does today, what can replace it in the portable product, which wave or product surface owns that replacement, and the recommended disposition for owner decision O5.

## Evidence and source boundary

Source facts below come from the read-only reference repository `atsisqual/SISQUALManagementConsole`, file `database/sync/ManagementSync.sql`, reference `dde24f26a1719bb2f7ee1f4db8c9c4aeadf70d94`, generated 2026-10-08 02:00:01 from `_sisqualMANAGEMENT`.

Portable-product decisions come from:

- `docs/architecture/ADR-0007-embedded-readonly-catalog.md`;
- `docs/architecture/ADR-0008-engine-host-contract.md`;
- `docs/phase3/runtime-logging.md`;
- `docs/engines/LINKS_VISIBILITY.md`;
- `docs/decisions-log.md`.

The source snapshot describes the old console. It is not executable evidence for the portable product. This PR does not claim that any SQL command below was executed in the portable catalog.

## Summary recommendation

| Action | Current type | Current behavior | Portable replacement | Owner / wave | Recommendation |
|---|---|---|---|---|---|
| `EXECUTION_HISTORY` | `SQL` | Reads the latest 200 rows from `ops.ExecutionLog` | Read-only report over portable text logs after the runtime producer records the required action lifecycle fields | Runtime/report surface; no engine wave | Read-only report; do not create an engine |
| `LINKS_VISIBILITY_MATRIX` | `SQL` | Reads effective `/links` publication state from `cfg.LinksPageInstanceApplicationCatalog`, including both page modes | Wave 8 read-only visibility surface covering general-page and individual-page rows; change proposals remain individual-page only | Wave 8 | Read-only report; no second engine |
| `OBJECT_AUDIT` | `SQL` | Executes `ops.GetObjectUsageAudit` against Management Console SQL metadata | No like-for-like runtime replacement after `_sisqualMANAGEMENT` is retired | None if retired; new approved scope if retained | Retire from portable V1; use a separate support/cutover tool only if the capability is still required |

## 1. EXECUTION_HISTORY

### What it does today

The source action is enabled, has `ModePolicy = NONE`, has no engine and no instance selection, and executes this SQL:

```sql
SELECT TOP (200)
    ExecutionID,
    SessionID,
    ActionCode,
    EngineCode,
    InstanceCode,
    ExecutionMode,
    StartedAt,
    EndedAt,
    Status,
    Message
FROM ops.ExecutionLog
ORDER BY ExecutionID DESC;
```

Its enabled requirement is `ops.ExecutionLog`.

This is a read-only presentation of execution history. It does not reconcile or mutate a managed target.

### Portable replacement

ADR-0007 removes the writable state database from the portable application and states that operation history goes to plain-text logs. ADR-0008 explicitly records the owner decision that `EXECUTION_HISTORY` is replaced by reading those text logs.

That architectural decision does not mean the current log records are already a field-for-field replacement. The current engine host completion/failure records include operation id, engine, mode, instance, duration, exit code, outcome/summary, locks and plan information, but they do not record the top-level `ActionCode` or the engine result message. `EngineCode` cannot be used to reconstruct the action reliably because an action may alias another engine and a composite parent action may execute child engines.

Before a text-log reader can replace the current history action without losing source-visible information, the runtime producer/adapter must emit normalized operation lifecycle records that preserve, at minimum:

- `operationId`;
- top-level `actionCode`;
- `engineCode` when an engine is involved;
- `instanceCode` or equivalent target identity;
- execution `mode`;
- `startedAt` and `endedAt` (or enough timestamp plus duration data to derive both);
- final `status`/outcome;
- the non-secret result or failure `message` that is intended for history display.

For composite actions the record must retain the parent action identity as well as child engine events. For aliases, the requested action code must remain distinct from the resolved engine code. None of these fields requires a state database; they are structured fields in the plain-text operation log.

The replacement therefore belongs to the runtime/reporting surface, not the engine host as a new engine. The report reader is complete only after those producer fields exist; this brief does not implement them.

### Wave ownership

`N/A` as an engine wave. The foundation is Phase 3 runtime logging. Completing the replacement requires runtime/adapter logging work to emit the normalized lifecycle fields above, followed by the UI/report surface that reads them.

### Recommendation

**Read-only report; do not create an engine.**

Preserve the current history semantics in the text-log producer first, then build the reader. Keeping this as an engine would add a process launch only to read product-local history and would incorrectly model that history as a managed-system operation.

## 2. LINKS_VISIBILITY_MATRIX

### What it does today

The source action is enabled, has `ModePolicy = NONE`, has no engine and no instance selection. Its SQL selects published application visibility from `cfg.LinksPageInstanceApplicationCatalog`, including:

- instance, country, customer and host;
- application code and display name;
- global publication state;
- individual-page default state;
- explicit instance publication state;
- effective publication state;
- last modification time.

It filters `IsGloballyPublished = 1` and orders the result by page mode, instance and application. The report therefore covers the general-page publication view as well as the individual-page visibility view.

This is already a read-only matrix. It does not apply visibility changes.

### Portable replacement

The owner decision recorded in `docs/decisions-log.md` makes link visibility a read-only matrix in V1; a change is an owner edit of the catalog followed by a seal. The Wave 8 `LINKS_VISIBILITY` specification defines the portable individual-page direction as an effective-visibility matrix and change proposal rather than a central database write.

The current Wave 8 specification describes the 840 instance/application combinations for the 70 individual-page instances. That is sufficient for per-instance override proposals, but by itself it is not the complete replacement for the SQL report because the SQL report also exposes the general-page publication rows/state.

The Wave 8 read-only surface must therefore cover both page modes:

- general-page rows/state needed to preserve the current report visibility;
- individual-page effective visibility (default/profile/override) for the existing matrix and proposal logic.

Change proposals remain restricted to the individual-page capability described by `LINKS_VISIBILITY`; general-page rows are read-only report data in this replacement. The read-only calculation should still be shared with `LINKS_PAGES` so the report and generated pages cannot disagree.

### Wave ownership

**Wave 8 - `LINKS_VISIBILITY`.**

The complete matrix/report surface belongs to that capability. It is not a second engine. The Wave 8 implementation/specification must account for the general-page report rows in addition to its existing individual-page matrix.

### Recommendation

**Read-only report owned by Wave 8; retire the standalone SQL action path.**

Expose both page modes in the read-only surface, while keeping owner-edit/change-proposal behavior limited to the individual-page visibility rules already approved. If a browser route or API endpoint is needed, it should call shared read-only visibility logic rather than queueing an engine or executing catalog SQL text.

## 3. OBJECT_AUDIT

### What it does today

The source action is enabled, has `ModePolicy = NONE`, has no engine and no instance selection, and executes:

```sql
EXEC ops.GetObjectUsageAudit;
```

Its enabled requirement is `ops.GetObjectUsageAudit`.

The procedure is read-only. It inventories Management Console SQL objects and reports, among other fields:

- SQL dependency count from `sys.sql_expression_dependencies`;
- enabled engine-script references to each object;
- enabled action-requirement references;
- object creation and modification dates.

After the retired-object registry cleanup, the procedure deliberately returns `IsRetiredCandidate = 0` for every row. Its remaining value is support/audit visibility into the old Management Console database and its SQL-owned runtime model.

### Portable replacement

There is no like-for-like target in the accepted portable architecture:

- ADR-0007 decommissions `_sisqualMANAGEMENT` after cutover;
- the portable catalog is SQLite and read-only;
- stored engine script text is not carried in the catalog;
- ADR-0008 never executes catalog SQL text.

An engine cannot preserve the current semantics without inventing a new SQL target and a new contract for what is being audited. That would be new product scope, not a port of the existing action.

If the audit remains useful during migration or support before the old database is retired, it can remain a separate read-only operator tool that explicitly targets the legacy Management Console database. Such a tool would be outside the portable engine host and outside the runtime catalog.

### Wave ownership

**None if retired, which is the recommendation.**

If the owner chooses to preserve it as a portable capability, it needs a new explicitly approved scope/wave because no existing engine wave owns a Management Console SQL metadata audit after `_sisqualMANAGEMENT` is decommissioned.

### Recommendation

**Retire `OBJECT_AUDIT` from portable V1.**

Optionally preserve the legacy query as a separate cutover/support tool if operators still need to inspect the old Management Console database before decommission. Do not create a portable engine merely to retain the action code.

## Host and catalog consequence

Until implementation follows this decision, ADR-0008 remains fail-closed: all three `SQL` actions are refused by the host with `ACTION_TYPE_NOT_SUPPORTED`.

A later implementation PR may change navigation or catalog metadata according to the owner's decision, but this decision brief does not change or disable any action row.

Recommended end state:

1. `EXECUTION_HISTORY`: no executable action; after the runtime producer preserves the required action lifecycle fields, expose a read-only text-log report.
2. `LINKS_VISIBILITY_MATRIX`: no executable SQL action; expose the Wave 8 read-only surface for both general-page and individual-page rows, with change proposals restricted to individual pages.
3. `OBJECT_AUDIT`: absent from portable V1; optional separate legacy support/cutover tool only if still needed.

## Owner decision O5

Please decide one disposition for each action:

| Action | A | B | C | Recommendation |
|---|---|---|---|---|
| `EXECUTION_HISTORY` | Read-only text-log report, with producer lifecycle fields completed first | New read-only engine | Retire without replacement | **A** |
| `LINKS_VISIBILITY_MATRIX` | Wave 8 read-only matrix/report covering both page modes; proposals individual-page only | New separate read-only engine | Retire without replacement | **A** |
| `OBJECT_AUDIT` | Retire from portable V1; optional separate legacy support tool | Define a new portable audit capability and wave | Keep blocked indefinitely | **A** |

No implementation should infer owner approval from this document. Record O5 in `docs/decisions-log.md` before changing runtime behavior or catalog/navigation semantics.
