# LINKS_VISIBILITY port brief

**Status:** [PROPOSED]
**Task:** T14 / M3.8
**Date:** 2026-10-10

This brief defines the implementation gate for `LINKS_VISIBILITY`. It is documentation only.

## 1. Sources and evidence boundary

[CONFIRMED] Checked now against `main`:

- `docs/engines/LINKS_VISIBILITY.md` documents the source-era interactive writer and the owner decision Q9 (2026-10-06): V1 is option A, read-only effective-visibility matrix first; changes are owner catalog edits followed by seal.
- C9 tooling is already implemented: `tools/Apply-CatalogChange.ps1` applies structured `contracts/catalog-change.schema.json` proposals offline with exact base SHA-256, expected-state/PK checks, validation and atomic replacement. It does **not** reseal; sealing remains a separate owner workflow step.
- `LINKS_PAGES` and the instance-directory design define page scope. Visibility overrides apply to individual pages; general-page visibility follows its own source rules.

[NOT VERIFIED] This brief did not apply a proposal to a production catalog or render the resulting real page. Production second-reader/seal workflow remains an owner/process validation.

## 2. Purpose and class

[DECIDED] The portable `LINKS_VISIBILITY` engine does **not** mutate the catalog. Its managed-target behavior is observational: compute and display effective individual-page visibility and optionally produce a structured change proposal outside managed targets.

[PROPOSED] Host class remains `OBSERVATIONAL`. `PREVIEW_APPLY` action semantics are interpreted as:

- preview: matrix/diff only;
- apply-like action: emit validated proposal artifact only.

There is no runtime database/catalog write.

## 3. Visibility inputs and precedence

[CONFIRMED] The visibility model uses:

- enabled individual-page instances (`LinksIncludeAllInstances = 0`);
- enabled published applications and `LinksDefaultForIndividualPages`;
- explicit `cfg.LinksPageInstanceApplication` overrides;
- profile assignment/application visibility tables.

[PROPOSED] One shared pure visibility function is used by `LINKS_VISIBILITY` and `LINKS_PAGES`. Its precedence/order is fixed from source evidence and tested once; the two engines must never contain independent implementations that can disagree.

General-page instances are not valid targets for per-instance visibility override; source procedure rejected them and portable proposal validation must do the same.

## 4. Effective matrix

[PROPOSED] Compute every relevant individual-instance × published-application combination. Each matrix cell includes non-secret identifiers and provenance of the effective state:

- effective `ENABLED`/`DISABLED`;
- source layer (`INSTANCE_OVERRIDE`, `PROFILE`, `APPLICATION_DEFAULT` or exact approved vocabulary);
- current explicit override state if one exists;
- whether a change of explicit override would alter effective visibility.

Deterministic ordering: instance then application sort/code. The reference snapshot count (70 × 12 = 840) is evidence, not a runtime invariant.

## 5. Proposal semantics

[PROPOSED] A requested visibility change is translated to the **minimal explicit override delta** required by the approved model. Proposal contains only rows whose stored override state must add/change/remove; repeating the same desired matrix yields an empty proposal.

Each proposed operation must include:

- catalog/table identity allowed by `contracts/catalog-change.schema.json`;
- primary-key values for the instance/application pair;
- exact expected current state (including expected absence for insert);
- desired non-secret enabled/disabled state;
- base catalog SHA-256/provenance required by C9.

No raw SQL, arbitrary table/column name or free-form mutation is emitted.

[PENDING] Exact UX choice of “remove override to inherit” versus “store explicit value equal to inherited state” must follow source/owner policy. Recommendation: prefer minimal override/inheritance where semantics are equivalent, but do not change source behavior without review.

## 6. Owner edit/seal workflow

[CONFIRMED] Runtime engine output alone does not publish a visibility change. The owner workflow is:

1. generate/review proposal;
2. second-reader review for production catalog changes as required by C6;
3. apply proposal offline with C9 `Apply-CatalogChange.ps1` against the exact base catalog;
4. validate the changed catalog;
5. seal the package through the normal seal flow;
6. deploy/use the newly verified catalog;
7. run `LINKS_PAGES` to materialize the page files.

`Apply-CatalogChange.ps1` does not update `package-manifest.json`; do not describe apply-tool success alone as a sealed/deployable package.

## 7. Catalog immutability and stale proposals

[PROPOSED] Proposal generation fingerprints the exact catalog. Any catalog change after proposal generation invalidates the proposal; C9 expected-state/base-hash checks must fail rather than rebase automatically.

The runtime never “fixes” a stale proposal by reading another machine or editing its local catalog.

## 8. Validation and invalid cases

Proposal generation reports all invalid selections instead of stopping after the first:

- unknown/disabled instance;
- instance is a general-page instance;
- unknown/disabled/not-published application;
- invalid desired state;
- inconsistent profile/override model that prevents deterministic effective state.

Invalid combinations are never emitted as mutation operations.

## 9. Side effects, secrets and backup

Engine side effects: optional proposal/report files only. No managed-target/catalog write, no credentials and no network dependency.

Backup/restore at runtime: not applicable. C9 creates/retains the catalog baseline/change evidence according to its tool contract; rollback is owner catalog restore + reseal, not an engine operation.

## 10. Result contract

[PROPOSED] Result contains matrix/diff/proposal summary rows without treating “desired visibility differs” as an engine error. Engine failure means matrix/proposal could not be computed/validated, not that changes are proposed.

Proposal artifact identity/hash is returned as metadata; its contents are non-secret application/instance codes and booleans.

## 11. Required tests

Runner tests must cover:

- default-only visibility;
- profile visibility;
- explicit instance override and exact precedence;
- same shared pure visibility function used by LINKS_PAGES fixtures;
- individual page accepted; general-page instance rejected for override;
- disabled/unpublished/unknown application rejection;
- minimal add/change/remove proposal behavior;
- already-effective desired state -> empty proposal;
- deterministic  matrix/proposal ordering;
- proposal conforms to `contracts/catalog-change.schema.json` and contains no raw SQL/arbitrary table mutation;
- base catalog SHA mismatch and expected-state mismatch rejected by C9;
- catalog file unchanged by engine execution;
- apply C9 proposal to temporary catalog, validate it, then show LINKS_PAGES fixture changes as expected;
- stale proposal after independent catalog edit fails closed;
- no credential-package access.

[V] Pilot browser/pages only; engine itself has no real-server managed write.

## 12. Open questions

1. [PENDING] Exact browser UX/proposal-file presentation; implementation detail, not a new architecture decision.
2. [PENDING] Whether explicit overrides equal to inherited state should be removed or retained; source-equivalence decision.
3. [PROPOSED] Keep proposal generation in this observational engine while C9 remains the only offline mutation tool.

## 13. Entry gate for the code PR

The code PR may start when:

- visibility precedence is source-evidenced and shared with LINKS_PAGES;
- proposal operations map only to C9-approved structured catalog changes;
- base-hash/expected-state stale protection is end-to-end tested;
- no runtime catalog-write path exists;
- production edit/reseal remains an owner workflow with second-reader gate.
