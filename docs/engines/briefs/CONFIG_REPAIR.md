# CONFIG_REPAIR port brief

**Status:** [PROPOSED]
**Task:** T1 / M3.2
**Date:** 2026-10-10

This brief is the entry document for the `CONFIG_REPAIR` port. It narrows the existing specification into the evidence, invariants and review gates that the implementation PR must satisfy. It is documentation only.

## 1. Sources and evidence boundary

[CONFIRMED] Checked now against `main`:

- `docs/engines/CONFIG_REPAIR.md` describes the source-era `Invoke-ConfigRepair.ps1`, the `CONFIG_REPAIR` action, `cfg.GetRepairPlan` and `cfg.ReviewRepairModel`.
- `tests/Fixtures/carried-schema.json` carries the catalog shape used by this engine. In particular it confirms `cfg.ConfigFile`, `cfg.ConfigFileRepairPolicy`, `cfg.ConfigRule` and `cfg.Application`, including the repair fields `RepairAction`, `RepairValueType`, `RepairGroup`, `RepairOrder`, `CreateIfMissing`, `MissingParentSelector` and `MissingNodeTemplate`.
- `docs/decisions-log.md` records that the retired `V8_KEYCLOAK_CONFIG` behavior is absorbed by the `CONFIG_REPAIR` rule `KEYCLOAK_DB_URL`.
- The 2026-10-09 owner decision makes `RULE_SECRET` references exact. `RULE_SECRET.*` is not an admissible family contract; an engine must declare the exact `RULE_SECRET.<RuleCode>` references it needs.
- Rules 6 and 7 of `docs/handoff/preflight-port-gap.md` on PR #69 are the cross-instance and path-containment rules to carry into engine work where applicable.

[NOT VERIFIED] The original `Invoke-ConfigRepair.ps1`, `cfg.GetRepairPlan` and `cfg.ReviewRepairModel` texts were not re-extracted or re-executed for this brief. Counts, retry behavior and source-era semantics below that are tagged `[CONFIRMED]` come from the existing specification, whose source reading predates this brief. The implementation reviewer must compare them with the approved evidence before code is written.

## 2. Purpose and scope

[CONFIRMED] `CONFIG_REPAIR` is a `MUTATING` engine. Its job is to compare managed JSON, XML and text configuration files with catalog rules, show the changes in preview, apply only the confirmed plan, and verify the same plan after writing.

[CONFIRMED] The action supports all enabled instances or one selected instance, optional rule and repair-group filters, and is step 20 of `FULL_DEPLOYMENT`, where an error blocks later steps.

[PROPOSED] The portable engine keeps this boundary: configuration-file repair only. It does not restart services, pools or sites and does not write the catalog.

## 3. Catalog inputs confirmed by carried schema

| Table | Columns used by the port |
|---|---|
| `cfg.ConfigFile` | `FileID`, `ApplicationCode`, `RelativePath`, `FileFormat`, `IsRequired`, `IsEnabled` |
| `cfg.ConfigRule` | `RuleID`, `FileID`, `CountryCode`, `RuleCode`, `Category`, `SelectorType`, `Selector`, `ExpectedTemplate`, `ValidationType`, `IsRequired`, `AllowEncrypted`, `IsSensitive`, `Severity`, `IsEnabled`, `RepairAction`, `RepairValueType`, `RepairGroup`, `RepairOrder`, `CreateIfMissing`, `MissingParentSelector`, `MissingNodeTemplate` |
| `cfg.ConfigFileRepairPolicy` | `FileID`, `RepairMode`, `ExpectedContentTemplate`, `NormalizeJsonEscapedAmpersand`, `RepairGroup`, `IsEnabled` |
| `cfg.Application` | `ApplicationCode`, `PhysicalPathTemplate`, `IsEnabled` |
| `dbo.ManagedServer` / `dbo.ManagedInstance` | machine and instance data used to resolve the local target and template tokens; `ConfigBackupRoot` is the catalog backup root named by the existing specification |

[CONFIRMED from the existing specification] The reference catalog has 41 managed config files, 417 rules (416 enabled) and eight repair policies. These are evidence numbers, not hard-coded runtime requirements.

## 4. Credentials

[CONFIRMED] Sensitive rule values are resolved from the credential package in memory. The credential identity is the rule code.

[DECIDED 2026-10-09] Every rule secret is exact: `RULE_SECRET.<RuleCode>`. The stale `RULE_SECRET.*` line in the older engine specification must not be copied into the executable host contract.

[PROPOSED] Before implementation, derive the exact required reference list mechanically from enabled sensitive rules whose expected template contains a rule-secret reference. The engine contract then declares those exact references; it never asks the host for an unrestricted `RULE_SECRET.*` family.

No resolved secret value may enter preview rows, logs, reports, fingerprints or exception text. A marker-secret test is mandatory.

## 5. Old behavior, step by step

The current specification records this source-era flow:

