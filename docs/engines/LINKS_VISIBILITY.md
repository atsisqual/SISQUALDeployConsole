# Engine port specification: LINKS_VISIBILITY

**Status:** [PROPOSED] specification for review (task 3, wave 8). No product code.
**Date:** 2026-10-05
**Sources (read only):** `ops.Engine` row `LINKS_VISIBILITY` of `database/sync/ManagementSync.sql` of `atsisqual/SISQUALManagementConsole` (file `Invoke-LinksVisibility.ps1`, version `1.0`, Windows PowerShell 5.1, administrator not required, stored `ScriptSha256` `67CCAEDB...`; reference head `9756ba956842884fabcf25b82c4fbf1d11cf56bd`); the action `LINKS_VISIBILITY`, the procedure `cfg.SetLinksPageApplicationVisibility` and the table `cfg.LinksPageInstanceApplication`; the instance directory design (task 1c, PR #29) and the specification of `LINKS_PAGES` (wave 5, PR #39). Script text is not copied and no secret value appears here.
Tags: [CONFIRMED] read in the source; [PROPOSED] recommendation; [PENDING] needs a decision; [V] needs a real server.

## 1. Purpose

Choose which published applications appear on each instance's individual `/links` page, per instance and application, and store that choice. [CONFIRMED] Action: group `ACCESS`, preview and apply, no instance selection, hidden from the menu. It is an interactive console tool: it lists the individual-page instances and the published applications, asks for numbers or ranges, asks Enabled or Disabled, previews, and on apply stores one row per choice. The pages themselves are rebuilt by `LINKS_PAGES`.

## 2. Inputs

| Source (catalog) | Content |
|---|---|
| `dbo_ManagedInstance` | enabled instances with `LinksIncludeAllInstances` = 0 (individual pages): 70 of 76; code, country, customer, host |
| `cfg_Application` | enabled applications with `PublishInLinks` = 1 (12), name, `LinksDefaultForIndividualPages` (3 default shown, 9 default hidden) |
| `cfg_LinksPageInstanceApplication` | the stored choices: 12 rows today, all for one instance (9 hidden, 3 shown) |
| `cfg_LinksProfile`, `cfg_LinksProfileInstance`, `cfg_LinksProfileApplication` | profile visibility, the other layer of the rule |

Parameters: instance (optional), apply. There are 840 instance and application combinations.

## 3. Steps

1. List the individual-page instances; choose some (or all). With an instance code given, skip the choice.
2. List the published applications; choose some (or all); choose Enabled or Disabled.
3. Build the plan: every chosen instance times every chosen application, with the desired state; preview prints it (`PLANNED`).
4. Apply: for each combination call the store procedure, status `UPDATED`; print "rebuild the links pages to publish the change".

## 4. Side effects

[CONFIRMED] **Writes configuration**: a merge into `cfg.LinksPageInstanceApplication`. The procedure rejects an unknown instance (52040), an instance whose page lists all environments (52041, the setting is ignored there) and an application that is not enabled and published (52042). [CONFIRMED] There is no transaction around the loop and no error handling per row: the first failure stops the run after earlier rows were written. The old plan does not compare with the stored state, so every combination is `PLANNED` even when already equal.

## 5. External dependencies

Only the configuration database. Rebuilding the pages is a separate engine.

## 6. Conflict with ADR-0007

The catalog is read-only for the application, and the owner changes it by hand and seals it. This engine's purpose, writing configuration, cannot be ported as it is. The options:

| Option | Description | Assessment |
|---|---|---|
| A | The engine shows the **effective visibility** and generates a **change proposal** (the rows of `cfg_LinksPageInstanceApplication` to add, change or remove, with a diff against the current ones); the owner applies it to the catalog and seals it (`Seal-Package`, with a baseline), then runs `LINKS_PAGES` | Keeps one source of truth; needs a small catalog-change function in the tools |
| B | The application keeps its own override file outside the catalog | A second source of truth, the risk the architecture removed (R-001); not recommended |
| C | No engine: the owner edits the 12 rows with the catalog edit and seal flow | Simplest; no preview of the effect |

[PROPOSED] Option A, with a read-only matrix of effective visibility (default, profile, override) for all 840 combinations, computed by the same function that `LINKS_PAGES` uses so that the two never disagree.

## 7. Preview and apply

Preview: the effective matrix and the change proposal, with the pages that would change. There is no apply that changes the catalog; "apply" produces the proposal file (a text file of rows, no database) and checks it against the catalog rules (instance exists and is individual, application enabled and published).

## 8. Idempotency

The proposal contains only rows that differ from the current state; repeating it with nothing to change gives an empty proposal.

## 9. Failures

An invalid combination is an error in the proposal and is not written to it; the rest is reported. [PROPOSED] The tool reports all errors, not only the first.

## 10. Backup and restore

The proposal is the audit trail; the previous state is the baseline catalog the seal tool already compares against (risk R-047).

## 11. Secret risks

None. The values are application codes and flags.

## 12. What does not port as it is

The console menus (reading numbers and ranges from the keyboard) become browser selection. The store procedure, the central write and the SQL context go.

## 13. Test plan and open questions

- Runner: effective-visibility fixtures shared with `LINKS_PAGES` (default, profile and override layers; an all-environments instance); proposal generation, empty proposal, each invalid case, the catalog file unchanged by the engine, a proposal applied with the seal tool and the resulting page set.
- [V] None needed beyond the pilot pages.
1. [PENDING] Which option (A recommended). A needs a catalog-change function in the tools (a separate PR).
2. [PENDING] Whether per-instance visibility changes are needed in V1 at all: only 1 of 70 instances has an override today. Recommendation: provide the read-only effective matrix first and the proposal generator second.
3. [PENDING] Who may change visibility and whether a second reader is required (R-047).

## Host contract

- Engine class: `MUTATING`.
- Classification rule: an engine is `READ_ONLY` only when every converted `ops_Action` row that uses it has `ModePolicy = NONE`; if any such action has another mode policy, the engine is `MUTATING`.
- Third-party evidence (reviewer, 2026-10-08; not independently verified in this change): `SELECT ActionCode, EngineCode, ModePolicy, IsEnabled FROM ops_Action WHERE EngineCode = 'LINKS_VISIBILITY' ORDER BY ActionCode;` returned exactly `LINKS_VISIBILITY | LINKS_VISIBILITY | PREVIEW_APPLY | 1` in each of the six converted catalogs from the 29516382-byte snapshot (`BR_DEMO`, `ES_DEMO`, `PRESALES`, `PT_DEMO`, `SANDBOX_HUB`, `TENDERS`). This matches the raw snapshot SQL row checked separately.
- [PENDING] The specification above and the owner decision of 2026-10-06 describe a read-only matrix/proposal flow, but the current converted catalog still says `PREVIEW_APPLY`. If the owner wants `READ_ONLY`, the action must be changed to `ModePolicy = NONE` by catalog edit and the catalog must be sealed again. Until then the executable classification is `MUTATING`.
- Intended credential references: none.
- Executable host acceptance today: none.
