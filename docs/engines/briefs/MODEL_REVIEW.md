# MODEL_REVIEW port brief

**Status:** [PROPOSED]
**Task:** T13 / M3.7
**Date:** 2026-10-10

This brief defines the implementation gate for the standalone `MODEL_REVIEW` engine. It is documentation only.

## 1. Sources and evidence boundary

[CONFIRMED] Checked now against `main`:

- `docs/engines/MODEL_REVIEW.md` documents source-era `Invoke-ModelReview.ps1`, action `MODEL_REVIEW` and the twelve enabled `ops.ReviewDefinition` review codes.
- The source-era review definitions carry executable SQL `CommandText`; repository rules prohibit executing code/text stored in the catalog.
- `DEPLOYMENT_PREFLIGHT` already implements local review functions, but its current coverage is explicitly incomplete: 31 of 66 original issue-code names and semantic parity work E0h remains. `MODEL_REVIEW` must not present those current functions as a complete twelve-review implementation until parity/coverage gates close.

[NOT VERIFIED] This brief did not compare all twelve reviews against a real pilot catalog. The D14/E0h evidence and the missing-code work remain the authority for parity.

## 2. Purpose and class

[CONFIRMED] `MODEL_REVIEW` is `READ_ONLY`, mode `NONE`, and has no credential references. It runs the model reviews as a standalone diagnostic and reports their findings without changing managed targets.

[CONFIRMED] Review findings themselves do not make the source-era engine execution fail. The run fails when a review cannot execute or when the engine cannot establish a trustworthy catalog/review set.

## 3. Review registry

[CONFIRMED] The twelve review codes are:

1. `MANAGEMENT_MODEL`
2. `APPLICATION_CATALOG`
3. `MANAGED_ASSETS`
4. `REPAIR_MODEL`
5. `IIS_MODEL`
6. `EXTENDED_APPLICATIONS`
7. `WINDOWS_SERVICES`
8. `WEB_ACCESS`
9. `LINKS_MODEL`
10. `LINKS_PRESENTATION`
11. `PULSE_MODEL`
12. `OPERATIONS_FRAMEWORK`

[PROPOSED] Catalog review-definition rows are an allowlisted registry/order/enablement input only. `CommandText` is ignored and never parsed/evaluated. The executable implementation is local, versioned source code identified by exact review code.

An enabled unknown review code is a contract/model error; do not execute catalog text or silently skip it.

## 4. Shared implementation with preflight

[PROPOSED] One local review library is called by both `MODEL_REVIEW` and `DEPLOYMENT_PREFLIGHT`. Do not fork/copy review predicates into two engines.

The shared library contract includes:

- exact code/predicate/severity behavior for each original finding;
- approved architectural deviations explicitly tagged/tested;
- deterministic result ordering;
- instance filter semantics;
- only presence checks for credentials where the review requires them, with no value access/output beyond the host-provided minimum.

[PENDING] Current preflight review code cannot be called “the complete shared library” until E0h parity and E0b–E0g missing-code work close. Until then a MODEL_REVIEW executable slice must carry the same explicit incomplete-coverage notice or wait.

## 5. Credential boundary

The host contract for standalone `MODEL_REVIEW` currently says no credential references. Some model predicates historically reason about password presence for service/Web Access models.

[PROPOSED] Preserve the no-secret host contract by separating **catalog/model validity** from **credential-package presence** unless an owner-approved contract says the standalone review must consume credential-presence metadata. `DEPLOYMENT_PREFLIGHT`, which already has credential families, may perform the package-dependent readiness checks.

[PENDING] The reviewer must classify each original credential-related finding: pure catalog predicate, credential-package readiness predicate, or architectural replacement. Do not give `MODEL_REVIEW` broad secrets simply because preflight has them.

## 6. Execution semantics

1. Verify package/catalog/machine identity before reviews.
2. Read enabled review registry and require a non-empty, known set.
3. Resolve all enabled local instances or the exact enabled requested instance.
4. Execute each local review independently.
5. A review implementation exception becomes a structured `REVIEW_EXECUTION_FAILED`-style engine error for that review; continue other reviews where trustworthy.
6. Sort findings deterministically by review/severity/instance/object/code.
7. Engine `succeeded` means the review machinery completed, not “there were zero model findings”.

[PROPOSED] Summary separates `reviewFailureCount` conceptually from issue severity counts, while remaining compatible with the shared engine-result schema.

## 7. Findings and result rows

[PROPOSED] One result row per model finding. Operation type identifies the review/area; object begins with the issue code under the current result-row contract; status carries original severity (`ERROR`, `WARNING`, `INFO`).

Review findings are diagnostic data. An `ERROR` finding can be a blocking preflight condition while standalone `MODEL_REVIEW` execution still succeeds because the review executed correctly. UI/orchestrator must not infer engine-execution failure solely from finding severity.

[PENDING] This differs from the current generic schema validation rule that equates `errorCount > 0` with `succeeded = false`; the standalone engine needs either a documented summary mapping or a contract refinement before code. Do not hide this semantic conflict.

## 8. Catalog provenance information

[PROPOSED] Add informational rows for catalog build/provenance and verified-package state where available, without turning age into an invented hard limit. This makes stale-catalog risk visible to an operator.

No network refresh or central database lookup is allowed; provenance is from the verified local package/catalog.

## 9. Side effects, reports and backup

Managed side effects: none. Optional text/structured report files are ordinary output artifacts under the approved log/report root.

Backup/restore: not applicable.

No source-era report folder under mutable deployment roots is required; runtime logging/report conventions apply.

## 10. Secret safety

No secret value may be requested or emitted under the current host contract. Findings may identify instance/account/rule codes only where the original predicate requires non-secret identifiers.

A marker-secret test remains useful at the integration level: place marker credentials in the package available to neighboring/preflight tests and prove standalone MODEL_REVIEW outputs never contain them.

## 11. Required tests

The code PR must cover:

- exact twelve-code registry and unknown enabled review refusal;
- prove `CommandText` is ignored even when it contains executable/malicious text;
- empty enabled review list failure;
- every original issue code/predicate/severity fixture after parity work closes;
- approved `ARQUITECTURAL` deviations versus corrected `DIVERGENCIA` cases;
- all-enabled and exact-instance filtering;
- a throwing local review does not stop independent reviews and makes execution failure visible;
- model `ERROR` findings do not get confused with review-engine execution failure;
- deterministic ordering;
- foreign-machine/unverified catalog refusal;
- incomplete-coverage marker if implementation lands before 66/66 + parity;
- no credential value/marker in results/reports;
- catalog provenance information rows without invented age threshold.

[V] Pilot output compared with the old standalone engine where available, with differences classified rather than normalized away.

## 12. Open questions

1. [PENDING] Exact engine-result representation for “reviews executed successfully but model contains ERROR findings” versus the generic `succeeded/errorCount` invariant.
2. [PENDING] Whether standalone MODEL_REVIEW consumes any credential-presence metadata; current host contract says none.
3. [PENDING] Land the executable only after E0h/E0b–E0g closes, or land an explicitly incomplete slice with the same coverage marker.
4. [PROPOSED] Keep standalone model-check action rather than aliasing it to preflight, while both share one local review library.

## 13. Entry gate for the code PR

The code PR may start when:

- shared-review coverage/parity state is explicit and cannot be mistaken for complete;
- all original finding predicates/severities used by the slice are test-backed evidence;
- `CommandText` execution is mechanically impossible;
- standalone credential boundary is decided;
- result semantics distinguish model findings from engine execution failure;
- no managed write or backup requirement exists.