1. Resolve the local machine and selected enabled instances; run the repair-model review before building a plan.
2. Select enabled config files and rules, applying instance, rule, repair-group and country filters.
3. Expand catalog templates with instance data and resolve exact secret references only in memory.
4. For `PATCH`, evaluate rule selectors and calculate the would-be file bytes in memory. For `REPLACE`, use the policy content template.
5. Preserve the input encoding: UTF-8 with/without BOM and UTF-16 in either byte order are explicitly called out by the existing spec.
6. Preview without writes. Existing documented statuses are `MATCHED`, `WOULD_UPDATE`, `NOT_DEPLOYED` and `ERROR`.
7. On apply, back up each changed file once, write atomically through a temporary file in the same directory, then verify by rebuilding the plan.
8. A verification pass that still yields a required change or error makes the run fail.
9. Emit structured result rows and the text log without current/expected secret values.

[CONFIRMED from the existing specification] The source-era implementation retried a just-written file up to ten times with a two-second delay. [PROPOSED] Keep bounded retry semantics only after the reviewer confirms the exact source predicate and failure conditions.

## 6. Path and cross-instance rules

[PROPOSED] Every physical path derived from the catalog must obey the containment rule before any probe or write: resolve junctions/symbolic links and require the real path to remain under the approved instance/application root. A denied path becomes an item error; it must not escape as an unstructured crash.

[PROPOSED] Rule evaluation is per selected target, but any invariant that compares instance-derived names or paths across instances must use every enabled instance on the machine and report a conflict on the selected participant, following rule 6 from PR #69. Do not silently reduce a machine-wide uniqueness rule to `SelectedInstances`.

## 7. Side effects and backup

[CONFIRMED] Intended managed side effects are configuration-file writes plus backup/report artifacts. No database write and no service/IIS restart belongs to this engine.

[PROPOSED] APPLY is allowed only for the exact preview fingerprint. Before the first mutation of each file, capture the original bytes and SHA-256 in the run backup manifest. A restore path must verify the restored hash. Backup ACL/retention remains an owner decision; backups can contain real secrets even though normal result/log output cannot.

## 8. Result and failure contract

[PROPOSED] One result row represents one managed file. It names the instance/application/file and a non-secret status; details identify rule codes or failure classes but never values.

The implementation must fail closed for at least:

- unresolved template tokens or exact secret references;
- required file missing;
- unsupported or malformed file format;
- selector/repair operation that cannot perform a required mutation;
- path outside the approved root or inaccessible path;
- backup/write/atomic-replace failure;
- verification that does not converge to the previewed expected state.

Optional absent files may retain the existing documented `NOT_DEPLOYED` behavior only if the source evidence confirms the predicate.

## 9. Original codes and severities

[PENDING] This brief does not invent issue codes for `cfg.ReviewRepairModel`. The exact original review findings and severities must be extracted from the approved source evidence before the code PR. Engine result statuses documented by the existing specification (`MATCHED`, `WOULD_UPDATE`, `NOT_DEPLOYED`, `ERROR`) are not substitutes for original model-review issue codes.

Entry gate: the reviewer attaches or points to the evidence that enumerates every `cfg.ReviewRepairModel` finding and severity, and the tests contain one positive and one negative case per finding.

## 10. Required tests

The code PR must cover at minimum:

- each selector type, validation type and repair value type present in the carried rules;
- `PATCH` and `REPLACE`;
- `CreateIfMissing`, including parent/node-template handling;
- country, instance, rule and group filters;
- supported encodings, BOM handling, XML declaration and CRLF preservation;
- exact `RULE_SECRET.<RuleCode>` authorization and a missing exact secret;
- marker secret absent from result, text log, report, error text and plan fingerprint;
- path containment including a junction/symlink that leaves the approved root;
- preview/apply fingerprint mismatch;
- backup, atomic write, restore and post-restore hash verification;
- idempotency: second run is all matched and performs no managed write;
- bounded retry and terminal failure after its limit;
- post-apply verification failure;
- any cross-instance invariant discovered in the source, with one selected instance conflicting with an enabled unselected instance.

[V] Differential comparison with the old engine and a pilot real application tree remain real-server validations.

## 11. Open questions to close before implementation

1. [PENDING] Exact `cfg.ReviewRepairModel` issue codes, predicates and severities.
2. [PENDING] Exact behavior when a non-`XML_NODES_ALL` selector matches several nodes.
3. [PENDING] Exact source behavior when a selector finds nothing and `CreateIfMissing = 0`.
4. [PENDING] Backup retention and ACL policy for files that can contain secrets.
5. [PENDING] Whether the documented retry count/delay is retained as fixed behavior or represented by an approved policy value.
6. [PENDING] Whether any repaired application needs a restart; if so, keep the restart outside this engine unless an owner decision changes the scope.

## 12. Entry gate for the code PR

The `CONFIG_REPAIR` code PR may start when:

- original review predicates/codes/severities are present as reviewable evidence;
- exact rule-secret references are derived, with no wildcard `RULE_SECRET.*` contract;
- every table/column used by code exists in `tests/Fixtures/carried-schema.json`;
- containment and cross-instance applicability have been classified for every path/name invariant;
- backup/restore behavior and unresolved owner choices are either decided or explicitly excluded from the first executable slice;
- the reviewer has a test matrix mapping each source behavior and issue code to a fixture.
