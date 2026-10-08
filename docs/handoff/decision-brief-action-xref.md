# Decision brief: stale configuration adapter action references

**Status:** [PROPOSED] owner decision O4.
**Date:** 2026-10-08.
**Scope:** documentation only. No catalog, verifier, engine or runtime change is made here.

## 1. Evidence boundary

### Checked now against the converted real snapshot

The reviewer real-snapshot run on the 2026-10-07 nightly export produced 6 catalogs, 76 instances and 16 redacted values. After the obsolete-metadata cleanup, `Test-CatalogConversion.ps1` reported 131 passed / 6 failed. The six failures are one `action-xref` failure in each catalog, and every catalog reports the same three unresolved adapter references:

- `DATABASE_SETTING -> SETTINGS_SYNC`
- `HOUSEKEEPING -> HOUSEKEEPING_APPLY`
- `WINDOWS_SERVICE -> SERVICE_RECONCILE`

These are therefore three stale global adapter rows repeated in all six catalogs, not six different adapter rows.

I also checked the current specifications and source definitions now to identify the corresponding portable actions and to avoid guessing from the stale names:

- action `DATABASE_SETTINGS` exists and runs engine `DATABASE_CONTENT_SYNC`; it remains the retained step 30 of `FULL_DEPLOYMENT`;
- action `WINDOWS_SERVICES` exists and runs engine `WINDOWS_SERVICES`;
- action `STORAGE_SIZE_SCAN` exists, but it only measures housekeeping-policy storage. The specification explicitly says deletion/cleanup is a separate old-console feature, outside the 19 engines;
- the owner decision of 2026-10-06 puts housekeeping itself in a separate phase after wave 9.

The stale target codes `SETTINGS_SYNC`, `HOUSEKEEPING_APPLY` and `SERVICE_RECONCILE` do not resolve to rows in `ops_Action`, which is exactly why the real-snapshot `action-xref` group fails.

### What was in CI

CI proved the converter/verifier behavior with synthetic and LocalDB/SQL Server fixtures, not the contents of the real nightly snapshot. On the cleanup head, the relevant CI evidence included the C8/action-xref regression suite, the B4 verifier suite and the 41/41 LocalDB/SQL Server integration. The real-snapshot 131 passed / 6 failed result above was a reviewer local run and must not be described as CI evidence.

## 2. The three adapter rows

| AdapterCode | SourceType | Route | Current ActionCode | Portable action that exists | Assessment |
|---|---|---|---|---|---|
| `DATABASE_SETTING` | `DATABASE_SETTING_RULE` | `/actions` | `SETTINGS_SYNC` | `DATABASE_SETTINGS` -> engine `DATABASE_CONTENT_SYNC` | stale name; there is already one approved portable action for this behavior |
| `WINDOWS_SERVICE` | `WINDOWS_SERVICE` | `/environments` | `SERVICE_RECONCILE` | `WINDOWS_SERVICES` -> engine `WINDOWS_SERVICES` | stale name; there is already one approved portable action for this behavior |
| `HOUSEKEEPING` | `RETENTION_POLICY` | `/housekeeping` | `HOUSEKEEPING_APPLY` | no equivalent apply action in the 19-engine catalog | stale execution reference; `STORAGE_SIZE_SCAN` is not an apply/cleanup replacement |

`cfg_ConfigurationAdapterDefinition.ActionCode` is optional. The verifier deliberately accepts NULL/blank references and only requires a non-empty value to resolve exactly to `ops_Action.ActionCode`.

## 3. Options

### Option A - repair the two real aliases and make housekeeping route-only for now

Set the adapter references to:

- `DATABASE_SETTING.ActionCode = DATABASE_SETTINGS`
- `WINDOWS_SERVICE.ActionCode = WINDOWS_SERVICES`
- `HOUSEKEEPING.ActionCode = NULL`

The housekeeping row and `/housekeeping` route can remain catalog data, but any UI state that claims apply/approval through an action must be made consistent when the data change is implemented; a NULL `ActionCode` must not dispatch an engine.

**Verifier effect:** the three unresolved references disappear. Because the adapter table is global, the same repair removes the `action-xref` failure from all six catalogs, assuming there are no other changes.

**Engine effect:** none. The first two adapters point at engines already in the approved port plan. No housekeeping engine is invented, and `STORAGE_SIZE_SCAN` keeps its read-only measurement purpose.

### Option B - add a real portable housekeeping apply action later

Repair the first two aliases as in option A, but keep housekeeping executable by defining a new portable `HOUSEKEEPING_APPLY` action and an explicit implementation in the post-wave-9 housekeeping phase.

Until that action exists, either leave `HOUSEKEEPING.ActionCode` NULL or keep the verifier failure open intentionally; do not create a placeholder action that has no implementation.

**Verifier effect:** the database and Windows-service references can become valid immediately. The housekeeping reference becomes valid only when the new action is actually present in `ops_Action`.

**Engine effect:** expands the executable surface beyond the current 19 engines and needs its own specification, safety model, tests and owner-approved phase work. It must not be substituted by `STORAGE_SIZE_SCAN`, because that engine does not delete or move files.

### Option C - disable or detach all three adapters until later UI work

Set all three `ActionCode` values to NULL, or disable the rows, and reconnect them only when their screens are revisited.

**Verifier effect:** the `action-xref` failures disappear because optional empty references are allowed.

**Engine effect:** no engine change, but two adapters would unnecessarily lose direct links to valid existing actions (`DATABASE_SETTINGS` and `WINDOWS_SERVICES`). This discards useful catalog wiring without solving a functional problem.

## 4. Recommendation

**Recommend option A.** It is the smallest correction that matches the current portable action model and the owner decisions already recorded:

1. map `DATABASE_SETTING` to `DATABASE_SETTINGS`;
2. map `WINDOWS_SERVICE` to `WINDOWS_SERVICES`;
3. set `HOUSEKEEPING.ActionCode` to NULL until the separate post-wave-9 housekeeping phase defines an executable action.

Do not map `HOUSEKEEPING` to `STORAGE_SIZE_SCAN`: that would make an apply/retention adapter invoke a read-only size measurement and would change the meaning of the action rather than repair a stale cross-reference.

## 5. Owner decision needed

Approve one of these mappings for the later catalog-data change. If option A is approved, the implementation should also verify that the housekeeping adapter UI does not expose an apply/approval dispatch while its `ActionCode` is NULL. This brief does not make that data or UI change.
